extends RefCounted
## Game data from the JSON files in res://data: items, character, monsters,
## combat. The same files are checked by tools/check_data.py and are meant to
## be read by the server too. Each file is read once, on first use.
##
## JSON has no integers: every number arrives as a float, so callers convert
## with int() where they need whole numbers.

const DATA_DIR := "res://data/"

static var _tables: Dictionary = {}


static func table(table_name: String) -> Dictionary:
	if not _tables.has(table_name):
		var path: String = DATA_DIR + table_name + ".json"
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_error("GameData: cannot read %s" % path)
			parsed = {}
		_tables[table_name] = parsed
	return _tables[table_name]
