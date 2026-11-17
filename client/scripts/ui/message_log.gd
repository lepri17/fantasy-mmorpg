extends VBoxContainer
## The last few game messages at the bottom of the screen ("+20 EXP",
## "Picked up Red Potion."), newest at the bottom. Each one fades out.

const MAX_LINES := 5
const SHOW_SECONDS := 4.0
const FADE_SECONDS := 0.6
const OUTLINE := Color(0.1, 0.05, 0.1)


func add_message(text: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	while get_child_count() > MAX_LINES:
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var fade := label.create_tween()
	fade.tween_interval(SHOW_SECONDS)
	fade.tween_property(label, "modulate:a", 0.0, FADE_SECONDS)
	fade.tween_callback(label.queue_free)
