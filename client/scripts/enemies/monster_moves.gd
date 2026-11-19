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
## - "swoop" (Gale Harpy, Stormcrest Roc): it flies up out of reach, glides
##   over to the hero (over cliffs and rifts too), marks a circle under itself
##   and dives onto it.
## - "ambush" (Stone Gargoyle, Mimic): placed on a map, it sleeps as a statue or
##   a chest: still, no health bar, nothing can aim at it. When the hero comes
##   within "wake_range" (or hits it) it wakes with a warned blow all round it.
## - "beam" (Ruin Sentinel): a lane lights up toward the hero, then its eye
##   fires along it (beam_flash.gd), hitting him if he is still in the lane.
## slime.gd owns it (a child named "Moves") and asks it each frame: busy(),
## step() while busy, try_start() when a move could begin; damage_taken() when
## hit; on_death() when it dies; reset() when it comes back.

const Telegraph := preload("res://scripts/combat/telegraph.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const LobbedRock := preload("res://scripts/combat/lobbed_rock.gd")
const BeamFlash := preload("res://scripts/combat/beam_flash.gd")
const MOVES := ["shell", "leap", "split", "roll", "lob", "swoop", "ambush", "beam"]
## The moves it starts itself, in the order they are tried.
const STARTED := ["shell", "leap", "roll", "swoop", "beam", "lob"]
const STONE_CHIPS := Color(0.74, 0.75, 0.8)
const DIVE_SECONDS := 0.18
const FEATHERS := Color(0.84, 0.8, 0.96)
const THROW_SECONDS := 0.4  # it stands still while it throws
const SLIME_SCENE_PATH := "res://scenes/enemies/slime.tscn"
const DUST := Color(0.7, 0.62, 0.45)

var monster = null
var shell: Dictionary = {}
var leap: Dictionary = {}
var split: Dictionary = {}
var roll: Dictionary = {}
var lob: Dictionary = {}
var swoop: Dictionary = {}
var ambush: Dictionary = {}
var beam: Dictionary = {}
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
var _rise_left: float = 0.0
var _glide_left: float = 0.0
var _mark_left: float = 0.0
var _dive_left: float = 0.0
var _swoop_to := Vector2.ZERO
var _dormant: bool = false
var _beam_left: float = 0.0
var _beam_dir := Vector2.RIGHT


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
	swoop = data.get("swoop", {})
	ambush = data.get("ambush", {})
	beam = data.get("beam", {})
	reset()


func reset() -> void:
	_ready_in = randf_range(0.8, 2.0)
	_shell_left = 0.0
	_crouch_left = 0.0
	_air_left = 0.0
	_roll_left = 0.0
	_throw_left = 0.0
	_beam_left = 0.0
	_land_from_sky()
	if not ambush.is_empty() and monster.get("respawns") != false:
		_sleep()  # placed on the map (not summoned): a statue again


## In the middle of a move: the monster neither walks nor attacks by itself.
func busy() -> bool:
	return (
		_shell_left > 0.0
		or _crouch_left > 0.0
		or _air_left > 0.0
		or _roll_left > 0.0
		or _throw_left > 0.0
		or _beam_left > 0.0
		or _dormant
		or in_sky()
	)


## Asleep as a statue or a chest, waiting for the hero.
func dormant() -> bool:
	return _dormant


## Up in the air in a swoop: out of reach.
func in_sky() -> bool:
	return _rise_left > 0.0 or _glide_left > 0.0 or _mark_left > 0.0 or _dive_left > 0.0


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
	match _move_for(distance):
		"shell":
			_go_in()
		"leap":
			_crouch(target)
		"roll":
			_start_roll(target)
		"swoop":
			_take_wing()
		"lob":
			_throw(target)
		"beam":
			_charge_beam(target)
		_:
			return false
	return true


## Which of its moves suits the hero's distance now ("" for none).
func _move_for(distance: float) -> String:
	for move in STARTED:
		var data: Dictionary = get(move)
		if data.is_empty():
			continue
		if float(data.get("min_range", 0.0)) <= distance and distance <= float(data["range"]):
			return move
	return ""


## The movement while busy (none: it hides, crouches, or flies on its own).
func step(delta: float) -> Vector2:
	if _dormant:
		_watch()
	elif _shell_left > 0.0:
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
	elif in_sky():
		return _swoop_step(delta)
	elif _beam_left > 0.0:
		_beam_left -= delta
		if _beam_left <= 0.0:
			_fire_beam()
	return Vector2.ZERO


## Less damage while it hides in its shell.
func damage_taken(amount: int) -> int:
	if _dormant:
		_wake()  # something hit the statue after all: it wakes up
	if _shell_left > 0.0:
		return maxi(1, roundi(amount * float(shell["damage_taken"])))
	if _roll_left > 0.0:
		return maxi(1, roundi(amount * float(roll["damage_taken"])))
	return amount


func on_death() -> void:
	monster.lift(0.0)
	_air_left = 0.0
	_roll_left = 0.0
	_land_from_sky()
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


func _take_wing() -> void:
	_ready_in = float(swoop["cooldown"])
	_rise_left = float(swoop["rise_seconds"])
	monster.set_solid(false)
	monster.remove_from_group("enemies")  # nothing can aim at it up there
	monster.z_index = 3
	monster.play_move("soar")


## Up, over to the hero, a circle under it, and down onto it.
func _swoop_step(delta: float) -> Vector2:
	var height: float = float(swoop["height"])
	var target: Node2D = monster.chase_target()
	if _rise_left > 0.0:
		_rise_left = maxf(0.0, _rise_left - delta)
		monster.lift(height * (1.0 - _rise_left / float(swoop["rise_seconds"])))
		if _rise_left == 0.0:
			_glide_left = float(swoop["glide_seconds"])
		return Vector2.ZERO
	if _glide_left > 0.0:
		_glide_left = maxf(0.0, _glide_left - delta)
		var aim: Vector2 = target.global_position if target != null else monster.global_position
		if _glide_left == 0.0 or monster.global_position.distance_to(aim) < 24.0:
			_glide_left = 0.0
			_mark(aim)
			return Vector2.ZERO
		return monster.global_position.direction_to(aim) * float(swoop["glide_speed"])
	if _mark_left > 0.0:
		_mark_left = maxf(0.0, _mark_left - delta)
		if _mark_left == 0.0:
			_dive_left = DIVE_SECONDS
			monster.play_move("dive")
		return (_swoop_to - monster.global_position) * 8.0
	_dive_left = maxf(0.0, _dive_left - delta)
	monster.lift(height * _dive_left / DIVE_SECONDS)
	if _dive_left == 0.0:
		_back_down()
		Burst.spawn(monster.get_parent(), monster.position, FEATHERS, 16, 140.0)
		if target != null and target.global_position.distance_to(_swoop_to) <= float(swoop["radius"]):
			monster.hit_hard(target, float(swoop["damage_multiplier"]))
	return Vector2.ZERO


func _mark(spot: Vector2) -> void:
	_swoop_to = spot
	_mark_left = float(swoop["warning_seconds"])
	var circle: Node2D = Telegraph.new()
	circle.radius = float(swoop["radius"])
	circle.seconds = float(swoop["warning_seconds"]) + DIVE_SECONDS
	circle.z_index = -1
	circle.position = monster.get_parent().to_local(spot)
	monster.get_parent().add_child(circle)


## Cut short (it died, or came back): down on the ground again.
func _land_from_sky() -> void:
	if in_sky():
		_back_down()
	_rise_left = 0.0
	_glide_left = 0.0
	_mark_left = 0.0
	_dive_left = 0.0


func _back_down() -> void:
	monster.lift(0.0)
	monster.set_solid(true)
	monster.z_index = 0
	if not monster.is_in_group("enemies"):
		monster.add_to_group("enemies")
	monster.play_move("idle")


func _sleep() -> void:
	_dormant = true
	monster.remove_from_group("enemies")
	monster.set_bar_visible(false)
	monster.play_move("sleep")


## Asleep: wakes when a hero comes close.
func _watch() -> void:
	monster.play_move("sleep")  # (nothing else may change its pose while it sleeps)
	for hero in monster.get_tree().get_nodes_in_group("player"):
		if hero.get("is_dead"):
			continue
		var gap: float = hero.global_position.distance_to(monster.global_position)
		if gap <= float(ambush["wake_range"]):
			_wake()
			return


func _wake() -> void:
	_dormant = false
	monster.add_to_group("enemies")
	monster.set_bar_visible(true)
	monster.play_move("attack")
	Burst.spawn(monster.get_parent(), monster.position, STONE_CHIPS, 14, 130.0)
	monster.area_attack(
		float(ambush["radius"]), float(ambush["warning_seconds"]), float(ambush["damage_multiplier"])
	)


func _charge_beam(target: Node2D) -> void:
	_ready_in = float(beam["cooldown"])
	_beam_left = float(beam["warning_seconds"])
	_beam_dir = monster.global_position.direction_to(target.global_position)
	monster.play_move("attack")
	var lane: Node2D = Telegraph.new()
	lane.radius = float(beam["width"]) * 0.5
	lane.length = float(beam["length"])
	lane.rotation = _beam_dir.angle()
	lane.seconds = _beam_left
	lane.z_index = -1
	lane.position = monster.position
	monster.get_parent().add_child(lane)


func _fire_beam() -> void:
	_beam_left = 0.0
	var flash: Node2D = BeamFlash.new()
	flash.position = monster.position
	flash.rotation = _beam_dir.angle()
	flash.length = float(beam["length"])
	flash.width = float(beam["width"])
	monster.get_parent().add_child(flash)
	var target: Node2D = monster.chase_target()
	if target == null:
		return
	var offset: Vector2 = target.global_position - monster.global_position
	var along: float = offset.dot(_beam_dir)
	var across: float = absf(offset.cross(_beam_dir))
	if along >= 0.0 and along <= float(beam["length"]) and across <= float(beam["width"]) * 0.5 + 14.0:
		monster.hit_hard(target, float(beam["damage_multiplier"]))
