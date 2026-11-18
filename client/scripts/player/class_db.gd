extends RefCounted
## The classes (data/classes.json): Warrior, Mage and Archer. Each has its name,
## art, basic attack, its own numbers over character.json, what its stat points
## give, and its skills (the skills with its "class" in skills.json).

const GameData := preload("res://scripts/data/game_data.gd")
const DEFAULT := "warrior"


## Class ids in the order the character screen shows them.
static func ids() -> Array:
	return GameData.table("classes")["order"]


## The classes a new hero can be (classes.json "playable"; the mage waits for now).
static func playable() -> Array:
	return GameData.table("classes").get("playable", ids())


static func exists(class_id: String) -> bool:
	return GameData.table("classes")["classes"].has(class_id)


## The class's entry in classes.json (the Warrior's for an unknown id).
static func info(class_id: String) -> Dictionary:
	var table: Dictionary = GameData.table("classes")["classes"]
	return table.get(class_id, table[DEFAULT])


## A number or setting from character.json, or the class's own value for it.
static func rule(class_id: String, key: String) -> Variant:
	var own: Dictionary = info(class_id).get("rules", {})
	return own[key] if own.has(key) else GameData.table("character")[key]


## What one point in a stat gives this class: character.json's rule, with the
## class's own changes on top.
static func stat_rule(class_id: String, stat_id: String) -> Dictionary:
	var base: Dictionary = GameData.table("character")["stats"].get(stat_id, {})
	return base.merged(info(class_id).get("stats", {}).get(stat_id, {}), true)


## The class's skill ids, in button order (skill, skill_2 ... skill_5).
static func skills(class_id: String) -> Array:
	var table: Dictionary = GameData.table("skills")
	var result: Array = []
	for skill_id in table:
		if table[skill_id].get("class", DEFAULT) == class_id:
			result.append(skill_id)
	result.sort_custom(func(a, b) -> bool: return table[a]["action"] < table[b]["action"])
	return result


## "Mage", or the name after the job advancement ("Sorcerer").
static func display_name(class_id: String, advanced: bool = false) -> String:
	var data: Dictionary = info(class_id)
	return data["advanced"]["name"] if advanced else data["name"]


## The colour of the glow under a hero who made the job advancement.
static func advanced_color(class_id: String) -> Color:
	var rgb: Array = info(class_id)["advanced"]["color"]
	return Color(rgb[0], rgb[1], rgb[2])


## The colour of the second bar (stamina or mana).
static func resource_color(class_id: String) -> Color:
	var rgb: Array = info(class_id)["resource_color"]
	return Color(rgb[0], rgb[1], rgb[2])
