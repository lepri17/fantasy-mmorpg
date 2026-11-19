extends CharacterBody2D
## A slime. It wanders around its spawn point, chases the warrior when he comes
## close, bumps into him for damage, gets knocked back when hit, drops loot and
## gives XP when it dies, and comes back a few seconds later.
##
## Every kind of slime is this scene with a different monster_id; the numbers
## come from res://data/monsters.json.

const FloatingText = preload("res://scripts/ui/floating_text.gd")
const GameData = preload("res://scripts/data/game_data.gd")
const CombatRules = preload("res://scripts/combat/combat_rules.gd")
const StatusEffects = preload("res://scripts/combat/status_effects.gd")
const Telegraph = preload("res://scripts/combat/telegraph.gd")
const CRIT_COLOR := Color(1.0, 0.55, 0.2)
const MISS_COLOR := Color(0.8, 0.85, 0.95)
const PICKUP_SCENE := preload("res://scenes/items/pickup.tscn")
const ItemDb := preload("res://scripts/items/item_db.gd")
const Projectile := preload("res://scripts/combat/projectile.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const MonsterMoves := preload("res://scripts/enemies/monster_moves.gd")
const CROWN := preload("res://assets/monsters/slime/crown.png")
const SLIME_SCENE_PATH := "res://scenes/enemies/slime.tscn"
const BAR_HEIGHT := 56.0
## How often the path to a moving target is worked out again.
const PATH_REFRESH_SECONDS := 0.25

const KNOCKBACK_SPEED := 240.0
const KNOCKBACK_DECAY := 1400.0
const WANDER_RADIUS := 90.0
## A slime that gets this far from home gives up the chase and walks back.
const LEASH_RADIUS := 480.0

## Chance of spawning as an elite; below 0 = use combat.json. Tests set it to 0.
static var elite_chance_override: float = -1.0

## Which entry of monsters.json this is.
@export var monster_id: String = "green_slime"

# Filled from monsters.json in _ready.
var display_name: String = "Slime"
var level: int = 1
var max_hp: int = 40
var move_speed: float = 70.0
## The slime starts chasing when the warrior is closer than this.
var detect_radius: float = 260.0
## The slime attacks when the warrior is closer than this.
var attack_range: float = 48.0
var attack_damage: int = 6
## Damage from each hit goes down by this much (never below 1).
var defense: int = 0
## Chance (0..1) that the warrior's hit misses.
var evasion: float = 0.0
var attack_cooldown: float = 1.2
var respawn_seconds: float = 5.0
var xp_reward: int = 20
var gold_min: int = 1
var gold_max: int = 5
## [{"item": item id, "chance": 0..1}, ...]
var drops: Array = []
## {"chance", "items"}: gear that can drop, with a random rarity.
var gear_drops: Dictionary = {}
## Shoots from afar instead of biting, or {}: {"keep_distance", "projectile_speed", "on_hit"}.
var ranged: Dictionary = {}
## C9: a boss, or {}: {"enrage_at", "enrage_speed", "rarity_rolls", "summon": {...}}.
var boss: Dictionary = {}
## How big it is drawn and how wide its body is (monsters.json "scale").
var size_scale: float = 1.0
## False for monsters that should not come back: a boss's summons, invaders.
var respawns: bool = true
## Status put on the warrior by a landed hit, or {}: {"status", "chance", "seconds", "value"}.
var on_hit: Dictionary = {}
## How much of a push it shrugs off: 0 = all of it moves it, 1 = none (bosses).
var knockback_resist: float = 0.0
## A telegraphed slam instead of every Nth attack, or {}:
## {"every", "radius", "warning_seconds", "damage_multiplier"}.
var special: Dictionary = {}
## Stun (and any other effect) on this slime.
var statuses = StatusEffects.new()
## Color multiplier, used to tell the kinds of slime apart.
var tint: Color = Color.WHITE
## A charge (Bramble Boar): a lane fills up on the ground, then it rushes along it.
var charge: Dictionary = {}
## Fading out and back a little way off when the hero comes close (Lantern Wisp).
var blink: Dictionary = {}
## Digging in, moving under the ground and bursting out by the hero (Rootling).
var burrow: Dictionary = {}
## How many pixels it floats up and down (Lantern Wisp).
var hover: float = 0.0
## True while it is under the ground: it cannot be seen or hit.
var burrowed: bool = false
## Elites have more HP, damage, XP and loot, glow, and are a bit bigger.
var is_elite: bool = false
## The open world's moves (monster_moves.gd: shell, leap, split), if it has any.
var moves = null

var hp: int = 0
var is_dead: bool = false

var _attack_ready_in: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO
var _knockback: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _is_returning: bool = false
var _player: Node2D = null
## Attacker -> damage it has done: the slime goes after whoever hurt it most.
var _threat: Dictionary = {}
var _sprite_scale: Vector2 = Vector2.ONE
var _attack_count: int = 0
var _casting_left: float = 0.0
var _glow: Tween = null
var _agent: NavigationAgent2D = null
var _path_refresh: float = 0.0
var _enraged: bool = false
var _summon_left: float = 0.0
var _minions: Array = []
var _crown: Sprite2D = null
var _move_ready_in: float = 0.0  # until its charge, blink or dig can be used again
var _rush: Vector2 = Vector2.ZERO
var _rush_left: float = 0.0
var _rush_hit: bool = false
var _dig_left: float = 0.0
var _hover_time: float = 0.0
var _sprite_y: float = 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _hp_bar = $HpBar


func _ready() -> void:
	add_to_group("enemies")
	_agent = NavigationAgent2D.new()
	_agent.path_desired_distance = 10.0
	_agent.target_desired_distance = 8.0
	_agent.radius = 16.0
	add_child(_agent)
	_load_monster_data()
	_apply_size()
	_roll_elite()
	var data: Dictionary = GameData.table("monsters").get(monster_id, {})
	if MonsterMoves.wanted(data):
		moves = MonsterMoves.new()
		moves.name = "Moves"
		add_child(moves)
		moves.setup(self, data)
	hp = max_hp
	_spawn_position = global_position
	_wander_target = global_position
	_sprite.modulate = tint
	_sprite_y = _sprite.position.y
	_hp_bar.set_label("Lv.%d %s" % [level, display_name])
	_hp_bar.set_values(hp, max_hp)
	_sprite.play("idle")
	_sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_attack_ready_in = maxf(0.0, _attack_ready_in - delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	statuses.update(delta)
	_casting_left = maxf(0.0, _casting_left - delta)
	_move_ready_in = maxf(0.0, _move_ready_in - delta)
	if _enraged:
		_summon_tick(delta)
	var stunned: bool = statuses.is_active("stun")
	_sprite.speed_scale = 0.0 if stunned else 1.0
	_float(delta)
	if moves != null:
		moves.tick(delta)

	var movement := Vector2.ZERO
	var target: Node2D = _chase_target()
	if _rush_left > 0.0:
		movement = _rush_step(delta, target)
	elif moves != null and moves.busy():
		movement = moves.step(delta)
	elif burrowed:
		movement = _dig_toward(target, delta)
	elif stunned or _casting_left > 0.0:
		pass  # stays put: stunned, or winding up a slam
	elif target == null:
		movement = _wander(delta)
	else:
		var distance: float = global_position.distance_to(target.global_position)
		if _try_move(target, distance):
			pass  # started its charge, blink or dig
		elif not ranged.is_empty():
			movement = _ranged_movement(target, distance, delta)
		elif distance > attack_range:
			var speed: float = move_speed * statuses.speed_factor()
			movement = _steer_to(target.global_position, delta) * speed
		elif _attack_ready_in == 0.0:
			_attack(target)

	velocity = movement + _knockback
	move_and_slide()


## Called by the warrior's attacks, after miss / crit / defense were worked out
## (see CombatRules.resolve_hit). from_position is where the hit came from.
func take_damage(
	amount: int,
	from_position: Vector2 = Vector2.ZERO,
	crit: bool = false,
	attacker: Node = null,
	knockback: float = 1.0
) -> void:
	if is_dead:
		return
	if moves != null:
		amount = moves.damage_taken(amount)  # less while it hides in its shell
	hp = maxi(hp - amount, 0)
	_hp_bar.set_values(hp, max_hp)
	if crit:
		FloatingText.spawn(self, "%d!" % amount, CRIT_COLOR, 90.0, 36)
	else:
		FloatingText.spawn(self, str(amount), Color(1.0, 0.95, 0.4))
	if attacker != null:
		_threat[attacker] = int(_threat.get(attacker, 0)) + amount
	if from_position != Vector2.ZERO:
		_knockback = _push(from_position, knockback)
	if hp == 0:
		_die()
		return
	if not boss.is_empty() and not _enraged and hp <= max_hp * float(boss.get("enrage_at", 0.5)):
		_enrage()
	_sprite.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(_sprite, "modulate", tint, 0.2)


## The radius of its body (bigger for bosses), for reaching it with a swing.
func body_radius() -> float:
	var circle := _collision.shape as CircleShape2D
	return circle.radius if circle != null else 16.0 * size_scale


## A gentle push away from a hit: less on elites, none on bosses, and never
## farther than combat.json's knockback_max_distance.
func _push(from_position: Vector2, knockback: float) -> Vector2:
	var settings: Dictionary = CombatRules.settings
	var speed: float = float(settings.get("knockback_speed", KNOCKBACK_SPEED)) * knockback
	speed *= 1.0 - clampf(knockback_resist, 0.0, 1.0)
	var farthest: float = float(settings.get("knockback_max_distance", 48.0))
	var limit: float = sqrt(2.0 * KNOCKBACK_DECAY * farthest)
	return (global_position - from_position).normalized() * minf(speed, limit)


## The warrior, if the slime should be chasing him right now. Otherwise null.
func _chase_target() -> Node2D:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
	var distance_from_home: float = global_position.distance_to(_spawn_position)
	if distance_from_home > LEASH_RADIUS:
		_is_returning = true
	elif distance_from_home <= WANDER_RADIUS:
		_is_returning = false
	if _is_returning:
		_threat.clear()
		return null
	var hated: Node2D = _most_threatening()
	if hated != null:
		return hated
	if _player == null or _player.get("is_dead"):
		return null
	if _player.global_position.distance_to(global_position) > detect_radius:
		return null
	return _player


## The living attacker that did the most damage, if any.
func _most_threatening() -> Node2D:
	var best: Node2D = null
	var best_threat: int = 0
	for attacker in _threat.keys():
		if not is_instance_valid(attacker) or attacker.get("is_dead"):
			_threat.erase(attacker)
			continue
		if int(_threat[attacker]) > best_threat:
			best = attacker
			best_threat = int(_threat[attacker])
	return best


## Q1: the way to walk to reach a point, along the map's navigation path around
## trees and rocks (game_map.gd bakes it), or straight there while there is none.
func _steer_to(point: Vector2, delta: float) -> Vector2:
	_path_refresh -= delta
	if _path_refresh <= 0.0:
		_path_refresh = PATH_REFRESH_SECONDS
		_agent.target_position = point
	var next: Vector2 = _agent.get_next_path_position()
	if _agent.is_navigation_finished() or next.distance_to(global_position) < 1.0:
		return global_position.direction_to(point)
	return global_position.direction_to(next)


## C7: a ranged monster keeps its distance. It comes closer when out of range,
## backs off when the warrior gets too near, and shoots whenever it can.
func _ranged_movement(target: Node2D, distance: float, delta: float) -> Vector2:
	var speed: float = move_speed * statuses.speed_factor()
	if distance <= attack_range and _attack_ready_in == 0.0:
		_shoot(target)
	if distance > attack_range:
		return _steer_to(target.global_position, delta) * speed
	if distance < float(ranged.get("keep_distance", 0.0)):
		return target.global_position.direction_to(global_position) * speed
	return Vector2.ZERO


func _shoot(target: Node2D) -> void:
	_attack_ready_in = attack_cooldown
	_sprite.play("attack")
	var shot: Area2D = Projectile.new()
	shot.position = position
	shot.direction = global_position.direction_to(target.global_position)
	shot.speed = float(ranged.get("projectile_speed", 260.0))
	shot.damage = attack_damage
	shot.on_hit = ranged.get("on_hit", {})
	if ranged.has("color"):  # e.g. the Crag Imp's pebbles
		var rgb: Array = ranged["color"]
		shot.color = Color(rgb[0], rgb[1], rgb[2])
	get_parent().add_child(shot)


## Slow, aimless walking around the spawn point. Returns the velocity to use.
func _wander(delta: float) -> Vector2:
	if global_position.distance_to(_spawn_position) > WANDER_RADIUS:
		return global_position.direction_to(_spawn_position) * move_speed
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.5, 3.5)
		_wander_target = global_position
		if randf() < 0.6:
			var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			_wander_target = _spawn_position + offset * WANDER_RADIUS * 0.7
	if global_position.distance_to(_wander_target) < 4.0:
		return Vector2.ZERO
	return global_position.direction_to(_wander_target) * move_speed * 0.5


## Called by the warrior's Ground Slam (stun) and anything else that adds effects.
func apply_status(effect: String, seconds: float, value: float = 0.0) -> void:
	if is_dead:
		return
	statuses.apply(effect, seconds, value)
	FloatingText.spawn(self, effect.to_upper() + "!", Color(1.0, 0.95, 0.6), 100.0, 20)


func _attack(target: Node2D) -> void:
	_attack_ready_in = attack_cooldown
	_attack_count += 1
	_sprite.play("attack")
	if not special.is_empty() and _attack_count % int(special["every"]) == 0:
		_start_slam()
		return
	var target_stats = target.get("stats")
	var target_defense: int = target_stats.defense() if target_stats != null else 0
	var target_evasion: float = target_stats.evasion() if target_stats != null else 0.0
	var hit: Dictionary = CombatRules.resolve_hit(attack_damage, 0.0, target_defense, target_evasion)
	if hit["miss"]:
		FloatingText.spawn(target, "MISS", MISS_COLOR, 100.0, 22)
		return
	target.call("take_damage", hit["damage"])
	if not on_hit.is_empty() and randf() < float(on_hit["chance"]):
		target.call(
			"apply_status", on_hit["status"], float(on_hit["seconds"]), float(on_hit.get("value", 0.0))
		)


## Telegraphed slam: a red circle fills up, then everything inside gets hit hard.
func _start_slam() -> void:
	_area_attack(
		float(special["radius"]),
		float(special["warning_seconds"]),
		float(special["damage_multiplier"])
	)


## A red circle round it fills up while it stands still; whoever it is after
## gets a hard hit if still inside when the circle is full.
func _area_attack(radius: float, warning: float, multiplier: float) -> void:
	_casting_left = warning
	var center: Vector2 = global_position  # the circle frees itself when it is full
	var circle: Node2D = Telegraph.new()
	circle.radius = radius
	circle.seconds = warning
	circle.z_index = -1
	circle.position = position
	get_parent().add_child(circle)
	await _wait(warning)
	if is_dead or not is_inside_tree():
		return
	var target: Node2D = _chase_target()
	if target != null and target.global_position.distance_to(center) <= radius:
		_hit_hard(target, multiplier)


## A strong hit that was warned of: no dodge roll, but defense counts.
func _hit_hard(target: Node2D, multiplier: float) -> void:
	var target_stats = target.get("stats")
	var hit: Dictionary = CombatRules.resolve_hit(
		roundi(attack_damage * multiplier),
		0.0,
		target_stats.defense() if target_stats != null else 0,
		0.0
	)
	target.call("take_damage", hit["damage"])


## Starts its special move when it is ready and the hero is where it works:
## a charge from mid range, a blink when he comes too close, a dig from afar.
func _try_move(target: Node2D, distance: float) -> bool:
	if moves != null and moves.try_start(target, distance):
		return true
	if _move_ready_in > 0.0:
		return false
	if not charge.is_empty() and distance <= float(charge["range"]):
		if distance >= float(charge["min_range"]):
			_start_charge(target)
			return true
	if not blink.is_empty() and distance <= float(blink["when_closer"]):
		_blink_away(target)
		return true
	if not burrow.is_empty() and distance > attack_range * 1.5:
		_dig_in()
		return true
	return false


## Bramble Boar: a lane fills up on the ground toward the hero, then it rushes
## along the lane and hits him once if he is still in the way.
func _start_charge(target: Node2D) -> void:
	_move_ready_in = float(charge["cooldown"])
	var warning: float = float(charge["warning_seconds"])
	var direction: Vector2 = global_position.direction_to(target.global_position)
	var length: float = float(charge["distance"])
	_casting_left = warning
	var lane: Node2D = Telegraph.new()
	lane.radius = body_radius() + 10.0
	lane.length = length
	lane.rotation = direction.angle()
	lane.seconds = warning
	lane.z_index = -1
	lane.position = position
	get_parent().add_child(lane)
	await _wait(warning)
	if is_dead or not is_inside_tree():
		return
	_sprite.play("attack")
	_rush = direction * float(charge["speed"])
	_rush_left = length / float(charge["speed"])
	_rush_hit = false


func _rush_step(delta: float, target: Node2D) -> Vector2:
	_rush_left = maxf(0.0, _rush_left - delta)
	if target != null and not _rush_hit:
		if global_position.distance_to(target.global_position) <= body_radius() + 22.0:
			_rush_hit = true
			_hit_hard(target, float(charge["damage_multiplier"]))
	if _rush_left == 0.0:
		_attack_ready_in = attack_cooldown  # catches its breath after the rush
	return _rush


## Lantern Wisp: fades out and comes back a little way off, still facing the hero.
func _blink_away(target: Node2D) -> void:
	_move_ready_in = float(blink["cooldown"])
	var away: Vector2 = target.global_position.direction_to(global_position)
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var spot: Vector2 = target.global_position + away.rotated(randf_range(-1.0, 1.0)) * float(
		blink["distance"]
	)
	var closest: Vector2 = NavigationServer2D.map_get_closest_point(
		get_world_2d().navigation_map, spot
	)
	if closest != Vector2.ZERO:
		spot = closest
	_casting_left = 0.3
	Burst.spawn(get_parent(), position, Color(1.0, 0.92, 0.6), 10, 80.0)
	var fade: Tween = create_tween()
	fade.tween_property(_sprite, "modulate:a", 0.0, 0.12)
	fade.tween_callback(func() -> void: global_position = spot)
	fade.tween_property(_sprite, "modulate:a", 1.0, 0.15)


## Rootling: digs in where it stands, out of sight and out of reach.
func _dig_in() -> void:
	_move_ready_in = float(burrow["cooldown"])
	_dig_left = float(burrow["seconds"])
	_set_burrowed(true)


## Moves under the ground toward the hero; bursts out next to him or when the
## time is up.
func _dig_toward(target: Node2D, delta: float) -> Vector2:
	_dig_left -= delta
	var beside: bool = target != null and global_position.distance_to(target.global_position) < 40.0
	if _dig_left <= 0.0 or beside or target == null:
		_set_burrowed(false)
		_sprite.play("attack")
		_area_attack(
			float(burrow["radius"]),
			float(burrow["warning_seconds"]),
			float(burrow["damage_multiplier"])
		)
		return Vector2.ZERO
	return _steer_to(target.global_position, delta) * float(burrow["speed"])


func _set_burrowed(value: bool) -> void:
	burrowed = value
	_sprite.visible = not value
	_hp_bar.visible = not value and not is_dead
	_collision.set_deferred("disabled", value)
	if value:
		remove_from_group("enemies")
	else:
		add_to_group("enemies")
	queue_redraw()


## While it is under the ground: a mound of earth that moves along.
func _draw() -> void:
	if not burrowed:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2(0.0, -6.0), 15.0, Color(0.33, 0.24, 0.17))
	draw_circle(Vector2(-4.0, -10.0), 7.0, Color(0.45, 0.33, 0.22))
	draw_circle(Vector2(6.0, -4.0), 4.0, Color(0.4, 0.29, 0.2))


## For monster_moves.gd: plays one of its own animations ("shell", "leap"), if
## its sheet has it.
func play_move(animation: String) -> void:
	if _sprite.sprite_frames.has_animation(animation):
		_sprite.play(animation)


## For monster_moves.gd: raises the picture off the ground (a leap).
func lift(height: float) -> void:
	_sprite.position.y = _sprite_y - height


## For monster_moves.gd: off while it flies over things in a leap.
func set_solid(solid: bool) -> void:
	_collision.set_deferred("disabled", not solid)


func area_attack(radius: float, warning: float, multiplier: float) -> void:
	_area_attack(radius, warning, multiplier)


func hit_hard(target: Node2D, multiplier: float) -> void:
	_hit_hard(target, multiplier)


func chase_target() -> Node2D:
	return _chase_target()


## Lantern Wisp: bobs gently in the air.
func _float(delta: float) -> void:
	if hover <= 0.0:
		return
	_hover_time += delta
	_sprite.position.y = _sprite_y + sin(_hover_time * 3.0) * hover


func _on_animation_finished() -> void:
	if _sprite.animation == "attack" and not is_dead:
		_sprite.play("idle")


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_collision.set_deferred("disabled", true)
	_hp_bar.hide()
	statuses.clear()
	_sprite.speed_scale = 1.0
	_sprite.play("die")
	if moves != null:
		moves.on_death()  # lands from a leap; a Bubble Slime bursts into small ones
	var fade: Tween = create_tween()
	fade.tween_interval(0.4)
	fade.tween_property(_sprite, "modulate:a", 0.0, 0.35)
	if _player != null:
		_player.call("record_kill", monster_id, is_elite)
		_player.call("gain_kill_xp", xp_reward, level)
	_drop("gold", randi_range(gold_min, gold_max))
	for drop in drops:
		if _for_player(drop["item"]) and randf() < float(drop["chance"]):
			_drop("item", 1, drop["item"])
	_maybe_drop_gear()
	if not boss.is_empty():
		get_tree().call_group("hud", "show_banner", "%s is defeated!" % display_name, "")
		Burst.spawn(get_parent(), position, Color(1.0, 0.86, 0.4), 60, 280.0)
	if not respawns:
		await _wait(1.0)
		queue_free()
		return
	await _wait(respawn_seconds)
	_respawn()


## Turns this slime into an elite: more HP, damage, XP, gold and loot, a glow
## and a bigger body (numbers from the "elite" part of combat.json).
func make_elite() -> void:
	if is_elite:
		return
	var elite: Dictionary = CombatRules.settings["elite"]
	is_elite = true
	max_hp = roundi(max_hp * float(elite["hp"]))
	hp = max_hp
	attack_damage = roundi(attack_damage * float(elite["damage"]))
	xp_reward = roundi(xp_reward * float(elite["xp"]))
	gold_min = roundi(gold_min * float(elite["gold"]))
	gold_max = roundi(gold_max * float(elite["gold"]))
	drops = drops + elite.get("extra_drops", [])
	knockback_resist = maxf(knockback_resist, float(elite.get("knockback_resist", 0.0)))
	display_name = "Elite " + display_name
	_sprite_scale = Vector2.ONE * size_scale * float(elite["scale"])
	if is_node_ready():
		_sprite.scale = _sprite_scale
		_hp_bar.set_label("Lv.%d %s" % [level, display_name])
		_hp_bar.set_values(hp, max_hp)
		_glow = create_tween().set_loops()
		_glow.tween_property(_sprite, "self_modulate", Color(1.6, 1.4, 0.8), 0.5)
		_glow.tween_property(_sprite, "self_modulate", Color.WHITE, 0.5)


func _roll_elite() -> void:
	if not boss.is_empty():
		return
	var chance: float = elite_chance_override
	if chance < 0.0:
		chance = float(CombatRules.settings["elite"]["chance"])
	if randf() < chance:
		make_elite()


func _clear_elite() -> void:
	is_elite = false
	_sprite_scale = Vector2.ONE * size_scale
	_sprite.scale = _sprite_scale
	if _glow != null:
		_glow.kill()
		_glow = null
	_sprite.self_modulate = Color.WHITE


func _load_monster_data() -> void:
	var data: Dictionary = GameData.table("monsters").get(monster_id, {})
	if data.is_empty():
		push_error("Slime: no monster '%s' in monsters.json" % monster_id)
		return
	display_name = data["name"]
	level = int(data["level"])
	max_hp = int(data["max_hp"])
	move_speed = float(data["move_speed"])
	detect_radius = float(data["detect_radius"])
	attack_range = float(data["attack_range"])
	attack_damage = int(data["attack_damage"])
	defense = int(data.get("defense", 0))
	evasion = float(data.get("evasion", 0.0))
	attack_cooldown = float(data["attack_cooldown"])
	respawn_seconds = float(data["respawn_seconds"])
	xp_reward = int(data["xp"])
	gold_min = int(data["gold"][0])
	gold_max = int(data["gold"][1])
	drops = data.get("drops", [])
	gear_drops = data.get("gear_drops", {})
	ranged = data.get("ranged", {})
	if data.has("frames"):
		_sprite.sprite_frames = load(data["frames"])
	on_hit = data.get("on_hit", {})
	knockback_resist = float(data.get("knockback_resist", 0.0))
	special = data.get("special", {})
	var rgba: Array = data.get("tint", [1, 1, 1, 1])
	tint = Color(rgba[0], rgba[1], rgba[2], rgba[3])
	boss = data.get("boss", {})
	size_scale = float(data.get("scale", 1.0))
	charge = data.get("charge", {})
	blink = data.get("blink", {})
	burrow = data.get("burrow", {})
	hover = float(data.get("hover", 0.0))


## Draws and sizes it by size_scale: sprite, body, health bar; a boss gets a crown.
func _apply_size() -> void:
	_sprite_scale = Vector2.ONE * size_scale
	_sprite.scale = _sprite_scale
	_hp_bar.position.y = -BAR_HEIGHT * size_scale
	if size_scale != 1.0 and _collision.shape is CircleShape2D:
		var body := _collision.shape.duplicate() as CircleShape2D
		body.radius *= size_scale
		_collision.shape = body
	if not boss.is_empty():
		add_to_group("bosses")
	if not boss.is_empty() and GameData.table("monsters")[monster_id].get("crown", true):
		_crown = Sprite2D.new()
		_crown.texture = CROWN
		_crown.scale = Vector2.ONE * size_scale * 0.5
		_crown.position = Vector2(0.0, -40.0 * size_scale)
		add_child(_crown)


## Below the boss's enrage line: faster, quicker to attack, and calling help.
func _enrage() -> void:
	_enraged = true
	move_speed *= float(boss.get("enrage_speed", 1.3))
	attack_cooldown *= 0.8
	_summon_left = 0.0
	FloatingText.spawn(self, "ENRAGED!", Color(1.0, 0.4, 0.3), 140.0, 34)


func _summon_tick(delta: float) -> void:
	var summon: Dictionary = boss.get("summon", {})
	if summon.is_empty():
		return
	_summon_left -= delta
	if _summon_left > 0.0:
		return
	_summon_left = float(summon.get("every", 12.0))
	_minions = _minions.filter(func(minion) -> bool: return is_instance_valid(minion))
	var room: int = int(summon.get("most", 4)) - _minions.size()
	for i in mini(int(summon.get("count", 2)), room):
		var minion: Node2D = load(SLIME_SCENE_PATH).instantiate()
		minion.set("monster_id", summon["monster"])
		minion.set("respawns", false)
		minion.position = position + Vector2(randf_range(-90.0, 90.0), randf_range(-60.0, 60.0))
		get_parent().add_child(minion)
		_minions.append(minion)


## Waits on a Timer that belongs to this monster, so leaving the map (which
## frees it) ends the wait too. A SceneTree timer would outlive the monster.
func _wait(seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()


## Loot is for the player's class: gear it cannot wear and other classes'
## skill books do not drop.
func _for_player(item_id: String) -> bool:
	if _player == null:
		return true
	var class_id: String = _player.get("stats").class_id
	var item: Dictionary = ItemDb.items.get(item_id, {})
	if item.has("teaches"):
		return GameData.table("skills")[item["teaches"]].get("class", "warrior") == class_id
	return ItemDb.usable_by(item_id, class_id)


## Gear drops now and then; elites drop it more often and roll better rarity.
## The gear comes from the monster's level (ItemDb.drop_pool). A boss drops
## "gear_count" pieces, none below its "min_rarity". Good pieces stay on the
## ground longer (the rarity's "ground_seconds").
func _maybe_drop_gear() -> void:
	var pool: Array = gear_drops.get("items", ItemDb.drop_pool(level)).filter(_for_player)
	var chance: float = float(gear_drops.get("chance", 0.0))
	var rolls: int = int(boss.get("rarity_rolls", 1))
	if is_elite:
		var elite: Dictionary = CombatRules.settings["elite"]
		chance += float(elite.get("gear_chance", 0.0))
		rolls = int(elite.get("rarity_rolls", 1))
	if pool.is_empty():
		return
	for i in int(boss.get("gear_count", 1)):
		if randf() >= chance:
			continue
		var piece: Dictionary = ItemDb.roll_gear(
			pool.pick_random(), rolls, boss.get("min_rarity", "")
		)
		var pickup: Node2D = PICKUP_SCENE.instantiate()
		pickup.set("kind", "item")
		pickup.set("item_id", piece["id"])
		pickup.set("stack", piece)
		pickup.set("lifetime", float(ItemDb.rarities[piece["rarity"]].get("ground_seconds", 60)))
		var spread := Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0))
		pickup.position = position + spread + Vector2(i * 28.0, 0.0)
		get_parent().call_deferred("add_child", pickup)


func _drop(kind: String, amount: int, item_id: String = "") -> void:
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", kind)
	pickup.set("amount", amount)
	pickup.set("item_id", item_id)
	pickup.position = position + Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0))
	get_parent().call_deferred("add_child", pickup)


func _respawn() -> void:
	global_position = _spawn_position
	if moves != null:
		moves.reset()
		lift(0.0)
	_threat.clear()
	_attack_count = 0
	_casting_left = 0.0
	_rush_left = 0.0
	_move_ready_in = 0.0
	if burrowed:
		_set_burrowed(false)
	_load_monster_data()
	_enraged = false
	_clear_elite()
	_roll_elite()
	hp = max_hp
	is_dead = false
	_is_returning = false
	_attack_ready_in = attack_cooldown
	_collision.set_deferred("disabled", false)
	_sprite.modulate = tint
	_sprite.play("idle")
	_hp_bar.set_label("Lv.%d %s" % [level, display_name])
	_hp_bar.set_values(hp, max_hp)
	_hp_bar.show()
