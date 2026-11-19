extends StaticBody2D
## A townsperson from res://data/npcs.json. Standing close shows the TALK
## button (hud.gd); talking opens a dialog with the person's services (shop,
## heal, storage, teleport, quests).
## Each person has their own drawing (generate_assets.py TOWNSFOLK): 8 frames,
## 4 of breathing with a blink, then 4 of their own action (the smith
## hammers, the healer raises her staff, the guide's orb glows, some wave).
## They do it every few seconds and when the hero comes near, and now and then
## say one of their lines ("chatter") in a bubble, so the towns feel alive.

const GameData := preload("res://scripts/data/game_data.gd")
const FRAMES := 8
const IDLE_FRAMES := 4
const FPS := 4.0
const ACTION_FPS := 6.0
## Seconds between a person's actions, and between their lines.
const ACTION_EVERY := Vector2(4.0, 9.0)
const CHATTER_EVERY := Vector2(10.0, 22.0)
## They only talk to themselves when the hero is this close (no bubbles far off).
const CHATTER_RANGE := 650.0
const BUBBLE_SECONDS := 3.2
const NAME_COLOR := Color(1.0, 0.9, 0.55)
const BUBBLE_FILL := Color(1.0, 1.0, 1.0, 0.92)
const BUBBLE_TEXT := Color(0.18, 0.13, 0.22)

@export var npc_id: String = ""

var data: Dictionary = {}
## True while the action frames play.
var acting: bool = false
var _time: float = 0.0
var _action_time: float = 0.0
var _next_action: float = 0.0
var _next_chatter: float = 0.0
var _bubble_left: float = 0.0
var _bubble: PanelContainer
var _bubble_label: Label
## Their own dice, so a town's chatter does not change the game's luck.
var _rng := RandomNumberGenerator.new()

@onready var _sprite: Sprite2D = $Sprite
@onready var _talk_area: Area2D = $TalkArea


func _ready() -> void:
	add_to_group("npcs")
	data = GameData.table("npcs").get(npc_id, {})
	_sprite.texture = load("res://assets/characters/npcs/%s.png" % data.get("look", "mira"))
	_sprite.hframes = FRAMES
	_rng.seed = hash(npc_id)
	_time = _rng.randf() * 4.0  # not all breathing in step
	_next_action = _rng.randf_range(ACTION_EVERY.x, ACTION_EVERY.y)
	_next_chatter = _rng.randf_range(2.0, CHATTER_EVERY.y)
	var label := Label.new()
	label.text = "%s\n%s" % [display_name(), data.get("title", "")]
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", NAME_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.12))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(160, 40)
	label.position = Vector2(-80, -118)
	add_child(label)
	_make_bubble()
	_talk_area.body_entered.connect(_on_body_entered)
	_talk_area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta
	if acting:
		_action_time += delta
		var step: int = int(_action_time * ACTION_FPS)
		if step >= FRAMES - IDLE_FRAMES:
			acting = false
			_next_action = _rng.randf_range(ACTION_EVERY.x, ACTION_EVERY.y)
		else:
			_sprite.frame = IDLE_FRAMES + step
	if not acting:
		_sprite.frame = int(_time * FPS) % IDLE_FRAMES
		_next_action -= delta
		if _next_action <= 0.0:
			act()
	_next_chatter -= delta
	if _next_chatter <= 0.0:
		_next_chatter = _rng.randf_range(CHATTER_EVERY.x, CHATTER_EVERY.y)
		if _hero_near(CHATTER_RANGE):
			chat()
	if _bubble_left > 0.0:
		_bubble_left -= delta
		_bubble.modulate.a = clampf(_bubble_left / 0.4, 0.0, 1.0)
		_bubble.position = Vector2(-_bubble.size.x * 0.5, -132.0 - _bubble.size.y)
		_bubble.visible = _bubble_left > 0.0


func display_name() -> String:
	return data.get("name", npc_id)


## Plays the person's own action once (hammering, raising a staff, waving...).
func act() -> void:
	acting = true
	_action_time = 0.0


## Says one of the person's lines in a bubble over their head.
func chat() -> void:
	var lines: Array = data.get("chatter", [])
	if not lines.is_empty():
		say(lines[_rng.randi_range(0, lines.size() - 1)])


func say(text: String) -> void:
	_bubble_label.text = text
	_bubble.reset_size()
	_bubble.visible = true
	_bubble.modulate.a = 1.0
	_bubble_left = BUBBLE_SECONDS


## The text in the bubble now, or "" when there is none (tests read it).
func bubble_text() -> String:
	return _bubble_label.text if _bubble.visible else ""


func _make_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	var style := StyleBoxFlat.new()
	style.bg_color = BUBBLE_FILL
	style.set_corner_radius_all(10)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 5.0
	style.border_color = Color(0.2, 0.15, 0.25, 0.5)
	style.set_border_width_all(1)
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble_label = Label.new()
	_bubble_label.add_theme_font_size_override("font_size", 14)
	_bubble_label.add_theme_color_override("font_color", BUBBLE_TEXT)
	_bubble.add_child(_bubble_label)
	_bubble.z_index = 20  # over trees and houses
	_bubble.visible = false
	add_child(_bubble)


func _hero_near(distance: float) -> bool:
	var hero: Node2D = get_tree().get_first_node_in_group("player")
	return hero != null and hero.global_position.distance_to(global_position) < distance


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("hud", "set_nearby_npc", self)
		act()  # a wave, a swing, a glow: they notice you
		chat()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("hud", "clear_nearby_npc", self)
