extends RefCounted
## The game's text: English only (Mor, 2026-11-18; the Hebrew translation was
## taken out). It sets the game's font (Rubik) at run time.

const FONT := preload("res://assets/fonts/rubik_medium.ttf")


## Called by the first scene (and again harmlessly by the next).
static func setup(tree: SceneTree) -> void:
	ThemeDB.fallback_font = FONT
	ThemeDB.get_default_theme().default_font = FONT
	tree.root.set_layout_direction(Window.LAYOUT_DIRECTION_LTR)
	TranslationServer.set_locale("en")
