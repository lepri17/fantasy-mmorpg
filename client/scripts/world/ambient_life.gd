extends Node2D
## Life in a map (maps.json "life"), so places do not stand still (Mor: "birds,
## trees that move"):
## - "birds": that many birds of kind "bird" (song, sparrow, snow, crow) hop
##   and peck on open ground, and fly off when the hero comes near; a while
##   later they land somewhere else;
## - "butterflies": that many flutter about, each its own colour;
## - "flocks": now and then a few birds fly over, their shadows on the ground;
## - "clouds": that many cloud shadows drift slowly over the map.
## game_map.gd adds it; the trees' sway is its shader (sway.gdshader).
## It rolls its own dice, so it does not change the game's luck (or tests').

const BIRD_PATH := "res://assets/environment/critters/bird_%s.png"
const BUTTERFLY_PATH := "res://assets/environment/critters/butterfly.png"
const BUTTERFLY_COLORS := [
	Color(1.0, 0.85, 0.3), Color(0.55, 0.75, 1.0), Color(1.0, 0.6, 0.8), Color(1.0, 0.65, 0.35),
	Color(0.75, 0.6, 1.0), Color(0.6, 0.95, 0.7)
]
## The hero this close to a bird on the ground, and it flies off.
const FLEE_DISTANCE := 140.0
const FLY_SPEED := 300.0
## Seconds a bird is away before it lands again somewhere else.
const AWAY_SECONDS := Vector2(6.0, 14.0)
const FLOCK_EVERY := Vector2(18.0, 40.0)
const FLOCK_SPEED := 230.0
const CLOUD_SPEED := 16.0
const SHADOW := Color(0.0, 0.0, 0.0, 0.16)

var life: Dictionary = {}
## Each: {"sprite", "state": "ground"/"fly"/"away", "timer", "velocity"}.
var birds: Array = []
## Each: {"sprite", "home", "time", "speed"}.
var butterflies: Array = []
## The birds of a flock flying over now (and their shadows), or none.
var flock: Array = []
var clouds: Array = []
var _bounds := Rect2()
var _flock_wait: float = 0.0
var _populated: bool = false
var _wait_to_populate: float = 0.3
var _rng := RandomNumberGenerator.new()
var _cloud_texture: Texture2D = null


func setup(map_life: Dictionary, bounds: Rect2, seed_from: String) -> void:
	life = map_life
	_bounds = bounds
	_rng.seed = hash(seed_from)
	_flock_wait = _rng.randf_range(4.0, FLOCK_EVERY.x)


func _ready() -> void:
	y_sort_enabled = true
	for i in int(life.get("clouds", 0)):
		_add_cloud()


func _process(delta: float) -> void:
	if not _populated:  # the navigation map is ready a moment after the map
		_wait_to_populate -= delta
		if _wait_to_populate <= 0.0:
			_populate()
		return
	var hero: Node2D = get_tree().get_first_node_in_group("player")
	for bird in birds:
		_update_bird(bird, hero, delta)
	for butterfly in butterflies:
		_update_butterfly(butterfly, delta)
	for cloud in clouds:
		cloud.position.x += CLOUD_SPEED * delta
		if cloud.position.x > _bounds.end.x + 700.0:
			cloud.position.x = _bounds.position.x - 700.0
	if life.get("flocks", false):
		_update_flock(delta)


func _populate() -> void:
	_populated = true
	for i in int(life.get("birds", 0)):
		var spot: Vector2 = _ground_spot()
		if spot == Vector2.INF:
			continue
		var sprite := _sprite(BIRD_PATH % life.get("bird", "song"), 4)
		sprite.position = spot
		sprite.flip_h = _rng.randf() < 0.5
		add_child(sprite)
		birds.append(
			{"sprite": sprite, "state": "ground", "timer": _rng.randf(), "velocity": Vector2.ZERO}
		)
	for i in int(life.get("butterflies", 0)):
		var spot: Vector2 = _ground_spot()
		if spot == Vector2.INF:
			continue
		var sprite := _sprite(BUTTERFLY_PATH, 2)
		sprite.modulate = BUTTERFLY_COLORS[i % BUTTERFLY_COLORS.size()]
		sprite.z_index = 4
		sprite.position = spot
		add_child(sprite)
		var speed: float = _rng.randf_range(0.7, 1.2)
		butterflies.append(
			{"sprite": sprite, "home": spot, "time": _rng.randf() * 10.0, "speed": speed}
		)


## Starts a flock flying over the part of the map the camera shows.
func start_flock() -> void:
	var camera := get_viewport().get_camera_2d()
	var center: Vector2 = _bounds.get_center()
	if camera != null:
		center = camera.get_screen_center_position()
	var heading: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var start := Vector2(center.x - heading * 900.0, center.y + _rng.randf_range(-300.0, 100.0))
	for i in _rng.randi_range(3, 5):
		var offset := Vector2(-heading * 40.0 * i, 26.0 * i * (1 if i % 2 else -1))
		var bird := _sprite(BIRD_PATH % life.get("bird", "song"), 4)
		bird.flip_h = heading < 0.0
		bird.z_index = 30
		bird.position = start + offset
		add_child(bird)
		var shade := _sprite(BIRD_PATH % life.get("bird", "song"), 4)
		shade.frame = 2
		shade.flip_h = bird.flip_h
		shade.modulate = SHADOW
		shade.z_index = -7
		shade.position = bird.position + Vector2(0, 170)
		add_child(shade)
		flock.append({"bird": bird, "shadow": shade, "heading": heading, "life": 1800.0 / FLOCK_SPEED})


func _update_flock(delta: float) -> void:
	if flock.is_empty():
		_flock_wait -= delta
		if _flock_wait <= 0.0:
			_flock_wait = _rng.randf_range(FLOCK_EVERY.x, FLOCK_EVERY.y)
			start_flock()
		return
	for member in flock:
		var step := Vector2(member["heading"] * FLOCK_SPEED * delta, -6.0 * delta)
		member["bird"].position += step
		member["shadow"].position += step
		member["bird"].frame = 2 + int(Time.get_ticks_msec() / 110) % 2
		member["life"] -= delta
	if flock[0]["life"] <= 0.0:
		for member in flock:
			member["bird"].queue_free()
			member["shadow"].queue_free()
		flock.clear()


func _update_bird(bird: Dictionary, hero: Node2D, delta: float) -> void:
	var sprite: Sprite2D = bird["sprite"]
	bird["timer"] -= delta
	match bird["state"]:
		"ground":
			if hero != null and hero.global_position.distance_to(sprite.global_position) < FLEE_DISTANCE:
				fly_off(bird, hero.global_position)
				return
			if bird["timer"] <= 0.0:  # peck, look about, or hop a little
				bird["timer"] = _rng.randf_range(0.3, 1.1)
				var choice: float = _rng.randf()
				if choice < 0.45:
					sprite.frame = 1
				elif choice < 0.8:
					sprite.frame = 0
				else:
					sprite.frame = 0
					sprite.flip_h = _rng.randf() < 0.5
					var hop := Vector2((-1.0 if sprite.flip_h else 1.0) * _rng.randf_range(8.0, 18.0), 0)
					create_tween().tween_property(sprite, "position", sprite.position + hop, 0.18)
		"fly":
			sprite.position += bird["velocity"] * delta
			sprite.frame = 2 + int(bird["timer"] * 9.0) % 2
			if bird["timer"] <= 0.0:
				bird["state"] = "away"
				bird["timer"] = _rng.randf_range(AWAY_SECONDS.x, AWAY_SECONDS.y)
				sprite.visible = false
		"away":
			if bird["timer"] <= 0.0:
				var spot: Vector2 = _ground_spot()
				if spot == Vector2.INF or (hero != null and hero.global_position.distance_to(spot) < 300.0):
					bird["timer"] = 2.0
					return
				sprite.position = spot
				sprite.frame = 0
				sprite.z_index = 0
				sprite.visible = true
				sprite.modulate.a = 0.0
				create_tween().tween_property(sprite, "modulate:a", 1.0, 0.4)
				bird["state"] = "ground"
				bird["timer"] = 1.0


## Off it goes: up and away from `from`, wings flapping.
func fly_off(bird: Dictionary, from: Vector2) -> void:
	var sprite: Sprite2D = bird["sprite"]
	var away: Vector2 = (sprite.global_position - from).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	bird["velocity"] = (away + Vector2(0, -0.9)).normalized() * FLY_SPEED
	sprite.flip_h = bird["velocity"].x < 0.0
	sprite.z_index = 30
	bird["state"] = "fly"
	bird["timer"] = 2.2


func _update_butterfly(butterfly: Dictionary, delta: float) -> void:
	butterfly["time"] += delta * butterfly["speed"]
	var t: float = butterfly["time"]
	var sprite: Sprite2D = butterfly["sprite"]
	sprite.position = (
		butterfly["home"] + Vector2(sin(t * 0.7) * 70.0 + sin(t * 1.9) * 14.0, sin(t * 1.1) * 40.0 - 30.0)
	)
	sprite.frame = int(t * 11.0) % 2
	butterfly["home"] += Vector2(sin(t * 0.13), cos(t * 0.11)) * 6.0 * delta


func _add_cloud() -> void:
	if _cloud_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0, 0, 0, 0.13))
		gradient.set_color(1, Color(0, 0, 0, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 256
		texture.height = 256
		_cloud_texture = texture
	var cloud := Sprite2D.new()
	cloud.texture = _cloud_texture
	cloud.scale = Vector2(_rng.randf_range(3.0, 5.0), _rng.randf_range(1.6, 2.6))
	cloud.position = Vector2(
		_rng.randf_range(_bounds.position.x, _bounds.end.x),
		_rng.randf_range(_bounds.position.y, _bounds.end.y)
	)
	cloud.z_index = -7  # on the ground, under people and trees
	add_child(cloud)
	clouds.append(cloud)


func _sprite(path: String, frames: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.hframes = frames
	sprite.scale = Vector2(0.5, 0.5)
	sprite.offset = Vector2(0, -36)  # the feet (design y 26 of 32, at 64 px) on the point
	return sprite


## A random point on open ground (the map's navigation mesh), or INF.
func _ground_spot() -> Vector2:
	var nav: RID = get_world_2d().navigation_map
	for attempt in 8:
		var want := Vector2(
			_rng.randf_range(_bounds.position.x + 120.0, _bounds.end.x - 120.0),
			_rng.randf_range(_bounds.position.y + 120.0, _bounds.end.y - 120.0)
		)
		var ground: Vector2 = NavigationServer2D.map_get_closest_point(nav, want)
		if ground != Vector2.ZERO and ground.distance_to(want) < 30.0:
			return ground
	return Vector2.INF
