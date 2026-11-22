extends PanelContainer
## Hidden admin / debug panel. Reached by tapping the "MENU" heading five
## times. It lives inside the game menu and uses the same button helpers.
##
## Features
## --------
## • Set level (1–50)        • Give gold (1 000 / 10 000 / 100 000)
## • Teleport to any map     • God mode (invincible)
## • Kill all on-screen      • Give potions (x50)
## • Show FPS overlay        • Full heal
## • Reset tutorial          • Clear bag

signal back_pressed

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const ItemDb := preload("res://scripts/items/item_db.gd")
const Leveling := preload("res://scripts/player/leveling.gd")
const GREEN := Color(0.22, 0.48, 0.3)
const BLUE := Color(0.22, 0.32, 0.55)
const RED := Color(0.6, 0.18, 0.18)
const BROWN := Color(0.5, 0.3, 0.18)
const PURPLE := Color(0.42, 0.22, 0.55)
const WIDTH := 500.0

## Other scripts check this to skip damage.
static var god_mode: bool = false
var _fps_label: Label = null
var _god_button: Button = null
var _level_label: Label = null
var _scroll: ScrollContainer = null


func _ready() -> void:
	name = "AdminPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	custom_minimum_size = Vector2(WIDTH, 0.0)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = -20.0
	offset_bottom = 20.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 500)
	add_child(_scroll)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(stack)

	var title := UiStyle.label("ADMIN PANEL", 26, Color(1.0, 0.3, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	# -- Level ---------------------------------------------------------------
	var level_section := UiStyle.label("LEVEL", 20, UiStyle.GOLD_TEXT)
	level_section.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(level_section)

	_level_label = UiStyle.label("Current: 1", 18, Color.WHITE)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_level_label)

	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for lv in [1, 5, 10, 15, 20, 25, 30, 40, 50]:
		var b := _small_button("Lv%d" % lv, BLUE, _set_level.bind(lv))
		level_row.add_child(b)
	stack.add_child(level_row)

	# -- Gold ----------------------------------------------------------------
	var gold_section := UiStyle.label("GOLD", 20, UiStyle.GOLD_TEXT)
	gold_section.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(gold_section)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 8)
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_child(_small_button("+1K", GREEN, _add_gold.bind(1000)))
	gold_row.add_child(_small_button("+10K", GREEN, _add_gold.bind(10000)))
	gold_row.add_child(_small_button("+100K", GREEN, _add_gold.bind(100000)))
	stack.add_child(gold_row)

	# -- Teleport ------------------------------------------------------------
	var tp_section := UiStyle.label("TELEPORT", 20, UiStyle.GOLD_TEXT)
	tp_section.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(tp_section)

	var maps: Dictionary = GameData.table("maps").get("maps", {})
	var tp_grid := GridContainer.new()
	tp_grid.columns = 3
	tp_grid.add_theme_constant_override("h_separation", 6)
	tp_grid.add_theme_constant_override("v_separation", 6)
	for map_id in maps:
		var map_name: String = maps[map_id].get("name", map_id)
		var short: String = map_name.left(14)
		tp_grid.add_child(_small_button(short, PURPLE, _teleport.bind(map_id)))
	stack.add_child(tp_grid)

	# -- Combat / Items ------------------------------------------------------
	var combat_section := UiStyle.label("COMBAT & ITEMS", 20, UiStyle.GOLD_TEXT)
	combat_section.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(combat_section)

	_god_button = _button("GOD MODE: OFF", RED, _toggle_god)
	stack.add_child(_god_button)
	stack.add_child(_button("KILL ALL MONSTERS", RED, _kill_all))
	stack.add_child(_button("FULL HEAL", GREEN, _full_heal))
	stack.add_child(_button("+50 POTIONS", GREEN, _give_potions))

	# -- Misc ----------------------------------------------------------------
	var misc_section := UiStyle.label("MISC", 20, UiStyle.GOLD_TEXT)
	misc_section.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(misc_section)

	stack.add_child(_button("TOGGLE FPS", BLUE, _toggle_fps))
	stack.add_child(_button("RESET TUTORIAL", BROWN, _reset_tutorial))
	stack.add_child(_button("CLEAR BAG", RED, _clear_bag))

	# -- Back ----------------------------------------------------------------
	stack.add_child(_button("BACK", BROWN, func() -> void: back_pressed.emit()))

	_refresh_level()


func _process(_delta: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


# -- Helpers -----------------------------------------------------------------

func _player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _game() -> Node:
	return get_tree().get_first_node_in_group("game")


func _refresh_level() -> void:
	var p := _player()
	if p == null:
		return
	_level_label.text = "Current: Lv%d  XP: %d/%d  Gold: %d" % [
		p.stats.level, p.stats.xp, Leveling.xp_for_level(p.stats.level), p.stats.gold
	]


# -- Actions -----------------------------------------------------------------

func _set_level(target: int) -> void:
	var p := _player()
	if p == null:
		return
	p.stats.level = maxi(1, target)
	p.stats.xp = 0
	p.stats.stat_points = {}
	p.stats.learned_skills = []
	# Refresh HP and stats.
	p.max_hp = p.stats.max_hp()
	p.hp = p.max_hp
	p.emit_signal("hp_changed", p.hp, p.max_hp)
	_refresh_level()


func _add_gold(amount: int) -> void:
	var p := _player()
	if p == null:
		return
	p.stats.gold += amount
	_refresh_level()


func _teleport(map_id: String) -> void:
	var g := _game()
	if g == null:
		return
	back_pressed.emit()  # close admin + menu
	g.call("change_map", map_id)


func _toggle_god() -> void:
	god_mode = not god_mode
	_god_button.text = "GOD MODE: %s" % ("ON" if god_mode else "OFF")
	var p := _player()
	if p == null:
		return
	if god_mode:
		p.hp = p.max_hp
		p.emit_signal("hp_changed", p.hp, p.max_hp)


func _kill_all() -> void:
	for mob in get_tree().get_nodes_in_group("enemies"):
		if "hp" in mob:
			mob.hp = 0


func _full_heal() -> void:
	var p := _player()
	if p == null:
		return
	p.hp = p.max_hp
	p.emit_signal("hp_changed", p.hp, p.max_hp)


func _give_potions() -> void:
	var p := _player()
	if p == null:
		return
	# Find the basic potion (first usable item).
	var potion_id: String = ""
	for item_id in ItemDb.items:
		if ItemDb.items[item_id].get("usable", false):
			potion_id = item_id
			break
	if potion_id == "":
		return
	p.stats.add_item(potion_id, 50)


func _toggle_fps() -> void:
	if _fps_label == null:
		_fps_label = UiStyle.label("FPS: 0", 18, Color(1, 1, 0))
		_fps_label.position = Vector2(10, 10)
		_fps_label.z_index = 100
		# Add to the HUD's parent so it's always visible.
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.add_child(_fps_label)
		else:
			get_parent().add_child(_fps_label)
		_fps_label.visible = true
	else:
		_fps_label.visible = not _fps_label.visible


func _reset_tutorial() -> void:
	var p := _player()
	if p == null:
		return
	p.stats.tutorial = 0


func _clear_bag() -> void:
	var p := _player()
	if p == null:
		return
	p.stats.bag = []


# -- UI builders (mirror the game menu's style) ------------------------------

func _button(text: String, color: Color, action: Callable) -> Button:
	var button := UiStyle.button(text, color, Vector2(0, 52))
	button.pressed.connect(action)
	return button


func _small_button(text: String, color: Color, action: Callable) -> Button:
	var button := UiStyle.button(text, color, Vector2(0, 40))
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button
