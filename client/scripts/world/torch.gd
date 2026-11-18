extends Node2D
## A wall torch for dark maps (G3): a stick with a flame and a warm,
## flickering light.

const SkyClock := preload("res://scripts/world/sky.gd")

var _light: PointLight2D
var _time: float = 0.0


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = SkyClock.light_texture()
	_light.color = Color(1.0, 0.72, 0.4)
	_light.energy = 1.1
	_light.texture_scale = 2.4
	_light.position = Vector2(0, -34)
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	_light.energy = 1.0 + sin(_time * 9.0) * 0.08 + sin(_time * 23.0) * 0.05
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-3, -30, 6, 30), Color(0.42, 0.26, 0.16))
	var sway: float = sin(_time * 7.0) * 1.5
	draw_circle(Vector2(sway, -36), 8.0, Color(1.0, 0.55, 0.15, 0.9))
	draw_circle(Vector2(sway * 0.6, -38), 4.5, Color(1.0, 0.92, 0.5))
