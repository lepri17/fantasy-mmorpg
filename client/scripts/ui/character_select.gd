extends Control
## The first screen: the saved heroes in three slots, each with PLAY and
## DELETE, and NEW HERO on an empty slot: pick a class (Warrior or Archer for
## now) and a name. PLAY loads that hero's save and starts the game.

const SaveFile := preload("res://scripts/player/save_file.gd")
const ClassDb := preload("res://scripts/player/class_db.gd")
const HeroLook := preload("res://scripts/player/hero_look.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const Language := preload("res://scripts/i18n/language.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
## The hero sheets: cell size, and the idle frames in the first row (facing down).
const CELL := 128
const IDLE_FRAMES := 4
const IDLE_SECONDS := 0.2
const CARD_SIZE := Vector2(320, 0)
const PREVIEW_SIZE := Vector2(170, 170)
const NAMES := ["Aren", "Lio", "Nessa", "Tavi", "Elin", "Doran", "Pip", "Wren", "Quill", "Brin"]
const BACKGROUND_TOP := Color(0.17, 0.24, 0.38)
const BACKGROUND_BOTTOM := Color(0.07, 0.09, 0.15)
const DIM_TEXT := Color(0.78, 0.75, 0.84)
const GREEN := Color(0.22, 0.48, 0.3)
const RED := Color(0.55, 0.2, 0.2)
const BROWN := Color(0.5, 0.3, 0.18)

## False in the smoke test: PLAY then only picks the save, without changing scene.
var starts_game: bool = true
## The slot NEW HERO fills (1..3).
var new_slot: int = 0

var _title: Label
var _cards: HBoxContainer
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _back_button: Button
var _language_button: Button
## The idle frames shown on the cards; they move on together.
var _previews: Array[AtlasTexture] = []
var _idle_time: float = 0.0
## The slot whose DELETE was pressed once (a second press deletes), or 0.
var _delete_armed: int = 0


func _ready() -> void:
	Language.setup(get_tree())
	SaveFile.adopt_old_save()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	_build()
	show_slots()


## The phone's back button: from NEW HERO back to the slots, from the slots out.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _back_button != null and _back_button.visible:
			show_slots()
		else:
			get_tree().quit()


func _process(delta: float) -> void:
	_idle_time += delta
	var column: int = int(_idle_time / IDLE_SECONDS) % IDLE_FRAMES
	for preview in _previews:
		preview.region = Rect2(column * CELL, 0, CELL, CELL)


func _draw() -> void:
	var corners := PackedVector2Array(
		[Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	)
	var colors := PackedColorArray(
		[BACKGROUND_TOP, BACKGROUND_TOP, BACKGROUND_BOTTOM, BACKGROUND_BOTTOM]
	)
	draw_polygon(corners, colors)


## The three save slots.
func show_slots() -> void:
	_delete_armed = 0
	_show_slot_cards()


## NEW HERO for a slot: the classes to choose from, and a name.
func show_classes(slot: int) -> void:
	new_slot = slot
	_clear_cards()
	_title.text = "NEW HERO"
	_name_edit.text = NAMES.pick_random()
	_name_row.show()
	_back_button.show()
	for class_id in ClassDb.playable():
		_class_card(class_id)


## Saves a new hero of the class in the chosen slot, and plays it.
func create(class_id: String) -> void:
	var hero_name: String = _name_edit.text.strip_edges().left(12)
	if hero_name == "":
		hero_name = NAMES.pick_random()
	SaveFile.create_slot(new_slot, class_id, hero_name)
	play(new_slot)


## Plays the hero saved in the slot.
func play(slot: int) -> void:
	SaveFile.path = SaveFile.slot_path(slot)
	if starts_game:
		get_tree().change_scene_to_file(MAIN_SCENE)


## DELETE asks first: the first press shows "SURE?", the second deletes.
## Returns true when the hero was deleted.
func request_delete(slot: int) -> bool:
	if _delete_armed != slot:
		_delete_armed = slot
		_show_slot_cards()
		return false
	SaveFile.delete_slot(slot)
	show_slots()
	return true


func _build() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 40.0
	column.offset_top = 24.0
	column.offset_right = -40.0
	column.offset_bottom = -24.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	var game_name: String = ProjectSettings.get_setting("application/config/name", "")
	column.add_child(_centered(UiStyle.label(game_name, 40, UiStyle.GOLD_TEXT)))
	_title = _centered(UiStyle.label("", 26, Color.WHITE))
	column.add_child(_title)
	_name_row = HBoxContainer.new()
	_name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_name_row.add_theme_constant_override("separation", 12)
	_name_row.add_child(UiStyle.label("Name", 22, Color.WHITE))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(260, 48)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_row.add_child(_name_edit)
	column.add_child(_name_row)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", 24)
	column.add_child(_cards)
	_language_button = UiStyle.button("", BROWN, Vector2(150, 52))
	_language_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_language_button.offset_left = -190.0
	_language_button.offset_top = 24.0
	_language_button.offset_right = -40.0
	_language_button.offset_bottom = 76.0
	_language_button.pressed.connect(_switch_language)
	add_child(_language_button)
	_update_language_button()
	_back_button = UiStyle.button("BACK", BROWN, Vector2(180, 52))
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(show_slots)
	column.add_child(_back_button)


## The button shows the other language's own name: "עברית" or "English".
func _switch_language() -> void:
	Language.set_language(Language.other())
	_update_language_button()


func _update_language_button() -> void:
	_language_button.text = Language.NAMES[Language.other()]
	_language_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


func _show_slot_cards() -> void:
	_clear_cards()
	_title.text = "CHOOSE YOUR HERO"
	_name_row.hide()
	_back_button.hide()
	for slot in range(1, SaveFile.SLOT_COUNT + 1):
		_slot_card(slot, SaveFile.peek(slot))


func _slot_card(slot: int, data: Dictionary) -> void:
	var box: VBoxContainer = _card()
	if data.is_empty():
		box.add_child(_centered(UiStyle.label("Empty slot", 24, DIM_TEXT)))
		var new_button := UiStyle.button("NEW HERO", GREEN, Vector2(0, 64))
		new_button.pressed.connect(show_classes.bind(slot))
		box.add_child(new_button)
		return
	var class_id: String = str(data.get("class", ClassDb.DEFAULT))
	var equipment = data.get("equipment", {})
	box.add_child(_preview(class_id, equipment if equipment is Dictionary else {}))
	var hero_name: String = str(data.get("name", ""))
	if hero_name == "":
		hero_name = "Hero %d" % slot
	box.add_child(_centered(UiStyle.label(hero_name, 26, Color.WHITE)))
	var class_text: String = ClassDb.display_name(class_id, data.get("advanced", false) == true)
	var level_line: String = "Lv.%d %s" % [int(data.get("level", 1)), class_text]
	box.add_child(_centered(UiStyle.label(level_line, 20, UiStyle.GOLD_TEXT)))
	box.add_child(_centered(UiStyle.label(_map_name(str(data.get("map", ""))), 16, DIM_TEXT)))
	var play_button := UiStyle.button("PLAY", GREEN, Vector2(0, 64))
	play_button.pressed.connect(play.bind(slot))
	box.add_child(play_button)
	var delete_text: String = "SURE?" if _delete_armed == slot else "DELETE"
	var delete_button := UiStyle.button(delete_text, RED, Vector2(0, 44))
	delete_button.pressed.connect(request_delete.bind(slot))
	box.add_child(delete_button)


func _class_card(class_id: String) -> void:
	var box: VBoxContainer = _card()
	var info: Dictionary = ClassDb.info(class_id)
	box.add_child(_preview(class_id, {}))
	box.add_child(_centered(UiStyle.label(info["name"], 28, UiStyle.GOLD_TEXT)))
	var text: Label = _centered(UiStyle.label(info["text"], 16, DIM_TEXT))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(260, 0)
	box.add_child(text)
	var choose_button := UiStyle.button("CHOOSE", GREEN, Vector2(0, 64))
	choose_button.pressed.connect(create.bind(class_id))
	box.add_child(choose_button)


## A framed card in the row; returns the box to fill.
func _card() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.add_theme_stylebox_override("panel", UiStyle.frame_style())
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_cards.add_child(panel)
	return box


## The hero standing (first idle frame, facing down), in its gear; a new hero
## in its class's starting gear.
func _preview(class_id: String, equipment: Dictionary) -> TextureRect:
	if equipment.is_empty():
		equipment = ClassDb.rule(class_id, "starting_gear")
	var frame := AtlasTexture.new()
	frame.atlas = HeroLook.build(equipment, class_id)
	frame.region = Rect2(0, 0, CELL, CELL)
	_previews.append(frame)
	var picture := TextureRect.new()
	picture.texture = frame
	picture.custom_minimum_size = PREVIEW_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return picture


func _clear_cards() -> void:
	_previews.clear()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()


func _map_name(map_id: String) -> String:
	var maps: Dictionary = GameData.table("maps")["maps"]
	return maps[map_id]["name"] if maps.has(map_id) else maps["field"]["name"]


func _centered(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
