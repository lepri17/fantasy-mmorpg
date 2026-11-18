extends Area2D
## Loot lying on the ground. The warrior collects it by walking over it.
## Whoever drops it sets kind ("gold" or "item"), amount, item_id for items,
## and lifetime / pickup_delay if they should differ, before adding it.

const ItemDb := preload("res://scripts/items/item_db.gd")
const COIN_TEXTURE := preload("res://assets/items/coin.png")
## Q7: loot this close to the warrior drifts to him, at this speed.
const MAGNET_RADIUS := 90.0
const MAGNET_SPEED := 280.0
## Loot blinks for this long before it disappears.
const BLINK_SECONDS := 5.0
## Inventory icons are 64 px; on the ground they are shown at about half size.
const ICON_SCALE_ON_GROUND := 0.55

var kind: String = "gold"
var item_id: String = ""
var amount: int = 1
## For gear: the whole entry (rarity, upgrades, options) that goes into the bag.
var stack: Dictionary = {}
## Drifts to a warrior close by (Q7). Off for what the warrior drops himself,
## so a thrown-away item does not come straight back.
var magnetic: bool = true
## Seconds before it disappears.
var lifetime: float = 30.0
## Seconds before it can be picked up, so a dropped item is not picked straight
## back up by the warrior who dropped it.
var pickup_delay: float = 0.0

var _age: float = 0.0
var _waiting_for_delay: bool = true

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("pickups")
	var target_scale: float = 1.0
	if kind == "item":
		if not ItemDb.items.has(item_id):
			queue_free()
			return
		var item: Dictionary = ItemDb.items[item_id]
		if item.has("world_icon"):
			_sprite.texture = load(item["world_icon"])
		else:
			_sprite.texture = load(item["icon"])
			target_scale = ICON_SCALE_ON_GROUND
	else:
		_sprite.texture = COIN_TEXTURE
	if not stack.is_empty() and ItemDb.is_special(stack):
		queue_redraw()  # a glow in the rarity color under the item
	_sprite.scale = Vector2.ONE * target_scale * 0.3
	create_tween().tween_property(_sprite, "scale", Vector2.ONE * target_scale, 0.25)
	body_entered.connect(_on_body_entered)


func _draw() -> void:
	if not stack.is_empty() and ItemDb.is_special(stack):
		var glow: Color = ItemDb.rarity_color(stack)
		draw_circle(Vector2(0, 8), 18.0, Color(glow.r, glow.g, glow.b, 0.22))
		draw_arc(Vector2(0, 8), 18.0, 0.0, TAU, 32, Color(glow.r, glow.g, glow.b, 0.7), 2.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var left: float = lifetime - _age
	visible = left > BLINK_SECONDS or int(left * 8.0) % 2 == 0
	if magnetic and _age >= pickup_delay:
		var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
		if player != null and not player.get("is_dead"):
			if global_position.distance_to(player.global_position) < MAGNET_RADIUS:
				global_position = global_position.move_toward(
					player.global_position, MAGNET_SPEED * delta
				)
	if _waiting_for_delay and _age >= pickup_delay:
		# Someone may already be standing on it; body_entered will not fire again.
		_waiting_for_delay = false
		for body in get_overlapping_bodies():
			_on_body_entered(body)


func _on_body_entered(body: Node) -> void:
	if _age < pickup_delay or is_queued_for_deletion() or not body.is_in_group("player"):
		return
	if kind == "item":
		var picked: bool = (
			body.call("add_stack", stack)
			if not stack.is_empty()
			else body.call("add_item", item_id, amount)
		)
		if not picked:
			return  # bag full: the item stays on the ground
	else:
		body.call("add_gold", amount)
	queue_free()
