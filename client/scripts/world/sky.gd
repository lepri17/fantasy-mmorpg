extends RefCounted
## W8: the light of the day from the device clock. A 16-minute cycle of day,
## dusk, night and dawn, and rain in some cycles. Cosmetic only; game.gd tints
## the world with it and lights up the warrior when it is dark.

const CYCLE_MINUTES := 16.0
const DAY := Color(1, 1, 1)
const DUSK := Color(0.98, 0.78, 0.66)
const NIGHT := Color(0.42, 0.48, 0.74)
## Cellars and other maps marked "indoor" in maps.json.
const INDOOR := Color(0.5, 0.46, 0.6)
## [point in the cycle 0..1, colour], in order.
const STEPS := [
	[0.0, DAY], [0.5, DAY], [0.58, DUSK], [0.66, NIGHT], [0.9, NIGHT], [0.97, DUSK], [1.0, DAY]
]


## The light outdoors at a moment (seconds since midnight).
static func daylight(seconds: float) -> Color:
	var cycle: float = fposmod(seconds / 60.0, CYCLE_MINUTES) / CYCLE_MINUTES
	for i in STEPS.size() - 1:
		var step: Array = STEPS[i]
		var next: Array = STEPS[i + 1]
		if cycle <= next[0]:
			var part: float = (cycle - step[0]) / maxf(0.0001, next[0] - step[0])
			return (step[1] as Color).lerp(next[1], part)
	return DAY


## How dark a light colour is: 0 by day, 1 at night or deeper.
static func darkness(light: Color) -> float:
	return clampf((1.0 - light.v) / (1.0 - NIGHT.v), 0.0, 1.0)


## Rain in every third cycle, for a while in the middle of the day.
static func raining(seconds: float) -> bool:
	var cycle_count: int = int(seconds / 60.0 / CYCLE_MINUTES)
	var cycle: float = fposmod(seconds / 60.0, CYCLE_MINUTES) / CYCLE_MINUTES
	return cycle_count % 3 == 1 and cycle > 0.2 and cycle < 0.45


## A soft round light for PointLight2D: bright in the middle, gone at the edge.
static func light_texture(size: int = 256) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture
