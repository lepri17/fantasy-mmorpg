extends Area2D
## Loot lying on the ground. The warrior collects it by walking over it.
## Whoever drops it sets kind ("gold" or "potion") and amount before adding it.

const TEXTURES := {
	"gold": preload("res://assets/items/coin.png"),
	"potion": preload("res://assets/items/potion.png"),
}
const LIFETIME_SECONDS := 30.0

var kind: String = "gold"
var amount: int = 1

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("pickups")
	_sprite.texture = TEXTURES.get(kind, TEXTURES["gold"])
	_sprite.scale = Vector2(0.3, 0.3)
	create_tween().tween_property(_sprite, "scale", Vector2.ONE, 0.25)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(LIFETIME_SECONDS).timeout.connect(queue_free)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if kind == "potion":
		body.call("add_potions", amount)
	else:
		body.call("add_gold", amount)
	queue_free()
