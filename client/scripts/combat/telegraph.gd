extends Node2D
## Red circle on the ground that fills up before a strong attack lands there,
## so the warrior can step (or dash) out of it. Frees itself when done.

var radius: float = 80.0
var seconds: float = 0.8

var _elapsed: float = 0.0


func _ready() -> void:
	add_to_group("telegraphs")


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= seconds:
		queue_free()


func _draw() -> void:
	var fill: float = clampf(_elapsed / maxf(seconds, 0.01), 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, radius * fill, Color(1.0, 0.15, 0.1, 0.3))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.2, 0.15, 0.85), 3.0, true)
