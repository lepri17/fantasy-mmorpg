extends CharacterBody2D
## The warrior. Reads the four move actions, walks at a constant speed and
## plays the idle / walk animation that matches the direction it faces.
##
## Movement goes through input actions only (move_left / right / up / down),
## so the touch joystick can drive the same actions later without changes here.

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const ACTION_UP := "move_up"
const ACTION_DOWN := "move_down"

## Walking speed in pixels per second.
@export var move_speed: float = 220.0
## Area the camera may show. Set by the map; an empty rect means no limits.
@export var camera_limits: Rect2 = Rect2()

## "down", "left", "right" or "up".
var facing: String = "down"

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	_apply_camera_limits()
	_play("idle_" + facing)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	var is_moving: bool = direction != Vector2.ZERO

	if is_moving:
		direction = direction.normalized()
		facing = _facing_for(direction)

	velocity = direction * move_speed
	move_and_slide()

	if is_moving:
		_play("walk_" + facing)
	else:
		_play("idle_" + facing)


func _facing_for(direction: Vector2) -> String:
	if absf(direction.x) >= absf(direction.y):
		return "right" if direction.x > 0.0 else "left"
	return "down" if direction.y > 0.0 else "up"


func _play(animation_name: String) -> void:
	if _sprite.animation != animation_name or not _sprite.is_playing():
		_sprite.play(animation_name)


func _apply_camera_limits() -> void:
	if not camera_limits.has_area():
		return
	_camera.limit_left = int(camera_limits.position.x)
	_camera.limit_top = int(camera_limits.position.y)
	_camera.limit_right = int(camera_limits.end.x)
	_camera.limit_bottom = int(camera_limits.end.y)
