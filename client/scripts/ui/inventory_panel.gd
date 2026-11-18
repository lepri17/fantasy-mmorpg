extends PanelContainer
## Small inventory on the right side of the screen: the gear the warrior wears
## around his portrait, the bag, gold, auto-potion, and the item last tapped with
## its buttons (EQUIP / REMOVE / USE, UPGRADE for gear, and DROP). A double tap
## does the first button.
## It only shows state. What to do with an item is asked for with item_action,
## naming the player method to call and its argument.

signal close_requested
signal item_action(method: String, argument: Variant)

const ItemDb := preload("res://scripts/items/item_db.gd")
const CombatRules := preload("res://scripts/combat/combat_rules.gd")
const InventorySlot := preload("res://scripts/ui/inventory_slot.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")

const SLOT_SIZE := Vector2(52, 52)
const BAG_COLUMNS := 5
const BAG_ROWS := 3
const PORTRAIT_SIZE := Vector2(128, 128)
const WARRIOR_SHEET := "res://assets/characters/warrior/warrior.png"
const COIN_ICON := "res://assets/items/icons/coin.png"
const GOLD_TEXT := Color(1.0, 0.86, 0.45)
const FRAME_BORDER := Color(0.85, 0.68, 0.32)
## How gear bonuses are named in the details, in this order.
const STAT_NAMES := {
	"attack": "Attack",
	"max_hp": "Max HP",
	"defense": "Defense",
	"max_stamina": "Max Stamina",
	"crit_chance": "Crit",
	"evasion": "Evasion",
	"skill_damage": "Skill damage",
}

## Gear slot name -> slot control.
var gear_slots: Dictionary = {}
var bag_slots: Array = []

var _selected = null
var _stats = null
var _portrait_frame := AtlasTexture.new()
var _gold_label: Label
var _stats_label: Label
var _name_label: Label
var _info_label: Label
var _primary_button: Button
var _upgrade_button: Button
var _drop_button: Button
var _auto_button: Button


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
	_stats = stats
	for slot_name in gear_slots:
		gear_slots[slot_name].show_stack(stats.equipment.get(slot_name, {}))
	var items: Array = stats.bag
	for i in bag_slots.size():
		bag_slots[i].show_stack(items[i] if i < items.size() else {})
	_gold_label.text = str(stats.gold)
	_auto_button.text = "AUTO OFF" if stats.auto_potion == 0 else "AUTO %d%%" % stats.auto_potion
	var damage: Vector2i = CombatRules.damage_range(stats.attack_damage())
	_stats_label.text = "ATK %d~%d  HP %d\nDEF %d  CRIT %d%%  EVA %d%%" % [
		damage.x,
		damage.y,
		stats.max_hp(),
		stats.defense(),
		roundi(stats.crit_chance() * 100.0),
		roundi(stats.evasion() * 100.0),
	]
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
		_upgrade_button.hide()
		_drop_button.hide()
		return
	var stack: Dictionary = _selected.stack
	var item: Dictionary = ItemDb.items[stack["id"]]
	var text: String = item["text"]
	var name_color := Color.WHITE
	if ItemDb.is_gear(stack["id"]):
		var worn: Dictionary = {}
		if _selected.place == "bag" and _stats != null:
			worn = _stats.equipment.get(item["slot"], {})
		text = _gear_text(stack, worn) + _set_text(item) + "\n" + _upgrade_text(stack)
		name_color = ItemDb.rarity_color(stack)
	_name_label.text = ItemDb.display_name(stack, true)
	_name_label.add_theme_color_override("font_color", name_color)
	_info_label.text = text
	_primary_button.text = _primary_action()[0]
	_primary_button.visible = _primary_button.text != ""
	_upgrade_button.visible = not ItemDb.upgrade_step(stack).is_empty()
	_drop_button.show()


## "vs Training Sword: +6 ATK (+2), +3% CRIT (+3%)". For gear in the bag, each
## bonus also says how it compares with the piece worn in that slot now (I7).
func _gear_text(stack: Dictionary, worn: Dictionary) -> String:
	var parts := PackedStringArray()
	for stat in STAT_NAMES:
		var value: float = ItemDb.stat_of(stack, stat)
		var worn_value: float = 0.0 if worn.is_empty() else ItemDb.stat_of(worn, stat)
		if is_zero_approx(value) and is_zero_approx(worn_value):
			continue
		var line: String = "%s %s" % [_amount(stat, value), UiStyle.SHORT_NAMES[stat]]
		if not worn.is_empty():
			var diff: float = value - worn_value
			line += " (=)" if is_zero_approx(diff) else " (%s)" % _amount(stat, diff)
		parts.append(line)
	var text: String = ", ".join(parts)
	if not worn.is_empty():
		text = "vs %s: %s" % [ItemDb.display_name(worn), text]
	return text


## "\nVerdant Set 2/4: 2 = +15 HP; 4 = +3 ATK, +3% EVA"
func _set_text(item: Dictionary) -> String:
	var set_id: String = item.get("set", "")
	if set_id == "" or not ItemDb.sets.has(set_id):
		return ""
	var worn: int = int(_stats.set_pieces().get(set_id, 0)) if _stats != null else 0
	var steps := PackedStringArray()
	var bonuses: Dictionary = ItemDb.sets[set_id]["bonuses"]
	for needed in bonuses:
		steps.append("%s = %s" % [needed, UiStyle.bonus_text(bonuses[needed], true)])
	return (
		"\n%s %d/%d: %s"
		% [ItemDb.sets[set_id]["name"], worn, ItemDb.set_size(set_id), "; ".join(steps)]
	)


## "Next +4: Ember Stone, 100% (have 2)"
func _upgrade_text(stack: Dictionary) -> String:
	var step: Dictionary = ItemDb.upgrade_step(stack)
	if step.is_empty():
		return "Fully upgraded."
	var stones: int = _stats.count_of(step["stone"]) if _stats != null else 0
	return (
		"Next +%d: %s, %d%% (have %d)"
		% [
			int(stack.get("plus", 0)) + 1,
			ItemDb.items[step["stone"]]["name"],
			roundi(float(step["chance"]) * 100.0),
			stones,
		]
	)


static func _amount(stat: String, value: float) -> String:
	var sign_text: String = "+" if value >= 0.0 else "-"
	if stat in ItemDb.PERCENT_STATS:
		var percent: float = absf(value) * 100.0
		var shown: String = (
			str(roundi(percent)) if is_equal_approx(percent, roundf(percent)) else "%.1f" % percent
		)
		return "%s%s%%" % [sign_text, shown]
	return "%s%d" % [sign_text, roundi(absf(value))]


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


func _on_upgrade_pressed() -> void:
	if _selected != null and _selected.item_id != "":
		var method: String = "upgrade_equipped" if _selected.place == "gear" else "upgrade_bag_item"
		item_action.emit(method, _selected.key)


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
	_stats_label = _label("", 13, Color(0.88, 0.9, 1.0))
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
	_auto_button = _button("AUTO OFF", Color(0.32, 0.2, 0.3), Vector2(104, 34))
	_auto_button.add_theme_font_size_override("font_size", 14)
	_auto_button.pressed.connect(func() -> void: item_action.emit("cycle_auto_potion", null))
	row.add_child(_auto_button)
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


## The tapped item's name and details. The details scroll inside a fixed
## height, so a long text never pushes the buttons out of the window.
func _info_box() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_name_label = _label("", 17, Color.WHITE)
	_info_label = _label("", 13, Color(0.85, 0.85, 0.9))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(286, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 54)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_info_label)
	box.add_child(_name_label)
	box.add_child(scroll)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return box


func _actions_row() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.add_theme_constant_override("separation", 10)
	_primary_button = _button("EQUIP", Color(0.22, 0.48, 0.3), Vector2(0, 44))
	_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_button.pressed.connect(_on_primary_pressed)
	row.add_child(_primary_button)
	_upgrade_button = _button("UPGRADE", Color(0.42, 0.28, 0.55), Vector2(0, 44))
	_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	row.add_child(_upgrade_button)
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
	return UiStyle.label(text, font_size, color)


func _button(text: String, color: Color, min_size: Vector2) -> Button:
	return UiStyle.button(text, color, min_size)


func _frame_style() -> StyleBoxFlat:
	return UiStyle.frame_style()
