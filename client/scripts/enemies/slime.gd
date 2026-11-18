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
## Status put on the warrior by a landed hit, or {}: {"status", "chance", "seconds", "value"}.
var on_hit: Dictionary = {}
## A telegraphed slam instead of every Nth attack, or {}:
## {"every", "radius", "warning_seconds", "damage_multiplier"}.
var special: Dictionary = {}
## Stun (and any other effect) on this slime.
var statuses = StatusEffects.new()
## Color multiplier, used to tell the kinds of slime apart.
var tint: Color = Color.WHITE
## Elites have more HP, damage, XP and loot, glow, and are a bit bigger.
var is_elite: bool = false

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

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _hp_bar = $HpBar


func _ready() -> void:
	add_to_group("enemies")
	_load_monster_data()
	_roll_elite()
	hp = max_hp
	_spawn_position = global_position
	_wander_target = global_position
	_sprite.modulate = tint
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
	var stunned: bool = statuses.is_active("stun")
	_sprite.speed_scale = 0.0 if stunned else 1.0

	var movement := Vector2.ZERO
	var target: Node2D = _chase_target()
	if stunned or _casting_left > 0.0:
		pass  # stays put: stunned, or winding up a slam
	elif target == null:
		movement = _wander(delta)
	else:
		var to_target: Vector2 = target.global_position - global_position
		var distance: float = to_target.length()
		if distance > attack_range:
			movement = to_target / distance * move_speed * statuses.speed_factor()
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
	hp = maxi(hp - amount, 0)
	_hp_bar.set_values(hp, max_hp)
	if crit:
		FloatingText.spawn(self, "%d!" % amount, CRIT_COLOR, 90.0, 36)
	else:
		FloatingText.spawn(self, str(amount), Color(1.0, 0.95, 0.4))
	if attacker != null:
		_threat[attacker] = int(_threat.get(attacker, 0)) + amount
	if from_position != Vector2.ZERO:
		var away: Vector2 = (global_position - from_position).normalized()
		_knockback = away * KNOCKBACK_SPEED * knockback
	if hp == 0:
		_die()
		return
	_sprite.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(_sprite, "modulate", tint, 0.2)


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
	var warning: float = float(special["warning_seconds"])
	var radius: float = float(special["radius"])
	_casting_left = warning
	var center: Vector2 = global_position  # the circle frees itself when it is full
	var circle: Node2D = Telegraph.new()
	circle.radius = radius
	circle.seconds = warning
	circle.z_index = -1
	circle.position = position
	get_parent().add_child(circle)
	await get_tree().create_timer(warning).timeout
	if is_dead or not is_inside_tree():
		return
	var target: Node2D = _chase_target()
	if target == null or target.global_position.distance_to(center) > radius:
		return
	var target_stats = target.get("stats")
	var hit: Dictionary = CombatRules.resolve_hit(
		roundi(attack_damage * float(special["damage_multiplier"])),
		0.0,
		target_stats.defense() if target_stats != null else 0,
		0.0
	)
	target.call("take_damage", hit["damage"])


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
	var fade: Tween = create_tween()
	fade.tween_interval(0.4)
	fade.tween_property(_sprite, "modulate:a", 0.0, 0.35)
	if _player != null:
		_player.call("record_kill", monster_id, is_elite)
		_player.call("gain_xp", xp_reward)
	_drop("gold", randi_range(gold_min, gold_max))
	for drop in drops:
		if randf() < float(drop["chance"]):
			_drop("item", 1, drop["item"])
	_maybe_drop_gear()
	await get_tree().create_timer(respawn_seconds).timeout
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
	display_name = "Elite " + display_name
	_sprite_scale = Vector2.ONE * float(elite["scale"])
	if is_node_ready():
		_sprite.scale = _sprite_scale
		_hp_bar.set_label("Lv.%d %s" % [level, display_name])
		_hp_bar.set_values(hp, max_hp)
		_glow = create_tween().set_loops()
		_glow.tween_property(_sprite, "self_modulate", Color(1.6, 1.4, 0.8), 0.5)
		_glow.tween_property(_sprite, "self_modulate", Color.WHITE, 0.5)


func _roll_elite() -> void:
	var chance: float = elite_chance_override
	if chance < 0.0:
		chance = float(CombatRules.settings["elite"]["chance"])
	if randf() < chance:
		make_elite()


func _clear_elite() -> void:
	is_elite = false
	_sprite_scale = Vector2.ONE
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
	on_hit = data.get("on_hit", {})
	special = data.get("special", {})
	var rgba: Array = data.get("tint", [1, 1, 1, 1])
	tint = Color(rgba[0], rgba[1], rgba[2], rgba[3])


## Gear drops now and then; elites drop it more often and roll better rarity.
func _maybe_drop_gear() -> void:
	var pool: Array = gear_drops.get("items", [])
	var chance: float = float(gear_drops.get("chance", 0.0))
	var rolls: int = 1
	if is_elite:
		var elite: Dictionary = CombatRules.settings["elite"]
		chance += float(elite.get("gear_chance", 0.0))
		rolls = int(elite.get("rarity_rolls", 1))
	if pool.is_empty() or randf() >= chance:
		return
	var piece: Dictionary = ItemDb.roll_gear(pool.pick_random(), rolls)
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", "item")
	pickup.set("item_id", piece["id"])
	pickup.set("stack", piece)
	pickup.set("lifetime", 60.0)
	pickup.position = position + Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0))
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
	_threat.clear()
	_attack_count = 0
	_casting_left = 0.0
	_load_monster_data()
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
