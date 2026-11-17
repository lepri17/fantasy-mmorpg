extends CharacterBody2D
## The warrior: movement, sword attack with auto-aim, spin skill, potions,
## health / stamina, gear, death and respawn. Progress (level, XP, gold, bag,
## gear) lives in PlayerStats; this script only applies it to the scene.
##
## Input goes through actions only (move_*, attack, skill, use_potion), so the
## touch controls drive the same code as the keyboard.

signal hp_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal stats_changed
signal died
signal respawned
## A line for the message log, such as "+20 EXP" or "Your bag is full."
signal message(text: String, color: Color)

const CombatRules = preload("res://scripts/combat/combat_rules.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")
const FloatingText = preload("res://scripts/ui/floating_text.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const WarriorLook = preload("res://scripts/player/warrior_look.gd")
const PICKUP_SCENE = preload("res://scenes/items/pickup.tscn")

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
## Dropped items land this far in front of the warrior and stay this long.
const DROP_DISTANCE := 56.0
const DROPPED_ITEM_SECONDS := 120.0
const DAMAGE_TAKEN_COLOR := Color(0.8, 0.55, 1.0)
const XP_COLOR := Color(0.6, 0.85, 1.0)
const GOLD_COLOR := Color(1.0, 0.86, 0.4)
const LEVEL_COLOR := Color(1.0, 0.9, 0.3)
const WARNING_COLOR := Color(1.0, 0.5, 0.45)

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
## The sprite sheet built for the gear worn now (see warrior_look.gd).
var look_texture: Texture2D = null

var _attack_ready_in: float = 0.0
var _skill_ready_in: float = 0.0
var _attack_animation_left: float = 0.0
var _seconds_since_damage: float = 0.0
var _regen_progress: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO
var _invincible_left: float = 0.0
# Tuning from res://data/character.json (see _load_tuning).
var _stamina_regen: float = 12.0
var _skill_cost: float = 40.0
var _skill_radius: float = 130.0
var _skill_multiplier: float = 2.0
var _skill_cooldown: float = 1.0
var _regen_delay: float = 5.0
var _regen_per_second: float = 2.0
var _respawn_seconds: float = 2.5
## After a hit the warrior blinks and cannot be hurt for this long.
var _hit_invincible_seconds: float = 1.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _camera: Camera2D = $Camera
@onready var _slash = $Slash


func _ready() -> void:
	add_to_group("player")
	_load_tuning()
	stats.from_dict(SaveFile.load_data())
	max_hp = stats.max_hp()
	hp = max_hp
	stamina = max_stamina
	_spawn_position = global_position
	_apply_camera_limits()
	_apply_look()
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
	_blink_while_invincible(delta)

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
	if is_dead or _invincible_left > 0.0:
		return
	hp = maxi(hp - amount, 0)
	_seconds_since_damage = 0.0
	hp_changed.emit(hp, max_hp)
	FloatingText.spawn(self, str(amount), DAMAGE_TAKEN_COLOR, 100.0)
	_sfx("hurt")
	_shake_camera()
	if hp == 0:
		_die()
		return
	_invincible_left = _hit_invincible_seconds
	_sprite.modulate = Color(1.0, 0.4, 0.4)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.2)


## Called by enemies when they die.
func gain_xp(amount: int) -> void:
	var levels_gained: int = stats.add_xp(amount)
	_say("+%d EXP" % amount, XP_COLOR)
	if levels_gained > 0:
		max_hp = stats.max_hp()
		hp = max_hp
		hp_changed.emit(hp, max_hp)
		FloatingText.spawn(self, "LEVEL UP!", LEVEL_COLOR, 120.0, 32)
		_sfx("levelup")
		_say("Level up! You are now level %d." % stats.level, LEVEL_COLOR)
	_progress_changed()


## Called by gold pickups.
func add_gold(amount: int) -> void:
	stats.gold += amount
	FloatingText.spawn(self, "+%d G" % amount, Color(1.0, 0.85, 0.3), 100.0, 22)
	_sfx("coin")
	_say("+%d gold" % amount, GOLD_COLOR)
	_progress_changed()


## Called by item pickups. Returns false, and the item stays on the ground,
## when the bag is full.
func add_item(item_id: String, count: int = 1) -> bool:
	if not stats.add_item(item_id, count):
		_say("Your bag is full.", WARNING_COLOR)
		return false
	var text: String = _item_name(item_id) + (" x%d" % count if count > 1 else "")
	FloatingText.spawn(self, "+" + text, Color(1.0, 0.6, 0.65), 100.0, 22)
	_sfx("coin")
	_say("Picked up %s." % text)
	_progress_changed()
	return true


## Puts on the gear in a bag slot. Gear worn in that place goes to the bag.
func equip_from_bag(index: int) -> void:
	if is_dead or index < 0 or index >= stats.bag.size():
		return
	var item_id: String = stats.bag[index]["id"]
	if stats.equip(index):
		_say("Equipped %s." % _item_name(item_id))
		_gear_changed()


## Moves worn gear (by gear slot, such as "weapon") into the bag.
func unequip(slot: String) -> void:
	var item_id: String = stats.equipment.get(slot, "")
	if is_dead or item_id == "":
		return
	if not stats.unequip(slot):
		_say("Your bag is full.", WARNING_COLOR)
		return
	_say("Took off %s." % _item_name(item_id))
	_gear_changed()


## Drops one item from a bag slot on the ground in front of the warrior.
func drop_from_bag(index: int) -> void:
	if is_dead:
		return
	var item_id: String = stats.take_from_bag(index)
	if item_id == "":
		return
	_drop_on_ground(item_id)
	_progress_changed()


## Takes worn gear off and drops it on the ground.
func drop_equipped(slot: String) -> void:
	if is_dead:
		return
	var item_id: String = stats.remove_equipped(slot)
	if item_id == "":
		return
	_drop_on_ground(item_id)
	_gear_changed()


## Uses the item in a bag slot. Potions are the only usable item so far.
func use_from_bag(index: int) -> void:
	if index >= 0 and index < stats.bag.size():
		if stats.bag[index]["id"] == PlayerStats.POTION_ID:
			use_potion()


## For the SPIN button: true when the skill would work right now.
func can_use_skill() -> bool:
	return not is_dead and _skill_ready_in == 0.0 and stamina >= _skill_cost


## Drinks one potion. Does nothing at full health or with no potions left.
func use_potion() -> void:
	if is_dead or stats.potions <= 0 or hp >= max_hp:
		return
	stats.potions -= 1
	var heal_fraction: float = float(ItemDb.items[PlayerStats.POTION_ID]["heal_fraction"])
	var healed: int = mini(roundi(max_hp * heal_fraction), max_hp - hp)
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
	if _skill_ready_in > 0.0 or stamina < _skill_cost:
		return
	_skill_ready_in = _skill_cooldown
	stamina -= _skill_cost
	stamina_changed.emit(stamina, max_stamina)
	_slash.play_spin()
	_sfx("skill")
	var base_damage: int = roundi(stats.attack_damage() * _skill_multiplier)
	for enemy in _alive_enemies():
		if enemy.global_position.distance_to(global_position) <= _skill_radius:
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
		stamina = minf(max_stamina, stamina + _stamina_regen * delta)
		stamina_changed.emit(stamina, max_stamina)

	_seconds_since_damage += delta
	if hp >= max_hp or _seconds_since_damage < _regen_delay:
		_regen_progress = 0.0
		return
	_regen_progress += _regen_per_second * delta
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
	await get_tree().create_timer(_respawn_seconds).timeout
	_respawn()


func _respawn() -> void:
	global_position = _spawn_position
	hp = max_hp
	stamina = max_stamina
	is_dead = false
	_invincible_left = 0.0
	_sprite.self_modulate.a = 1.0
	_sprite.modulate = Color.WHITE
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	respawned.emit()


func _progress_changed() -> void:
	SaveFile.save_data(stats.to_dict())
	stats_changed.emit()


## After the gear changed: health limits, look, save.
func _gear_changed() -> void:
	max_hp = stats.max_hp()
	hp = mini(hp, max_hp)
	hp_changed.emit(hp, max_hp)
	_apply_look()
	_progress_changed()


## Rebuilds the sprite sheet for the gear worn now and points every frame at it.
func _apply_look() -> void:
	look_texture = WarriorLook.build(stats.equipment)
	var frames: SpriteFrames = _sprite.sprite_frames
	for animation in frames.get_animation_names():
		for i in frames.get_frame_count(animation):
			var frame := frames.get_frame_texture(animation, i) as AtlasTexture
			if frame != null:
				frame.atlas = look_texture


## Reads speed, ranges, stamina, skill and regeneration from character.json.
func _load_tuning() -> void:
	var rules: Dictionary = PlayerStats.rules
	var skill: Dictionary = rules["skill"]
	move_speed = float(rules["move_speed"])
	attack_range = float(rules["attack_range"])
	attack_cooldown = float(rules["attack_cooldown"])
	max_stamina = float(rules["max_stamina"])
	_stamina_regen = float(rules["stamina_regen_per_second"])
	_skill_cost = float(skill["stamina_cost"])
	_skill_radius = float(skill["radius"])
	_skill_multiplier = float(skill["damage_multiplier"])
	_skill_cooldown = float(skill["cooldown"])
	_regen_delay = float(rules["regen_delay_seconds"])
	_regen_per_second = float(rules["regen_hp_per_second"])
	_respawn_seconds = float(rules["respawn_seconds"])
	_hit_invincible_seconds = float(rules["hit_invincible_seconds"])


func _drop_on_ground(item_id: String) -> void:
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", "item")
	pickup.set("item_id", item_id)
	pickup.set("lifetime", DROPPED_ITEM_SECONDS)
	pickup.set("pickup_delay", 1.0)
	pickup.position = position + FACING_VECTORS[facing] * DROP_DISTANCE
	get_parent().call_deferred("add_child", pickup)
	_say("Dropped %s." % _item_name(item_id))


func _blink_while_invincible(delta: float) -> void:
	if _invincible_left <= 0.0:
		return
	_invincible_left = maxf(0.0, _invincible_left - delta)
	var shown: bool = _invincible_left == 0.0 or int(_invincible_left * 12.0) % 2 == 0
	_sprite.self_modulate.a = 1.0 if shown else 0.35


func _say(text: String, color: Color = Color.WHITE) -> void:
	message.emit(text, color)


func _item_name(item_id: String) -> String:
	return ItemDb.items[item_id]["name"]


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
