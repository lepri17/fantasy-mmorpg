extends Control
## One square of the inventory: a frame (in the rarity color for special gear),
## the item icon, the stack count and the upgrade level ("+3").
## Emits tapped when it is touched or clicked, and double_tapped on a quick
## second tap (like double-clicking an item in MapleStory).

signal tapped(slot: Control)
signal double_tapped(slot: Control)

const ItemDb := preload("res://scripts/items/item_db.gd")
const BACKGROUND := Color(0.27, 0.19, 0.26, 0.95)
const BORDER := Color(0.5, 0.4, 0.46)
const BORDER_GEAR := Color(0.78, 0.6, 0.3)
const BORDER_SELECTED := Color(1.0, 0.92, 0.5)
const HINT_COLOR := Color(1, 1, 1, 0.35)
const COUNT_OUTLINE := Color(0.1, 0.05, 0.1)
const PLUS_COLOR := Color(1.0, 0.86, 0.4)
const DOUBLE_TAP_MSEC := 350

## "gear" (worn) or "bag".
var place: String = "bag"
## Gear slot name ("weapon") for worn gear, or the index in the bag.
var key: Variant = 0
## The entry shown here ({} when empty), and its item id ("" when empty).
var stack: Dictionary = {}
var item_id: String = ""
var count: int = 0
## Faint word shown while the slot is empty, such as "Head".
var hint: String = ""
## Gear slots get a gold frame.
var is_gear: bool = false
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

var _icon: Texture2D = null
var _last_tap_msec: int = -DOUBLE_TAP_MSEC
var _box := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box.bg_color = BACKGROUND
	_box.set_corner_radius_all(8)


## Shows a bag or worn entry; {} empties the slot.
func show_stack(entry: Dictionary) -> void:
	stack = entry
	item_id = entry.get("id", "")
	count = int(entry.get("count", 0)) if item_id != "" else 0
	_icon = load(ItemDb.items[item_id]["icon"]) as Texture2D if item_id != "" else null
	queue_redraw()


func show_item(id: String, amount: int = 1) -> void:
	show_stack({} if id == "" else {"id": id, "count": amount})


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var now: int = Time.get_ticks_msec()
		tapped.emit(self)
		if now - _last_tap_msec <= DOUBLE_TAP_MSEC:
			_last_tap_msec = -DOUBLE_TAP_MSEC
			double_tapped.emit(self)
		else:
			_last_tap_msec = now
		accept_event()


func _draw() -> void:
	if selected:
		_box.border_color = BORDER_SELECTED
		_box.set_border_width_all(3)
	elif not stack.is_empty() and ItemDb.is_special(stack):
		_box.border_color = ItemDb.rarity_color(stack)
		_box.set_border_width_all(3)
	else:
		_box.border_color = BORDER_GEAR if is_gear else BORDER
		_box.set_border_width_all(2)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var font: Font = ThemeDB.fallback_font
	if _icon != null:
		var pad := size * 0.1
		draw_texture_rect(_icon, Rect2(pad, size - pad * 2.0), false)
	elif hint != "":
		var middle := Vector2(0.0, size.y / 2.0 + 5.0)
		draw_string(font, middle, hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, HINT_COLOR)
	var plus: int = int(stack.get("plus", 0))
	if plus > 0:
		var top := Vector2(5.0, 17.0)
		var label := "+%d" % plus
		draw_string_outline(font, top, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, COUNT_OUTLINE)
		draw_string(font, top, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PLUS_COLOR)
	if count > 1:
		var corner := Vector2(0.0, size.y - 5.0)
		var width: float = size.x - 6.0
		var text := str(count)
		draw_string_outline(
			font, corner, text, HORIZONTAL_ALIGNMENT_RIGHT, width, 17, 5, COUNT_OUTLINE
		)
		draw_string(font, corner, text, HORIZONTAL_ALIGNMENT_RIGHT, width, 17, Color.WHITE)
