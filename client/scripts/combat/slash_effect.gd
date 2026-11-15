extends Node2D
## Short crescent flash drawn in front of the warrior when he swings.
## The parent calls play() with the direction of the swing.

const RADIUS := 56.0
const ARC_HALF_ANGLE := 0.9
const DURATION := 0.18

var _tween: Tween


func _ready() -> void:
	hide()


func play(direction: Vector2) -> void:
	if _tween != null:
		_tween.kill()
	rotation = direction.angle()
	scale = Vector2(0.7, 0.7)
	modulate.a = 1.0
	show()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, DURATION)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, DURATION)
	_tween.tween_callback(hide)


func _draw() -> void:
	var outer_color := Color(1, 1, 1, 0.95)
	var inner_color := Color(1, 0.85, 0.4, 0.8)
	var inner_radius: float = RADIUS - 8.0
	var inner_angle: float = ARC_HALF_ANGLE * 0.8
	draw_arc(Vector2.ZERO, RADIUS, -ARC_HALF_ANGLE, ARC_HALF_ANGLE, 20, outer_color, 10.0, true)
	draw_arc(Vector2.ZERO, inner_radius, -inner_angle, inner_angle, 20, inner_color, 4.0, true)
