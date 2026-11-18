extends Area2D
## A shot flying in a straight line (a Spore Shroom's spore). It hits the
## warrior (defense and evasion count, and it may carry a status, such as
## poison), stops at trees and rocks, and is gone after a while. It touches
## things at the ground line and is drawn a little higher, at body height.

const CombatRules := preload("res://scripts/combat/combat_rules.gd")
const FloatingText := preload("res://scripts/ui/floating_text.gd")
const HEIGHT := 22.0
const MISS_COLOR := Color(0.8, 0.85, 0.95)

var direction: Vector2 = Vector2.RIGHT
var speed: float = 260.0
var damage: int = 10
## {"status", "chance", "seconds", "value"}, or {}.
var on_hit: Dictionary = {}
var radius: float = 9.0
var color: Color = Color(0.7, 0.92, 0.45)
var lifetime: float = 2.2


func _ready() -> void:
	add_to_group("projectiles")
	var circle := CircleShape2D.new()
	circle.radius = radius
	var shape := CollisionShape2D.new()
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _draw() -> void:
	var middle := Vector2(0.0, -HEIGHT)
	draw_circle(middle, radius + 4.0, Color(color.r, color.g, color.b, 0.3))
	draw_circle(middle, radius, color)
	draw_circle(middle + Vector2(-2.5, -2.5), radius * 0.35, Color(1, 1, 1, 0.8))


func _on_body_entered(body: Node) -> void:
	if is_queued_for_deletion():
		return
	if body.is_in_group("player"):
		_hit(body)
		queue_free()
	elif body.is_in_group("obstacles"):
		queue_free()


func _hit(target: Node) -> void:
	if target.get("is_dead"):
		return
	var stats = target.get("stats")
	var hit: Dictionary = CombatRules.resolve_hit(damage, 0.0, stats.defense(), stats.evasion())
	if hit["miss"]:
		FloatingText.spawn(target, "MISS", MISS_COLOR, 100.0, 22)
		return
	target.call("take_damage", hit["damage"])
	if not on_hit.is_empty() and randf() < float(on_hit.get("chance", 1.0)):
		target.call(
			"apply_status", on_hit["status"], float(on_hit["seconds"]), float(on_hit.get("value", 0.0))
		)
