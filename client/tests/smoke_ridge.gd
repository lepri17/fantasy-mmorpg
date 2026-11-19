extends "res://tests/smoke_lake.gd"
## The Galeclaw Ridge part of the smoke test: the road east from Twilight
## Woods, the rift (it stops the hero, its rope bridges cross it) and the
## cliffs, the Rock Beetle's bouncing roll, the Crag Imp's thrown rock, the
## Gale Harpy's swoop and the Stormcrest Roc.
## smoke_test.gd runs it; the helpers come from smoke_lake.gd.


func run(test, main, player, _hud) -> void:
	t = test
	await _check_ridge_road(main, player)
	await _check_ridge(main)
	await _check_rift(main, player)
	await _check_cliff(main, player)
	await _check_roll(main, player)
	await _check_bounce(main, player)
	await _check_lob(main, player)
	await _check_swoop(main, player)
	main.change_map("town")
	await t._frames(3)


func _check_ridge_road(main, player) -> void:
	main.change_map("twilight", "south")
	await t._frames(30)
	var road = _portal_to("ridge")
	t._check(road != null, "Twilight Woods has a road east, to Galeclaw Ridge")
	if road == null:
		return
	_heal(player)
	player.global_position = road.global_position
	await t._frames(30)
	t._check(
		main.map.map_id == "ridge" and player.global_position.x < 400.0,
		"walking along it reaches the west end of the ridge (%s)" % main.map.map_id
	)
	t._check(_portal_to("twilight") != null, "and the ridge has the road back")


func _check_ridge(main) -> void:
	main.change_map("ridge", "west")
	await t._frames(3)
	var monsters := {}
	for enemy in t.get_nodes_in_group("enemies"):
		monsters[enemy.monster_id] = int(monsters.get(enemy.monster_id, 0)) + 1
	t._check(
		monsters == {"rock_beetle": 6, "crag_imp": 5, "gale_harpy": 4},
		"the ridge has its own monsters (%s)" % str(monsters)
	)
	var rift = _water()
	t._check(
		rift != null and rift.style == "chasm" and rift.bridges.size() == 2,
		"a rift splits the ridge, with two rope bridges"
	)
	t._check(
		t.get_nodes_in_group("cliffs").size() == 5 and t.get_nodes_in_group("chests").size() == 2,
		"five cliffs, and two treasure chests to find"
	)
	main.bosses.appear("stormcrest_roc", "ridge")
	var roc = main.bosses.node_of("stormcrest_roc")
	t._check(
		roc != null and roc.is_in_group("bosses") and roc.level == 17,
		"the Stormcrest Roc can come to the ridge"
	)
	main.bosses.leave("stormcrest_roc")


func _check_rift(main, player) -> void:
	main.change_map("ridge", "west")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var rift = _water()
	_heal(player)
	player.global_position = Vector2(1050, 700)
	await t._frames(2)
	await t._hold("move_right", 80)
	t._check(
		not rift.is_wet(player.global_position) and player.global_position.x < 1285.0,
		"the rift stops the hero at its edge (x %d)" % player.global_position.x
	)
	player.global_position = Vector2(1180, 480)  # the west end of the north bridge
	await t._frames(2)
	await t._hold("move_right", 100)
	t._check(
		player.global_position.x > 1490.0,
		"the rope bridge carries him across (x %d)" % player.global_position.x
	)


func _check_cliff(main, player) -> void:
	main.change_map("ridge", "west")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	_heal(player)
	player.global_position = Vector2(450, 760)
	await t._frames(2)
	await t._hold("move_up", 80)
	var cliff = _nearest(t.get_nodes_in_group("cliffs"), Vector2(560, 330))
	t._check(
		player.global_position.y > 540.0 and not cliff.is_solid(player.global_position),
		"a cliff's rock face stops him (y %d)" % player.global_position.y
	)


func _check_roll(main, player) -> void:
	main.change_map("ridge", "west")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var beetle = _monster_near("rock_beetle", Vector2(820, 1060))
	t._freeze([beetle], false)
	beetle.moves.set("_ready_in", 0.0)
	_heal(player)
	player.global_position = beetle.global_position + Vector2(200, 0)
	await t._frames(3)
	t._check(beetle.moves.rolling(), "the Rock Beetle curls up and rolls at the hero")
	var hp_before: int = beetle.hp
	beetle.take_damage(100)
	t._check(
		hp_before - beetle.hp == 40,
		"rolled up, it takes less damage (%d of 100)" % (hp_before - beetle.hp)
	)
	await t._frames(60)
	t._check(player.hp < player.max_hp, "and it bowls into him (%d HP)" % player.hp)


func _check_bounce(main, player) -> void:
	main.change_map("ridge", "west")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var beetle = _monster_near("rock_beetle", Vector2(820, 1060))
	beetle.global_position = Vector2(1150, 700)  # the rift is just east of it
	beetle.set("_spawn_position", beetle.global_position)  # its home, so it stays to fight
	t._freeze([beetle], false)
	beetle.moves.set("_ready_in", 0.0)
	_heal(player)
	player.global_position = Vector2(1450, 700)  # across the rift
	var furthest: float = 0.0
	for i in 70:
		await t._frames(1)
		furthest = maxf(furthest, beetle.global_position.x)
	t._check(
		furthest < 1285.0 and Vector2(beetle.moves.get("_roll_dir")).x < 0.0,
		"it bounces back off the rift's edge instead of rolling in (x %d)" % furthest
	)


func _check_lob(main, player) -> void:
	main.change_map("ridge", "west")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var imp = _monster_near("crag_imp", Vector2(980, 640))
	t._freeze([imp], false)
	imp.moves.set("_ready_in", 0.0)
	_heal(player)
	player.global_position = imp.global_position + Vector2(0, 280)
	var spot: Vector2 = player.global_position
	await t._frames(3)
	var marks: Array = t.get_nodes_in_group("telegraphs").filter(
		func(mark): return mark.global_position.distance_to(spot) < 30.0
	)
	t._check(
		marks.size() == 1 and is_equal_approx(float(marks[0].get("radius")), 85.0),
		"the Crag Imp marks the hero's spot and heaves a rock at it"
	)
	await t._frames(80)
	t._check(player.hp < player.max_hp, "the rock comes down on him (%d HP)" % player.hp)


func _check_swoop(main, player) -> void:
	main.change_map("ridge", "west")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var harpy = _monster_near("gale_harpy", Vector2(700, 1010))
	t._freeze([harpy], false)
	harpy.moves.set("_ready_in", 0.0)
	_heal(player)
	player.global_position = harpy.global_position + Vector2(250, 0)
	var spot: Vector2 = player.global_position
	await t._frames(3)
	t._check(
		harpy.moves.in_sky() and not harpy.is_in_group("enemies"),
		"the Gale Harpy flies up out of reach"
	)
	var mark = null
	for i in 150:
		await t._frames(1)
		for circle in t.get_nodes_in_group("telegraphs"):
			if is_equal_approx(float(circle.get("radius")), 80.0):
				mark = circle
		if mark != null:
			break
	t._check(
		mark != null and mark.global_position.distance_to(spot) < 40.0,
		"it glides over the hero and marks a circle under itself"
	)
	await t._frames(70)
	t._check(
		not harpy.moves.in_sky() and harpy.is_in_group("enemies") and player.hp < player.max_hp,
		"then it dives onto him and is back in reach (%d HP)" % player.hp
	)
