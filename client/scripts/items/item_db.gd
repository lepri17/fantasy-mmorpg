extends RefCounted
## Every item in the game, from res://data/items.json: its name, the gear slot
## it is worn in ("" = not worn), icon, bonuses and a short text.
##
## Bonuses: "attack" adds to the sword damage, "max_hp" to maximum health.
## "usable" items can be used from the bag; "world_icon" is the picture on the
## ground when it should differ from the inventory icon; potions have
## "heal_fraction".
##
## The bag and the worn gear hold entries: {"id", "count"}. Gear entries also
## keep their own "rarity", "plus" (upgrade level) and "options" (random
## bonuses), so two swords can differ.

const Settings := preload("res://scripts/settings.gd")
const GameData := preload("res://scripts/data/game_data.gd")

## Bonuses written as fractions (0.03 = 3%); the rest are whole numbers.
const PERCENT_STATS := [
	"crit_chance", "crit_damage", "evasion", "accuracy", "attack_speed", "skill_damage"
]

## Item id -> its fields.
static var items: Dictionary = GameData.table("items")["items"]
## Gear slots in the order the inventory shows them: left column, then right.
static var gear_slots: Array = GameData.table("items")["gear_slots"]
static var slot_names: Dictionary = GameData.table("items")["slot_names"]
## Gear rarities from the most common up: name, color, how many random options
## a piece gets, and how often it drops (weight).
static var rarities: Dictionary = GameData.table("items")["rarities"]
## Stat -> [lowest, highest] for the random options on dropped gear.
static var random_options: Dictionary = GameData.table("items")["random_options"]
## +1..+15 upgrades; empty when the data has none.
static var upgrades: Dictionary = GameData.table("items").get("upgrades", {})
## A shop pays this part of an item's price when buying it back.
static var sell_fraction: float = float(GameData.table("items").get("sell_fraction", 0.25))
## Set id -> {"name", "bonuses": {"<pieces worn>": {stat: value}}}.
static var sets: Dictionary = GameData.table("items").get("sets", {})


static func price(item_id: String) -> int:
	return int(items[item_id].get("price", 0))


## What a shop pays for one of this entry: part of the price, more for rarer
## and upgraded gear.
static func sell_price(stack: Dictionary) -> int:
	var value: float = price(stack["id"]) * sell_fraction
	if is_gear(stack["id"]):
		value *= 1.0 + rarity_rank(stack.get("rarity", "")) * 0.75
		value += int(stack.get("plus", 0)) * 10
	return maxi(1, floori(value))


## How many items belong to a set: those a class can wear when one is given.
static func set_size(set_id: String, class_id: String = "") -> int:
	var total: int = 0
	for item_id in items:
		if items[item_id].get("set", "") == set_id:
			if class_id == "" or usable_by(item_id, class_id):
				total += 1
	return total


## True when the class may wear the item (items.json "classes"; none = every class).
static func usable_by(item_id: String, class_id: String) -> bool:
	var classes: Array = items.get(item_id, {}).get("classes", [])
	return classes.is_empty() or classes.has(class_id)


## The level a hero needs to wear the item (items.json "level"; 1 when not set).
static func required_level(item_id: String) -> int:
	return maxi(1, int(items.get(item_id, {}).get("level", 1)))


## True when a hero of this class and level may wear the piece now.
static func can_wear(item_id: String, class_id: String, level: int) -> bool:
	return is_gear(item_id) and usable_by(item_id, class_id) and level >= required_level(item_id)


static func is_gear(item_id: String) -> bool:
	return items.has(item_id) and items[item_id].get("slot", "") != ""


## A bag or worn entry for one piece of gear.
static func gear(
	item_id: String, rarity: String = "common", plus: int = 0, options: Dictionary = {}
) -> Dictionary:
	return {"id": item_id, "count": 1, "rarity": rarity, "plus": plus, "options": options.duplicate()}


## A dropped piece: a rarity by weight (rolled `rolls` times, the best kept,
## never below min_rarity), then that many different random options, each in
## its option_range.
static func roll_gear(item_id: String, rolls: int = 1, min_rarity: String = "") -> Dictionary:
	var rarity: String = _roll_rarity()
	for _i in rolls - 1:
		var other: String = _roll_rarity()
		if rarity_rank(other) > rarity_rank(rarity):
			rarity = other
	if rarity_rank(min_rarity) > rarity_rank(rarity):
		rarity = min_rarity
	var stats_left: Array = random_options.keys()
	stats_left.shuffle()
	var options: Dictionary = {}
	for stat in stats_left.slice(0, int(rarities[rarity]["options"])):
		var span: Vector2 = option_range(stat, item_id, rarity)
		if stat in PERCENT_STATS:
			options[stat] = snappedf(randf_range(span.x, span.y), 0.005)
		else:
			options[stat] = randi_range(int(span.x), int(span.y))
	return gear(item_id, rarity, 0, options)


## What a random option can roll on this piece: the items.json range, grown
## with the piece's level ("option_growth"), and starting higher up the range
## for rarer pieces (the rarity's "roll_floor").
static func option_range(stat: String, item_id: String, rarity: String) -> Vector2:
	var growth: Dictionary = GameData.table("items").get("option_growth", {})
	var per_level: float = float(growth.get("percent" if stat in PERCENT_STATS else "whole", 0.0))
	var grown: float = 1.0 + (required_level(item_id) - 1) * per_level
	var low: float = float(random_options[stat][0]) * grown
	var high: float = float(random_options[stat][1]) * grown
	low += (high - low) * float(rarities.get(rarity, {}).get("roll_floor", 0.0))
	if stat in PERCENT_STATS:
		return Vector2(snappedf(low, 0.005), snappedf(high, 0.005))
	return Vector2(roundi(low), roundi(high))


## The gear a monster of this level can drop: every piece whose level is in
## the items.json "drop_levels" window round it, except gear that is only
## ever given ("no_drop", such as job gear).
static func drop_pool(monster_level: int) -> Array:
	var window: Array = GameData.table("items").get("drop_levels", [-6, 2])
	var pool: Array = []
	for item_id in items:
		if not is_gear(item_id) or items[item_id].get("no_drop", false):
			continue
		var level: int = required_level(item_id)
		if level >= monster_level + int(window[0]) and level <= monster_level + int(window[1]):
			pool.append(item_id)
	return pool


## 0 for the most common rarity, then 1, 2, ...
static func rarity_rank(rarity: String) -> int:
	return rarities.keys().find(rarity)


static func rarity_color(stack: Dictionary) -> Color:
	var rarity: Dictionary = rarities.get(stack.get("rarity", ""), rarities.values()[0])
	var rgba: Array = rarity["color"]
	if Settings.get_value("colorblind") == true and rarity.has("colorblind_color"):
		rgba = rarity["colorblind_color"]  # U7: colours told apart with any colour vision
	return Color(rgba[0], rgba[1], rgba[2], rgba[3])


## True for gear better than the most common rarity.
static func is_special(stack: Dictionary) -> bool:
	return rarity_rank(stack.get("rarity", "")) > 0


## One stat of one entry: the item's own value, its random option and its
## upgrade level.
static func stat_of(stack: Dictionary, stat: String) -> float:
	var item: Dictionary = items[stack["id"]]
	var total: float = float(item.get(stat, 0.0)) + float(stack.get("options", {}).get(stat, 0.0))
	var plus: int = int(stack.get("plus", 0))
	if plus > 0:
		var per_plus: Dictionary = upgrades.get("per_plus", {}).get(item.get("slot", ""), {})
		total += plus * float(per_plus.get(stat, 0.0))
	return total


## The upgrade rule for the next level of a piece ({"up_to", "stone", "chance",
## "on_fail"}), or {} when it cannot go higher.
static func upgrade_step(stack: Dictionary) -> Dictionary:
	var plus: int = int(stack.get("plus", 0))
	if not is_gear(stack.get("id", "")) or plus >= int(upgrades.get("max_plus", 0)):
		return {}
	for step in upgrades.get("steps", []):
		if plus < int(step["up_to"]):
			return step
	return {}


## "Training Sword +3"; "Rare Training Sword +3" with_rarity, for gear above common.
static func display_name(stack: Dictionary, with_rarity: bool = false) -> String:
	var text: String = items[stack["id"]]["name"]
	var plus: int = int(stack.get("plus", 0))
	if plus > 0:
		text += " +%d" % plus
	if with_rarity and is_special(stack):
		text = "%s %s" % [rarities[stack["rarity"]]["name"], text]
	return text


## The bag in a tidy order: gear this class can wear (by slot, then the
## highest level, rarity and upgrade first), other gear, things to use, then
## the rest. Entries that tie keep their order.
static func sorted_bag(bag: Array, class_id: String) -> Array:
	var keyed: Array = []
	for i in bag.size():
		keyed.append([_sort_key(bag[i], class_id), i, bag[i]])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return keyed.map(func(entry): return entry[2])


## A safe copy of a saved or dropped entry, or {} for an unknown item.
static func clean_stack(stack) -> Dictionary:
	if not stack is Dictionary or not items.has(stack.get("id", "")):
		return {}
	var item_id: String = stack["id"]
	if not is_gear(item_id):
		return {"id": item_id, "count": maxi(1, int(stack.get("count", 1)))}
	var rarity: String = str(stack.get("rarity", ""))
	if not rarities.has(rarity):
		rarity = rarities.keys()[0]
	var options: Dictionary = {}
	var saved = stack.get("options", {})
	if saved is Dictionary:
		for stat in saved:
			if random_options.has(stat):
				if stat in PERCENT_STATS:
					options[stat] = float(saved[stat])
				else:
					options[stat] = roundi(float(saved[stat]))
	var plus: int = clampi(int(stack.get("plus", 0)), 0, int(upgrades.get("max_plus", 15)))
	return gear(item_id, rarity, plus, options)


static func _sort_key(stack: Dictionary, class_id: String) -> int:
	var item_id: String = stack["id"]
	if is_gear(item_id):
		var group: int = 0 if usable_by(item_id, class_id) else 1
		return (
			group * 10000000
			+ gear_slots.find(items[item_id]["slot"]) * 100000
			+ (99 - required_level(item_id)) * 1000
			+ (9 - rarity_rank(stack.get("rarity", ""))) * 100
			+ (99 - int(stack.get("plus", 0)))
		)
	var group: int = 2 if items[item_id].get("usable", false) else 3
	return group * 10000000 + items.keys().find(item_id)


static func _roll_rarity() -> String:
	var total: float = 0.0
	for rarity in rarities:
		total += float(rarities[rarity]["weight"])
	var roll: float = randf() * total
	for rarity in rarities:
		roll -= float(rarities[rarity]["weight"])
		if roll < 0.0:
			return rarity
	return rarities.keys()[0]
