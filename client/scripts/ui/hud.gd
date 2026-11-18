extends CanvasLayer
## Connects the HUD widgets to the player. Only shows state, decides nothing:
## requests from the inventory are passed on to the player.

const ACTION_INVENTORY := "inventory"
const ACTION_CHARACTER := "character"
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const PlayerStats := preload("res://scripts/player/player_stats.gd")
const DEATH_RED := Color(1.0, 0.45, 0.5)
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
	_build_banner()
	_build_death_screen()
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
	if _player != null:
		_update_action_buttons()


func toggle_inventory() -> void:
	_show_window(_inventory, not _inventory.visible)


func toggle_character() -> void:
	_show_window(_character, not _character.visible)


## Opens one window (inventory or character) and closes the other. While a
## window is open the round action buttons are hidden, because it covers them.
func _show_window(window: Control, open: bool) -> void:
	_inventory.visible = open and window == _inventory
	_character.visible = open and window == _character
	_refresh_windows()
	get_tree().call_group(ACTION_BUTTONS_GROUP, "set_visible", not open)


func _refresh_windows() -> void:
	if _player == null:
		return
	var stats = _player.get("stats")
	if _inventory.visible:
		_inventory.refresh(stats, _player.get("look_texture"))
	if _character.visible:
		_character.refresh(stats)


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
	_death_screen.show()


func _on_player_respawned() -> void:
	_death_screen.hide()
	_message.hide()


func _on_town_pressed() -> void:
	get_tree().call_group("game", "return_to_town")


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
