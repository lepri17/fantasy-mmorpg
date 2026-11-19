extends RefCounted
## Roaming bosses (roaming_bosses.gd): three bosses, one for every few maps,
## and none of them is always there. A boss waits minutes, appears in one of
## its maps, leaves after a while unless someone is fighting it, and is there
## when the hero walks into its map. smoke_test.gd runs it; t is the test.

const RoamingBosses = preload("res://scripts/world/roaming_bosses.gd")
const GameData = preload("res://scripts/data/game_data.gd")

var t = null


func run(test, main, player, _hud) -> void:
	t = test
	_check_few(main.bosses)
	await _check_clock(main, main.bosses)
	await _check_walk_in(main, main.bosses)
	await _check_fight(main, player, main.bosses)
	main.change_map("town")
	await t._frames(3)


func _check_few(roaming) -> void:
	var ids: Array = roaming.bosses.keys()
	ids.sort()
	t._check(
		ids == ["frost_wyrm", "slime_king", "stormcrest_roc"],
		"three roaming bosses, one for every few maps (%s)" % str(ids)
	)
	var placed: Array = []
	var maps: Dictionary = GameData.table("maps")["maps"]
	var monsters: Dictionary = GameData.table("monsters")
	for map_id in maps:
		for thing in maps[map_id].get("objects", []):
			if thing.get("type") == "monster" and monsters[thing["id"]].has("boss"):
				placed.append(thing["id"])
	t._check(placed.is_empty(), "no map keeps a boss there all the time (%s)" % str(placed))
	t._check(
		roaming.bosses.values().all(func(state): return float(state["wait"]) >= 60.0),
		"each boss waits minutes before it comes"
	)


func _check_clock(main, roaming) -> void:
	main.change_map("forest", "west")
	await t._frames(3)
	RoamingBosses.enabled = true
	roaming.bosses["slime_king"]["wait"] = 0.05
	await t._frames(5)
	RoamingBosses.enabled = false
	var state: Dictionary = roaming.bosses["slime_king"]
	t._check(
		roaming.is_out("slime_king") and state["map"] in ["field", "forest", "lake"],
		"when its wait is over, the Slime King appears in one of its maps (%s)" % state["map"]
	)
	state["left"] = 0.01  # its time is up, and no one is fighting it
	await t._frames(3)
	t._check(
		not roaming.is_out("slime_king") and float(state["wait"]) >= 400.0,
		"after a while it leaves, and stays away for minutes (%d s)" % state["wait"]
	)


func _check_walk_in(main, roaming) -> void:
	main.change_map("town")
	await t._frames(3)
	roaming.appear("stormcrest_roc", "twilight")
	t._check(
		roaming.is_out("stormcrest_roc") and roaming.node_of("stormcrest_roc") == null,
		"a boss can come out in another map, away from the hero"
	)
	main.change_map("twilight", "south")
	await t._frames(3)
	var roc = roaming.node_of("stormcrest_roc")
	t._check(
		(
			roc != null
			and roc.is_in_group("bosses")
			and RoamingBosses.spots("twilight").any(
				func(spot): return spot.distance_to(roc.global_position) < 40.0
			)
		),
		"walking into its map, the hero finds it at one of the boss spots"
	)
	roaming.leave("stormcrest_roc")
	await t._frames(2)
	t._check(
		t.get_nodes_in_group("bosses").is_empty() and not roaming.is_out("stormcrest_roc"),
		"then it leaves the map"
	)


func _check_fight(main, player, roaming) -> void:
	main.change_map("frostfang", "south")
	await t._frames(3)
	roaming.appear("frost_wyrm", "frostfang")
	var wyrm = roaming.node_of("frost_wyrm")
	t._check(wyrm != null and wyrm.level == 23, "the Frost Wyrm appears in Frostfang Hollow")
	if wyrm == null:
		return
	wyrm.set_physics_process(false)
	wyrm.take_damage(100, Vector2.ZERO, false, player)
	roaming.bosses["frost_wyrm"]["left"] = 0.01
	await t._frames(3)
	t._check(
		roaming.is_out("frost_wyrm") and roaming.node_of("frost_wyrm") == wyrm,
		"a boss in a fight does not run off when its time is up"
	)
	roaming.leave("frost_wyrm")
	await t._frames(2)
