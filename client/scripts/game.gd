extends Node2D
## The game: the warrior and one map at a time under World. Portals and the
## death screen call change_map(); the first map is the one the save names,
## else the meadow that main.tscn starts with. W7: on a map with an
## "invasion" in maps.json, monsters invade at set minutes of the clock.

const Settings = preload("res://scripts/settings.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const MAP_SCENE := preload("res://scenes/maps/map.tscn")
const SLIME_SCENE := preload("res://scenes/enemies/slime.tscn")
const INVADERS := "invaders"
const SkyClock := preload("res://scripts/world/sky.gd")
const FloatingText := preload("res://scripts/ui/floating_text.gd")
const MUSIC_DB := -14.0
## Rain makes the day a little greyer.
const RAIN_DIM := Color(0.86, 0.88, 0.94)

## Off in the smoke test, so the clock cannot start an invasion mid-test.
static var invasions_enabled: bool = true
## Seconds since midnight to use for the sky instead of the clock (tests,
## screenshots), or below 0 for the clock.
static var sky_seconds: float = -1.0

## The map node shown now (game_map.gd).
var map = null
var _invasion_check: float = 0.0
var _sky_check: float = 0.0
var _daylight: CanvasModulate
var _rain: CPUParticles2D
var _music: AudioStreamPlayer
## The invasion window already used ("YYYY-MM-DD HH:MM"), so it comes once.
var _invaded_window: String = ""

@onready var _world: Node2D = $World
@onready var _player = $World/Player
@onready var _hud = $Hud


func _ready() -> void:
	add_to_group("game")
	_build_sky()
	var pool := Node.new()
	pool.name = "TextPool"
	pool.add_to_group(FloatingText.POOL_GROUP)
	add_child(pool)
	map = _world.get_node("Map")
	var saved: String = _player.stats.map_id
	if saved != "" and saved != map.map_id and _maps().has(saved):
		_swap_map(saved, "default")
	else:
		_arrive(_player.global_position)


func _process(delta: float) -> void:
	_sky_check -= delta
	if _sky_check <= 0.0:
		_sky_check = 0.5
		update_sky()
	_invasion_check -= delta
	if not invasions_enabled or _invasion_check > 0.0:
		return
	_invasion_check = 1.0
	var invasion: Dictionary = _maps()[map.map_id].get("invasion", {})
	if invasion.is_empty():
		return
	var window: String = invasion_window(invasion, Time.get_datetime_dict_from_system())
	if window != "" and window != _invaded_window:
		_invaded_window = window
		start_invasion()
	elif window == "" and not get_tree().get_nodes_in_group(INVADERS).is_empty():
		end_invasion()


## The invasion window a time falls in ("2026-11-18 14:30"), or "" outside them.
static func invasion_window(invasion: Dictionary, now: Dictionary) -> String:
	var every: int = int(invasion["every_minutes"])
	var minute: int = int(now["minute"])
	if minute % every >= int(invasion["lasts_minutes"]):
		return ""
	return (
		"%04d-%02d-%02d %02d:%02d"
		% [now["year"], now["month"], now["day"], now["hour"], minute - minute % every]
	)


## Invaders appear at random spots in the map's invasion area. They do not
## come back once beaten, and run off when the window ends.
func start_invasion() -> void:
	var invasion: Dictionary = _maps()[map.map_id].get("invasion", {})
	if invasion.is_empty():
		return
	var area: Array = invasion["area"]
	for i in int(invasion["count"]):
		var invader: Node2D = SLIME_SCENE.instantiate()
		invader.set("monster_id", invasion["monster"])
		invader.set("respawns", false)
		invader.position = Vector2(randf_range(area[0], area[2]), randf_range(area[1], area[3]))
		invader.add_to_group(INVADERS)
		map.add_child(invader)
	var monster_name: String = GameData.table("monsters")[invasion["monster"]]["name"]
	_hud.call("show_banner", "%s invasion!" % monster_name, "Beat them before they run off")


func end_invasion() -> void:
	for invader in get_tree().get_nodes_in_group(INVADERS):
		if not invader.get("is_dead"):
			invader.queue_free()
	_hud.call("show_banner", "The invaders ran off", "")


## Takes the warrior to another map, after the current physics step.
func change_map(map_id: String, spawn: String = "default") -> void:
	if not _maps().has(map_id):
		return
	if _maps()[map_id].has("dungeon") and not _player.call("enter_dungeon", map_id):
		return
	call_deferred("_swap_map", map_id, spawn)


## The death screen's button: get up at once, in town.
func return_to_town() -> void:
	_player.call("revive")
	change_map(GameData.table("maps")["town"])


static func _maps() -> Dictionary:
	return GameData.table("maps")["maps"]


func _swap_map(map_id: String, spawn: String) -> void:
	_world.remove_child(map)
	map.queue_free()
	var scene_path: String = _maps()[map_id].get("scene", "")
	map = (load(scene_path) if scene_path != "" else MAP_SCENE).instantiate()
	map.set("map_id", map_id)
	map.name = "Map"
	_world.add_child(map)
	_world.move_child(map, 0)
	_arrive(map.spawn_point(spawn))


## W8 / G3: tints the world with the time of day (or the dark of a cellar),
## lights the warrior when it is dark, and lets it rain now and then.
func update_sky() -> void:
	var seconds: float = sky_seconds
	if seconds < 0.0:
		var now: Dictionary = Time.get_time_dict_from_system()
		seconds = now["hour"] * 3600.0 + now["minute"] * 60.0 + now["second"]
	var indoor: bool = _maps()[map.map_id].get("indoor", false)
	var raining: bool = not indoor and SkyClock.raining(seconds)
	var light: Color = SkyClock.INDOOR if indoor else SkyClock.daylight(seconds)
	_daylight.color = light * RAIN_DIM if raining else light
	_player.call("set_light", SkyClock.darkness(_daylight.color))
	_rain.emitting = raining


## G4: the map's music, looping. Changing maps fades the new track in.
func _play_music(track: String) -> void:
	if track == "":
		_music.stop()
		return
	var path: String = "res://assets/audio/%s.wav" % track
	if _music.playing and _music.stream != null and _music.stream.resource_path == path:
		return
	_music.stream = load(path)
	_music.volume_db = -40.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", MUSIC_DB, 0.8)


func _build_sky() -> void:
	_daylight = CanvasModulate.new()
	_daylight.name = "Daylight"
	add_child(_daylight)
	_rain = CPUParticles2D.new()
	_rain.name = "Rain"
	_rain.amount = 160
	_rain.lifetime = 1.0
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain.emission_rect_extents = Vector2(760, 20)
	_rain.position = Vector2(0, -460)
	_rain.direction = Vector2(-0.2, 1)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 700.0
	_rain.initial_velocity_max = 820.0
	_rain.gravity = Vector2.ZERO
	var streak := Image.create(2, 16, false, Image.FORMAT_RGBA8)
	streak.fill(Color(1, 1, 1, 1))
	_rain.texture = ImageTexture.create_from_image(streak)
	_rain.particle_flag_align_y = true
	_rain.scale_amount_min = 0.8
	_rain.scale_amount_max = 1.2
	_rain.color = Color(0.75, 0.85, 1.0, 0.5)
	_rain.emitting = false
	_player.add_child(_rain)
	Settings.apply_audio()
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.name = "Music"
	_music.volume_db = MUSIC_DB
	_music.finished.connect(_music.play)
	add_child(_music)


func _arrive(point: Vector2) -> void:
	_player.call("enter_map", map.map_id, point, map.spawn_point("default"), map.bounds())
	_play_music(_maps()[map.map_id].get("music", ""))
	update_sky()
	_hud.call("show_banner", map.display_name(), _maps()[map.map_id].get("levels", ""))
