extends RefCounted
## Text that pops up above a character, floats upwards and fades:
## damage numbers, "LEVEL UP!", "+5 G" and so on.
## Q11: finished labels wait in a pool node (game.gd adds it) and are used
## again, instead of a new label for every number.

const POOL_GROUP := "floating_text_pool"
## The pool keeps at most this many labels.
const POOL_SIZE := 40


static func spawn(
	parent: Node, text: String, color: Color, height: float = 80.0, font_size: int = 26
) -> void:
	var label: Label = _take(parent)
	label.visible = true
	label.modulate.a = 1.0
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
	tween.tween_callback(_put_back.bind(label))


static func _take(parent: Node) -> Label:
	var pool: Node = parent.get_tree().get_first_node_in_group(POOL_GROUP)
	if pool != null and pool.get_child_count() > 0:
		var label: Label = pool.get_child(pool.get_child_count() - 1)
		pool.remove_child(label)
		return label
	return Label.new()


static func _put_back(label: Label) -> void:
	if not is_instance_valid(label) or not label.is_inside_tree():
		return
	var pool: Node = label.get_tree().get_first_node_in_group(POOL_GROUP)
	if pool == null or pool.get_child_count() >= POOL_SIZE:
		label.queue_free()
		return
	label.visible = false
	label.get_parent().remove_child(label)
	pool.add_child(label)
