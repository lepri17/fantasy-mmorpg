extends PanelContainer
## The game menu: the MENU button, Esc, or the phone's back button opens it,
## and the game pauses while it is open. Its pages: the menu (RESUME, SETTINGS,
## CONTROLS, CHANGE HERO), the settings (music, sounds, text size, colour-blind
## colours, language) and the controls (joystick, left-handed, button editor).

## The HUD acts on these: "resume", "change_hero", "settings_changed",
## "edit_buttons".
signal request(method: String)

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const Settings := preload("res://scripts/settings.gd")
const GREEN := Color(0.22, 0.48, 0.3)
const BLUE := Color(0.22, 0.32, 0.55)
const BROWN := Color(0.5, 0.3, 0.18)
const DIM_TEXT := Color(0.78, 0.75, 0.84)
const WIDTH := 480.0
## [page, setting, name, lowest, highest, step]
const SLIDERS := [
	["settings", "music", "Music", 0.0, 1.0, 0.05],
	["settings", "sounds", "Sounds", 0.0, 1.0, 0.05],
	["settings", "text_size", "Text size", 0.85, 1.3, 0.05],
	["controls", "joystick_size", "Joystick size", 0.7, 1.4, 0.1],
]
## [page, setting, name]
const TOGGLES := [
	["settings", "colorblind", "Colour-blind colours"],
	["settings", "show_dps", "Show DPS"],
	["settings", "ambience", "Background sounds"],
	["controls", "floating_joystick", "Floating joystick"],
	["controls", "left_handed", "Left-handed"],
]

var _pages: Dictionary = {}
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _toggles: Dictionary = {}


func _ready() -> void:
	name = "GameMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	custom_minimum_size = Vector2(WIDTH, 0.0)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = -20.0
	offset_bottom = 20.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var stack := VBoxContainer.new()
	add_child(stack)
	_pages["main"] = _main_page()
	_pages["settings"] = _settings_page("settings", "SETTINGS")
	_pages["controls"] = _settings_page("controls", "CONTROLS")
	for page in _pages.values():
		stack.add_child(page)
	show_page("main")


func show_page(page_name: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page_name
	if page_name != "main":
		_refresh_settings()
	# As tall as the page shown, around the middle of the screen.
	offset_top = -20.0
	offset_bottom = 20.0
	reset_size()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request.emit("resume")


func _main_page() -> VBoxContainer:
	var page := _page("MENU")
	page.add_child(_button("RESUME", GREEN, func() -> void: request.emit("resume")))
	page.add_child(_button("SETTINGS", BLUE, func() -> void: show_page("settings")))
	page.add_child(_button("CONTROLS", BLUE, func() -> void: show_page("controls")))
	page.add_child(_button("CHANGE HERO", BROWN, func() -> void: request.emit("change_hero")))
	var hint := UiStyle.label("Your hero is saved all the time.", 15, DIM_TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)
	return page


func _settings_page(page_id: String, heading: String) -> VBoxContainer:
	var page := _page(heading)
	for full in SLIDERS:
		if full[0] != page_id:
			continue
		var entry: Array = full.slice(1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var title := UiStyle.label(entry[1], 19, Color.WHITE)
		title.custom_minimum_size = Vector2(150, 0)
		row.add_child(title)
		var slider := HSlider.new()
		slider.min_value = entry[2]
		slider.max_value = entry[3]
		slider.step = entry[4]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(0, 44)
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_on_slider.bind(entry[0]))
		row.add_child(slider)
		var value := UiStyle.label("", 19, UiStyle.GOLD_TEXT)
		value.custom_minimum_size = Vector2(64, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		page.add_child(row)
		_sliders[entry[0]] = slider
		_value_labels[entry[0]] = value
	for full in TOGGLES:
		if full[0] != page_id:
			continue
		var toggle := _button("", BLUE, _on_toggle.bind(full[1]))
		page.add_child(toggle)
		_toggles[full[1]] = [toggle, full[2]]
	if page_id != "settings":
		page.add_child(_button("EDIT BUTTONS", BLUE, func() -> void: request.emit("edit_buttons")))
	page.add_child(_button("BACK", BROWN, func() -> void: show_page("main")))
	return page


func _refresh_settings() -> void:
	for key in _sliders:
		_sliders[key].set_value_no_signal(float(Settings.get_value(key)))
		_value_labels[key].text = "%d%%" % roundi(float(Settings.get_value(key)) * 100.0)
	for key in _toggles:
		var on: bool = Settings.get_value(key) == true
		_toggles[key][0].text = "%s: %s" % [_toggles[key][1], "ON" if on else "OFF"]


func _on_slider(value: float, key: String) -> void:
	Settings.set_value(key, value)
	_refresh_settings()
	request.emit("settings_changed")


func _on_toggle(key: String) -> void:
	Settings.set_value(key, not Settings.get_value(key) == true)
	_refresh_settings()
	request.emit("settings_changed")


func _page(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var label := UiStyle.label(title, 28, UiStyle.GOLD_TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(label)
	return page


func _button(text: String, color: Color, action: Callable) -> Button:
	var button := UiStyle.button(text, color, Vector2(0, 58))
	button.pressed.connect(action)
	return button
