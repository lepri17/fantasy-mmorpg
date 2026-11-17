extends Control
## The warrior's status panel on the HUD: level, HP, stamina, XP, potions, gold.
## It only draws what it is told; the HUD script feeds it.

const CHARACTER_NAME := "Warrior"
const TEXT_SIZE := 18
const HP_TOP := 28.0
const HP_HEIGHT := 24.0
const STAMINA_HEIGHT := 12.0
const XP_HEIGHT := 15.0
const GAP := 6.0

var _hp: int = 1
var _max_hp: int = 1
var _stamina: float = 1.0
var _max_stamina: float = 1.0
var _level: int = 1
var _xp: int = 0
var _xp_to_next: int = 1
var _gold: int = 0
var _potions: int = 0


func set_hp(current: int, maximum: int) -> void:
	_hp = current
	_max_hp = maximum
	queue_redraw()


func set_stamina(current: float, maximum: float) -> void:
	_stamina = current
	_max_stamina = maximum
	queue_redraw()


func set_progress(level: int, xp: int, xp_to_next: int, gold: int, potions: int) -> void:
	_level = level
	_xp = xp
	_xp_to_next = xp_to_next
	_gold = gold
	_potions = potions
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var left: int = HORIZONTAL_ALIGNMENT_LEFT
	var right: int = HORIZONTAL_ALIGNMENT_RIGHT
	var title: String = "Lv.%d %s" % [_level, CHARACTER_NAME]
	var purse: String = "Potions %d   Gold %d" % [_potions, _gold]
	draw_string(font, Vector2(2, 20), title, left, -1, TEXT_SIZE + 2, Color.WHITE)
	draw_string(font, Vector2(0, 20), purse, right, size.x, TEXT_SIZE - 2, Color(1, 0.9, 0.5))

	var hp_rect := Rect2(0.0, HP_TOP, size.x, HP_HEIGHT)
	_draw_bar(hp_rect, float(_hp) / float(maxi(_max_hp, 1)), Color(0.85, 0.2, 0.28))
	var hp_text: String = "HP %d / %d" % [_hp, _max_hp]
	draw_string(font, Vector2(10, HP_TOP + 18.0), hp_text, left, -1, TEXT_SIZE - 2, Color.WHITE)

	var stamina_rect := Rect2(0.0, hp_rect.end.y + GAP, size.x, STAMINA_HEIGHT)
	_draw_bar(stamina_rect, _stamina / maxf(_max_stamina, 1.0), Color(0.95, 0.75, 0.2))

	var xp_rect := Rect2(0.0, stamina_rect.end.y + GAP, size.x, XP_HEIGHT)
	var xp_ratio: float = float(_xp) / float(maxi(_xp_to_next, 1))
	_draw_bar(xp_rect, xp_ratio, Color(0.45, 0.7, 1.0))
	var xp_text: String = "EXP %d / %d  (%.2f%%)" % [_xp, _xp_to_next, xp_ratio * 100.0]
	var xp_baseline := Vector2(8.0, xp_rect.end.y - 2.0)
	draw_string_outline(font, xp_baseline, xp_text, left, -1, 12, 3, Color(0.05, 0.1, 0.2))
	draw_string(font, xp_baseline, xp_text, left, -1, 12, Color.WHITE)


func _draw_bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect.grow(3.0), Color(0.1, 0.06, 0.1, 0.8))
	var fill := Vector2(rect.size.x * clampf(ratio, 0.0, 1.0), rect.size.y)
	draw_rect(Rect2(rect.position, fill), color)
