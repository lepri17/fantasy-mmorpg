extends Node2D
## A thing on a market plaza (maps.json "prop": "look" names a drawing in
## assets/environment/props, "pos" is the middle of its front, on the ground):
## stalls, a fountain, barrels, crates and benches. "block": [width, height]
## makes its foot something to walk around (monsters and the map guide too).
## "npc" names an npcs.json entry: walking up shows TALK, like a townsperson
## (a market's wishing fountain).

## The drawing's ground line: design y 120 of 128, in a 256 px image.
const GROUND_Y := 240.0
const SIZE := 256.0

const GameData := preload("res://scripts/data/game_data.gd")
const NAME_COLOR := Color(0.7, 0.92, 1.0)
const TALK_RADIUS := 150.0

var look: String = "bench"
var block: Vector2 = Vector2.ZERO
## The npcs.json entry it talks as (hud.gd reads npc_id), or "".
var npc_id: String = ""


func _ready() -> void:
	add_to_group("props")
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/environment/props/%s.png" % look)
	sprite.centered = false
	sprite.position = Vector2(-SIZE * 0.5, -GROUND_Y)
	add_child(sprite)
	if npc_id != "":
		_make_talkable()
	if block == Vector2.ZERO:
		return
	var body := StaticBody2D.new()
	body.add_to_group("obstacles")
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = block
	shape.shape = box
	shape.position = Vector2(0, -block.y * 0.5)
	body.add_child(shape)
	add_child(body)


func display_name() -> String:
	return GameData.table("npcs").get(npc_id, {}).get("name", npc_id)


func _make_talkable() -> void:
	add_to_group("talkers")
	var data: Dictionary = GameData.table("npcs").get(npc_id, {})
	var label := Label.new()
	label.text = "%s\n%s" % [data.get("name", npc_id), data.get("title", "")]
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", NAME_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.1, 0.18))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(200, 40)
	label.position = Vector2(-100, -196)
	add_child(label)
	var area := Area2D.new()
	area.name = "TalkArea"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TALK_RADIUS
	shape.shape = circle
	shape.position = Vector2(0, -20)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("hud", "set_nearby_npc", self)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("hud", "clear_nearby_npc", self)
