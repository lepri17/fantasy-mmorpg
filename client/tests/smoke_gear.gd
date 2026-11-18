extends RefCounted
## The equipment part of the smoke test: the level a piece needs, what wearing
## a piece really changes (GearPreview), every random option doing something,
## sorting the bag, and the inventory window and shop showing it all.
## smoke_test.gd runs it after the progression part; t is the test (a SceneTree).

const ItemDb = preload("res://scripts/items/item_db.gd")
const GearPreview = preload("res://scripts/items/gear_preview.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const ShopPanel = preload("res://scripts/ui/shop_panel.gd")

var t = null


func run(test, _main, player, hud) -> void:
	t = test
	_check_levels()
	_check_preview()
	_check_every_option()
	_check_sorting()
	await _check_window(player, hud)


func _check_levels() -> void:
	t._check(
		(
			ItemDb.required_level("training_sword") == 1
			and ItemDb.required_level("verdant_headband") == 3
			and ItemDb.required_level("crimson_sword") == 6
			and ItemDb.required_level("champion_cape") == 10
		),
		"gear needs a level: starting gear 1, Verdant 3, Crimson 6, job gear 10"
	)
	var hero = PlayerStats.new()
	hero.bag = [ItemDb.gear("verdant_headband")]
	t._check(
		not hero.equip(0) and hero.bag.size() == 1,
		"a level 1 warrior cannot wear the Verdant Headband"
	)
	hero.level = 3
	t._check(
		hero.equip(0) and hero.equipped_id("head") == "verdant_headband",
		"at level 3 he can wear it"
	)
	var news: Array = ["swift_boots", "hawk_gloves", "duelist_cape"]
	var new_stats: bool = true
	for item_id in news:
		new_stats = new_stats and ItemDb.is_gear(item_id) and ItemDb.required_level(item_id) > 1
	t._check(
		(
			new_stats
			and ItemDb.stat_of(ItemDb.gear("swift_boots"), "attack_speed") > 0.0
			and ItemDb.stat_of(ItemDb.gear("hawk_gloves"), "accuracy") > 0.0
			and ItemDb.stat_of(ItemDb.gear("duelist_cape"), "crit_damage") > 0.0
		),
		"the sample items carry the new stats and need a level"
	)


func _check_preview() -> void:
	var hero = PlayerStats.new()
	hero.level = 6
	var now: Dictionary = GearPreview.numbers(hero)
	t._check(
		GearPreview.changes(now, GearPreview.numbers(GearPreview.copy_of(hero))).is_empty(),
		"a copy of the hero has the same numbers"
	)
	hero.bag = [
		ItemDb.gear("crimson_sword"),
		ItemDb.gear("hawk_gloves"),
		ItemDb.gear("verdant_cape"),
		ItemDb.gear("short_bow"),
	]
	var bag_before: Array = hero.bag.duplicate(true)
	var worn_before: Dictionary = hero.equipment.duplicate(true)
	var sword: Dictionary = GearPreview.changes(now, GearPreview.if_worn(hero, 0))
	t._check(
		sword.keys() == ["attack"] and is_equal_approx(sword["attack"], 4.0),
		"the Crimson Sword shows +4 attack over the Training Sword (%s)" % str(sword)
	)
	t._check(GearPreview.is_better(hero, 0), "so it is better with no loss")
	var gloves: Dictionary = GearPreview.changes(now, GearPreview.if_worn(hero, 1))
	t._check(
		(
			gloves.get("crit_chance", 0.0) < 0.0
			and gloves.get("accuracy", 0.0) > 0.0
			and not GearPreview.is_better(hero, 1)
		),
		"Hawk Gloves trade crit chance for accuracy, so no arrow (%s)" % str(gloves)
	)
	var plain_cape: float = GearPreview.changes(now, GearPreview.if_worn(hero, 2))["max_hp"]
	hero.equipment["head"] = ItemDb.gear("verdant_headband")
	var with_set: Dictionary = GearPreview.changes(
		GearPreview.numbers(hero), GearPreview.if_worn(hero, 2)
	)
	var set_bonus: float = float(ItemDb.sets["verdant"]["bonuses"]["2"]["max_hp"])
	t._check(
		is_equal_approx(with_set["max_hp"], plain_cape + set_bonus),
		"the preview counts the set bonus a second Verdant piece gives (%s)" % str(with_set)
	)
	hero.equipment = worn_before.duplicate(true)
	t._check(
		GearPreview.if_worn(hero, 3).is_empty() and not GearPreview.is_better(hero, 3),
		"an archer's bow cannot be tried on by a warrior"
	)
	t._check(
		hero.bag == bag_before and hero.equipment == worn_before,
		"trying gear on never changes the real hero"
	)


## Each random option a piece can roll changes the hero number it names.
func _check_every_option() -> void:
	var hero = PlayerStats.new()
	hero.level = 6
	var nothing: Array = []
	for stat in ItemDb.random_options:
		var low = ItemDb.random_options[stat][0]
		hero.bag = [ItemDb.gear("leather_gloves", "uncommon", 0, {stat: low})]
		var change: Dictionary = GearPreview.changes(
			GearPreview.numbers(hero), GearPreview.if_worn(hero, 0)
		)
		if not change.has(stat):
			nothing.append(stat)
	t._check(
		nothing.is_empty(),
		"every random option changes the hero's number (%s)" % ", ".join(nothing)
	)


func _check_sorting() -> void:
	var bag: Array = [
		{"id": "ember_stone", "count": 2},
		ItemDb.gear("short_bow"),
		{"id": "red_potion", "count": 3},
		ItemDb.gear("leather_boots"),
		ItemDb.gear("training_sword"),
		ItemDb.gear("crimson_sword"),
		ItemDb.gear("training_sword", "rare"),
	]
	var order: Array = ItemDb.sorted_bag(bag, "warrior").map(_short_name)
	var wanted: Array = [
		"crimson_sword",
		"training_sword rare",
		"training_sword",
		"leather_boots",
		"short_bow",
		"red_potion",
		"ember_stone",
	]
	t._check(
		order == wanted,
		"SORT puts this hero's gear first, best first, then other gear, potions, stones (%s)"
		% ", ".join(order)
	)


func _short_name(entry: Dictionary) -> String:
	return entry["id"] + (" rare" if entry.get("rarity", "") == "rare" else "")


func _check_window(player, hud) -> void:
	var stats = player.stats
	var saved_bag: Array = stats.bag.duplicate(true)
	var saved_gloves: Dictionary = stats.equipment.get("gloves", {}).duplicate(true)
	var saved_level: int = stats.level
	stats.level = 4
	stats.equipment["gloves"] = ItemDb.gear("leather_gloves")
	stats.bag = [
		ItemDb.gear("short_bow"),
		{"id": "red_potion", "count": 3},
		ItemDb.gear("crimson_sword"),
		{"id": "ember_stone", "count": 2},
		ItemDb.gear("leather_gloves", "rare", 0, {"crit_damage": 0.1}),
	]
	if not hud.get_node("Inventory").visible:
		hud.toggle_inventory()
	var inventory = hud.get_node("Inventory")
	inventory.refresh(stats, null)
	var marks: Array = []
	for i in 5:
		marks.append(inventory.bag_slots[i].mark)
	t._check(
		marks == ["other", "", "locked", "", "better"],
		"the bag marks another class's gear, a piece that needs a level, and a better one (%s)"
		% str(marks)
	)
	var numbers: String = inventory.get("_stats_label").text
	t._check(
		"ACC" in numbers and "SPD" in numbers and "(x1." in numbers,
		"the window shows accuracy, attack speed and crit damage"
	)
	inventory.call("_on_slot_tapped", inventory.bag_slots[2])
	var details: String = inventory.get("_info_label").text
	t._check(
		"Needs level 6 (you are 4)." in details,
		"a piece that needs a higher level says so (%s)" % details.replace("\n", " / ")
	)
	inventory.call("_on_slot_tapped", inventory.bag_slots[4])
	details = inventory.get("_info_label").text
	t._check(
		"If worn: +10% CRIT DMG" in details and "Gives: +1 ATK, +3% CRIT, +10% CRIT DMG" in details,
		"the details show crit damage and what wearing it changes (%s)" % details.replace("\n", " / ")
	)
	var said: Array = []
	var listen := func(text: String, _color: Color) -> void: said.append(text)
	player.message.connect(listen)
	player.equip_from_bag(2)
	player.message.disconnect(listen)
	t._check(
		stats.equipped_id("weapon") != "crimson_sword" and said.has("You need level 6 to wear that."),
		"equipping it is refused with a message (%s)" % ", ".join(said)
	)
	var sort_button: Button = null
	for button in inventory.find_children("*", "Button", true, false):
		if button.text == "SORT":
			sort_button = button
	sort_button.pressed.emit()
	await t._frames(1)
	t._check(
		stats.bag.map(_short_name) == [
			"crimson_sword", "leather_gloves rare", "short_bow", "red_potion", "ember_stone"
		],
		"the SORT button sorts the bag (%s)" % ", ".join(stats.bag.map(_short_name))
	)
	t._check(
		ShopPanel._item_info("swift_boots") == "Lv 5 +8 HP, +6% SPD",
		"the shop shows a piece's bonuses and level (%s)" % ShopPanel._item_info("swift_boots")
	)
	stats.bag = saved_bag
	stats.level = saved_level
	if saved_gloves.is_empty():
		stats.equipment.erase("gloves")
	else:
		stats.equipment["gloves"] = saved_gloves
	hud.toggle_inventory()
	inventory.refresh(stats, null)
