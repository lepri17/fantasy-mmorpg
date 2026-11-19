extends Node2D
## One map. Its entry in res://data/maps.json (by map_id) gives its name,
## where the warrior arrives (spawns) and what stands on it (objects). Roads
## at its edges ("exit" objects) lead on into the next maps: the open world. A map
## with ground rows is built here: a TileMapLayer ground, edges and objects.
## A map with a scene of its own (the meadow) keeps its nodes and only gets
## the objects from the data (its portals).

const GameData := preload("res://scripts/data/game_data.gd")
const MapTiles := preload("res://scripts/maps/map_tiles.gd")
const GroundBlend := preload("res://scripts/maps/ground_blend.gd")
## Things drifting over a whole map (maps.json "leaves", "pollen", "dust": how
## many): colours to pick from, heading, speed, size and spin.
const DRIFTS := {
	"leaves": {
		"colors": [Color(0.55, 0.72, 0.28), Color(0.88, 0.6, 0.22), Color(0.72, 0.42, 0.18)],
		"heading": Vector2(0.45, 1.0),
		"speed": [28.0, 55.0],
		"size": [2.5, 4.5],
		"spin": 180.0
	},
	"pollen": {
		"colors": [Color(1.0, 0.96, 0.66), Color(1.0, 1.0, 1.0)],
		"heading": Vector2(1.0, -0.35),
		"speed": [8.0, 22.0],
		"size": [1.5, 2.6],
		"spin": 0.0
	},
	"dust": {
		"colors": [Color(0.88, 0.82, 0.7, 0.6), Color(0.74, 0.7, 0.62, 0.5)],
		"heading": Vector2(1.0, 0.12),
		"speed": [55.0, 100.0],
		"size": [1.5, 3.0],
		"spin": 0.0
	}
}
const DungeonRun := preload("res://scripts/maps/dungeon_run.gd")
const Torch := preload("res://scripts/world/torch.gd")
const Glowcap := preload("res://scripts/world/glowcap.gd")
const EdgeExit := preload("res://scripts/maps/edge_exit.gd")
const Water := preload("res://scripts/world/water.gd")
const Cliff := preload("res://scripts/world/cliff.gd")
const Icefall := preload("res://scripts/world/icefall.gd")
const House := preload("res://scripts/world/house.gd")
const Prop := preload("res://scripts/world/prop.gd")
const Decor := preload("res://scripts/world/decor.gd")
const Chest := preload("res://scripts/world/chest.gd")
const Shrine := preload("res://scripts/world/shrine.gd")
const AmbientLife := preload("res://scripts/world/ambient_life.gd")
## Every tree sways in the wind (one material, each tree in its own time).
const SWAY := preload("res://shaders/sway.gdshader")
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

static var _sway_material: ShaderMaterial = null

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
		var blend: Node2D = GroundBlend.new()
		blend.name = "GroundBlend"
		blend.setup(
			data["ground"], data.get("objects", []).filter(func(o): return o["type"] == "exit")
		)
		if DisplayServer.get_name() == "headless":
			add_child(blend)  # no screen to draw on (the smoke test reads it as it is)
		else:
			_bake(blend)
		_add_edges()
	for thing in data.get("objects", []):
		_add_object(thing)
	if int(data.get("fireflies", 0)) > 0:
		_add_fireflies(int(data["fireflies"]))
	if int(data.get("snowfall", 0)) > 0:
		_add_snowfall(int(data["snowfall"]))
	for drift in DRIFTS:
		if int(data.get(drift, 0)) > 0:
			_add_drift(drift, int(data[drift]))
	_dress_scenery()
	if data.has("life"):
		var life: Node2D = AmbientLife.new()
		life.name = "AmbientLife"
		life.setup(data["life"], bounds(), map_id)
		add_child(life)
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
	if thing["type"] == "water":
		_add_water(thing)
		return
	if thing["type"] == "house":
		var house = House.new()
		house.look = thing["look"]
		house.position = Vector2(thing["pos"][0], thing["pos"][1])
		add_child(house)
		return
	if thing["type"] == "prop":
		var prop = Prop.new()
		prop.look = thing["look"]
		var block: Array = thing.get("block", [0, 0])
		prop.block = Vector2(block[0], block[1])
		prop.npc_id = thing.get("npc", "")
		prop.position = Vector2(thing["pos"][0], thing["pos"][1])
		add_child(prop)
		return
	if thing["type"] == "icefall":
		var gorge = Icefall.new()
		var box: Array = thing["area"]
		gorge.area = Rect2(box[0], box[1], box[2], box[3])
		gorge.every = float(thing.get("every", 2.2))
		gorge.damage = int(thing.get("damage", 70))
		add_child(gorge)
		return
	if thing["type"] == "cliff":
		var cliff = Cliff.new()
		cliff.style = thing.get("style", "rock")
		cliff.points = _shape(thing["points"])
		add_child(cliff)
		return
	var node: Node2D
	match thing["type"]:
		"torch":
			node = Torch.new()
			node.set("lamp", not data.get("indoor", false))  # real light only in the dark cellar
		"glowcap":
			node = Glowcap.new()
			node.set("color_name", thing.get("color", "cyan"))
		"decor":
			node = Decor.new()
			node.set("kind", thing["kind"])
		"chest":
			node = Chest.new()
			node.set("level", int(thing["level"]))
		"shrine":
			node = Shrine.new()
			node.set("gift", thing.get("gift", "heal"))
		_:
			node = SCENES[thing["type"]].instantiate()
	node.position = Vector2(thing["pos"][0], thing["pos"][1])
	if thing["type"] in ["tree", "rock"]:
		# The deep forest: bigger, darker trees (maps.json "scale" and "tint").
		node.scale = Vector2.ONE * float(thing.get("scale", 1.0))
		var rgba: Array = thing.get("tint", [1, 1, 1, 1])
		# Each a little lighter or darker than the next, so no two look cloned.
		var shade: float = 0.92 + 0.12 * float(posmod(hash(node.position), 100)) / 100.0
		node.modulate = Color(rgba[0] * shade, rgba[1] * shade, rgba[2] * shade, rgba[3])
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


## A lake or a river, with its bridges (water.gd).
func _add_water(thing: Dictionary) -> void:
	var lake = Water.new()
	lake.style = thing.get("style", "water")
	lake.points = _shape(thing["points"])
	for box in thing.get("bridges", []):
		lake.bridges.append(Rect2(box[0], box[1], box[2], box[3]))
	for island in thing.get("islands", []):
		lake.islands.append(_shape(island))
	add_child(lake)


## maps.json points ([x, y] pairs) as a shape.
static func _shape(points: Array) -> PackedVector2Array:
	var shape := PackedVector2Array()
	for point in points:
		shape.append(Vector2(point[0], point[1]))
	return shape


## Snow drifting down over the whole map (maps.json "snowfall": how many flakes).
func _add_snowfall(count: int) -> void:
	var flakes := CPUParticles2D.new()
	flakes.name = "Snowfall"
	flakes.amount = count
	flakes.lifetime = 9.0
	flakes.preprocess = 9.0
	flakes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var size: Vector2 = map_size()
	flakes.position = Vector2(size.x * 0.5, -40.0)
	flakes.emission_rect_extents = Vector2(size.x * 0.6, 20.0)
	flakes.direction = Vector2(0.3, 1.0)
	flakes.spread = 15.0
	flakes.gravity = Vector2.ZERO
	flakes.initial_velocity_min = 120.0
	flakes.initial_velocity_max = 190.0
	flakes.scale_amount_min = 1.5
	flakes.scale_amount_max = 3.5
	flakes.color = Color(1, 1, 1, 0.85)
	flakes.z_index = 5
	add_child(flakes)


## The ground's soft borders and details (ground_blend.gd) are thousands of
## little shapes: drawn every frame they cost hundreds of draw calls, and the
## frame rate dropped, most of all in the long towns. They are drawn once into
## a picture instead (a SubViewport that renders one time), shown by a sprite.
func _bake(blend: Node2D) -> void:
	var viewport := SubViewport.new()
	viewport.name = "GroundBake"
	viewport.size = Vector2i(map_size())
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(blend)
	add_child(viewport)
	var picture := Sprite2D.new()
	picture.name = "GroundPicture"
	picture.texture = viewport.get_texture()
	picture.centered = false
	picture.z_index = -9  # just over the ground, as the shapes were
	# Shown at 1:1. Smooth filtering with the camera between pixels mixed in the
	# clear pixels beside each band: a faint line of road along every border.
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(picture)


## Gives each tree and rock a drawing of the map's kinds (maps.json
## "tree_style", "rock_style": names in assets/environment/trees and rocks),
## picked by its place, in one of two shapes. Also the meadow scene's trees.
func _dress_scenery() -> void:
	var styles := {
		"trees": data.get("tree_style", ["oak"]), "rocks": data.get("rock_style", ["stone"])
	}
	for node in find_children("*", "StaticBody2D", true, false):
		for group in styles:
			var sprite = node.get_node_or_null("Sprite")
			if not node.is_in_group(group) or sprite == null:
				continue
			var kinds: Array = styles[group]
			var pick: int = hash(Vector2i(node.position))
			sprite.texture = load(
				"res://assets/environment/%s/%s_%d.png"
				% [group, kinds[posmod(pick, kinds.size())], posmod(pick >> 4, 2)]
			)
			if group == "trees":
				if _sway_material == null:
					_sway_material = ShaderMaterial.new()
					_sway_material.shader = SWAY
				sprite.material = _sway_material


## Leaves, pollen or dust drifting over the whole map (DRIFTS), each bit
## fading in and out where it is, so the map looks alive everywhere.
func _add_drift(kind: String, count: int) -> void:
	var look: Dictionary = DRIFTS[kind]
	var bits := CPUParticles2D.new()
	bits.name = kind.capitalize()
	bits.amount = count
	bits.lifetime = 7.0
	bits.preprocess = 7.0
	bits.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var size: Vector2 = map_size()
	bits.position = size * 0.5
	bits.emission_rect_extents = size * 0.5
	bits.direction = look["heading"]
	bits.spread = 25.0
	bits.gravity = Vector2.ZERO
	bits.initial_velocity_min = look["speed"][0]
	bits.initial_velocity_max = look["speed"][1]
	bits.scale_amount_min = look["size"][0]
	bits.scale_amount_max = look["size"][1]
	bits.angular_velocity_min = -float(look["spin"])
	bits.angular_velocity_max = float(look["spin"])
	var colors: Array = look["colors"]
	var pick := Gradient.new()
	pick.offsets = PackedFloat32Array([0.0, 1.0] if colors.size() == 2 else [0.0, 0.5, 1.0])
	pick.colors = PackedColorArray(colors)
	bits.color_initial_ramp = pick
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray(
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]
	)
	bits.color_ramp = fade
	bits.z_index = 5
	add_child(bits)


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
		[Vector2.DOWN, float(data.get("street_top", EDGE_MARGINS[1]))],  # a town's street
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
