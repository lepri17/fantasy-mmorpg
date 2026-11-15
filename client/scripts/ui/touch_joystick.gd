extends Control
## On-screen joystick. It drives the same four move actions as the keyboard,
## so the player script does not know (or care) where the movement comes from.
## The whole rect of this Control is the touch zone; the stick sits in its centre.

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const ACTION_UP := "move_up"
const ACTION_DOWN := "move_down"
const NO_TOUCH := -1

@export var base_radius: float = 110.0
@export var knob_radius: float = 46.0
## Stick movement below this fraction of the radius is ignored.
@export var dead_zone: float = 0.2

var _touch_index: int = NO_TOUCH
var _knob_offset: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == NO_TOUCH:
			if get_global_rect().has_point(event.position):
				_touch_index = event.index
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
	draw_circle(center, base_radius, Color(1, 1, 1, 0.16))
	draw_arc(center, base_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0, true)
	draw_circle(center + _knob_offset, knob_radius, Color(1, 1, 1, 0.55))


func _move_knob(touch_position: Vector2) -> void:
	var center: Vector2 = global_position + size / 2.0
	_knob_offset = (touch_position - center).limit_length(base_radius)
	var value: Vector2 = _knob_offset / base_radius
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
