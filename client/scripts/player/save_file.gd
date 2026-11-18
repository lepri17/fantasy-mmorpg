extends RefCounted
## Local saves of the heroes' progress, as small files on the device: one file
## per slot of the character screen. Temporary home for this data: once there
## is a server, the server keeps it.

const PlayerStats := preload("res://scripts/player/player_stats.gd")
const DEFAULT_PATH := "user://save.cfg"
const SECTION := "character"
## The character screen keeps up to three heroes.
const SLOT_COUNT := 3
const SLOT_PATH := "user://slot_%d.cfg"

## Where the hero being played is saved. The character screen sets it to the
## chosen slot; the smoke test points it at its own file.
static var path: String = DEFAULT_PATH
## Where the slots are. The smoke test points them at its own files.
static var slot_pattern: String = SLOT_PATH


static func load_data() -> Dictionary:
	return _read(path)


static func save_data(data: Dictionary) -> void:
	_write(path, data)


static func slot_path(slot: int) -> String:
	return slot_pattern % slot


## A slot's save, read without playing it ({} for an empty slot).
static func peek(slot: int) -> Dictionary:
	return _read(slot_path(slot))


## A new hero: only the class and the name. The game gives the class's starting
## gear when it loads (player_stats.gd from_dict).
static func create_slot(slot: int, class_id: String, hero_name: String) -> void:
	_write(
		slot_path(slot), {"version": PlayerStats.SAVE_VERSION, "class": class_id, "name": hero_name}
	)


static func delete_slot(slot: int) -> void:
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


## The one save from before the character screen becomes the first slot.
static func adopt_old_save(old_path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(old_path) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(old_path), ProjectSettings.globalize_path(slot_path(1))
		)


static func _read(file_path: String) -> Dictionary:
	var config := ConfigFile.new()
	var data := {}
	if config.load(file_path) != OK or not config.has_section(SECTION):
		return data
	for key in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	return data


static func _write(file_path: String, data: Dictionary) -> void:
	var config := ConfigFile.new()
	for key in data:
		config.set_value(SECTION, key, data[key])
	config.save(file_path)
