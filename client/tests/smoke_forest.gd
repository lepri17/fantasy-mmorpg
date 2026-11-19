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
	main.change_map("town")
	await t._frames(3)


func _check_gates(main, player) -> void:
	main.change_map("forest", "west")
	await t._frames(30)
	for step in [["twilight", "Mossy Woods has a gate north, into Twilight Woods"],
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
		for enemy in t.get_nodes_in_group("enemies"):
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
			monsters == ({"bramble_boar": 5, "lantern_wisp": 5} if map_id == "twilight" else {
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
	main.bosses.appear("stormcrest_roc", "grove")
	var roc = main.bosses.node_of("stormcrest_roc")
	t._check(
		roc != null and roc.is_in_group("bosses") and roc.get("_crown") == null and roc.level == 17,
		"the Stormcrest Roc can come down in the grove, without the Slime King's crown"
	)
	main.bosses.leave("stormcrest_roc")


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
