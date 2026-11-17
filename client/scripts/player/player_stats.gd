extends RefCounted
## Progress of one character: level, XP, gold, the bag, the gear it wears, and
## the numbers that follow from them. Pure data and rules with no scene
## dependencies, so the same logic can move to the server later.

const ItemDb := preload("res://scripts/items/item_db.gd")

## Version of what to_dict() writes. 1 = level, xp, gold, potions.
## 2 = adds the bag and the gear; potions live in the bag.
const SAVE_VERSION := 2
## Health and damage without any gear. The starting gear adds 35 HP and
## 5 damage, so a new warrior has 100 HP and 10 damage.
const BASE_MAX_HP := 65
const HP_PER_LEVEL := 20
const BASE_DAMAGE := 5
const DAMAGE_PER_LEVEL := 3
const XP_PER_LEVEL := 50
const STARTING_POTIONS := 2
const BAG_SIZE := 15
const POTION_ID := "red_potion"
const STARTING_BAG := [{"id": POTION_ID, "count": STARTING_POTIONS}]
## Gear slot -> item id the warrior starts with.
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
## Gear slot -> item id. A slot with nothing on it is not in the dictionary.
var equipment: Dictionary = STARTING_GEAR.duplicate()
## Up to BAG_SIZE stacks of {"id": item id, "count": n}, with no gaps.
## Gear never stacks; other items (potions) share one stack.
var bag: Array = STARTING_BAG.duplicate(true)
## Potions in the bag. Setting it changes the potion stack.
var potions: int:
	get:
		return count_of(POTION_ID)
	set(value):
		_set_count(POTION_ID, maxi(value, 0))


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


## The bag's stacks, for showing them.
func bag_items() -> Array:
	return bag


func count_of(item_id: String) -> int:
	var index: int = _stack_index(item_id)
	return int(bag[index]["count"]) if index >= 0 else 0


func has_room_for(item_id: String) -> bool:
	return (_stacks(item_id) and _stack_index(item_id) >= 0) or bag.size() < BAG_SIZE


## Puts items in the bag. Returns false, and changes nothing, when they do not fit.
func add_item(item_id: String, count: int = 1) -> bool:
	if count <= 0 or not ItemDb.ITEMS.has(item_id):
		return false
	if _stacks(item_id):
		var index: int = _stack_index(item_id)
		if index >= 0:
			bag[index]["count"] = int(bag[index]["count"]) + count
			return true
		if bag.size() >= BAG_SIZE:
			return false
		bag.append({"id": item_id, "count": count})
		return true
	if bag.size() + count > BAG_SIZE:
		return false
	for _i in count:
		bag.append({"id": item_id, "count": 1})
	return true


## Takes one item out of a bag slot. Returns its id, or "" if the slot is empty.
func take_from_bag(index: int) -> String:
	if index < 0 or index >= bag.size():
		return ""
	var item_id: String = bag[index]["id"]
	var left: int = int(bag[index]["count"]) - 1
	if left <= 0:
		bag.remove_at(index)
	else:
		bag[index]["count"] = left
	return item_id


## Wears the gear in a bag slot. Gear already worn in that place goes to the
## same bag slot. Returns false for items that are not gear.
func equip(index: int) -> bool:
	if index < 0 or index >= bag.size():
		return false
	var item_id: String = bag[index]["id"]
	var slot: String = ItemDb.ITEMS[item_id].get("slot", "")
	if slot == "":
		return false
	var worn: String = equipment.get(slot, "")
	equipment[slot] = item_id
	if worn == "":
		bag.remove_at(index)
	else:
		bag[index] = {"id": worn, "count": 1}
	return true


## Moves worn gear into the bag. Returns false if nothing is worn there or the
## bag is full.
func unequip(slot: String) -> bool:
	var item_id: String = equipment.get(slot, "")
	if item_id == "" or bag.size() >= BAG_SIZE:
		return false
	equipment.erase(slot)
	bag.append({"id": item_id, "count": 1})
	return true


## Takes worn gear off without keeping it (it is dropped). Returns its id, or "".
func remove_equipped(slot: String) -> String:
	var item_id: String = equipment.get(slot, "")
	equipment.erase(slot)
	return item_id


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
	return {
		"version": SAVE_VERSION,
		"level": level,
		"xp": xp,
		"gold": gold,
		"bag": bag.duplicate(true),
		"equipment": equipment.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	gold = maxi(0, int(data.get("gold", 0)))
	bag = []
	if int(data.get("version", 1)) < 2:
		# Version 1 kept only a potion count, and the gear could not change yet.
		equipment = STARTING_GEAR.duplicate()
		potions = maxi(0, int(data.get("potions", STARTING_POTIONS)))
		return
	equipment = {}
	var saved_gear = data.get("equipment", {})
	if saved_gear is Dictionary:
		for slot in saved_gear:
			var item_id = saved_gear[slot]
			if ItemDb.ITEMS.has(item_id) and ItemDb.ITEMS[item_id].get("slot", "") == slot:
				equipment[slot] = item_id
	var saved_bag = data.get("bag", [])
	if saved_bag is Array:
		for stack in saved_bag:
			if stack is Dictionary and ItemDb.ITEMS.has(stack.get("id", "")):
				add_item(stack["id"], int(stack.get("count", 1)))


func _stacks(item_id: String) -> bool:
	return ItemDb.ITEMS[item_id].get("slot", "") == ""


func _stack_index(item_id: String) -> int:
	for i in bag.size():
		if bag[i]["id"] == item_id:
			return i
	return -1


func _set_count(item_id: String, count: int) -> void:
	var index: int = _stack_index(item_id)
	if index < 0:
		add_item(item_id, count)
	elif count == 0:
		bag.remove_at(index)
	else:
		bag[index]["count"] = count
