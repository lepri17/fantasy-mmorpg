extends RefCounted
## The loot part of the smoke test: the gear a monster drops comes from its
## level (ItemDb.drop_pool), random bonuses grow with the piece's level and
## start higher on rarer pieces, the Elderwood set, a boss dropping several
## good pieces, the beam of light over rare drops, and the Options line in the
## bag. smoke_test.gd runs it last; t is the test (a SceneTree).

const ItemDb = preload("res://scripts/items/item_db.gd")
const PICKUP_SCENE = preload("res://scenes/items/pickup.tscn")
const JOB_GEAR := ["champion_cape", "azure_hood", "starlit_hat"]

var t = null


func run(test, main, player, hud) -> void:
	t = test
	_check_pools()
	_check_ranges()
	_check_rolls()
	await _check_boss(main, player)
	await _check_window(player, hud)
	main.change_map("town")
	await t._frames(3)


func _check_pools() -> void:
	var low: Array = ItemDb.drop_pool(1)
	var deep: Array = ItemDb.drop_pool(15)
	t._check(
		not low.is_empty() and low.all(func(i): return ItemDb.required_level(i) <= 3),
		"a level 1 monster drops gear of level 3 at most (%d pieces)" % low.size()
	)
	t._check(
		"elderwood_blade" in deep and deep.all(func(i): return ItemDb.required_level(i) >= 9),
		"a level 15 monster drops gear near its level (%s)" % ", ".join(deep)
	)
	var given: bool = false
	for level in range(1, 21):
		for item_id in JOB_GEAR:
			given = given or item_id in ItemDb.drop_pool(level)
	t._check(not given, "job gear is only given, never dropped")
	t._check(
		ItemDb.set_size("elderwood") == 12 and ItemDb.set_size("elderwood", "warrior") == 6,
		"the Elderwood set has 12 pieces, 6 that each class can wear"
	)


func _check_ranges() -> void:
	var first: Vector2 = ItemDb.option_range("attack", "training_sword", "common")
	var deep: Vector2 = ItemDb.option_range("attack", "elderwood_blade", "common")
	var rare: Vector2 = ItemDb.option_range("attack", "elderwood_blade", "rare")
	var epic: Vector2 = ItemDb.option_range("attack", "elderwood_blade", "epic")
	t._check(
		deep.y > first.y and rare.x > deep.x and epic.x > rare.x and epic.y == deep.y,
		"bonuses grow with the piece's level and start higher on rarer pieces (%s %s %s %s)"
		% [first, deep, rare, epic]
	)


func _check_rolls() -> void:
	var good: bool = true
	var inside: bool = true
	for i in 40:
		var piece: Dictionary = ItemDb.roll_gear("elderwood_cape", 1, "rare")
		var options: Dictionary = piece.get("options", {})
		good = (
			good
			and ItemDb.rarity_rank(piece["rarity"]) >= ItemDb.rarity_rank("rare")
			and options.size() == int(ItemDb.rarities[piece["rarity"]]["options"])
		)
		for stat in options:
			var span: Vector2 = ItemDb.option_range(stat, piece["id"], piece["rarity"])
			inside = inside and options[stat] >= span.x - 0.001 and options[stat] <= span.y + 0.001
	t._check(good, "a roll with a lowest rarity of rare is never below it, with its bonuses")
	t._check(inside, "every random bonus is inside its range")


func _check_boss(main, player) -> void:
	main.change_map("grove", "south")
	await t._frames(3)
	main.bosses.appear("stormcrest_roc", "grove")
	var boss = main.bosses.node_of("stormcrest_roc")
	t._check(boss != null, "the Stormcrest Roc can come down in Elder Grove")
	if boss == null:
		return
	boss.set_physics_process(false)
	player.global_position = boss.global_position + Vector2(0, 700)  # out of reach of the loot
	boss.set("_player", player)
	var before: Array = t.get_nodes_in_group("pickups")
	boss.call("_maybe_drop_gear")
	await t._frames(2)
	main.bosses.leave("stormcrest_roc")
	var dropped: Array = t.get_nodes_in_group("pickups").filter(
		func(p): return not p in before and not p.get("stack").is_empty()
	)
	var class_id: String = player.stats.class_id
	var all_good: bool = dropped.size() == 3
	for pickup in dropped:
		var piece: Dictionary = pickup.get("stack")
		var rarity: Dictionary = ItemDb.rarities[piece["rarity"]]
		all_good = (
			all_good
			and ItemDb.rarity_rank(piece["rarity"]) >= ItemDb.rarity_rank("rare")
			and ItemDb.usable_by(piece["id"], class_id)
			and ItemDb.required_level(piece["id"]) >= 12
			and is_equal_approx(pickup.get("lifetime"), float(rarity["ground_seconds"]))
			and pickup.has_beam()
		)
	t._check(
		all_good,
		"the Stormcrest Roc drops 3 pieces for the hero's class, rare or better, in a beam of light"
	)
	var plain = PICKUP_SCENE.instantiate()
	plain.set("stack", ItemDb.gear("leather_boots"))
	t._check(not plain.has_beam(), "a common piece has no beam")
	plain.free()
	if dropped.is_empty():
		return
	var saved_bag: Array = player.stats.bag.duplicate(true)
	player.stats.bag.clear()
	var piece: Dictionary = dropped[0].get("stack").duplicate(true)
	player.global_position = dropped[0].global_position
	await t._frames(4)
	t._check(player.stats.bag.has(piece), "picking it up keeps the piece whole")
	for pickup in dropped:
		if is_instance_valid(pickup):
			pickup.queue_free()
	player.stats.bag = saved_bag


func _check_window(player, hud) -> void:
	var stats = player.stats
	var saved_bag: Array = stats.bag.duplicate(true)
	var options := {"attack": 6, "crit_chance": 0.03, "max_hp": 30}
	stats.bag = [ItemDb.gear("elderwood_gloves", "epic", 0, options)]
	if not hud.get_node("Inventory").visible:
		hud.toggle_inventory()
	var inventory = hud.get_node("Inventory")
	inventory.refresh(stats, null)
	inventory.call("_on_slot_tapped", inventory.bag_slots[0])
	var details: String = inventory.get("_info_label").text
	t._check(
		"Options: " in details and "+6 ATK (5~7)" in details and "+3% CRIT (3~4.5%)" in details,
		"the bag shows each random bonus with its range (%s)" % details.replace("\n", " / ")
	)
	t._check(
		"Elderwood Set %d/6" % int(stats.set_pieces().get("elderwood", 0)) in details,
		"and counts the set pieces the hero's class can wear"
	)
	stats.bag = saved_bag
	hud.toggle_inventory()
	inventory.refresh(stats, null)
