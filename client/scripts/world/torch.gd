extends Node2D
## A wall torch for dark maps (G3): a stick with a flame and a warm,
## flickering light. As a street lamp ("lamp", everywhere but dark indoor
## maps) it paints a soft glow round the flame instead of a real light: each
## PointLight2D makes the phone draw everything near it again, and a town's
## row of lamps made the frame rate drop.

const SkyClock := preload("res://scripts/world/sky.gd")

## True: a painted glow, no real light (game_map.gd sets it).
var lamp: bool = false
var _light: PointLight2D = null
var _time: float = 0.0


func _ready() -> void:
	if lamp:
		return
	_light = PointLight2D.new()
	_light.texture = SkyClock.light_texture()
	_light.color = Color(1.0, 0.72, 0.4)
	_light.energy = 1.1
	_light.texture_scale = 2.4
	_light.position = Vector2(0, -34)
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	if _light != null:
		_light.energy = 1.0 + sin(_time * 9.0) * 0.08 + sin(_time * 23.0) * 0.05
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-3, -30, 6, 30), Color(0.42, 0.26, 0.16))
	var sway: float = sin(_time * 7.0) * 1.5
	if lamp:
		draw_circle(Vector2(sway, -36), 34.0, Color(1.0, 0.74, 0.36, 0.09))
		draw_circle(Vector2(sway, -36), 21.0, Color(1.0, 0.8, 0.42, 0.14))
	draw_circle(Vector2(sway, -36), 8.0, Color(1.0, 0.55, 0.15, 0.9))
	draw_circle(Vector2(sway * 0.6, -38), 4.5, Color(1.0, 0.92, 0.5))
