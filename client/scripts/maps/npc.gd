extends StaticBody2D
## A townsperson from res://data/npcs.json. Standing close shows the TALK
## button (hud.gd); talking opens a dialog with the person's services (shop,
## heal, storage, teleport, quests).

const GameData := preload("res://scripts/data/game_data.gd")
const FRAMES := 4
const FPS := 4.0
const NAME_COLOR := Color(1.0, 0.9, 0.55)

@export var npc_id: String = ""

var data: Dictionary = {}
var _time: float = 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _talk_area: Area2D = $TalkArea


func _ready() -> void:
	add_to_group("npcs")
	data = GameData.table("npcs").get(npc_id, {})
	_sprite.texture = load("res://assets/characters/npcs/%s.png" % data.get("look", "merchant"))
	_sprite.hframes = FRAMES
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
	_talk_area.body_entered.connect(_on_body_entered)
	_talk_area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta
	_sprite.frame = int(_time * FPS) % FRAMES


func display_name() -> String:
	return data.get("name", npc_id)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("hud", "set_nearby_npc", self)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("hud", "clear_nearby_npc", self)
