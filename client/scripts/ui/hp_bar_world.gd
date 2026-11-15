extends Node2D
## Small health bar that floats above a character in the world.
## The owner calls set_values(current, maximum) whenever its HP changes.

const BAR_SIZE := Vector2(56, 8)

var _ratio: float = 1.0


func set_values(current: int, maximum: int) -> void:
	_ratio = clampf(float(current) / float(maxi(maximum, 1)), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var origin: Vector2 = -BAR_SIZE / 2.0
	draw_rect(Rect2(origin - Vector2(2, 2), BAR_SIZE + Vector2(4, 4)), Color(0.15, 0.08, 0.12, 0.85))
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _ratio, BAR_SIZE.y)), Color(0.9, 0.25, 0.3))
