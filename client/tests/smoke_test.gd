extends SceneTree
## Headless smoke test: really runs the main scene in Godot and checks the
## basics (walking, obstacles, combat, loot, levels, skill, potion, death, save).
##
## Run from the client folder:
##   godot --headless -s res://tests/smoke_test.gd
## Exit code 0 = all checks passed. Note: it deletes the local save file.

const SAVE_PATH := "user://save.cfg"
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)

	var player = get_first_node_in_group("player")
	_check(player != null, "player exists")
	if player == null:
		quit(1)
		return
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
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

	# --- death and respawn
	player.global_position = Vector2(1000, 500)
	await _frames(2)
	player.take_damage(99999)
	_check(player.is_dead, "the warrior dies at 0 HP")
	var death_position: Vector2 = player.global_position
	await _hold("move_right", 15)
	_check(player.global_position == death_position, "a dead warrior cannot move")
	await _frames(200)
	_check(not player.is_dead and player.hp == player.max_hp, "respawns with full HP")
	_check(player.global_position.distance_to(Vector2(1280, 768)) < 5.0, "respawns at the start")

	print("SMOKE TEST: %s" % ("PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


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
