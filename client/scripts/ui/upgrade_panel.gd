extends PanelContainer
## M5: the upgrade window, beside the bag. Before any gold is paid it shows
## what the next + adds, what it costs, the chance, and what a miss means: the
## piece keeps its level and its next try is likelier. Nothing breaks. A stone
## can be added for a better chance. It stays open for the next try, and says
## how the last one went. The rules: ItemDb.upgrade_step, PlayerStats.upgrade.

signal close_requested
signal item_action(method: String, argument: Variant)

const ItemDb := preload("res://scripts/items/item_db.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const GOOD := Color(0.55, 0.95, 0.55)
const BAD := Color(1.0, 0.6, 0.5)
const STONE_OFF := Color(0.3, 0.33, 0.45)
const STONE_ON := Color(0.22, 0.5, 0.32)

## The piece: "gear" (key: its slot) or "bag" (key: its index in the bag).
var place: String = ""
var key: Variant = null
## A stone goes into the next try.
var use_stone: bool = false
var _stats = null
## The piece itself (the same entry while it moves between the bag and the body).
var _piece: Dictionary = {}
## Its + when the last try was sent (-1: none), to say how it went.
var _tried_at: int = -1
var _title: Label
var _body: Label
var _result: Label
var _stone_button: Button
var _confirm_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var top := HBoxContainer.new()
	var heading := UiStyle.label("UPGRADE", 22, UiStyle.GOLD_TEXT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var close := UiStyle.button("X", Color(0.55, 0.2, 0.25), Vector2(46, 40))
	close.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(close)
	column.add_child(top)
	_title = UiStyle.label("", 19, Color.WHITE)
	column.add_child(_title)
	_body = UiStyle.label("", 16, Color(0.92, 0.9, 0.95))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_body)
	_stone_button = UiStyle.button("", STONE_OFF, Vector2(0, 44))
	_stone_button.pressed.connect(_on_stone_pressed)
	column.add_child(_stone_button)
	_result = UiStyle.label("", 17, GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_result)
	_confirm_button = UiStyle.button("", Color(0.42, 0.28, 0.55), Vector2(0, 52))
	_confirm_button.pressed.connect(_on_confirm_pressed)
	column.add_child(_confirm_button)


## Shows a piece: place "gear" with its slot, or "bag" with its index.
func open(stats, at_place: String, at_key: Variant) -> void:
	place = at_place
	key = at_key
	_stats = stats
	_piece = {}
	if at_place == "gear":
		_piece = stats.equipment.get(at_key, {})
	elif at_key is int and at_key >= 0 and at_key < stats.bag.size():
		_piece = stats.bag[at_key]
	use_stone = false
	_tried_at = -1
	_result.text = ""
	show()
	refresh(stats)


func refresh(stats) -> void:
	_stats = stats
	var stack: Dictionary = _stack()
	if stack.is_empty():
		hide()
		return
	var plus: int = int(stack.get("plus", 0))
	var step: Dictionary = ItemDb.upgrade_step(stack)
	if _tried_at >= 0:
		_show_result(plus, step)
	if step.is_empty():
		_title.text = "%s is fully upgraded." % ItemDb.display_name(stack)
		_body.text = ""
		_stone_button.hide()
		_confirm_button.hide()
		return
	var stone: String = step["stone"]
	var stones: int = stats.count_of(stone) if stone != "" else 0
	use_stone = use_stone and stones > 0
	var chance: float = float(step["chance"]) + (float(step["stone_bonus"]) if use_stone else 0.0)
	_title.text = "%s  +%d → +%d" % [ItemDb.items[stack["id"]]["name"], plus, plus + 1]
	var lines := PackedStringArray([_gain_text(stack)])
	lines.append("Cost: %d gold (you have %d)" % [int(step["cost"]), stats.gold])
	lines.append(_chance_text(minf(chance, 1.0), int(step["misses"])))
	if float(step["chance"]) < 1.0:
		lines.append(
			(
				"A miss keeps +%d and adds %d%% to the next try. Nothing breaks."
				% [plus, roundi(float(ItemDb.upgrades.get("miss_bonus", 0.0)) * 100.0)]
			)
		)
	_body.text = "\n".join(lines)
	_stone_button.visible = stones > 0
	if stones > 0:
		_stone_button.text = (
			"Use %s: +%d%% (have %d)"
			% [ItemDb.items[stone]["name"], roundi(float(step["stone_bonus"]) * 100.0), stones]
		)
		_paint(_stone_button, STONE_ON if use_stone else STONE_OFF)
	_confirm_button.show()
	_confirm_button.text = "UPGRADE %s" % ("%d G" % int(step["cost"]))
	UiStyle.set_enabled(_confirm_button, stats.gold >= int(step["cost"]))


## The piece, found again in the bag or on the body (sorting or wearing it
## moves it), or {} if it is gone (dropped, sold).
func _stack() -> Dictionary:
	if _stats == null or _piece.is_empty() or not ItemDb.is_gear(_piece.get("id", "")):
		return {}
	for slot in _stats.equipment:
		if is_same(_stats.equipment[slot], _piece):
			place = "gear"
			key = slot
			return _piece
	for i in _stats.bag.size():
		if is_same(_stats.bag[i], _piece):
			place = "bag"
			key = i
			return _piece
	return {}


## "ATK +17 → +19", a line for each bonus: what the piece itself gives now
## and after the next +.
func _gain_text(stack: Dictionary) -> String:
	var next: Dictionary = stack.duplicate(true)
	next["plus"] = int(stack.get("plus", 0)) + 1
	var parts := PackedStringArray()
	for stat in UiStyle.BONUS_NAMES:
		var now: float = ItemDb.stat_of(stack, stat)
		var later: float = ItemDb.stat_of(next, stat)
		if not is_equal_approx(now, later):
			parts.append(
				(
					"%s %s → %s"
					% [
						UiStyle.stat_name(stat, true),
						UiStyle.amount(stat, now),
						UiStyle.amount(stat, later)
					]
				)
			)
	return "\n".join(parts)


static func _chance_text(chance: float, misses: int) -> String:
	var percent: int = roundi(chance * 100.0)
	if misses <= 0:
		return "Chance: %d%%" % percent
	var bonus: int = roundi(misses * float(ItemDb.upgrades.get("miss_bonus", 0.0)) * 100.0)
	return "Chance: %d%% (+%d%% from misses)" % [percent, bonus]


func _show_result(plus: int, step: Dictionary) -> void:
	var went_up: bool = plus > _tried_at
	_tried_at = -1
	if went_up:
		_result.text = "Success! Now +%d." % plus
	else:
		var next_try: int = roundi(float(step.get("chance", 1.0)) * 100.0)
		_result.text = "Missed. It stays +%d. Next try: %d%%." % [plus, next_try]
	_result.add_theme_color_override("font_color", GOOD if went_up else BAD)


func _on_stone_pressed() -> void:
	use_stone = not use_stone
	refresh(_stats)


func _on_confirm_pressed() -> void:
	var stack: Dictionary = _stack()
	if stack.is_empty():
		return
	_tried_at = int(stack.get("plus", 0))
	_result.text = ""
	var method: String = "upgrade_equipped" if place == "gear" else "upgrade_bag_item"
	item_action.emit(method, [key, use_stone])


## A button's colour, in every state.
static func _paint(target: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := target.get_theme_stylebox(state) as StyleBoxFlat
		if box != null:
			box.bg_color = color.darkened(0.25) if state == "pressed" else color
