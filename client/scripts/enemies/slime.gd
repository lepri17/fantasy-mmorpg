extends CharacterBody2D
## A slime. It wanders around its spawn point, chases the warrior when he comes
## close, bumps into him for damage, gets knocked back when hit, drops loot and
## gives XP when it dies, and comes back a few seconds later.
##
## Every kind of slime is this scene with a different monster_id; the numbers
## come from res://data/monsters.json.

const FloatingText = preload("res://scripts/ui/floating_text.gd")
const GameData = preload("res://scripts/data/game_data.gd")
const PICKUP_SCENE := preload("res://scenes/items/pickup.tscn")

const KNOCKBACK_SPEED := 240.0
const KNOCKBACK_DECAY := 1400.0
const WANDER_RADIUS := 90.0
## A slime that gets this far from home gives up the chase and walks back.
const LEASH_RADIUS := 480.0

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
var attack_cooldown: float = 1.2
var respawn_seconds: float = 5.0
var xp_reward: int = 20
var gold_min: int = 1
var gold_max: int = 5
## [{"item": item id, "chance": 0..1}, ...]
var drops: Array = []
## Color multiplier, used to tell the kinds of slime apart.
var tint: Color = Color.WHITE

var hp: int = 0
var is_dead: bool = false

var _attack_ready_in: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO
var _knockback: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _is_returning: bool = false
var _player: Node2D = null

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _hp_bar = $HpBar


func _ready() -> void:
	add_to_group("enemies")
	_load_monster_data()
	hp = max_hp
	_spawn_position = global_position
	_wander_target = global_position
	_sprite.modulate = tint
	_hp_bar.set_label("Lv.%d %s" % [level, display_name])
	_hp_bar.set_values(hp, max_hp)
	_sprite.play("idle")


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_attack_ready_in = maxf(0.0, _attack_ready_in - delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

	var movement := Vector2.ZERO
	var target: Node2D = _chase_target()
	if target == null:
		movement = _wander(delta)
	else:
		var to_target: Vector2 = target.global_position - global_position
		var distance: float = to_target.length()
		if distance > attack_range:
			movement = to_target / distance * move_speed
		elif _attack_ready_in == 0.0:
			_attack(target)

	velocity = movement + _knockback
	move_and_slide()


## Called by the warrior's attacks. from_position is where the hit came from.
func take_damage(amount: int, from_position: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return
	hp = maxi(hp - amount, 0)
	_hp_bar.set_values(hp, max_hp)
	FloatingText.spawn(self, str(amount), Color(1.0, 0.95, 0.4))
	if from_position != Vector2.ZERO:
		_knockback = (global_position - from_position).normalized() * KNOCKBACK_SPEED
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
	if _is_returning or _player == null or _player.get("is_dead"):
		return null
	if _player.global_position.distance_to(global_position) > detect_radius:
		return null
	return _player


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


func _attack(target: Node2D) -> void:
	_attack_ready_in = attack_cooldown
	target.call("take_damage", attack_damage)
	_sprite.scale = Vector2(1.3, 0.75)
	create_tween().tween_property(_sprite, "scale", Vector2.ONE, 0.2)


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_collision.set_deferred("disabled", true)
	_hp_bar.hide()
	create_tween().tween_property(_sprite, "modulate:a", 0.0, 0.35)
	if _player != null:
		_player.call("gain_xp", xp_reward)
	_drop("gold", randi_range(gold_min, gold_max))
	for drop in drops:
		if randf() < float(drop["chance"]):
			_drop("item", 1, drop["item"])
	await get_tree().create_timer(respawn_seconds).timeout
	_respawn()


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
	attack_cooldown = float(data["attack_cooldown"])
	respawn_seconds = float(data["respawn_seconds"])
	xp_reward = int(data["xp"])
	gold_min = int(data["gold"][0])
	gold_max = int(data["gold"][1])
	drops = data.get("drops", [])
	var rgba: Array = data.get("tint", [1, 1, 1, 1])
	tint = Color(rgba[0], rgba[1], rgba[2], rgba[3])


func _drop(kind: String, amount: int, item_id: String = "") -> void:
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", kind)
	pickup.set("amount", amount)
	pickup.set("item_id", item_id)
	pickup.position = position + Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0))
	get_parent().call_deferred("add_child", pickup)


func _respawn() -> void:
	global_position = _spawn_position
	hp = max_hp
	is_dead = false
	_is_returning = false
	_attack_ready_in = attack_cooldown
	_collision.set_deferred("disabled", false)
	_sprite.modulate = tint
	_hp_bar.set_values(hp, max_hp)
	_hp_bar.show()
