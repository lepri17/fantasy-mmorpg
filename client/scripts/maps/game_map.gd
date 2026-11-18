extends Node2D
## One map. Its entry in res://data/maps.json (by map_id) gives its name,
## where the warrior arrives (spawns) and what stands on it (objects). Roads
## at its edges ("exit" objects) lead on into the next maps: the open world. A map
## with ground rows is built here: a TileMapLayer ground, edges and objects.
## A map with a scene of its own (the meadow) keeps its nodes and only gets
## the objects from the data (its portals).

const GameData := preload("res://scripts/data/game_data.gd")
const MapTiles := preload("res://scripts/maps/map_tiles.gd")
const DungeonRun := preload("res://scripts/maps/dungeon_run.gd")
const Torch := preload("res://scripts/world/torch.gd")
const Glowcap := preload("res://scripts/world/glowcap.gd")
const EdgeExit := preload("res://scripts/maps/edge_exit.gd")
const SCENES := {
	"tree": preload("res://scenes/maps/tree.tscn"),
	"rock": preload("res://scenes/maps/rock.tscn"),
	"monster": preload("res://scenes/enemies/slime.tscn"),
	"portal": preload("res://scenes/maps/portal.tscn"),
	"npc": preload("res://scenes/maps/npc.tscn"),
}
## Monsters keep this far from trees and rocks when they find their way.
const NAV_AGENT_RADIUS := 18.0
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
	if int(data.get("fireflies", 0)) > 0:
		_add_fireflies(int(data["fireflies"]))
	call_deferred("_bake_navigation")
	if data.has("dungeon"):
		var run: Node = DungeonRun.new()
		run.name = "DungeonRun"
		add_child(run)
		run.setup(data["dungeon"])


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
	if thing["type"] == "exit":
		_add_exit(thing)
		return
	var node: Node2D
	match thing["type"]:
		"torch":
			node = Torch.new()
		"glowcap":
			node = Glowcap.new()
			node.set("color_name", thing.get("color", "cyan"))
		_:
			node = SCENES[thing["type"]].instantiate()
	node.position = Vector2(thing["pos"][0], thing["pos"][1])
	if thing["type"] in ["tree", "rock"]:
		# The deep forest: bigger, darker trees (maps.json "scale" and "tint").
		node.scale = Vector2.ONE * float(thing.get("scale", 1.0))
		var rgba: Array = thing.get("tint", [1, 1, 1, 1])
		node.modulate = Color(rgba[0], rgba[1], rgba[2], rgba[3])
	match thing["type"]:
		"monster":
			node.set("monster_id", thing["id"])
		"npc":
			node.set("npc_id", thing["id"])
		"portal":
			node.set("to_map", thing["to"])
			node.set("to_spawn", thing.get("spawn", "default"))
	add_child(node)


## A road out at an edge into the next map (edge_exit.gd): the open world.
func _add_exit(thing: Dictionary) -> void:
	var road = EdgeExit.new()
	road.side = thing["side"]
	road.span = Vector2(thing["span"][0], thing["span"][1])
	road.map_size = map_size()
	road.to_map = thing["to"]
	road.to_spawn = thing.get("spawn", "default")
	add_child(road)


## Fireflies drifting over the whole map (maps.json "fireflies": how many).
func _add_fireflies(count: int) -> void:
	var flies := CPUParticles2D.new()
	flies.name = "Fireflies"
	flies.amount = count
	flies.lifetime = 7.0
	flies.preprocess = 7.0
	flies.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flies.emission_rect_extents = map_size() / 2.0
	flies.position = map_size() / 2.0
	flies.direction = Vector2(0, -1)
	flies.spread = 180.0
	flies.gravity = Vector2.ZERO
	flies.initial_velocity_min = 4.0
	flies.initial_velocity_max = 16.0
	flies.scale_amount_min = 2.0
	flies.scale_amount_max = 3.5
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 1.0, 0.5, 0.0))
	fade.set_color(1, Color(0.85, 1.0, 0.5, 0.0))
	fade.add_point(0.3, Color(0.9, 1.0, 0.55, 0.95))
	fade.add_point(0.7, Color(0.9, 1.0, 0.55, 0.95))
	flies.color_ramp = fade
	flies.z_index = 5
	add_child(flies)


## Q1: a navigation mesh over the map that leaves out trees and rocks (the
## "obstacles" group), so monsters walk around them instead of into them.
func _bake_navigation() -> void:
	var size: Vector2 = map_size()
	var left: float = EDGE_MARGINS[0]
	var top: float = EDGE_MARGINS[1]
	var right: float = size.x - EDGE_MARGINS[2]
	var bottom: float = size.y - EDGE_MARGINS[3]
	var polygon := NavigationPolygon.new()
	polygon.add_outline(
		PackedVector2Array(
			[Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)]
		)
	)
	polygon.agent_radius = NAV_AGENT_RADIUS
	polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	polygon.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	polygon.source_geometry_group_name = &"obstacles"
	var region := NavigationRegion2D.new()
	region.name = "Navigation"
	region.navigation_polygon = polygon
	add_child(region)
	region.bake_navigation_polygon(false)


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
