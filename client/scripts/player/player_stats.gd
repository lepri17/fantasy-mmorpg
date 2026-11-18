extends RefCounted
## Progress of one character: level, XP, gold, the bag, the gear it wears, and
## the numbers that follow from them. Pure data and rules with no scene
## dependencies, so the same logic can move to the server later.

const ItemDb := preload("res://scripts/items/item_db.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const AchievementRecord := preload("res://scripts/player/achievement_record.gd")

## Version of what to_dict() writes. 1 = level, xp, gold, potions.
## 2 = adds the bag and the gear; potions live in the bag.
## 3 = adds stat points, skills learned from books, achievements and the title.
## 4 = gear keeps its own rarity, upgrade level and random options.
const SAVE_VERSION := 4
const POTION_ID := "red_potion"

## The numbers from res://data/character.json: health and damage without gear
## (the starting gear adds 35 HP and 5 damage, so a new warrior has 100 HP and
## 10 damage), what each level adds, XP per level, bag size, starting gear and
## bag, and the tuning the player scene reads (speed, skill, regeneration).
static var rules: Dictionary = GameData.table("character")
static var bag_size: int = int(rules["bag_size"])
## STR, AGI, VIT, ENE: what one point in each adds ("attack", "max_hp", ...).
static var stat_rules: Dictionary = rules["stats"]

var level: int = 1
var xp: int = 0
var gold: int = 0
## Gear slot -> the worn entry ({"id", "count": 1, "rarity", "plus", "options"}).
var equipment: Dictionary = {}
## Up to bag_size stacks of {"id": item id, "count": n}, with no gaps.
## Gear never stacks; other items (potions) share one stack.
var bag: Array = []
## Potions in the bag. Setting it changes the potion stack.
var potions: int:
	get:
		return count_of(POTION_ID)
	set(value):
		_set_count(POTION_ID, maxi(value, 0))
## Points put into each stat ("strength", "agility", "vitality", "energy").
var stat_points: Dictionary = {}
## Skills learned from books (skills.json entries with a "book").
var learned_skills: Array = []
## Drink a red potion by itself below this percent of HP (0 = off).
var auto_potion: int = 0
## Achievements, their counters and the title shown (achievement_record.gd).
var record = AchievementRecord.new()


func _init() -> void:
	_start_fresh()


## The auto-potion settings as whole percents (JSON gives floats).
static func auto_potion_choices() -> Array:
	return rules["auto_potion_choices"].map(func(value): return int(value))


func max_hp() -> int:
	var per_level: int = int(rules["hp_per_level"])
	return (
		int(rules["base_max_hp"])
		+ per_level * (level - 1)
		+ gear_bonus("max_hp")
		+ int(extra_bonus("max_hp"))
	)


func attack_damage() -> int:
	var per_level: int = int(rules["damage_per_level"])
	return (
		int(rules["base_damage"])
		+ per_level * (level - 1)
		+ gear_bonus("attack")
		+ int(extra_bonus("attack"))
	)


## Damage taken from each hit goes down by this much (never below 1).
func defense() -> int:
	return int(rules.get("defense", 0)) + gear_bonus("defense") + int(extra_bonus("defense"))


## Chance (0..1) that a hit is critical.
func crit_chance() -> float:
	return (
		float(rules.get("crit_chance", 0.0))
		+ gear_bonus_fraction("crit_chance")
		+ extra_bonus("crit_chance")
	)


## Chance (0..1) that a monster's hit misses.
func evasion() -> float:
	return float(rules.get("evasion", 0.0)) + gear_bonus_fraction("evasion") + extra_bonus("evasion")


func max_stamina() -> float:
	return float(rules["max_stamina"]) + gear_total("max_stamina") + extra_bonus("max_stamina")


## Extra skill damage as a fraction (0.1 = +10%).
func skill_damage_bonus() -> float:
	return gear_total("skill_damage") + extra_bonus("skill_damage")


## What the stat points and the title add to one number ("attack", "max_hp",
## "defense", "crit_chance", "evasion", "max_stamina", "skill_damage").
func extra_bonus(stat: String) -> float:
	var total: float = 0.0
	for stat_id in stat_points:
		total += float(stat_points[stat_id]) * float(stat_rules[stat_id].get(stat, 0.0))
	return total + record.title_bonus(stat)


# --- stat points (MU style: every level gives points to put into STR, AGI, VIT, ENE)


## Points earned so far that are not in a stat yet.
func free_points() -> int:
	return (level - 1) * int(rules["stat_points_per_level"]) - spent_points()


func spent_points() -> int:
	var total: int = 0
	for stat_id in stat_points:
		total += int(stat_points[stat_id])
	return total


func points_in(stat_id: String) -> int:
	return int(stat_points.get(stat_id, 0))


## Puts one free point into a stat. Returns false when there is none to spend.
func add_stat_point(stat_id: String) -> bool:
	if free_points() <= 0 or not stat_rules.has(stat_id):
		return false
	stat_points[stat_id] = points_in(stat_id) + 1
	return true


func reset_cost() -> int:
	return int(rules["stat_reset_gold_per_level"]) * level


## Gives every point back. With pay_gold it costs reset_cost() gold (a Rebirth
## Scroll resets for free). Returns false when nothing changed.
func reset_stats(pay_gold: bool) -> bool:
	if spent_points() == 0 or (pay_gold and gold < reset_cost()):
		return false
	if pay_gold:
		gold -= reset_cost()
	stat_points = {}
	return true


# --- skills from books


func knows_skill(skill_id: String) -> bool:
	return learned_skills.has(skill_id)


func learn_skill(skill_id: String) -> bool:
	if knows_skill(skill_id):
		return false
	learned_skills.append(skill_id)
	return true


## Sum of one whole-number bonus ("attack", "max_hp", "defense") over the gear worn.
func gear_bonus(stat: String) -> int:
	return roundi(gear_total(stat))


## Sum of one fraction bonus ("crit_chance", "evasion") over the gear worn.
func gear_bonus_fraction(stat: String) -> float:
	return gear_total(stat)


## One stat over all the gear worn: own values, random options and upgrades.
func gear_total(stat: String) -> float:
	var total: float = set_bonus(stat)
	for stack in equipment.values():
		total += ItemDb.stat_of(stack, stat)
	return total


## Set id -> how many of its pieces are worn.
func set_pieces() -> Dictionary:
	var counts: Dictionary = {}
	for stack in equipment.values():
		var set_id: String = ItemDb.items[stack["id"]].get("set", "")
		if set_id != "":
			counts[set_id] = int(counts.get(set_id, 0)) + 1
	return counts


## What the worn sets add to one stat: every bonus whose piece count is reached.
func set_bonus(stat: String) -> float:
	var total: float = 0.0
	var counts: Dictionary = set_pieces()
	for set_id in counts:
		var bonuses: Dictionary = ItemDb.sets[set_id]["bonuses"]
		for needed in bonuses:
			if int(counts[set_id]) >= int(needed):
				total += float(bonuses[needed].get(stat, 0.0))
	return total


## Id of the item worn in a gear slot, or "".
func equipped_id(slot: String) -> String:
	return equipment.get(slot, {}).get("id", "")


## The bag's stacks, for showing them.
func bag_items() -> Array:
	return bag


func count_of(item_id: String) -> int:
	var index: int = _stack_index(item_id)
	return int(bag[index]["count"]) if index >= 0 else 0


func has_room_for(item_id: String) -> bool:
	return (_stacks(item_id) and _stack_index(item_id) >= 0) or bag.size() < bag_size


## Puts items in the bag. Returns false, and changes nothing, when they do not fit.
func add_item(item_id: String, count: int = 1) -> bool:
	if count <= 0 or not ItemDb.items.has(item_id):
		return false
	if _stacks(item_id):
		var index: int = _stack_index(item_id)
		if index >= 0:
			bag[index]["count"] = int(bag[index]["count"]) + count
			return true
		if bag.size() >= bag_size:
			return false
		bag.append({"id": item_id, "count": count})
		return true
	if bag.size() + count > bag_size:
		return false
	for _i in count:
		bag.append(ItemDb.gear(item_id))
	return true


## Puts an entry in the bag as it is (gear keeps its rarity, upgrades and
## options). Returns false, and changes nothing, when it does not fit.
func add_stack(stack: Dictionary) -> bool:
	var entry: Dictionary = ItemDb.clean_stack(stack)
	if entry.is_empty():
		return false
	if not ItemDb.is_gear(entry["id"]):
		return add_item(entry["id"], int(entry["count"]))
	if bag.size() >= bag_size:
		return false
	bag.append(entry)
	return true


## Takes one item out of a bag slot and returns its entry, or {} for an empty slot.
func take_from_bag(index: int) -> Dictionary:
	if index < 0 or index >= bag.size():
		return {}
	var stack: Dictionary = bag[index]
	var left: int = int(stack["count"]) - 1
	if left <= 0:
		bag.remove_at(index)
		return stack
	stack["count"] = left
	return {"id": stack["id"], "count": 1}


## Wears the gear in a bag slot. Gear already worn in that place goes to the
## same bag slot. Returns false for items that are not gear.
func equip(index: int) -> bool:
	if index < 0 or index >= bag.size():
		return false
	var stack: Dictionary = bag[index]
	var slot: String = ItemDb.items[stack["id"]].get("slot", "")
	if slot == "":
		return false
	var worn: Dictionary = equipment.get(slot, {})
	equipment[slot] = stack
	if worn.is_empty():
		bag.remove_at(index)
	else:
		bag[index] = worn
	return true


## Moves worn gear into the bag. Returns false if nothing is worn there or the
## bag is full.
func unequip(slot: String) -> bool:
	var worn: Dictionary = equipment.get(slot, {})
	if worn.is_empty() or bag.size() >= bag_size:
		return false
	equipment.erase(slot)
	bag.append(worn)
	return true


## Takes worn gear off without keeping it (it is dropped). Returns its entry, or {}.
func remove_equipped(slot: String) -> Dictionary:
	var worn: Dictionary = equipment.get(slot, {})
	equipment.erase(slot)
	return worn


## Tries to raise a piece (an entry in the bag or worn) by one level, using one
## stone from the bag. roll is 0..1 (randf()). Returns "up", "same" (failed,
## level kept), "down" (failed, one level lost), or "" if it cannot be tried.
func upgrade(stack: Dictionary, roll: float) -> String:
	var step: Dictionary = ItemDb.upgrade_step(stack)
	if step.is_empty() or count_of(step["stone"]) <= 0:
		return ""
	_set_count(step["stone"], count_of(step["stone"]) - 1)
	if roll < float(step["chance"]):
		stack["plus"] = int(stack.get("plus", 0)) + 1
		return "up"
	if step.get("on_fail", "stay") == "down" and int(stack.get("plus", 0)) > 0:
		stack["plus"] = int(stack["plus"]) - 1
		return "down"
	return "same"


## XP needed to finish the current level.
func xp_to_next() -> int:
	return int(rules["xp_per_level"]) * level


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
		"equipment": equipment.duplicate(true),
		"stat_points": stat_points.duplicate(),
		"learned_skills": learned_skills.duplicate(),
		"auto_potion": auto_potion,
	}.merged(record.to_dict())


func from_dict(data: Dictionary) -> void:
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	gold = maxi(0, int(data.get("gold", 0)))
	_load_progress(data)
	if int(data.get("version", 1)) < 2:
		# Version 1 kept only a potion count, and the gear could not change yet.
		_start_fresh()
		potions = maxi(0, int(data.get("potions", potions)))
		return
	bag = []
	equipment = {}
	var saved_gear = data.get("equipment", {})
	if saved_gear is Dictionary:
		for slot in saved_gear:
			# Before version 4 a worn piece was only its item id.
			var saved = saved_gear[slot]
			var worn: Dictionary = ItemDb.clean_stack(saved if saved is Dictionary else {"id": saved})
			if not worn.is_empty() and ItemDb.items[worn["id"]].get("slot", "") == slot:
				equipment[slot] = worn
	var saved_bag = data.get("bag", [])
	if saved_bag is Array:
		for stack in saved_bag:
			add_stack(stack if stack is Dictionary else {})


## Version 3 parts. Anything unknown or out of range is left out.
func _load_progress(data: Dictionary) -> void:
	stat_points = {}
	var saved_points = data.get("stat_points", {})
	if saved_points is Dictionary:
		for stat_id in saved_points:
			if stat_rules.has(stat_id) and int(saved_points[stat_id]) > 0:
				stat_points[stat_id] = int(saved_points[stat_id])
	if free_points() < 0:
		stat_points = {}
	var skills: Dictionary = GameData.table("skills")
	learned_skills = []
	var saved_skills = data.get("learned_skills", [])
	if saved_skills is Array:
		for skill_id in saved_skills:
			if skills.has(skill_id) and not learned_skills.has(skill_id):
				learned_skills.append(skill_id)
	record.from_dict(data)
	auto_potion = int(data.get("auto_potion", 0))
	if auto_potion not in auto_potion_choices():
		auto_potion = 0


## Starting gear and bag from the data.
func _start_fresh() -> void:
	equipment = {}
	for slot in rules["starting_gear"]:
		equipment[slot] = ItemDb.gear(rules["starting_gear"][slot])
	bag = []
	for stack in rules["starting_bag"]:
		add_item(stack["id"], int(stack["count"]))


func _stacks(item_id: String) -> bool:
	return ItemDb.items[item_id].get("slot", "") == ""


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
