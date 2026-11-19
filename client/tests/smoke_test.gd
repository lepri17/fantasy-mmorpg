extends SceneTree
## Headless smoke test: really runs the main scene in Godot and checks the
## basics (walking, obstacles, combat, loot, levels, skill, potion, death, save).
##
## Run from the client folder:
##   godot --headless -s res://tests/smoke_test.gd
## Exit code 0 = all checks passed. It uses its own save file, so the real
## save on this computer is left alone.

const SAVE_PATH := "user://smoke_test_save.cfg"
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")
const CombatRules = preload("res://scripts/combat/combat_rules.gd")
const SlimeScript = preload("res://scripts/enemies/slime.gd")
const AchievementRecord = preload("res://scripts/player/achievement_record.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const HeroLook = preload("res://scripts/player/hero_look.gd")
const GameScript = preload("res://scripts/game.gd")
const SmokeWorld = preload("res://tests/smoke_world.gd")
const SmokeClasses = preload("res://tests/smoke_classes.gd")
const SmokeUi = preload("res://tests/smoke_ui.gd")
const SmokeCombat = preload("res://tests/smoke_combat.gd")
const SmokeProgress = preload("res://tests/smoke_progress.gd")
const SmokeGear = preload("res://tests/smoke_gear.gd")
const SmokeForest = preload("res://tests/smoke_forest.gd")
const SmokeLoot = preload("res://tests/smoke_loot.gd")
const SmokeUpgrade = preload("res://tests/smoke_upgrade.gd")
const SmokeLake = preload("res://tests/smoke_lake.gd")
const SmokeRidge = preload("res://tests/smoke_ridge.gd")
const SmokeRuins = preload("res://tests/smoke_ruins.gd")
const SmokeFrost = preload("res://tests/smoke_frost.gd")
const SmokeBosses = preload("res://tests/smoke_bosses.gd")
const SmokeTowns = preload("res://tests/smoke_towns.gd")
const SmokeEvents = preload("res://tests/smoke_events.gd")
const MapEvents = preload("res://scripts/world/map_events.gd")
const RoamingBosses = preload("res://scripts/world/roaming_bosses.gd")
const Settings = preload("res://scripts/settings.gd")
const SETTINGS_PATH := "user://smoke_test_settings.cfg"

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	SaveFile.path = SAVE_PATH
	Settings.path = SETTINGS_PATH  # the default settings, whatever the computer has saved
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	Settings.load_file()
	_remove_test_save()
	SlimeScript.elite_chance_override = 0.0  # random elites would change the numbers below
	seed(20261118)  # the same drops on every run
	GameScript.invasions_enabled = false  # the clock must not start one mid-test
	RoamingBosses.enabled = false  # nor bring a boss
	MapEvents.enabled = false  # nor an event
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)

	var player = get_first_node_in_group("player")
	_check(player != null, "player exists")
	if player == null:
		quit(1)
		return
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
	var blue_slimes: Array = get_nodes_in_group("enemies").filter(
		func(enemy): return enemy.get("monster_id") == "blue_slime"
	)
	_check(
		blue_slimes.size() == 2 and blue_slimes[0].level == 3 and blue_slimes[0].max_hp == 110,
		"blue slimes take their numbers from monsters.json"
	)
	var enemies: Array = get_nodes_in_group("enemies")
	var meadow_navigation = main.map.get_node_or_null("Navigation")
	_check(
		meadow_navigation != null and meadow_navigation.navigation_polygon.get_polygon_count() > 0,
		"the meadow has a navigation mesh"
	)
	if meadow_navigation != null:
		var around_tree: PackedVector2Array = NavigationServer2D.map_get_path(
			meadow_navigation.get_navigation_map(), Vector2(300, 220), Vector2(300, 380), true
		)
		_check(
			around_tree.size() >= 3,
			"a path past a tree goes around it (%d points)" % around_tree.size()
		)
	_check(enemies.size() == 6, "six slimes on the map (found %d)" % enemies.size())
	for enemy in enemies:
		enemy.evasion = 0.0  # no random misses in the checks below

	# --- combat rules: miss, crit, defense
	_check(
		is_equal_approx(CombatRules.hit_evasion(1.0, 0.0), CombatRules.max_evasion),
		"evasion is capped (%d%% at most)" % roundi(CombatRules.max_evasion * 100.0)
	)
	var evasion_cap: float = CombatRules.max_evasion
	CombatRules.max_evasion = 1.0  # without the cap, so the next check does not hang on luck
	_check(CombatRules.resolve_hit(10, 0.0, 0, 1.0)["miss"], "100% evasion always misses")
	CombatRules.max_evasion = evasion_cap
	var crit_hit: Dictionary = CombatRules.resolve_hit(10, 1.0, 3, 0.0)
	_check(
		crit_hit["crit"] and crit_hit["damage"] >= roundi(8 * 1.5) - 3,
		"a crit multiplies the damage before defense (%d)" % crit_hit["damage"]
	)
	var tiny_hit: Dictionary = CombatRules.resolve_hit(1, 0.0, 50, 0.0)
	_check(tiny_hit["damage"] == 1, "defense never takes a hit below 1")
	_check(player.stats.defense() == 4, "the starting gear gives 4 defense")
	_check(sprite.animation == &"idle_down", "starts in idle_down")
	_check(player.stats.level == 1 and player.max_hp == 100, "starts at level 1 with 100 HP")

	# --- obstacle: walk straight into a tree
	var tree: Node2D = get_first_node_in_group("obstacles")
	player.global_position = tree.global_position + Vector2(-80, 0)
	await _frames(2)
	await _hold("move_right", 40)
	_check(player.global_position.x < tree.global_position.x - 20.0, "tree blocks the warrior")

	# --- walking + animations, in open ground
	player.global_position = Vector2(1280, 768)
	await _frames(2)
	var start: Vector2 = player.global_position
	Input.action_press("move_right")
	await _frames(30)
	_check(sprite.animation == &"walk_right", "walk_right plays while moving right")
	Input.action_release("move_right")
	await _frames(3)
	var walked: float = player.global_position.x - start.x
	_check(walked > 80.0 and walked < 140.0, "walks at about 220 px/s (moved %d px)" % walked)
	_check(sprite.animation == &"idle_right", "idle_right after stopping")
	await _hold("move_up", 10)
	_check(player.facing == "up", "faces up after moving up")

	# --- attack out of range does nothing
	var slime = enemies[0]
	player.global_position = slime.global_position + Vector2(-400, 0)
	await _frames(2)
	await _hold("attack", 5)
	_check(slime.hp == slime.max_hp, "attack out of range does no damage")
	await _frames(40)  # let the attack cooldown from that swing run out

	# --- auto-aim: stand left of the slime while facing DOWN, then attack
	player.global_position = slime.global_position + Vector2(-70, 0)
	await _hold("move_down", 2)
	_check(player.facing == "down", "facing down before the attack")
	Input.action_press("attack")
	await _frames(3)
	_check(player.facing == "right", "auto-aim turns the warrior to the slime")
	_check(String(sprite.animation).begins_with("attack_"), "attack animation plays")
	_check(slime.hp < slime.max_hp, "attack damages the slime (hp %d/%d)" % [slime.hp, slime.max_hp])
	_check(player.cooldown_left("attack") > 0.0, "ATK shows a cooldown right after a swing")
	await _frames(15)
	_check(player.get("_target_marker").visible, "a ring marks the enemy auto-aim will hit")
	var waited: int = 0
	while not slime.is_dead and waited < 600:
		await _frames(1)
		waited += 1
	Input.action_release("attack")
	_check(slime.is_dead, "slime dies under repeated attacks (after %d frames)" % waited)
	_check(slime.get_node("Sprite").animation == "die", "a dead slime plays its death animation")
	_check(int(player.stats.record.counters.get("kills", 0)) >= 1, "kills are counted")
	_check(
		player.stats.record.earned.has("first_hunt") and player.stats.record.title == "first_hunt",
		"the first kill earns an achievement and shows its title"
	)
	_check(player.hp < player.max_hp, "slime hurt the warrior (hp %d/%d)" % [player.hp, player.max_hp])
	_check(player.stats.xp == 20, "killing a slime gives 20 XP (xp %d)" % player.stats.xp)

	# --- loot: walk over whatever dropped
	await _frames(3)
	_check(get_nodes_in_group("pickups").size() + player.stats.gold > 0, "the slime dropped loot")
	for pickup in get_nodes_in_group("pickups"):
		if is_instance_valid(pickup):
			player.global_position = pickup.global_position
			await _frames(4)
	_check(player.stats.gold > 0, "picking up coins adds gold (gold %d)" % player.stats.gold)
	_check(get_nodes_in_group("pickups").is_empty(), "collected pickups disappear")

	# --- level up
	player.gain_xp(100)
	_check(player.stats.level >= 2, "enough XP raises the level (level %d)" % player.stats.level)
	_check(player.max_hp > 100 and player.hp == player.max_hp, "level up raises and refills HP")

	# --- potion
	player.stats.potions = 1
	player.hp = 10
	await _hold("use_potion", 2)
	_check(player.hp > 10, "potion heals (hp %d)" % player.hp)
	_check(player.stats.potions == 0, "potion is used up")

	# --- inventory: gear, bag and drinking a potion from the bag
	var fresh = PlayerStats.new()
	_check(
		fresh.max_hp() == 100 and fresh.attack_damage() == 10,
		"starting gear keeps 100 HP and 10 damage"
	)
	var hud = main.get_node("Hud")
	var inventory = hud.get_node("Inventory")
	var attack_button: Control = main.get_node("TouchControls/AttackButton")
	player.stats.potions = 3
	hud.get_node("BagButton").emit_signal("pressed")
	await _frames(2)
	_check(inventory.visible, "the bag button opens the inventory")
	_check(not attack_button.visible, "action buttons hide while the inventory is open")
	var worn: int = 0
	for slot in inventory.gear_slots.values():
		if slot.item_id != "":
			worn += 1
	_check(worn == 6, "six pieces of gear are shown (found %d)" % worn)
	var first = inventory.bag_slots[_bag_index(player, "red_potion")]
	_check(
		first.item_id == "red_potion" and first.count == 3,
		"the bag shows the potions (%s x%d)" % [first.item_id, first.count]
	)
	player.hp = 10
	first.emit_signal("tapped", first)
	inventory.call("_on_primary_pressed")
	await _frames(2)
	_check(player.hp > 10 and player.stats.potions == 2, "USE in the bag drinks a potion")
	_check(first.count == 2, "the bag count follows (%d)" % first.count)
	var pot_button = main.get_node("TouchControls/PotionButton")
	_check(pot_button.badge == "2", "POT shows the potions left (%s)" % pot_button.badge)

	# --- gear: take off, put back on, drop on the ground, pick up again
	_check(
		load("res://assets/characters/warrior/warrior_parts.png") is Image,
		"the warrior parts load as an Image (no GPU read-back)"
	)
	var attack_with_sword: int = player.stats.attack_damage()
	var look_with_sword: PackedByteArray = player.look_texture.get_image().get_data()
	var weapon_slot = inventory.gear_slots["weapon"]
	weapon_slot.emit_signal("tapped", weapon_slot)
	inventory.call("_on_primary_pressed")
	await _frames(2)
	_check(not player.stats.equipment.has("weapon"), "REMOVE takes the sword off")
	_check(player.stats.count_of("training_sword") == 1, "the sword goes into the bag")
	_check(
		player.stats.attack_damage() == attack_with_sword - 4,
		"without the sword the attack drops by 4"
	)
	_check(weapon_slot.item_id == "", "the weapon slot shows empty")
	var look_without_sword: PackedByteArray = player.look_texture.get_image().get_data()
	_check(look_without_sword != look_with_sword, "the warrior is drawn without the sword")
	var sword_slot = inventory.bag_slots[_bag_index(player, "training_sword")]
	sword_slot.emit_signal("tapped", sword_slot)
	sword_slot.emit_signal("double_tapped", sword_slot)
	await _frames(2)
	_check(
		player.stats.equipped_id("weapon") == "training_sword",
		"a double tap in the bag puts the sword back on"
	)
	_check(player.stats.attack_damage() == attack_with_sword, "the attack is back")

	var max_hp_with_boots: int = player.max_hp
	var boots_slot = inventory.gear_slots["boots"]
	boots_slot.emit_signal("tapped", boots_slot)
	inventory.call("_on_drop_pressed")
	await _frames(3)
	_check(player.max_hp == max_hp_with_boots - 5, "dropping the boots lowers max HP by 5")
	var boots_on_ground = null
	for pickup in get_nodes_in_group("pickups"):
		if pickup.get("item_id") == "leather_boots":
			boots_on_ground = pickup
	_check(boots_on_ground != null, "the dropped boots lie on the ground")
	if boots_on_ground != null:
		await _frames(70)  # a dropped item waits a second before it can be picked up
		player.global_position = boots_on_ground.global_position
		await _frames(4)
	_check(player.stats.count_of("leather_boots") == 1, "walking over the boots picks them up")
	player.equip_from_bag(_bag_index(player, "leather_boots"))
	_check(player.max_hp == max_hp_with_boots, "boots back on, max HP back")
	_check(hud.get_node("MessageLog").get_child_count() > 0, "the message log shows what happened")

	# --- a full bag
	while player.stats.add_item("red_headband"):
		pass
	_check(player.stats.bag.size() == 15, "the bag holds 15 stacks")
	player.unequip("cape")
	_check(player.stats.equipment.has("cape"), "with a full bag the cape stays on")
	player.stats.bag = player.stats.bag.filter(func(stack): return stack["id"] != "red_headband")

	# --- save version 2, and a save from the version before
	var copy = PlayerStats.new()
	copy.from_dict(player.stats.to_dict())
	_check(
		copy.equipment == player.stats.equipment and copy.bag == player.stats.bag,
		"gear and bag survive saving"
	)
	var old_save = PlayerStats.new()
	old_save.from_dict({"level": 3, "xp": 10, "gold": 7, "potions": 4})
	_check(
		old_save.potions == 4 and old_save.equipment.size() == 6,
		"an old save keeps its potions and gets the starting gear"
	)
	# --- stat points (MU style), a stat reset, titles, save version 3
	var trainee = PlayerStats.new()
	_check(trainee.free_points() == 0, "a new warrior has no stat points")
	trainee.level = 3
	_check(trainee.free_points() == 10, "every level gives 5 stat points")
	var base_attack: int = trainee.attack_damage()
	var base_hp: int = trainee.max_hp()
	var base_defense: int = trainee.defense()
	var base_crit: float = trainee.crit_chance()
	var base_accuracy: float = trainee.total("accuracy")
	var base_speed: float = trainee.total("attack_speed")
	for stat_id in ["strength", "strength", "strength", "strength"]:
		trainee.add_stat_point(stat_id)
	for stat_id in ["vitality", "vitality", "vitality"]:
		trainee.add_stat_point(stat_id)
	_check(trainee.attack_damage() == base_attack + 4, "4 STR add 4 attack")
	_check(
		trainee.max_hp() == base_hp + 15 and trainee.defense() == base_defense + 1,
		"3 VIT add 15 max HP and 1 defense"
	)
	for _i in 3:
		trainee.add_stat_point("dexterity")
	_check(
		(
			trainee.attack_damage() == base_attack + 5
			and is_equal_approx(trainee.crit_chance(), base_crit + 0.015)
			and is_equal_approx(trainee.total("accuracy"), base_accuracy + 0.03)
			and is_equal_approx(trainee.total("attack_speed"), base_speed + 0.018)
		),
		"3 DEX add 1 attack, 1.5% crit, 3% accuracy and 1.8% attack speed"
	)
	_check(not trainee.add_stat_point("energy"), "no point can be spent when none is left")
	trainee.gold = 0
	_check(
		trainee.reset_cost() == 0 and trainee.reset_stats(true) and trainee.free_points() == 10,
		"below level 10 a stat reset is free and gives every point back"
	)
	trainee.level = 10
	trainee.add_stat_point("strength")
	_check(not trainee.reset_stats(true), "from level 10 a stat reset costs gold")
	trainee.gold = 250
	_check(
		trainee.reset_stats(true) and trainee.gold == 50 and trainee.spent_points() == 0,
		"a stat reset at level 10 costs 200 gold"
	)
	trainee.level = 3
	trainee.add_stat_point("energy")
	_check(
		is_equal_approx(trainee.max_stamina(), 102.0)
		and is_equal_approx(trainee.skill_damage_bonus(), 0.01),
		"ENE adds stamina and skill damage"
	)
	var no_title_attack: int = trainee.attack_damage()
	_check(
		trainee.record.count("kills:green_slime", 30, trainee.level).has("slime_hunter"),
		"30 green slimes earn Slime Hunter"
	)
	_check(
		trainee.record.title == "slime_hunter" and trainee.attack_damage() == no_title_attack + 1,
		"the first title is shown at once and its bonus counts"
	)
	_check(not trainee.record.set_title("veteran"), "a title not earned cannot be shown")
	trainee.level = 5
	_check(trainee.record.check(trainee.level).has("rising_star"), "level 5 earns Rising Star")
	trainee.learn_skill("ground_slam")
	var reloaded = PlayerStats.new()
	reloaded.from_dict(trainee.to_dict())
	_check(
		(
			reloaded.stat_points == trainee.stat_points
			and reloaded.knows_skill("ground_slam")
			and reloaded.record.earned == trainee.record.earned
			and reloaded.record.title == "slime_hunter"
			and trainee.to_dict()["version"] == PlayerStats.SAVE_VERSION
		),
		"stat points, learned skills and titles survive saving"
	)

	# --- gear with a rarity and random options, compared with what is worn (save version 4)
	seed(7)
	var rarities_seen: Dictionary = {}
	var options_match := true
	for _i in 300:
		var piece: Dictionary = ItemDb.roll_gear("training_sword")
		rarities_seen[piece["rarity"]] = true
		var wanted: int = int(ItemDb.rarities[piece["rarity"]]["options"])
		options_match = options_match and piece["options"].size() == wanted
	_check(
		rarities_seen.size() >= 3 and options_match,
		"dropped gear rolls rarities, each with its number of options (%s)" % str(rarities_seen.keys())
	)
	var sharp_options := {"attack": 3, "crit_chance": 0.02}
	var sharp: Dictionary = ItemDb.gear("training_sword", "rare", 0, sharp_options)
	_check(is_equal_approx(ItemDb.stat_of(sharp, "attack"), 7.0), "a Rare sword adds its options")
	_check(ItemDb.display_name(sharp, true) == "Rare Training Sword", "its name shows the rarity")
	while player.stats.bag.size() >= 14:
		player.stats.bag.pop_back()
	var attack_before_rare: int = player.stats.attack_damage()
	_check(player.add_stack(sharp), "a Rare sword goes into the bag")
	var sharp_index: int = player.stats.bag.size() - 1
	inventory.refresh(player.stats, null)
	inventory.call("_on_slot_tapped", inventory.bag_slots[sharp_index])
	var details: String = inventory.get("_info_label").text
	_check(
		"If worn: +3 ATK, +2% CRIT" in details and "Gives: +7 ATK, +2% CRIT" in details,
		"the details show its bonuses and what wearing it changes (%s)" % details.replace("\n", " / ")
	)
	player.equip_from_bag(sharp_index)
	_check(
		player.stats.attack_damage() == attack_before_rare + 3
		and player.stats.equipment["weapon"]["rarity"] == "rare",
		"wearing the Rare sword adds its options to the attack"
	)
	var saved_gear = PlayerStats.new()
	saved_gear.from_dict(player.stats.to_dict())
	_check(
		saved_gear.equipment["weapon"] == player.stats.equipment["weapon"],
		"gear keeps its rarity and options after saving (version 4)"
	)
	var v3_save = PlayerStats.new()
	v3_save.from_dict(
		{
			"version": 3,
			"level": 2,
			"equipment": {"weapon": "training_sword"},
			"bag": [{"id": "leather_boots", "count": 1}],
		}
	)
	_check(
		v3_save.equipped_id("weapon") == "training_sword" and v3_save.bag[0]["rarity"] == "common",
		"a version 3 save turns its gear into common pieces"
	)

	# --- the Blue Potion, auto potion (upgrades: smoke_upgrade.gd)
	player.stamina = 10.0
	player.add_item("blue_potion")
	player.use_from_bag(_bag_index(player, "blue_potion"))
	_check(
		player.stamina > 10.0 + player.max_stamina * 0.4
		and player.stats.count_of("blue_potion") == 0,
		"a Blue Potion gives back half the stamina"
	)
	player.stats.auto_potion = 0
	player.cycle_auto_potion()
	player.cycle_auto_potion()
	_check(player.stats.auto_potion == 50, "AUTO goes off -> 30% -> 50%")
	player.add_item("red_potion", 2)
	var potions_before_auto: int = player.stats.potions
	var low_hp: int = int(player.max_hp * 0.3)
	player.hp = low_hp
	await _frames(3)
	_check(
		player.stats.potions == potions_before_auto - 1 and player.hp > low_hp,
		"below 50% HP a red potion is drunk by itself"
	)
	var auto_saved = PlayerStats.new()
	auto_saved.from_dict({"version": 4, "auto_potion": 50})
	var auto_odd = PlayerStats.new()
	auto_odd.from_dict({"version": 4, "auto_potion": 55})
	_check(
		auto_saved.auto_potion == 50 and auto_odd.auto_potion == 0,
		"the auto potion setting is saved, and odd values turn it off"
	)
	player.stats.auto_potion = 0

	# --- sets: look-alike gear in its own colours, and bonuses by pieces worn
	var dresser = PlayerStats.new()
	var hp_plain: int = dresser.max_hp()
	var attack_plain: int = dresser.attack_damage()
	var defense_plain: int = dresser.defense()
	var look_plain: PackedByteArray = HeroLook.build(dresser.equipment).get_image().get_data()
	dresser.equipment["head"] = ItemDb.gear("verdant_headband")
	dresser.equipment["cape"] = ItemDb.gear("verdant_cape")
	_check(
		dresser.set_pieces().get("verdant", 0) == 2 and dresser.max_hp() == hp_plain + 25,
		"two Verdant pieces add their HP and the 2-piece bonus (%d)" % dresser.max_hp()
	)
	dresser.equipment["gloves"] = ItemDb.gear("verdant_gloves")
	dresser.equipment["boots"] = ItemDb.gear("verdant_boots")
	_check(
		dresser.attack_damage() == attack_plain + 4,
		"four Verdant pieces add the 4-piece bonus (attack %d)" % dresser.attack_damage()
	)
	dresser.equipment["weapon"] = ItemDb.gear("crimson_sword")
	dresser.equipment["armor"] = ItemDb.gear("crimson_plate")
	_check(
		dresser.attack_damage() == attack_plain + 12 and dresser.defense() == defense_plain + 4,
		"the Crimson pair adds +4 attack and +2 defense on top of its own"
	)
	var look_sets: PackedByteArray = HeroLook.build(dresser.equipment).get_image().get_data()
	_check(
		look_sets.size() == look_plain.size() and look_sets != look_plain,
		"the sets are drawn in their own colours"
	)
	while player.stats.bag.size() >= 14:
		player.stats.bag.pop_back()
	player.add_stack(ItemDb.gear("verdant_headband"))
	inventory.refresh(player.stats, null)
	inventory.call("_on_slot_tapped", inventory.bag_slots[player.stats.bag.size() - 1])
	_check(
		"Verdant Set 0/4" in inventory.get("_info_label").text,
		"the details name the set and how much of it is worn"
	)

	# --- the character window: C opens it, + spends a point, titles change
	var character = hud.get_node("Character")
	var inventory_was_open: bool = inventory.visible
	var free_before: int = player.stats.free_points()
	_check(
		free_before > 0 and "+%d" % free_before in hud.get_node("StatsButton").text,
		"the STATS button shows the free points (%d)" % free_before
	)
	await _hold("character", 2)
	_check(character.visible and not inventory.visible, "C opens the character window")
	var hp_limit: int = player.max_hp
	character.get("_plus_buttons")["vitality"].pressed.emit()
	await _frames(1)
	_check(
		player.stats.free_points() == free_before - 1 and player.max_hp == hp_limit + 5,
		"+ on VIT spends a point and adds 5 max HP (%d)" % player.max_hp
	)
	_check(character.get("_stat_values")["vitality"].text == "1", "the window shows VIT 1")
	character.show_page("titles")
	_check(
		character.get("_achievement_rows").get_child_count() == AchievementRecord.list.size(),
		"the titles page lists every achievement"
	)
	character.call("_step_title", 1)
	_check(player.stats.record.title == "", "> can hide the title")
	character.call("_step_title", 1)
	_check(player.stats.record.title == "first_hunt", "> shows it again")
	player.add_item("rebirth_scroll")
	player.use_from_bag(_bag_index(player, "rebirth_scroll"))
	_check(
		player.stats.spent_points() == 0 and player.stats.count_of("rebirth_scroll") == 0,
		"a Rebirth Scroll gives the stat points back"
	)
	hud.toggle_character()
	_check(not character.visible, "the character window closes")
	if inventory_was_open:
		hud.toggle_inventory()  # the checks below close it with the inventory key

	await _hold("inventory", 2)
	_check(not inventory.visible, "the inventory key closes it")
	_check(attack_button.visible, "action buttons come back after closing")

	# --- touch controls: the ATK button and the joystick react to fingers
	var touch_attack: Control = main.get_node("TouchControls/AttackButton")
	var finger := InputEventScreenTouch.new()
	finger.index = 0
	finger.pressed = true
	finger.position = touch_attack.get_global_rect().get_center()
	touch_attack.call("_input", finger)
	_check(Input.is_action_pressed("attack"), "touching ATK presses attack")
	finger.pressed = false
	touch_attack.call("_input", finger)
	_check(not Input.is_action_pressed("attack"), "lifting the finger releases attack")
	var joystick: Control = main.get_node("TouchControls/Joystick")
	var stick_center: Vector2 = joystick.get_global_rect().get_center()
	var thumb := InputEventScreenTouch.new()
	thumb.index = 1
	thumb.pressed = true
	thumb.position = stick_center
	joystick.call("_input", thumb)
	var slide := InputEventScreenDrag.new()
	slide.index = 1
	slide.position = stick_center + Vector2(90, 0)
	joystick.call("_input", slide)
	_check(Input.get_action_strength("move_right") > 0.5, "dragging the joystick right moves right")
	thumb.pressed = false
	joystick.call("_input", thumb)
	_check(Input.get_action_strength("move_right") == 0.0, "letting go of the joystick stops")
	await _frames(2)

	# --- combo and elites (swing in an empty spot, so no slime gets killed here)
	var combo_spot: Vector2 = player.global_position
	player.global_position = Vector2(1000, 500)
	await _frames(2)
	player.combo_step = 0
	for i in 3:
		player.call("_attack")
	player.global_position = combo_spot
	await _frames(2)
	_check(player.combo_step == 3, "three quick swings reach the combo finisher")
	var elite = enemies[2]
	elite.make_elite()
	_check(
		elite.max_hp == 120 and elite.xp_reward == 60 and elite.display_name.begins_with("Elite"),
		"an elite slime has 3x HP and XP (%d HP, %d XP)" % [elite.max_hp, elite.xp_reward]
	)

	# --- skill: spin slash hits a slime that is BEHIND the warrior
	var second = enemies[1]
	player.global_position = second.global_position + Vector2(-90, 0)
	await _hold("move_left", 2)
	var hp_before: int = second.hp
	await _hold("skill", 2)
	_check(second.hp < hp_before, "spin skill hits enemies all around (hp %d)" % second.hp)
	_check(player.stamina < player.max_stamina, "skill costs stamina (%d)" % player.stamina)

	# --- save file
	_check(FileAccess.file_exists(SAVE_PATH), "progress is saved to a file")
	var loaded = PlayerStats.new()
	loaded.from_dict(SaveFile.load_data())
	_check(loaded.level == player.stats.level, "saved level matches (level %d)" % loaded.level)
	_check(loaded.gold == player.stats.gold, "saved gold matches")

	# --- monsters drop gear with a rolled rarity; picking it up keeps it whole
	var looter = _first_alive(enemies)
	looter.gear_drops = {"chance": 1.0, "items": ["leather_boots"]}
	looter.call("_maybe_drop_gear")
	await _frames(2)
	var gear_pickup = null
	for pickup in get_nodes_in_group("pickups"):
		if pickup.get("item_id") == "leather_boots" and not pickup.get("stack").is_empty():
			gear_pickup = pickup
	_check(gear_pickup != null, "a monster can drop gear")
	if gear_pickup != null:
		var dropped: Dictionary = gear_pickup.get("stack").duplicate(true)
		while player.stats.bag.size() >= 15:
			player.stats.bag.pop_back()
		player.global_position = gear_pickup.global_position
		await _frames(4)
		_check(player.stats.bag.has(dropped), "picking dropped gear up keeps its rarity and options")

	# --- skills from skills.json, dash, statuses, telegraphed slam
	await _frames(70)
	_freeze(enemies, true)
	for enemy in enemies:
		enemy.evasion = 0.0
	player.stamina = player.max_stamina
	player.global_position = _first_alive(enemies).global_position + Vector2(-80, 0)
	await _frames(2)
	var struck = player.call("_nearest_enemy", 110.0)
	var struck_hp: int = struck.hp
	_check(player.use_skill("power_strike"), "Power Strike can be used")
	_check(struck.hp < struck_hp, "Power Strike hits the nearest enemy (hp %d)" % struck.hp)
	_check(player.cooldown_left("skill_2") > 0.9, "STRIKE starts its cooldown")
	_check(not player.use_skill("war_cry"), "War Cry is locked below level 3")
	while player.stats.bag.size() >= 15:
		player.stats.bag.pop_back()
	player.add_item("book_ground_slam")
	player.use_from_bag(_bag_index(player, "book_ground_slam"))
	_check(
		not player.stats.knows_skill("ground_slam") and player.stats.count_of("book_ground_slam") == 1,
		"a skill book waits until the level is high enough"
	)
	player.stats.level = 5
	_check(player.skill_lock("ground_slam") == "BOOK", "Ground Slam waits for its book")
	_check(not player.use_skill("ground_slam"), "Ground Slam cannot be used before reading it")
	player.use_from_bag(_bag_index(player, "book_ground_slam"))
	_check(
		player.stats.knows_skill("ground_slam") and player.stats.count_of("book_ground_slam") == 0,
		"reading the book teaches Ground Slam and uses the book up"
	)
	_check(player.stats.record.earned.has("scholar"), "learning from a book earns Scholar")
	player.stamina = player.max_stamina
	_check(
		player.use_skill("war_cry") and player.has_damage_bonus(), "War Cry gives a damage boost"
	)
	player.stamina = player.max_stamina
	var slammed = _first_alive(enemies)
	slammed.max_hp = 500
	slammed.hp = 500  # tough enough to live through the slam, so the stun shows
	player.global_position = slammed.global_position + Vector2(-60, 0)
	await _frames(2)
	_check(player.use_skill("ground_slam"), "Ground Slam can be used at level 5")
	_check(slammed.statuses.is_active("stun"), "Ground Slam stuns the enemies it hits")
	_freeze(enemies, false)

	player.global_position = Vector2(1000, 500)
	await _frames(70)
	player.stamina = player.max_stamina
	var before_dash: Vector2 = player.global_position
	_check(player.dash(Vector2.RIGHT), "dash starts")
	var hp_dashing: int = player.hp
	player.take_damage(5)
	_check(player.hp == hp_dashing, "no damage while dashing")
	await _frames(14)
	var dashed: float = player.global_position.x - before_dash.x
	_check(dashed > 80.0, "a dash covers ground fast (%d px)" % dashed)

	player.apply_status("slow", 1.0, 0.5)
	_check(is_equal_approx(player.statuses.speed_factor(), 0.5), "slow halves the walking speed")
	player.statuses.clear()
	var hp_poisoned: int = player.hp
	player.apply_status("poison", 2.0, 10.0)
	await _frames(40)
	_check(player.hp < hp_poisoned, "poison hurts over time (hp %d)" % player.hp)
	player.statuses.clear()
	await _frames(70)
	player.take_damage(1)
	_check(String(sprite.animation).begins_with("hurt_"), "getting hit plays the hurt frame")

	var blue = _first_alive(blue_slimes)
	_freeze(enemies, true)
	blue.set_physics_process(true)
	blue.set("_attack_ready_in", 99.0)  # only the slam may hurt the warrior in this check
	player.global_position = blue.global_position + Vector2(30, 0)
	await _frames(5)
	player.set("_invincible_left", 0.0)
	player.hp = player.max_hp  # the slam must not knock out a warrior worn down earlier
	var hp_before_slam: int = player.hp
	blue.call("_start_slam")
	_check(get_nodes_in_group("telegraphs").size() > 0, "a red circle warns before the slam")
	await _frames(60)
	_check(
		player.hp < hp_before_slam, "standing in the red circle gets you hit (hp %d)" % player.hp
	)
	blue.set("_attack_ready_in", 0.0)
	_freeze(enemies, false)

	# --- a moment of invincibility after a hit
	_freeze(enemies, true)  # no slime may land a hit of its own in this check
	while player.is_dead:
		await _frames(10)
	_check(not player.is_dead, "the warrior is standing before the invincibility check")
	player.global_position = Vector2(1000, 500)
	await _frames(5)
	player.set("_invincible_left", 0.0)
	player.hp = player.max_hp  # earlier fights may have left too little HP for two hits
	var hp_before_hits: int = player.hp
	player.take_damage(5)
	player.take_damage(5)
	_check(
		player.hp == hp_before_hits - 5,
		"right after a hit the warrior cannot be hurt again (%d -> %d)" % [hp_before_hits, player.hp]
	)
	_freeze(enemies, false)
	await _frames(70)

	# --- death and respawn
	player.take_damage(99999)
	_check(player.is_dead, "the warrior dies at 0 HP")
	var death_position: Vector2 = player.global_position
	await _hold("move_right", 15)
	_check(player.global_position == death_position, "a dead warrior cannot move")
	await _frames(200)
	_check(not player.is_dead and player.hp == player.max_hp, "respawns with full HP")
	_check(player.global_position.distance_to(Vector2(1280, 768)) < 5.0, "respawns at the start")
	_check(player.stats.record.earned.has("back_again"), "getting back up earns Back Again")

	await SmokeWorld.new().run(self, main, player, hud)
	await SmokeClasses.new().run(self, main, player, hud)
	await SmokeUi.new().run(self, main, player, hud)
	await SmokeCombat.new().run(self, main, player, hud)
	await SmokeProgress.new().run(self, main, player, hud)
	await SmokeGear.new().run(self, main, player, hud)
	await SmokeForest.new().run(self, main, player, hud)
	await SmokeLoot.new().run(self, main, player, hud)
	await SmokeUpgrade.new().run(self, main, player, hud)
	await SmokeLake.new().run(self, main, player, hud)
	await SmokeRidge.new().run(self, main, player, hud)
	await SmokeRuins.new().run(self, main, player, hud)
	await SmokeFrost.new().run(self, main, player, hud)
	await SmokeBosses.new().run(self, main, player, hud)
	await SmokeTowns.new().run(self, main, player, hud)
	await SmokeEvents.new().run(self, main, player, hud)

	_remove_test_save()
	root.remove_child(main)
	main.free()  # free the game before quitting, so nothing is left in use at exit
	await _frames(60)  # and let sounds, tweens and timers that were still running let go
	print("SMOKE TEST: %s" % ("PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _freeze(enemies: Array, frozen: bool) -> void:
	for enemy in enemies:
		enemy.set_physics_process(not frozen)


func _first_alive(enemies: Array):
	for enemy in enemies:
		if not enemy.is_dead:
			return enemy
	return enemies[0]


func _remove_test_save() -> void:
	for path in [SAVE_PATH, SETTINGS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _bag_index(player, item_id: String) -> int:
	for i in player.stats.bag.size():
		if player.stats.bag[i]["id"] == item_id:
			return i
	return -1


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(1)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  ok   - ", description)
	else:
		_failures += 1
		print("  FAIL - ", description)
