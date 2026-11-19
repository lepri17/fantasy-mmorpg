extends Node2D
## Softens the ground of a map (maps.json "ground"), so it does not look like
## a grid of squares. Where two kinds of ground meet, the one that grows over
## the other (SPILL) creeps across the border in a wavy band, drawn with its
## own texture from tiles.png; where it touches a cell only at a corner, the
## corner is rounded. On top, a few small things lie about on each kind of
## ground: tufts and flowers on grass, leaves in the woods, pebbles and cracks
## on paths and stone, shells on sand, sparkles on snow and ice. Along the
## map's edges, except where a road leads out, a frame of bushes (or rocks, or
## snow banks) closes the picture, as MapleStory's maps never just stop. The
## shapes are worked out once, in setup(); _draw() only paints them.

const GameData := preload("res://scripts/data/game_data.gd")
const TEXTURE := preload("res://assets/environment/tiles.png")
## Which ground grows over which at a border: the higher creeps onto the lower.
const SPILL := {
	"snow": 8,
	"grass": 7,
	"forest": 7,
	"twilight": 7,
	"grove": 7,
	"sand": 5,
	"crag": 4,
	"ruin": 3,
	"stone": 3,
	"path": 2,
	"ice": 1,
	"cellar": 0
}
const SIDES := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const CORNERS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
const STEP := 8.0  # pixels between the points of a wavy edge
const TAPER := 44.0  # a band that stops thins out over this many pixels
const RIM := Color(0, 0, 0, 0.12)  # a soft shadow along each wavy edge

## How many wavy bands and rounded corners the map has (the smoke test reads it).
var bands: int = 0
var _kinds: Array = []  # rows of kind numbers (tiles.png order)
var _names: Array = []
var _size: float = 128.0
var _cols: int = 0
var _rows: int = 0
var _shapes: Array = []  # [points, uvs, rim] for each band and corner
var _gaps: Array = []  # [side, from, to]: where roads lead out, no frame


## rows: maps.json "ground"; roads: its "exit" objects (left open in the frame).
func setup(rows: Array, roads: Array = []) -> void:
	for road in roads:
		_gaps.append([road["side"], float(road["span"][0]) - 50.0, float(road["span"][1]) + 50.0])
	var maps: Dictionary = GameData.table("maps")
	_names = maps["tile_kinds"]
	_size = float(maps["tile_size"])
	var legend: Dictionary = maps["legend"]
	_rows = rows.size()
	_cols = String(rows[0]).length()
	for row in rows:
		var line: Array = []
		for letter in String(row):
			line.append(_names.find(legend[letter]))
		_kinds.append(line)
	z_index = -9  # just over the ground, under water, cliffs and everyone
	for y in _rows:
		for x in _cols:
			_edges_of(Vector2i(x, y))
	bands = _shapes.size()


func _edges_of(cell: Vector2i) -> void:
	var mine: int = _rank(_kind(cell))
	for side in SIDES:
		var other: int = _kind(cell + side)
		if _rank(other) > mine:
			_band(cell, side, other)
	for corner in CORNERS:
		var other: int = _kind(cell + corner)
		if _has_corner(cell, corner, other):
			_round_corner(cell, corner, other)


## True when the neighbour's ground touches this cell only at `corner`, so the
## cell gets a rounded corner of it.
func _has_corner(cell: Vector2i, corner: Vector2i, other: int) -> bool:
	return (
		_rank(other) > _rank(_kind(cell))
		and _kind(cell + corner) == other
		and _kind(cell + Vector2i(corner.x, 0)) != other
		and _kind(cell + Vector2i(0, corner.y)) != other
	)


## A wavy band of the neighbour's ground along one side of this cell. It runs
## on into the next cell when that one has the same border, else it thins out.
func _band(cell: Vector2i, side: Vector2i, other: int) -> void:
	var along_cell := Vector2i(absi(side.y), absi(side.x))
	var along := Vector2(along_cell)
	var inward := -Vector2(side)
	var origin := Vector2(cell) * _size
	var start: Vector2 = origin + Vector2(maxi(side.x, 0), maxi(side.y, 0)) * _size
	var thin_start: bool = not _runs_on(cell, cell - along_cell, side, other)
	var thin_end: bool = not _runs_on(cell, cell + along_cell, side, other)
	var line: float = start.x if side.x != 0 else start.y  # the border's place, for its waves
	var points := PackedVector2Array([start])
	var rim := PackedVector2Array()
	var t: float = 0.0
	while t <= _size + 0.1:
		var depth: float = _wave((start + along * t).dot(along), line)
		if thin_start:
			depth *= smoothstep(0.0, TAPER, t)
		if thin_end:
			depth *= smoothstep(0.0, TAPER, _size - t)
		var point: Vector2 = start + along * t + inward * depth
		if point.distance_to(points[points.size() - 1]) > 0.5:
			points.append(point)
		rim.append(point)
		t += STEP
	var end: Vector2 = start + along * _size
	if end.distance_to(points[points.size() - 1]) > 0.5:
		points.append(end)
	_add_shape(points, origin, other, cell + side, rim)


## True when the border goes on through the next cell too (or the neighbour's
## ground fills it, or turns round a corner there), so a band need not thin
## out there. At an outer corner (where two roads meet, say) the band runs on
## into the next cell's rounded corner; thinned out, it left the tile's square
## corner showing.
func _runs_on(cell: Vector2i, next: Vector2i, side: Vector2i, other: int) -> bool:
	if _kind(next) < 0:
		return true  # it runs off the map
	if _kind(next) == other or _kind(next + side) == other:
		return true
	return _has_corner(next, cell + side - next, other)


## A rounded corner of the neighbour's ground, where it touches this cell only
## at a corner. It reaches as far as the bands beside it end, so they join it
## without a step: across as far as the band in the cell above or below goes,
## down or up as far as the band in the cell beside.
func _round_corner(cell: Vector2i, corner: Vector2i, other: int) -> void:
	var origin := Vector2(cell) * _size
	var at: Vector2 = origin + Vector2(maxi(corner.x, 0), maxi(corner.y, 0)) * _size
	var inward := -Vector2(corner)
	var fallback: float = 22.0 + 6.0 * sin(at.x * 0.031 + at.y * 0.047)
	var across: float = fallback  # the band in the cell above or below runs down a side
	if _rank(other) > _rank(_kind(cell + Vector2i(0, corner.y))):
		across = _wave(at.y, at.x)
	var down: float = fallback  # the band in the cell beside runs along a top or bottom
	if _rank(other) > _rank(_kind(cell + Vector2i(corner.x, 0))):
		down = _wave(at.x, at.y)
	var points := PackedVector2Array([at])
	var rim := PackedVector2Array()
	for i in 9:
		var angle: float = PI * 0.5 * i / 8.0
		var bulge: float = 1.0 + 0.12 * sin(PI * i / 8.0)  # rounder in the middle, exact at the ends
		var point: Vector2 = (
			at + Vector2(cos(angle) * inward.x * across, sin(angle) * inward.y * down) * bulge
		)
		points.append(point)
		rim.append(point)
	_add_shape(points, origin, other, cell + corner, rim)


## Keeps a shape with texture coordinates from the neighbour's tile. The
## tiles are seamless, so its texture at this cell's own coordinates carries
## straight on across the border.
func _add_shape(
	points: PackedVector2Array, origin: Vector2, kind: int, source: Vector2i, rim: PackedVector2Array
) -> void:
	var column: int = kind * 2 + posmod(hash(source), 2)
	var width: float = TEXTURE.get_width()
	var height: float = TEXTURE.get_height()
	var uvs := PackedVector2Array()
	for point in points:
		var local: Vector2 = (point - origin).clamp(Vector2.ONE * 0.5, Vector2.ONE * (_size - 0.5))
		uvs.append(Vector2((column * _size + local.x) / width, local.y / height))
	_shapes.append([points, uvs, rim])


## How far a band reaches into the cell at a place along the border: waves
## that carry on from one cell to the next.
func _wave(along: float, line: float) -> float:
	return (
		17.0
		+ 8.0 * sin(along * 0.049 + line * 0.013)
		+ 5.0 * sin(along * 0.131 + line * 0.021 + 1.3)
	)


func _kind(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= _cols or cell.y >= _rows:
		return -1
	return _kinds[cell.y][cell.x]


func _rank(kind: int) -> int:
	return -1 if kind < 0 else int(SPILL.get(_names[kind], 0)) * 16 + kind


func _draw() -> void:
	for shape in _shapes:
		draw_polygon(shape[0], PackedColorArray([Color.WHITE]), shape[1], TEXTURE)
		draw_polyline(shape[2], RIM, 3.0, true)
	for y in _rows:
		for x in _cols:
			_draw_details(Vector2i(x, y))
	_draw_frame()


## Clumps of bush, rock or snow along each edge, half over it.
func _draw_frame() -> void:
	var size := Vector2(_cols, _rows) * _size
	var rng := RandomNumberGenerator.new()
	rng.seed = _cols * 1000 + _rows
	for side in ["north", "south", "west", "east"]:
		var length: float = size.x if side in ["north", "south"] else size.y
		var along: float = rng.randf_range(0.0, 30.0)
		while along < length:
			var open: bool = _gaps.any(
				func(gap): return gap[0] == side and along > gap[1] and along < gap[2]
			)
			if not open:
				var at: Vector2 = {
					"north": Vector2(along, 6), "south": Vector2(along, size.y - 6),
					"west": Vector2(6, along), "east": Vector2(size.x - 6, along)
				}[side]
				_clump(at, _kind(Vector2i((at / _size).floor()).clamp(
					Vector2i.ZERO, Vector2i(_cols - 1, _rows - 1)
				)), rng)
			along += rng.randf_range(38.0, 56.0)


func _clump(at: Vector2, kind_index: int, rng: RandomNumberGenerator) -> void:
	var kind: String = _names[kind_index]
	var radius: float = rng.randf_range(22.0, 32.0)
	var dark: Color
	var mid: Color
	var light: Color
	if kind in ["grass", "forest", "twilight", "grove"]:
		dark = Color(0.16, 0.36, 0.2)
		mid = Color(0.26, 0.52, 0.27)
		light = Color(0.45, 0.7, 0.36)
		if kind in ["twilight", "grove"]:
			dark = Color(0.1, 0.24, 0.22)
			mid = Color(0.16, 0.36, 0.3)
			light = Color(0.28, 0.5, 0.4)
	elif kind in ["snow", "ice"]:
		dark = Color(0.68, 0.76, 0.9)
		mid = Color(0.88, 0.92, 0.98)
		light = Color(1, 1, 1)
	else:
		dark = Color(0.36, 0.34, 0.36)
		mid = Color(0.54, 0.52, 0.52)
		light = Color(0.7, 0.68, 0.66)
	draw_circle(at + Vector2(3, 5), radius, Color(0, 0, 0, 0.18))
	draw_circle(at, radius, dark)
	draw_circle(at + Vector2(-radius * 0.15, -radius * 0.18), radius * 0.78, mid)
	draw_circle(at + Vector2(-radius * 0.35, -radius * 0.4), radius * 0.32, light)


## A few small things lying on a cell, by its kind of ground (always the same
## for the same cell).
func _draw_details(cell: Vector2i) -> void:
	var kind: String = _names[_kind(cell)]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) + 7
	for i in rng.randi_range(0, 2):
		var at: Vector2 = Vector2(cell) * _size + Vector2(
			rng.randf_range(14.0, _size - 14.0), rng.randf_range(14.0, _size - 14.0)
		)
		var roll: float = rng.randf()
		match kind:
			"grass":
				if roll < 0.55:
					_tuft(at, Color(0.3, 0.55, 0.22, 0.8))
				elif roll < 0.85:
					_flower(at, [Color.WHITE, Color(1, 0.86, 0.3), Color(1, 0.62, 0.75)][i % 3])
				else:
					_pebble(at, Color(0.62, 0.62, 0.58), rng)
			"forest", "twilight", "grove":
				if roll < 0.6:
					_leaf(at, rng, kind)
				elif roll < 0.85:
					_tuft(at, Color(0.18, 0.32, 0.2, 0.7))
				else:
					_mushroom(at, kind)
			"path", "stone", "ruin", "crag":
				if roll < 0.55:
					_pebble(at, Color(0.55, 0.5, 0.45) if kind == "path" else Color(0.6, 0.6, 0.62), rng)
				elif roll < 0.85 or kind != "ruin":
					_crack(at, rng)
				else:
					_tuft(at, Color(0.35, 0.55, 0.3, 0.75))
			"sand":
				if roll < 0.5:
					_shell(at)
				else:
					_pebble(at, Color(0.72, 0.64, 0.5), rng)
			"snow", "ice":
				if roll < 0.6:
					_sparkle(at)
				elif kind == "snow":
					_lump(at)
				else:
					_crack(at, rng, Color(1, 1, 1, 0.5))


func _tuft(at: Vector2, color: Color) -> void:
	for blade in [Vector2(-4, -7), Vector2(0, -10), Vector2(4, -7)]:
		draw_line(at, at + blade, color, 2.0, true)


func _flower(at: Vector2, petal: Color) -> void:
	for i in 5:
		draw_circle(at + Vector2.from_angle(TAU * i / 5.0) * 2.8, 2.2, petal)
	draw_circle(at, 1.6, Color(0.95, 0.72, 0.2))


func _pebble(at: Vector2, color: Color, rng: RandomNumberGenerator) -> void:
	var size: float = rng.randf_range(2.5, 4.5)
	draw_set_transform(at, 0.0, Vector2(1.0, 0.68))
	draw_circle(Vector2(0, 1.2), size, Color(0, 0, 0, 0.15))
	draw_circle(Vector2.ZERO, size, color)
	draw_circle(Vector2(-size * 0.3, -size * 0.35), size * 0.35, Color(1, 1, 1, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _leaf(at: Vector2, rng: RandomNumberGenerator, kind: String) -> void:
	var colors: Array = [Color(0.62, 0.6, 0.25), Color(0.72, 0.45, 0.2), Color(0.45, 0.55, 0.22)]
	if kind == "twilight":
		colors = [Color(0.38, 0.32, 0.48), Color(0.3, 0.42, 0.45), Color(0.48, 0.36, 0.3)]
	draw_set_transform(at, rng.randf_range(0.0, TAU), Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 4.5, colors[rng.randi_range(0, colors.size() - 1)])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _mushroom(at: Vector2, kind: String) -> void:
	var cap: Color = Color(0.45, 0.85, 0.95) if kind == "twilight" else Color(0.78, 0.3, 0.22)
	draw_line(at, at + Vector2(0, -5), Color(0.92, 0.88, 0.78), 2.0)
	draw_set_transform(at + Vector2(0, -5), 0.0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, 4.0, cap)
	draw_circle(Vector2(-1.2, -1.0), 0.9, Color(1, 1, 1, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _crack(at: Vector2, rng: RandomNumberGenerator, color: Color = Color(0, 0, 0, 0.16)) -> void:
	var points := PackedVector2Array([at])
	var heading: float = rng.randf_range(0.0, TAU)
	for i in 3:
		heading += rng.randf_range(-0.7, 0.7)
		points.append(points[i] + Vector2.from_angle(heading) * rng.randf_range(5.0, 9.0))
	draw_polyline(points, color, 1.5, true)


func _shell(at: Vector2) -> void:
	draw_circle(at, 3.4, Color(0.97, 0.9, 0.84))
	for i in 3:
		draw_line(at, at + Vector2.from_angle(-PI * (0.25 + 0.25 * i)) * 3.2, Color(0.8, 0.66, 0.6), 1.0)


func _sparkle(at: Vector2) -> void:
	draw_line(at - Vector2(4, 0), at + Vector2(4, 0), Color(1, 1, 1, 0.75), 1.2)
	draw_line(at - Vector2(0, 4), at + Vector2(0, 4), Color(1, 1, 1, 0.75), 1.2)
	draw_circle(at, 1.3, Color.WHITE)


func _lump(at: Vector2) -> void:
	draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2(0, 2), 7.0, Color(0.72, 0.8, 0.94, 0.55))
	draw_circle(Vector2.ZERO, 6.5, Color(0.98, 0.99, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
