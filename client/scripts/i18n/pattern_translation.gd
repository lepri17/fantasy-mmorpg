extends Translation
## The Hebrew translation (data/he.json: English text -> Hebrew text). Besides
## whole texts it knows sentences with blanks: the key "Got %s x%d." matches
## "Got Slime Jelly x2.", the parts in the blanks are translated too, and they
## go into the Hebrew text by number: "קיבלת {0} x{1}.". So the many texts the
## game builds from pieces translate without changing the code that builds
## them. A text of several lines that matches nothing is done line by line.

## How deep blanks inside blanks are translated.
const MAX_DEPTH := 3

var _exact: Dictionary = {}
## [RegEx, Hebrew text with {0}, {1}...], the most specific first.
var _patterns: Array = []
var _letters := RegEx.create_from_string("[A-Za-z]")


func load_table(table: Dictionary) -> void:
	_exact.clear()
	_patterns.clear()
	var keys: Array = table.keys()
	keys.sort_custom(func(a, b) -> bool: return _literal(a).length() > _literal(b).length())
	for key in keys:
		var blanks: int = key.count("%") - 2 * key.count("%%")
		# A key that is nothing but blanks and spaces would match any text.
		if blanks > 0 and _literal(key).strip_edges() != "":
			var regex := RegEx.new()
			if regex.compile(_to_regex(key)) == OK:
				_patterns.append([regex, table[key]])
		else:
			_exact[key] = table[key]


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(translate_text(String(src_message)))


func translate_text(text: String, depth: int = 0) -> String:
	if _exact.has(text):
		return _exact[text]
	if depth > MAX_DEPTH or _letters.search(text) == null:
		return text
	for pattern in _patterns:
		var found: RegExMatch = pattern[0].search(text)
		if found == null:
			continue
		var result: String = pattern[1]
		for group in range(1, found.get_group_count() + 1):
			var part: String = translate_text(found.get_string(group), depth + 1)
			result = result.replace("{%d}" % (group - 1), part)
		return result
	if "\n" in text:
		var lines := PackedStringArray()
		for line in text.split("\n"):
			lines.append(translate_text(line, depth + 1))
		return "\n".join(lines)
	return text


## The key without its blanks (to sort the most specific first).
static func _literal(key: String) -> String:
	var regex := RegEx.create_from_string("%(\\.\\d+)?[sdf]|%%")
	return regex.sub(key, "", true)


## "Got %s x%d." -> ^Got (.+?) x([+-]?\d+)\.$ (one line per line of the key).
static func _to_regex(key: String) -> String:
	var out: String = "^"
	var i: int = 0
	while i < key.length():
		var c: String = key[i]
		if c == "%" and i + 1 < key.length():
			var rest: String = key.substr(i + 1)
			if rest.begins_with("%"):
				out += "%"
				i += 2
				continue
			if rest.begins_with("s"):
				out += "(.+?)"
				i += 2
				continue
			if rest.begins_with("d"):
				out += "([+-]?\\d+)"
				i += 2
				continue
			var decimals := RegEx.create_from_string("^\\.\\d+f")
			var number: RegExMatch = decimals.search(rest)
			if number != null:
				out += "([+-]?\\d+(?:\\.\\d+)?)"
				i += 1 + number.get_string().length()
				continue
		out += "\\" + c if c in ".^$|?*+()[]{}\\" else ("\\n" if c == "\n" else c)
		i += 1
	return out + "$"
