extends RefCounted
## Local save of the character's progress, as a small file on the device.
## Temporary home for this data: once there is a server, the server keeps it.

const DEFAULT_PATH := "user://save.cfg"
const SECTION := "character"

## Where the save lives. The smoke test points this at its own file.
static var path: String = DEFAULT_PATH


static func load_data() -> Dictionary:
	var config := ConfigFile.new()
	var data := {}
	if config.load(path) != OK or not config.has_section(SECTION):
		return data
	for key in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	return data


static func save_data(data: Dictionary) -> void:
	var config := ConfigFile.new()
	for key in data:
		config.set_value(SECTION, key, data[key])
	config.save(path)
