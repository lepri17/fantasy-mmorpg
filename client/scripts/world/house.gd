extends Node2D
## A house in a town (maps.json "house": "look" names a drawing in
## assets/environment/houses, "pos" is the middle of its front, on the ground).
## Houses stand above the town's street (the map's "street_top"), so they need
## no walls of their own: the hero walks along in front of them.

## The drawing's ground line: design y 120 of 128, in a 256 px image.
const GROUND_Y := 240.0
const SIZE := 256.0

var look: String = "willow_home"


func _ready() -> void:
	add_to_group("houses")
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/environment/houses/%s.png" % look)
	sprite.centered = false
	sprite.position = Vector2(-SIZE * 0.5, -GROUND_Y)
	add_child(sprite)
