extends RefCounted
## The shared look of the HUD windows (inventory, character): a framed panel,
## labels and buttons. Static helpers only.

const GOLD_TEXT := Color(1.0, 0.86, 0.45)
const FRAME_BORDER := Color(0.85, 0.68, 0.32)
const BONUS_NAMES := {
	"attack": "Attack",
	"max_hp": "Max HP",
	"defense": "Defense",
	"max_stamina": "Max Stamina",
	"crit_chance": "Crit",
	"evasion": "Evasion",
	"skill_damage": "Skill damage",
}
const SHORT_NAMES := {
	"attack": "ATK",
	"max_hp": "HP",
	"defense": "DEF",
	"max_stamina": "STA",
	"crit_chance": "CRIT",
	"evasion": "EVA",
	"skill_damage": "SKILL",
}
const PERCENT_BONUSES := ["crit_chance", "evasion", "skill_damage"]

## The second bar's name for the class played ("Stamina", or "Mana" for the mage).
static var resource_name: String = "Stamina"
static var resource_short: String = "STA"


## "Max Mana" / "MP" for the mage's max_stamina; other bonuses by their names.
static func stat_name(stat: String, short: bool = false) -> String:
	var text: String = (SHORT_NAMES if short else BONUS_NAMES).get(stat, stat)
	if stat == "max_stamina":
		text = resource_short if short else "Max " + resource_name
	return TranslationServer.translate(text)


## "+1 Attack, +2% Crit" ("+1 ATK, +2% CRIT" when short), or "No bonus".
static func bonus_text(bonus: Dictionary, short: bool = false) -> String:
	var parts := PackedStringArray()
	for stat in bonus:
		var value: float = float(bonus[stat])
		var name_text: String = stat_name(stat, short)
		if stat in PERCENT_BONUSES:
			parts.append("+%s%% %s" % [number(value * 100.0), name_text])
		else:
			parts.append("+%s %s" % [number(value), name_text])
	return TranslationServer.translate("No bonus") if parts.is_empty() else ", ".join(parts)


## 3 -> "3", 2.5 -> "2.5".
static func number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


static func label(text: String, font_size: int, color: Color) -> Label:
	var new_label := Label.new()
	new_label.text = text
	new_label.add_theme_font_size_override("font_size", font_size)
	new_label.add_theme_color_override("font_color", color)
	return new_label


static func button(text: String, color: Color, min_size: Vector2) -> Button:
	var new_button := Button.new()
	new_button.text = text
	new_button.custom_minimum_size = min_size
	new_button.focus_mode = Control.FOCUS_NONE
	new_button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		if state == "hover":
			box.bg_color = color.lightened(0.15)
		elif state == "pressed":
			box.bg_color = color.darkened(0.25)
		box.border_color = FRAME_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(10)
		new_button.add_theme_stylebox_override(state, box)
	return new_button


## Greys a button out when it would do nothing.
static func set_enabled(target: Button, enabled: bool) -> void:
	target.disabled = not enabled
	target.modulate.a = 1.0 if enabled else 0.45


static func frame_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.06, 0.1, 0.9)
	box.border_color = FRAME_BORDER
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(14)
	return box
