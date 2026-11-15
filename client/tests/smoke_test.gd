extends SceneTree
## Headless smoke test: really runs the main scene in Godot and checks the
## basics (walking, obstacles, attacking, enemy damage, enemy death).
##
## Run from the client folder:
##   godot --headless -s res://tests/smoke_test.gd
## Exit code 0 = all checks passed.

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)

	var player = get_first_node_in_group("player")
	_check(player != null, "player exists")
	if player == null:
		quit(1)
		return
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
	_check(get_nodes_in_group("enemies").size() == 3, "three slimes on the map")
	_check(sprite.animation == &"idle_down", "starts in idle_down")

	# --- obstacle: walk straight into a tree
	var tree: Node2D = get_first_node_in_group("obstacles")
	_check(tree != null, "an obstacle exists")
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
	_check(walked > 80.0 and walked < 140.0, "walks right at about 220 px/s (moved %d px)" % walked)
	_check(sprite.animation == &"idle_right", "idle_right after stopping")
	await _hold("move_up", 10)
	_check(player.facing == "up", "faces up after moving up")
	await _hold("move_left", 10)
	_check(player.facing == "left", "faces left after moving left")
	await _hold("move_down", 10)
	_check(player.facing == "down", "faces down after moving down")

	# --- combat: stand left of a slime, face it, attack until it dies
	var slime = get_first_node_in_group("enemies")
	player.global_position = slime.global_position + Vector2(-70, 0)
	await _hold("move_right", 2)
	Input.action_press("attack")
	await _frames(3)
	_check(String(sprite.animation).begins_with("attack_"), "attack animation plays")
	_check(slime.hp < slime.max_hp, "attack damages the slime (hp %d/%d)" % [slime.hp, slime.max_hp])
	var waited: int = 0
	while not slime.is_dead and waited < 600:
		await _frames(1)
		waited += 1
	Input.action_release("attack")
	_check(slime.is_dead, "slime dies under repeated attacks (after %d frames)" % waited)
	_check(player.hp < player.max_hp, "slime hurt the warrior (hp %d/%d)" % [player.hp, player.max_hp])

	# --- attack out of range does nothing
	var other = get_nodes_in_group("enemies")[1]
	var hp_before: int = other.hp
	player.global_position = other.global_position + Vector2(-400, 0)
	await _frames(2)
	Input.action_press("attack")
	await _frames(5)
	Input.action_release("attack")
	_check(other.hp == hp_before, "attack out of range does no damage")

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
