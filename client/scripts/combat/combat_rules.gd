extends RefCounted
## Pure combat math with no scene or node dependencies.
## Kept separate on purpose: later the server can run the same rules.
## The numbers come from res://data/combat.json.

const GameData = preload("res://scripts/data/game_data.gd")

static var settings: Dictionary = GameData.table("combat")
## Plus or minus this fraction of the base damage.
static var damage_spread: float = float(settings["damage_spread"])
static var crit_multiplier: float = float(settings["crit_multiplier"])


## One attack against one target: a miss (target's evasion), otherwise the
## rolled damage, times crit_multiplier on a critical hit, minus the target's
## defense, never below 1. Returns {"damage": int, "crit": bool, "miss": bool}.
static func resolve_hit(
	base_damage: int, crit_chance: float, defense: int, evasion: float
) -> Dictionary:
	if randf() < evasion:
		return {"damage": 0, "crit": false, "miss": true}
	var damage: int = roll_damage(base_damage)
	var crit: bool = randf() < crit_chance
	if crit:
		damage = roundi(damage * crit_multiplier)
	return {"damage": maxi(1, damage - defense), "crit": crit, "miss": false}


## Damage of one hit: the base value, plus or minus a small random spread. Never below 1.
static func roll_damage(base_damage: int) -> int:
	var spread: int = _spread(base_damage)
	return maxi(1, base_damage + randi_range(-spread, spread))


## Lowest and highest damage roll_damage can give, for showing "8 ~ 12".
static func damage_range(base_damage: int) -> Vector2i:
	var spread: int = _spread(base_damage)
	return Vector2i(maxi(1, base_damage - spread), maxi(1, base_damage + spread))


static func _spread(base_damage: int) -> int:
	return maxi(1, roundi(base_damage * damage_spread))
