extends Control
## The warrior's health bar on the HUD: name on top, bar with numbers below.
## The HUD calls set_values(current, maximum) whenever the player's HP changes.

const CHARACTER_NAME := "Warrior"
const BAR_TOP := 26.0

var _current: int = 1
var _maximum: int = 1


func set_values(current: int, maximum: int) -> void:
	_current = current
	_maximum = maximum
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var bar_rect := Rect2(0.0, BAR_TOP, size.x, size.y - BAR_TOP)
	var ratio: float = clampf(float(_current) / float(maxi(_maximum, 1)), 0.0, 1.0)

	draw_string(font, Vector2(2, 20), CHARACTER_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_rect(bar_rect.grow(3.0), Color(0.1, 0.06, 0.1, 0.8))
	var fill_size := Vector2(bar_rect.size.x * ratio, bar_rect.size.y)
	draw_rect(Rect2(bar_rect.position, fill_size), Color(0.85, 0.2, 0.28))
	draw_string(
		font,
		bar_rect.position + Vector2(10, bar_rect.size.y - 6.0),
		"HP %d / %d" % [_current, _maximum],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE
	)
