extends RefCounted
## Text that pops up above a character, floats upwards and fades:
## damage numbers, "LEVEL UP!", "+5 G" and so on.


static func spawn(
	parent: Node, text: String, color: Color, height: float = 80.0, font_size: int = 26
) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 10
	label.custom_minimum_size = Vector2(200, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-100, -height)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.1))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)
