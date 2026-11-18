extends RefCounted
## The class part of the smoke test (stage 7): the Mage and the Archer, their
## gear, art, attacks and skills, the job skills of all three classes, and what
## the HUD, the shop and the loot do for each class. smoke_test.gd runs it last.
## The live hero becomes each class in place, the way a new character starts.
## t is the test itself (a SceneTree); its _check, _frames and helpers are used.

const ClassDb = preload("res://scripts/player/class_db.gd")
const HeroLook = preload("res://scripts/player/hero_look.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const GameData = preload("res://scripts/data/game_data.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")
const SELECT_SCENE = preload("res://scenes/ui/character_select.tscn")
## Where the monsters not in a test wait, frozen.
const PARK := Vector2(2300, 1350)

var t = null


func run(test, main, player, hud) -> void:
	t = test
	_check_data()
	_check_stats(player)
	main.change_map("field", "default")
	await t._frames(20)
	await _check_mage(player, hud)
	await _check_archer(player, hud)
	await _check_warrior_job(player, hud)
	await _check_select()


func _check_data() -> void:
	t._check(ClassDb.ids() == ["warrior", "mage", "archer"], "three classes: Warrior, Mage, Archer")
	var five_each := true
	for class_id in ClassDb.ids():
		five_each = five_each and ClassDb.skills(class_id).size() == 5
	t._check(five_each, "each class has five skills (the fifth comes with the job advancement)")
	t._check(
		(
			ClassDb.rule("mage", "base_max_hp") < ClassDb.rule("warrior", "base_max_hp")
			and ClassDb.rule("archer", "move_speed") == ClassDb.rule("warrior", "move_speed")
		),
		"classes have their own numbers (less HP for the mage), the rest from character.json"
	)
	t._check(
		(
			float(ClassDb.stat_rule("mage", "energy")["attack"]) > 0.0
			and not ClassDb.stat_rule("warrior", "energy").has("attack")
		),
		"Energy gives the mage attack; it does not for the warrior"
	)


func _check_stats(player) -> void:
	var mage = PlayerStats.new()
	mage.from_dict({"version": 9, "class": "mage", "name": "Aria"})
	t._check(
		mage.class_id == "mage" and mage.hero_name == "Aria", "a new mage keeps its class and name"
	)
	t._check(
		(
			mage.equipped_id("weapon") == "oak_staff"
			and mage.equipped_id("head") == "sage_hat"
			and mage.equipped_id("armor") == "violet_robe"
		),
		"a new mage starts with a staff, a hat and a robe"
	)
	t._check(
		is_equal_approx(mage.max_stamina(), 140.0),
		"the mage has more mana: 120, +20 from the hat and robe (%.0f)" % mage.max_stamina()
	)
	mage.bag.append(ItemDb.gear("training_sword"))
	t._check(not mage.equip(mage.bag.size() - 1), "a mage cannot wear a warrior's sword")
	mage.advanced = true
	var saved = PlayerStats.new()
	saved.from_dict(mage.to_dict())
	t._check(
		saved.class_id == "mage" and saved.advanced and saved.hero_name == "Aria",
		"class, job advancement and name survive saving (version 9)"
	)
	var old_save: Dictionary = player.stats.to_dict()
	old_save.erase("class")
	old_save["version"] = 8
	var old = PlayerStats.new()
	old.from_dict(old_save)
	t._check(
		old.class_id == "warrior" and old.equipped_id("weapon") == player.stats.equipped_id("weapon"),
		"an old save (version 8) loads as the warrior it was"
	)
	var mage_look: ImageTexture = HeroLook.build(mage.equipment, "mage")
	var warrior_look: ImageTexture = HeroLook.build(player.stats.equipment, "warrior")
	t._check(
		(
			mage_look.get_size() == warrior_look.get_size()
			and mage_look.get_image().get_data() != warrior_look.get_image().get_data()
		),
		"the mage has its own art, in the same sheet layout"
	)


func _check_mage(player, hud) -> void:
	_become(player, hud, "mage")
	t._check(
		player.stats.class_id == "mage" and player.look_texture != null,
		"the hero becomes a mage, with the mage's look"
	)
	t._check(_button_label(hud, "skill") == "FIRE", "the first skill button says FIRE for the mage")
	t._check(not _button(hud, "skill_5").visible, "the fifth button waits for the job advancement")
	var dummy: Node2D = _line_up(player, [Vector2(150, 0)])[0]
	player.facing = "right"
	var hp_before: int = dummy.hp
	player.call("_attack")
	t._check(
		not t.get_nodes_in_group("hero_shots").is_empty(), "the mage's attack fires a magic bolt"
	)
	await t._frames(30)
	t._check(dummy.hp < hp_before, "the bolt flies to the slime (%d -> %d)" % [hp_before, dummy.hp])

	var pair: Array = _line_up(player, [Vector2(170, 0), Vector2(200, 45)])
	var before: Array = pair.map(func(enemy): return enemy.hp)
	_ready_to_cast(player)
	t._check(player.use_skill("fireball"), "Fireball can be cast")
	await t._frames(40)
	t._check(
		pair[0].hp < before[0] and pair[1].hp < before[1],
		"the fireball bursts on the first slime and burns the one next to it"
	)
	pair = _line_up(player, [Vector2(70, 0), Vector2(-60, 30)])
	before = pair.map(func(enemy): return enemy.hp)
	_ready_to_cast(player)
	player.use_skill("frost_nova")
	t._check(
		pair[0].hp < before[0] and pair[1].hp < before[1], "Frost Nova hits all around the mage"
	)
	t._check(
		pair[0].statuses.is_active("slow") and pair[1].statuses.is_active("slow"),
		"Frost Nova slows the slimes it hits"
	)
	_ready_to_cast(player)
	player.use_skill("mana_shield")
	var hp_shielded: int = player.hp
	player.take_damage(100)
	t._check(
		hp_shielded - player.hp == 60 and not t.get_nodes_in_group("shield_bubbles").is_empty(),
		"Mana Shield: 40%% less damage (100 -> %d), with a bubble" % (hp_shielded - player.hp)
	)
	player.set("_guard_left", 0.0)
	await t._frames(2)
	dummy = _line_up(player, [Vector2(160, 0)])[0]
	hp_before = dummy.hp
	player.add_item("book_meteor")
	player.use_from_bag(t._bag_index(player, "book_meteor"))
	t._check(player.stats.knows_skill("meteor"), "the mage learns Meteor from its book")
	_ready_to_cast(player)
	player.use_skill("meteor")
	t._check(not t.get_nodes_in_group("telegraphs").is_empty(), "Meteor marks where it will fall")
	t._check(dummy.hp == hp_before, "the meteor has not landed yet")
	await t._frames(60)
	t._check(
		dummy.hp < hp_before and dummy.statuses.is_active("stun"), "the meteor lands: damage and stun"
	)

	t._check(player.skill_lock("chain_lightning") == "JOB", "Chain Lightning needs the advancement")
	player.stats.level = maxi(player.stats.level, 10)  # the job skills open at level 10
	player.stats.advanced = true
	hud.call("_refresh_progress")
	t._check(
		_button(hud, "skill_5").visible and _button_label(hud, "skill_5") == "CHAIN",
		"after the advancement the fifth button shows CHAIN"
	)
	var chain: Array = _line_up(player, [Vector2(150, 0), Vector2(300, 0), Vector2(430, 40)])
	before = chain.map(func(enemy): return enemy.hp)
	_ready_to_cast(player)
	t._check(player.use_skill("chain_lightning"), "a Sorcerer can cast Chain Lightning")
	var all_hit := true
	for i in chain.size():
		all_hit = all_hit and chain[i].hp < before[i]
	t._check(
		all_hit and not t.get_nodes_in_group("lightning").is_empty(),
		"the lightning jumps from slime to slime"
	)

	var slime: Node2D = chain[0]
	t._check(
		slime.call("_for_player", "book_meteor") and not slime.call("_for_player", "book_arrow_rain"),
		"monsters drop the mage's skill book, not the archer's"
	)
	t._check(
		not slime.call("_for_player", "training_sword") and slime.call("_for_player", "oak_staff"),
		"monsters drop gear the mage can wear"
	)
	hud.get_node("Shop").open("merchant", "mage")
	var usable: int = GameData.table("npcs")["merchant"]["shop"].filter(
		func(item_id): return ItemDb.usable_by(item_id, "mage")
	).size()
	t._check(
		hud.get_node("Shop").get("_buy_rows").get_child_count() == usable,
		"the shop sells the mage only what a mage can use (%d items)" % usable
	)
	player.add_item("book_ground_slam")
	player.use_from_bag(t._bag_index(player, "book_ground_slam"))
	t._check(not player.stats.knows_skill("ground_slam"), "a mage cannot learn a warrior's skill")
	player.add_item("training_sword")
	player.equip_from_bag(t._bag_index(player, "training_sword"))
	t._check(player.stats.equipped_id("weapon") == "oak_staff", "a mage keeps the staff, not a sword")


func _check_archer(player, hud) -> void:
	_become(player, hud, "archer")
	t._check(
		player.stats.equipped_id("weapon") == "short_bow" and _button_label(hud, "skill") == "MULTI",
		"the archer starts with a bow, and MULTI on the first button"
	)
	var dummy: Node2D = _line_up(player, [Vector2(180, 0)])[0]
	player.facing = "right"
	var hp_before: int = dummy.hp
	player.call("_attack")
	await t._frames(30)
	t._check(dummy.hp < hp_before, "the archer's arrow hits (%d -> %d)" % [hp_before, dummy.hp])
	_ready_to_cast(player)
	player.use_skill("multi_shot")
	t._check(
		t.get_nodes_in_group("hero_shots").size() == 5, "Multi Shot fires five arrows in a fan"
	)
	await t._frames(30)
	var line: Array = _line_up(player, [Vector2(150, 0), Vector2(260, 0)])
	var before: Array = line.map(func(enemy): return enemy.hp)
	_ready_to_cast(player)
	player.use_skill("piercing_arrow")
	await t._frames(30)
	t._check(
		line[0].hp < before[0] and line[1].hp < before[1],
		"Piercing Arrow flies through both slimes in a line"
	)
	_ready_to_cast(player)
	player.use_skill("eagle_eye")
	t._check(is_equal_approx(player.get("_crit_bonus"), 0.25), "Eagle Eye: +25% crit for a while")
	dummy = _line_up(player, [Vector2(160, 0)])[0]
	hp_before = dummy.hp
	player.add_item("book_arrow_rain")
	player.use_from_bag(t._bag_index(player, "book_arrow_rain"))
	_ready_to_cast(player)
	t._check(player.use_skill("arrow_rain"), "the archer learns Arrow Rain from its book and uses it")
	await t._frames(110)
	t._check(dummy.hp < hp_before, "Arrow Rain falls on the slime (%d -> %d)" % [hp_before, dummy.hp])
	player.stats.level = maxi(player.stats.level, 10)
	player.stats.advanced = true
	line = _line_up(player, [Vector2(150, 0), Vector2(300, 0)])
	before = line.map(func(enemy): return enemy.hp)
	_ready_to_cast(player)
	t._check(player.use_skill("spirit_arrow"), "a Ranger can shoot the Spirit Arrow")
	await t._frames(30)
	t._check(
		line[0].hp < before[0] and line[1].hp < before[1], "the Spirit Arrow tears through the line"
	)


func _check_warrior_job(player, hud) -> void:
	_become(player, hud, "warrior")
	player.stats.level = 9
	player.accept_quest("trial_of_the_king")
	t._check(
		not player.stats.quests.active.has("trial_of_the_king"), "the trial waits for level 10"
	)
	player.stats.level = 10
	var hp_before_job: int = player.stats.max_hp()
	var hp_per_level: int = int(player.stats.rule("hp_per_level"))
	player.accept_quest("trial_of_the_king")
	t._check(
		player.stats.quests.active.has("trial_of_the_king"),
		"at level 10 Master Hale gives the Trial of the King"
	)
	player.record_kill("slime_king", false)
	player.turn_in_quest("trial_of_the_king")
	t._check(
		player.stats.advanced and t._bag_index(player, "champion_cape") >= 0,
		"beating the Slime King makes the warrior a Champion, with the Champion Cape"
	)
	var from_levels: int = (player.stats.level - 10) * hp_per_level  # the reward's XP
	t._check(
		player.stats.max_hp() == hp_before_job + 40 + from_levels,
		"the advancement adds 40 HP (%d -> %d)" % [hp_before_job + from_levels, player.stats.max_hp()]
	)
	t._check(
		hud.get("_panel").get("_class_name") == "Champion" and _button(hud, "skill_5").visible,
		"the HUD says Champion and shows the fifth skill"
	)
	player.equip_from_bag(t._bag_index(player, "champion_cape"))
	t._check(player.stats.equipped_id("cape") == "champion_cape", "the Champion wears the new cape")
	var three: Array = _line_up(player, [Vector2(100, 0), Vector2(110, 60), Vector2(-120, 0)])
	var before: Array = three.map(func(enemy): return enemy.hp)
	player.facing = "right"
	_ready_to_cast(player)
	t._check(player.use_skill("great_cleave"), "a Champion can use Great Cleave")
	t._check(
		three[0].hp < before[0] and three[1].hp < before[1] and three[2].hp == before[2],
		"Great Cleave hits everything in front, not behind"
	)
	t._check(_button_label(hud, "skill") == "SPIN", "back as a warrior, the first button says SPIN")
	_release(player)


## The character screen: three slots, NEW HERO (Warrior or Archer), PLAY and
## DELETE, on test files.
func _check_select() -> void:
	var game_save: String = SaveFile.path
	SaveFile.slot_pattern = "user://test_slot_%d.cfg"
	for slot in range(1, SaveFile.SLOT_COUNT + 1):
		SaveFile.delete_slot(slot)
	SaveFile.save_data({"version": 8, "level": 7, "gold": 5})
	SaveFile.adopt_old_save(game_save)
	t._check(
		int(SaveFile.peek(1).get("level", 0)) == 7 and not FileAccess.file_exists(game_save),
		"the save from before the character screen becomes the first slot"
	)
	var screen: Control = SELECT_SCENE.instantiate()
	screen.starts_game = false
	t.root.add_child(screen)
	await t._frames(3)
	var cards: HBoxContainer = screen.get("_cards")
	t._check(cards.get_child_count() == 3, "the character screen shows three slots")
	screen.show_classes(2)
	t._check(
		ClassDb.playable() == ["warrior", "archer"] and cards.get_child_count() == 2,
		"a new hero can be a Warrior or an Archer (the mage waits for now)"
	)
	screen.get("_name_edit").text = "Tavi"
	screen.create("archer")
	var made: Dictionary = SaveFile.peek(2)
	t._check(
		made.get("class") == "archer" and made.get("name") == "Tavi",
		"NEW HERO saves the class and the name in its slot"
	)
	t._check(SaveFile.path == SaveFile.slot_path(2), "and plays that slot")
	var archer = PlayerStats.new()
	archer.from_dict(made)
	t._check(archer.equipped_id("weapon") == "short_bow", "the new archer starts with a bow")
	screen.show_slots()
	t._check(
		not screen.request_delete(2) and FileAccess.file_exists(SaveFile.slot_path(2)),
		"DELETE asks first"
	)
	t._check(
		screen.request_delete(2) and SaveFile.peek(2).is_empty(), "and deletes on the second press"
	)
	screen.queue_free()
	for slot in range(1, SaveFile.SLOT_COUNT + 1):
		SaveFile.delete_slot(slot)
	SaveFile.slot_pattern = SaveFile.SLOT_PATH
	SaveFile.path = game_save
	await t._frames(2)


## Turns the live hero into a new character of the class: its own gear, look,
## numbers and buttons (as from the character screen).
func _become(player, hud, class_id: String) -> void:
	var data: Dictionary = player.stats.to_dict()
	data["class"] = class_id
	data["advanced"] = false
	data.erase("equipment")
	player.stats.from_dict(data)
	player.call("_load_tuning")
	player.call("_apply_look")
	player.call("_limits_changed")
	player.hp = player.max_hp
	hud.call("_refresh_progress")


## Parks every monster far away, frozen, and puts one at each offset from the
## hero: no evasion and plenty of HP, so every hit shows.
func _line_up(player, offsets: Array) -> Array:
	for shot in t.get_nodes_in_group("hero_shots"):
		shot.queue_free()
	var enemies: Array = t.get_nodes_in_group("enemies").filter(func(enemy): return not enemy.is_dead)
	t._freeze(enemies, true)
	for enemy in enemies:
		enemy.global_position = PARK
	var placed: Array = []
	for i in mini(offsets.size(), enemies.size()):
		var enemy: Node2D = enemies[i]
		enemy.global_position = player.global_position + offsets[i]
		enemy.evasion = 0.0
		enemy.max_hp = 5000
		enemy.hp = 5000
		enemy.statuses.clear()
		placed.append(enemy)
	return placed


## Full mana or stamina and no cooldowns, so a skill can be cast at once.
func _ready_to_cast(player) -> void:
	player.stamina = player.max_stamina
	player.get("_skill_cooldowns").clear()


## Lets the monsters move again.
func _release(_player) -> void:
	t._freeze(t.get_nodes_in_group("enemies"), false)


func _button(hud, action: String) -> Control:
	for button in hud.get_tree().get_nodes_in_group("action_buttons"):
		if button.get("action") == action:
			return button
	return null


func _button_label(hud, action: String) -> String:
	var button: Control = _button(hud, action)
	return "" if button == null else button.get_node("Label").text
