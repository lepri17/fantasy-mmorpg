extends RefCounted
## The player's settings, kept on the device (user://settings.cfg): music and
## sound volume, joystick size, a floating joystick, left-handed controls, text
## size, colour-blind colours, and where the touch buttons are and how big (the
## button editor).

const PATH := "user://settings.cfg"
const SECTION := "settings"
## The round buttons' layout. Places moved in the button editor for an older
## layout are dropped (they would put the buttons in odd places now).
const BUTTON_LAYOUT := 2
const DEFAULTS := {
	"music": 0.8,
	"sounds": 1.0,
	"joystick_size": 1.0,
	"floating_joystick": false,
	"left_handed": false,
	"text_size": 1.0,
	"colorblind": false,
	"button_offsets": {},
	"button_scale": 1.0,
	"button_layout": BUTTON_LAYOUT,
	"show_dps": false,
}
## The two sound buses and the setting each one follows.
const BUSES := {"Music": "music", "Sounds": "sounds"}

## Where the settings are kept. The smoke test points this at its own file.
static var path: String = PATH
static var _values: Dictionary = {}


static func get_value(key: String) -> Variant:
	if _values.is_empty():
		load_file()
	return _values.get(key, DEFAULTS[key])


static func set_value(key: String, value: Variant) -> void:
	if _values.is_empty():
		load_file()
	_values[key] = value
	var config := ConfigFile.new()
	for each in _values:
		config.set_value(SECTION, each, _values[each])
	config.save(path)
	apply_audio()


static func load_file() -> void:
	_values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for key in DEFAULTS:
			_values[key] = config.get_value(SECTION, key, DEFAULTS[key])
		if int(config.get_value(SECTION, "button_layout", 1)) < BUTTON_LAYOUT:
			_values["button_offsets"] = {}
			_values["button_layout"] = BUTTON_LAYOUT


## The Music and Sounds buses at the chosen volumes (made the first time).
static func apply_audio() -> void:
	for bus_name in BUSES:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index == -1:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		var volume: float = clampf(float(get_value(BUSES[bus_name])), 0.0, 1.0)
		AudioServer.set_bus_mute(index, volume < 0.01)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.01)))
