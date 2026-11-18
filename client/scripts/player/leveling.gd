extends RefCounted
## The level rules from res://data/character.json: the XP each level needs
## ("xp_curve") and how much of a monster's XP a hero gets for its level
## ("xp_level_gap"). Pure rules, the same as server/rules/stats.py.

const GameData := preload("res://scripts/data/game_data.gd")


## XP to finish a level: base x level^exponent, rounded.
static func xp_for_level(level: int) -> int:
	var curve: Dictionary = GameData.table("character")["xp_curve"]
	return roundi(float(curve["base"]) * pow(float(level), float(curve["exponent"])))


## Part of a monster's XP a hero gets: all of it up to a few levels above the
## monster, then less for every level more (never below "lowest"), and a
## little more for a monster above the hero (up to "highest").
static func gap_factor(hero_level: int, monster_level: int) -> float:
	var gap: Dictionary = GameData.table("character")["xp_level_gap"]
	var difference: int = hero_level - monster_level
	if difference < 0:
		return minf(1.0 + float(gap["gain_per_level"]) * -difference, float(gap["highest"]))
	var extra: int = difference - int(gap["free_levels"])
	if extra <= 0:
		return 1.0
	return maxf(1.0 - float(gap["loss_per_level"]) * extra, float(gap["lowest"]))


## The XP one kill gives, never less than 1.
static func kill_xp(xp: int, hero_level: int, monster_level: int) -> int:
	return maxi(1, roundi(xp * gap_factor(hero_level, monster_level)))
