extends RefCounted
## G2: a one-time spray of particles, for a level up, a pickup, a skill or a
## boss falling. The particles remove themselves when they are done.

const GROUP := "bursts"


static func spawn(
	parent: Node, at: Vector2, color: Color, amount: int = 24, speed: float = 160.0
) -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.amount = amount
	burst.explosiveness = 0.9
	burst.lifetime = 0.7
	burst.direction = Vector2.UP
	burst.spread = 180.0
	burst.initial_velocity_min = speed * 0.6
	burst.initial_velocity_max = speed
	burst.gravity = Vector2(0, 260)
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 5.0
	burst.color = color
	burst.position = at
	burst.z_index = 15
	burst.add_to_group(GROUP)
	burst.finished.connect(burst.queue_free)
	parent.add_child(burst)
	burst.emitting = true
