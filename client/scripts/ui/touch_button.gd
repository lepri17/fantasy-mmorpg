extends Control
## Round on-screen button that presses an input action while it is held.
## Used for Attack, Skill and Potion. What the action does is decided elsewhere.

const NO_TOUCH := -1

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


func _ready() -> void:
	add_to_group("action_buttons")  # the HUD hides this group while the inventory is open


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch) or not is_visible_in_tree():
		return
	if event.pressed and _touch_index == NO_TOUCH:
		if get_global_rect().has_point(event.position):
			_touch_index = event.index
			Input.action_press(action)
			queue_redraw()
	elif not event.pressed and event.index == _touch_index:
		_release()


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
	var radius: float = minf(size.x, size.y) / 2.0
	var is_held: bool = _touch_index != NO_TOUCH
	draw_circle(center, radius, Color(color, 0.85 if is_held else 0.5))
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.7), 3.0, true)
	if cooldown > 0.0:
		var wedge := PackedVector2Array([center])
		var steps: int = maxi(2, int(40 * cooldown))
		for i in steps + 1:
			var angle: float = -PI / 2.0 + TAU * cooldown * float(i) / steps
			wedge.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(wedge, Color(0, 0, 0, 0.45))
	if badge != "":
		var spot: Vector2 = center + Vector2(radius, radius) * 0.68
		draw_circle(spot, 17.0, Color(0.1, 0.06, 0.1, 0.9))
		draw_arc(spot, 17.0, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 2.0, true)
		var font: Font = ThemeDB.fallback_font
		var baseline := Vector2(spot.x - 17.0, spot.y + 6.0)
		draw_string(font, baseline, tr(badge), HORIZONTAL_ALIGNMENT_CENTER, 34.0, 17, Color.WHITE)


func _release() -> void:
	_touch_index = NO_TOUCH
	Input.action_release(action)
	queue_redraw()
