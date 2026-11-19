extends Node2D
## An icicle falling from high above (icefall.gd): it drops onto the spot under
## its warning circle and shatters, hurting and slowing whoever is still in the
## circle.

const CombatRules := preload("res://scripts/combat/combat_rules.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const ICE := Color(0.84, 0.94, 1.0)
const ICE_DARK := Color(0.56, 0.76, 0.93)
const DROP := 260.0  # how high above the ground it starts

var seconds: float = 0.8
var radius: float = 60.0
var damage: int = 60
var _time: float = 0.0


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if _time >= seconds:
		_shatter()


func _shatter() -> void:
	set_process(false)
	Burst.spawn(get_parent(), position, ICE, 14, 120.0)
	for hero in get_tree().get_nodes_in_group("player"):
		if hero.get("is_dead") or hero.global_position.distance_to(global_position) > radius:
			continue
		var stats = hero.get("stats")
		var hit: Dictionary = CombatRules.resolve_hit(
			damage, 0.0, stats.defense() if stats != null else 0, 0.0
		)
		hero.call("take_damage", hit["damage"])
		if hero.has_method("apply_status"):
			hero.call("apply_status", "slow", 1.5, 0.4)
	queue_free()


func _draw() -> void:
	var done: float = minf(1.0, _time / seconds)
	var height: float = DROP * (1.0 - done * done)  # it falls faster and faster
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 6.0 + done * 8.0, Color(0, 0, 0, 0.15 + done * 0.2))
	draw_set_transform(Vector2(0, -height), 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(-7, -34), Vector2(7, -34), Vector2(0, 0)]), ICE)
	draw_colored_polygon(
		PackedVector2Array([Vector2(0, -34), Vector2(7, -34), Vector2(0, 0)]), ICE_DARK
	)
