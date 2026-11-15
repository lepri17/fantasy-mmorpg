extends RefCounted
## Progress of one character: level, XP, gold, potions, and the numbers that
## follow from the level. Pure data and rules with no scene dependencies,
## so the same logic can move to the server later.

const BASE_MAX_HP := 100
const HP_PER_LEVEL := 20
const BASE_DAMAGE := 10
const DAMAGE_PER_LEVEL := 3
const XP_PER_LEVEL := 50
const STARTING_POTIONS := 2

var level: int = 1
var xp: int = 0
var gold: int = 0
var potions: int = STARTING_POTIONS


func max_hp() -> int:
	return BASE_MAX_HP + HP_PER_LEVEL * (level - 1)


func attack_damage() -> int:
	return BASE_DAMAGE + DAMAGE_PER_LEVEL * (level - 1)


## XP needed to finish the current level.
func xp_to_next() -> int:
	return XP_PER_LEVEL * level


## Adds XP and returns how many levels were gained.
func add_xp(amount: int) -> int:
	var gained: int = 0
	xp += maxi(amount, 0)
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
	return gained


func to_dict() -> Dictionary:
	return {"level": level, "xp": xp, "gold": gold, "potions": potions}


func from_dict(data: Dictionary) -> void:
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	gold = maxi(0, int(data.get("gold", 0)))
	potions = maxi(0, int(data.get("potions", STARTING_POTIONS)))
