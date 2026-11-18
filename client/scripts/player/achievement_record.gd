extends RefCounted
## Achievements and titles: counters of what the player did, the achievements
## those counters reached, and the one title shown (its bonus counts in the
## stats). Pure data, like player_stats.gd.

const GameData := preload("res://scripts/data/game_data.gd")

## res://data/achievements.json: what each achievement counts, its goal, its
## title and the bonus that title gives while it is shown.
static var list: Dictionary = GameData.table("achievements")

## "kills", "kills:<monster id>", "elite_kills", "gold_earned", "potions_used",
## "deaths", "books_read".
var counters: Dictionary = {}
## Earned achievement ids, oldest first.
var earned: Array = []
## The achievement whose title is shown, or "".
var title: String = ""


## Adds to a counter and returns the achievements this finished.
func count(counter: String, amount: int, level: int) -> Array:
	counters[counter] = int(counters.get(counter, 0)) + maxi(amount, 0)
	return check(level)


## How far an achievement is: its counter, or the level for "level".
func progress(achievement_id: String, level: int) -> int:
	var counter: String = list[achievement_id]["counter"]
	return level if counter == "level" else int(counters.get(counter, 0))


## Marks every achievement whose goal is reached and returns the new ones.
## The first title earned is shown right away.
func check(level: int) -> Array:
	var new_ones: Array = []
	for achievement_id in list:
		var goal: int = int(list[achievement_id]["goal"])
		if not earned.has(achievement_id) and progress(achievement_id, level) >= goal:
			earned.append(achievement_id)
			new_ones.append(achievement_id)
	if title == "" and not new_ones.is_empty():
		title = new_ones[0]
	return new_ones


## Shows an earned title ("" for none). Returns false for one not earned.
func set_title(achievement_id: String) -> bool:
	if achievement_id != "" and not earned.has(achievement_id):
		return false
	title = achievement_id
	return true


## What the shown title adds to one number ("attack", "max_hp", ...).
func title_bonus(stat: String) -> float:
	if title == "":
		return 0.0
	return float(list[title].get("bonus", {}).get(stat, 0.0))


func to_dict() -> Dictionary:
	return {"counters": counters.duplicate(), "achievements": earned.duplicate(), "title": title}


## Anything unknown or out of range is left out.
func from_dict(data: Dictionary) -> void:
	counters = {}
	var saved_counters = data.get("counters", {})
	if saved_counters is Dictionary:
		for counter in saved_counters:
			counters[str(counter)] = maxi(0, int(saved_counters[counter]))
	earned = []
	var saved = data.get("achievements", [])
	if saved is Array:
		for achievement_id in saved:
			if list.has(achievement_id) and not earned.has(achievement_id):
				earned.append(achievement_id)
	title = str(data.get("title", ""))
	if not earned.has(title):
		title = ""
