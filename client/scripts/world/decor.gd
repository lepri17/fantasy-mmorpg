extends Node2D
## Small things that make a map look lived in (a maps.json object "decor":
## "kind" and "pos"): reeds, cattails, lily pads, flowers, pebbles, a log,
## mushrooms, bones, crystals. Drawn here; nothing to bump into. Each is a little
## different (seeded by where it stands).

const KINDS := [
	"reeds", "cattails", "lily", "flowers", "pebbles", "log", "mushrooms", "bones", "crystals"
]
## These lie flat, under the feet of whoever walks by; the rest stand up.
const FLAT := ["lily", "flowers", "pebbles", "bones", "mushrooms"]
const STALK := Color(0.36, 0.6, 0.3)
const STALK_LIGHT := Color(0.5, 0.74, 0.38)
const CATTAIL := Color(0.45, 0.29, 0.17)
const PAD := Color(0.33, 0.6, 0.32)
const PAD_DARK := Color(0.24, 0.46, 0.25)
const BARK := Color(0.5, 0.34, 0.21)
const BARK_DARK := Color(0.35, 0.23, 0.14)
const BONE := Color(0.94, 0.92, 0.84)
const CRYSTAL := [Color(0.56, 0.9, 1.0), Color(0.8, 0.66, 1.0)]
const PETALS := [
	Color(1.0, 0.72, 0.84), Color(1.0, 0.95, 0.6), Color(0.96, 0.96, 1.0), Color(0.8, 0.7, 1.0)
]

var kind: String = "reeds"


func _ready() -> void:
	if kind in FLAT:
		z_index = -4


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x) * 7919 + int(position.y) * 31
	match kind:
		"reeds":
			_reeds(rng, false)
		"cattails":
			_reeds(rng, true)
		"lily":
			_lily(rng)
		"flowers":
			_flowers(rng)
		"pebbles":
			_pebbles(rng)
		"log":
			_log()
		"mushrooms":
			_mushrooms(rng)
		"bones":
			_bones(rng)
		"crystals":
			_crystals(rng)


## A cluster of glowing crystal shards in the rock (Galeclaw Ridge).
func _crystals(rng: RandomNumberGenerator) -> void:
	var tint: Color = CRYSTAL[rng.randi() % CRYSTAL.size()]
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 28.0, Color(tint, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in rng.randi_range(3, 5):
		var base := Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-3.0, 3.0))
		var height: float = rng.randf_range(18.0, 40.0)
		var lean: float = rng.randf_range(-7.0, 7.0)
		var half: float = rng.randf_range(4.0, 7.0)
		var shoulder := Vector2(lean * 0.7, -height * 0.75)
		var tip := base + Vector2(lean, -height)
		draw_colored_polygon(
			PackedVector2Array(
				[base + Vector2(-half, 0), base + shoulder - Vector2(half, 0), tip, base]
			),
			tint.darkened(0.2)
		)
		draw_colored_polygon(
			PackedVector2Array(
				[base, tip, base + shoulder + Vector2(half, 0), base + Vector2(half, 0)]
			),
			tint.lightened(0.2)
		)


func _reeds(rng: RandomNumberGenerator, heads: bool) -> void:
	for i in rng.randi_range(5, 8):
		var base := Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-4.0, 4.0))
		var height: float = rng.randf_range(26.0, 46.0)
		var bend: float = rng.randf_range(-8.0, 8.0)
		var middle := base + Vector2(bend * 0.4, -height * 0.55)
		var top := base + Vector2(bend, -height)
		var color: Color = STALK if i % 2 else STALK_LIGHT
		draw_polyline(PackedVector2Array([base, middle, top]), color, 2.5, true)
		if heads and i % 2 == 0:
			draw_line(top + Vector2(0, 4), top + Vector2(bend * 0.1, 15), CATTAIL, 5.0, true)


func _lily(rng: RandomNumberGenerator) -> void:
	var radius: float = rng.randf_range(11.0, 16.0)
	_ellipse(Vector2.ZERO, Vector2(radius, radius * 0.62), PAD_DARK)
	_ellipse(Vector2(0, -1.5), Vector2(radius - 1.5, (radius - 1.5) * 0.6), PAD)
	draw_line(Vector2.ZERO, Vector2(radius * 0.9, -radius * 0.2), PAD_DARK, 2.0)
	if rng.randf() < 0.4:  # a flower on the pad
		for k in 5:
			var petal := Vector2(5, 0).rotated(TAU * k / 5.0) * Vector2(1, 0.6)
			_ellipse(petal + Vector2(-3, -4), Vector2(3.5, 2.4), Color(1.0, 0.76, 0.86))
		draw_circle(Vector2(-3, -4), 2.0, Color(1.0, 0.9, 0.5))


func _flowers(rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(4, 7):
		var at := Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-10.0, 10.0))
		var petal: Color = PETALS[rng.randi() % PETALS.size()]
		for k in 4:
			draw_circle(at + Vector2(2.6, 0).rotated(TAU * k / 4.0), 2.4, petal)
		draw_circle(at, 1.6, Color(1.0, 0.82, 0.3))


func _pebbles(rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(4, 6):
		var at := Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-8.0, 8.0))
		var shade: float = rng.randf_range(0.55, 0.75)
		var size := Vector2(rng.randf_range(3.0, 6.0), rng.randf_range(2.0, 3.5))
		_ellipse(at, size, Color(shade, shade, shade + 0.04))


func _log() -> void:
	draw_rect(Rect2(-34, -12, 68, 20), BARK)
	draw_line(Vector2(-30, -6), Vector2(28, -6), BARK_DARK, 2.0)
	draw_line(Vector2(-26, 2), Vector2(30, 2), BARK_DARK, 2.0)
	_ellipse(Vector2(34, -2), Vector2(6, 10), Color(0.78, 0.6, 0.4))
	_ellipse(Vector2(34, -2), Vector2(3, 5), BARK_DARK)
	_ellipse(Vector2(-12, -12), Vector2(7, 3), Color(0.42, 0.62, 0.32))


func _mushrooms(rng: RandomNumberGenerator) -> void:
	for i in 3:
		var at := Vector2(-12 + i * 12 + rng.randf_range(-3.0, 3.0), rng.randf_range(-4.0, 4.0))
		draw_rect(Rect2(at.x - 2, at.y - 6, 4, 7), Color(0.96, 0.92, 0.84))
		_ellipse(at + Vector2(0, -7), Vector2(6, 4), Color(0.86, 0.26, 0.24))
		draw_circle(at + Vector2(-2, -8), 1.1, Color.WHITE)
		draw_circle(at + Vector2(2.4, -6.6), 0.9, Color.WHITE)


func _bones(rng: RandomNumberGenerator) -> void:
	for i in 2:
		var at := Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-6.0, 6.0))
		var tilt := Vector2(10, 0).rotated(rng.randf_range(-0.6, 0.6))
		draw_line(at - tilt, at + tilt, BONE, 3.0)
		for end in [at - tilt, at + tilt]:
			draw_circle(end + Vector2(0, -1.6), 2.2, BONE)
			draw_circle(end + Vector2(0, 1.6), 2.2, BONE)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, radii.y / radii.x))
	draw_circle(Vector2.ZERO, radii.x, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
