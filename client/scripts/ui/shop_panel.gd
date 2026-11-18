extends PanelContainer
## A shop. BUY lists what the townsperson sells, one tap per item. SELL shows
## the bag: tap an item, then SELL gets part of its price (more for rare or
## upgraded gear). Only shows state; buying and selling are requests.

signal close_requested
signal request(method: String, argument: Variant)

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const ItemDb := preload("res://scripts/items/item_db.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const InventorySlot := preload("res://scripts/ui/inventory_slot.gd")
const GREEN := Color(0.22, 0.48, 0.3)
const BROWN := Color(0.5, 0.3, 0.18)
const BAG_COLUMNS := 5

var npc_id: String = ""
var bag_slots: Array = []
var _title: Label
var _gold_label: Label
var _buy_rows: VBoxContainer
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _sell_info: Label
var _sell_button: Button
var _selected = null
var _stats = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var top := HBoxContainer.new()
	_title = UiStyle.label("SHOP", 22, UiStyle.GOLD_TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_gold_label = UiStyle.label("0 G", 18, UiStyle.GOLD_TEXT)
	top.add_child(_gold_label)
	var close := UiStyle.button("X", Color(0.55, 0.2, 0.25), Vector2(46, 40))
	close.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(close)
	column.add_child(top)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	for page_name in ["buy", "sell"]:
		var tab := UiStyle.button(page_name.to_upper(), BROWN, Vector2(0, 40))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_page.bind(page_name))
		_tabs[page_name] = tab
		tabs.add_child(tab)
	column.add_child(tabs)
	_pages["buy"] = _buy_page()
	_pages["sell"] = _sell_page()
	for page in _pages.values():
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(page)
	show_page("buy")


## Fills BUY with what this townsperson sells.
func open(id: String) -> void:
	npc_id = id
	var data: Dictionary = GameData.table("npcs")[id]
	_title.text = "%s'S SHOP" % data["name"].to_upper()
	for child in _buy_rows.get_children():
		_buy_rows.remove_child(child)
		child.queue_free()
	for item_id in data.get("shop", []):
		_buy_rows.add_child(_buy_row(item_id))
	_select(null)
	show_page("buy")


func show_page(page_name: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page_name
		_tabs[key].modulate.a = 1.0 if key == page_name else 0.5


## stats is a player_stats.gd object.
func refresh(stats) -> void:
	_stats = stats
	_gold_label.text = "%d G" % stats.gold
	var items: Array = stats.bag
	for i in bag_slots.size():
		bag_slots[i].show_stack(items[i] if i < items.size() else {})
	if _selected != null and _selected.item_id == "":
		_select(null)
	_show_sell_info()


func _buy_row(item_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = load(ItemDb.items[item_id]["icon"])
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var item_name := UiStyle.label(ItemDb.items[item_id]["name"], 16, Color.WHITE)
	item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(item_name)
	row.add_child(UiStyle.label("%d G" % ItemDb.price(item_id), 16, UiStyle.GOLD_TEXT))
	var buy := UiStyle.button("BUY", GREEN, Vector2(64, 40))
	buy.pressed.connect(func() -> void: request.emit("buy_item", item_id))
	row.add_child(buy)
	return row


func _buy_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_buy_rows = VBoxContainer.new()
	_buy_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_buy_rows)
	return scroll


func _sell_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var grid := GridContainer.new()
	grid.columns = BAG_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in BAG_COLUMNS * 3:
		var slot = InventorySlot.new()
		slot.place = "bag"
		slot.key = i
		slot.custom_minimum_size = Vector2(52, 52)
		slot.connect("tapped", _on_slot_tapped)
		bag_slots.append(slot)
		grid.add_child(slot)
	page.add_child(grid)
	_sell_info = UiStyle.label("", 15, Color(0.85, 0.85, 0.9))
	_sell_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sell_info.custom_minimum_size = Vector2(280, 44)
	page.add_child(_sell_info)
	_sell_button = UiStyle.button("SELL", BROWN, Vector2(0, 44))
	_sell_button.pressed.connect(_on_sell_pressed)
	page.add_child(_sell_button)
	return page


func _on_slot_tapped(slot) -> void:
	_select(slot if slot.item_id != "" else null)


func _select(slot) -> void:
	if _selected != null:
		_selected.selected = false
	_selected = slot
	if _selected != null:
		_selected.selected = true
	_show_sell_info()


func _show_sell_info() -> void:
	if _sell_info == null:
		return
	if _selected == null:
		_sell_info.text = "Tap something in your bag to sell it."
		_sell_button.hide()
		return
	var stack: Dictionary = _selected.stack
	_sell_info.text = "%s: %d G each." % [ItemDb.display_name(stack, true), ItemDb.sell_price(stack)]
	_sell_button.show()


func _on_sell_pressed() -> void:
	if _selected != null and _selected.item_id != "":
		request.emit("sell_from_bag", _selected.key)
