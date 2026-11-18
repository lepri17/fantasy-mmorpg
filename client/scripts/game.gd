extends Node2D
## The game: the warrior and one map at a time under World. Portals and the
## death screen call change_map(); the first map is the one the save names,
## else the meadow that main.tscn starts with. W7: on a map with an
## "invasion" in maps.json, monsters invade at set minutes of the clock.

const GameData := preload("res://scripts/data/game_data.gd")
const MAP_SCENE := preload("res://scenes/maps/map.tscn")
const SLIME_SCENE := preload("res://scenes/enemies/slime.tscn")
const INVADERS := "invaders"

## Off in the smoke test, so the clock cannot start an invasion mid-test.
static var invasions_enabled: bool = true

## The map node shown now (game_map.gd).
var map = null
var _invasion_check: float = 0.0
## The invasion window already used ("YYYY-MM-DD HH:MM"), so it comes once.
var _invaded_window: String = ""

@onready var _world: Node2D = $World
@onready var _player = $World/Player
@onready var _hud = $Hud


func _ready() -> void:
	add_to_group("game")
	map = _world.get_node("Map")
	var saved: String = _player.stats.map_id
	if saved != "" and saved != map.map_id and _maps().has(saved):
		_swap_map(saved, "default")
	else:
		_arrive(_player.global_position)


func _process(delta: float) -> void:
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


func _arrive(point: Vector2) -> void:
	_player.call("enter_map", map.map_id, point, map.spawn_point("default"), map.bounds())
	_hud.call("show_banner", map.display_name(), _maps()[map.map_id].get("levels", ""))
