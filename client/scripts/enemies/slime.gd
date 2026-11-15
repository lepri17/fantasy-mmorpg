extends CharacterBody2D
## A simple slime: waits, chases the warrior when he comes close, bumps into
## him for a little damage, and comes back to life a few seconds after dying.

@export var max_hp: int = 40
@export var move_speed: float = 70.0
## The slime starts chasing when the warrior is closer than this.
@export var detect_radius: float = 260.0
## The slime attacks when the warrior is closer than this.
@export var attack_range: float = 48.0
@export var attack_damage: int = 6
@export var attack_cooldown: float = 1.2
@export var respawn_seconds: float = 5.0

var hp: int = 0
var is_dead: bool = false

var _attack_ready_in: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO
var _player: Node2D = null

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _hp_bar = $HpBar


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_spawn_position = global_position
	_hp_bar.set_values(hp, max_hp)
	_sprite.play("idle")


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_attack_ready_in = maxf(0.0, _attack_ready_in - delta)

	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D

	var direction := Vector2.ZERO
	if _player != null:
		var to_player: Vector2 = _player.global_position - global_position
		var distance: float = to_player.length()
		if distance <= attack_range:
			if _attack_ready_in == 0.0:
				_attack()
		elif distance <= detect_radius:
			direction = to_player / distance

	velocity = direction * move_speed
	move_and_slide()


## Called by the warrior's attack.
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = maxi(hp - amount, 0)
	_hp_bar.set_values(hp, max_hp)
	_show_damage_number(amount)
	_flash_hit()
	if hp == 0:
		_die()


func _attack() -> void:
	_attack_ready_in = attack_cooldown
	_player.call("take_damage", attack_damage)
	_sprite.scale = Vector2(1.3, 0.75)
	create_tween().tween_property(_sprite, "scale", Vector2.ONE, 0.2)


func _flash_hit() -> void:
	_sprite.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.2)


func _show_damage_number(amount: int) -> void:
	var label := Label.new()
	label.text = str(amount)
	label.position = Vector2(-12, -80)
	label.z_index = 10
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.1))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	_collision.set_deferred("disabled", true)
	_hp_bar.hide()
	create_tween().tween_property(_sprite, "modulate:a", 0.0, 0.35)
	await get_tree().create_timer(respawn_seconds).timeout
	_respawn()


func _respawn() -> void:
	global_position = _spawn_position
	hp = max_hp
	is_dead = false
	_attack_ready_in = attack_cooldown
	_collision.set_deferred("disabled", false)
	_sprite.modulate = Color.WHITE
	_hp_bar.set_values(hp, max_hp)
	_hp_bar.show()
