extends Node2D
## The see-through bubble round the mage while Mana Shield is on. Fades out at
## the end and frees itself.

var seconds: float = 10.0
var color: Color = Color(0.62, 0.52, 1.0)

var _age: float = 0.0


func _ready() -> void:
	add_to_group("shield_bubbles")
	z_index = 1


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= seconds:
		queue_free()


func _draw() -> void:
	var fade: float = clampf((seconds - _age) / 0.5, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_age * 4.0)
	var middle := Vector2(0.0, -36.0)
	draw_circle(middle, 46.0, Color(color, (0.1 + 0.05 * pulse) * fade))
	draw_arc(middle, 46.0, 0.0, TAU, 48, Color(0.85, 0.8, 1.0, 0.7 * fade), 2.0, true)
