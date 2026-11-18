extends Control
## Q8: a small map in the corner. The map's edges, the warrior (white),
## monsters (red; bosses bigger and purple), townspeople (yellow) and portals
## (blue). Redrawn ten times a second.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const PADDING := 8.0
## [group, colour, dot radius], drawn in this order (the warrior last, on top).
const MARKERS := [
	["portals", Color(0.45, 0.85, 1.0), 3.5],
	["npcs", Color(1.0, 0.86, 0.35), 3.0],
	["enemies", Color(1.0, 0.35, 0.35), 2.5],
	["bosses", Color(0.8, 0.4, 1.0), 5.5],
	["player", Color(1, 1, 1), 4.0],
]

var _redraw_left: float = 0.0
var _frame: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = UiStyle.frame_style()
	_frame.bg_color = Color(0.08, 0.05, 0.1, 0.72)
	_frame.set_border_width_all(2)
	_frame.set_corner_radius_all(10)


func _process(delta: float) -> void:
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = 0.1
		queue_redraw()


## Every dot to draw now: [position on the minimap, colour, radius].
func markers() -> Array:
	var dots: Array = []
	var map: Node = get_tree().get_first_node_in_group("maps")
	if map == null:
		return dots
	var bounds: Rect2 = map.call("bounds")
	if not bounds.has_area():
		return dots
	var inner: Vector2 = size - Vector2.ONE * PADDING * 2.0
	var zoom: float = minf(inner.x / bounds.size.x, inner.y / bounds.size.y)
	var corner: Vector2 = (size - bounds.size * zoom) / 2.0
	for marker in MARKERS:
		for node in get_tree().get_nodes_in_group(marker[0]):
			if node is Node2D and not node.get("is_dead"):
				var spot: Vector2 = corner + (node.global_position - bounds.position) * zoom
				dots.append([spot, marker[1], marker[2]])
	return dots


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	for dot in markers():
		draw_circle(dot[0], dot[2] + 1.0, Color(0.05, 0.03, 0.06))
		draw_circle(dot[0], dot[2], dot[1])
