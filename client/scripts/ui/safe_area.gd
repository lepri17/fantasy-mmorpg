extends RefCounted
## Keeps controls clear of a phone's notch or round corners: the screen's safe
## area as margins on the canvas, and a helper that moves controls inside them.
## On a computer the margins are 0.

## The most a margin may take, in canvas pixels.
const MAX_MARGIN := 120.0


## [left, top, right, bottom] margins in canvas pixels.
static func margins(viewport: Viewport) -> Array:
	if not OS.has_feature("mobile"):
		return [0.0, 0.0, 0.0, 0.0]
	var window: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return [0.0, 0.0, 0.0, 0.0]
	var scale: Vector2 = viewport.get_visible_rect().size / Vector2(window)
	var result: Array = [
		safe.position.x * scale.x,
		safe.position.y * scale.y,
		(window.x - safe.end.x) * scale.x,
		(window.y - safe.end.y) * scale.y,
	]
	return result.map(func(margin: float) -> float: return clampf(margin, 0.0, MAX_MARGIN))


## Where a control is anchored, remembered once so it can be moved again later.
static func home_of(control: Control) -> Array:
	return [
		control.anchor_left,
		control.anchor_right,
		control.offset_left,
		control.offset_right,
		control.anchor_top,
		control.offset_top,
		control.offset_bottom,
	]


## Puts a control back home, mirrored left-right if asked, then inside the
## margins: left-anchored ones move right, right-anchored ones left, top ones
## down and bottom ones up. Centred controls stay.
static func place(control: Control, home: Array, margins: Array, mirrored := false) -> void:
	var anchor_left: float = home[0]
	var anchor_right: float = home[1]
	var left: float = home[2]
	var right: float = home[3]
	if mirrored:
		anchor_left = 1.0 - home[1]
		anchor_right = 1.0 - home[0]
		left = -home[3]
		right = -home[2]
	var shift_x: float = 0.0
	if anchor_right <= 0.0:
		shift_x = margins[0]
	elif anchor_left >= 1.0:
		shift_x = -margins[2]
	var full_width: bool = anchor_left == 0.0 and anchor_right == 1.0
	control.anchor_left = anchor_left
	control.anchor_right = anchor_right
	control.offset_left = left + shift_x + (margins[0] if full_width else 0.0)
	control.offset_right = right + shift_x - (margins[2] if full_width else 0.0)
	var shift_y: float = 0.0
	if home[4] <= 0.0:
		shift_y = margins[1]
	elif home[4] >= 1.0:
		shift_y = -margins[3]
	control.offset_top = home[5] + shift_y
	control.offset_bottom = home[6] + shift_y
