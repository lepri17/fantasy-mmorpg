extends Node2D
## Glowing mushrooms for the deep forest: a small cluster with a soft,
## slowly breathing light in its colour (maps.json "glowcap", "color").

const SkyClock := preload("res://scripts/world/sky.gd")
const COLORS := {
	"cyan": Color(0.45, 0.9, 1.0),
	"teal": Color(0.4, 1.0, 0.75),
	"violet": Color(0.78, 0.55, 1.0),
}

## One of COLORS.
var color_name: String = "cyan"

var _light: PointLight2D
var _time: float = 0.0


func _ready() -> void:
	_time = randf() * TAU
	_light = PointLight2D.new()
	_light.texture = SkyClock.light_texture()
	_light.color = COLORS.get(color_name, COLORS["cyan"])
	_light.energy = 0.8
	_light.texture_scale = 1.6
	_light.position = Vector2(0, -10)
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	_light.energy = 0.75 + sin(_time * 1.6) * 0.15


func _draw() -> void:
	var glow: Color = COLORS.get(color_name, COLORS["cyan"])
	for cap in [[Vector2(-10, 0), 8.5], [Vector2(9, 3), 6.5], [Vector2(0, -4), 10.5]]:
		var base: Vector2 = cap[0]
		var size: float = cap[1]
		draw_rect(Rect2(base.x - size * 0.22, base.y - size, size * 0.44, size), Color(0.92, 0.9, 0.82))
		draw_set_transform(base + Vector2(0, -size), 0.0, Vector2(1.0, 0.6))
		draw_circle(Vector2.ZERO, size, glow)
		draw_circle(Vector2(-size * 0.3, -size * 0.3), size * 0.35, glow.lightened(0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
