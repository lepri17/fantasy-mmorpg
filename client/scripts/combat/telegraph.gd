extends Node2D
## Red circle on the ground that fills up before a strong attack lands there,
## so the warrior can step (or dash) out of it. Frees itself when done.
## With a length it is a lane instead (a charge): it starts here, runs along
## the node's rotation, and radius is half its width.

var radius: float = 80.0
var length: float = 0.0
var seconds: float = 0.8
## Red for a monster's attack; the hero's spells mark their spot in their colour.
var color: Color = Color(1.0, 0.15, 0.1)

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
	if length > 0.0:
		draw_rect(Rect2(0.0, -radius, length * fill, radius * 2.0), Color(color, 0.3))
		draw_rect(
			Rect2(0.0, -radius, length, radius * 2.0), Color(color.lightened(0.05), 0.85), false, 3.0
		)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, radius * fill, Color(color, 0.3))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color.lightened(0.05), 0.85), 3.0, true)
