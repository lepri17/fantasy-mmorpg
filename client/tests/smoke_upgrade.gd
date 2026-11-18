extends RefCounted
## The gold upgrade part of the smoke test (M5): a + costs gold, more each
## time and on higher gear; the chance falls; a miss keeps the level and makes
## the next try likelier; a stone adds more; nothing breaks; and the upgrade
## window shows it all before any gold is paid. smoke_test.gd runs it after the
## loot part; t is the test (a SceneTree).

const ItemDb = preload("res://scripts/items/item_db.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")

var t = null


func run(test, _main, player, hud) -> void:
	t = test
	_check_rules()
	await _check_window(player, hud)


func _check_rules() -> void:
	var smith = PlayerStats.new()
	var sword: Dictionary = ItemDb.gear("training_sword")
	smith.gold = 0
	t._check(smith.upgrade(sword, 0.0) == "", "no upgrade without the gold")
	smith.gold = 100000
	var paid: int = 0
	for i in 3:
		paid += ItemDb.upgrade_cost(sword)
		smith.upgrade(sword, 0.99)
	t._check(
		int(sword["plus"]) == 3 and smith.gold == 100000 - paid,
		"+1 to +3 never miss, and each costs gold (%d in all)" % paid
	)
	var per_plus: float = float(ItemDb.upgrades["per_plus"]["weapon"]["attack"])
	var own: float = float(ItemDb.items["training_sword"]["attack"])
	t._check(
		is_equal_approx(ItemDb.stat_of(sword, "attack"), own + 3 * per_plus),
		"each + adds attack to a sword"
	)
	var deep: Dictionary = ItemDb.gear("elderwood_blade", "common", 3)
	var deep_own: float = float(ItemDb.items["elderwood_blade"]["attack"])
	t._check(
		(
			ItemDb.upgrade_cost({"id": "training_sword", "plus": 4}) > ItemDb.upgrade_cost(sword)
			and ItemDb.upgrade_cost(deep) > ItemDb.upgrade_cost(sword)
			and ItemDb.stat_of(deep, "attack") - deep_own > 3 * per_plus
		),
		"a + costs more each time and on higher gear, where it also adds more"
	)
	sword["plus"] = 6
	var chance: float = float(ItemDb.upgrade_step(sword)["chance"])
	t._check(
		smith.upgrade(sword, 0.99) == "same" and int(sword["plus"]) == 6 and sword["misses"] == 1,
		"a miss keeps +6"
	)
	var next_chance: float = float(ItemDb.upgrade_step(sword)["chance"])
	t._check(
		is_equal_approx(next_chance, chance + float(ItemDb.upgrades["miss_bonus"])),
		"and makes its next try likelier (%d%% -> %d%%)" % [chance * 100, next_chance * 100]
	)
	smith.add_item("ember_stone", 1)
	t._check(
		(
			smith.upgrade(sword, next_chance + 0.05, true) == "up"
			and smith.count_of("ember_stone") == 0
			and not sword.has("misses")
		),
		"an Ember Stone adds its bonus and is used up; a success clears the misses"
	)
	sword["plus"] = 9
	t._check(ItemDb.upgrade_step(sword)["stone"] == "moon_stone", "from +9 a Moon Stone helps")
	sword["plus"] = 12
	t._check(
		smith.upgrade(sword, 0.99) == "same" and int(sword["plus"]) == 12,
		"high up a miss still keeps the level: nothing breaks or falls"
	)
	var saved = PlayerStats.new()
	smith.bag = [sword]
	saved.from_dict(smith.to_dict())
	t._check(
		int(saved.bag[0].get("misses", 0)) == 1 and int(saved.bag[0]["plus"]) == 12,
		"a piece's misses are kept in the save"
	)
	sword["plus"] = 15
	t._check(
		ItemDb.upgrade_step(sword).is_empty() and ItemDb.display_name(sword) == "Training Sword +15",
		"+15 is the top, and the name shows it"
	)


func _check_window(player, hud) -> void:
	var stats = player.stats
	var saved_gold: int = stats.gold
	var saved_bag: Array = stats.bag.duplicate(true)
	var saved_weapon: Dictionary = stats.equipment.get("weapon", {}).duplicate(true)
	stats.gold = 5000
	stats.bag.clear()
	stats.equipment["weapon"] = ItemDb.gear("training_sword")
	if not hud.get_node("Inventory").visible:
		hud.toggle_inventory()
	var inventory = hud.get_node("Inventory")
	inventory.refresh(stats, null)
	inventory.call("_on_slot_tapped", inventory.gear_slots["weapon"])
	t._check(
		"Next +1: 30 gold, 100%" in inventory.get("_info_label").text,
		"the details show the next +'s gold and chance"
	)
	inventory.call("_on_upgrade_pressed")
	var window = hud.get_node("Upgrade")
	var body: String = window.get("_body").text
	t._check(
		(
			window.visible
			and "Cost: 30 gold (you have 5000)" in body
			and "Chance: 100%" in body
			and "ATK" in body
		),
		"UPGRADE first shows what the + adds, its cost and chance (%s)" % body.replace("\n", " / ")
	)
	t._check(
		stats.gold == 5000 and int(stats.equipment["weapon"]["plus"]) == 0,
		"and nothing is paid before the button"
	)
	window.get("_confirm_button").pressed.emit()
	await t._frames(1)
	t._check(
		(
			int(stats.equipment["weapon"]["plus"]) == 1
			and stats.gold == 4970
			and window.visible
			and window.get("_result").text == "Success! Now +1."
			and "+1 → +2" in window.get("_title").text
		),
		"it pays, upgrades, says so, and stays open for the next try"
	)
	stats.equipment["weapon"]["plus"] = 4
	stats.add_item("ember_stone", 1)
	window.refresh(stats)
	var stone_button: Button = window.get("_stone_button")
	var before: String = window.get("_body").text
	stone_button.pressed.emit()
	t._check(
		(
			stone_button.visible
			and "Ember Stone" in stone_button.text
			and "Chance: 90%" in before
			and "Chance: 100%" in window.get("_body").text
		),
		"a stone can be added for a better chance, shown before the try"
	)
	window.set("_tried_at", 4)
	window.refresh(stats)
	t._check(
		window.get("_result").text.begins_with("Missed. It stays +4."),
		"a miss says the level stays and the next try's chance"
	)
	stats.gold = 0
	window.refresh(stats)
	t._check(window.get("_confirm_button").disabled, "without the gold the button waits")
	player.unequip("weapon")
	window.refresh(stats)
	t._check(
		window.visible and window.get("place") == "bag" and "Training Sword" in window.get("_title").text,
		"the window follows the piece into the bag"
	)
	hud.toggle_inventory()
	t._check(not window.visible, "closing the bag closes the upgrade window")
	stats.gold = saved_gold
	stats.bag = saved_bag
	if saved_weapon.is_empty():
		stats.equipment.erase("weapon")
	else:
		stats.equipment["weapon"] = saved_weapon
