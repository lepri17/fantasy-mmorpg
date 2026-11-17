extends RefCounted
## Timed effects on one character: "poison" (value = damage per second),
## "slow" (value = how much slower, 0..1) and "stun" (cannot move or act).
## The owner calls update() every physics frame.

var _effects: Dictionary = {}  # name -> {"left": seconds, "value": float}
var _poison_carry: float = 0.0


## Starts an effect, or makes a running one last longer / hit harder.
func apply(effect: String, seconds: float, value: float = 0.0) -> void:
	var current: Dictionary = _effects.get(effect, {"left": 0.0, "value": 0.0})
	_effects[effect] = {
		"left": maxf(seconds, float(current["left"])),
		"value": maxf(value, float(current["value"])),
	}


func is_active(effect: String) -> bool:
	return _effects.has(effect)


## Multiplier for walking speed (1 = normal).
func speed_factor() -> float:
	if not _effects.has("slow"):
		return 1.0
	return clampf(1.0 - float(_effects["slow"]["value"]), 0.1, 1.0)


## Counts the effects down. Returns the whole points of poison damage due now.
func update(delta: float) -> int:
	for effect in _effects.keys():
		var entry: Dictionary = _effects[effect]
		entry["left"] = float(entry["left"]) - delta
		if effect == "poison":
			_poison_carry += float(entry["value"]) * delta
		if entry["left"] <= 0.0:
			_effects.erase(effect)
	var damage: int = int(_poison_carry)
	_poison_carry -= damage
	return damage


func clear() -> void:
	_effects.clear()
	_poison_carry = 0.0
