extends Area2D
## A shrine (a maps.json object "shrine"; "gift": "heal" or "power"). Touch it
## while its crystal glows: "heal" makes the hero whole (health, stamina, no
## poison or slow), "power" adds 25% to his damage for a minute, as War Cry
## does. Then it rests for "rest_seconds" and glows again.

const GIFTS := {"heal": Color(0.45, 1.0, 0.6), "power": Color(1.0, 0.62, 0.3)}
const STONE := Color(0.62, 0.62, 0.68)
const STONE_DARK := Color(0.44, 0.44, 0.5)

var gift: String = "heal"
var rest_seconds: float = 180.0
var power_bonus: float = 0.25
var power_seconds: float = 60.0
var _rest_in: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	add_to_group("shrines")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func is_ready() -> bool:
	return _rest_in <= 0.0


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not body.get("is_dead") and is_ready():
		bless(body)


func bless(hero: Node) -> void:
	_rest_in = rest_seconds
	if gift == "power":
		hero.call("bless", power_bonus, power_seconds)
	else:
		hero.call("heal_at_npc")


func _process(delta: float) -> void:
	_time += delta
	_rest_in = maxf(0.0, _rest_in - delta)
	queue_redraw()


func _draw() -> void:
	var glow: Color = GIFTS.get(gift, GIFTS["heal"])
	var ready: bool = is_ready()
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 34.0, Color(0, 0, 0, 0.2))
	if ready:  # a soft ring of light on the ground
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.4)
		draw_circle(Vector2.ZERO, 40.0 + pulse * 6.0, Color(glow.r, glow.g, glow.b, 0.16 + pulse * 0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-22, -10, 44, 12), STONE_DARK)  # the step
	draw_rect(Rect2(-14, -56, 28, 48), STONE)  # the pillar
	draw_rect(Rect2(-14, -56, 28, 48), STONE_DARK, false, 2.0)
	draw_line(Vector2(-6, -48), Vector2(-6, -16), Color(0.75, 0.75, 0.8), 2.0)
	var bob: float = sin(_time * 2.0) * 3.0 if ready else 0.0
	var crystal := PackedVector2Array(
		[Vector2(0, -88 + bob), Vector2(10, -72 + bob), Vector2(0, -58 + bob), Vector2(-10, -72 + bob)]
	)
	var color: Color = glow if ready else glow.darkened(0.6)
	if ready:
		draw_circle(Vector2(0, -73 + bob), 18.0, Color(glow.r, glow.g, glow.b, 0.25))
	draw_colored_polygon(crystal, color)
	draw_polyline(crystal + PackedVector2Array([crystal[0]]), Color(1, 1, 1, 0.6), 1.5)
