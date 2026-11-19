extends Node2D
## The flash of a Ruin Sentinel's beam (monster_moves.gd "beam"): a bright ray
## along the node's rotation that fades in a moment.

const SECONDS := 0.3

var length: float = 400.0
var width: float = 40.0
var _left: float = SECONDS


func _ready() -> void:
	z_index = 4


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var fade: float = clampf(_left / SECONDS, 0.0, 1.0)
	draw_rect(Rect2(0, -width * 0.5, length, width), Color(0.45, 0.92, 1.0, 0.35 * fade))
	draw_rect(Rect2(0, -width * 0.2, length, width * 0.4), Color(0.85, 1.0, 1.0, 0.85 * fade))
