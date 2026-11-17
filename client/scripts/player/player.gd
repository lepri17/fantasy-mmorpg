extends CharacterBody2D
## The warrior: movement, sword attack with auto-aim, spin skill, potions,
## health / stamina, death and respawn. Progress (level, XP, gold, potions)
## lives in PlayerStats; this script only applies it to the scene.
##
## Input goes through actions only (move_*, attack, skill, use_potion), so the
## touch controls drive the same code as the keyboard.

signal hp_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal stats_changed
signal died
signal respawned

const CombatRules = preload("res://scripts/combat/combat_rules.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")
const FloatingText = preload("res://scripts/ui/floating_text.gd")

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const ACTION_UP := "move_up"
const ACTION_DOWN := "move_down"
const ACTION_ATTACK := "attack"
const ACTION_SKILL := "skill"
const ACTION_POTION := "use_potion"

const FACING_VECTORS := {
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
	"up": Vector2.UP,
}

## How long the swing animation keeps priority over walk / idle
## (5 frames at 18 fps in warrior_frames.tres).
const ATTACK_ANIMATION_SECONDS := 0.28
const STAMINA_REGEN_PER_SECOND := 12.0
const SKILL_STAMINA_COST := 40.0
const SKILL_RADIUS := 130.0
const SKILL_DAMAGE_MULTIPLIER := 2.0
const SKILL_COOLDOWN := 1.0
const POTION_HEAL_FRACTION := 0.4
## Health starts coming back after this long without taking damage.
const REGEN_DELAY_SECONDS := 5.0
const REGEN_HP_PER_SECOND := 2.0
const RESPAWN_SECONDS := 2.5

## Walking speed in pixels per second.
@export var move_speed: float = 220.0
## How far from the warrior a hit can land, in pixels.
@export var attack_range: float = 90.0
## Seconds between swings.
@export var attack_cooldown: float = 0.45
## Area the camera may show. Set by the map; an empty rect means no limits.
@export var camera_limits: Rect2 = Rect2()

## "down", "left", "right" or "up".
var facing: String = "down"
var stats = PlayerStats.new()
var hp: int = 0
var max_hp: int = 0
var stamina: float = 100.0
var max_stamina: float = 100.0
var is_dead: bool = false

var _attack_ready_in: float = 0.0
var _skill_ready_in: float = 0.0
var _attack_animation_left: float = 0.0
var _seconds_since_damage: float = 0.0
var _regen_progress: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _camera: Camera2D = $Camera
@onready var _slash = $Slash


func _ready() -> void:
	add_to_group("player")
	stats.from_dict(SaveFile.load_data())
	max_hp = stats.max_hp()
	hp = max_hp
	stamina = max_stamina
	_spawn_position = global_position
	_apply_camera_limits()
	_play("idle_" + facing)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

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

	_recover(delta)

	_attack_ready_in = maxf(0.0, _attack_ready_in - delta)
	_skill_ready_in = maxf(0.0, _skill_ready_in - delta)
	if Input.is_action_pressed(ACTION_ATTACK) and _attack_ready_in == 0.0:
		_attack()
	if Input.is_action_just_pressed(ACTION_SKILL):
		_use_skill()
	if Input.is_action_just_pressed(ACTION_POTION):
		use_potion()


## Called by enemies.
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = maxi(hp - amount, 0)
	_seconds_since_damage = 0.0
	hp_changed.emit(hp, max_hp)
	FloatingText.spawn(self, str(amount), Color(1.0, 0.45, 0.45), 100.0)
	_sfx("hurt")
	_shake_camera()
	if hp == 0:
		_die()
		return
	_sprite.modulate = Color(1.0, 0.4, 0.4)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.2)


## Called by enemies when they die.
func gain_xp(amount: int) -> void:
	var levels_gained: int = stats.add_xp(amount)
	if levels_gained > 0:
		max_hp = stats.max_hp()
		hp = max_hp
		hp_changed.emit(hp, max_hp)
		FloatingText.spawn(self, "LEVEL UP!", Color(1.0, 0.9, 0.3), 120.0, 32)
		_sfx("levelup")
	_progress_changed()


## Called by gold pickups.
func add_gold(amount: int) -> void:
	stats.gold += amount
	FloatingText.spawn(self, "+%d G" % amount, Color(1.0, 0.85, 0.3), 100.0, 22)
	_sfx("coin")
	_progress_changed()


## Called by potion pickups.
func add_potions(amount: int) -> void:
	stats.potions += amount
	FloatingText.spawn(self, "+%d Potion" % amount, Color(1.0, 0.6, 0.65), 100.0, 22)
	_sfx("coin")
	_progress_changed()


## Drinks one potion. Does nothing at full health or with no potions left.
func use_potion() -> void:
	if is_dead or stats.potions <= 0 or hp >= max_hp:
		return
	stats.potions -= 1
	var healed: int = mini(roundi(max_hp * POTION_HEAL_FRACTION), max_hp - hp)
	hp += healed
	hp_changed.emit(hp, max_hp)
	FloatingText.spawn(self, "+%d" % healed, Color(0.5, 1.0, 0.55), 100.0)
	_sfx("potion")
	_progress_changed()


func _attack() -> void:
	_attack_ready_in = attack_cooldown

	# Auto-aim: if an enemy is within reach, turn to it and swing at it.
	var aim: Vector2 = FACING_VECTORS[facing]
	var target: Node2D = _nearest_enemy(attack_range)
	if target != null:
		var to_target: Vector2 = target.global_position - global_position
		if to_target.length() > 1.0:
			aim = to_target.normalized()
			facing = _facing_for(aim)

	_slash.play(aim)
	_attack_animation_left = ATTACK_ANIMATION_SECONDS
	_sprite.stop()
	_sprite.play("attack_" + facing)
	var lunge: Tween = create_tween()
	lunge.tween_property(_sprite, "position", aim * 8.0, 0.06)
	lunge.tween_property(_sprite, "position", Vector2.ZERO, 0.1)

	var did_hit: bool = false
	for enemy in _alive_enemies():
		if _can_hit(enemy.global_position, aim):
			var damage: int = CombatRules.roll_damage(stats.attack_damage())
			enemy.call("take_damage", damage, global_position)
			did_hit = true
	_sfx("hit" if did_hit else "swing")


## Spin slash: costs stamina and hits every enemy around the warrior.
func _use_skill() -> void:
	if _skill_ready_in > 0.0 or stamina < SKILL_STAMINA_COST:
		return
	_skill_ready_in = SKILL_COOLDOWN
	stamina -= SKILL_STAMINA_COST
	stamina_changed.emit(stamina, max_stamina)
	_slash.play_spin()
	_sfx("skill")
	var base_damage: int = roundi(stats.attack_damage() * SKILL_DAMAGE_MULTIPLIER)
	for enemy in _alive_enemies():
		if enemy.global_position.distance_to(global_position) <= SKILL_RADIUS:
			enemy.call("take_damage", CombatRules.roll_damage(base_damage), global_position)


func _alive_enemies() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy != null and not enemy.get("is_dead"):
			result.append(enemy)
	return result


func _nearest_enemy(max_distance: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = max_distance
	for enemy in _alive_enemies():
		var distance: float = enemy.global_position.distance_to(global_position)
		if distance <= nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest


## True when the target is within range and roughly in the direction of the swing.
func _can_hit(target_position: Vector2, aim: Vector2) -> bool:
	var to_target: Vector2 = target_position - global_position
	var distance: float = to_target.length()
	if distance > attack_range:
		return false
	if distance < 1.0:
		return true
	return aim.dot(to_target / distance) > 0.2


## Stamina always comes back; health only after a while without being hit.
func _recover(delta: float) -> void:
	if stamina < max_stamina:
		stamina = minf(max_stamina, stamina + STAMINA_REGEN_PER_SECOND * delta)
		stamina_changed.emit(stamina, max_stamina)

	_seconds_since_damage += delta
	if hp >= max_hp or _seconds_since_damage < REGEN_DELAY_SECONDS:
		_regen_progress = 0.0
		return
	_regen_progress += REGEN_HP_PER_SECOND * delta
	if _regen_progress >= 1.0:
		_regen_progress -= 1.0
		hp = mini(hp + 1, max_hp)
		hp_changed.emit(hp, max_hp)


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	died.emit()
	_sfx("defeat")
	_sprite.stop()
	create_tween().tween_property(_sprite, "modulate:a", 0.0, 0.6)
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	_respawn()


func _respawn() -> void:
	global_position = _spawn_position
	hp = max_hp
	stamina = max_stamina
	is_dead = false
	_sprite.modulate = Color.WHITE
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	respawned.emit()


func _progress_changed() -> void:
	SaveFile.save_data(stats.to_dict())
	stats_changed.emit()


func _shake_camera() -> void:
	var shake: Tween = create_tween()
	for offset in [Vector2(6, -4), Vector2(-5, 3), Vector2(3, 2), Vector2.ZERO]:
		shake.tween_property(_camera, "offset", offset, 0.04)


func _sfx(sound_name: String) -> void:
	get_tree().call_group("sfx", "play", sound_name)


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
