extends RefCounted
## The Sunpetal Lake part of the smoke test: the road south from Mossy Woods,
## water that blocks the way and bridges that cross it, the island's treasure
## chest, the two shrines, and the lake's monsters: the Bubble Slime bursts
## into small ones, the Snapjaw Turtle hides in its shell and snaps, the Marsh
## Frog leaps onto the hero. smoke_test.gd runs it; t is the test (a SceneTree).

var t = null


func run(test, main, player, _hud) -> void:
	t = test
	await _check_road(main, player)
	await _check_lake(main)
	await _check_water(main, player)
	await _check_chest(main, player)
	await _check_shrines(main, player)
	await _check_split(main, player)
	await _check_shell(main, player)
	await _check_leap(main, player)
	main.change_map("town")
	await t._frames(3)


func _check_road(main, player) -> void:
	main.change_map("forest", "west")
	await t._frames(30)
	var road = _portal_to("lake")
	t._check(road != null, "Mossy Woods has a road south, to Sunpetal Lake")
	if road == null:
		return
	_heal(player)
	player.global_position = road.global_position
	await t._frames(30)
	t._check(
		main.map.map_id == "lake" and player.global_position.y < 400.0,
		"walking down it reaches the lake's north shore (%s)" % main.map.map_id
	)
	t._check(_portal_to("forest") != null, "and the lake has the road back")


func _check_lake(main) -> void:
	main.change_map("lake", "north")
	await t._frames(3)
	var monsters := {}
	for enemy in t.get_nodes_in_group("enemies"):
		monsters[enemy.monster_id] = int(monsters.get(enemy.monster_id, 0)) + 1
	t._check(
		monsters == {
			"bubble_slime": 6, "snapjaw_turtle": 5, "marsh_frog": 5, "elder_snapjaw": 1
		},
		"the lake has its own monsters (%s)" % str(monsters)
	)
	var water = _water()
	t._check(
		water != null and water.bridges.size() == 3 and water.islands.size() == 1,
		"a lake and a river, with three bridges and an island"
	)
	var boss = _monster_near("elder_snapjaw", Vector2.ZERO)
	t._check(
		boss != null and boss.is_in_group("bosses") and boss.level == 11,
		"the Elder Snapjaw is the lake's boss"
	)
	t._check(
		t.get_nodes_in_group("chests").size() == 2 and t.get_nodes_in_group("shrines").size() == 2,
		"two treasure chests and two shrines to find"
	)


func _check_water(main, player) -> void:
	main.change_map("lake", "north")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var water = _water()
	_heal(player)
	player.global_position = Vector2(1800, 610)  # the river's north bank
	await t._frames(2)
	await t._hold("move_down", 50)
	t._check(
		not water.is_wet(player.global_position) and player.global_position.y < 700.0,
		"the river stops the hero at its bank (y %d)" % player.global_position.y
	)
	player.global_position = Vector2(2100, 610)  # the end of the east bridge
	await t._frames(2)
	await t._hold("move_down", 100)
	t._check(
		player.global_position.y > 910.0,
		"the bridge carries him over to the far bank (y %d)" % player.global_position.y
	)


func _check_chest(main, player) -> void:
	main.change_map("lake", "north")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var chest = _nearest(t.get_nodes_in_group("chests"), Vector2(690, 735))
	t._check(not chest.is_open, "the island's chest is shut")
	_heal(player)
	var gold_before: int = player.stats.gold
	player.global_position = Vector2(690, 300)  # the north end of the island bridge
	await t._frames(2)
	await t._hold("move_down", 120)
	await t._frames(60)  # the spilled gold flies to him
	t._check(
		chest.is_open and player.stats.gold > gold_before,
		"walking over the bridge to the island opens it: gold for him (%d -> %d)" % [
			gold_before, player.stats.gold
		]
	)
	chest.set("_refill_in", 0.05)
	await t._frames(10)
	t._check(not chest.is_open, "after a while it is full and shut again")


func _check_shrines(main, player) -> void:
	main.change_map("lake", "north")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var heal = _nearest(t.get_nodes_in_group("shrines"), Vector2(1560, 300))
	var power = _nearest(t.get_nodes_in_group("shrines"), Vector2(1800, 1060))
	_heal(player)
	player.hp = 10
	player.global_position = heal.global_position
	await t._frames(5)
	t._check(
		player.hp == player.max_hp and not heal.is_ready(),
		"the green shrine heals the hero, then rests"
	)
	player.global_position = power.global_position
	await t._frames(5)
	t._check(
		float(player.get("_damage_bonus")) > 0.2 and float(player.get("_damage_bonus_left")) > 50.0,
		"the orange shrine gives him more damage for a minute"
	)
	player.set("_damage_bonus", 0.0)
	player.set("_damage_bonus_left", 0.0)


func _check_split(main, player) -> void:
	main.change_map("lake", "north")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var bubble = _monster_near("bubble_slime", Vector2(2350, 480))
	_heal(player)
	player.global_position = Vector2(1280, 300)
	bubble.take_damage(bubble.hp + 10)
	await t._frames(4)
	var small: Array = t.get_nodes_in_group("enemies").filter(
		func(enemy): return enemy.monster_id == "bubblet"
	)
	t._check(
		(
			bubble.is_dead
			and small.size() == 2
			and small.all(func(s): return s.global_position.distance_to(bubble.global_position) < 60.0)
		),
		"a Bubble Slime bursts into two Bubblets when it dies (%d)" % small.size()
	)
	t._check(
		small.all(func(s): return s.get("respawns") == false), "and they do not come back"
	)


func _check_shell(main, player) -> void:
	main.change_map("lake", "north")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var turtle = _monster_near("snapjaw_turtle", Vector2(1050, 1060))
	t._freeze([turtle], false)
	turtle.moves.set("_ready_in", 0.0)  # its move is ready (a new monster waits up to 2 s)
	_heal(player)
	player.global_position = turtle.global_position + Vector2(95, 0)
	for i in 150:
		await t._frames(1)
		if turtle.moves.in_shell():
			break
	t._check(turtle.moves.in_shell(), "the Snapjaw Turtle hides in its shell when the hero comes")
	var hp_before: int = turtle.hp
	turtle.take_damage(100)
	t._check(
		hp_before - turtle.hp == 20, "in its shell it takes a fifth of the damage (%d)" % (
			hp_before - turtle.hp
		)
	)
	var snap := false
	for i in 200:
		await t._frames(1)
		snap = snap or t.get_nodes_in_group("telegraphs").any(
			func(mark): return is_equal_approx(float(mark.get("radius")), 130.0)
		)
		if snap:
			break
	_heal(player)
	await t._frames(50)
	t._check(
		snap and not turtle.moves.in_shell() and player.hp < player.max_hp,
		"then it comes out snapping all round it (%d HP)" % player.hp
	)


func _check_leap(main, player) -> void:
	main.change_map("lake", "north")
	await t._frames(3)
	t._freeze(t.get_nodes_in_group("enemies"), true)
	var frog = _monster_near("marsh_frog", Vector2(480, 1300))
	t._freeze([frog], false)
	frog.moves.set("_ready_in", 0.0)  # else it may walk up close first, too near to leap
	_heal(player)
	player.global_position = frog.global_position + Vector2(240, 0)
	var spot: Vector2 = player.global_position
	var mark = null
	for i in 150:
		await t._frames(1)
		for circle in t.get_nodes_in_group("telegraphs"):
			if is_equal_approx(float(circle.get("radius")), 90.0):
				mark = circle
		if mark != null:
			break
	t._check(
		mark != null and mark.global_position.distance_to(spot) < 30.0,
		"the Marsh Frog marks the spot where the hero stands"
	)
	var hp_before: int = player.hp
	await t._frames(80)
	t._check(
		frog.global_position.distance_to(spot) < 60.0 and player.hp < hp_before,
		"then it leaps there and lands on him (%d -> %d HP)" % [hp_before, player.hp]
	)


func _water():
	var all: Array = t.get_nodes_in_group("water")
	return all[0] if not all.is_empty() else null


func _monster_near(monster_id: String, point: Vector2):
	var kind: Array = t.get_nodes_in_group("enemies").filter(
		func(enemy): return enemy.monster_id == monster_id
	)
	return _nearest(kind, point)


func _nearest(nodes: Array, point: Vector2):
	var best = null
	for node in nodes:
		if best == null or node.global_position.distance_to(point) < best.global_position.distance_to(
			point
		):
			best = node
	return best


func _portal_to(map_id: String):
	for portal in t.get_nodes_in_group("portals"):
		if portal.get("to_map") == map_id:
			return portal
	return null


func _heal(player) -> void:
	player.hp = player.max_hp
	player.set("_invincible_left", 0.0)
