extends RefCounted
## The mage's and the archer's skills, the job skills of all three classes
## (Great Cleave, Chain Lightning, Spirit Arrow), and the shots the mage and
## the archer fire (hero_shot.gd). The warrior's first four skills are in
## player.gd. Every function gets the hero (player.gd) and the skill's entry
## from skills.json.

const HeroShot := preload("res://scripts/combat/hero_shot.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const Telegraph := preload("res://scripts/combat/telegraph.gd")
const ShieldBubble := preload("res://scripts/combat/shield_bubble.gd")
const Lightning := preload("res://scripts/combat/lightning.gd")
const FloatingText := preload("res://scripts/ui/floating_text.gd")
const FIRE := Color(1.0, 0.55, 0.2)
const ICE := Color(0.6, 0.88, 1.0)
const ARCANE := Color(0.62, 0.52, 1.0)
const ARROW := Color(0.95, 0.9, 0.8)
const SPIRIT := Color(0.5, 0.95, 1.0)
## Seconds before the first arrows of Arrow Rain land.
const RAIN_START := 0.2


static func cast(hero: Node2D, skill: Dictionary) -> void:
	match skill["type"]:
		"bolt":
			_fireball(hero, skill)
		"nova":
			_frost_nova(hero, skill)
		"shield":
			_mana_shield(hero, skill)
		"meteor":
			_meteor(hero, skill)
		"fan":
			_multi_shot(hero, skill)
		"pierce":
			_piercing_arrow(hero, skill)
		"rain":
			_arrow_rain(hero, skill)
		"cleave":
			_great_cleave(hero, skill)
		"chain":
			_chain_lightning(hero, skill)


## Fires one shot from the hero. settings sets the shot's fields (see
## hero_shot.gd): kind, speed, reach, damage, knockback, color, radius...
static func shoot(hero: Node2D, direction: Vector2, settings: Dictionary) -> Area2D:
	var shot: Area2D = HeroShot.new()
	shot.shooter = hero
	shot.direction = direction
	shot.position = hero.position + direction * 16.0
	for key in settings:
		shot.set(key, settings[key])
	hero.get_parent().add_child(shot)
	return shot


## Calls back after a while, from a Timer under the hero: it goes away with the
## hero, so nothing is left waiting when the game closes.
static func later(hero: Node, seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(seconds, 0.01)
	timer.timeout.connect(callback)
	timer.timeout.connect(timer.queue_free)
	hero.add_child(timer)
	timer.start()


## A circle on the ground where a spell is about to land (in the hero's colours).
static func mark(hero: Node2D, point: Vector2, radius: float, seconds: float, color: Color) -> void:
	var circle: Node2D = Telegraph.new()
	circle.radius = radius
	circle.seconds = seconds
	circle.color = color
	circle.position = hero.get_parent().to_local(point)
	hero.get_parent().add_child(circle)


static func _arrow(hero: Node2D, skill: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var settings := {
		"kind": "arrow",
		"speed": float(skill["speed"]),
		"reach": float(skill["range"]),
		"damage": hero.skill_damage(skill),
		"color": ARROW,
		"radius": 7.0,
		"knockback": 0.8,
		"cast": hero.current_cast,
	}
	return settings.merged(extra, true)


## Fireball: a slow ball of fire that bursts on the first enemy it hits.
static func _fireball(hero: Node2D, skill: Dictionary) -> void:
	var direction: Vector2 = hero.aim(float(skill["range"]))
	var settings := {
		"kind": "fire",
		"speed": float(skill["speed"]),
		"reach": float(skill["range"]),
		"damage": hero.skill_damage(skill),
		"blast_radius": float(skill["blast_radius"]),
		"radius": 11.0,
		"color": FIRE,
		"knockback": 1.5,
		"cast": hero.current_cast,
	}
	shoot(hero, direction, settings)
	hero.play_sound("skill")


## Frost Nova: hits every enemy around the mage and slows the ones it hits.
static func _frost_nova(hero: Node2D, skill: Dictionary) -> void:
	hero.effect_ring()
	Burst.spawn(hero, Vector2(0, -20), ICE, 34, 260.0)
	hero.play_sound("skill")
	var slow := {"effect": "slow", "seconds": skill["slow_seconds"], "value": skill["slow"]}
	var enemies: Array = hero.enemies_near(hero.global_position, float(skill["radius"]))
	hero.hit_all(enemies, hero.skill_damage(skill), 1.2, slow)


## Mana Shield: less damage taken for a while, with a bubble round the mage.
static func _mana_shield(hero: Node2D, skill: Dictionary) -> void:
	hero.set_guard(float(skill["damage_cut"]), float(skill["seconds"]))
	for old in hero.get_children():
		if old.is_in_group("shield_bubbles"):
			old.queue_free()
	var bubble: Node2D = ShieldBubble.new()
	bubble.seconds = float(skill["seconds"])
	bubble.color = ARCANE
	hero.add_child(bubble)
	FloatingText.spawn(hero, skill["name"].to_upper() + "!", ARCANE, 130.0, 30)
	hero.play_sound("levelup")


## Meteor: a circle shows where it falls; after a moment everything in it is
## hit hard and stunned.
static func _meteor(hero: Node2D, skill: Dictionary) -> void:
	hero.aim(float(skill["range"]))
	var point: Vector2 = hero.target_point(float(skill["range"]))
	mark(hero, point, float(skill["radius"]), float(skill["delay"]), FIRE)
	hero.play_sound("skill")
	var cast: int = hero.current_cast
	later(hero, float(skill["delay"]), func() -> void: _meteor_lands(hero, skill, point, cast))


static func _meteor_lands(hero: Node2D, skill: Dictionary, point: Vector2, cast: int) -> void:
	if not is_instance_valid(hero) or hero.get_parent() == null:
		return
	var world: Node2D = hero.get_parent()
	Burst.spawn(world, world.to_local(point) + Vector2(0, -12), FIRE, 44, 280.0)
	hero.shake()
	var stun := {"effect": "stun", "seconds": skill["stun_seconds"]}
	var enemies: Array = hero.enemies_near(point, float(skill["radius"]))
	hero.hit_all(enemies, hero.skill_damage(skill), 2.0, stun, true, cast)


## Multi Shot: arrows in a fan towards the nearest enemy.
static func _multi_shot(hero: Node2D, skill: Dictionary) -> void:
	var middle: Vector2 = hero.aim(float(skill["range"]))
	var count: int = int(skill["arrows"])
	var spread: float = deg_to_rad(float(skill["spread_degrees"]))
	for i in count:
		var turn: float = 0.0
		if count > 1:
			turn = lerpf(-spread / 2.0, spread / 2.0, float(i) / float(count - 1))
		shoot(hero, middle.rotated(turn), _arrow(hero, skill))
	hero.play_sound("skill")


## Piercing Arrow (and the Ranger's Spirit Arrow): flies through every enemy in
## its way.
static func _piercing_arrow(hero: Node2D, skill: Dictionary) -> void:
	var direction: Vector2 = hero.aim(float(skill["range"]))
	var spirit: bool = skill.has("shot_radius")
	var extra := {
		"pierce": true,
		"kind": "spirit" if spirit else "arrow",
		"color": SPIRIT if spirit else ARROW,
		"radius": float(skill.get("shot_radius", 8.0)),
		"knockback": float(skill.get("knockback", 1.0)),
	}
	shoot(hero, direction, _arrow(hero, skill, extra))
	hero.play_sound("skill")


## Arrow Rain: several waves of arrows on the area round the nearest enemy.
static func _arrow_rain(hero: Node2D, skill: Dictionary) -> void:
	hero.aim(float(skill["range"]))
	var point: Vector2 = hero.target_point(float(skill["range"]))
	var waves: int = int(skill["waves"])
	var every: float = float(skill["every"])
	mark(hero, point, float(skill["radius"]), RAIN_START + every * waves, ARROW)
	hero.play_sound("skill")
	for wave in waves:
		later(hero, RAIN_START + every * wave, func() -> void: _rain_wave(hero, skill, point))


static func _rain_wave(hero: Node2D, skill: Dictionary, point: Vector2) -> void:
	if not is_instance_valid(hero) or hero.get_parent() == null:
		return
	var world: Node2D = hero.get_parent()
	var radius: float = float(skill["radius"])
	for i in 3:
		var spot := Vector2(randf_range(-radius, radius), randf_range(-radius, radius) * 0.5) * 0.7
		Burst.spawn(world, world.to_local(point) + spot, ARROW, 8, 140.0)
	var enemies: Array = hero.enemies_near(point, radius)
	# Every wave may hit again: no cast (each enemy is in the list once).
	hero.hit_all(enemies, hero.skill_damage(skill), 0.4, {}, true, 0)


## Great Cleave (Champion): one huge swing at everything in front.
static func _great_cleave(hero: Node2D, skill: Dictionary) -> void:
	var radius: float = float(skill["radius"])
	var direction: Vector2 = hero.aim(radius)
	hero.effect_swing(direction)
	hero.shake()
	hero.play_sound("skill")
	Burst.spawn(hero, direction * 60.0 + Vector2(0, -20), Color(1.0, 0.85, 0.5), 30, 260.0)
	var half: float = deg_to_rad(float(skill["arc_degrees"])) / 2.0
	var targets: Array = []
	for enemy in hero.enemies_near(hero.global_position, radius):
		var to_enemy: Vector2 = enemy.global_position - hero.global_position
		if to_enemy.length() < 1.0 or absf(direction.angle_to(to_enemy)) <= half:
			targets.append(enemy)
	hero.hit_all(targets, hero.skill_damage(skill), 3.0, {}, true)


## Chain Lightning (Sorcerer): strikes the nearest enemy, then jumps on from
## each one to the nearest it has not hit yet.
static func _chain_lightning(hero: Node2D, skill: Dictionary) -> void:
	hero.aim(float(skill["range"]))
	hero.play_sound("skill")
	var struck: Array = []
	var points: Array[Vector2] = [hero.global_position + Vector2(0, -34)]
	var from: Vector2 = hero.global_position
	var reach: float = float(skill["range"])
	for i in int(skill["jumps"]) + 1:
		var next: Node2D = null
		var best: float = reach
		for enemy in hero.enemies_near(from, reach):
			var distance: float = enemy.global_position.distance_to(from)
			if not struck.has(enemy) and distance <= best:
				next = enemy
				best = distance
		if next == null:
			break
		struck.append(next)
		points.append(next.global_position + Vector2(0, -20))
		from = next.global_position
		reach = float(skill["jump_range"])
	if struck.is_empty():
		return
	var bolt: Node2D = Lightning.new()
	var world: Node2D = hero.get_parent()
	for point in points:
		bolt.points.append(world.to_local(point))
	world.add_child(bolt)
	hero.hit_all(struck, hero.skill_damage(skill), 0.8, {}, true)
