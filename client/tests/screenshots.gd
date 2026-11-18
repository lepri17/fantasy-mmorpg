extends SceneTree
## Saves screenshots of the game for checking the look by eye (not a test).
## Needs a display, for example:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       -s res://tests/screenshots.gd -- /tmp/shots
## Uses its own save file, so a real save is not touched.

const SaveFile = preload("res://scripts/player/save_file.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
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
	Settings.path = "user://screenshots_settings.cfg"
	Settings.load_file()
	Settings.set_value("language", "en")
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
	Settings.set_value("language", "he")
	TranslationServer.set_locale("he")
	player.call("_say", "Got Slime Jelly x2.")
	await _frames(5)
	await _shot("24_hebrew")
	hud.toggle_inventory()
	_tap_first_gear(player, hud)
	await _shot("25_hebrew_bag")
	hud.toggle_inventory()
	hud.toggle_menu()
	hud.get("_menu").show_page("settings")
	await _shot("26_hebrew_settings")
	hud.toggle_menu()
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
	Settings.set_value("language", "en")
	TranslationServer.set_locale("en")
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


## Taps the first piece of gear in the bag, so its details show.
func _tap_first_gear(player, hud) -> void:
	var inventory = hud.get_node("Inventory")
	for i in player.stats.bag.size():
		if ItemDb.is_gear(player.stats.bag[i]["id"]):
			inventory.call("_on_slot_tapped", inventory.bag_slots[i])
			return
