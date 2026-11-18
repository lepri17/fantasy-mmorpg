extends Node2D
## The game: the warrior and one map at a time under World. Portals and the
## death screen call change_map(); the first map is the one the save names,
## else the meadow that main.tscn starts with.

const GameData := preload("res://scripts/data/game_data.gd")
const MAP_SCENE := preload("res://scenes/maps/map.tscn")

## The map node shown now (game_map.gd).
var map = null

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


## Takes the warrior to another map, after the current physics step.
func change_map(map_id: String, spawn: String = "default") -> void:
	if _maps().has(map_id):
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
