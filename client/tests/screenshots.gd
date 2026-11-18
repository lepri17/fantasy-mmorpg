extends SceneTree
## Saves screenshots of the game for checking the look by eye (not a test).
## Needs a display, for example:
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       -s res://tests/screenshots.gd -- /tmp/shots
## Uses its own save file, so a real save is not touched.

const SaveFile = preload("res://scripts/player/save_file.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const SAVE_PATH := "user://screenshots_save.cfg"

var _folder: String = "/tmp/shots"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_folder = args[0]
	DirAccess.make_dir_recursive_absolute(_folder)
	SaveFile.path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
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
	await _shot("01_meadow")
	hud.toggle_inventory()
	hud.get_node("Inventory").call("_on_slot_tapped", hud.get_node("Inventory").bag_slots[2])
	await _shot("02_inventory")
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit()


func _shot(file_name: String) -> void:
	await _frames(12)
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_folder, file_name])


func _frames(count: int) -> void:
	for i in count:
		await process_frame
