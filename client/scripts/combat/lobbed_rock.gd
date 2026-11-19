extends Node2D
## A rock a Crag Imp throws high over the ground (monster_moves.gd "lob"). It
## flies in an arc from where it was thrown to the spot under a warning circle,
## and when it lands it hits whoever is still in that circle. Once thrown it
## lands even if the imp is gone.

const CombatRules := preload("res://scripts/combat/combat_rules.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const ROCK := Color(0.55, 0.51, 0.48)
const ROCK_LIGHT := Color(0.72, 0.68, 0.64)

var from := Vector2.ZERO
var to := Vector2.ZERO
var seconds: float = 1.0
var height: float = 140.0
var radius: float = 80.0
var damage: int = 10
var _time: float = 0.0


func _ready() -> void:
	z_index = 5  # up in the air, over everyone
	position = from


func _process(delta: float) -> void:
	_time += delta
	var done: float = minf(1.0, _time / seconds)
	position = from.lerp(to, done)
	queue_redraw()
	if done >= 1.0:
		_land()


func _land() -> void:
	set_process(false)
	Burst.spawn(get_parent(), position, ROCK_LIGHT, 12, 110.0)
	for hero in get_tree().get_nodes_in_group("player"):
		if hero.get("is_dead") or hero.global_position.distance_to(global_position) > radius:
			continue
		var stats = hero.get("stats")
		var hit: Dictionary = CombatRules.resolve_hit(
			damage, 0.0, stats.defense() if stats != null else 0, 0.0
		)
		hero.call("take_damage", hit["damage"])
	queue_free()


func _draw() -> void:
	var done: float = minf(1.0, _time / seconds)
	var lift: float = sin(PI * done) * height
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 10.0 - lift * 0.03, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2(0, -lift), _time * 7.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, 11.0, ROCK)
	draw_circle(Vector2(-3, -3), 4.0, ROCK_LIGHT)
