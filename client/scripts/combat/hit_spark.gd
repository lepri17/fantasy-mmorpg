extends RefCounted
## A small burst of sparks where a hit lands. Made in code; frees itself.


static func spawn(parent: Node, at: Vector2, color: Color, amount: int = 8) -> void:
	var sparks := CPUParticles2D.new()
	sparks.one_shot = true
	sparks.emitting = false
	sparks.amount = amount
	sparks.lifetime = 0.35
	sparks.explosiveness = 1.0
	sparks.direction = Vector2.UP
	sparks.spread = 180.0
	sparks.gravity = Vector2(0, 300)
	sparks.initial_velocity_min = 90.0
	sparks.initial_velocity_max = 190.0
	sparks.scale_amount_min = 2.5
	sparks.scale_amount_max = 4.0
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	sparks.color_ramp = fade
	sparks.z_index = 9
	sparks.position = at
	parent.add_child(sparks)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)
