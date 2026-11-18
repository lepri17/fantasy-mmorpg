extends RefCounted
## The game's language: English (the texts as written in the code and data) or
## Hebrew (data/he.json, through pattern_translation.gd). It is a setting; until
## it is chosen it follows the phone's language. Also the game's font (Rubik,
## which has Hebrew letters), set here at run time.

const Settings := preload("res://scripts/settings.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const PatternTranslation := preload("res://scripts/i18n/pattern_translation.gd")
const FONT := preload("res://assets/fonts/rubik_medium.ttf")
const LANGUAGES := ["en", "he"]
## Each language's own name, for the button that picks it.
const NAMES := {"en": "English", "he": "עברית"}

static var _hebrew: Translation = null


## Called by the first scene (and again harmlessly by the next).
static func setup(tree: SceneTree) -> void:
	ThemeDB.fallback_font = FONT
	ThemeDB.get_default_theme().default_font = FONT
	# The screens keep their layout in Hebrew too (the joystick stays on the
	# left for right-handed players; left-handed is a setting); only the text
	# runs right to left.
	tree.root.set_layout_direction(Window.LAYOUT_DIRECTION_LTR)
	if _hebrew == null:
		_hebrew = PatternTranslation.new()
		_hebrew.locale = "he"
		_hebrew.load_table(GameData.table("he"))
		TranslationServer.add_translation(_hebrew)
		# The translation is a script; it must go before the engine shuts down
		# its scripts, or closing the game crashes. A node under the root, left
		# when the game closes, takes it out.
		var keeper := Node.new()
		keeper.name = "LanguageKeeper"
		keeper.tree_exiting.connect(release)
		tree.root.add_child.call_deferred(keeper)
	TranslationServer.set_locale(current())


static func release() -> void:
	if _hebrew != null:
		TranslationServer.remove_translation(_hebrew)
		_hebrew = null


## "en" or "he": the setting, or the phone's language until one is chosen.
static func current() -> String:
	var chosen: String = str(Settings.get_value("language"))
	if chosen in LANGUAGES:
		return chosen
	return "he" if OS.get_locale_language() in ["he", "iw"] else "en"


static func set_language(code: String) -> void:
	Settings.set_value("language", code)
	TranslationServer.set_locale(current())


## The other language (for a button that switches).
static func other() -> String:
	return "en" if current() == "he" else "he"
