extends PanelContainer
## The character window (STATS button or C). STATS page: level, free points,
## a + button for each of STR, AGI, VIT and ENE, the numbers that follow from
## them, and a stat reset for gold. TITLES page: the title shown (with < and >
## to change it) and every achievement with its progress. Only shows state:
## each change is a request that the HUD passes on to the player.

signal close_requested
signal request(method: String, argument: Variant)

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const CombatRules := preload("res://scripts/combat/combat_rules.gd")
const PlayerStats := preload("res://scripts/player/player_stats.gd")
const AchievementRecord := preload("res://scripts/player/achievement_record.gd")

const BONUS_NAMES := {
	"attack": "Attack",
	"max_hp": "Max HP",
	"defense": "Defense",
	"max_stamina": "Max Stamina",
	"crit_chance": "Crit",
	"evasion": "Evasion",
	"skill_damage": "Skill damage",
}
const PERCENT_BONUSES := ["crit_chance", "evasion", "skill_damage"]
const POINTS_COLOR := Color(0.55, 1.0, 0.6)
const DIM_TEXT := Color(0.78, 0.75, 0.84)
const DONE_TEXT := Color(1.0, 0.8, 0.45)
const GREEN := Color(0.22, 0.48, 0.3)
const BROWN := Color(0.5, 0.3, 0.18)

var _level_label: Label
var _points_label: Label
## Stat id -> the Label with its points, and -> its + Button.
var _stat_values: Dictionary = {}
var _plus_buttons: Dictionary = {}
var _numbers_label: Label
var _reset_button: Button
var _title_label: Label
var _title_bonus_label: Label
var _achievement_rows: VBoxContainer
## "stats" / "titles" -> the page, and -> its tab button.
var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
## "" (no title) and the earned achievements, for the < and > buttons.
var _titles: Array = [""]
var _title: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	column.add_child(_title_row())
	column.add_child(_tabs_row())
	_pages["stats"] = _stats_page()
	_pages["titles"] = _titles_page()
	for page in _pages.values():
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(page)
	show_page("stats")


## Shows "stats" or "titles".
func show_page(page_name: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page_name
		_tab_buttons[key].modulate.a = 1.0 if key == page_name else 0.5


## stats is a player_stats.gd object.
func refresh(stats) -> void:
	_level_label.text = "Lv %d Warrior" % stats.level
	var free: int = stats.free_points()
	_points_label.text = "POINTS %d" % free
	_points_label.add_theme_color_override("font_color", POINTS_COLOR if free > 0 else DIM_TEXT)
	for stat_id in _stat_values:
		_stat_values[stat_id].text = str(stats.points_in(stat_id))
		UiStyle.set_enabled(_plus_buttons[stat_id], free > 0)
	var damage: Vector2i = CombatRules.damage_range(stats.attack_damage())
	_numbers_label.text = (
		"ATK %d~%d   HP %d   STA %d\nDEF %d   CRIT %d%%   EVA %d%%   SKILL +%d%%"
		% [
			damage.x,
			damage.y,
			stats.max_hp(),
			roundi(stats.max_stamina()),
			stats.defense(),
			roundi(stats.crit_chance() * 100.0),
			roundi(stats.evasion() * 100.0),
			roundi(stats.skill_damage_bonus() * 100.0),
		]
	)
	_reset_button.text = "RESET STATS  (%d G)" % stats.reset_cost()
	UiStyle.set_enabled(
		_reset_button, stats.spent_points() > 0 and stats.gold >= stats.reset_cost()
	)
	_refresh_titles(stats.record, stats.level)


## "+1 Attack, +2% Crit", or "No bonus".
static func bonus_text(bonus: Dictionary) -> String:
	var parts := PackedStringArray()
	for stat in bonus:
		var value: float = float(bonus[stat])
		var stat_name: String = BONUS_NAMES.get(stat, stat)
		if stat in PERCENT_BONUSES:
			parts.append("+%s%% %s" % [_number(value * 100.0), stat_name])
		else:
			parts.append("+%s %s" % [_number(value), stat_name])
	return "No bonus" if parts.is_empty() else ", ".join(parts)


static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _refresh_titles(record, level: int) -> void:
	_titles = [""] + record.earned
	_title = record.title
	if _title == "":
		_title_label.text = "No title"
		_title_bonus_label.text = "Earn achievements to get titles."
	else:
		var shown: Dictionary = AchievementRecord.list[_title]
		_title_label.text = shown["title"]
		_title_bonus_label.text = bonus_text(shown.get("bonus", {}))
	for child in _achievement_rows.get_children():
		_achievement_rows.remove_child(child)
		child.queue_free()
	for achievement_id in AchievementRecord.list:
		_achievement_rows.add_child(_achievement_row(record, achievement_id, level))


func _achievement_row(record, achievement_id: String, level: int) -> Label:
	var achievement: Dictionary = AchievementRecord.list[achievement_id]
	var goal: int = int(achievement["goal"])
	var done: bool = record.earned.has(achievement_id)
	var reached: int = mini(record.progress(achievement_id, level), goal)
	var status: String = "DONE" if done else "%d/%d" % [reached, goal]
	var row := UiStyle.label(
		(
			"%s  %s\n%s Title: %s (%s)"
			% [
				achievement["name"],
				status,
				achievement["text"],
				achievement["title"],
				bonus_text(achievement.get("bonus", {})),
			]
		),
		14,
		DONE_TEXT if done else DIM_TEXT
	)
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _step_title(step: int) -> void:
	var index: int = maxi(0, _titles.find(_title))
	request.emit("choose_title", _titles[posmod(index + step, _titles.size())])


func _title_row() -> Control:
	var row := HBoxContainer.new()
	var heading := UiStyle.label("CHARACTER", 22, UiStyle.GOLD_TEXT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var close := UiStyle.button("X", Color(0.55, 0.2, 0.25), Vector2(46, 40))
	close.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(close)
	return row


func _tabs_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for page_name in ["stats", "titles"]:
		var tab := UiStyle.button(page_name.to_upper(), BROWN, Vector2(0, 40))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_page.bind(page_name))
		_tab_buttons[page_name] = tab
		row.add_child(tab)
	return row


func _stats_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	_level_label = UiStyle.label("", 20, Color.WHITE)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_level_label)
	_points_label = UiStyle.label("", 20, POINTS_COLOR)
	header.add_child(_points_label)
	page.add_child(header)
	for stat_id in PlayerStats.stat_rules:
		page.add_child(_stat_row(stat_id, PlayerStats.stat_rules[stat_id]))
	_numbers_label = UiStyle.label("", 15, Color.WHITE)
	page.add_child(_numbers_label)
	_reset_button = UiStyle.button("RESET STATS", BROWN, Vector2(0, 44))
	_reset_button.pressed.connect(func() -> void: request.emit("reset_stats", null))
	page.add_child(_reset_button)
	return page


func _stat_row(stat_id: String, rule: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var short_name := UiStyle.label(rule["short"], 20, UiStyle.GOLD_TEXT)
	short_name.custom_minimum_size = Vector2(48, 0)
	row.add_child(short_name)
	var text := UiStyle.label(rule["text"], 12, DIM_TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(120, 0)
	row.add_child(text)
	var value := UiStyle.label("0", 20, Color.WHITE)
	value.custom_minimum_size = Vector2(36, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var plus := UiStyle.button("+", GREEN, Vector2(48, 44))
	plus.pressed.connect(func() -> void: request.emit("add_stat_point", stat_id))
	row.add_child(plus)
	_stat_values[stat_id] = value
	_plus_buttons[stat_id] = plus
	return row


func _titles_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var chooser := HBoxContainer.new()
	var back := UiStyle.button("<", BROWN, Vector2(48, 44))
	back.pressed.connect(_step_title.bind(-1))
	chooser.add_child(back)
	_title_label = UiStyle.label("", 20, UiStyle.GOLD_TEXT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chooser.add_child(_title_label)
	var forward := UiStyle.button(">", BROWN, Vector2(48, 44))
	forward.pressed.connect(_step_title.bind(1))
	chooser.add_child(forward)
	page.add_child(chooser)
	_title_bonus_label = UiStyle.label("", 15, POINTS_COLOR)
	_title_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_title_bonus_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_achievement_rows = VBoxContainer.new()
	_achievement_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_achievement_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_achievement_rows)
	page.add_child(scroll)
	return page
