extends "res://tests/smoke_lake.gd"
## The Moonfall Ruins part of the smoke test: the roads from Galeclaw Ridge and
## Elder Grove, the ruined walls, statues that wake (Stone Gargoyle), the
## Mimic that sits like a chest, the Ruin Sentinel's beam and the sleeping
## Ruin Colossus. smoke_test.gd runs it; the helpers come from smoke_lake.gd.


func run(test, main, player, _hud) -> void:
	t = test
	await _check_ruin_roads(main, player)
	await _check_ruins(main)
	await _check_statue(main, player)
	await _check_mimic(main, player)
	await _check_beam(main, player)
	await _check_wall(main, player)
	main.change_map("town")
	await t._frames(3)


## Up again, whole: a bite from a Mimic can be the end of a weak hero.
func _heal(player) -> void:
	if player.is_dead:
		player.revive()
	super._heal(player)


## Every monster on the map, sleeping ones too (they are not "enemies").
func _all_monsters(main) -> Array:
	return main.map.get_children().filter(func(node): return node.get("monster_id") != null)


func _one(main, monster_id: String, point: Vector2):
	var all: Array = _all_monsters(main)
	t._freeze(all, true)
	var chosen = _nearest(all.filter(func(m): return m.monster_id == monster_id), point)
	t._freeze([chosen], false)
	return chosen


func _check_ruin_roads(main, player) -> void:
	for step in [["ridge", "south", "Galeclaw Ridge"], ["grove", "south", "Elder Grove"]]:
		main.change_map(step[0], step[1])
		await t._frames(30)
		var road = _portal_to("ruins")
		t._check(road != null, "%s has a road to Moonfall Ruins" % step[2])
		if road == null:
			continue
		_heal(player)
		player.global_position = road.global_position
		await t._frames(30)
		t._check(main.map.map_id == "ruins", "walking along it reaches the ruins")
	t._check(
		_portal_to("ridge") != null and _portal_to("grove") != null,
		"and the ruins have both roads back"
	)


func _check_ruins(main) -> void:
	main.change_map("ruins", "south")
	await t._frames(3)
	var monsters := {}
	for monster in _all_monsters(main):
		monsters[monster.monster_id] = int(monsters.get(monster.monster_id, 0)) + 1
	t._check(
		monsters == {"stone_gargoyle": 5, "mimic": 3, "ruin_sentinel": 4, "ruin_colossus": 1},
		"the ruins have their own monsters (%s)" % str(monsters)
	)
	var walls: Array = t.get_nodes_in_group("cliffs").filter(func(w): return w.style == "wall")
	t._check(walls.size() == 11, "old walls stand round the temple (%d)" % walls.size())
	var colossus = _nearest(
		_all_monsters(main).filter(func(m): return m.monster_id == "ruin_colossus"), Vector2.ZERO
	)
	t._check(
		colossus.is_in_group("bosses") and colossus.moves.dormant(),
		"the Ruin Colossus sleeps as a statue in the temple"
	)


func _check_statue(main, player) -> void:
	main.change_map("ruins", "south")
	await t._frames(3)
	var gargoyle = _one(main, "stone_gargoyle", Vector2(420, 840))
	_heal(player)
	player.global_position = gargoyle.global_position + Vector2(250, 0)
	var home: Vector2 = gargoyle.global_position
	await t._frames(10)
	t._check(
		(
			gargoyle.moves.dormant()
			and not gargoyle.is_in_group("enemies")
			and not gargoyle.get_node("HpBar").visible
			and gargoyle.global_position.distance_to(home) < 1.0
		),
		"a Stone Gargoyle stands still as a statue: no health bar, nothing aims at it"
	)
	player.global_position = gargoyle.global_position + Vector2(120, 0)
	await t._frames(3)
	var marks: Array = t.get_nodes_in_group("telegraphs").filter(
		func(mark): return is_equal_approx(float(mark.get("radius")), 120.0)
	)
	t._check(
		not gargoyle.moves.dormant() and gargoyle.is_in_group("enemies") and marks.size() == 1,
		"when the hero comes close it wakes with a blow all round it"
	)
	await t._frames(45)
	t._check(player.hp < player.max_hp, "and the blow hits him (%d HP)" % player.hp)
	var other = _one(main, "stone_gargoyle", Vector2(2000, 640))
	other.take_damage(10)
	t._check(not other.moves.dormant(), "hitting a statue wakes it too")


func _check_mimic(main, player) -> void:
	main.change_map("ruins", "south")
	await t._frames(3)
	var mimic = _one(main, "mimic", Vector2(620, 240))
	_heal(player)
	t._check(
		mimic.moves.dormant() and mimic.get_node("Sprite").animation == "sleep",
		"a Mimic sits shut like a treasure chest"
	)
	player.global_position = mimic.global_position + Vector2(60, 0)
	await t._frames(45)
	t._check(
		not mimic.moves.dormant() and player.hp < player.max_hp,
		"walk up to it and it gapes open and bites (%d HP)" % player.hp
	)


func _check_beam(main, player) -> void:
	main.change_map("ruins", "south")
	await t._frames(3)
	var sentinel = _one(main, "ruin_sentinel", Vector2(2150, 1100))
	sentinel.moves.set("_ready_in", 0.0)
	_heal(player)
	player.global_position = sentinel.global_position + Vector2(0, -300)
	await t._frames(3)
	var lanes: Array = t.get_nodes_in_group("telegraphs").filter(
		func(mark): return is_equal_approx(float(mark.get("length")), 480.0)
	)
	t._check(lanes.size() == 1, "a Ruin Sentinel lights a lane toward the hero")
	await t._frames(60)
	t._check(player.hp < player.max_hp, "then its beam fires along it (%d HP)" % player.hp)


func _check_wall(main, player) -> void:
	main.change_map("ruins", "south")
	await t._frames(3)
	t._freeze(_all_monsters(main), true)
	_heal(player)
	player.global_position = Vector2(1500, 1300)
	await t._frames(2)
	await t._hold("move_up", 60)
	t._check(
		player.global_position.y > 1200.0 and player.global_position.y < 1290.0,
		"the old temple wall stops him (y %d)" % player.global_position.y
	)
