extends PanelContainer
## U2: the first minutes of a new hero. One short hint at a time at the top of
## the screen; each goes away when the hero has done it (moved, attacked,
## picked up loot, used a skill, opened the bag, gone to town, taken a quest).
## SKIP ends it. The step is kept in the save (player_stats.gd "tutorial").

const UiStyle := preload("res://scripts/ui/ui_style.gd")
## [id, hint]. The hints are English here and translated like every text.
const STEPS := [
	["move", "Move with the joystick on the left (or WASD)."],
	["attack", "Tap ATK near a monster to attack it."],
	["loot", "Walk over what a monster drops to pick it up."],
	["skill", "Tap a coloured skill button to use a skill."],
	["bag", "Open your bag (top right) to see your gear."],
	["town", "The portal on the left of the meadow leads to town."],
	["quest", "Talk to people in town (TALK) and take a quest."],
	["auto", "Tap a quest at the top right to walk to it. AUTO hunts for you. Have fun!"],
]
## The last hint stays this long.
const LAST_SECONDS := 6.0

## The hero (player.gd) and the HUD, set by the HUD.
var hero: Node = null
var hud: Node = null

var _label: Label
var _start: Dictionary = {}
var _last_left: float = LAST_SECONDS


func _ready() -> void:
	name = "Tutorial"
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -300.0
	offset_right = 300.0
	offset_top = 104.0
	offset_bottom = 150.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_label = UiStyle.label("", 18, Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	var skip := UiStyle.button("SKIP", Color(0.5, 0.3, 0.18), Vector2(90, 40))
	skip.pressed.connect(finish)
	row.add_child(skip)
	hide()


## Which step the hero is on, 0..STEPS.size() (that is: done).
func step() -> int:
	return int(hero.stats.tutorial)


## Called by the HUD a few times a second.
func update(delta: float) -> void:
	if hero == null or step() >= STEPS.size():
		hide()
		return
	if _start.is_empty():
		_start = _snapshot()
	var id: String = STEPS[step()][0]
	_label.text = STEPS[step()][1]
	# Out of the way while a window (bag, shop, menu...) is open.
	visible = not hud.call("_windows").any(func(window) -> bool: return window.visible)
	if id == "auto":
		if visible:
			_last_left -= delta
		if _last_left <= 0.0:
			finish()
	elif _done(id):
		hero.stats.tutorial = step() + 1
		hero.call("_progress_changed")
		_start = _snapshot()


## SKIP, or the end: no more hints for this hero.
func finish() -> void:
	if hero != null:
		hero.stats.tutorial = STEPS.size()
		hero.call("_progress_changed")
	hide()


func _done(id: String) -> bool:
	var stats = hero.stats
	var counters: Dictionary = stats.record.counters
	var checks := {
		"move": hero.global_position.distance_to(_start["position"]) > 150.0,
		"attack": int(counters.get("kills", 0)) > _start["kills"],
		"loot": stats.gold > _start["gold"] or stats.bag.size() != _start["bag"],
		"skill": int(counters.get("skills_used", 0)) > _start["skills"],
		"bag": hud.get("_inventory").visible,
		"town": stats.map_id == "town",
		"quest": not stats.quests.active.is_empty() or not stats.quests.done.is_empty(),
	}
	return checks.get(id, true)


func _snapshot() -> Dictionary:
	var stats = hero.stats
	return {
		"position": hero.global_position,
		"kills": int(stats.record.counters.get("kills", 0)),
		"gold": stats.gold,
		"bag": stats.bag.size(),
		"skills": int(stats.record.counters.get("skills_used", 0)),
	}
