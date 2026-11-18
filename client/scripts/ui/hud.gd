extends CanvasLayer
## Connects the HUD widgets to the player. Only shows state, decides nothing:
## requests from the inventory are passed on to the player.

const ACTION_INVENTORY := "inventory"
const ACTION_CHARACTER := "character"
const ACTION_TALK := "talk"
const NpcDialog := preload("res://scripts/ui/npc_dialog.gd")
const ShopPanel := preload("res://scripts/ui/shop_panel.gd")
const StoragePanel := preload("res://scripts/ui/storage_panel.gd")
const GameData := preload("res://scripts/data/game_data.gd")
## Player methods the town windows (dialog, shop, storage) may ask for.
const TOWN_ACTIONS := [
	"buy_item",
	"sell_from_bag",
	"store_item",
	"take_stored",
	"heal_at_npc",
	"travel",
	"accept_quest",
	"turn_in_quest",
]
const QuestLog := preload("res://scripts/player/quest_log.gd")
const Minimap := preload("res://scripts/ui/minimap.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const PlayerStats := preload("res://scripts/player/player_stats.gd")
const DEATH_RED := Color(1.0, 0.45, 0.5)
const BOSS_BAR_WIDTH := 520.0
## The boss bar shows while a boss is this close to the warrior.
const BOSS_VIEW := 1000.0
## The round touch buttons on the right (ATK, SPIN, POT) are in this group.
const ACTION_BUTTONS_GROUP := "action_buttons"
## Player methods the inventory may ask for.
const ITEM_ACTIONS := [
	"equip_from_bag",
	"unequip",
	"use_from_bag",
	"drop_from_bag",
	"drop_equipped",
	"upgrade_bag_item",
	"upgrade_equipped",
	"cycle_auto_potion",
]
## Player methods the character window may ask for.
const CHARACTER_ACTIONS := ["add_stat_point", "reset_stats", "choose_title"]

var _player: Node = null
var _banner: Label
var _dialog
var _shop
var _storage
var _talk_button: Button
var _tracker: Label
var _minimap: Control
var _boss_bar: Control
var _boss_name: Label
var _boss_fill: ColorRect
## The townsperson close enough to talk to, or null.
var _nearby_npc: Node = null
var _death_screen: Control
var _death_count: Label
var _death_left: float = 0.0

@onready var _panel = $PlayerPanel
@onready var _message: Label = $Message
@onready var _bag_button: Button = $BagButton
@onready var _inventory = $Inventory
@onready var _stats_button: Button = $StatsButton
@onready var _character = $Character
@onready var _log = $MessageLog


func _ready() -> void:
	_message.hide()
	add_to_group("hud")
	_build_banner()
	_build_death_screen()
	_build_town_windows()
	_build_boss_bar()
	_style_round_button(_bag_button)
	_style_round_button(_stats_button)
	_stats_button.add_theme_font_size_override("font_size", 18)
	_bag_button.pressed.connect(toggle_inventory)
	_stats_button.pressed.connect(toggle_character)
	_inventory.connect("close_requested", toggle_inventory)
	_inventory.connect("item_action", _on_item_action)
	_character.connect("close_requested", toggle_character)
	_character.connect("request", _on_character_request)
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("Hud: no node in group 'player'")
		return
	_player.connect("hp_changed", Callable(_panel, "set_hp"))
	_player.connect("stamina_changed", Callable(_panel, "set_stamina"))
	_player.connect("stats_changed", _refresh_progress)
	_player.connect("died", _on_player_died)
	_player.connect("respawned", _on_player_respawned)
	_player.connect("message", Callable(_log, "add_message"))
	_panel.set_hp(_player.get("hp"), _player.get("max_hp"))
	_panel.set_stamina(_player.get("stamina"), _player.get("max_stamina"))
	_refresh_progress()


## Read in the physics step, the same way the player reads its actions.
func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_INVENTORY):
		toggle_inventory()
	if Input.is_action_just_pressed(ACTION_CHARACTER):
		toggle_character()
	if Input.is_action_just_pressed(ACTION_TALK) and _talk_button.visible:
		talk()
	if _player != null:
		_update_action_buttons()
		_update_boss_bar()


func toggle_inventory() -> void:
	_show_window(_inventory, not _inventory.visible)


func toggle_character() -> void:
	_show_window(_character, not _character.visible)


## Opens one window (inventory or character) and closes the other. While a
## window is open the round action buttons are hidden, because it covers them.
func _show_window(window: Control, open: bool) -> void:
	for each in _windows():
		each.visible = open and each == window
	_refresh_windows()
	get_tree().call_group(ACTION_BUTTONS_GROUP, "set_visible", not open)
	_update_talk_button()


func _windows() -> Array:
	return [_inventory, _character, _dialog, _shop, _storage]


func _close_windows() -> void:
	_show_window(null, false)


## A townsperson's talk area was entered (npc.gd).
func set_nearby_npc(npc: Node) -> void:
	_nearby_npc = npc
	_update_talk_button()


func clear_nearby_npc(npc: Node) -> void:
	if _nearby_npc == npc:
		_nearby_npc = null
		_update_talk_button()


## Opens the dialog of the townsperson close by.
func talk() -> void:
	if _nearby_npc == null or not is_instance_valid(_nearby_npc):
		return
	var npc_id: String = _nearby_npc.get("npc_id")
	_player.call("talked_to", npc_id)
	_dialog.open(npc_id, _quest_rows(npc_id))
	_show_window(_dialog, true)


## Dialog rows for the quests this townsperson gives that can be taken or handed in.
func _quest_rows(npc_id: String) -> Array:
	var rows: Array = []
	var stats = _player.get("stats")
	for quest_id in QuestLog.given_by(npc_id):
		var quest: Dictionary = QuestLog.list[quest_id]
		match stats.quests.state(quest_id, stats, QuestLog.today()):
			"ready":
				rows.append(["Complete: %s" % quest["name"], "turn_in_quest", quest_id])
			"available":
				var kind: String = "Daily" if quest.get("daily", false) else "Quest"
				rows.append(["%s: %s" % [kind, quest["name"]], "offer_quest", quest_id])
	return rows

func _update_talk_button() -> void:
	var any_open: bool = _windows().any(func(each: Control) -> bool: return each.visible)
	_tracker.visible = not any_open
	_minimap.visible = not any_open
	_talk_button.visible = (
		_nearby_npc != null
		and is_instance_valid(_nearby_npc)
		and not any_open
		and _player != null
		and not _player.get("is_dead")
	)


func _on_town_request(method: String, argument: Variant) -> void:
	if _player == null:
		return
	match method:
		"open_shop":
			_shop.open(argument)
			_show_window(_shop, true)
		"open_storage":
			_show_window(_storage, true)
		"offer_quest":
			var quest: Dictionary = QuestLog.list[argument]
			_dialog.open(_dialog.npc_id, [["Accept", "accept_quest", argument]], quest["text"], false)
		"turn_in_quest":
			_player.call("turn_in_quest", argument)
			if not _player.get("stats").quests.active.has(argument):
				_dialog.open(_dialog.npc_id, [], QuestLog.list[argument]["done_text"], false)
		"buy_item":
			var stock: Array = GameData.table("npcs").get(_shop.npc_id, {}).get("shop", [])
			if argument in stock:
				_player.call("buy_item", argument)
		_:
			if method in TOWN_ACTIONS:
				_player.call(method, argument)
				if method in ["travel", "heal_at_npc", "accept_quest"]:
					_close_windows()


func _refresh_windows() -> void:
	if _player == null:
		return
	var stats = _player.get("stats")
	if _inventory.visible:
		_inventory.refresh(stats, _player.get("look_texture"))
	if _character.visible:
		_character.refresh(stats)
	if _shop.visible:
		_shop.refresh(stats)
	if _storage.visible:
		_storage.refresh(stats)


func _on_item_action(method: String, argument: Variant) -> void:
	if _player != null and method in ITEM_ACTIONS:
		_player.call(method, argument)


func _on_character_request(method: String, argument: Variant) -> void:
	if _player != null and method in CHARACTER_ACTIONS:
		_player.call(method, argument)


## POT shows how many potions are left. Skill buttons show their cooldown, fade
## when they would do nothing, and show what opens them ("Lv3", "BOOK").
func _update_action_buttons() -> void:
	var stats = _player.get("stats")
	for button in get_tree().get_nodes_in_group(ACTION_BUTTONS_GROUP):
		var action: String = button.get("action")
		if action == "use_potion":
			button.set("badge", str(stats.potions))
			button.set("dimmed", stats.potions == 0)
			continue
		button.set("cooldown", _player.call("cooldown_left", action))
		var skill_id: String = _player.call("skill_for_action", action)
		if skill_id == "":
			continue
		button.set("badge", _player.call("skill_lock", skill_id))
		button.set("dimmed", not _player.call("can_use", skill_id))


func _refresh_progress() -> void:
	var stats = _player.get("stats")
	_panel.set_progress(stats.level, stats.xp, stats.xp_to_next(), stats.gold, stats.potions)
	var free: int = stats.free_points()
	_stats_button.text = "STATS" if free == 0 else "STATS\n+%d" % free
	_refresh_windows()
	_refresh_tracker(stats)


## Active quests at the top right: "Slime Cleanup 3/8".
func _refresh_tracker(stats) -> void:
	var lines := PackedStringArray()
	for quest_id in stats.quests.active:
		var quest: Dictionary = QuestLog.list[quest_id]
		var counted: int = mini(stats.quests.progress(quest_id, stats), stats.quests.goal_count(quest_id))
		var needed: int = stats.quests.goal_count(quest_id)
		var line: String = "%s  %d/%d" % [quest["name"], counted, needed]
		if quest["goal"]["type"] == "talk":
			var who: String = GameData.table("npcs")[quest["goal"]["npc"]]["name"]
			line = "%s: talk to %s" % [quest["name"], who]
		if counted >= needed:
			line += "  (done)"
		lines.append(line)
	_tracker.text = "\n".join(lines)


func _style_round_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.1, 0.06, 0.1, 0.55 if state == "normal" else 0.8)
		box.border_color = Color(0.85, 0.68, 0.32)
		box.set_border_width_all(2)
		box.set_corner_radius_all(18)
		box.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, box)


## The map's name for a moment when the warrior arrives.
func show_banner(title: String, subtitle: String = "") -> void:
	# a new map: whoever was close by is gone, and so are their windows
	_nearby_npc = null
	for each in [_dialog, _shop, _storage]:
		if each.visible:
			_close_windows()
	_update_talk_button()
	_banner.text = title if subtitle == "" else "%s\n%s" % [title, subtitle]
	_banner.modulate.a = 0.0
	var fade: Tween = create_tween()
	fade.tween_property(_banner, "modulate:a", 1.0, 0.4)
	fade.tween_interval(1.6)
	fade.tween_property(_banner, "modulate:a", 0.0, 0.6)


func _process(delta: float) -> void:
	if _death_screen.visible:
		_death_left = maxf(0.0, _death_left - delta)
		_death_count.text = "Back on your feet in %d..." % ceili(_death_left)


## K5: a real death screen with a countdown, and a button to get up in town.
func _on_player_died() -> void:
	_death_left = float(PlayerStats.rules["respawn_seconds"])
	_close_windows()
	_death_screen.show()
	_update_talk_button()


func _on_player_respawned() -> void:
	_death_screen.hide()
	_message.hide()
	_update_talk_button()


func _on_town_pressed() -> void:
	get_tree().call_group("game", "return_to_town")


func _build_town_windows() -> void:
	_dialog = NpcDialog.new()
	_dialog.name = "NpcDialog"
	_place(_dialog, Control.PRESET_CENTER_BOTTOM, Rect2(-360, -340, 720, 320))
	_shop = ShopPanel.new()
	_shop.name = "Shop"
	_place(_shop, Control.PRESET_TOP_RIGHT, Rect2(-352, 100, 336, 600))
	_storage = StoragePanel.new()
	_storage.name = "Storage"
	_place(_storage, Control.PRESET_CENTER, Rect2(-370, -290, 740, 580))
	for window in [_dialog, _shop, _storage]:
		window.hide()
		window.connect("close_requested", _close_windows)
		window.connect("request", _on_town_request)
		add_child(window)
	_talk_button = UiStyle.button("TALK", Color(0.25, 0.42, 0.55), Vector2(180, 64))
	_talk_button.name = "TalkButton"
	_talk_button.add_theme_font_size_override("font_size", 24)
	_place(_talk_button, Control.PRESET_CENTER_BOTTOM, Rect2(-90, -150, 180, 64))
	_talk_button.pressed.connect(talk)
	_talk_button.hide()
	add_child(_talk_button)
	_tracker = UiStyle.label("", 15, Color(0.6, 0.9, 1.0))
	_tracker.name = "QuestTracker"
	_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tracker.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.12))
	_tracker.add_theme_constant_override("outline_size", 5)
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_tracker, Control.PRESET_TOP_RIGHT, Rect2(-460, 228, 444, 120))
	add_child(_tracker)
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_place(_minimap, Control.PRESET_TOP_RIGHT, Rect2(-216, 100, 200, 120))
	add_child(_minimap)


## Anchors a control to a corner or side, offset by rect (position and size).
static func _place(control: Control, preset: int, rect: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


## C9: a wide health bar at the top while a boss is near.
func _update_boss_bar() -> void:
	var shown: Node2D = null
	for boss in get_tree().get_nodes_in_group("bosses"):
		var near: bool = boss.global_position.distance_to(_player.global_position) < BOSS_VIEW
		if not boss.get("is_dead") and near:
			shown = boss
	_boss_bar.visible = shown != null
	if shown != null:
		var max_hp: int = maxi(1, int(shown.get("max_hp")))
		var hp: int = int(shown.get("hp"))
		_boss_name.text = "%s   %d / %d" % [shown.get("display_name"), hp, max_hp]
		_boss_fill.size.x = (BOSS_BAR_WIDTH - 4.0) * clampf(float(hp) / max_hp, 0.0, 1.0)


func _build_boss_bar() -> void:
	_boss_bar = Control.new()
	_boss_bar.name = "BossBar"
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_boss_bar, Control.PRESET_CENTER_TOP, Rect2(-BOSS_BAR_WIDTH / 2.0, 72, BOSS_BAR_WIDTH, 46))
	_boss_name = UiStyle.label("", 18, Color(1.0, 0.85, 0.5))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.size = Vector2(BOSS_BAR_WIDTH, 22)
	_boss_name.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.1))
	_boss_name.add_theme_constant_override("outline_size", 6)
	_boss_bar.add_child(_boss_name)
	var back := ColorRect.new()
	back.color = Color(0.12, 0.05, 0.08, 0.85)
	back.position = Vector2(0, 24)
	back.size = Vector2(BOSS_BAR_WIDTH, 20)
	_boss_bar.add_child(back)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(0.86, 0.22, 0.26)
	_boss_fill.position = Vector2(2, 26)
	_boss_fill.size = Vector2(BOSS_BAR_WIDTH - 4.0, 16)
	_boss_bar.add_child(_boss_fill)
	_boss_bar.hide()
	add_child(_boss_bar)


func _build_banner() -> void:
	_banner = Label.new()
	_banner.name = "MapBanner"
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -320.0
	_banner.offset_right = 320.0
	_banner.offset_top = 120.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.add_theme_color_override("font_color", UiStyle.GOLD_TEXT)
	_banner.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.12))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	add_child(_banner)


func _build_death_screen() -> void:
	_death_screen = ColorRect.new()
	_death_screen.name = "DeathScreen"
	_death_screen.color = Color(0.08, 0.02, 0.06, 0.62)
	_death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_death_screen.hide()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	var title := UiStyle.label("YOU FELL", 60, DEATH_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_death_count = UiStyle.label("", 22, Color.WHITE)
	_death_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_death_count)
	var town := UiStyle.button("RETURN TO TOWN", Color(0.3, 0.22, 0.42), Vector2(300, 56))
	town.name = "TownButton"
	town.pressed.connect(_on_town_pressed)
	column.add_child(town)
	center.add_child(column)
	_death_screen.add_child(center)
	add_child(_death_screen)
