extends "res://tests/smoke_ruins.gd"
## The Frostfang Hollow part of the smoke test: the road north from Moonfall
## Ruins, the frozen pond (ice to walk on), ice cliffs and falling snow, the
## icicle gorge, a Snow Wolf's pounce, the Frost Wyrm and the Frostfang set. smoke_test.gd runs
## it; the helpers come from smoke_ruins.gd and smoke_lake.gd.


func run(test, main, player, _hud) -> void:
	t = test
	await _check_frost_road(main, player)
	await _check_hollow(main)
	await _check_pond(main, player)
	await _check_icefall(main, player)
	await _check_pounce(main, player)
	await _check_frost_set(main, player)
	main.change_map("town")
	await t._frames(3)


func _check_frost_road(main, player) -> void:
	main.change_map("ruins", "south")
	await t._frames(30)
	var road = _portal_to("frostfang")
	t._check(road != null, "Moonfall Ruins has a road north, to Frostfang Hollow")
	if road == null:
		return
	_heal(player)
	player.global_position = road.global_position
	await t._frames(30)
	t._check(main.map.map_id == "frostfang", "walking along it reaches the hollow")
	t._check(_portal_to("ruins") != null, "and the hollow has the road back")


func _check_hollow(main) -> void:
	main.change_map("frostfang", "south")
	await t._frames(3)
	var monsters := {}
	for monster in _all_monsters(main):
		monsters[monster.monster_id] = int(monsters.get(monster.monster_id, 0)) + 1
	t._check(
		monsters == {"snow_wolf": 9, "frost_wraith": 4, "ice_golem": 3, "frost_wyrm": 1},
		"the hollow has its own monsters (%s)" % str(monsters)
	)
	var cliffs: Array = t.get_nodes_in_group("cliffs").filter(func(c): return c.style == "ice")
	t._check(
		(
			_water() != null
			and _water().style == "frozen"
			and cliffs.size() == 4
			and t.get_nodes_in_group("icefalls").size() == 1
			and main.map.get_node_or_null("Snowfall") is CPUParticles2D
		),
		"a frozen pond, ice cliffs, an icicle gorge and falling snow"
	)
	var wyrm = _nearest(
		_all_monsters(main).filter(func(m): return m.monster_id == "frost_wyrm"), Vector2.ZERO
	)
	t._check(
		wyrm.is_in_group("bosses") and wyrm.level == 23, "the Frost Wyrm is the hollow's boss"
	)


func _check_pond(main, player) -> void:
	main.change_map("frostfang", "south")
	await t._frames(3)
	t._freeze(_all_monsters(main), true)
	_heal(player)
	player.global_position = Vector2(1300, 1240)
	await t._frames(2)
	await t._hold("move_up", 60)
	t._check(
		player.global_position.y < 1100.0,
		"the frozen pond is ice: the hero walks out onto it (y %d)" % player.global_position.y
	)


func _check_icefall(main, player) -> void:
	main.change_map("frostfang", "south")
	await t._frames(3)
	t._freeze(_all_monsters(main), true)
	_heal(player)
	player.global_position = Vector2(1920, 800)  # in the gorge, under the icicles
	var mark = null
	for i in 90:
		await t._frames(1)
		for circle in t.get_nodes_in_group("telegraphs"):
			if is_equal_approx(float(circle.get("radius")), 62.0):
				mark = circle
		if mark != null:
			break
	t._check(
		mark != null and mark.global_position.distance_to(player.global_position) < 80.0,
		"in the gorge an icicle's circle appears by the hero"
	)
	await t._frames(60)
	t._check(
		player.hp < player.max_hp and player.statuses.is_active("slow"),
		"it falls and shatters on him, and the cold slows him (%d HP)" % player.hp
	)


func _check_pounce(main, player) -> void:
	main.change_map("frostfang", "south")
	await t._frames(3)
	var wolf = _one(main, "snow_wolf", Vector2(380, 860))
	wolf.set("_move_ready_in", 0.0)
	_heal(player)
	player.global_position = wolf.global_position + Vector2(200, 0)
	await t._frames(4)
	var lanes: Array = t.get_nodes_in_group("telegraphs").filter(
		func(mark): return float(mark.get("length")) > 0.0
	)
	t._check(lanes.size() == 1, "a Snow Wolf crouches and marks its pounce")
	await t._frames(60)
	t._check(player.hp < player.max_hp, "then it leaps on the hero (%d HP)" % player.hp)


func _check_frost_set(main, player) -> void:
	t._check(
		ItemDb.set_size("frostfang") == 12 and ItemDb.set_size("frostfang", "warrior") == 6,
		"the Frostfang set has 12 pieces, 6 that each class can wear"
	)
	t._check(
		"frostfang_blade" in ItemDb.drop_pool(23) and not "frostfang_blade" in ItemDb.drop_pool(19),
		"Frostfang gear drops from the hollow's strongest monsters, not yet from the wolves"
	)
	main.change_map("frostfang", "south")
	await t._frames(3)
	var wyrm = _one(main, "frost_wyrm", Vector2(1920, 170))
	wyrm.set_physics_process(false)
	_heal(player)
	player.global_position = wyrm.global_position + Vector2(-700, 700)  # out of the loot's reach
	wyrm.set("_player", player)
	var before: Array = t.get_nodes_in_group("pickups")
	wyrm.call("_maybe_drop_gear")
	await t._frames(2)
	var dropped: Array = t.get_nodes_in_group("pickups").filter(
		func(p): return not p in before and not p.get("stack").is_empty()
	)
	t._check(
		(
			dropped.size() == 3
			and dropped.all(func(p): return str(p.get("stack")["id"]).begins_with("frostfang_"))
		),
		"the Frost Wyrm drops three Frostfang pieces (%d)" % dropped.size()
	)
