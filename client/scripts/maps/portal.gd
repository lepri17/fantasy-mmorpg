extends Area2D
## A glowing swirl that takes the warrior to another map when he walks in.
## The name of the place it leads to floats above it.

const GameData := preload("res://scripts/data/game_data.gd")
const SWIRL := Color(0.55, 0.85, 1.0)
const RINGS := 3

@export var to_map: String = ""
@export var to_spawn: String = "default"

var _spin: float = 0.0


func _ready() -> void:
	add_to_group("portals")
	body_entered.connect(_on_body_entered)
	var label := Label.new()
	label.text = GameData.table("maps")["maps"].get(to_map, {}).get("name", to_map)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.15))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(200, 24)
	label.position = Vector2(-100, -84)
	add_child(label)


func _process(delta: float) -> void:
	_spin += delta * 2.5
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 38.0, Color(SWIRL.r, SWIRL.g, SWIRL.b, 0.18))
	for ring in RINGS:
		var radius: float = 14.0 + ring * 10.0
		var start: float = _spin * (1.0 + ring * 0.4) + ring
		draw_arc(Vector2.ZERO, radius, start, start + PI * 1.3, 24, SWIRL, 3.0)
	draw_circle(Vector2.ZERO, 8.0, Color(1, 1, 1, 0.8))


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not body.get("is_dead"):
		get_tree().call_group("game", "change_map", to_map, to_spawn)
