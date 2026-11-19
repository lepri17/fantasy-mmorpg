extends RefCounted
## O19: random events in the hunting maps (map_events.gd): a treasure chest,
## a swarm to beat in time, and a Lucky monster sure to drop good gear.
## smoke_test.gd runs it; t is the test (a SceneTree).

const ItemDb = preload("res://scripts/items/item_db.gd")
const MapEvents = preload("res://scripts/world/map_events.gd")

var t = null


func run(test, main, player, _hud) -> void:
	t = test
	var events = main.events
	main.change_map("town", "default")
	await t._frames(10)
	t._check(
		not events.huntable() and not events.start("treasure"),
		"no events in town"
	)
	main.change_map("forest", "west")
	await t._frames(30)
	_heal(player)
	t._check(events.huntable() and events.map_level() >= 4, "Mossy Woods is a hunting map")
	await _check_treasure(main, player, events)
	await _check_swarm(main, player, events)
	await _check_lucky(main, player, events)
	await _check_clock(main, player, events)


func _check_treasure(main, player, events) -> void:
	t._check(events.start("treasure"), "a treasure event starts")
	var chest = events.things[0]
	var nav: RID = main.map.get_world_2d().navigation_map
	var away: float = chest.position.distance_to(player.global_position)
	var ground: Vector2 = NavigationServer2D.map_get_closest_point(nav, chest.position)
	t._check(
		(
			chest.get_parent() == main.map
			and away < 500.0
			and ground.distance_to(chest.position) < 41.0
		),
		"a chest appears near the hero, on open ground (%d px away)" % away
	)
	t._check(not events.start("swarm"), "one event at a time")
	player.global_position = chest.position + Vector2(0, 20)
	await t._frames(10)
	t._check(chest.is_open and events.kind == "", "walking to it opens it, and the event is over")
	events.start("treasure")
	chest = events.things[0]
	events.left = 0.01
	await t._frames(3)
	t._check(
		events.kind == "" and events.things.is_empty(), "a chest nobody finds in time goes away"
	)
	await t._frames(2)
	t._check(
		not is_instance_valid(chest) or chest.is_queued_for_deletion(), "(and is gone from the map)"
	)


func _check_swarm(main, player, events) -> void:
	_heal(player)
	player.global_position = main.map.spawn_point("west") + Vector2(300, 0)
	await t._frames(5)
	t._check(events.start("swarm"), "a swarm event starts")
	var swarm: Array = events.things.duplicate()
	t._check(
		(
			swarm.size() == 6
			and swarm.all(func(monster): return monster.has_meta("event") and not monster.respawns)
			and swarm.all(func(monster): return monster.monster_id == swarm[0].monster_id)
		),
		"six of one of the map's monsters come, and they do not come back (%s)" % swarm[0].monster_id
	)
	var gold_before: int = player.stats.gold
	var xp_wanted: int = 0
	for monster in swarm:
		xp_wanted += monster.xp_reward
	var xp_before: int = player.stats.xp
	var level_before: int = player.stats.level
	for monster in swarm:
		monster.take_damage(999999, Vector2.ZERO, false, player)
	await t._frames(5)
	var wanted_gold: int = 25 * events.map_level()
	t._check(
		events.kind == "" and player.stats.gold >= gold_before + wanted_gold,
		"beating them all in time is a bonus: +%d gold, and EXP" % wanted_gold
	)
	t._check(
		player.stats.level > level_before or player.stats.xp >= xp_before + xp_wanted,
		"and the bonus EXP is the swarm's full EXP, on top of the kills (%d)" % xp_wanted
	)
	_heal(player)
	events.start("swarm")
	swarm = events.things.duplicate()
	events.left = 0.01
	await t._frames(3)
	t._check(events.kind == "", "a swarm not beaten in time gets away")
	await t._frames(2)
	t._check(
		swarm.all(
			func(monster): return not is_instance_valid(monster) or monster.is_queued_for_deletion()
		),
		"(they leave the map)"
	)


func _check_lucky(main, player, events) -> void:
	_heal(player)
	t._check(events.start("lucky"), "a Lucky monster event starts")
	var lucky = events.things[0]
	t._check(
		lucky.is_elite and lucky.display_name.begins_with("Lucky") and lucky.lucky_rarity == "rare",
		"it is golden (%s), and sure to drop Rare gear or better" % lucky.display_name
	)
	var before: Array = t.get_nodes_in_group("pickups")
	lucky.take_damage(999999, Vector2.ZERO, false, player)
	await t._frames(3)
	var gear: Array = t.get_nodes_in_group("pickups").filter(
		func(pickup): return not pickup in before and not pickup.get("stack").is_empty()
	)
	t._check(
		(
			events.kind == ""
			and not gear.is_empty()
			and ItemDb.rarity_rank(gear[0].get("stack")["rarity"]) >= ItemDb.rarity_rank("rare")
		),
		"catching it drops gear, Rare or better"
	)
	events.start("lucky")
	lucky = events.things[0]
	main.change_map("lake", "north")
	await t._frames(10)
	t._check(events.kind == "" and events.things.is_empty(), "leaving the map ends the event")


func _check_clock(main, player, events) -> void:
	main.change_map("forest", "west")
	await t._frames(20)
	_heal(player)
	MapEvents.enabled = true
	events.wait = 0.05
	await t._frames(10)
	t._check(events.kind != "", "when the wait is over, an event comes by itself (%s)" % events.kind)
	MapEvents.enabled = false
	events.left = 0.01
	await t._frames(3)
	t._check(
		events.kind == "" and events.wait >= 150.0 and events.wait <= 300.0,
		"and the next one waits minutes (%d s)" % events.wait
	)
	await t._frames(2)


func _heal(player) -> void:
	player.hp = player.max_hp
	player.set("_invincible_left", 0.0)
