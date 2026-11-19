extends Node
## The open world's monster moves (monsters.json), beside slime.gd's own:
## - "shell" (Snapjaw Turtle): when the hero comes close it hides in its shell
##   and takes little damage ("damage_taken"), then comes out snapping at
##   everything round it (a warned area hit).
## - "leap" (Marsh Frog): it crouches while a circle marks where the hero
##   stands, jumps there through the air, and lands hard on whoever is still in
##   the circle.
## - "split" (Bubble Slime): when it dies it bursts into smaller ones ("into",
##   "count") that do not come back.
## slime.gd owns it (a child named "Moves") and asks it each frame: busy(),
## step() while busy, try_start() when a move could begin; damage_taken() when
## hit; on_death() when it dies; reset() when it comes back.

const Telegraph := preload("res://scripts/combat/telegraph.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const SLIME_SCENE_PATH := "res://scenes/enemies/slime.tscn"
const DUST := Color(0.7, 0.62, 0.45)

var monster = null
var shell: Dictionary = {}
var leap: Dictionary = {}
var split: Dictionary = {}
var _ready_in: float = 0.0
var _shell_left: float = 0.0
var _crouch_left: float = 0.0
var _air_left: float = 0.0
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO


## True if a monster's data asks for any of these moves.
static func wanted(data: Dictionary) -> bool:
	return data.has("shell") or data.has("leap") or data.has("split")


func setup(owner_monster, data: Dictionary) -> void:
	monster = owner_monster
	shell = data.get("shell", {})
	leap = data.get("leap", {})
	split = data.get("split", {})
	reset()


func reset() -> void:
	_ready_in = randf_range(0.8, 2.0)
	_shell_left = 0.0
	_crouch_left = 0.0
	_air_left = 0.0


## In the middle of a move: the monster neither walks nor attacks by itself.
func busy() -> bool:
	return _shell_left > 0.0 or _crouch_left > 0.0 or _air_left > 0.0


func in_shell() -> bool:
	return _shell_left > 0.0


func tick(delta: float) -> void:
	_ready_in = maxf(0.0, _ready_in - delta)


## Starts a move if one is ready and the hero is where it works.
func try_start(target: Node2D, distance: float) -> bool:
	if _ready_in > 0.0 or busy():
		return false
	if not shell.is_empty() and distance <= float(shell["range"]):
		_go_in()
		return true
	if not leap.is_empty() and distance >= float(leap["min_range"]):
		if distance <= float(leap["range"]):
			_crouch(target)
			return true
	return false


## The movement while busy (none: it hides, crouches, or flies on its own).
func step(delta: float) -> Vector2:
	if _shell_left > 0.0:
		_shell_left -= delta
		if _shell_left <= 0.0:
			_come_out()
	elif _crouch_left > 0.0:
		_crouch_left -= delta
		if _crouch_left <= 0.0:
			_take_off()
	elif _air_left > 0.0:
		_air_left = maxf(0.0, _air_left - delta)
		var done: float = 1.0 - _air_left / float(leap["air_seconds"])
		monster.global_position = _leap_from.lerp(_leap_to, done)
		monster.lift(sin(PI * done) * float(leap["height"]))
		if _air_left == 0.0:
			_land()
	return Vector2.ZERO


## Less damage while it hides in its shell.
func damage_taken(amount: int) -> int:
	if _shell_left > 0.0:
		return maxi(1, roundi(amount * float(shell["damage_taken"])))
	return amount


func on_death() -> void:
	monster.lift(0.0)
	_air_left = 0.0
	if split.is_empty():
		return
	for i in int(split["count"]):
		var small: Node2D = load(SLIME_SCENE_PATH).instantiate()
		small.set("monster_id", split["into"])
		small.set("respawns", false)
		var angle: float = TAU * i / float(split["count"]) + randf_range(-0.4, 0.4)
		small.position = monster.position + Vector2(28, 0).rotated(angle)
		monster.get_parent().call_deferred("add_child", small)


func _go_in() -> void:
	_ready_in = float(shell["cooldown"])
	_shell_left = float(shell["seconds"])
	monster.play_move("shell")


func _come_out() -> void:
	monster.play_move("attack")
	monster.area_attack(
		float(shell["radius"]), float(shell["warning_seconds"]), float(shell["damage_multiplier"])
	)


func _crouch(target: Node2D) -> void:
	_ready_in = float(leap["cooldown"])
	_crouch_left = float(leap["warning_seconds"])
	_leap_from = monster.global_position
	_leap_to = target.global_position
	monster.play_move("attack")
	var circle: Node2D = Telegraph.new()
	circle.radius = float(leap["radius"])
	circle.seconds = float(leap["warning_seconds"]) + float(leap["air_seconds"])
	circle.z_index = -1
	circle.position = monster.get_parent().to_local(_leap_to)
	monster.get_parent().add_child(circle)


func _take_off() -> void:
	_air_left = float(leap["air_seconds"])
	monster.set_solid(false)
	monster.play_move("leap")


func _land() -> void:
	monster.lift(0.0)
	monster.set_solid(true)
	monster.play_move("idle")
	Burst.spawn(monster.get_parent(), monster.position, DUST, 14, 120.0)
	var target: Node2D = monster.chase_target()
	if target != null and target.global_position.distance_to(_leap_to) <= float(leap["radius"]):
		monster.hit_hard(target, float(leap["damage_multiplier"]))
