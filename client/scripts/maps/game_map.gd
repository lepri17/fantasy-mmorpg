extends Node2D
## One map. Its entry in res://data/maps.json (by map_id) gives its name,
## where the warrior arrives (spawns) and what stands on it (objects). A map
## with ground rows is built here: a TileMapLayer ground, edges and objects.
## A map with a scene of its own (the meadow) keeps its nodes and only gets
## the objects from the data (its portals).

const GameData := preload("res://scripts/data/game_data.gd")
const MapTiles := preload("res://scripts/maps/map_tiles.gd")
const SCENES := {
	"tree": preload("res://scenes/maps/tree.tscn"),
	"rock": preload("res://scenes/maps/rock.tscn"),
	"monster": preload("res://scenes/enemies/slime.tscn"),
	"portal": preload("res://scenes/maps/portal.tscn"),
}
## How far inside the map's edge the invisible walls stand: left, top, right, bottom.
const EDGE_MARGINS := [24.0, 80.0, 24.0, 20.0]

@export var map_id: String = ""

var data: Dictionary = {}


func _ready() -> void:
	add_to_group("maps")
	y_sort_enabled = true
	data = GameData.table("maps")["maps"].get(map_id, {})
	if data.has("ground"):
		var ground: TileMapLayer = MapTiles.build(data["ground"])
		ground.z_index = -10
		add_child(ground)
		_add_edges()
	for thing in data.get("objects", []):
		_add_object(thing)


## The map's size in pixels.
func map_size() -> Vector2:
	if data.has("ground"):
		var tile: float = float(GameData.table("maps")["tile_size"])
		return Vector2(data["ground"][0].length() * tile, data["ground"].size() * tile)
	var size: Array = data.get("size", [0, 0])
	return Vector2(size[0], size[1])


func bounds() -> Rect2:
	return Rect2(Vector2.ZERO, map_size())


## Where the warrior arrives: a named spawn, else "default".
func spawn_point(spawn: String) -> Vector2:
	var spawns: Dictionary = data.get("spawns", {})
	var point: Array = spawns.get(spawn, spawns.get("default", [0, 0]))
	return Vector2(point[0], point[1])


func display_name() -> String:
	return data.get("name", map_id)


## True in towns: no monsters there.
func is_safe() -> bool:
	return data.get("safe", false)


func _add_object(thing: Dictionary) -> void:
	var node: Node2D = SCENES[thing["type"]].instantiate()
	node.position = Vector2(thing["pos"][0], thing["pos"][1])
	match thing["type"]:
		"monster":
			node.set("monster_id", thing["id"])
		"portal":
			node.set("to_map", thing["to"])
			node.set("to_spawn", thing.get("spawn", "default"))
	add_child(node)


## Invisible walls just inside the edges, like the meadow's WorldBounds.
func _add_edges() -> void:
	var size: Vector2 = map_size()
	var walls := StaticBody2D.new()
	walls.name = "Edges"
	var sides := [
		[Vector2.RIGHT, EDGE_MARGINS[0]],
		[Vector2.DOWN, EDGE_MARGINS[1]],
		[Vector2.LEFT, -(size.x - EDGE_MARGINS[2])],
		[Vector2.UP, -(size.y - EDGE_MARGINS[3])],
	]
	for side in sides:
		var boundary := WorldBoundaryShape2D.new()
		boundary.normal = side[0]
		boundary.distance = side[1]
		var shape := CollisionShape2D.new()
		shape.shape = boundary
		walls.add_child(shape)
	add_child(walls)
