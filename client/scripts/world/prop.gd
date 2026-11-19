extends Node2D
## A thing on a market plaza (maps.json "prop": "look" names a drawing in
## assets/environment/props, "pos" is the middle of its front, on the ground):
## stalls, a fountain, barrels, crates and benches. "block": [width, height]
## makes its foot something to walk around (monsters and the map guide too).

## The drawing's ground line: design y 120 of 128, in a 256 px image.
const GROUND_Y := 240.0
const SIZE := 256.0

var look: String = "bench"
var block: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("props")
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/environment/props/%s.png" % look)
	sprite.centered = false
	sprite.position = Vector2(-SIZE * 0.5, -GROUND_Y)
	add_child(sprite)
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
