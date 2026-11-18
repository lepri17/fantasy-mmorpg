extends PanelContainer
## The storage keeper's chest: the bag on the left, storage on the right.
## Tap a slot, then STORE or TAKE moves the whole stack across.

signal close_requested
signal request(method: String, argument: Variant)

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const ItemDb := preload("res://scripts/items/item_db.gd")
const PlayerStats := preload("res://scripts/player/player_stats.gd")
const InventorySlot := preload("res://scripts/ui/inventory_slot.gd")
const COLUMNS := 5
const MOVE := Color(0.32, 0.22, 0.42)

var bag_slots: Array = []
var storage_slots: Array = []
var _selected = null
var _info: Label
var _move_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var top := HBoxContainer.new()
	var title := UiStyle.label("STORAGE", 22, UiStyle.GOLD_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := UiStyle.button("X", Color(0.55, 0.2, 0.25), Vector2(46, 40))
	close.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(close)
	column.add_child(top)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	sides.add_child(_grid("BAG", "bag", PlayerStats.bag_size, bag_slots))
	sides.add_child(_grid("STORAGE", "storage", PlayerStats.storage_size, storage_slots))
	column.add_child(sides)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	_info = UiStyle.label("", 15, Color(0.85, 0.85, 0.9))
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_info)
	_move_button = UiStyle.button("STORE", MOVE, Vector2(140, 44))
	_move_button.pressed.connect(_on_move_pressed)
	bottom.add_child(_move_button)
	column.add_child(bottom)
	_select(null)


## stats is a player_stats.gd object.
func refresh(stats) -> void:
	for i in bag_slots.size():
		bag_slots[i].show_stack(stats.bag[i] if i < stats.bag.size() else {})
	for i in storage_slots.size():
		storage_slots[i].show_stack(stats.storage[i] if i < stats.storage.size() else {})
	if _selected != null and _selected.item_id == "":
		_select(null)


func _grid(heading: String, place: String, count: int, slots: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiStyle.label(heading, 16, UiStyle.GOLD_TEXT))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in count:
		var slot = InventorySlot.new()
		slot.place = place
		slot.key = i
		slot.custom_minimum_size = Vector2(52, 52)
		slot.connect("tapped", _on_slot_tapped)
		slots.append(slot)
		grid.add_child(slot)
	box.add_child(grid)
	return box


func _on_slot_tapped(slot) -> void:
	_select(slot if slot.item_id != "" else null)


func _select(slot) -> void:
	if _selected != null:
		_selected.selected = false
	_selected = slot
	if _selected != null:
		_selected.selected = true
	if _selected == null:
		_info.text = "Tap a slot to move it."
		_move_button.hide()
		return
	_info.text = ItemDb.display_name(_selected.stack, true)
	_move_button.text = "STORE" if _selected.place == "bag" else "TAKE"
	_move_button.show()


func _on_move_pressed() -> void:
	if _selected != null and _selected.item_id != "":
		var method: String = "store_item" if _selected.place == "bag" else "take_stored"
		request.emit(method, _selected.key)
