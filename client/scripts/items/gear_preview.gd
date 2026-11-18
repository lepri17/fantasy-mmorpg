extends RefCounted
## What wearing a piece from the bag would really change for the hero: his
## attack, HP, defense, crit and the rest, counting set bonuses, upgrades and
## the piece that comes off. Pure rules on a copy of the stats; the inventory
## window only shows the result.

const PlayerStats := preload("res://scripts/player/player_stats.gd")

## The hero numbers compared, in the order the window shows them.
const NUMBERS := [
	"attack",
	"max_hp",
	"defense",
	"crit_chance",
	"crit_damage",
	"evasion",
	"accuracy",
	"attack_speed",
	"max_stamina",
	"skill_damage",
]


## stat -> the hero's number now ("attack" is the hit before the ±20% spread).
static func numbers(stats) -> Dictionary:
	return {
		"attack": stats.attack_damage(),
		"max_hp": stats.max_hp(),
		"defense": stats.defense(),
		"crit_chance": stats.crit_chance(),
		"crit_damage": stats.total("crit_damage"),
		"evasion": stats.evasion(),
		"accuracy": stats.total("accuracy"),
		"attack_speed": stats.total("attack_speed"),
		"max_stamina": stats.max_stamina(),
		"skill_damage": stats.skill_damage_bonus(),
	}


## The same numbers if the bag entry at index were worn, or {} when it cannot
## be worn now (not gear, another class, or the hero's level is too low).
static func if_worn(stats, index: int) -> Dictionary:
	var copy = copy_of(stats)
	if not copy.equip(index):
		return {}
	return numbers(copy)


## stat -> change (after minus before), only for the numbers that change.
static func changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for stat in NUMBERS:
		var difference: float = float(after.get(stat, 0.0)) - float(before.get(stat, 0.0))
		if absf(difference) > 0.0001:
			result[stat] = difference
	return result


## True when wearing the piece makes no number worse and at least one better.
static func is_better(stats, index: int) -> bool:
	var after: Dictionary = if_worn(stats, index)
	if after.is_empty():
		return false
	var difference: Dictionary = changes(numbers(stats), after)
	if difference.is_empty():
		return false
	for stat in difference:
		if difference[stat] < 0.0:
			return false
	return true


## A copy of the hero to try gear on: every field copied, the bag and the
## gear as their own copies, so trying never changes the real hero.
static func copy_of(stats):
	var copy = PlayerStats.new()
	for property in stats.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = stats.get(property["name"])
			if value is Array or value is Dictionary:
				value = value.duplicate(true)
			copy.set(property["name"], value)
	return copy
