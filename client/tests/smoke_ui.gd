extends RefCounted
## The interface part of the smoke test (stage 8): the game menu and pausing,
## the settings (volume, left-handed, joystick size, floating joystick), the
## phone's back button and CHANGE HERO. smoke_test.gd runs it near the end.
## t is the test itself (a SceneTree); its _check, _frames and helpers are used.

const Settings = preload("res://scripts/settings.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")

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
