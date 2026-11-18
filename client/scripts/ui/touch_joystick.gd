extends Control
## On-screen joystick. It drives the same four move actions as the keyboard,
## so the player script does not know (or care) where the movement comes from.
## The whole rect of this Control is the touch zone; the stick sits in its centre.
## A floating stick (settings) starts wherever the thumb goes down on its side
## of the screen, lower down and not on a button.

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const ACTION_UP := "move_up"
const ACTION_DOWN := "move_down"
const NO_TOUCH := -1

@export var base_radius: float = 110.0
@export var knob_radius: float = 46.0
## Stick movement below this fraction of the radius is ignored.
@export var dead_zone: float = 0.2

## The settings' joystick size (1 = 100%).
var size_scale: float = 1.0:
	set(value):
		size_scale = value
		queue_redraw()
var floating: bool = false

var _touch_index: int = NO_TOUCH
var _knob_offset: Vector2 = Vector2.ZERO
## Where the stick is while held, in global coordinates.
var _center: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == NO_TOUCH and _accepts(event.position):
			_touch_index = event.index
			_center = event.position if floating else _home_center()
			_move_knob(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_move_knob(event.position)


func _notification(what: int) -> void:
	# Never leave the player walking if the app loses focus mid-touch.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		if _touch_index != NO_TOUCH:
			_release()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	if _touch_index != NO_TOUCH:
		center = _center - global_position
	var radius: float = base_radius * size_scale
	draw_circle(center, radius, Color(1, 1, 1, 0.16))
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0, true)
	draw_circle(center + _knob_offset, knob_radius * size_scale, Color(1, 1, 1, 0.55))


func _home_center() -> Vector2:
	return global_position + size / 2.0


## A touch in the zone always counts. A floating stick also takes one on its
## side of the screen, below the top part, if it is not on a round button and
## no window is open (the buttons are hidden then).
func _accepts(point: Vector2) -> bool:
	if get_global_rect().has_point(point):
		return true
	if not floating:
		return false
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var left_side: bool = _home_center().x < screen.x / 2.0
	if (point.x < screen.x / 2.0) != left_side or point.y < screen.y * 0.3:
		return false
	for button in get_tree().get_nodes_in_group("action_buttons"):
		if button.get("action") == "attack" and not button.visible:
			return false
		if button.visible and button.get_global_rect().has_point(point):
			return false
	return true


func _move_knob(touch_position: Vector2) -> void:
	var radius: float = base_radius * size_scale
	_knob_offset = (touch_position - _center).limit_length(radius)
	var value: Vector2 = _knob_offset / radius
	if value.length() < dead_zone:
		value = Vector2.ZERO
	_send(value)
	queue_redraw()


func _release() -> void:
	_touch_index = NO_TOUCH
	_knob_offset = Vector2.ZERO
	_send(Vector2.ZERO)
	queue_redraw()


func _send(value: Vector2) -> void:
	_set_action(ACTION_LEFT, -value.x)
	_set_action(ACTION_RIGHT, value.x)
	_set_action(ACTION_UP, -value.y)
	_set_action(ACTION_DOWN, value.y)


func _set_action(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)
