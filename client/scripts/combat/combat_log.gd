extends RefCounted
## The hero's damage over the last seconds, for the DPS meter (settings: Show
## DPS) and the tests. Pure data: the owner adds the time that passed.

## Hits are kept this long.
const WINDOW := 10.0

var total_damage: int = 0
var hits: int = 0
var crits: int = 0
var misses: int = 0
var _time: float = 0.0
var _recent: Array = []  # [time, damage]


func advance(delta: float) -> void:
	_time += delta
	while not _recent.is_empty() and _time - float(_recent[0][0]) > WINDOW:
		_recent.pop_front()


func record(hit: Dictionary) -> void:
	if hit.get("miss", false):
		misses += 1
		return
	var damage: int = int(hit["damage"])
	total_damage += damage
	hits += 1
	if hit.get("crit", false):
		crits += 1
	_recent.append([_time, damage])


## Damage a second over the last `seconds` (at most WINDOW).
func dps(seconds: float = 5.0) -> float:
	var since: float = _time - minf(seconds, WINDOW)
	var sum: int = 0
	for entry in _recent:
		if float(entry[0]) > since:
			sum += int(entry[1])
	return sum / maxf(minf(seconds, _time), 0.001)


func reset() -> void:
	total_damage = 0
	hits = 0
	crits = 0
	misses = 0
	_recent.clear()
