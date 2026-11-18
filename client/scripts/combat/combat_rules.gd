extends RefCounted
## Pure combat math with no scene or node dependencies: every hit in the game
## (the hero's swings, shots and skills, and the monsters' bites, slams and
## shots) is worked out here, so they all follow the same rules. The server
## has the same rules in Python (server/rules/combat.py).
## The numbers come from res://data/combat.json.

const GameData = preload("res://scripts/data/game_data.gd")

static var settings: Dictionary = GameData.table("combat")
## Plus or minus this fraction of the base damage.
static var damage_spread: float = float(settings["damage_spread"])
## A critical hit does this many times the damage (before crit damage bonuses).
static var crit_multiplier: float = float(settings["crit_multiplier"])
## Defense takes off its value from each hit, but a hit always keeps at least
## this part of its damage: weak heroes still hurt strong monsters a little.
static var defense_floor: float = float(settings.get("defense_floor", 0.0))
## Evasion (after the attacker's accuracy) never goes above this.
static var max_evasion: float = float(settings.get("max_evasion", 0.75))


## One attack against one target. Returns {"damage": int, "crit": bool, "miss": bool}.
## crit_damage: extra crit multiplier (0.2 = crits do 1.7x instead of 1.5x).
## accuracy: taken off the target's evasion.
static func resolve_hit(
	base_damage: int,
	crit_chance: float,
	defense: int,
	evasion: float,
	crit_damage: float = 0.0,
	accuracy: float = 0.0
) -> Dictionary:
	if randf() < hit_evasion(evasion, accuracy):
		return {"damage": 0, "crit": false, "miss": true}
	var damage: int = roll_damage(base_damage)
	var crit: bool = randf() < crit_chance
	if crit:
		damage = roundi(damage * (crit_multiplier + crit_damage))
	return {"damage": mitigate(damage, defense), "crit": crit, "miss": false}


## The chance that an attack misses: the target's evasion, less the attacker's accuracy.
static func hit_evasion(evasion: float, accuracy: float) -> float:
	return clampf(evasion - accuracy, 0.0, max_evasion)


## Damage left after the target's defense: never below defense_floor of it, nor below 1.
static func mitigate(damage: int, defense: int) -> int:
	return maxi(1, maxi(damage - defense, roundi(damage * defense_floor)))


## Damage of one hit: the base value, plus or minus a small random spread. Never below 1.
static func roll_damage(base_damage: int) -> int:
	var spread: int = _spread(base_damage)
	return maxi(1, base_damage + randi_range(-spread, spread))


## Lowest and highest damage roll_damage can give, for showing "8 ~ 12".
static func damage_range(base_damage: int) -> Vector2i:
	var spread: int = _spread(base_damage)
	return Vector2i(maxi(1, base_damage - spread), maxi(1, base_damage + spread))


## What one hit does on average: misses, crits, the spread and defense counted.
## For the DPS numbers and the balance tables (tools/balance.py).
static func expected_damage(
	base_damage: int,
	crit_chance: float,
	defense: int,
	evasion: float,
	crit_damage: float = 0.0,
	accuracy: float = 0.0
) -> float:
	var spread: int = _spread(base_damage)
	var total: float = 0.0
	var rolls: int = 0
	for each in range(base_damage - spread, base_damage + spread + 1):
		var roll: int = maxi(1, each)
		var normal: float = mitigate(roll, defense)
		var critical: float = mitigate(roundi(roll * (crit_multiplier + crit_damage)), defense)
		total += lerpf(normal, critical, clampf(crit_chance, 0.0, 1.0))
		rolls += 1
	return total / rolls * (1.0 - hit_evasion(evasion, accuracy))


static func _spread(base_damage: int) -> int:
	return maxi(1, roundi(base_damage * damage_spread))
