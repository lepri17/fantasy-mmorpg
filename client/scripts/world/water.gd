extends Node2D
## A lake or a river (a maps.json object "water"): "points" are its shore in
## map pixels, going round; "bridges" are [x, y, width, height] boxes of planks
## across it, reaching dry land at both ends; "islands" are sandy shapes in it,
## reached by a bridge (or a frog's leap). The hero walks round the water or
## over a bridge: the walls are the water with the bridges and islands cut out
## (Geometry2D.clip_polygons), in the "obstacles" group, so monsters path round
## it too. All drawn here: a sandy rim, shallow and deep water, the islands,
## ripples that come and go, and the bridges.
## "style": "chasm" makes it a deep rift in the rock instead (Galeclaw Ridge):
## a dark drop with wisps of mist, crossed by rope bridges.

const RIM := Color(0.86, 0.78, 0.56)
const SHALLOW := Color(0.38, 0.68, 0.8)
const DEEP := Color(0.22, 0.46, 0.66)
const EDGE := Color(0.82, 0.94, 0.97, 0.75)
const SAND := Color(0.91, 0.82, 0.6)
const PLANK := Color(0.62, 0.44, 0.27)
const PLANK_DARK := Color(0.43, 0.29, 0.17)
const PLANK_WIDTH := 16.0
const REDRAW_SECONDS := 0.1  # the ripples move ten times a second
const CHASM := {
	"rim": Color(0.5, 0.45, 0.4),
	"shallow": Color(0.17, 0.14, 0.16),
	"deep": Color(0.06, 0.05, 0.08),
	"edge": Color(0.66, 0.6, 0.54, 0.8),
	"ripple": Color(0.8, 0.82, 0.95),
	"rail": Color(0.78, 0.68, 0.46)
}

## "water", or "chasm" (a rift in the rock).
var style: String = "water"
var points := PackedVector2Array()
## Rect2 boxes of planks across the water.
var bridges: Array = []
## PackedVector2Array shapes of dry sand in the water.
var islands: Array = []
var _rim: Array = []
var _deep: Array = []
var _shoals: Array = []  # the shallow water round each island
var _ripples: Array = []  # of [position, phase, half length]
var _time: float = 0.0
var _redraw_in: float = 0.0
var _colors: Dictionary = {}


func _ready() -> void:
	add_to_group("water")
	z_index = -5  # on the ground, under everyone walking by
	_colors = CHASM if style == "chasm" else {
		"rim": RIM, "shallow": SHALLOW, "deep": DEEP, "edge": EDGE, "ripple": Color.WHITE,
		"rail": PLANK_DARK
	}
	_rim = Geometry2D.offset_polygon(points, 16.0)
	_deep = Geometry2D.offset_polygon(points, -40.0)
	for island in islands:
		_shoals.append_array(Geometry2D.offset_polygon(island, 30.0))
	_place_ripples()
	var body := StaticBody2D.new()
	body.add_to_group("obstacles")
	for piece in wall_pieces():
		var shape := CollisionPolygon2D.new()
		shape.polygon = piece
		body.add_child(shape)
	add_child(body)


## The water that blocks the way: all of it but the bridges.
func wall_pieces() -> Array:
	var pieces: Array = [points]
	for bridge in bridges:
		var box: Rect2 = bridge
		var cut := PackedVector2Array(
			[
				box.position,
				Vector2(box.end.x, box.position.y),
				box.end,
				Vector2(box.position.x, box.end.y)
			]
		)
		var left: Array = []
		for piece in pieces:
			left.append_array(Geometry2D.clip_polygons(piece, cut))
		pieces = left
	# Islands after bridges: a bridge reaches each island (check_data.py checks),
	# so the island joins the bridge's gap and is never a hole in the water
	# (a collision shape cannot have one, nor can the monsters' walking mesh).
	for island in islands:
		var left: Array = []
		for piece in pieces:
			var parts: Array = Geometry2D.clip_polygons(piece, island)
			if _has_hole(parts):
				push_error("water.gd: an island that no bridge reaches")
			left.append_array(parts)
		pieces = left
	return pieces.filter(func(piece): return piece.size() >= 3)


## True if a point (map pixels) is in the water: not on a bridge or an island.
func is_wet(point: Vector2) -> bool:
	for bridge in bridges:
		if (bridge as Rect2).has_point(point):
			return false
	for island in islands:
		if Geometry2D.is_point_in_polygon(point, island):
			return false
	return Geometry2D.is_point_in_polygon(point, points)


static func _box(shape: PackedVector2Array) -> Rect2:
	var box := Rect2(shape[0], Vector2.ZERO)
	for point in shape:
		box = box.expand(point)
	return box


## Clipping left a hole: an outer shape and a hole go round opposite ways.
static func _has_hole(parts: Array) -> bool:
	var turns: Array = parts.map(func(part): return Geometry2D.is_polygon_clockwise(part))
	return turns.has(true) and turns.has(false)


func _place_ripples() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(points[0].x) * 7919 + int(points[0].y)
	var box: Rect2 = _box(points)
	var wanted: int = clampi(int(box.get_area() / 14000.0), 4, 60)
	for i in wanted * 4:
		if _ripples.size() >= wanted:
			break
		var spot := Vector2(
			rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y)
		)
		if is_wet(spot):
			_ripples.append([spot, rng.randf() * TAU, rng.randf_range(7.0, 16.0)])


func _process(delta: float) -> void:
	_time += delta
	_redraw_in -= delta
	if _redraw_in <= 0.0:
		_redraw_in = REDRAW_SECONDS
		queue_redraw()


func _draw() -> void:
	for rim in _rim:
		draw_colored_polygon(rim, _colors["rim"])
	draw_colored_polygon(points, _colors["shallow"])
	for deep in _deep:
		draw_colored_polygon(deep, _colors["deep"])
	var shore := points.duplicate()
	shore.append(points[0])
	draw_polyline(shore, _colors["edge"], 3.0, true)
	for shoal in _shoals:
		draw_colored_polygon(shoal, _colors["shallow"])
	for island in islands:
		var beach: PackedVector2Array = island.duplicate()
		beach.append(island[0])
		draw_colored_polygon(island, RIM)
		for inner in Geometry2D.offset_polygon(island, -14.0):
			draw_colored_polygon(inner, SAND)
		draw_polyline(beach, _colors["edge"], 3.0, true)
	for ripple in _ripples:
		var wave: float = sin(_time * 1.3 + ripple[1])
		var half: float = ripple[2] * (0.7 + 0.3 * wave)
		var color: Color = _colors["ripple"]
		color.a = 0.1 + 0.14 * (wave + 1.0) * 0.5
		draw_line(ripple[0] - Vector2(half, 0), ripple[0] + Vector2(half, 0), color, 2.0)
	for bridge in bridges:
		_draw_bridge(bridge)


## Planks across the water, a rail on each side, and a shadow on the water.
func _draw_bridge(box: Rect2) -> void:
	draw_rect(Rect2(box.position + Vector2(0, 10), box.size), Color(0, 0, 0, 0.2))
	draw_rect(box, PLANK)
	var east_west: bool = box.size.x >= box.size.y
	var step: float = PLANK_WIDTH
	var along: float = box.size.x if east_west else box.size.y
	var at: float = step
	while at < along:
		if east_west:
			draw_line(
				Vector2(box.position.x + at, box.position.y),
				Vector2(box.position.x + at, box.end.y),
				PLANK_DARK,
				2.0
			)
		else:
			draw_line(
				Vector2(box.position.x, box.position.y + at),
				Vector2(box.end.x, box.position.y + at),
				PLANK_DARK,
				2.0
			)
		at += step
	var rails: Array = []
	if east_west:
		rails = [
			Rect2(box.position.x, box.position.y - 3, box.size.x, 7),
			Rect2(box.position.x, box.end.y - 4, box.size.x, 7)
		]
	else:
		rails = [
			Rect2(box.position.x - 3, box.position.y, 7, box.size.y),
			Rect2(box.end.x - 4, box.position.y, 7, box.size.y)
		]
	for rail in rails:
		if style == "chasm":  # rope, not wood
			draw_rect(rail.grow(-2.0), _colors["rail"])
		else:
			draw_rect(rail, PLANK_DARK)
	var corners: Array = [
		box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)
	]
	for corner in corners:
		draw_rect(Rect2(corner - Vector2(6, 6), Vector2(12, 12)), PLANK_DARK)
