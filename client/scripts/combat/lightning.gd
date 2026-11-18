extends Node2D
## A jagged bolt through a list of points (Chain Lightning) that fades away
## and frees itself.

const SECONDS := 0.35

## Where the bolt goes, in this node's parent's space.
var points: Array[Vector2] = []
var color: Color = Color(0.75, 0.9, 1.0)

var _age: float = 0.0
var _jagged := PackedVector2Array()


func _ready() -> void:
	add_to_group("lightning")
	for i in range(points.size() - 1):
		var start: Vector2 = points[i]
		var end: Vector2 = points[i + 1]
		var across: Vector2 = (end - start).orthogonal().normalized()
		_jagged.append(start)
		for step in range(1, 6):
			_jagged.append(start.lerp(end, step / 6.0) + across * randf_range(-10.0, 10.0))
	if not points.is_empty():
		_jagged.append(points[-1])


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= SECONDS:
		queue_free()


func _draw() -> void:
	if _jagged.size() < 2:
		return
	var fade: float = 1.0 - clampf(_age / SECONDS, 0.0, 1.0)
	draw_polyline(_jagged, Color(color, 0.35 * fade), 9.0, true)
	draw_polyline(_jagged, Color(1.0, 1.0, 1.0, fade), 3.0, true)
