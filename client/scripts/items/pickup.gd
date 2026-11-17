extends Area2D
## Loot lying on the ground. The warrior collects it by walking over it.
## Whoever drops it sets kind ("gold" or "item"), amount, item_id for items,
## and lifetime / pickup_delay if they should differ, before adding it.

const ItemDb := preload("res://scripts/items/item_db.gd")
const COIN_TEXTURE := preload("res://assets/items/coin.png")
## Loot blinks for this long before it disappears.
const BLINK_SECONDS := 5.0
## Inventory icons are 64 px; on the ground they are shown at about half size.
const ICON_SCALE_ON_GROUND := 0.55

var kind: String = "gold"
var item_id: String = ""
var amount: int = 1
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
	_sprite.scale = Vector2.ONE * target_scale * 0.3
	create_tween().tween_property(_sprite, "scale", Vector2.ONE * target_scale, 0.25)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var left: float = lifetime - _age
	visible = left > BLINK_SECONDS or int(left * 8.0) % 2 == 0
	if _waiting_for_delay and _age >= pickup_delay:
		# Someone may already be standing on it; body_entered will not fire again.
		_waiting_for_delay = false
		for body in get_overlapping_bodies():
			_on_body_entered(body)


func _on_body_entered(body: Node) -> void:
	if _age < pickup_delay or is_queued_for_deletion() or not body.is_in_group("player"):
		return
	if kind == "item":
		if not body.call("add_item", item_id, amount):
			return  # bag full: the item stays on the ground
	else:
		body.call("add_gold", amount)
	queue_free()
