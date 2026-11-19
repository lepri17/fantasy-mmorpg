extends RefCounted
## Towns (Mor's wish, 2026-11-19): Willow Town as a street, and the new towns
## Lanternhold (between Mossy Woods and Twilight Woods) and Frostgate (between
## Moonfall Ruins and Frostfang Hollow). Houses stand along the top and the
## people stand at their doors along the street, so the hero walks left and
## right to reach them; behind each new town's hall is an arena. smoke_test.gd
## runs it; t is the test (a SceneTree).

const GameData = preload("res://scripts/data/game_data.gd")

var t = null


func run(test, main, player, hud) -> void:
	t = test
	await _check_street(main, player)
	await _check_new_towns(main, player)
	await _check_teleports(main, player, hud)
	await _check_arena(main, player)
	main.change_map("town")
	await t._frames(3)


func _check_street(main, player) -> void:
	main.change_map("town", "default")
	await t._frames(5)
	var size: Vector2 = main.map.map_size()
	var houses: Array = t.get_nodes_in_group("houses")
	var people: Array = t.get_nodes_in_group("npcs")
	var xs: Array = people.map(func(npc): return npc.global_position.x)
	t._check(
		size.x > 3000.0 and size.y <= 768.0 and houses.size() == 9,
		"Willow Town is a long street with a row of houses (%d x %d)" % [size.x, size.y]
	)
	t._check(
		xs.max() - xs.min() > 2000.0,
		"its people stand along the street, not in one clump (%d px)" % (xs.max() - xs.min())
	)
	t._check(
		people.all(
			func(npc): return houses.any(
				func(house): return absf(house.global_position.x - npc.global_position.x) < 30.0
			)
		),
		"each of them stands at the door of their own house"
	)
	t._check(
		main.map.find_children("*", "PointLight2D", true, false).is_empty(),
		"the street lamps paint their glow, with no real lights to slow a phone"
	)
	_heal(player)
	player.global_position = Vector2(1700, 560)
	await t._frames(2)
	await t._hold("move_up", 120)
	t._check(
		player.global_position.y > 290.0,
		"the hero cannot walk up past the houses (y %d)" % player.global_position.y
	)
	var before: float = player.global_position.x
	await t._hold("move_right", 40)
	t._check(player.global_position.x > before + 80.0, "but walks along the street")


func _check_new_towns(main, player) -> void:
	for step in [
		["forest", "lanternhold", "twilight", "Lanternhold", "lantern_arena"],
		["ruins", "frostgate", "frostfang", "Frostgate", "frost_arena"]
	]:
		main.change_map(step[0], "south")
		await t._frames(30)
		var road = _portal_to(step[1])
		t._check(road != null, "%s has a road to %s" % [main.map.display_name(), step[3]])
		if road == null:
			continue
		_heal(player)
		player.global_position = road.global_position
		await t._frames(30)
		t._check(main.map.map_id == step[1], "the road leads into the town of %s" % step[3])
		var services: Array = []
		for npc in t.get_nodes_in_group("npcs"):
			services.append_array(GameData.table("npcs")[npc.npc_id].get("services", []))
		t._check(
			["shop", "heal", "storage", "teleport"].all(func(service): return service in services),
			"%s has a shop, a healer, storage and a guide" % step[3]
		)
		t._check(
			(
				_portal_to(step[0]) != null
				and _portal_to(step[2]) != null
				and _portal_to(step[4]) != null
			),
			"and roads back and on, and a door into its arena"
		)
		t._check(
			t.get_nodes_in_group("enemies").is_empty() and t.get_nodes_in_group("houses").size() == 7,
			"no monsters in %s, and seven houses" % step[3]
		)


func _check_teleports(main, player, hud) -> void:
	main.change_map("lanternhold", "default")
	await t._frames(5)
	var guide = t.get_nodes_in_group("npcs").filter(func(npc): return npc.npc_id == "lh_guide")[0]
	player.global_position = guide.global_position + Vector2(40, 50)
	await t._frames(5)
	hud.talk()
	await t._frames(3)
	var dialog = hud.get_node("NpcDialog")
	t._check(
		(
			dialog.option("Go to Willow Town") != null
			and dialog.option("Go to Lanternhold") == null
			and dialog.option("Go to Lantern Arena") == null
		),
		"Lanternhold's guide sends you to Willow Town, but not here or into an arena"
	)
	hud.call("_close_windows")
	await t._frames(2)


func _check_arena(main, player) -> void:
	main.change_map("lanternhold", "default")
	await t._frames(30)
	var door = _portal_to("lantern_arena")
	_heal(player)
	player.global_position = door.global_position
	await t._frames(30)
	t._check(main.map.map_id == "lantern_arena", "the hall's door leads into the Lantern Arena")
	for i in 300:  # the first wave comes after a short wait (dungeon_run.gd wave_delay)
		await t._frames(1)
		if not t.get_nodes_in_group("enemies").is_empty():
			break
	t._check(
		main.map.get_node_or_null("DungeonRun") != null
		and not t.get_nodes_in_group("enemies").is_empty(),
		"the first wave comes out to fight"
	)


func _portal_to(map_id: String):
	for portal in t.get_nodes_in_group("portals"):
		if portal.get("to_map") == map_id:
			return portal
	return null


func _heal(player) -> void:
	player.hp = player.max_hp
	player.set("_invincible_left", 0.0)
