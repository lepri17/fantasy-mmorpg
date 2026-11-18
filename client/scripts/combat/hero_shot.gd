extends Area2D
## A shot fired by the hero: the mage's bolt and fireball, the archer's arrows.
## It flies straight, hits the first enemy (or every enemy in its way when it
## pierces), stops at trees and rocks, and is gone at the end of its reach. The
## hit itself is worked out by the hero (player.gd shot_hit), so crits, misses
## and defense work as for a swing. It touches things at the ground line and is
## drawn a little higher, at body height.

const HEIGHT := 24.0
const SHAFT := Color(0.5, 0.34, 0.22)
const FLETCH := Color(0.92, 0.38, 0.34)

## The hero who fired it (player.gd).
var shooter: Node2D = null
var direction: Vector2 = Vector2.RIGHT
var speed: float = 500.0
## How far it flies, in pixels.
var reach: float = 320.0
var damage: int = 10
var knockback: float = 1.0
## "bolt", "fire", "arrow" or "spirit".
var kind: String = "bolt"
var color: Color = Color(0.78, 0.62, 1.0)
var radius: float = 8.0
var pierce: bool = false
## Above 0: bursts there and hits every enemy this close (Fireball).
var blast_radius: float = 0.0
## The hero's cast it belongs to: shots of one cast (Multi Shot's arrows) hit
## each enemy only once between them (player.gd _strike).
var cast: int = 0

var _travelled: float = 0.0
var _hit: Array = []


func _ready() -> void:
	add_to_group("hero_shots")
	var circle := CircleShape2D.new()
	circle.radius = radius
	var shape := CollisionShape2D.new()
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var step: float = speed * delta
	position += direction * step
	_travelled += step
	if _travelled >= reach:
		queue_free()


func _draw() -> void:
	var middle := Vector2(0.0, -HEIGHT)
	match kind:
		"arrow", "spirit":
			_draw_arrow(middle, kind == "spirit")
		"fire":
			draw_circle(middle, radius + 6.0, Color(1.0, 0.4, 0.1, 0.3))
			draw_circle(middle, radius, color)
			draw_circle(middle - direction * 2.0, radius * 0.5, Color(1.0, 0.95, 0.7))
		_:
			draw_circle(middle, radius + 5.0, Color(color, 0.3))
			draw_circle(middle, radius, color)
			draw_circle(middle + Vector2(-2.0, -2.0), radius * 0.4, Color(1, 1, 1, 0.85))


func _draw_arrow(middle: Vector2, glowing: bool) -> void:
	var tip: Vector2 = middle + direction * 12.0
	var tail: Vector2 = middle - direction * 16.0
	var side: Vector2 = direction.orthogonal()
	if glowing:
		draw_line(tail - direction * 18.0, tip, Color(color, 0.35), radius)
		draw_line(tail, tip, color, 4.0)
	else:
		draw_line(tail, tip, SHAFT, 2.0)
	var head := PackedVector2Array([tip + direction * 7.0, tip + side * 4.0, tip - side * 4.0])
	draw_colored_polygon(head, Color(0.92, 0.95, 1.0))
	for sign in [-1.0, 1.0]:
		draw_line(tail, tail - direction * 5.0 + side * 4.0 * sign, FLETCH, 2.0)


func _on_body_entered(body: Node) -> void:
	if is_queued_for_deletion():
		return
	if body.is_in_group("enemies"):
		if body.get("is_dead") or _hit.has(body):
			return
		_hit.append(body)
		if is_instance_valid(shooter):
			shooter.call("shot_hit", self, body)
		if not pierce:
			queue_free()
	elif body.is_in_group("obstacles"):
		queue_free()
