extends "res://scripts/maps/portal.gd"
## A road out of the map at one of its edges (a maps.json object of type
## "exit": "side" north/south/east/west, "span" [from, to] along that edge in
## pixels, and "to" and "spawn" like a portal). Walking into it goes on into
## the next map, so the maps join into one open world. Chevrons on the ground
## and the next place's name show where the road leads. It is in the "portals"
## group, like a portal, so the minimap and AUTO find it too.

## How far into the map the trigger reaches from the edge wall.
const DEPTH := 64.0
## The edge walls of a map, as in game_map.gd EDGE_MARGINS: left, top, right, bottom.
const WALLS := [24.0, 80.0, 24.0, 20.0]
const CHEVRON := Color(1.0, 0.92, 0.6)

var side: String = "east"
var span := Vector2.ZERO
var map_size := Vector2.ZERO
var _outward := Vector2.RIGHT


## The middle of the trigger for an exit on this side of a map this big.
static func spot(exit_side: String, exit_span: Vector2, size: Vector2) -> Vector2:
	var middle: float = (exit_span.x + exit_span.y) / 2.0
	match exit_side:
		"west":
			return Vector2(WALLS[0] + DEPTH / 2.0, middle)
		"east":
			return Vector2(size.x - WALLS[2] - DEPTH / 2.0, middle)
		"north":
			return Vector2(middle, WALLS[1] + DEPTH / 2.0)
	return Vector2(middle, size.y - WALLS[3] - DEPTH / 2.0)


func _ready() -> void:
	position = spot(side, span, map_size)
	var outwards := {"west": Vector2.LEFT, "east": Vector2.RIGHT, "north": Vector2.UP}
	_outward = outwards.get(side, Vector2.DOWN)
	var length: float = absf(span.y - span.x)
	var box := RectangleShape2D.new()
	box.size = Vector2(DEPTH, length) if side in ["west", "east"] else Vector2(length, DEPTH)
	var shape := CollisionShape2D.new()
	shape.shape = box
	add_child(shape)
	super._ready()
	# The name stands a little way into the map, where the road comes in.
	_label.position = -_outward * 92.0 - _label.size / 2.0


func _draw() -> void:
	var across := Vector2(-_outward.y, _outward.x)
	for i in 3:
		var shift: float = fmod(_spin * 14.0 + i * 22.0, 66.0) - 44.0
		var alpha: float = 0.55 * (1.0 - absf(shift + 11.0) / 33.0)
		if alpha <= 0.0:
			continue
		var tip: Vector2 = _outward * shift
		var color := Color(CHEVRON.r, CHEVRON.g, CHEVRON.b, alpha)
		var arms := PackedVector2Array(
			[tip - _outward * 14.0 + across * 20.0, tip, tip - _outward * 14.0 - across * 20.0]
		)
		draw_polyline(arms, color, 4.0, true)
