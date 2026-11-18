extends CanvasLayer
## The on-screen controls (joystick and round buttons), put in place for the
## settings: mirrored for left-handed players, moved and resized in the button
## editor (U4), the joystick bigger or smaller, and clear of a phone's notch.

const Settings := preload("res://scripts/settings.gd")
const SafeArea := preload("res://scripts/ui/safe_area.gd")
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const BUTTON_SCALES := [0.8, 0.9, 1.0, 1.1, 1.2, 1.3]
## The joystick's touch zone at 100%.
const JOYSTICK_SIZE := 300.0

## True while the button editor is open (the game is paused then).
var editing: bool = false
var _homes: Dictionary = {}
var _editor: Control
var _scale_label: Label
var _dragged: Control = null
var _drag_total := Vector2.ZERO


func _ready() -> void:
	add_to_group("touch_controls")
	for child in get_children():
		if child is Control:
			_homes[child] = SafeArea.home_of(child)
	_build_editor()
	apply_settings()


## U4: drag the joystick and the buttons to new places, and make the buttons
## bigger or smaller. The game pauses meanwhile; DONE saves and goes on.
func start_editing() -> void:
	editing = true
	_editor.show()
	_refresh_editor()
	get_tree().paused = true


func stop_editing() -> void:
	editing = false
	_dragged = null
	_editor.hide()
	get_tree().paused = false


## Also called by the game menu after a setting changed.
func apply_settings() -> void:
	var mirrored: bool = Settings.get_value("left_handed") == true
	var margins: Array = SafeArea.margins(get_viewport())
	var offsets: Dictionary = Settings.get_value("button_offsets")
	var button_scale: float = float(Settings.get_value("button_scale"))
	for control in _homes:
		SafeArea.place(control, _homes[control], margins, mirrored)
		var moved: Array = offsets.get(String(control.name), [0.0, 0.0])
		var dx: float = float(moved[0]) * (-1.0 if mirrored else 1.0)
		control.offset_left += dx
		control.offset_right += dx
		control.offset_top += float(moved[1])
		control.offset_bottom += float(moved[1])
		if control.name != "Joystick" and not is_equal_approx(button_scale, 1.0):
			_resize(control, button_scale)
	var joystick := get_node_or_null("Joystick") as Control
	if joystick == null:
		return
	var factor: float = clampf(float(Settings.get_value("joystick_size")), 0.6, 1.6)
	var side: float = JOYSTICK_SIZE * factor
	# It grows from the corner it is anchored to: bottom left, or bottom right.
	if joystick.anchor_left >= 1.0:
		joystick.offset_left = joystick.offset_right - side
	else:
		joystick.offset_right = joystick.offset_left + side
	joystick.offset_top = joystick.offset_bottom - side
	joystick.set("size_scale", factor)
	joystick.set("floating", Settings.get_value("floating_joystick") == true)


## Bigger or smaller around its middle.
func _resize(control: Control, factor: float) -> void:
	var middle := Vector2(
		(control.offset_left + control.offset_right) / 2.0,
		(control.offset_top + control.offset_bottom) / 2.0
	)
	var half := Vector2(
		(control.offset_right - control.offset_left) / 2.0,
		(control.offset_bottom - control.offset_top) / 2.0
	) * factor
	control.offset_left = middle.x - half.x
	control.offset_right = middle.x + half.x
	control.offset_top = middle.y - half.y
	control.offset_bottom = middle.y + half.y


## A full-screen layer over the controls while editing: it takes the drags,
## with a bar at the top (size, RESET, DONE). It works while the game is paused.
func _build_editor() -> void:
	_editor = Control.new()
	_editor.name = "ButtonEditor"
	_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_editor.process_mode = Node.PROCESS_MODE_ALWAYS
	_editor.mouse_filter = Control.MOUSE_FILTER_STOP
	_editor.gui_input.connect(_on_editor_input)
	_editor.draw.connect(_draw_frames)
	_editor.hide()
	add_child(_editor)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.frame_style())
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -330.0
	bar.offset_right = 330.0
	bar.offset_top = 120.0  # under the hero panel and the MENU button
	bar.offset_bottom = 224.0
	_editor.add_child(bar)
	var stack := VBoxContainer.new()
	bar.add_child(stack)
	var hint := UiStyle.label("Drag the buttons to move them.", 18, Color.WHITE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	stack.add_child(row)
	var blue := Color(0.22, 0.32, 0.55)
	var smaller := UiStyle.button("SIZE -", blue, Vector2(100, 48))
	smaller.pressed.connect(_change_size.bind(-1))
	row.add_child(smaller)
	_scale_label = UiStyle.label("", 18, UiStyle.GOLD_TEXT)
	row.add_child(_scale_label)
	var bigger := UiStyle.button("SIZE +", blue, Vector2(100, 48))
	bigger.pressed.connect(_change_size.bind(1))
	row.add_child(bigger)
	var reset := UiStyle.button("RESET", Color(0.5, 0.3, 0.18), Vector2(110, 48))
	reset.pressed.connect(_reset_layout)
	row.add_child(reset)
	var done := UiStyle.button("DONE", Color(0.22, 0.48, 0.3), Vector2(110, 48))
	done.pressed.connect(stop_editing)
	row.add_child(done)


func _refresh_editor() -> void:
	_scale_label.text = "Buttons %d%%" % roundi(float(Settings.get_value("button_scale")) * 100.0)
	_editor.queue_redraw()


## A gold frame around everything that can be moved.
func _draw_frames() -> void:
	for control in _homes:
		if control.visible:
			_editor.draw_rect(control.get_global_rect(), UiStyle.GOLD_TEXT, false, 3.0)


## A drag moves what is under the finger; it is saved when the finger lifts.
func _on_editor_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragged = _control_at(event.position)
			_drag_total = Vector2.ZERO
		elif _dragged != null:
			var control: Control = _dragged
			_dragged = null
			move_control(control, _drag_total)
	elif event is InputEventMouseMotion and _dragged != null:
		var step: Vector2 = _inside_screen(_dragged, event.relative)
		_drag_total += step
		_dragged.offset_left += step.x
		_dragged.offset_right += step.x
		_dragged.offset_top += step.y
		_dragged.offset_bottom += step.y
		_editor.queue_redraw()


## Moves one control by an amount and keeps it in the settings (by its name).
func move_control(control: Control, amount: Vector2) -> void:
	var offsets: Dictionary = Settings.get_value("button_offsets").duplicate()
	var moved: Array = offsets.get(String(control.name), [0.0, 0.0])
	var mirrored: bool = Settings.get_value("left_handed") == true
	var dx: float = amount.x * (-1.0 if mirrored else 1.0)
	offsets[String(control.name)] = [float(moved[0]) + dx, float(moved[1]) + amount.y]
	Settings.set_value("button_offsets", offsets)
	apply_settings()
	_editor.queue_redraw()


## The part of a move that keeps the control on the screen.
func _inside_screen(control: Control, amount: Vector2) -> Vector2:
	var screen: Rect2 = _editor.get_global_rect()
	var rect: Rect2 = control.get_global_rect()
	return Vector2(
		clampf(amount.x, screen.position.x - rect.position.x, screen.end.x - rect.end.x),
		clampf(amount.y, screen.position.y - rect.position.y, screen.end.y - rect.end.y)
	)


func _control_at(point: Vector2) -> Control:
	for control in _homes:
		if control.visible and control.get_global_rect().has_point(point):
			return control
	return null


func _change_size(step: int) -> void:
	var now: float = float(Settings.get_value("button_scale"))
	var index: int = 0
	for each in BUTTON_SCALES.size():
		if absf(BUTTON_SCALES[each] - now) < absf(BUTTON_SCALES[index] - now):
			index = each
	index = clampi(index + step, 0, BUTTON_SCALES.size() - 1)
	Settings.set_value("button_scale", BUTTON_SCALES[index])
	apply_settings()
	_refresh_editor()


func _reset_layout() -> void:
	Settings.set_value("button_offsets", {})
	Settings.set_value("button_scale", 1.0)
	apply_settings()
	_refresh_editor()
