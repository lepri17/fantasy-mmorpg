extends RefCounted
## The deep forest part of the smoke test: the north gate of Mossy Woods,
## Twilight Woods and Elder Grove (each darker, with its own monsters), and
## the new monster moves: the Bramble Boar's charge, the Lantern Wisp's blink
## and the Rootling's dig. smoke_test.gd runs it last; t is the test (a SceneTree).

const GameScript = preload("res://scripts/game.gd")
const Glowcap = preload("res://scripts/world/glowcap.gd")

var t = null


func run(test, main, player, _hud) -> void:
	t = test
	await _check_gates(main, player)
	await _check_maps(main)
	await _check_charge(main, player)
	await _check_blink(main, player)
	await _check_dig(main, player)
	await _check_old_maps(main, player)
	main.change_map("town")
	await t._frames(3)


func _check_gates(main, player) -> void:
	main.change_map("forest", "west")
	await t._frames(30)
	for step in [["lanternhold", "Mossy Woods has a road north, into the town of Lanternhold"],
			["twilight", "Lanternhold's road goes on into Twilight Woods"],
			["grove", "Twilight Woods has a gate north, into Elder Grove"]]:
		var gate = _portal_to(step[0])
		t._check(gate != null, step[1])
		if gate == null:
			return
		_heal(player)
		player.global_position = gate.global_position
		await t._frames(30)  # the new map's portals work after a moment (portal.gd)
		t._check(main.map.map_id == step[0], "walking into it goes deeper (%s)" % main.map.map_id)
	t._check(_portal_to("twilight") != null, "and Elder Grove has the way back")


func _check_maps(main) -> void:
	var sky_before: float = GameScript.sky_seconds
	GameScript.sky_seconds = 60.0  # broad day, no rain
	var light := {}
	for map_id in ["forest", "twilight", "grove"]:
		main.change_map(map_id, "south" if map_id != "forest" else "north")
		await t._frames(3)
		main.update_sky()
		light[map_id] = main.get("_daylight").color.v
		if map_id == "forest":
			continue
		var monsters := {}
		for enemy in main.map.get_children().filter(func(n): return n.get("monster_id") != null):
			monsters[enemy.monster_id] = int(monsters.get(enemy.monster_id, 0)) + 1
		var glowcaps: int = main.map.get_children().filter(func(n): return n is Glowcap).size()
		var tinted: int = t.get_nodes_in_group("trees").filter(
			func(tree): return tree.modulate != Color.WHITE
		).size()
		t._check(
			(
				main.map.get_node("Fireflies") is CPUParticles2D
				and glowcaps >= 8
				and tinted >= 30
			),
			"%s has dark trees, glowing mushrooms and fireflies" % main.map.display_name()
		)
		t._check(
			monsters == ({"bramble_boar": 5, "lantern_wisp": 5, "dusk_imp": 3} if map_id == "twilight" else {
				"rootling": 5, "moss_golem": 4
			}),
			"%s has its own monsters (%s)" % [main.map.display_name(), str(monsters)]
		)
	GameScript.sky_seconds = sky_before
	t._check(
		light["grove"] < light["twilight"] and light["twilight"] < light["forest"],
		"each map deeper in is darker (%.2f, %.2f, %.2f)" % [
			light["forest"], light["twilight"], light["grove"]
		]
	)
	var visitors: Array = main.bosses.bosses.keys().filter(
		func(id): return "grove" in main.bosses.maps_of(id) or "twilight" in main.bosses.maps_of(id)
	)
	t._check(visitors.is_empty(), "no boss comes to the deep woods: they are no boss's land")
	var blend = main.map.get_node_or_null("GroundBlend")
	var bands: int = blend.bands if blend != null else 0
	t._check(
		bands > 10 and main.map.get_node_or_null("Leaves") is CPUParticles2D,
		"the grove's ground has soft, wavy borders (%d), and leaves drift down" % bands
	)


func _check_charge(main, player) -> void:
	main.change_map("twilight", "south")
	await t._frames(3)
	var boar = _alone("bramble_boar")
	_heal(player)
	player.global_position = boar.global_position + Vector2(200, 0)
	await t._frames(6)
	var lanes: Array = t.get_nodes_in_group("telegraphs").filter(
		func(mark): return float(mark.get("length")) > 0.0
	)
	t._check(lanes.size() == 1, "the Bramble Boar marks a lane on the ground before it charges")
	var hp_before: int = player.hp
	var start: Vector2 = boar.global_position
	await t._frames(100)
	t._check(
		player.hp < hp_before and boar.global_position.distance_to(start) > 150.0,
		"then it rushes along the lane and hits the hero (%d -> %d HP)" % [hp_before, player.hp]
	)


func _check_blink(main, player) -> void:
	main.change_map("twilight", "south")
	await t._frames(3)
	var wisp = _alone("lantern_wisp")
	_heal(player)
	player.global_position = wisp.global_position + Vector2(60, 0)
	await t._frames(40)
	var gap: float = wisp.global_position.distance_to(player.global_position)
	t._check(
		gap > 140.0, "the Lantern Wisp blinks away when the hero comes close (%d px)" % gap
	)


func _check_dig(main, player) -> void:
	main.change_map("grove", "south")
	await t._frames(3)
	var rootling = _alone("rootling")
	_heal(player)
	player.global_position = rootling.global_position + Vector2(220, 0)
	await t._frames(6)
	t._check(
		rootling.burrowed and not rootling.is_in_group("enemies"),
		"the Rootling digs in: it cannot be seen or hit under the ground"
	)
	var hp_before: int = player.hp
	await t._frames(170)
	t._check(
		(
			not rootling.burrowed
			and rootling.global_position.distance_to(player.global_position) < 90.0
			and player.hp < hp_before
		),
		"it bursts out next to the hero and hits him (%d -> %d HP)" % [hp_before, player.hp]
	)


## The older woods, livened up: a pond, a chest and a shrine in each, new
## monsters (a slime that splits, a beetle that rolls, a mushroom that lies in
## wait, an imp that throws rocks), and Moss Golems that sleep like boulders.
func _check_old_maps(main, player) -> void:
	for map_id in ["forest", "twilight", "grove"]:
		main.change_map(map_id, "south" if map_id != "forest" else "north")
		await t._frames(3)
		var ponds: int = main.map.get_children().filter(func(n): return n.get("islands") != null).size()
		t._check(
			(
				ponds == 1
				and t.get_nodes_in_group("chests").size() == 1
				and t.get_nodes_in_group("shrines").size() == 1
			),
			"%s has a pond, a treasure chest and a shrine" % main.map.display_name()
		)
	main.change_map("forest", "north")
	await t._frames(3)
	var all: Array = main.map.get_children().filter(func(n): return n.get("monster_id") != null)
	var counts := {}
	for monster in all:
		counts[monster.monster_id] = int(counts.get(monster.monster_id, 0)) + 1
	t._check(
		[counts.get("twin_slime"), counts.get("mossback_beetle"), counts.get("puffcap")] == [2, 3, 3],
		"Mossy Woods has new monsters (%s)" % str(counts)
	)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var beetle = _monster("mossback_beetle")
	t._check(
		beetle != null and not beetle.moves.get("roll").is_empty(),
		"a Mossback Beetle can curl up and roll"
	)
	var twin = _monster("twin_slime")
	var spot: Vector2 = twin.global_position
	twin.take_damage(99999, Vector2.ZERO, false, player)
	await t._frames(3)
	var halves: Array = t.get_nodes_in_group("enemies").filter(
		func(e): return e.monster_id == "blue_slime" and e.get("respawns") == false
	)
	halves = halves.filter(func(e): return e.global_position.distance_to(spot) < 140.0)
	t._check(halves.size() == 2, "a Twin Slime splits into two blue slimes (%d)" % halves.size())
	var puff = all.filter(func(m): return m.monster_id == "puffcap")[0]
	t._check(
		puff.moves.dormant() and not puff.is_in_group("enemies"),
		"a Puffcap lies in wait, looking like a mushroom"
	)
	_heal(player)
	player.global_position = puff.global_position + Vector2(70, 0)
	await t._frames(6)
	t._check(not puff.moves.dormant(), "the Puffcap wakes when the hero comes close")
	main.change_map("twilight", "south")
	await t._frames(3)
	var imp = _monster("dusk_imp")
	t._check(
		imp != null and not imp.moves.get("lob").is_empty(), "Dusk Imps throw rocks in Twilight Woods"
	)
	main.change_map("grove", "south")
	await t._frames(3)
	var golems: Array = main.map.get_children().filter(
		func(n): return n.get("monster_id") == "moss_golem"
	)
	t._check(
		golems.size() == 4 and golems.all(func(g): return g.moves.dormant()),
		"Moss Golems sleep like mossy boulders until someone comes near"
	)


## The only monster of that kind left free to move: the others stand still.
func _alone(monster_id: String):
	var enemies: Array = t.get_nodes_in_group("enemies")
	t._freeze(enemies, true)
	var chosen = _monster(monster_id)
	t._freeze([chosen], false)
	return chosen


func _monster(monster_id: String):
	for enemy in t.get_nodes_in_group("enemies"):
		if enemy.monster_id == monster_id:
			return enemy
	return null


func _portal_to(map_id: String):
	for portal in t.get_nodes_in_group("portals"):
		if portal.get("to_map") == map_id:
			return portal
	return null


func _heal(player) -> void:
	player.hp = player.max_hp
	player.set("_invincible_left", 0.0)
