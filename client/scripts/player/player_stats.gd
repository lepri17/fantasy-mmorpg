extends RefCounted
## Progress of one character: level, XP, gold, the bag, the gear it wears, and
## the numbers that follow from them. Pure data and rules with no scene
## dependencies, so the same logic can move to the server later.

const ItemDb := preload("res://scripts/items/item_db.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const AchievementRecord := preload("res://scripts/player/achievement_record.gd")
const QuestLog := preload("res://scripts/player/quest_log.gd")
const DungeonLog := preload("res://scripts/player/dungeon_log.gd")
const ClassDb := preload("res://scripts/player/class_db.gd")
const Leveling := preload("res://scripts/player/leveling.gd")

## Version of what to_dict() writes. 1 = level, xp, gold, potions.
## 2 = adds the bag and the gear; potions live in the bag.
## 3 = adds stat points, skills learned from books, achievements and the title.
## 4 = gear keeps its own rarity, upgrade level and random options.
## 5 = adds the map the warrior is on.
## 6 = adds the storage in town.
## 7 = adds quests.
## 8 = adds dungeon entries per day.
## 11 = the stats were reworked (AGI became DEX): older saves get their points back.
const SAVE_VERSION := 11
const STATS_REWORK_VERSION := 11
const STATS_REWORK_NOTICE := (
	"The stats were reworked: all your stat points are free to spend again."
)
const POTION_ID := "red_potion"

## The numbers from res://data/character.json: health and damage without gear
## (the starting gear adds 35 HP and 5 damage, so a new warrior has 100 HP and
## 10 damage), what each level adds, the XP curve, bag size, starting gear and
## bag, and the tuning the player scene reads (speed, skill, regeneration).
static var rules: Dictionary = GameData.table("character")
static var bag_size: int = int(rules["bag_size"])
static var storage_size: int = int(rules["storage_size"])
## STR, DEX, VIT, ENE: what one point in each adds ("attack", "max_hp", ...).
static var stat_rules: Dictionary = rules["stats"]

## The class (classes.json) and whether it made its job advancement (version 9).
var class_id: String = ClassDb.DEFAULT
var advanced: bool = false
## The name the player gave the character on the character screen.
var hero_name: String = ""
## The step of the first-minutes hints (tutorial.gd); 8 = done (version 10).
var tutorial: int = 0
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
## Points put into each stat ("strength", "dexterity", "vitality", "energy").
var stat_points: Dictionary = {}
## A message for the player after loading an older save, or "".
var notice: String = ""
## Skills learned from books (skills.json entries with a "book").
var learned_skills: Array = []
## Stacks left with the storage keeper in town, like the bag but bigger.
var storage: Array = []
## Dungeon entries per day (dungeon_log.gd).
var dungeons = DungeonLog.new()
## The map the warrior is on (maps.json id), or "" before he has been anywhere.
var map_id: String = ""
## Drink a red potion by itself below this percent of HP (0 = off).
var auto_potion: int = 0
## Quests taken and finished (quest_log.gd).
var quests = QuestLog.new()
## Achievements, their counters and the title shown (achievement_record.gd).
var record = AchievementRecord.new()


func _init() -> void:
	_start_fresh()


## The auto-potion settings as whole percents (JSON gives floats).
static func auto_potion_choices() -> Array:
	return rules["auto_potion_choices"].map(func(value): return int(value))


## A number or setting from character.json, or the class's own value for it.
func rule(key: String) -> Variant:
	return ClassDb.rule(class_id, key)


func max_hp() -> int:
	var per_level: int = int(rule("hp_per_level"))
	return (
		int(rule("base_max_hp"))
		+ per_level * (level - 1)
		+ gear_bonus("max_hp")
		+ int(extra_bonus("max_hp"))
	)


func attack_damage() -> int:
	var per_level: int = int(rule("damage_per_level"))
	return (
		int(rule("base_damage"))
		+ per_level * (level - 1)
		+ gear_bonus("attack")
		+ int(extra_bonus("attack"))
	)


## Damage taken from each hit goes down by this much (never below 1).
func defense() -> int:
	return int(rule("defense")) + gear_bonus("defense") + int(extra_bonus("defense"))


## Chance (0..1) that a hit is critical.
func crit_chance() -> float:
	return (
		float(rule("crit_chance"))
		+ gear_total("crit_chance")
		+ extra_bonus("crit_chance")
	)


## Chance (0..1) that a monster's hit misses.
func evasion() -> float:
	return float(rule("evasion")) + gear_total("evasion") + extra_bonus("evasion")


## A number from the class rules, the gear, the stat points and the title,
## such as "crit_damage" (extra crit multiplier: 0.2 = crits do +20%),
## "accuracy" (taken off a monster's evasion) or "attack_speed" (0.25 = basic
## attacks 25% faster; player.gd keeps it under combat.json's limit).
func total(stat: String) -> float:
	return float(rule(stat)) + gear_total(stat) + extra_bonus(stat)


func max_stamina() -> float:
	return float(rule("max_stamina")) + gear_total("max_stamina") + extra_bonus("max_stamina")


## Extra skill damage as a fraction (0.1 = +10%).
func skill_damage_bonus() -> float:
	return gear_total("skill_damage") + extra_bonus("skill_damage")


## What the stat points, the title and the job advancement add to one number
## ("attack", "max_hp", "defense", "crit_chance", "crit_damage", "evasion",
## "accuracy", "attack_speed", "max_stamina", "skill_damage"). What a stat
## point gives depends on the class.
func extra_bonus(stat: String) -> float:
	var total: float = 0.0
	for stat_id in stat_points:
		var gives: float = float(ClassDb.stat_rule(class_id, stat_id).get(stat, 0.0))
		total += float(stat_points[stat_id]) * gives
	if advanced:
		total += float(ClassDb.info(class_id)["advanced"].get("bonus", {}).get(stat, 0.0))
	return total + record.title_bonus(stat)


# --- stat points (MU style: every level gives points to put into STR, DEX, VIT, ENE)


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


## Gold for a stat reset: free below "stat_reset_free_below_level", so a new
## player can try builds, then "stat_reset_gold_per_level" for every level.
func reset_cost() -> int:
	if level < int(rules["stat_reset_free_below_level"]):
		return 0
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


## One stat over all the gear worn: own values, random options and upgrades.
func gear_total(stat: String) -> float:
	var total: float = _set_bonus(stat)
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
func _set_bonus(stat: String) -> float:
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
	if slot == "" or not ItemDb.usable_by(stack["id"], class_id):
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


## Takes some of an item out of the bag (a quest's collected items).
func remove_items(item_id: String, count: int) -> bool:
	if count_of(item_id) < count:
		return false
	_set_count(item_id, count_of(item_id) - count)
	return true


## True when all these [{"id", "count"}] would fit in the bag together.
func room_for(entries: Array) -> bool:
	var slots_needed: int = 0
	for entry in entries:
		if ItemDb.is_gear(entry["id"]):
			slots_needed += int(entry.get("count", 1))
		elif _stack_index(entry["id"]) < 0:
			slots_needed += 1
	return bag.size() + slots_needed <= bag_size


## Moves a whole bag slot into storage. Returns false when storage is full.
func store(index: int) -> bool:
	if index < 0 or index >= bag.size():
		return false
	var stack: Dictionary = bag[index]
	if not ItemDb.is_gear(stack["id"]):
		for stored in storage:
			if stored["id"] == stack["id"]:
				stored["count"] = int(stored["count"]) + int(stack["count"])
				bag.remove_at(index)
				return true
	if storage.size() >= storage_size:
		return false
	storage.append(stack)
	bag.remove_at(index)
	return true


## Moves a whole storage slot back into the bag. Returns false when it does not fit.
func take_stored(index: int) -> bool:
	if index < 0 or index >= storage.size():
		return false
	var stack: Dictionary = storage[index]
	if not ItemDb.is_gear(stack["id"]):
		if not add_item(stack["id"], int(stack["count"])):
			return false
	elif bag.size() >= bag_size:
		return false
	else:
		bag.append(stack)
	storage.remove_at(index)
	return true


## XP needed to finish the current level (character.json "xp_curve").
func xp_to_next() -> int:
	return Leveling.xp_for_level(level)


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
		"class": class_id,
		"advanced": advanced,
		"name": hero_name,
		"tutorial": tutorial,
		"level": level,
		"xp": xp,
		"gold": gold,
		"bag": bag.duplicate(true),
		"equipment": equipment.duplicate(true),
		"stat_points": stat_points.duplicate(),
		"learned_skills": learned_skills.duplicate(),
		"auto_potion": auto_potion,
		"map": map_id,
		"storage": storage.duplicate(true),
	}.merged(record.to_dict()).merged(quests.to_dict()).merged(dungeons.to_dict())


func from_dict(data: Dictionary) -> void:
	# Before version 9 every character was a warrior.
	class_id = str(data.get("class", ClassDb.DEFAULT))
	if not ClassDb.exists(class_id):
		class_id = ClassDb.DEFAULT
	advanced = data.get("advanced", false) == true
	hero_name = str(data.get("name", "")).left(16)
	# Heroes from before the hints (they have gear saved) do not get them.
	tutorial = clampi(int(data.get("tutorial", 0 if not data.has("equipment") else 99)), 0, 99)
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	gold = maxi(0, int(data.get("gold", 0)))
	_load_progress(data)
	if int(data.get("version", 1)) < 2 or not data.has("equipment"):
		# Version 1 kept only a potion count, and the gear could not change yet.
		# A new character from the character screen has no gear saved yet either.
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
			if (
				not worn.is_empty()
				and ItemDb.items[worn["id"]].get("slot", "") == slot
				and ItemDb.usable_by(worn["id"], class_id)
			):
				equipment[slot] = worn
	var saved_bag = data.get("bag", [])
	if saved_bag is Array:
		for stack in saved_bag:
			add_stack(stack if stack is Dictionary else {})


## Version 3 parts. Anything unknown or out of range is left out.
func _load_progress(data: Dictionary) -> void:
	stat_points = {}
	notice = ""
	var saved_points = data.get("stat_points", {})
	if saved_points is Dictionary:
		for saved_id in saved_points:
			# Before version 11 DEX was called AGI ("agility").
			var stat_id: String = "dexterity" if saved_id == "agility" else str(saved_id)
			if stat_rules.has(stat_id) and int(saved_points[saved_id]) > 0:
				stat_points[stat_id] = points_in(stat_id) + int(saved_points[saved_id])
	if free_points() < 0:
		stat_points = {}
	if not stat_points.is_empty() and int(data.get("version", 1)) < STATS_REWORK_VERSION:
		# The points do other things now, so the player chooses again for free.
		stat_points = {}
		notice = STATS_REWORK_NOTICE
	var skills: Dictionary = GameData.table("skills")
	learned_skills = []
	var saved_skills = data.get("learned_skills", [])
	if saved_skills is Array:
		for skill_id in saved_skills:
			if (
				skills.has(skill_id)
				and skills[skill_id].get("class", ClassDb.DEFAULT) == class_id
				and not learned_skills.has(skill_id)
			):
				learned_skills.append(skill_id)
	record.from_dict(data)
	quests.from_dict(data)
	dungeons.from_dict(data)
	map_id = str(data.get("map", ""))
	storage = []
	var saved_storage = data.get("storage", [])
	if saved_storage is Array:
		for stack in saved_storage:
			var entry: Dictionary = ItemDb.clean_stack(stack)
			if not entry.is_empty() and storage.size() < storage_size:
				storage.append(entry)
	auto_potion = int(data.get("auto_potion", 0))
	if auto_potion not in auto_potion_choices():
		auto_potion = 0


## The class's starting gear and bag from the data.
func _start_fresh() -> void:
	equipment = {}
	var starting_gear: Dictionary = rule("starting_gear")
	for slot in starting_gear:
		equipment[slot] = ItemDb.gear(starting_gear[slot])
	bag = []
	for stack in rule("starting_bag"):
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
