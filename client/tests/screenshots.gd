extends SceneTree
## Saves screenshots of the game for checking the look by eye (not a test).
## Needs a display, for example:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       -s res://tests/screenshots.gd -- /tmp/shots
## Uses its own save file, so a real save is not touched.

const SaveFile = preload("res://scripts/player/save_file.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const PICKUP_SCENE = preload("res://scenes/items/pickup.tscn")
const GameScript = preload("res://scripts/game.gd")
const SAVE_PATH := "user://screenshots_save.cfg"
const Settings = preload("res://scripts/settings.gd")

var _folder: String = "/tmp/shots"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_folder = args[0]
	DirAccess.make_dir_recursive_absolute(_folder)
	SaveFile.path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameScript.invasions_enabled = false
	GameScript.fade_seconds = 0.0
	Settings.path = "user://screenshots_settings.cfg"
	Settings.load_file()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	var player = get_first_node_in_group("player")
	var hud = main.get_node("Hud")
	player.stats.level = 6
	player.stats.gold = 1234
	player.add_stack(ItemDb.gear("crimson_sword", "epic", 7, {"attack": 3, "crit_chance": 0.02}))
	player.add_stack(ItemDb.gear("verdant_cape", "rare", 2, {"max_hp": 12, "evasion": 0.015}))
	player.add_item("ember_stone", 4)
	player.add_item("slime_jelly", 6)
	player.add_stack(ItemDb.gear("short_bow"))  # another class's: faded in the bag
	player.add_stack(ItemDb.gear("duelist_cape"))  # needs level 8: "Lv8" in red
	await _shot("01_meadow")
	player.stats.tutorial = 99  # the first hint is in 01; no more hints after it
	hud.toggle_inventory()
	hud.get_node("Inventory").call("_on_slot_tapped", hud.get_node("Inventory").bag_slots[2])
	await _shot("02_inventory")
	player.stats.stat_points = {"strength": 10, "dexterity": 5, "vitality": 5}
	player.max_hp = player.stats.max_hp()
	player.hp = player.max_hp
	player.hp_changed.emit(player.hp, player.max_hp)
	hud.call("_refresh_progress")
	hud.toggle_character()
	await _shot("03_character")
	hud.get_node("Character").show_page("quests")
	await _shot("04_quests")
	hud.call("_close_windows")
	main.change_map("town", "default")
	await _frames(20)
	await _shot("05_town")
	var mira = get_nodes_in_group("npcs").filter(func(npc): return npc.npc_id == "merchant")[0]
	player.global_position = mira.global_position + Vector2(70, 30)
	await _frames(10)
	await _shot("06_near_npc")
	hud.talk()
	await _shot("07_dialog")
	hud.get_node("NpcDialog").option("Buy and sell").pressed.emit()
	await _shot("08_shop")
	hud.call("_close_windows")
	main.change_map("forest", "west")
	await _frames(20)
	await _shot("09_forest")
	var king = get_first_node_in_group("bosses")
	player.global_position = king.global_position + Vector2(-260, 40)
	await _frames(30)
	king.call("_start_slam")
	await _frames(20)
	await _shot("11_boss")
	var shroom = get_nodes_in_group("enemies").filter(
		func(enemy): return enemy.monster_id == "spore_shroom"
	)[0]
	player.global_position = shroom.global_position + Vector2(-220, 0)
	for _i in 120:
		await process_frame
		if not get_nodes_in_group("projectiles").is_empty():
			break
	await _shot("12_spore")
	GameScript.sky_seconds = 60.0  # day, to show how much darker the deep forest is
	main.change_map("twilight", "south")
	await _frames(30)
	var boar = get_nodes_in_group("enemies").filter(
		func(enemy): return enemy.monster_id == "bramble_boar"
	)[0]
	player.global_position = boar.global_position + Vector2(-210, 30)
	await _frames(24)
	await _shot("31_twilight")
	main.change_map("grove", "south")
	await _frames(30)
	player.global_position = Vector2(1280, 640)
	await _frames(30)
	await _shot("32_grove")
	await _boss_loot(player, hud)
	await _lake(main, player)
	await _ridge(main, player)
	await _ruins(main, player)
	GameScript.sky_seconds = -1.0
	main.change_map("cellar")
	await _frames(240)
	await _shot("13_cellar")
	player.take_damage(99999)
	await _frames(20)
	await _shot("10_death")
	main.change_map("field", "default")
	await _frames(20)
	player.revive()
	GameScript.sky_seconds = 720.0
	main.update_sky()
	await _shot("14_night")
	GameScript.sky_seconds = 1248.0
	main.update_sky()
	await _frames(60)
	await _shot("15_rain")
	GameScript.sky_seconds = 300.0
	main.update_sky()
	for class_id in ["mage", "archer"]:
		_become(player, hud, class_id)
		player.facing = "right"
		player.call("_attack")
		await _frames(5)
		await _shot("16_" + class_id)
	hud.toggle_inventory()
	await _shot("17_archer_bag")
	hud.toggle_inventory()
	player.stats.level = 10  # the job advancement and its hood need level 10
	player.stats.advanced = true
	player.add_item("azure_hood")
	for i in player.stats.bag.size():
		if player.stats.bag[i]["id"] == "azure_hood":
			player.equip_from_bag(i)
			break
	hud.call("_refresh_progress")
	await _frames(20)
	await _shot("18_ranger")
	hud.toggle_menu()
	await _frames(3)
	await _shot("21_menu")
	hud.get("_menu").show_page("settings")
	await _frames(3)
	await _shot("22_settings")
	hud.toggle_menu()
	Settings.set_value("left_handed", true)
	main.get_node("TouchControls").apply_settings()
	await _frames(3)
	await _shot("23_left_handed")
	Settings.set_value("left_handed", false)
	var touch: CanvasLayer = main.get_node("TouchControls")
	touch.apply_settings()
	hud.toggle_menu()
	hud.get("_menu").show_page("controls")
	await _frames(3)
	await _shot("27_controls")
	hud.call("_on_menu_request", "edit_buttons")
	touch.move_control(touch.get_node("AttackButton"), Vector2(-90, -50))
	touch.call("_change_size", 1)
	touch.call("_change_size", 1)
	await _frames(3)
	await _shot("28_button_editor")
	touch.call("_reset_layout")
	touch.stop_editing()
	Settings.set_value("text_size", 1.3)
	hud.call("_on_menu_request", "settings_changed")
	hud.toggle_menu()
	hud.get("_menu").show_page("settings")
	await _frames(3)
	await _shot("29_big_text")
	hud.toggle_menu()
	Settings.set_value("colorblind", true)
	hud.toggle_inventory()
	await _frames(3)
	await _shot("30_big_text_colorblind_bag")
	hud.toggle_inventory()
	Settings.set_value("colorblind", false)
	Settings.set_value("text_size", 1.0)
	hud.call("_on_menu_request", "settings_changed")
	GameScript.sky_seconds = -1.0
	# The character screen, with two heroes saved
	SaveFile.slot_pattern = "user://shots_slot_%d.cfg"
	SaveFile.path = SaveFile.slot_path(1)
	SaveFile.save_data(player.stats.to_dict())
	SaveFile.create_slot(2, "warrior", "Doran")
	SaveFile.delete_slot(3)
	root.remove_child(main)
	main.free()
	var screen: Control = load("res://scenes/ui/character_select.tscn").instantiate()
	screen.starts_game = false
	root.add_child(screen)
	await _frames(10)
	await _shot("19_select")
	screen.show_classes(3)
	await _frames(5)
	await _shot("20_new_hero")
	for slot in range(1, SaveFile.SLOT_COUNT + 1):
		SaveFile.delete_slot(slot)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit()


## The hero as a new character of another class (as in smoke_classes.gd).
func _become(player: Node, hud: Node, class_id: String) -> void:
	var data: Dictionary = player.stats.to_dict()
	data["class"] = class_id
	data.erase("equipment")
	player.stats.from_dict(data)
	player.call("_load_tuning")
	player.call("_apply_look")
	player.call("_limits_changed")
	hud.call("_refresh_progress")


func _shot(file_name: String) -> void:
	await _frames(12)
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_folder, file_name])


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## Sunpetal Lake: the island and its chest, the river's bridges, a Marsh Frog
## in the air, and the Elder Snapjaw coming out of its shell.
func _lake(main, player) -> void:
	main.change_map("lake", "north")
	await _frames(20)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	player.global_position = Vector2(690, 520)
	await _frames(20)
	await _shot("40_lake")
	player.global_position = Vector2(1280, 700)
	await _frames(20)
	await _shot("41_river")
	var frog = get_nodes_in_group("enemies").filter(
		func(enemy): return enemy.monster_id == "marsh_frog" and enemy.global_position.y > 1200
	)[0]
	frog.set_physics_process(true)
	player.global_position = frog.global_position + Vector2(250, -20)
	for _i in 200:
		await process_frame
		if float(frog.moves.get("_air_left")) > 0.25:
			break
	await _shot("42_frog_leap")
	var snapjaw = get_first_node_in_group("bosses")
	snapjaw.set_physics_process(true)
	player.global_position = snapjaw.global_position + Vector2(-170, 30)
	for _i in 400:
		player.hp = player.max_hp
		await process_frame
		if get_nodes_in_group("telegraphs").any(func(mark): return mark.get("radius") == 200.0):
			break
	await _shot("43_snapjaw")


## Galeclaw Ridge: the canyon between two cliffs, the rift and a rope bridge,
## a Rock Beetle rolling and a Crag Imp's rock in the air.
func _ridge(main, player) -> void:
	main.change_map("ridge", "west")
	await _frames(20)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	player.global_position = Vector2(640, 900)
	await _frames(20)
	await _shot("44_canyon")
	player.global_position = Vector2(1350, 480)
	await _frames(20)
	await _shot("45_rope_bridge")
	var beetle = _nearest_enemy("rock_beetle", Vector2(1960, 640))
	beetle.set_physics_process(true)
	beetle.moves.set("_ready_in", 0.0)
	player.global_position = beetle.global_position + Vector2(-230, 10)
	await _frames(14)
	await _shot("46_beetle_roll")
	beetle.set_physics_process(false)
	var imp = _nearest_enemy("crag_imp", Vector2(2470, 560))
	imp.set_physics_process(true)
	imp.moves.set("_ready_in", 0.0)
	player.global_position = imp.global_position + Vector2(-60, 260)
	await _frames(20)  # its rock is up in the air
	await _shot("47_imp_lob")
	imp.set_physics_process(false)
	var harpy = _nearest_enemy("gale_harpy", Vector2(700, 1010))
	harpy.set_physics_process(true)
	harpy.moves.set("_ready_in", 0.0)
	player.global_position = harpy.global_position + Vector2(200, -40)
	for _i in 300:
		await process_frame
		if float(harpy.moves.get("_mark_left")) > 0.0:
			break
	await _shot("48_harpy_swoop")
	harpy.set_physics_process(false)
	var roc = _nearest_enemy("stormcrest_roc", Vector2(2250, 1330))
	player.global_position = roc.global_position + Vector2(-250, -60)
	await _frames(20)
	await _shot("49_stormcrest_roc")


## Moonfall Ruins: the temple with the sleeping Colossus, a gargoyle waking,
## a Mimic biting and a Sentinel's beam.
func _ruins(main, player) -> void:
	main.change_map("ruins", "south")
	await _frames(20)
	var all: Array = main.map.get_children().filter(func(n): return n.get("monster_id") != null)
	for monster in all:
		monster.set_physics_process(false)
	player.global_position = Vector2(1350, 960)
	await _frames(20)
	await _shot("50_temple")
	for step in [["stone_gargoyle", Vector2(420, 840), Vector2(110, 30), "51_gargoyle_wakes"],
			["mimic", Vector2(2440, 840), Vector2(-60, 10), "52_mimic"],
			["ruin_sentinel", Vector2(2150, 1100), Vector2(0, -280), "53_sentinel_beam"]]:
		var picked = null
		for monster in all:
			if monster.monster_id == step[0]:
				if picked == null or monster.global_position.distance_to(step[1]) < (
					picked.global_position.distance_to(step[1])
				):
					picked = monster
		picked.set_physics_process(true)
		picked.moves.set("_ready_in", 0.0)
		player.hp = player.max_hp
		player.global_position = picked.global_position + step[2]
		await _frames(16)
		await _shot(step[3])
		picked.set_physics_process(false)


func _nearest_enemy(monster_id: String, point: Vector2):
	var best = null
	for enemy in get_nodes_in_group("enemies"):
		if enemy.monster_id != monster_id:
			continue
		var gap: float = enemy.global_position.distance_to(point)
		if best == null or gap < best.global_position.distance_to(point):
			best = enemy
	return best


## The Elder Treant's reward on the ground (rare pieces stand in a beam of
## light), and an Elderwood piece's random bonuses and their ranges in the bag.
func _boss_loot(player, hud) -> void:
	var treant = get_nodes_in_group("enemies").filter(
		func(enemy): return enemy.monster_id == "elder_treant"
	)[0]
	treant.set_physics_process(false)
	treant.set("_player", player)
	player.global_position = treant.global_position + Vector2(0, 330)
	var before: Array = get_nodes_in_group("pickups")
	treant.call("_maybe_drop_gear")
	await _frames(2)
	# Laid out on the open path in front of the hero (out of the magnet's reach),
	# next to a common piece, which has no beam.
	var spots: Array = [Vector2(-150, -40), Vector2(-100, 60), Vector2(130, -50)]
	var dropped: Array = get_nodes_in_group("pickups").filter(func(p): return not p in before)
	for i in dropped.size():
		dropped[i].global_position = player.global_position + spots[i % spots.size()]
	var plain: Node2D = PICKUP_SCENE.instantiate()
	plain.set("kind", "item")
	plain.set("item_id", "leather_boots")
	plain.set("stack", ItemDb.gear("leather_boots"))
	treant.get_parent().add_child(plain)
	plain.global_position = player.global_position + Vector2(150, 70)
	await _frames(40)
	await _shot("33_boss_loot")
	var saved_level: int = player.stats.level
	var saved_gear: Dictionary = player.stats.equipment.duplicate(true)
	player.stats.level = 12
	for item_id in ["elderwood_plate", "elderwood_band", "elderwood_gloves", "elderwood_boots"]:
		player.stats.equipment[ItemDb.items[item_id]["slot"]] = ItemDb.gear(item_id)
	player.stats.equipment["cape"] = ItemDb.gear("elderwood_cape")
	player.call("_gear_changed")  # the hero in jade Elderwood, five pieces of six
	var options := {"attack": 6, "crit_chance": 0.035, "attack_speed": 0.1}
	player.add_stack(ItemDb.gear("elderwood_blade", "epic", 0, options))
	hud.toggle_inventory()
	var inventory = hud.get_node("Inventory")
	var index: int = 0
	for i in player.stats.bag.size():
		if player.stats.bag[i]["id"] == "elderwood_blade":
			index = i
	inventory.call("_on_slot_tapped", inventory.bag_slots[index])
	await _shot("34_elderwood_bag")
	# M5: the upgrade window beside the bag, for the blade at +5 after one miss.
	player.stats.bag[index]["plus"] = 5
	player.stats.bag[index]["misses"] = 1
	inventory.refresh(player.stats, null)
	inventory.call("_on_slot_tapped", inventory.bag_slots[index])
	inventory.call("_on_upgrade_pressed")
	await _shot("35_upgrade")
	hud.toggle_inventory()
	player.stats.bag.remove_at(index)
	player.stats.equipment = saved_gear
	player.call("_gear_changed")
	player.stats.level = saved_level


## Taps the first piece of gear in the bag, so its details show.
func _tap_first_gear(player, hud) -> void:
	var inventory = hud.get_node("Inventory")
	for i in player.stats.bag.size():
		if ItemDb.is_gear(player.stats.bag[i]["id"]):
			inventory.call("_on_slot_tapped", inventory.bag_slots[i])
			return
