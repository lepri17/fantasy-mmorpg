extends PanelContainer
## Small inventory on the right side of the screen: the gear the warrior wears
## around his portrait, the bag, gold, and the item last tapped with its
## buttons (EQUIP / REMOVE / USE, and DROP). A double tap does the first button.
## It only shows state. What to do with an item is asked for with item_action,
## naming the player method to call and its argument.

signal close_requested
signal item_action(method: String, argument: Variant)

const ItemDb := preload("res://scripts/items/item_db.gd")
const CombatRules := preload("res://scripts/combat/combat_rules.gd")
const InventorySlot := preload("res://scripts/ui/inventory_slot.gd")

const SLOT_SIZE := Vector2(52, 52)
const BAG_COLUMNS := 5
const BAG_ROWS := 3
const PORTRAIT_SIZE := Vector2(128, 128)
const WARRIOR_SHEET := "res://assets/characters/warrior/warrior.png"
const COIN_ICON := "res://assets/items/icons/coin.png"
const GOLD_TEXT := Color(1.0, 0.86, 0.45)
const FRAME_BORDER := Color(0.85, 0.68, 0.32)

## Gear slot name -> slot control.
var gear_slots: Dictionary = {}
var bag_slots: Array = []

var _selected = null
var _portrait_frame := AtlasTexture.new()
var _gold_label: Label
var _stats_label: Label
var _name_label: Label
var _info_label: Label
var _primary_button: Button
var _drop_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _frame_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	column.add_child(_title_row())
	column.add_child(_gear_row())
	column.add_child(_bag_header())
	column.add_child(_bag_grid())
	column.add_child(_info_box())
	column.add_child(_actions_row())
	_show_details()


## Shows the current gear, bag and gold. stats is a player_stats.gd object,
## look the warrior's current sprite sheet (for the portrait).
func refresh(stats, look: Texture2D = null) -> void:
	for slot_name in gear_slots:
		gear_slots[slot_name].show_item(stats.equipment.get(slot_name, ""))
	var items: Array = stats.bag_items()
	for i in bag_slots.size():
		if i < items.size():
			bag_slots[i].show_item(items[i]["id"], items[i]["count"])
		else:
			bag_slots[i].show_item("")
	_gold_label.text = str(stats.gold)
	var damage: Vector2i = CombatRules.damage_range(stats.attack_damage())
	_stats_label.text = "ATK %d~%d   HP %d" % [damage.x, damage.y, stats.max_hp()]
	if look != null:
		_portrait_frame.atlas = look
	if _selected != null and _selected.item_id == "":
		_select(null)
	_show_details()


func _select(slot) -> void:
	if _selected != null:
		_selected.selected = false
	_selected = slot
	if _selected != null:
		_selected.selected = true
	_show_details()


func _on_slot_tapped(slot) -> void:
	_select(slot if slot.item_id != "" else null)


func _on_slot_double_tapped(slot) -> void:
	if slot == _selected and _primary_button.visible:
		_on_primary_pressed()


func _show_details() -> void:
	if _selected == null:
		_name_label.text = "Tap an item"
		_info_label.text = "to see it. Double tap to wear, remove or use."
		_primary_button.hide()
		_drop_button.hide()
		return
	var item: Dictionary = ItemDb.items[_selected.item_id]
	var parts: PackedStringArray = []
	if item.has("attack"):
		parts.append("+%d Attack." % item["attack"])
	if item.has("max_hp"):
		parts.append("+%d Max HP." % item["max_hp"])
	parts.append(item["text"])
	_name_label.text = item["name"]
	_info_label.text = " ".join(parts)
	_primary_button.text = _primary_action()[0]
	_primary_button.visible = _primary_button.text != ""
	_drop_button.show()


## [button text, player method] for the selected item. Text "" = no such button.
func _primary_action() -> Array:
	if _selected.place == "gear":
		return ["REMOVE", "unequip"]
	var item: Dictionary = ItemDb.items[_selected.item_id]
	if item.get("slot", "") != "":
		return ["EQUIP", "equip_from_bag"]
	if item.get("usable", false):
		return ["USE", "use_from_bag"]
	return ["", ""]


func _on_primary_pressed() -> void:
	if _selected != null and _selected.item_id != "":
		item_action.emit(_primary_action()[1], _selected.key)


func _on_drop_pressed() -> void:
	if _selected != null and _selected.item_id != "":
		var method: String = "drop_equipped" if _selected.place == "gear" else "drop_from_bag"
		item_action.emit(method, _selected.key)


# --- building the panel


func _title_row() -> Control:
	var row := HBoxContainer.new()
	var title := _label("INVENTORY", 22, GOLD_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var close := _button("X", Color(0.55, 0.2, 0.25), Vector2(46, 40))
	close.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(close)
	return row


func _gear_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_gear_column(ItemDb.gear_slots.slice(0, 3)))
	var middle := VBoxContainer.new()
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	var portrait := TextureRect.new()
	_portrait_frame.atlas = load(WARRIOR_SHEET)
	_portrait_frame.region = Rect2(Vector2.ZERO, PORTRAIT_SIZE)  # first idle frame, facing down
	portrait.texture = _portrait_frame
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	middle.add_child(portrait)
	_stats_label = _label("", 15, Color(0.88, 0.9, 1.0))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_stats_label)
	row.add_child(middle)
	row.add_child(_gear_column(ItemDb.gear_slots.slice(3, 6)))
	return row


func _gear_column(slot_names: Array) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	for slot_name in slot_names:
		var slot = _new_slot("gear", slot_name)
		slot.is_gear = true
		slot.hint = ItemDb.slot_names[slot_name]
		gear_slots[slot_name] = slot
		column.add_child(slot)
	return column


func _bag_header() -> Control:
	var row := HBoxContainer.new()
	var title := _label("BAG", 18, GOLD_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var coin := TextureRect.new()
	coin.texture = load(COIN_ICON)
	coin.custom_minimum_size = Vector2(26, 26)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(coin)
	_gold_label = _label("0", 18, GOLD_TEXT)
	row.add_child(_gold_label)
	return row


func _bag_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = BAG_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in BAG_COLUMNS * BAG_ROWS:
		var slot = _new_slot("bag", i)
		bag_slots.append(slot)
		grid.add_child(slot)
	return grid


func _info_box() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 44)
	_name_label = _label("", 17, Color.WHITE)
	_info_label = _label("", 14, Color(0.85, 0.85, 0.9))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(280, 0)
	box.add_child(_name_label)
	box.add_child(_info_label)
	return box


func _actions_row() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.add_theme_constant_override("separation", 10)
	_primary_button = _button("EQUIP", Color(0.22, 0.48, 0.3), Vector2(0, 44))
	_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_button.pressed.connect(_on_primary_pressed)
	row.add_child(_primary_button)
	_drop_button = _button("DROP", Color(0.5, 0.3, 0.18), Vector2(0, 44))
	_drop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_button.pressed.connect(_on_drop_pressed)
	row.add_child(_drop_button)
	return row


func _new_slot(place: String, key: Variant):
	var slot = InventorySlot.new()
	slot.place = place
	slot.key = key
	slot.custom_minimum_size = SLOT_SIZE
	slot.connect("tapped", _on_slot_tapped)
	slot.connect("double_tapped", _on_slot_double_tapped)
	return slot


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, color: Color, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		if state == "hover":
			box.bg_color = color.lightened(0.15)
		elif state == "pressed":
			box.bg_color = color.darkened(0.25)
		box.border_color = FRAME_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(10)
		button.add_theme_stylebox_override(state, box)
	return button


func _frame_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.06, 0.1, 0.9)
	box.border_color = FRAME_BORDER
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(14)
	return box
