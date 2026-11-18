extends RefCounted
## What is where, from data/maps.json: the maps a monster or a townsperson is
## in, and the next map on the way to another one (through the portals). Used
## to walk the hero to a quest's target (auto_pilot.gd).

const GameData := preload("res://scripts/data/game_data.gd")


static func maps() -> Dictionary:
	return GameData.table("maps")["maps"]


## Monster ids that live in a map (its "monsters" list and its monster objects).
static func monsters_in(map_id: String) -> Array:
	var data: Dictionary = maps().get(map_id, {})
	var result: Array = data.get("monsters", []).duplicate()
	for entry in data.get("objects", []):
		if entry.get("type") == "monster" and not result.has(entry["id"]):
			result.append(entry["id"])
	return result


## Where to hunt a monster: here if it lives here, else the first map with it.
## "any" is any monster: here if this map has monsters.
static func map_with_monster(monster_id: String, here: String) -> String:
	var mine: Array = monsters_in(here)
	if (monster_id == "any" and not mine.is_empty()) or mine.has(monster_id):
		return here
	for map_id in maps():
		var theirs: Array = monsters_in(map_id)
		if (monster_id == "any" and not theirs.is_empty()) or theirs.has(monster_id):
			return map_id
	return ""


static func map_with_npc(npc_id: String) -> String:
	for map_id in maps():
		for entry in maps()[map_id].get("objects", []):
			if entry.get("type") == "npc" and entry.get("id") == npc_id:
				return map_id
	return ""


## A monster that drops the item and lives in some map, or "".
static func monster_dropping(item_id: String) -> String:
	var monsters: Dictionary = GameData.table("monsters")
	for monster_id in monsters:
		for drop in monsters[monster_id].get("drops", []):
			if drop.get("item") == item_id and map_with_monster(monster_id, "") != "":
				return monster_id
	return ""


## The next map on the way from one map to another, or "" if there is no way.
static func next_map(from: String, to: String) -> String:
	if from == to:
		return to
	var came_from := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for entry in maps().get(current, {}).get("objects", []):
			var neighbor: String = entry.get("to", "")
			if not entry.get("type") in ["portal", "exit"] or came_from.has(neighbor):
				continue
			came_from[neighbor] = current
			if neighbor == to:
				var step: String = to
				while came_from[step] != from:
					step = came_from[step]
				return step
			queue.append(neighbor)
	return ""
