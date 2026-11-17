extends Node2D
## Pulsing ring on the ground under the enemy the warrior's auto-aim will hit.

const RADIUS := Vector2(30, 12)
const COLOR := Color(1.0, 0.4, 0.3, 0.85)

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse: float = 1.0 + 0.08 * sin(_time * 8.0)
	var points := PackedVector2Array()
	for i in 41:
		var angle: float = TAU * i / 40.0
		points.append(Vector2(cos(angle) * RADIUS.x, sin(angle) * RADIUS.y) * pulse)
	draw_polyline(points, COLOR, 3.0, true)
