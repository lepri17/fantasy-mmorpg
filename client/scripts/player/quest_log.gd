extends RefCounted
## Quests from res://data/quests.json: which are active and how far, and
## when each was last finished. Goals: "kill" a monster (or "any"), "collect"
## items (counted in the bag), "talk" to a townsperson. Daily quests can be
## done again on a new day. Pure data, like player_stats.gd; "today" is passed
## in ("YYYY-MM-DD") so tests can pick the day.

const GameData := preload("res://scripts/data/game_data.gd")

## Quest id -> its fields.
static var list: Dictionary = GameData.table("quests")

## Quest id -> kills or talks counted so far (collect goals count the bag).
var active: Dictionary = {}
## Quest id -> the day it was last finished.
var done: Dictionary = {}


## Today's date on this device, for daily quests.
static func today() -> String:
	return Time.get_date_string_from_system()


## "locked" (level or earlier quest missing), "available", "active", "ready"
## (goal reached, go back to the giver) or "done".
func state(quest_id: String, stats, today: String) -> String:
	if active.has(quest_id):
		return "ready" if progress(quest_id, stats) >= goal_count(quest_id) else "active"
	var quest: Dictionary = list[quest_id]
	if done.has(quest_id) and (not quest.get("daily", false) or done[quest_id] == today):
		return "done"
	if stats.level < int(quest.get("level", 1)):
		return "locked"
	if quest.has("after") and not done.has(quest["after"]):
		return "locked"
	return "available"


func start(quest_id: String, stats, today: String) -> bool:
	if state(quest_id, stats, today) != "available":
		return false
	active[quest_id] = 0
	return true


## How far a quest is: kills or talks, or the items of a collect goal in the bag.
func progress(quest_id: String, stats) -> int:
	var goal: Dictionary = list[quest_id]["goal"]
	if goal["type"] == "collect":
		return stats.count_of(goal["item"])
	return int(active.get(quest_id, 0))


func goal_count(quest_id: String) -> int:
	return int(list[quest_id]["goal"].get("count", 1))


## A monster died: counts it for the kill quests it matters to. Returns them.
func on_kill(monster_id: String) -> Array:
	var counted: Array = []
	for quest_id in active:
		var goal: Dictionary = list[quest_id]["goal"]
		var wanted: bool = goal["monster"] in ["any", monster_id] if goal["type"] == "kill" else false
		if wanted and int(active[quest_id]) < goal_count(quest_id):
			active[quest_id] = int(active[quest_id]) + 1
			counted.append(quest_id)
	return counted


## The warrior talked to a townsperson: finishes the talk goals about them.
func on_talk(npc_id: String) -> Array:
	var reached: Array = []
	for quest_id in active:
		var goal: Dictionary = list[quest_id]["goal"]
		if goal["type"] == "talk" and goal["npc"] == npc_id and int(active[quest_id]) < 1:
			active[quest_id] = 1
			reached.append(quest_id)
	return reached


## The giver took the quest back: no longer active, finished today.
func finish(quest_id: String, today: String) -> void:
	active.erase(quest_id)
	done[quest_id] = today


## Quests this townsperson gives, in the data's order.
static func given_by(npc_id: String) -> Array:
	return list.keys().filter(func(quest_id: String) -> bool: return list[quest_id]["giver"] == npc_id)


func to_dict() -> Dictionary:
	return {"quests": {"active": active.duplicate(), "done": done.duplicate()}}


## Anything unknown is left out.
func from_dict(data: Dictionary) -> void:
	active = {}
	done = {}
	var saved = data.get("quests", {})
	if not saved is Dictionary:
		return
	var saved_active = saved.get("active", {})
	if saved_active is Dictionary:
		for quest_id in saved_active:
			if list.has(quest_id):
				active[quest_id] = maxi(0, int(saved_active[quest_id]))
	var saved_done = saved.get("done", {})
	if saved_done is Dictionary:
		for quest_id in saved_done:
			if list.has(quest_id):
				done[quest_id] = str(saved_done[quest_id])
