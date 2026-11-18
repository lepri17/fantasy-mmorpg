extends Control
## Round on-screen button that presses an input action while it is held.
## Used for Attack, Skill and Potion. What the action does is decided elsewhere.
## It is see-through while resting, so it hides little of the map.

const NO_TOUCH := -1
## The circle drawn, as a part of the touch circle: a touch a little outside
## the drawn button still counts, so a small button stays easy to hit.
const DRAWN_PART := 0.88
## See-through when resting, so the map shows behind; solid while held.
const FILL_ALPHA := 0.3
const HELD_ALPHA := 0.7

@export var action: String = "attack"
@export var color: Color = Color(0.9, 0.25, 0.3)

## Small text in the corner, such as how many potions are left. "" = none.
var badge: String = "":
	set(value):
		if value != badge:
			badge = value
			queue_redraw()
## Part of the cooldown still to go, from 1 down to 0: drawn as a dark wedge.
var cooldown: float = 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, cooldown):
			cooldown = value
			queue_redraw()
## Faded when the action cannot be used right now.
var dimmed: bool = false:
	set(value):
		if value != dimmed:
			dimmed = value
			modulate.a = 0.45 if dimmed else 1.0

var _touch_index: int = NO_TOUCH
var _badge_style: StyleBoxFlat = null


func _ready() -> void:
	add_to_group("action_buttons")  # the HUD hides this group while the inventory is open


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch) or not is_visible_in_tree():
		return
	if event.pressed and _touch_index == NO_TOUCH:
		if touches(event.position):
			_touch_index = event.index
			Input.action_press(action)
			queue_redraw()
			# One touch is one button, even where moved or bigger buttons overlap.
			get_viewport().set_input_as_handled()
	elif not event.pressed and event.index == _touch_index:
		_release()


## True if a point on the screen is on this button: inside its touch circle,
## which fills its square (the corners do not count, so neighbours never share
## a touch).
func touches(point: Vector2) -> bool:
	var radius: float = minf(size.x, size.y) / 2.0
	return (point - get_global_rect().get_center()).length() <= radius


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()
	var lost: bool = what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		lost = true
	if lost and _touch_index != NO_TOUCH:
		_release()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0 * DRAWN_PART
	var is_held: bool = _touch_index != NO_TOUCH
	draw_circle(center, radius, Color(color, HELD_ALPHA if is_held else FILL_ALPHA))
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.8 if is_held else 0.55), 2.5, true)
	if cooldown > 0.0:
		var wedge := PackedVector2Array([center])
		var steps: int = maxi(2, int(40 * cooldown))
		for i in steps + 1:
			var angle: float = -PI / 2.0 + TAU * cooldown * float(i) / steps
			wedge.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(wedge, Color(0, 0, 0, 0.45))
	if badge != "":
		_draw_badge(center, radius)


## A small dark pill at the lower right, as wide as its text ("2", "Lv5", "BOOK").
func _draw_badge(center: Vector2, radius: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var text: String = tr(badge)
	var font_size: int = int(clampf(radius * 0.42, 12.0, 16.0))
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var half := Vector2(0.0, font_size * 0.8)
	half.x = maxf(half.y, text_width / 2.0 + font_size * 0.4)
	var spot: Vector2 = center + Vector2(radius, radius) * 0.7
	if _badge_style == null:
		_badge_style = StyleBoxFlat.new()
		_badge_style.bg_color = Color(0.1, 0.06, 0.1, 0.9)
		_badge_style.border_color = Color(1, 1, 1, 0.8)
		_badge_style.set_border_width_all(2)
		_badge_style.anti_aliasing = true
	_badge_style.set_corner_radius_all(int(half.y))
	draw_style_box(_badge_style, Rect2(spot - half, half * 2.0))
	var baseline := Vector2(spot.x - half.x, spot.y + font_size * 0.36)
	draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, half.x * 2.0, font_size, Color.WHITE
	)


func _release() -> void:
	_touch_index = NO_TOUCH
	Input.action_release(action)
	queue_redraw()
