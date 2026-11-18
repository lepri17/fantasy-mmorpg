extends RefCounted
## The shared look of the HUD windows (inventory, character): a framed panel,
## labels and buttons. Static helpers only.

const GOLD_TEXT := Color(1.0, 0.86, 0.45)
const FRAME_BORDER := Color(0.85, 0.68, 0.32)


static func label(text: String, font_size: int, color: Color) -> Label:
	var new_label := Label.new()
	new_label.text = text
	new_label.add_theme_font_size_override("font_size", font_size)
	new_label.add_theme_color_override("font_color", color)
	return new_label


static func button(text: String, color: Color, min_size: Vector2) -> Button:
	var new_button := Button.new()
	new_button.text = text
	new_button.custom_minimum_size = min_size
	new_button.focus_mode = Control.FOCUS_NONE
	new_button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		if state == "hover":
			box.bg_color = color.lightened(0.15)
		elif state == "pressed":
			box.bg_color = color.darkened(0.25)
		box.border_color = FRAME_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(10)
		new_button.add_theme_stylebox_override(state, box)
	return new_button


## Greys a button out when it would do nothing.
static func set_enabled(target: Button, enabled: bool) -> void:
	target.disabled = not enabled
	target.modulate.a = 1.0 if enabled else 0.45


static func frame_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.06, 0.1, 0.9)
	box.border_color = FRAME_BORDER
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(14)
	return box
