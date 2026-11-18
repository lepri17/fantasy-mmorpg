extends RefCounted
## The interface part of the smoke test (stage 8): the game menu and pausing,
## the settings (volume, left-handed, joystick size, floating joystick), the
## phone's back button, CHANGE HERO, auto hunt, Hebrew, the hints for a new hero,
## the button editor, text size and colour-blind colours. smoke_test.gd runs it
## near the end.
## t is the test itself (a SceneTree); its _check, _frames and helpers are used.

const Settings = preload("res://scripts/settings.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")
const MapGuide = preload("res://scripts/maps/map_guide.gd")
const Language = preload("res://scripts/i18n/language.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Tutorial = preload("res://scripts/ui/tutorial.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
## Where the monsters not in a test wait, frozen.
const PARK := Vector2(2300, 1350)

var t = null


func run(test, main, player, hud) -> void:
	t = test
	var menu: Control = hud.get("_menu")
	var touch: CanvasLayer = main.get_node("TouchControls")
	var joystick: Control = touch.get_node("Joystick")
	var attack_button: Control = touch.get_node("AttackButton")
	t._check(
		hud.get_node("MenuButton").visible and not menu.visible, "a MENU button sits at the top"
	)
	hud.toggle_menu()
	t._check(menu.visible and t.paused, "MENU opens the menu and pauses the game")
	t._check(not attack_button.visible, "the round buttons hide behind the menu")
	menu.show_page("settings")

	Settings.set_value("music", 0.5)
	var music_bus: int = AudioServer.get_bus_index("Music")
	t._check(
		music_bus != -1 and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.5)),
		"the music plays at the volume set"
	)
	t._check(
		main.get_node("Music").bus == "Music", "the music goes through the Music volume"
	)
	Settings.set_value("sounds", 0.0)
	t._check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Sounds")), "sounds at 0% are off")
	Settings.load_file()
	t._check(
		is_equal_approx(float(Settings.get_value("music")), 0.5), "the settings are kept on the device"
	)
	Settings.set_value("sounds", 1.0)

	Settings.set_value("left_handed", true)
	touch.apply_settings()
	t._check(
		joystick.anchor_left == 1.0 and attack_button.anchor_right == 0.0,
		"left-handed: the joystick moves right and the buttons left"
	)
	Settings.set_value("left_handed", false)
	touch.apply_settings()
	t._check(joystick.anchor_left == 0.0 and attack_button.anchor_left == 1.0, "and back again")
	Settings.set_value("joystick_size", 1.2)
	touch.apply_settings()
	t._check(
		is_equal_approx(joystick.size.x, 360.0) and is_equal_approx(joystick.get("size_scale"), 1.2),
		"a bigger joystick at 120%"
	)
	Settings.set_value("joystick_size", 1.0)
	touch.apply_settings()
	hud.call("_on_menu_request", "resume")
	t._check(not menu.visible and not t.paused, "RESUME closes the menu and the game goes on")
	t._check(attack_button.visible, "the round buttons come back")

	Settings.set_value("floating_joystick", true)
	touch.apply_settings()
	var thumb := InputEventScreenTouch.new()
	thumb.index = 2
	thumb.pressed = true
	thumb.position = Vector2(560, 520)
	joystick.call("_input", thumb)
	var slide := InputEventScreenDrag.new()
	slide.index = 2
	slide.position = Vector2(660, 520)
	joystick.call("_input", slide)
	t._check(
		Input.get_action_strength("move_right") > 0.5,
		"a floating joystick starts where the thumb goes down"
	)
	thumb.pressed = false
	joystick.call("_input", thumb)
	t._check(Input.get_action_strength("move_right") == 0.0, "and stops when it lets go")
	thumb.pressed = true
	thumb.position = attack_button.get_global_rect().get_center()
	joystick.call("_input", thumb)
	t._check(
		Input.get_action_strength("move_right") == 0.0 and joystick.get("_touch_index") == -1,
		"a touch on a round button is not taken by the floating joystick"
	)
	Settings.set_value("floating_joystick", false)
	touch.apply_settings()

	hud.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	t._check(menu.visible, "the phone's back button opens the menu")
	hud.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	t._check(not menu.visible and not t.paused, "and closes it again")
	hud.toggle_inventory()
	hud.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	t._check(
		not hud.get("_inventory").visible and not menu.visible,
		"back closes an open window first"
	)

	hud.leaves_game = false
	hud.toggle_menu()
	player.stats.gold += 7
	hud.call("_on_menu_request", "change_hero")
	t._check(
		not t.paused and int(SaveFile.load_data().get("gold", -1)) == player.stats.gold,
		"CHANGE HERO saves the hero before leaving"
	)
	await t._frames(2)
	await _check_auto(main, player, hud)
	await _check_hebrew(hud)
	_check_tutorial(player, hud)
	_check_editor(main, hud)
	_check_text_and_colours(hud)


## Q10: the Hebrew interface.
func _check_hebrew(hud) -> void:
	Language.set_language("he")
	t._check(
		TranslationServer.get_locale().begins_with("he") and tr("Slime") == "סליים",
		"in Hebrew, names are translated"
	)
	t._check(
		TranslationServer.translate("Got Slime Jelly x2.") == "קיבלת ג'לי סליים x2.",
		"a sentence with blanks is translated, and what is in the blanks too"
	)
	t._check(
		TranslationServer.translate("Lv.1 Elite Slime") == "רמה 1 סליים עלית"
		and TranslationServer.translate("Rare Oak Staff +3") == "מטה אלון +3 נדיר",
		"names the game builds (level, elite, rarity, upgrade) are translated"
	)
	t._check(
		(
			TranslationServer.translate("Slime Cleanup  3/8\nDaily Patrol  15/15  (done)")
			== "ניקוי סליימים  3/8\nסיור יומי  15/15  (בוצע)"
		),
		"a list of lines is translated line by line"
	)
	var menu_button: Button = hud.get_node("MenuButton")
	t._check(
		menu_button.atr(menu_button.text) == "תפריט" and UiStyle.stat_name("attack") == "התקפה",
		"buttons and stat names show in Hebrew"
	)
	Settings.load_file()
	t._check(Settings.get_value("language") == "he", "the chosen language is kept")
	await t._frames(2)
	Language.set_language("en")
	t._check(tr("Slime") == "Slime" and UiStyle.stat_name("attack") == "Attack", "and back to English")


## U5 auto hunt and U6 walking to a quest's target.
func _check_auto(main, player, hud) -> void:
	t._check(
		MapGuide.next_map("town", "forest") == "field" and MapGuide.next_map("forest", "town") == "field",
		"the map guide knows the way between maps"
	)
	t._check(
		MapGuide.map_with_monster("spore_shroom", "town") == "forest"
		and MapGuide.map_with_npc("merchant") == "town"
		and MapGuide.monster_dropping("slime_jelly") != "",
		"and where monsters, townspeople and loot are"
	)
	main.change_map("field", "default")
	await t._frames(20)
	var enemies: Array = t.get_nodes_in_group("enemies").filter(func(enemy): return not enemy.is_dead)
	t._freeze(enemies, true)
	for enemy in enemies:
		enemy.global_position = PARK
	var prey: Node2D = enemies[0]
	prey.global_position = player.global_position + Vector2(260, 0)
	prey.evasion = 0.0
	prey.hp = 1
	player.toggle_auto_hunt()
	t._check(player.auto.hunting, "AUTO starts hunting")
	var waited: int = 0
	while not prey.is_dead and waited < 400:
		await t._frames(5)
		waited += 5
	t._check(prey.is_dead, "auto hunt walks to a slime and defeats it (%d frames)" % waited)
	hud.call("_update_action_buttons")
	t._check(_button(hud, "auto_hunt").get("badge") == "ON", "the AUTO button shows ON")
	player.toggle_auto_hunt()
	t._check(not player.auto.active(), "tapping AUTO again stops it")
	t._freeze(t.get_nodes_in_group("enemies"), false)

	player.auto.walk_goal = {"map": "town", "npc": "merchant"}
	waited = 0
	while not player.auto.walk_goal.is_empty() and waited < 1800:
		await t._frames(10)
		waited += 10
	var mira: Node2D = null
	for npc in t.get_nodes_in_group("npcs"):
		if npc.get("npc_id") == "merchant":
			mira = npc
	t._check(
		(
			main.map.map_id == "town"
			and mira != null
			and player.global_position.distance_to(mira.global_position) < 160.0
		),
		"a quest walk goes through the portal to town and stops at Mira (%d frames)" % waited
	)
	player.toggle_auto_hunt()
	t._check(not player.auto.hunting, "there is nothing to hunt in town")
	player.auto.walk_goal = {"map": "field", "monster": "green_slime", "hunt": true}
	Input.action_press("move_down")
	await t._frames(3)
	Input.action_release("move_down")
	await t._frames(1)
	t._check(player.auto.walk_goal.is_empty(), "moving by hand ends a walk")
	var quest_id: String = "slime_cleanup"
	if not player.stats.quests.active.is_empty():
		quest_id = player.stats.quests.active.keys()[0]
	t._check(
		player.auto.walk_to_quest(quest_id) and MapGuide.maps().has(player.auto.walk_goal["map"]),
		"tapping a quest sets out for its target (%s)" % quest_id
	)
	player.auto.stop()


## U2: one hint at a time for a new hero, each gone once it is done.
func _check_tutorial(player, hud) -> void:
	var tutorial: Control = hud.get_node("Tutorial")
	var label: Label = tutorial.find_children("*", "Label", true, false)[0]
	t._check(PlayerStats.new().tutorial == 0, "a new hero starts with the hints")
	var saved: Dictionary = player.stats.to_dict()
	t._check(
		int(saved["version"]) == 10 and saved.has("tutorial"), "the save keeps the hint step (v10)"
	)
	saved.erase("tutorial")
	var older := PlayerStats.new()
	older.from_dict(saved)
	t._check(older.tutorial >= Tutorial.STEPS.size(), "a hero from an older save gets no hints")
	var counters: Dictionary = player.stats.record.counters
	var was_at: Vector2 = player.global_position
	player.stats.tutorial = 0
	tutorial.set("_start", {})
	tutorial.update(0.25)
	t._check(
		tutorial.visible and label.text == Tutorial.STEPS[0][1], "the first hint is about moving"
	)
	player.global_position += Vector2(200, 0)
	tutorial.update(0.25)
	t._check(player.stats.tutorial == 1, "moving ends it, and the next hint comes")
	counters["kills"] = int(counters.get("kills", 0)) + 1
	tutorial.update(0.25)
	player.stats.gold += 1
	tutorial.update(0.25)
	counters["skills_used"] = int(counters.get("skills_used", 0)) + 1
	tutorial.update(0.25)
	t._check(player.stats.tutorial == 4, "a kill, loot and a skill end the next three")
	hud.toggle_inventory()
	tutorial.update(0.25)
	hud.toggle_inventory()
	tutorial.update(0.25)
	tutorial.update(0.25)
	t._check(
		player.stats.tutorial == Tutorial.STEPS.size() - 1, "the bag, town and a quest end the rest"
	)
	tutorial.update(Tutorial.LAST_SECONDS + 0.1)
	t._check(
		not tutorial.visible and player.stats.tutorial == Tutorial.STEPS.size(),
		"the last hint goes away by itself"
	)
	player.stats.tutorial = 2
	tutorial.update(0.25)
	var skip: Button = tutorial.find_children("*", "Button", true, false)[0]
	skip.pressed.emit()
	t._check(
		(
			not tutorial.visible
			and int(SaveFile.load_data().get("tutorial", -1)) == Tutorial.STEPS.size()
		),
		"SKIP ends the hints, and that is saved"
	)
	player.global_position = was_at


## U4: moving the touch buttons and making them bigger.
func _check_editor(main, hud) -> void:
	var touch: CanvasLayer = main.get_node("TouchControls")
	var attack_button: Control = touch.get_node("AttackButton")
	var editor: Control = touch.get_node("ButtonEditor")
	var home: Rect2 = attack_button.get_global_rect()
	hud.toggle_menu()
	hud.get("_menu").show_page("controls")
	hud.call("_on_menu_request", "edit_buttons")
	t._check(
		editor.visible and t.paused and not hud.get("_menu").visible and attack_button.visible,
		"EDIT BUTTONS shows the buttons to move, and the game waits"
	)
	_drag(editor, home.get_center(), Vector2(-60, -40))
	t._check(
		attack_button.get_global_rect().position.is_equal_approx(home.position + Vector2(-60, -40)),
		"dragging a button moves it"
	)
	Settings.load_file()
	t._check(Settings.get_value("button_offsets").has("AttackButton"), "the new place is kept")
	var offsets: Dictionary = Settings.get_value("button_offsets")
	Settings.set_value("left_handed", true)
	Settings.set_value("button_offsets", {})
	touch.apply_settings()
	var mirrored_home: Rect2 = attack_button.get_global_rect()
	Settings.set_value("button_offsets", offsets)
	touch.apply_settings()
	t._check(
		attack_button.get_global_rect().position.is_equal_approx(
			mirrored_home.position + Vector2(60, -40)
		),
		"left-handed, the moved button is mirrored too"
	)
	Settings.set_value("left_handed", false)
	touch.call("_change_size", 1)
	t._check(
		attack_button.size.is_equal_approx(home.size * 1.1)
		and touch.get_node("Joystick").size.is_equal_approx(Vector2(300, 300)),
		"SIZE + makes the round buttons bigger, not the joystick"
	)
	touch.call("_reset_layout")
	t._check(attack_button.get_global_rect().is_equal_approx(home), "RESET puts everything back")
	_drag(editor, home.get_center(), Vector2(5000, 5000))
	t._check(
		editor.get_global_rect().grow(0.5).encloses(attack_button.get_global_rect()),
		"a button cannot be dragged off the screen"
	)
	touch.call("_reset_layout")
	hud.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	t._check(
		not editor.visible and not t.paused and not hud.get("_menu").visible,
		"the back button ends the editor and the game goes on"
	)


func _drag(editor: Control, from: Vector2, amount: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	editor.gui_input.emit(press)
	var motion := InputEventMouseMotion.new()
	motion.position = from + amount
	motion.relative = amount
	editor.gui_input.emit(motion)
	var lift := InputEventMouseButton.new()
	lift.button_index = MOUSE_BUTTON_LEFT
	lift.position = from + amount
	editor.gui_input.emit(lift)


## U7: a bigger text size and colours told apart with any colour vision.
func _check_text_and_colours(hud) -> void:
	var sample: Control = null
	for node in hud.find_children("*", "Label", true, false):
		if node.has_meta("design_font_size"):
			sample = node
			break
	var design: int = int(sample.get_meta("design_font_size"))
	Settings.set_value("text_size", 1.2)
	hud.call("_on_menu_request", "settings_changed")
	var fresh: Label = UiStyle.label("x", 20, Color.WHITE)
	var auto_potion: Button = hud.get_node("Inventory").get("_auto_button")
	t._check(
		(
			sample.get_theme_font_size("font_size") == roundi(design * 1.2)
			and fresh.get_theme_font_size("font_size") == 24
			and auto_potion.get_theme_font_size("font_size") == 17
		),
		"a bigger text size makes the window texts bigger, open or new (or sized by hand)"
	)
	fresh.free()
	Settings.set_value("text_size", 1.0)
	hud.call("_on_menu_request", "settings_changed")
	t._check(sample.get_theme_font_size("font_size") == design, "and back to the usual size")
	var rare := {"rarity": "rare"}
	var usual: Color = ItemDb.rarity_color(rare)
	Settings.set_value("colorblind", true)
	t._check(
		(
			ItemDb.rarity_color(rare).is_equal_approx(Color(0.9, 0.62, 0.0))
			and ItemDb.rarity_color({"rarity": "uncommon"}).is_equal_approx(Color(0.34, 0.71, 0.91))
		),
		"colour-blind colours: uncommon sky blue, rare orange"
	)
	Settings.set_value("colorblind", false)
	t._check(ItemDb.rarity_color(rare).is_equal_approx(usual), "and the usual colours come back")


func _button(hud, action: String) -> Control:
	for button in hud.get_tree().get_nodes_in_group("action_buttons"):
		if button.get("action") == action:
			return button
	return null
