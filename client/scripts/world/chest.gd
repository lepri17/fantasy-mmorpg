extends Area2D
## A treasure chest (a maps.json object "chest"; "level" picks the gear it may
## hold). Walk up to it and it opens: gold, a potion now and then, and a chance
## of a piece of gear for the hero's class (rolled like a monster's drop, from
## ItemDb.drop_pool, with a better rarity roll). It shuts and fills again after
## "refill_seconds".

const ItemDb := preload("res://scripts/items/item_db.gd")
const FloatingText := preload("res://scripts/ui/floating_text.gd")
const PICKUP_SCENE := preload("res://scenes/items/pickup.tscn")
const WOOD := Color(0.62, 0.39, 0.2)
const WOOD_DARK := Color(0.42, 0.25, 0.13)
const TRIM := Color(0.98, 0.8, 0.32)
const INSIDE := Color(0.2, 0.12, 0.08)

var level: int = 5
var refill_seconds: float = 300.0
var gear_chance: float = 0.4
var is_open: bool = false
var _refill_in: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	add_to_group("chests")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 36.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not body.get("is_dead") and not is_open:
		open_for(body)


## Opens and spills its treasure in front of it.
func open_for(hero: Node) -> void:
	is_open = true
	_refill_in = refill_seconds
	_drop("gold", roundi(level * randf_range(9.0, 15.0)) + 10)
	if randf() < 0.5:
		_drop("item", 1, "red_potion")
	if randf() < gear_chance:
		var stats = hero.get("stats")
		var class_id: String = stats.class_id if stats != null else ""
		var pool: Array = ItemDb.drop_pool(level).filter(
			func(item_id: String) -> bool: return class_id == "" or ItemDb.usable_by(item_id, class_id)
		)
		if not pool.is_empty():
			_drop_gear(ItemDb.roll_gear(pool.pick_random(), 2))
	FloatingText.spawn(self, "TREASURE!", TRIM, 70.0, 26)
	if hero.has_method("_sfx"):
		hero.call("_sfx", "levelup")
	queue_redraw()


func _drop(kind: String, amount: int, item_id: String = "") -> void:
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", kind)
	pickup.set("amount", amount)
	pickup.set("item_id", item_id)
	pickup.position = position + Vector2(randf_range(-40.0, 40.0), randf_range(26.0, 46.0))
	get_parent().call_deferred("add_child", pickup)


func _drop_gear(piece: Dictionary) -> void:
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", "item")
	pickup.set("item_id", piece["id"])
	pickup.set("stack", piece)
	pickup.set("lifetime", float(ItemDb.rarities[piece["rarity"]].get("ground_seconds", 60)))
	pickup.position = position + Vector2(randf_range(-30.0, 30.0), 50.0)
	get_parent().call_deferred("add_child", pickup)


func _process(delta: float) -> void:
	_time += delta
	if is_open:
		_refill_in -= delta
		if _refill_in <= 0.0:
			is_open = false
			queue_redraw()
	elif int(_time * 5.0) != int((_time - delta) * 5.0):
		queue_redraw()  # the glint twinkles


func _draw() -> void:
	draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-24, -26, 48, 30), WOOD)
	draw_rect(Rect2(-24, -26, 48, 30), WOOD_DARK, false, 2.0)
	for x in [-16.0, 12.0]:
		draw_rect(Rect2(x, -26, 5, 30), TRIM)
	if is_open:
		draw_rect(Rect2(-22, -34, 44, 10), INSIDE)
		draw_rect(Rect2(-25, -52, 50, 16), WOOD)  # the lid, thrown back
		draw_rect(Rect2(-25, -52, 50, 16), WOOD_DARK, false, 2.0)
		return
	draw_rect(Rect2(-26, -40, 52, 16), WOOD)  # the lid
	draw_rect(Rect2(-26, -40, 52, 16), WOOD_DARK, false, 2.0)
	for x in [-16.0, 12.0]:
		draw_rect(Rect2(x, -40, 5, 16), TRIM)
	draw_rect(Rect2(-5, -30, 10, 10), TRIM)  # the lock
	draw_rect(Rect2(-2, -27, 4, 5), WOOD_DARK)
	var twinkle: float = absf(sin(_time * 2.5))
	if twinkle > 0.6:  # a glint on the lid says there is something in it
		var spot := Vector2(16, -40)
		var arm: float = 7.0 * twinkle
		draw_line(spot - Vector2(arm, 0), spot + Vector2(arm, 0), Color(1, 1, 0.85), 2.0)
		draw_line(spot - Vector2(0, arm), spot + Vector2(0, arm), Color(1, 1, 0.85), 2.0)
