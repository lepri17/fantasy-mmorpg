extends Node2D
## A gorge hung with icicles (a maps.json object "icefall": "area" [x, y,
## width, height] in map pixels, "every" seconds, "damage"). While a hero is
## in it, an icicle falls near him every so often: a circle warns where, then
## it shatters (icicle.gd). On the ground: a frosty haze with glints of ice.

const Telegraph := preload("res://scripts/combat/telegraph.gd")
const Icicle := preload("res://scripts/combat/icicle.gd")
const WARNING := 0.8
const RADIUS := 62.0

var area := Rect2()
var every: float = 2.2
var damage: int = 70
var _next_in: float = 1.0
var _glints: Array = []


func _ready() -> void:
	add_to_group("icefalls")
	z_index = -4
	var rng := RandomNumberGenerator.new()
	rng.seed = int(area.position.x) * 31 + int(area.position.y)
	for i in clampi(int(area.get_area() / 9000.0), 6, 40):
		_glints.append(
			Vector2(
				rng.randf_range(area.position.x, area.end.x),
				rng.randf_range(area.position.y, area.end.y)
			)
		)


func _process(delta: float) -> void:
	var hero: Node2D = hero_under()
	if hero == null:
		_next_in = 1.0  # the first icicle comes a moment after someone walks in
		return
	_next_in -= delta
	if _next_in <= 0.0:
		_next_in = every
		drop(hero.global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-30.0, 30.0)))


## The hero under the icicles, if one is.
func hero_under() -> Node2D:
	for hero in get_tree().get_nodes_in_group("player"):
		if not hero.get("is_dead") and area.has_point(hero.global_position):
			return hero
	return null


## Drops one icicle on a spot (map pixels), warned by a circle.
func drop(spot: Vector2) -> void:
	var local: Vector2 = get_parent().to_local(spot)
	var circle: Node2D = Telegraph.new()
	circle.radius = RADIUS
	circle.seconds = WARNING
	circle.z_index = -1
	circle.position = local
	get_parent().add_child(circle)
	var icicle: Node2D = Icicle.new()
	icicle.seconds = WARNING
	icicle.radius = RADIUS
	icicle.damage = damage
	icicle.position = local
	get_parent().add_child(icicle)


func _draw() -> void:
	draw_rect(area, Color(0.86, 0.94, 1.0, 0.14))
	for glint in _glints:
		draw_circle(glint, 2.5, Color(1, 1, 1, 0.7))
		draw_line(glint - Vector2(5, 0), glint + Vector2(5, 0), Color(1, 1, 1, 0.45), 1.0)
		draw_line(glint - Vector2(0, 5), glint + Vector2(0, 5), Color(1, 1, 1, 0.45), 1.0)
