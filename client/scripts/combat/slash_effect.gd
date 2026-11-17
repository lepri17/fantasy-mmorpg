extends Node2D
## Short flash drawn around the warrior when he swings: a crescent in front
## for a normal attack (play; bigger and gold for a combo finisher), a full
## ring for the spin skill (play_spin).

const RADIUS := 56.0
const ARC_HALF_ANGLE := 0.9
const DURATION := 0.18
const SPIN_DURATION := 0.32
const SPIN_SCALE := 2.3
const STRONG_SCALE := 1.4

var _half_angle: float = ARC_HALF_ANGLE
var _strong: bool = false
var _tween: Tween


func _ready() -> void:
	hide()


func play(direction: Vector2, strong: bool = false) -> void:
	_half_angle = ARC_HALF_ANGLE
	_strong = strong
	rotation = direction.angle()
	var size: float = STRONG_SCALE if strong else 1.0
	_animate(Vector2(0.7, 0.7) * size, Vector2.ONE * size, 0.0, DURATION)


func play_spin() -> void:
	_half_angle = PI
	_strong = false
	rotation = 0.0
	_animate(Vector2(0.6, 0.6), Vector2(SPIN_SCALE, SPIN_SCALE), TAU, SPIN_DURATION)


func _animate(from_scale: Vector2, to_scale: Vector2, turn: float, duration: float) -> void:
	if _tween != null:
		_tween.kill()
	scale = from_scale
	modulate.a = 1.0
	queue_redraw()
	show()
	_tween = create_tween()
	_tween.tween_property(self, "scale", to_scale, duration)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, duration)
	_tween.parallel().tween_property(self, "rotation", rotation + turn, duration)
	_tween.tween_callback(hide)


func _draw() -> void:
	var outer_color := Color(1, 1, 1, 0.95)
	var inner_color := Color(1, 0.85, 0.4, 0.8)
	if _strong:
		outer_color = Color(1.0, 0.85, 0.35, 0.95)
		inner_color = Color(1.0, 0.5, 0.2, 0.9)
	var inner_radius: float = RADIUS - 8.0
	var inner_angle: float = _half_angle * 0.8
	draw_arc(Vector2.ZERO, RADIUS, -_half_angle, _half_angle, 32, outer_color, 10.0, true)
	draw_arc(Vector2.ZERO, inner_radius, -inner_angle, inner_angle, 32, inner_color, 4.0, true)
