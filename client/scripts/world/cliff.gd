extends Node2D
## A cliff (a maps.json object "cliff"): a raised plateau of rock. "points" are
## the edge of its flat top, going round, in map pixels; its rock face drops
## HEIGHT pixels below that. Nothing climbs it: the wall is the whole block, top
## and face, in the "obstacles" group, so monsters path round it too. Between
## cliffs are the narrow passes of Galeclaw Ridge.

const HEIGHT := 56.0
const TOP := Color(0.58, 0.53, 0.48)
const TOP_LIGHT := Color(0.66, 0.61, 0.55)
const FACE := Color(0.4, 0.35, 0.32)
const FACE_DARK := Color(0.29, 0.25, 0.23)
const EDGE := Color(0.84, 0.8, 0.72)
const MOSS := Color(0.47, 0.55, 0.36)
const SHADOW := Color(0, 0, 0, 0.18)

var points := PackedVector2Array()
var _block := PackedVector2Array()  # the top and the face together
var _inner: Array = []
var _grooves: Array = []  # [top, bottom] lines down the face
var _moss: Array = []  # [position, size]


func _ready() -> void:
	add_to_group("cliffs")
	z_index = -4  # on the ground, under everyone walking by
	_block = block()
	_inner = Geometry2D.offset_polygon(points, -12.0)
	_plan_details()
	var body := StaticBody2D.new()
	body.add_to_group("obstacles")
	var shape := CollisionPolygon2D.new()
	shape.polygon = _block
	body.add_child(shape)
	add_child(body)


## The ground the cliff stands on: its top and the face below it.
func block() -> PackedVector2Array:
	var base := PackedVector2Array()
	for point in points:
		base.append(point + Vector2(0, HEIGHT))
	var largest := PackedVector2Array()
	for part in Geometry2D.merge_polygons(points, base):
		if _area(part) > _area(largest):  # the outline (any hole is smaller)
			largest = part
	return largest


## Can a body stand at this point (map pixels)? No, if it is in the cliff.
func is_solid(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, _block)


static func _area(shape: PackedVector2Array) -> float:
	var total := 0.0
	for i in shape.size():
		total += shape[i].cross(shape[(i + 1) % shape.size()])
	return absf(total) * 0.5


func _plan_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(points[0].x) * 4099 + int(points[0].y)
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var out: Vector2 = (b - a).orthogonal().normalized()
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + out * 3.0, points):
			out = -out  # it pointed into the top: turn it outward
		if out.y < 0.3:
			continue  # only the edges facing south show their face
		var steps: int = maxi(1, int(a.distance_to(b) / 26.0))
		for k in steps:
			var top: Vector2 = a.lerp(b, (k + rng.randf_range(0.2, 0.8)) / steps)
			_grooves.append([top + Vector2(0, 6), top + Vector2(0, HEIGHT - rng.randf_range(4, 18))])
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	for i in clampi(int(box.get_area() / 18000.0), 2, 14):
		var spot := Vector2(
			rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y)
		)
		if Geometry2D.is_point_in_polygon(spot, points):
			_moss.append([spot, rng.randf_range(8.0, 18.0)])


func _draw() -> void:
	var shadow := PackedVector2Array()
	for point in _block:
		shadow.append(point + Vector2(10, 8))
	draw_colored_polygon(shadow, SHADOW)
	draw_colored_polygon(_block, FACE)
	for groove in _grooves:
		draw_line(groove[0], groove[1], FACE_DARK, 3.0)
	draw_colored_polygon(points, TOP)
	for inner in _inner:
		draw_colored_polygon(inner, TOP_LIGHT)
	for patch in _moss:
		draw_set_transform(patch[0], 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, patch[1], MOSS)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var rim := points.duplicate()
	rim.append(points[0])
	draw_polyline(rim, EDGE, 3.0, true)
