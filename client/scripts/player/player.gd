extends CharacterBody2D
## The warrior. Reads the move actions, walks at a constant speed, plays the
## idle / walk animation for the direction it faces, and swings the sword when
## the attack action is held.
##
## Input goes through actions only (move_*, attack), so the touch controls
## drive the same code as the keyboard.

signal hp_changed(current: int, maximum: int)

const CombatRules = preload("res://scripts/combat/combat_rules.gd")

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const ACTION_UP := "move_up"
const ACTION_DOWN := "move_down"
const ACTION_ATTACK := "attack"
## How long the swing animation keeps priority over walk / idle.
const ATTACK_ANIMATION_SECONDS := 0.22

const FACING_VECTORS := {
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
	"up": Vector2.UP,
}

## Walking speed in pixels per second.
@export var move_speed: float = 220.0
@export var max_hp: int = 100
@export var attack_damage: int = 10
## How far from the warrior a hit can land, in pixels.
@export var attack_range: float = 90.0
## Seconds between swings.
@export var attack_cooldown: float = 0.45
## Area the camera may show. Set by the map; an empty rect means no limits.
@export var camera_limits: Rect2 = Rect2()

## "down", "left", "right" or "up".
var facing: String = "down"
var hp: int = 0

var _attack_ready_in: float = 0.0
var _attack_animation_left: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _camera: Camera2D = $Camera
@onready var _slash = $Slash


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	_spawn_position = global_position
	_apply_camera_limits()
	_play("idle_" + facing)


func _physics_process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	var is_moving: bool = direction != Vector2.ZERO

	if is_moving:
		direction = direction.normalized()
		facing = _facing_for(direction)

	velocity = direction * move_speed
	move_and_slide()

	_attack_animation_left = maxf(0.0, _attack_animation_left - delta)
	if _attack_animation_left == 0.0:
		if is_moving:
			_play("walk_" + facing)
		else:
			_play("idle_" + facing)

	_attack_ready_in = maxf(0.0, _attack_ready_in - delta)
	if Input.is_action_pressed(ACTION_ATTACK) and _attack_ready_in == 0.0:
		_attack()


## Called by enemies. Only the warrior's own HP is handled here.
func take_damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)
	hp_changed.emit(hp, max_hp)
	_sprite.modulate = Color(1.0, 0.4, 0.4)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.2)
	if hp == 0:
		_defeat()


func _attack() -> void:
	_attack_ready_in = attack_cooldown
	var facing_vector: Vector2 = FACING_VECTORS[facing]
	_slash.play(facing_vector)
	_attack_animation_left = ATTACK_ANIMATION_SECONDS
	_sprite.stop()
	_sprite.play("attack_" + facing)

	var lunge: Tween = create_tween()
	lunge.tween_property(_sprite, "position", facing_vector * 8.0, 0.06)
	lunge.tween_property(_sprite, "position", Vector2.ZERO, 0.1)

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or enemy.get("is_dead"):
			continue
		if _can_hit(enemy.global_position, facing_vector):
			enemy.call("take_damage", CombatRules.roll_damage(attack_damage))


## True when the target is within range and roughly in front of the warrior.
func _can_hit(target_position: Vector2, facing_vector: Vector2) -> bool:
	var to_target: Vector2 = target_position - global_position
	var distance: float = to_target.length()
	if distance > attack_range:
		return false
	if distance < 1.0:
		return true
	return facing_vector.dot(to_target / distance) > 0.2


## Placeholder until there is a real death screen: stand up again at the start.
func _defeat() -> void:
	global_position = _spawn_position
	hp = max_hp
	hp_changed.emit(hp, max_hp)


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
