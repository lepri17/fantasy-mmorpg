extends Node2D
## A cliff (a maps.json object "cliff"): a raised plateau of rock. "points" are
## the edge of its flat top, going round, in map pixels; its rock face drops
## HEIGHT pixels below that. Nothing climbs it: the wall is the whole block, top
## and face, in the "obstacles" group, so monsters path round it too. Between
## cliffs are the narrow passes of Galeclaw Ridge.
## "style": "wall" makes it a stretch of old ruined wall instead (Moonfall
## Ruins): lower, of grey blocks laid in courses.

const HEIGHT := 56.0  # a rock cliff's face; check_data.py uses it for both
const SHADOW := Color(0, 0, 0, 0.18)
const STYLES := {
	"rock": {
		"height": 56.0,
		"top": Color(0.58, 0.53, 0.48),
		"top_light": Color(0.66, 0.61, 0.55),
		"face": Color(0.4, 0.35, 0.32),
		"face_dark": Color(0.29, 0.25, 0.23),
		"edge": Color(0.84, 0.8, 0.72),
		"moss": Color(0.47, 0.55, 0.36)
	},
	"wall": {
		"height": 40.0,
		"top": Color(0.64, 0.65, 0.7),
		"top_light": Color(0.72, 0.73, 0.78),
		"face": Color(0.5, 0.51, 0.57),
		"face_dark": Color(0.36, 0.37, 0.43),
		"edge": Color(0.88, 0.88, 0.92),
		"moss": Color(0.44, 0.58, 0.38)
	}
}

## "rock", or "wall" (ruins).
var style: String = "rock"
var points := PackedVector2Array()
var _block := PackedVector2Array()  # the top and the face together
var _inner: Array = []
var _grooves: Array = []  # [top, bottom] lines down the face
var _moss: Array = []  # [position, size]
var _look: Dictionary = STYLES["rock"]


func _ready() -> void:
	add_to_group("cliffs")
	_look = STYLES.get(style, STYLES["rock"])
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


## The ground the cliff stands on: its top and the face below it (the top swept
## down in steps, so a thin wall stays one piece).
func block() -> PackedVector2Array:
	var merged := points
	for k in range(1, 5):
		var shifted := PackedVector2Array()
		for point in points:
			shifted.append(point + Vector2(0, float(_look["height"]) * k / 4.0))
		var largest := PackedVector2Array()
		for part in Geometry2D.merge_polygons(merged, shifted):
			if _area(part) > _area(largest):  # the outline (any hole is smaller)
				largest = part
		merged = largest
	return merged


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
		var height: float = _look["height"]
		if style == "wall":  # courses of blocks: a line along the middle, joints between
			_grooves.append([a + Vector2(0, height * 0.5), b + Vector2(0, height * 0.5)])
		var gap: float = 20.0 if style == "wall" else 26.0
		var steps: int = maxi(1, int(a.distance_to(b) / gap))
		for k in steps:
			if style == "wall":
				var joint: Vector2 = a.lerp(b, (k + 0.5) / steps)
				var low: bool = k % 2 == 1
				_grooves.append(
					[
						joint + Vector2(0, height * (0.5 if low else 0.0) + 2.0),
						joint + Vector2(0, height * (1.0 if low else 0.5) - 2.0)
					]
				)
				continue
			var top: Vector2 = a.lerp(b, (k + rng.randf_range(0.2, 0.8)) / steps)
			_grooves.append([top + Vector2(0, 6), top + Vector2(0, height - rng.randf_range(4, 18))])
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
	draw_colored_polygon(_block, _look["face"])
	for groove in _grooves:
		draw_line(groove[0], groove[1], _look["face_dark"], 3.0 if style == "rock" else 2.0)
	draw_colored_polygon(points, _look["top"])
	for inner in _inner:
		draw_colored_polygon(inner, _look["top_light"])
	for patch in _moss:
		draw_set_transform(patch[0], 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, patch[1], _look["moss"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var rim := points.duplicate()
	rim.append(points[0])
	draw_polyline(rim, _look["edge"], 3.0, true)
