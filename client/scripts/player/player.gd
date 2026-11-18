extends CharacterBody2D
## The warrior: movement, sword attack with auto-aim, spin skill, potions,
## health / stamina, gear, death and respawn. Progress (level, XP, gold, bag,
## gear) lives in PlayerStats; this script only applies it to the scene.
##
## Input goes through actions only (move_*, attack, skill, skill_2..4, dash,
## use_potion), so the touch controls drive the same code as the keyboard.
## Skills come from res://data/skills.json; each names the action that uses it.

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
const HitSpark = preload("res://scripts/combat/hit_spark.gd")
const TargetMarker = preload("res://scripts/combat/target_marker.gd")
const StatusEffects = preload("res://scripts/combat/status_effects.gd")
const GameData = preload("res://scripts/data/game_data.gd")
const AchievementRecord = preload("res://scripts/player/achievement_record.gd")
const PICKUP_SCENE = preload("res://scenes/items/pickup.tscn")

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const ACTION_UP := "move_up"
const ACTION_DOWN := "move_down"
const ACTION_ATTACK := "attack"
const ACTION_DASH := "dash"
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
const MISS_COLOR := Color(0.8, 0.85, 0.95)
## The ring under the auto-aim target shows for enemies this much past the reach.
const TARGET_MARKER_REACH := 1.6
const HURT_ANIMATION_SECONDS := 0.2
const STATUS_COLOR := Color(0.75, 0.9, 1.0)
const ACHIEVEMENT_COLOR := Color(1.0, 0.72, 0.95)

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
## 1, 2 or 3: which swing of the combo comes next counts from here. The third is
## the finisher: stronger, with more knockback.
var combo_step: int = 0
## Poison, slow and stun on the warrior.
var statuses = StatusEffects.new()

var _attack_ready_in: float = 0.0
## Skill id -> seconds until it can be used again.
var _skill_cooldowns: Dictionary = {}
var _hurt_animation_left: float = 0.0
var _damage_bonus: float = 0.0
var _damage_bonus_left: float = 0.0
var _dash: Dictionary = {}
var _dash_left: float = 0.0
var _dash_ready_in: float = 0.0
var _dash_direction: Vector2 = Vector2.DOWN
var _attack_animation_left: float = 0.0
var _seconds_since_damage: float = 0.0
var _regen_progress: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO
var _invincible_left: float = 0.0
var _combo_left: float = 0.0
var _target_marker: Node2D = null
# Tuning from res://data/character.json (see _load_tuning).
var _stamina_regen: float = 12.0
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
	stats.record.check(stats.level)
	max_hp = stats.max_hp()
	hp = max_hp
	max_stamina = stats.max_stamina()
	stamina = max_stamina
	_spawn_position = global_position
	_apply_camera_limits()
	_apply_look()
	_target_marker = TargetMarker.new()
	_target_marker.z_index = -1
	_target_marker.hide()
	get_parent().call_deferred("add_child", _target_marker)
	_play("idle_" + facing)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_tick_statuses(delta)
	if is_dead:
		return
	var stunned: bool = statuses.is_active("stun")
	var direction: Vector2 = Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	if stunned:
		direction = Vector2.ZERO
	var is_moving: bool = direction != Vector2.ZERO
	if is_moving:
		direction = direction.normalized()
		facing = _facing_for(direction)
	if _dash_left > 0.0:
		_dash_left = maxf(0.0, _dash_left - delta)
		velocity = _dash_direction * move_speed * float(_dash["speed_multiplier"])
	else:
		velocity = direction * move_speed * statuses.speed_factor()
	move_and_slide()

	_attack_animation_left = maxf(0.0, _attack_animation_left - delta)
	_hurt_animation_left = maxf(0.0, _hurt_animation_left - delta)
	if _attack_animation_left == 0.0 and _hurt_animation_left == 0.0:
		if is_moving:
			_play("walk_" + facing)
		else:
			_play("idle_" + facing)

	_recover(delta)
	_blink_while_invincible(delta)
	_combo_left = maxf(0.0, _combo_left - delta)
	_update_target_marker()

	_attack_ready_in = maxf(0.0, _attack_ready_in - delta)
	_dash_ready_in = maxf(0.0, _dash_ready_in - delta)
	_damage_bonus_left = maxf(0.0, _damage_bonus_left - delta)
	if _damage_bonus_left == 0.0:
		_damage_bonus = 0.0
	for skill_id in _skill_cooldowns:
		_skill_cooldowns[skill_id] = maxf(0.0, float(_skill_cooldowns[skill_id]) - delta)
	if stunned:
		return
	if Input.is_action_pressed(ACTION_ATTACK) and _attack_ready_in == 0.0:
		_attack()
	for skill_id in skills_data():
		if Input.is_action_just_pressed(skills_data()[skill_id]["action"]):
			if not use_skill(skill_id):
				_explain_lock(skill_id)
	if Input.is_action_just_pressed(ACTION_DASH):
		dash(direction)
	if Input.is_action_just_pressed(ACTION_POTION):
		use_potion()


## Called by enemies.
func take_damage(amount: int) -> void:
	if is_dead or _invincible_left > 0.0 or _dash_left > 0.0:
		return
	hp = maxi(hp - amount, 0)
	_seconds_since_damage = 0.0
	hp_changed.emit(hp, max_hp)
	FloatingText.spawn(self, str(amount), DAMAGE_TAKEN_COLOR, 100.0)
	_sfx("hurt")
	_shake_camera()
	_vibrate(40)
	if hp == 0:
		_die()
		return
	_invincible_left = _hit_invincible_seconds
	_hurt_animation_left = HURT_ANIMATION_SECONDS
	_sprite.play("hurt_" + facing)
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
		_say("%d stat points to spend: open STATS (C)." % stats.free_points(), LEVEL_COLOR)
		_announce(stats.record.check(stats.level))
	_progress_changed()


## Called by gold pickups.
func add_gold(amount: int) -> void:
	stats.gold += amount
	FloatingText.spawn(self, "+%d G" % amount, Color(1.0, 0.85, 0.3), 100.0, 22)
	_sfx("coin")
	_say("+%d gold" % amount, GOLD_COLOR)
	_announce(_count("gold_earned", amount))
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
	if index < 0 or index >= stats.bag.size():
		return
	var item_id: String = stats.bag[index]["id"]
	var item: Dictionary = ItemDb.items[item_id]
	if item_id == PlayerStats.POTION_ID:
		use_potion()
	elif item.has("teaches"):
		_read_book(index, item)
	elif item.get("resets_stats", false):
		_read_rebirth_scroll(index)


## Called by a monster as it dies, just before it gives its XP (which saves).
func record_kill(monster_id: String, elite: bool) -> void:
	var earned: Array = _count("kills")
	earned += _count("kills:" + monster_id)
	if elite:
		earned += _count("elite_kills")
	_announce(earned)


## Puts one free stat point into "strength", "agility", "vitality" or "energy".
func add_stat_point(stat_id: String) -> void:
	if stats.add_stat_point(stat_id):
		_limits_changed()
		_progress_changed()


## Gives every stat point back, for gold (STATS window).
func reset_stats(_unused: Variant = null) -> void:
	if stats.spent_points() == 0:
		_say("There are no stat points to give back.", WARNING_COLOR)
	elif not stats.reset_stats(true):
		_say("A stat reset costs %d gold." % stats.reset_cost(), WARNING_COLOR)
	else:
		_limits_changed()
		_say("All stat points are free again.", LEVEL_COLOR)
		_progress_changed()


## Shows an earned title, or none for "".
func choose_title(achievement_id: String) -> void:
	if stats.record.set_title(achievement_id):
		_limits_changed()
		_progress_changed()


## Called by monsters whose hits poison, slow or stun.
func apply_status(effect: String, seconds: float, value: float = 0.0) -> void:
	if is_dead or _dash_left > 0.0:
		return
	statuses.apply(effect, seconds, value)
	FloatingText.spawn(self, effect.to_upper() + "!", STATUS_COLOR, 120.0, 20)


## The skill a button or key action uses ("skill" -> "spin_slash"), or "".
func skill_for_action(action: String) -> String:
	for skill_id in skills_data():
		if skills_data()[skill_id]["action"] == action:
			return skill_id
	return ""


func skill_unlocked(skill_id: String) -> bool:
	return skill_lock(skill_id) == ""


## Why a skill cannot be used yet: "Lv5" (level too low), "BOOK" (not learned
## from its book yet), or "" when it is open.
func skill_lock(skill_id: String) -> String:
	var skill: Dictionary = skills_data()[skill_id]
	if stats.level < int(skill["unlock_level"]):
		return "Lv%d" % int(skill["unlock_level"])
	if skill.has("book") and not stats.knows_skill(skill_id):
		return "BOOK"
	return ""


## True when the skill would work right now: unlocked, ready, enough stamina.
func can_use(skill_id: String) -> bool:
	if is_dead or statuses.is_active("stun") or not skills_data().has(skill_id):
		return false
	var skill: Dictionary = skills_data()[skill_id]
	return (
		skill_unlocked(skill_id)
		and float(_skill_cooldowns.get(skill_id, 0.0)) == 0.0
		and stamina >= float(skill["stamina"])
	)


## For the SPIN button.
func can_use_skill() -> bool:
	return can_use("spin_slash")


## Uses a skill from skills.json. Returns false if it could not be used now.
func use_skill(skill_id: String) -> bool:
	if not can_use(skill_id):
		return false
	var skill: Dictionary = skills_data()[skill_id]
	_skill_cooldowns[skill_id] = float(skill["cooldown"])
	stamina -= float(skill["stamina"])
	stamina_changed.emit(stamina, max_stamina)
	match skill["type"]:
		"spin":
			_skill_spin(skill)
		"strike":
			_skill_strike(skill)
		"buff":
			_skill_buff(skill)
		"slam":
			_skill_slam(skill)
	return true


## A quick dash with no damage taken on the way. Costs stamina.
func dash(direction: Vector2 = Vector2.ZERO) -> bool:
	var cost: float = float(_dash["stamina"])
	if is_dead or statuses.is_active("stun") or _dash_ready_in > 0.0 or stamina < cost:
		return false
	_dash_direction = direction.normalized() if direction != Vector2.ZERO else FACING_VECTORS[facing]
	_dash_left = float(_dash["seconds"])
	_dash_ready_in = float(_dash["cooldown"])
	stamina -= cost
	stamina_changed.emit(stamina, max_stamina)
	HitSpark.spawn(get_parent(), position, Color(0.85, 0.85, 0.8, 0.8), 10)
	_sfx("swing")
	return true


## All skills from skills.json.
static func skills_data() -> Dictionary:
	return GameData.table("skills")


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
	_announce(_count("potions_used"))
	_progress_changed()


func _attack() -> void:
	_attack_ready_in = attack_cooldown
	combo_step = combo_step % 3 + 1 if _combo_left > 0.0 else 1
	_combo_left = float(CombatRules.settings["combo_window_seconds"])
	var finisher: bool = combo_step == 3

	# Auto-aim: if an enemy is within reach, turn to it and swing at it.
	var aim: Vector2 = FACING_VECTORS[facing]
	var target: Node2D = _nearest_enemy(attack_range)
	if target != null:
		var to_target: Vector2 = target.global_position - global_position
		if to_target.length() > 1.0:
			aim = to_target.normalized()
			facing = _facing_for(aim)

	_slash.play(aim, finisher)
	_attack_animation_left = ATTACK_ANIMATION_SECONDS
	_sprite.stop()
	_sprite.play("attack_" + facing)
	var lunge: Tween = create_tween()
	lunge.tween_property(_sprite, "position", aim * 8.0, 0.06)
	lunge.tween_property(_sprite, "position", Vector2.ZERO, 0.1)

	var base_damage: int = stats.attack_damage()
	var knockback: float = 1.0
	if finisher:
		base_damage = roundi(base_damage * float(CombatRules.settings["combo_finisher_multiplier"]))
		knockback = float(CombatRules.settings["combo_finisher_knockback"])
	var hits: Array[Dictionary] = []
	for enemy in _alive_enemies():
		if _can_hit(enemy.global_position, aim):
			hits.append(_strike(enemy, base_damage, knockback))
	_after_strikes(hits)


## Spin Slash: hits every enemy around the warrior.
func _skill_spin(skill: Dictionary) -> void:
	_slash.play_spin()
	_sfx("skill")
	var base_damage: int = _skill_damage(skill)
	var hits: Array[Dictionary] = []
	for enemy in _alive_enemies():
		if enemy.global_position.distance_to(global_position) <= float(skill["radius"]):
			hits.append(_strike(enemy, base_damage))
	_after_strikes(hits, false)


## Power Strike: one heavy blow on the nearest enemy in reach.
func _skill_strike(skill: Dictionary) -> void:
	var target: Node2D = _nearest_enemy(float(skill["range"]))
	var aim: Vector2 = FACING_VECTORS[facing]
	if target != null and target.global_position.distance_to(global_position) > 1.0:
		aim = global_position.direction_to(target.global_position)
		facing = _facing_for(aim)
	_slash.play(aim, true)
	_attack_animation_left = ATTACK_ANIMATION_SECONDS
	_sprite.stop()
	_sprite.play("attack_" + facing)
	_sfx("skill")
	var hits: Array[Dictionary] = []
	if target != null:
		hits.append(_strike(target, _skill_damage(skill), 2.5))
		_shake_camera()
	_after_strikes(hits, false)


## War Cry: more damage for a while.
func _skill_buff(skill: Dictionary) -> void:
	_damage_bonus = float(skill["damage_bonus"])
	_damage_bonus_left = float(skill["seconds"])
	FloatingText.spawn(self, "WAR CRY!", Color(1.0, 0.45, 0.35), 130.0, 30)
	_sfx("levelup")


## Ground Slam: hits everything around and stuns it for a moment.
func _skill_slam(skill: Dictionary) -> void:
	_slash.play_spin()
	_shake_camera()
	_sfx("skill")
	var base_damage: int = _skill_damage(skill)
	var hits: Array[Dictionary] = []
	for enemy in _alive_enemies():
		if enemy.global_position.distance_to(global_position) <= float(skill["radius"]):
			var hit: Dictionary = _strike(enemy, base_damage, 1.5)
			hits.append(hit)
			if not hit["miss"]:
				enemy.call("apply_status", "stun", float(skill["stun_seconds"]))
	_after_strikes(hits, false)


func _skill_damage(skill: Dictionary) -> int:
	var multiplier: float = float(skill["damage_multiplier"]) * (1.0 + stats.skill_damage_bonus())
	return roundi(stats.attack_damage() * multiplier)


## One hit on one enemy. Miss, crit and the enemy's defense are worked out by
## CombatRules; the enemy only takes the result.
func _strike(enemy: Node2D, base_damage: int, knockback: float = 1.0) -> Dictionary:
	var boosted: int = roundi(base_damage * (1.0 + _damage_bonus))
	var hit: Dictionary = CombatRules.resolve_hit(
		boosted, stats.crit_chance(), int(enemy.get("defense")), float(enemy.get("evasion"))
	)
	if hit["miss"]:
		FloatingText.spawn(enemy, "MISS", MISS_COLOR, 80.0, 22)
		return hit
	enemy.call("take_damage", hit["damage"], global_position, hit["crit"], self, knockback)
	var spark_color := Color(1.0, 0.5, 0.2) if hit["crit"] else Color(1.0, 0.9, 0.5)
	HitSpark.spawn(enemy.get_parent(), enemy.position + Vector2(0, -20), spark_color, 14)
	return hit


## Sound, hit stop and vibration after a swing, by what it hit.
func _after_strikes(hits: Array[Dictionary], swing_sound: bool = true) -> void:
	var landed: bool = false
	var crit: bool = false
	for hit in hits:
		landed = landed or not hit["miss"]
		crit = crit or hit["crit"]
	if not landed:
		if swing_sound:
			_sfx("swing")
		return
	if swing_sound:
		_sfx("hit")
	var stop_key: String = "crit_hit_stop_seconds" if crit else "hit_stop_seconds"
	_hit_stop(float(CombatRules.settings[stop_key]))
	if crit:
		_vibrate(30)


## For the buttons: how much of an action's cooldown is left, from 1 down to 0.
func cooldown_left(action: String) -> float:
	if action == ACTION_ATTACK:
		return _attack_ready_in / maxf(attack_cooldown, 0.01)
	if action == ACTION_DASH:
		return _dash_ready_in / maxf(float(_dash["cooldown"]), 0.01)
	var skill_id: String = skill_for_action(action)
	if skill_id == "":
		return 0.0
	var cooldown: float = maxf(float(skills_data()[skill_id]["cooldown"]), 0.01)
	return float(_skill_cooldowns.get(skill_id, 0.0)) / cooldown


## True while War Cry (or another damage boost) is on.
func has_damage_bonus() -> bool:
	return _damage_bonus > 0.0


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
	statuses.clear()
	var fall: Tween = create_tween()
	fall.tween_property(_sprite, "rotation", PI / 2.0 * (-1.0 if facing == "left" else 1.0), 0.3)
	fall.tween_property(_sprite, "modulate:a", 0.0, 0.6)
	await get_tree().create_timer(_respawn_seconds).timeout
	_respawn()


func _respawn() -> void:
	global_position = _spawn_position
	hp = max_hp
	stamina = max_stamina
	is_dead = false
	_invincible_left = 0.0
	_dash_left = 0.0
	_sprite.rotation = 0.0
	_sprite.self_modulate.a = 1.0
	_sprite.modulate = Color.WHITE
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	respawned.emit()
	_announce(_count("deaths"))
	_progress_changed()


func _progress_changed() -> void:
	SaveFile.save_data(stats.to_dict())
	stats_changed.emit()


## After the gear changed: health limits, look, save.
func _gear_changed() -> void:
	_limits_changed()
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
	_dash = rules["dash"]
	move_speed = float(rules["move_speed"])
	attack_range = float(rules["attack_range"])
	attack_cooldown = float(rules["attack_cooldown"])
	max_stamina = float(rules["max_stamina"])
	_stamina_regen = float(rules["stamina_regen_per_second"])
	_regen_delay = float(rules["regen_delay_seconds"])
	_regen_per_second = float(rules["regen_hp_per_second"])
	_respawn_seconds = float(rules["respawn_seconds"])
	_hit_invincible_seconds = float(rules["hit_invincible_seconds"])


## After gear, stat points or the title changed: the health and stamina limits.
func _limits_changed() -> void:
	max_hp = stats.max_hp()
	hp = mini(hp, max_hp)
	max_stamina = stats.max_stamina()
	stamina = minf(stamina, max_stamina)
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)


func _count(counter: String, amount: int = 1) -> Array:
	return stats.record.count(counter, amount, stats.level)


## Tells the player about achievements just earned.
func _announce(earned: Array) -> void:
	if earned.is_empty():
		return
	for achievement_id in earned:
		var achievement: Dictionary = AchievementRecord.list[achievement_id]
		_say(
			'Achievement: %s! Title "%s".' % [achievement["name"], achievement["title"]],
			ACHIEVEMENT_COLOR
		)
	FloatingText.spawn(self, "ACHIEVEMENT!", ACHIEVEMENT_COLOR, 140.0, 28)
	_sfx("levelup")
	_limits_changed()


## A skill book teaches its skill once the level is high enough.
func _read_book(index: int, item: Dictionary) -> void:
	var skill_id: String = item["teaches"]
	var skill: Dictionary = skills_data()[skill_id]
	var needed_level: int = int(skill["unlock_level"])
	if stats.knows_skill(skill_id):
		_say("You already know %s." % skill["name"], WARNING_COLOR)
	elif stats.level < needed_level:
		_say("Reach level %d to learn %s." % [needed_level, skill["name"]], WARNING_COLOR)
	else:
		stats.take_from_bag(index)
		stats.learn_skill(skill_id)
		FloatingText.spawn(self, "NEW SKILL!", LEVEL_COLOR, 120.0, 30)
		_sfx("levelup")
		_say("You learned %s!" % skill["name"], LEVEL_COLOR)
		_announce(_count("books_read"))
		_progress_changed()


## A Rebirth Scroll gives every stat point back for free.
func _read_rebirth_scroll(index: int) -> void:
	if stats.spent_points() == 0:
		_say("There are no stat points to give back.", WARNING_COLOR)
		return
	stats.take_from_bag(index)
	stats.reset_stats(false)
	_limits_changed()
	_say("All stat points are free again.", LEVEL_COLOR)
	_progress_changed()


## Pressing a locked skill says what opens it.
func _explain_lock(skill_id: String) -> void:
	var lock: String = skill_lock(skill_id)
	var skill_name: String = skills_data()[skill_id]["name"]
	if lock == "BOOK":
		_say("Learn %s from its book first." % skill_name, WARNING_COLOR)
	elif lock != "":
		_say("%s opens at level %s." % [skill_name, lock.trim_prefix("Lv")], WARNING_COLOR)


func _drop_on_ground(item_id: String) -> void:
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", "item")
	pickup.set("item_id", item_id)
	pickup.set("lifetime", DROPPED_ITEM_SECONDS)
	pickup.set("pickup_delay", 1.0)
	pickup.position = position + FACING_VECTORS[facing] * DROP_DISTANCE
	get_parent().call_deferred("add_child", pickup)
	_say("Dropped %s." % _item_name(item_id))


## Freezes the game for a blink when a hit lands, so hits feel heavy. The timer
## ignores the slowed time; Engine itself restores the speed, so nothing is
## left slowed if this node goes away meanwhile.
func _hit_stop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	Engine.time_scale = 0.08
	var timer: SceneTreeTimer = get_tree().create_timer(seconds, true, false, true)
	timer.timeout.connect(Engine.set.bind("time_scale", 1.0))


func _vibrate(milliseconds: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(milliseconds)


func _update_target_marker() -> void:
	if _target_marker == null or not is_instance_valid(_target_marker):
		return
	var target: Node2D = _nearest_enemy(attack_range * TARGET_MARKER_REACH)
	_target_marker.visible = target != null
	if target != null:
		_target_marker.global_position = target.global_position


## Counts statuses down; poison hurts even through the blink after a hit.
func _tick_statuses(delta: float) -> void:
	var poison: int = statuses.update(delta)
	if poison <= 0 or is_dead:
		return
	hp = maxi(hp - poison, 0)
	_seconds_since_damage = 0.0
	hp_changed.emit(hp, max_hp)
	FloatingText.spawn(self, str(poison), Color(0.5, 0.9, 0.3), 90.0, 20)
	if hp == 0:
		_die()


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
