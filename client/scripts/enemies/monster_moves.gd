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
## - "roll" (Rock Beetle): it curls into a ball and rolls at the hero, bouncing
##   off rocks and cliffs, hitting him whenever it hits him, harder to hurt.
## - "lob" (Crag Imp): it heaves a rock high over the ground at the hero; it
##   lands on the spot under a warning circle (lobbed_rock.gd).
## slime.gd owns it (a child named "Moves") and asks it each frame: busy(),
## step() while busy, try_start() when a move could begin; damage_taken() when
## hit; on_death() when it dies; reset() when it comes back.

const Telegraph := preload("res://scripts/combat/telegraph.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const LobbedRock := preload("res://scripts/combat/lobbed_rock.gd")
const MOVES := ["shell", "leap", "split", "roll", "lob"]
const THROW_SECONDS := 0.4  # it stands still while it throws
const SLIME_SCENE_PATH := "res://scenes/enemies/slime.tscn"
const DUST := Color(0.7, 0.62, 0.45)

var monster = null
var shell: Dictionary = {}
var leap: Dictionary = {}
var split: Dictionary = {}
var roll: Dictionary = {}
var lob: Dictionary = {}
var _ready_in: float = 0.0
var _shell_left: float = 0.0
var _crouch_left: float = 0.0
var _air_left: float = 0.0
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _roll_left: float = 0.0
var _roll_dir := Vector2.RIGHT
var _roll_hit_in: float = 0.0
var _throw_left: float = 0.0


## True if a monster's data asks for any of these moves.
static func wanted(data: Dictionary) -> bool:
	return MOVES.any(func(move): return data.has(move))


func setup(owner_monster, data: Dictionary) -> void:
	monster = owner_monster
	shell = data.get("shell", {})
	leap = data.get("leap", {})
	split = data.get("split", {})
	roll = data.get("roll", {})
	lob = data.get("lob", {})
	reset()


func reset() -> void:
	_ready_in = randf_range(0.8, 2.0)
	_shell_left = 0.0
	_crouch_left = 0.0
	_air_left = 0.0
	_roll_left = 0.0
	_throw_left = 0.0


## In the middle of a move: the monster neither walks nor attacks by itself.
func busy() -> bool:
	return (
		_shell_left > 0.0
		or _crouch_left > 0.0
		or _air_left > 0.0
		or _roll_left > 0.0
		or _throw_left > 0.0
	)


func rolling() -> bool:
	return _roll_left > 0.0


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
	if not roll.is_empty() and distance <= float(roll["range"]):
		_start_roll(target)
		return true
	if not lob.is_empty() and distance >= float(lob["min_range"]):
		if distance <= float(lob["range"]):
			_throw(target)
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
	elif _roll_left > 0.0:
		return _roll_step(delta)
	elif _throw_left > 0.0:
		_throw_left -= delta
	return Vector2.ZERO


## Less damage while it hides in its shell.
func damage_taken(amount: int) -> int:
	if _shell_left > 0.0:
		return maxi(1, roundi(amount * float(shell["damage_taken"])))
	if _roll_left > 0.0:
		return maxi(1, roundi(amount * float(roll["damage_taken"])))
	return amount


func on_death() -> void:
	monster.lift(0.0)
	_air_left = 0.0
	_roll_left = 0.0
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


func _start_roll(target: Node2D) -> void:
	_ready_in = float(roll["cooldown"])
	_roll_left = float(roll["seconds"])
	_roll_hit_in = 0.0
	_roll_dir = monster.global_position.direction_to(target.global_position)
	monster.play_move("roll")


## Rolls on, bouncing off whatever it bumped into last frame, and hits the hero
## when it reaches him (not again for a moment).
func _roll_step(delta: float) -> Vector2:
	_roll_left -= delta
	_roll_hit_in = maxf(0.0, _roll_hit_in - delta)
	for i in monster.get_slide_collision_count():
		var normal: Vector2 = monster.get_slide_collision(i).get_normal()
		if _roll_dir.dot(normal) < 0.0:
			_roll_dir = _roll_dir.bounce(normal).normalized()
	var target: Node2D = monster.chase_target()
	if target != null and _roll_hit_in == 0.0:
		if target.global_position.distance_to(monster.global_position) < monster.body_radius() + 26.0:
			monster.hit_hard(target, float(roll["damage_multiplier"]))
			_roll_hit_in = 0.7
	if _roll_left <= 0.0:
		_roll_left = 0.0
		monster.play_move("idle")
		return Vector2.ZERO
	return _roll_dir * float(roll["speed"])


func _throw(target: Node2D) -> void:
	_ready_in = float(lob["cooldown"])
	_throw_left = THROW_SECONDS
	monster.play_move("attack")
	var parent: Node = monster.get_parent()
	var spot: Vector2 = parent.to_local(target.global_position)
	var circle: Node2D = Telegraph.new()
	circle.radius = float(lob["radius"])
	circle.seconds = float(lob["flight_seconds"])
	circle.z_index = -1
	circle.position = spot
	parent.add_child(circle)
	var rock: Node2D = LobbedRock.new()
	rock.from = monster.position + Vector2(0, -28)
	rock.to = spot
	rock.seconds = float(lob["flight_seconds"])
	rock.radius = float(lob["radius"])
	rock.damage = roundi(monster.attack_damage * float(lob["damage_multiplier"]))
	parent.add_child(rock)
