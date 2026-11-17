extends Control
## Round on-screen button that presses an input action while it is held.
## Used for Attack, Skill and Potion. What the action does is decided elsewhere.

const NO_TOUCH := -1

@export var action: String = "attack"
@export var color: Color = Color(0.9, 0.25, 0.3)

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


func _release() -> void:
	_touch_index = NO_TOUCH
	Input.action_release(action)
	queue_redraw()
