extends CanvasLayer
## The on-screen controls (joystick and round buttons), put in place for the
## settings: mirrored for left-handed players, the joystick bigger or smaller,
## and everything clear of a phone's notch.

const Settings := preload("res://scripts/settings.gd")
const SafeArea := preload("res://scripts/ui/safe_area.gd")
## The joystick's touch zone at 100%.
const JOYSTICK_SIZE := 300.0

var _homes: Dictionary = {}


func _ready() -> void:
	add_to_group("touch_controls")
	for child in get_children():
		if child is Control:
			_homes[child] = SafeArea.home_of(child)
	apply_settings()


## Also called by the game menu after a setting changed.
func apply_settings() -> void:
	var mirrored: bool = Settings.get_value("left_handed") == true
	var margins: Array = SafeArea.margins(get_viewport())
	for control in _homes:
		SafeArea.place(control, _homes[control], margins, mirrored)
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
