extends RefCounted
## Progress of one character: level, XP, gold, potions, the gear it wears,
## and the numbers that follow from them. Pure data and rules with no scene
## dependencies, so the same logic can move to the server later.

const ItemDb := preload("res://scripts/items/item_db.gd")

## Health and damage without any gear. The starting gear adds 35 HP and
## 5 damage, so a new warrior has 100 HP and 10 damage.
const BASE_MAX_HP := 65
const HP_PER_LEVEL := 20
const BASE_DAMAGE := 5
const DAMAGE_PER_LEVEL := 3
const XP_PER_LEVEL := 50
const STARTING_POTIONS := 2
## Gear slot -> item id. Nothing can change the gear yet, so it is not saved.
const STARTING_GEAR := {
	"head": "red_headband",
	"weapon": "training_sword",
	"gloves": "leather_gloves",
	"cape": "red_cape",
	"armor": "blue_plate",
	"boots": "leather_boots",
}

var level: int = 1
var xp: int = 0
var gold: int = 0
var potions: int = STARTING_POTIONS
var equipment: Dictionary = STARTING_GEAR.duplicate()


func max_hp() -> int:
	return BASE_MAX_HP + HP_PER_LEVEL * (level - 1) + gear_bonus("max_hp")


func attack_damage() -> int:
	return BASE_DAMAGE + DAMAGE_PER_LEVEL * (level - 1) + gear_bonus("attack")


## Sum of one bonus ("attack" or "max_hp") over all the gear worn.
func gear_bonus(stat: String) -> int:
	var total: int = 0
	for item_id in equipment.values():
		total += int(ItemDb.ITEMS[item_id].get(stat, 0))
	return total


## What is in the bag: [{"id": item id, "count": how many}].
## Potions are the only bag item so far.
func bag_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if potions > 0:
		items.append({"id": "red_potion", "count": potions})
	return items


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
