extends RefCounted
## The world part of the smoke test: maps and portals, the death screen, the
## town and its people, quests, Spore Shrooms, the Slime King and invasions.
## smoke_test.gd runs it at the end, when the meadow is no longer needed. t is
## the test itself (a SceneTree); its _check, _frames and helpers are used.

const GameScript = preload("res://scripts/game.gd")
const SkyClock = preload("res://scripts/world/sky.gd")
const TorchScript = preload("res://scripts/world/torch.gd")
const FloatingText = preload("res://scripts/ui/floating_text.gd")
const PICKUP_SCENE = preload("res://scenes/items/pickup.tscn")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")

var t = null


func run(test, main, player, hud) -> void:
	t = test
	# --- maps: a portal to town, the forest, the death screen (last: the meadow is left)
	t._check(
		main.map.map_id == "field" and player.stats.map_id == "field", "the game starts in the meadow"
	)
	var town_portal = null
	for portal in t.get_nodes_in_group("portals"):
		if portal.get("to_map") == "town":
			town_portal = portal
	t._check(town_portal != null, "the meadow has a portal to town")
	if town_portal != null:
		player.global_position = town_portal.global_position
		await t._frames(6)
	t._check(main.map.map_id == "town", "walking into the portal goes to town")
	t._check(t.get_nodes_in_group("enemies").is_empty(), "there are no monsters in town")
	t._check(
		player.global_position.distance_to(main.map.spawn_point("east")) < 5.0,
		"the warrior arrives by the town gate"
	)
	var town_ground = main.map.get_node("Ground")
	t._check(
		(
			town_ground is TileMapLayer
			and town_ground.get_used_cells().size()
			== main.map.data["ground"].size() * String(main.map.data["ground"][0]).length()
		),
		"the town ground is a TileMapLayer built from the map rows"
	)
	t._check(SaveFile.load_data().get("map", "") == "town", "the town is saved as the current map")
	main.change_map("forest", "west")
	await t._frames(3)
	t._check(
		(
			main.map.map_id == "forest"
			and t.get_nodes_in_group("enemies").filter(
				func(enemy): return enemy.monster_id == "blue_slime"
			).size() == 5
		),
		"the forest has its own blue slimes"
	)
	player.take_damage(99999)
	await t._frames(2)
	var death_screen = hud.get_node("DeathScreen")
	t._check(death_screen.visible, "falling shows the death screen")
	death_screen.find_child("TownButton", true, false).pressed.emit()
	await t._frames(4)
	t._check(
		not player.is_dead and main.map.map_id == "town" and not death_screen.visible,
		"RETURN TO TOWN gets the warrior up in town"
	)
	await t._frames(200)
	t._check(
		player.global_position.distance_to(main.map.spawn_point("default")) < 5.0,
		"the old respawn timer does not move him afterwards"
	)

	# --- the townspeople: TALK, the shop, storage, the healer and the guide (W1, W9)
	var townspeople: Array = t.get_nodes_in_group("npcs")
	t._check(townspeople.size() == 6, "six townspeople in Willow Town")
	var mira = townspeople.filter(func(npc): return npc.npc_id == "merchant")[0]
	player.global_position = mira.global_position + Vector2(70, 30)
	await t._frames(4)
	var talk_button = hud.get_node("TalkButton")
	t._check(talk_button.visible, "standing near Mira shows TALK")
	talk_button.pressed.emit()
	var dialog = hud.get_node("NpcDialog")
	t._check(dialog.visible and "Mira" in dialog.get("_name_label").text, "TALK opens Mira's dialog")
	dialog.option("Buy and sell").pressed.emit()
	var shop = hud.get_node("Shop")
	t._check(shop.visible and not dialog.visible, "Buy and sell opens her shop")
	player.stats.gold = 100
	var potions_before_buying: int = player.stats.potions
	shop.request.emit("buy_item", "red_potion")
	t._check(
		player.stats.gold == 80 and player.stats.potions == potions_before_buying + 1,
		"a potion costs 20 gold"
	)
	shop.request.emit("buy_item", "moon_stone")
	t._check(player.stats.gold == 80, "she does not sell what is not on her list")
	while player.stats.bag.size() >= 14:
		player.stats.bag.pop_back()
	var jelly_before: int = player.stats.count_of("slime_jelly")
	player.add_item("slime_jelly", 2)
	shop.request.emit("sell_from_bag", t._bag_index(player, "slime_jelly"))
	t._check(
		player.stats.gold == 87 and player.stats.count_of("slime_jelly") == jelly_before + 1,
		"selling a Slime Jelly gives 7 gold"
	)
	hud.call("_close_windows")
	player.add_item("ember_stone", 3)
	var stones: int = player.stats.count_of("ember_stone")
	player.store_item(t._bag_index(player, "ember_stone"))
	t._check(
		player.stats.count_of("ember_stone") == 0 and player.stats.storage.size() == 1,
		"storing moves the stones out of the bag"
	)
	var kept = PlayerStats.new()
	kept.from_dict(player.stats.to_dict())
	t._check(kept.storage == player.stats.storage, "storage survives saving (version 6)")
	player.take_stored(0)
	t._check(player.stats.count_of("ember_stone") == stones, "TAKE brings them all back")
	player.hp = 10
	player.heal_at_npc()
	t._check(player.hp == player.max_hp, "Sister Lune heals fully")
	# --- quests (W4) and daily quests (W5)
	var quest_book = PlayerStats.new()
	quest_book.level = 2
	var day: String = "2026-11-18"
	t._check(
		quest_book.quests.state("blue_trouble", quest_book, day) == "locked",
		"Blue Trouble waits for Slime Cleanup and level 3"
	)
	t._check(quest_book.quests.start("slime_cleanup", quest_book, day), "Slime Cleanup can be taken")
	for _i in 8:
		quest_book.quests.on_kill("green_slime")
	quest_book.quests.on_kill("blue_slime")
	t._check(
		quest_book.quests.state("slime_cleanup", quest_book, day) == "ready",
		"eight green slimes finish Slime Cleanup"
	)
	quest_book.quests.finish("slime_cleanup", day)
	t._check(
		quest_book.quests.state("slime_cleanup", quest_book, day) == "done", "a quest is done once"
	)
	quest_book.quests.start("daily_patrol", quest_book, day)
	for _i in 15:
		quest_book.quests.on_kill("blue_slime")
	quest_book.quests.finish("daily_patrol", day)
	t._check(
		(
			quest_book.quests.state("daily_patrol", quest_book, day) == "done"
			and quest_book.quests.state("daily_patrol", quest_book, "2026-11-19") == "available"
		),
		"a daily quest comes back the next day"
	)
	var saved_quests = PlayerStats.new()
	saved_quests.from_dict(quest_book.to_dict())
	t._check(saved_quests.quests.done == quest_book.quests.done, "quests survive saving (version 7)")
	while player.stats.bag.size() >= 13:
		player.stats.bag.pop_back()
	var rowan = townspeople.filter(func(npc): return npc.npc_id == "captain")[0]
	var lune = townspeople.filter(func(npc): return npc.npc_id == "healer")[0]
	player.global_position = rowan.global_position + Vector2(70, 30)
	await t._frames(4)
	hud.talk()
	t._check(dialog.option("Quest: A Friendly Face") != null, "Captain Rowan offers a quest")
	if dialog.option("Quest: A Friendly Face") != null:
		dialog.option("Quest: A Friendly Face").pressed.emit()
		dialog.option("Accept").pressed.emit()
	t._check(player.stats.quests.active.has("a_friendly_face"), "Accept takes the quest")
	t._check(
		"A Friendly Face" in hud.get_node("QuestTracker").text, "the quest shows at the top right"
	)
	player.global_position = lune.global_position + Vector2(70, 30)
	await t._frames(4)
	hud.talk()
	hud.call("_close_windows")
	player.global_position = rowan.global_position + Vector2(70, 30)
	await t._frames(4)
	hud.talk()
	var blue_before_reward: int = player.stats.count_of("blue_potion")
	if dialog.option("Complete: A Friendly Face") != null:
		dialog.option("Complete: A Friendly Face").pressed.emit()
	t._check(
		(
			player.stats.quests.done.has("a_friendly_face")
			and player.stats.count_of("blue_potion") == blue_before_reward + 2
		),
		"after talking to Sister Lune, Rowan gives the reward"
	)
	hud.call("_close_windows")
	player.accept_quest("sticky_business")
	player.add_item("slime_jelly", 5)
	var jelly_held: int = player.stats.count_of("slime_jelly")
	player.turn_in_quest("sticky_business")
	t._check(
		(
			player.stats.count_of("slime_jelly") == jelly_held - 5
			and player.stats.quests.done.has("sticky_business")
		),
		"Sticky Business takes 5 Slime Jelly for its reward"
	)
	hud.toggle_character()
	var journal = hud.get_node("Character")
	journal.show_page("quests")
	t._check(
		journal.get("_quest_rows").get_child_count() > 0, "the QUESTS page lists quests to take"
	)
	hud.toggle_character()

	player.stats.gold = 100
	player.travel("forest")
	await t._frames(3)
	t._check(
		main.map.map_id == "forest" and player.stats.gold == 60,
		"Tessa sends the warrior to the forest for 40 gold"
	)
	var forest_enemies: Array = t.get_nodes_in_group("enemies")
	var shrooms: Array = forest_enemies.filter(func(enemy): return enemy.monster_id == "spore_shroom")
	t._check(shrooms.size() == 3, "three Spore Shrooms grow in the forest")
	if not shrooms.is_empty():
		t._freeze(forest_enemies, true)
		shrooms[0].set_physics_process(true)
		player.hp = player.max_hp
		player.set("_invincible_left", 0.0)
		player.global_position = shrooms[0].global_position + Vector2(-210, 0)
		var hp_before_spores: int = player.hp
		var saw_spore := false
		for _i in 240:
			await t._frames(1)
			saw_spore = saw_spore or not t.get_nodes_in_group("projectiles").is_empty()
			if player.hp < hp_before_spores:
				break
		t._check(saw_spore, "a Spore Shroom shoots spores")
		t._check(player.hp < hp_before_spores, "a spore hits the warrior (hp %d)" % player.hp)

	# --- the Slime King (C9): it roams, and is not always in the forest
	t._check(t.get_nodes_in_group("bosses").is_empty(), "no boss stands in the forest all the time")
	main.bosses.appear("slime_king", "forest")
	var kings: Array = t.get_nodes_in_group("bosses")
	t._check(
		kings.size() == 1 and kings[0].monster_id == "slime_king",
		"the Slime King can appear in the forest"
	)
	if not kings.is_empty():
		var king = kings[0]
		t._freeze(t.get_nodes_in_group("enemies"), true)
		player.hp = player.max_hp
		player.global_position = king.global_position + Vector2(-320, 0)
		await t._frames(3)
		var boss_bar = hud.get_node("BossBar")
		t._check(
			boss_bar.visible and "Slime King" in boss_bar.get_child(0).text,
			"a big health bar shows the Slime King"
		)
		king.take_damage(king.max_hp / 2 + 10)
		t._check(king.get("_enraged"), "below half health the King is enraged")
		king.set_physics_process(true)
		await t._frames(3)
		var green_helpers: int = t.get_nodes_in_group("enemies").filter(
			func(enemy): return enemy.monster_id == "green_slime"
		).size()
		t._check(green_helpers >= 2, "an enraged King calls green slimes (%d)" % green_helpers)
		king.take_damage(99999, Vector2.ZERO, false, player)
		t._check(
			king.is_dead and player.stats.record.earned.has("king_slayer"),
			"beating the King earns King Slayer"
		)
		await t._frames(2)
		var rest: float = float(main.bosses.bosses["slime_king"]["wait"])
		t._check(
			not main.bosses.is_out("slime_king") and rest >= 400.0,
			"beaten, the King stays away for minutes before it comes again (%d s)" % rest
		)

	# --- a golden slime invasion in the meadow (W7)
	var window_rule := {"every_minutes": 30, "lasts_minutes": 5}
	t._check(
		(
			GameScript.invasion_window(
				window_rule, {"year": 2026, "month": 11, "day": 18, "hour": 14, "minute": 33}
			) == "2026-11-18 14:30"
			and GameScript.invasion_window(
				window_rule, {"year": 2026, "month": 11, "day": 18, "hour": 14, "minute": 40}
			) == ""
		),
		"invasions come in the first 5 minutes of every half hour"
	)
	main.change_map("field", "default")
	await t._frames(3)
	main.start_invasion()
	var invaders: Array = t.get_nodes_in_group("invaders")
	t._check(
		invaders.size() == 6 and invaders.all(func(slime): return slime.monster_id == "golden_slime"),
		"six Golden Slimes invade the meadow"
	)
	main.end_invasion()
	await t._frames(2)
	t._check(t.get_nodes_in_group("invaders").is_empty(), "when the time is up they run off")

	# --- the Old Cellar dungeon (W6): waves, the boss, the reward, entries per day
	main.change_map("cellar")
	await t._frames(3)
	var run = main.map.get_node_or_null("DungeonRun")
	t._check(
		(
			main.map.map_id == "cellar"
			and run != null
			and player.stats.dungeons.runs["cellar"]["count"] == 1
		),
		"going into the Old Cellar uses one of today's entries"
	)
	var torches: int = main.map.get_children().filter(
		func(node): return node.get_script() == TorchScript
	).size()
	t._check(
		torches == 5 and main.get_node("Daylight").color == SkyClock.INDOOR,
		"the cellar is dark and lit by five torches"
	)
	if run != null:
		run.wave_delay = 0.05
		var gold_before_run: int = player.stats.gold
		for _i in 600:
			await t._frames(1)
			for monster in t.get_nodes_in_group("enemies"):
				if not monster.is_dead:
					monster.take_damage(99999, Vector2.ZERO, false, player)
			if run.cleared:
				break
		t._check(
			run.cleared and run.wave == 3, "three waves and then the boss: the cellar is cleared"
		)
		t._check(player.stats.gold >= gold_before_run + 400, "clearing it pays the reward")
		await t._frames(2)
		var way_out: Array = t.get_nodes_in_group("portals").filter(
			func(portal): return portal.to_map == "town"
		)
		t._check(way_out.size() == 1, "a portal out to town opens")
	main.change_map("town")
	await t._frames(3)
	var today: String = Time.get_date_string_from_system()
	player.stats.dungeons.runs["cellar"] = {"date": today, "count": 3}
	main.change_map("cellar")
	await t._frames(3)
	t._check(main.map.map_id == "town", "after 3 entries in a day the cellar stays shut")
	var runs_saved = PlayerStats.new()
	runs_saved.from_dict(player.stats.to_dict())
	t._check(
		runs_saved.dungeons.runs == player.stats.dungeons.runs, "entries survive saving (version 8)"
	)

	# --- day and night, rain, music, the minimap, loot magnet, pooling, the silhouette (6D)
	t._check(
		(
			SkyClock.daylight(300.0) == SkyClock.DAY
			and SkyClock.daylight(720.0).is_equal_approx(SkyClock.NIGHT)
			and is_equal_approx(SkyClock.darkness(SkyClock.NIGHT), 1.0)
		),
		"a 16-minute day: light at the start, night three quarters in"
	)
	t._check(
		SkyClock.raining(1248.0) and not SkyClock.raining(300.0), "rain comes in some cycles only"
	)
	GameScript.sky_seconds = 720.0
	main.update_sky()
	t._check(
		main.get_node("Daylight").color.is_equal_approx(SkyClock.NIGHT) and player.get("_light").enabled,
		"at night the world is darker and the warrior carries a light"
	)
	GameScript.sky_seconds = 300.0
	main.update_sky()
	t._check(not player.get("_light").enabled, "by day the light is off")
	var music = main.get_node("Music")
	t._check(
		music.stream != null and music.stream.resource_path.ends_with("music_town.wav"),
		"the town plays its own music"
	)
	var dots: Array = hud.get_node("Minimap").markers()
	t._check(
		dots.any(func(dot): return dot[1] == Color(1, 1, 1)) and dots.size() > 5,
		"the minimap shows the warrior, townspeople and portals (%d dots)" % dots.size()
	)
	var gold_before_magnet: int = player.stats.gold
	var coins: Node2D = PICKUP_SCENE.instantiate()
	coins.set("kind", "gold")
	coins.set("amount", 5)
	coins.position = player.position + Vector2(70, 0)
	main.map.add_child(coins)
	await t._frames(40)
	t._check(player.stats.gold == gold_before_magnet + 5, "loot close by drifts to the warrior")
	FloatingText.spawn(player, "pool", Color.WHITE)
	await t._frames(60)
	var pool: Node = main.get_node("TextPool")
	var waiting: int = pool.get_child_count()
	FloatingText.spawn(player, "again", Color.WHITE)
	t._check(
		waiting > 0 and pool.get_child_count() == waiting - 1,
		"floating numbers reuse finished labels"
	)
	var town_tree: Node2D = t.get_nodes_in_group("trees").filter(
		func(tree): return tree.global_position.y > 600
	)[0]
	player.global_position = town_tree.global_position + Vector2(0, -60)
	await t._frames(12)
	t._check(player.get("_silhouette").visible, "behind a tree the warrior shows as a silhouette")
	player.global_position = main.map.spawn_point("default")
	await t._frames(12)
	t._check(not player.get("_silhouette").visible, "in the open the silhouette is gone")
	player.gain_xp(player.stats.xp_to_next())
	t._check(not t.get_nodes_in_group("bursts").is_empty(), "a level up sprays particles")
