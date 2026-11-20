extends Node2D
## Small health bar with a name line, floating above a character in the world.
## The owner calls set_values() when its HP changes and set_label() once.
## A quiet bar (a plain monster's) shows only once it is hurt, as in
## MapleStory; at full health it draws nothing at all, so 20 monsters on a map
## do not cost 60 draw calls a frame.

const BAR_SIZE := Vector2(56, 8)
const LABEL_WIDTH := 160.0

var quiet: bool = false:
	set(value):
		quiet = value
		queue_redraw()
var _ratio: float = 1.0
var _label: String = ""


func set_values(current: int, maximum: int) -> void:
	_ratio = clampf(float(current) / float(maxi(maximum, 1)), 0.0, 1.0)
	queue_redraw()


func set_label(text: String) -> void:
	_label = text
	queue_redraw()


## True when the bar draws anything (tests read it).
func showing() -> bool:
	return not quiet or _ratio < 1.0


func _draw() -> void:
	if not showing():
		return
	var origin: Vector2 = -BAR_SIZE / 2.0
	var frame := Rect2(origin - Vector2(2, 2), BAR_SIZE + Vector2(4, 4))
	draw_rect(frame, Color(0.15, 0.08, 0.12, 0.85))
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _ratio, BAR_SIZE.y)), Color(0.9, 0.25, 0.3))
	if _label.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var text_position := Vector2(-LABEL_WIDTH / 2.0, origin.y - 8.0)
	var centered: int = HORIZONTAL_ALIGNMENT_CENTER
	var outline_color := Color(0.15, 0.08, 0.12)
	var label: String = tr(_label)
	draw_string_outline(font, text_position, label, centered, LABEL_WIDTH, 14, 4, outline_color)
	draw_string(font, text_position, label, centered, LABEL_WIDTH, 14, Color.WHITE)


## Texts drawn by hand follow a change of language too.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()
