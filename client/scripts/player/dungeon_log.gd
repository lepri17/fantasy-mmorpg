extends RefCounted
## W6: how many times the warrior went into each dungeon today. Pure data,
## like player_stats.gd; "today" is passed in ("YYYY-MM-DD").

## Dungeon map id -> {"date": the day, "count": entries that day}.
var runs: Dictionary = {}


## Entries left today, out of the dungeon's entries per day.
func entries_left(dungeon: String, per_day: int, today: String) -> int:
	return maxi(0, per_day - _used(dungeon, today))


func count_entry(dungeon: String, today: String) -> void:
	runs[dungeon] = {"date": today, "count": _used(dungeon, today) + 1}


func to_dict() -> Dictionary:
	return {"dungeon_runs": runs.duplicate(true)}


## Anything that is not a {"date", "count"} entry is left out.
func from_dict(data: Dictionary) -> void:
	runs = {}
	var saved = data.get("dungeon_runs", {})
	if not saved is Dictionary:
		return
	for dungeon in saved:
		var run = saved[dungeon]
		if run is Dictionary:
			runs[str(dungeon)] = {
				"date": str(run.get("date", "")), "count": maxi(0, int(run.get("count", 0)))
			}


func _used(dungeon: String, today: String) -> int:
	var run: Dictionary = runs.get(dungeon, {})
	return int(run.get("count", 0)) if run.get("date", "") == today else 0
