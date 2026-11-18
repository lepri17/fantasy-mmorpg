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

const GameData := preload("res://scripts/data/game_data.gd")

## Bonuses written as fractions (0.03 = 3%); the rest are whole numbers.
const PERCENT_STATS := ["crit_chance", "evasion", "skill_damage"]

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


## How many items belong to a set.
static func set_size(set_id: String) -> int:
	var total: int = 0
	for item_id in items:
		if items[item_id].get("set", "") == set_id:
			total += 1
	return total


static func is_gear(item_id: String) -> bool:
	return items.has(item_id) and items[item_id].get("slot", "") != ""


## A bag or worn entry for one piece of gear.
static func gear(
	item_id: String, rarity: String = "common", plus: int = 0, options: Dictionary = {}
) -> Dictionary:
	return {"id": item_id, "count": 1, "rarity": rarity, "plus": plus, "options": options.duplicate()}


## A dropped piece: a rarity by weight (rolled `rolls` times, the best kept),
## then that many different random options.
static func roll_gear(item_id: String, rolls: int = 1) -> Dictionary:
	var rarity: String = _roll_rarity()
	for _i in rolls - 1:
		var other: String = _roll_rarity()
		if rarity_rank(other) > rarity_rank(rarity):
			rarity = other
	var stats_left: Array = random_options.keys()
	stats_left.shuffle()
	var options: Dictionary = {}
	for stat in stats_left.slice(0, int(rarities[rarity]["options"])):
		var low: float = float(random_options[stat][0])
		var high: float = float(random_options[stat][1])
		if stat in PERCENT_STATS:
			options[stat] = snappedf(randf_range(low, high), 0.005)
		else:
			options[stat] = randi_range(int(low), int(high))
	return gear(item_id, rarity, 0, options)


## 0 for the most common rarity, then 1, 2, ...
static func rarity_rank(rarity: String) -> int:
	return rarities.keys().find(rarity)


static func rarity_color(stack: Dictionary) -> Color:
	var rarity: Dictionary = rarities.get(stack.get("rarity", ""), rarities.values()[0])
	var rgba: Array = rarity["color"]
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
