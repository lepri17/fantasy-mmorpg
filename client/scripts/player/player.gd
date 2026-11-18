extends "res://scripts/player/player_base.gd"
## The hero, of any class: movement, attack with auto-aim (a swing, or a shot
## for the mage and the archer), skills, dash, statuses, health / stamina,
## death and respawn, arriving on maps, auto hunt. Its state and what it does
## with items and in town are in player_base.gd, which this extends. Progress
## (class, level, XP, gold, bag, gear) lives in PlayerStats.
##
## Input goes through actions only (move_*, attack, skill, skill_2..5, dash,
## use_potion, auto_hunt), so the touch controls drive the same code as the
## keyboard. Skills come from res://data/skills.json; each names its action.

const SkyClock = preload("res://scripts/world/sky.gd")
const Spells = preload("res://scripts/player/spells.gd")
const AutoPilot = preload("res://scripts/player/auto_pilot.gd")
const ACTION_AUTO := "auto_hunt"
## A tree hides the warrior when its trunk is this close below him (Q12).
const TREE_COVER := Vector2(70, 150)
const SILHOUETTE_SHADER := """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.45, 0.68, 1.0, 0.55);
void fragment() {
	COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);
}
"""

## Auto hunt and walking to a quest's target (auto_pilot.gd).
var auto = AutoPilot.new()
var _light: PointLight2D
var _silhouette: AnimatedSprite2D
var _silhouette_check: float = 0.0
## Time for the pulse of the job advancement glow.
var _aura_time: float = 0.0


func _ready() -> void:
	add_to_group("player")
	auto.hero = self
	stats.from_dict(SaveFile.load_data())
	_load_tuning()
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
	_make_light()
	_make_silhouette()


## After the job advancement, a soft ring in the class's colour under the hero
## (drawn under the sprite, which is a child).
func _draw() -> void:
	if not stats.advanced:
		return
	var color: Color = ClassDb.advanced_color(stats.class_id)
	var pulse: float = 0.5 + 0.5 * sin(_aura_time * 3.0)
	draw_set_transform(Vector2(0.0, 2.0), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 30.0, Color(color, 0.14))
	var ring := Color(color, 0.5 + 0.3 * pulse)
	draw_arc(Vector2.ZERO, 31.0 + pulse * 3.0, 0.0, TAU, 40, ring, 3.0, true)


func _physics_process(delta: float) -> void:
	if stats.advanced:
		_aura_time += delta
		queue_redraw()
	_update_silhouette(delta)
	if is_dead:
		return

	_tick_statuses(delta)
	if is_dead:
		return
	_auto_drink(delta)
	var stunned: bool = statuses.is_active("stun")
	var direction: Vector2 = Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	if direction != Vector2.ZERO and not auto.walk_goal.is_empty():
		auto.walk_goal = {}  # moving by hand ends a walk
	if stunned:
		direction = Vector2.ZERO
	elif direction == Vector2.ZERO and auto.active():
		direction = auto.steer(delta)
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
	_crit_bonus_left = maxf(0.0, _crit_bonus_left - delta)
	if _crit_bonus_left == 0.0:
		_crit_bonus = 0.0
	_guard_left = maxf(0.0, _guard_left - delta)
	if _guard_left == 0.0:
		_guard = 0.0
	for skill_id in _skill_cooldowns:
		_skill_cooldowns[skill_id] = maxf(0.0, float(_skill_cooldowns[skill_id]) - delta)
	if stunned:
		return
	if Input.is_action_pressed(ACTION_ATTACK) and _attack_ready_in == 0.0:
		_attack()
	for skill_id in class_skills():
		if Input.is_action_just_pressed(skills_data()[skill_id]["action"]):
			if not use_skill(skill_id):
				_explain_lock(skill_id)
	if Input.is_action_just_pressed(ACTION_DASH):
		dash(direction)
	if Input.is_action_just_pressed(ACTION_POTION):
		use_potion()
	if Input.is_action_just_pressed(ACTION_AUTO):
		toggle_auto_hunt()


## Called by enemies.
func take_damage(amount: int) -> void:
	if is_dead or _invincible_left > 0.0 or _dash_left > 0.0:
		return
	if _guard > 0.0:
		amount = maxi(1, roundi(amount * (1.0 - _guard)))
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


## Puts the warrior on a map (game.gd): where he arrives, where he gets back
## up after falling, and how far the camera may go.
func enter_map(map_id: String, point: Vector2, respawn_point: Vector2, limits: Rect2) -> void:
	global_position = point
	auto.on_map_changed()
	velocity = Vector2.ZERO
	_spawn_position = respawn_point
	camera_limits = limits
	_apply_camera_limits()
	_camera.reset_smoothing()
	if stats.map_id != map_id:
		stats.map_id = map_id
		_progress_changed()


## G3: a soft light around the warrior; game.gd turns it up when it is dark.
func set_light(darkness: float) -> void:
	_light.enabled = darkness > 0.05
	_light.energy = darkness * 0.5


## Gets up at once (the death screen's button), instead of after the wait.
func revive() -> void:
	if is_dead:
		_respawn()


## Called by monsters whose hits poison, slow or stun.
func apply_status(effect: String, seconds: float, value: float = 0.0) -> void:
	if is_dead or _dash_left > 0.0:
		return
	statuses.apply(effect, seconds, value)
	FloatingText.spawn(self, effect.to_upper() + "!", STATUS_COLOR, 120.0, 20)


## The skill a button or key action uses ("skill" -> "spin_slash"), or "".
func skill_for_action(action: String) -> String:
	for skill_id in class_skills():
		if skills_data()[skill_id]["action"] == action:
			return skill_id
	return ""


func skill_unlocked(skill_id: String) -> bool:
	return skill_lock(skill_id) == ""


## Why a skill cannot be used yet: "Lv5" (level too low), "BOOK" (not learned
## from its book yet), "JOB" (needs the job advancement), "CLASS" (another
## class's skill), or "" when it is open.
func skill_lock(skill_id: String) -> String:
	var skill: Dictionary = skills_data()[skill_id]
	if skill.get("class", ClassDb.DEFAULT) != stats.class_id:
		return "CLASS"
	if skill.get("job", false) and not stats.advanced:
		return "JOB"
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


## For the first skill button (SPIN, FIRE or MULTI).
func can_use_skill() -> bool:
	return can_use(skill_for_action("skill"))


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
		_:
			Spells.cast(self, skill)
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
	var basic: Dictionary = ClassDb.info(stats.class_id)["attack"]
	if basic["type"] == "shot":
		_shoot_attack(aim, finisher, basic)
		return

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
	Burst.spawn(self, Vector2(0, -24), Color(0.6, 0.95, 1.0), 30, 240.0)
	_sfx("skill")
	var base_damage: int = skill_damage(skill)
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
		hits.append(_strike(target, skill_damage(skill), 2.5))
		_shake_camera()
	_after_strikes(hits, false)


## Mage and archer: the basic attack is a shot (a bolt or an arrow) instead of
## a swing. The third shot of a combo hits harder, like the warrior's finisher.
func _shoot_attack(aim_direction: Vector2, finisher: bool, basic: Dictionary) -> void:
	_attack_animation_left = ATTACK_ANIMATION_SECONDS
	_sprite.stop()
	_sprite.play("attack_" + facing)
	var damage: int = stats.attack_damage()
	if finisher:
		damage = roundi(damage * float(CombatRules.settings["combo_finisher_multiplier"]))
	var rgb: Array = basic["color"]
	Spells.shoot(
		self,
		aim_direction,
		{
			"kind": basic["kind"],
			"speed": float(basic["speed"]),
			"reach": attack_range + 60.0,
			"damage": damage,
			"radius": float(basic["radius"]),
			"color": Color(rgb[0], rgb[1], rgb[2]),
			"knockback": 1.6 if finisher else 0.6,
		}
	)
	_sfx("swing")


## War Cry (more damage) and Eagle Eye (more crits) for a while.
func _skill_buff(skill: Dictionary) -> void:
	if skill.has("damage_bonus"):
		_damage_bonus = float(skill["damage_bonus"])
		_damage_bonus_left = float(skill["seconds"])
	if skill.has("crit_bonus"):
		_crit_bonus = float(skill["crit_bonus"])
		_crit_bonus_left = float(skill["seconds"])
	FloatingText.spawn(self, skill["name"].to_upper() + "!", Color(1.0, 0.45, 0.35), 130.0, 30)
	_sfx("levelup")


## Ground Slam: hits everything around and stuns it for a moment.
func _skill_slam(skill: Dictionary) -> void:
	_slash.play_spin()
	Burst.spawn(self, Vector2(0, -6), Color(0.72, 0.56, 0.38), 34, 200.0)
	_shake_camera()
	_sfx("skill")
	var base_damage: int = skill_damage(skill)
	var hits: Array[Dictionary] = []
	for enemy in _alive_enemies():
		if enemy.global_position.distance_to(global_position) <= float(skill["radius"]):
			var hit: Dictionary = _strike(enemy, base_damage, 1.5)
			hits.append(hit)
			if not hit["miss"]:
				enemy.call("apply_status", "stun", float(skill["stun_seconds"]))
	_after_strikes(hits, false)


func skill_damage(skill: Dictionary) -> int:
	var multiplier: float = float(skill["damage_multiplier"]) * (1.0 + stats.skill_damage_bonus())
	return roundi(stats.attack_damage() * multiplier)


## One hit on one enemy. Miss, crit and the enemy's defense are worked out by
## CombatRules; the enemy only takes the result.
func _strike(enemy: Node2D, base_damage: int, knockback: float = 1.0) -> Dictionary:
	var boosted: int = roundi(base_damage * (1.0 + _damage_bonus))
	var hit: Dictionary = CombatRules.resolve_hit(
		boosted,
		stats.crit_chance() + _crit_bonus,
		int(enemy.get("defense")),
		float(enemy.get("evasion"))
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


## U5: AUTO starts (or stops) hunting around where the hero stands.
func toggle_auto_hunt() -> void:
	if auto.hunting or not auto.walk_goal.is_empty():
		auto.stop()
		_say("Auto hunt off.")
	elif auto.start_hunt():
		_say("Auto hunt on. Move to take over, or tap AUTO to stop.", QUEST_COLOR)
	else:
		_say("Nothing to hunt here.", WARNING_COLOR)


## U6: walks to where the quest wants the hero (tap it in the quest list).
func walk_to_quest(quest_id: String) -> void:
	if auto.walk_to_quest(quest_id):
		_say("On the way: %s." % QuestLog.list[quest_id]["name"], QUEST_COLOR)
	else:
		_say("No way to walk there from here.", WARNING_COLOR)


## True while War Cry (or another damage boost) is on.
func has_damage_bonus() -> bool:
	return _damage_bonus > 0.0


# --- for spells.gd: the mage's and the archer's skills, and every hero shot


## Turns to the nearest enemy within max_distance (or keeps the facing), plays
## the attack animation, and returns the direction to cast or shoot in.
func aim(max_distance: float) -> Vector2:
	var direction: Vector2 = FACING_VECTORS[facing]
	var target: Node2D = _nearest_enemy(max_distance)
	if target != null and target.global_position.distance_to(global_position) > 1.0:
		direction = global_position.direction_to(target.global_position)
		facing = _facing_for(direction)
	_attack_animation_left = ATTACK_ANIMATION_SECONDS
	_sprite.stop()
	_sprite.play("attack_" + facing)
	return direction


## Where a spell lands: on the nearest enemy within max_distance, or a little
## ahead of the hero.
func target_point(max_distance: float) -> Vector2:
	var target: Node2D = _nearest_enemy(max_distance)
	if target != null:
		return target.global_position
	return global_position + FACING_VECTORS[facing] * 140.0


## Alive enemies within radius of a point.
func enemies_near(point: Vector2, radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for enemy in _alive_enemies():
		if enemy.global_position.distance_to(point) <= radius:
			result.append(enemy)
	return result


## One hit on each enemy (status: {"effect", "seconds", "value"} on the ones
## hit), then the hit sound and hit stop. Returns the hits.
func hit_all(
	enemies: Array, damage: int, knockback: float = 1.0, status: Dictionary = {}, sound := false
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.get("is_dead"):
			continue
		var hit: Dictionary = _strike(enemy, damage, knockback)
		hits.append(hit)
		if not hit["miss"] and not status.is_empty() and not enemy.get("is_dead"):
			var value: float = float(status.get("value", 0.0))
			enemy.call("apply_status", status["effect"], float(status["seconds"]), value)
	_after_strikes(hits, sound)
	return hits


## A shot (hero_shot.gd) reached an enemy: one hit, or a burst all round it.
func shot_hit(shot: Node2D, enemy: Node2D) -> void:
	var blast: float = float(shot.get("blast_radius"))
	var targets: Array = [enemy]
	if blast > 0.0:
		targets = enemies_near(enemy.global_position, blast)
		Burst.spawn(get_parent(), enemy.position + Vector2(0, -20), Color(1.0, 0.55, 0.2), 26, 220.0)
	hit_all(targets, int(shot.get("damage")), float(shot.get("knockback")), {}, true)


## Mana Shield: cut is the part of each hit's damage taken away (0..1).
func set_guard(cut: float, seconds: float) -> void:
	_guard = clampf(cut, 0.0, 0.9)
	_guard_left = seconds


func effect_ring() -> void:
	_slash.play_spin()


func effect_swing(direction: Vector2) -> void:
	_slash.play(direction, true)


func shake() -> void:
	_shake_camera()


func play_sound(sound: String) -> void:
	_sfx(sound)


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
	auto.stop()
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
	if is_dead:  # not already up from the death screen's button
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


## Reads speed, ranges, stamina, dash and regeneration from character.json,
## with the class's own numbers (classes.json) where it has them.
func _load_tuning() -> void:
	_dash = stats.rule("dash")
	move_speed = float(stats.rule("move_speed"))
	attack_range = float(stats.rule("attack_range"))
	attack_cooldown = float(stats.rule("attack_cooldown"))
	max_stamina = float(stats.rule("max_stamina"))
	_stamina_regen = float(stats.rule("stamina_regen_per_second"))
	_regen_delay = float(stats.rule("regen_delay_seconds"))
	_regen_per_second = float(stats.rule("regen_hp_per_second"))
	_respawn_seconds = float(stats.rule("respawn_seconds"))
	_hit_invincible_seconds = float(stats.rule("hit_invincible_seconds"))


## Auto potion: below the chosen part of max HP, drink a red potion (with a
## short wait between drinks so it does not empty the bag at once).
func _auto_drink(delta: float) -> void:
	_auto_potion_ready_in = maxf(0.0, _auto_potion_ready_in - delta)
	if stats.auto_potion <= 0 or _auto_potion_ready_in > 0.0 or stats.potions <= 0:
		return
	if hp * 100 <= max_hp * stats.auto_potion:
		_auto_potion_ready_in = float(PlayerStats.rules["auto_potion_seconds"])
		use_potion()


## Pressing a locked skill says what opens it.
func _explain_lock(skill_id: String) -> void:
	var lock: String = skill_lock(skill_id)
	var skill_name: String = skills_data()[skill_id]["name"]
	if lock == "BOOK":
		_say("Learn %s from its book first." % skill_name, WARNING_COLOR)
	elif lock == "JOB":
		_say("%s opens with the job advancement." % skill_name, WARNING_COLOR)
	elif lock.begins_with("Lv"):
		_say("%s opens at level %s." % [skill_name, lock.trim_prefix("Lv")], WARNING_COLOR)


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


func _shake_camera() -> void:
	var shake: Tween = create_tween()
	for offset in [Vector2(6, -4), Vector2(-5, 3), Vector2(3, 2), Vector2.ZERO]:
		shake.tween_property(_camera, "offset", offset, 0.04)


func _make_light() -> void:
	_light = PointLight2D.new()
	_light.texture = SkyClock.light_texture()
	_light.texture_scale = 2.6
	_light.color = Color(1.0, 0.86, 0.66)
	_light.position = Vector2(0, -30)
	_light.enabled = false
	add_child(_light)


## Q12: a see-through, single-colour copy of the warrior drawn over everything,
## shown while he walks behind a tree.
func _make_silhouette() -> void:
	_silhouette = AnimatedSprite2D.new()
	_silhouette.sprite_frames = _sprite.sprite_frames
	_silhouette.scale = _sprite.scale
	_silhouette.offset = _sprite.offset
	_silhouette.z_index = 20
	var shader := Shader.new()
	shader.code = SILHOUETTE_SHADER
	var flat := ShaderMaterial.new()
	flat.shader = shader
	_silhouette.material = flat
	_silhouette.visible = false
	add_child(_silhouette)


func _update_silhouette(delta: float) -> void:
	_silhouette_check -= delta
	if _silhouette_check <= 0.0:
		_silhouette_check = 0.1
		_silhouette.visible = not is_dead and _behind_tree()
	if _silhouette.visible:
		_silhouette.animation = _sprite.animation
		_silhouette.frame = _sprite.frame
		_silhouette.flip_h = _sprite.flip_h


func _behind_tree() -> bool:
	for tree in get_tree().get_nodes_in_group("trees"):
		var gap: Vector2 = tree.global_position - global_position
		if gap.y > 0.0 and gap.y < TREE_COVER.y and absf(gap.x) < TREE_COVER.x:
			return true
	return false


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
