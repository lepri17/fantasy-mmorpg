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

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	SaveFile.path = SAVE_PATH
	_remove_test_save()
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
	_check(enemies.size() == 6, "six slimes on the map (found %d)" % enemies.size())
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
	var waited: int = 0
	while not slime.is_dead and waited < 600:
		await _frames(1)
		waited += 1
	Input.action_release("attack")
	_check(slime.is_dead, "slime dies under repeated attacks (after %d frames)" % waited)
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
	var first = inventory.bag_slots[0]
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
		player.stats.equipment.get("weapon", "") == "training_sword",
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

	# --- a moment of invincibility after a hit
	player.global_position = Vector2(1000, 500)
	await _frames(70)  # any blinking from earlier hits is over
	var hp_before_hits: int = player.hp
	player.take_damage(5)
	player.take_damage(5)
	_check(player.hp == hp_before_hits - 5, "right after a hit the warrior cannot be hurt again")
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

	_remove_test_save()
	print("SMOKE TEST: %s" % ("PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _remove_test_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


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
