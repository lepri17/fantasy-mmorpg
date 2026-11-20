extends RefCounted
## The stages of each hunting region (Mor, 2026-11-20): like MapleStory's
## Hunting Ground I, II, III, each region is a chain of maps with the same
## family of monsters in a shifting mix, 17-23 monsters a map. The map that was
## there before is the deepest stage; Green Meadow, where heroes start, is the
## first. smoke_test.gd runs it; t is the test (a SceneTree).

const GameData = preload("res://scripts/data/game_data.gd")
const MapGuide = preload("res://scripts/maps/map_guide.gd")

## [region name, stage I, II, III map ids]
const REGIONS := [
	["Green Meadow", "field", "field_2", "field_3"],
	["Mossy Woods", "forest_1", "forest_2", "forest"],
]

var t = null


func run(test, main, player, _hud) -> void:
	t = test
	var maps: Dictionary = GameData.table("maps")["maps"]
	for region in REGIONS:
		var names: Array = [maps[region[1]]["name"], maps[region[2]]["name"], maps[region[3]]["name"]]
		t._check(
			names == ["%s I" % region[0], "%s II" % region[0], "%s III" % region[0]],
			"%s has three stages (%s)" % [region[0], ", ".join(names)]
		)
		t._check(
			_road(maps, region[1], region[2]) and _road(maps, region[2], region[3]),
			"the road goes I -> II -> III and back"
		)
		var sizes: Array = []
		for stage in [region[1], region[2], region[3]]:
			sizes.append(_monsters(maps, stage).size())
		t._check(
			sizes.all(func(n): return n >= 17 and n <= 23),
			"each stage of %s has 17-23 monsters (%s)" % [region[0], str(sizes)]
		)
		t._check(
			maps[region[2]].get("no_teleport", false),
			"the guides do not teleport to the middle stage"
		)
	var first: Array = _monsters(maps, "field")
	var third: Array = _monsters(maps, "field_3")
	t._check(
		(
			first.count("green_slime") > first.count("blue_slime")
			and third.count("blue_slime") + third.count("twin_slime") > third.count("green_slime")
		),
		"deeper into the meadow, the slimes get tougher (I: mostly green, III: blue and twin)"
	)
	t._check(
		(
			MapGuide.next_map("field", "forest") == "field_2"
			and MapGuide.next_map("town", "lake") == "field"
		),
		"the map guide walks through every stage"
	)
	main.change_map("field_2", "west")
	await t._frames(20)
	t._check(
		(
			main.map.map_id == "field_2"
			and t.get_nodes_in_group("enemies").size() >= 15
			and t.get_nodes_in_group("enemies").all(func(enemy): return enemy.boss.is_empty())
		),
		"Green Meadow II loads with its monsters"
	)
	var east = main.map.get_children().filter(
		func(node): return node.get("to_map") == "field_3"
	)[0]
	player.hp = player.max_hp
	player.global_position = east.global_position
	await t._frames(30)
	t._check(main.map.map_id == "field_3", "its east road leads on to Green Meadow III")
	main.change_map("forest", "west")
	await t._frames(10)


## True when a's road goes to b and b's comes back to a.
func _road(maps: Dictionary, a: String, b: String) -> bool:
	var there: bool = maps[a]["objects"].any(func(o): return o["type"] == "exit" and o["to"] == b)
	var back: bool = maps[b]["objects"].any(func(o): return o["type"] == "exit" and o["to"] == a)
	return there and back


func _monsters(maps: Dictionary, map_id: String) -> Array:
	return maps[map_id]["objects"].filter(func(o): return o["type"] == "monster").map(
		func(o): return o["id"]
	)
