extends SceneTree
## Writes the numbers player_stats.gd gives for a few heroes (every class, with
## stat points, upgraded and set gear, job advancement, a title, an old save from
## before the stat rework), the level rules (leveling.gd), the level each piece
## of gear needs and a sorted bag (item_db.gd) to a JSON file.
## The server's tests compare its Python port with it (server/tests/fixtures).
## Run: godot --headless -s res://tests/stats_fixture.gd -- <output.json>

const PlayerStats = preload("res://scripts/player/player_stats.gd")
const Leveling = preload("res://scripts/player/leveling.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const WEAPONS := {"warrior": "training_sword", "mage": "oak_staff", "archer": "short_bow"}


func _initialize() -> void:
	var heroes: Array = []
	for class_id in ["warrior", "mage", "archer"]:
		for case in range(5):
			var hero = PlayerStats.new()
			hero.from_dict(_case_dict(class_id, case))
			heroes.append(
				{
					"class": class_id,
					"case": case,
					"input": _case_dict(class_id, case),
					"max_hp": hero.max_hp(),
					"attack": hero.attack_damage(),
					"defense": hero.defense(),
					"crit": hero.crit_chance(),
					"evasion": hero.evasion(),
					"stamina": hero.max_stamina(),
					"skill": hero.skill_damage_bonus(),
					"free": hero.free_points(),
					"crit_damage": hero.total("crit_damage"),
					"accuracy": hero.total("accuracy"),
					"attack_speed": hero.total("attack_speed"),
					"xp_to_next": hero.xp_to_next(),
					"notice": hero.notice,
					"dict": hero.to_dict(),
				}
			)
	var curve: Array = []
	for level in range(1, 31):
		curve.append(Leveling.xp_for_level(level))
	var gaps: Array = []
	for pair in [[1, 1], [1, 3], [1, 40], [5, 5], [7, 5], [8, 5], [10, 4], [12, 1], [60, 1]]:
		gaps.append(
			[
				pair[0],
				pair[1],
				Leveling.gap_factor(pair[0], pair[1]),
				Leveling.kill_xp(37, pair[0], pair[1]),
			]
		)
	var out := {
		"heroes": heroes,
		"xp_for_level": curve,
		"gap": gaps,
		"bag": _bag(),
		"loot": _loot(),
		"upgrades": _upgrades(),
	}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "user://stats.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	quit()


func _case_dict(class_id: String, case: int) -> Dictionary:
	var data := {
		"version": PlayerStats.SAVE_VERSION,
		"class": class_id,
		"name": "Test",
		"level": 1,
		"xp": 3,
		"gold": 50,
	}
	if case == 0:
		return data
	data["level"] = 7
	data["stat_points"] = {"strength": 3, "dexterity": 4, "vitality": 2, "energy": 3}
	if case == 4:
		# A save from before the stat rework: the points come back.
		data["version"] = 10
		data["stat_points"] = {"strength": 3, "agility": 4}
		return data
	data["equipment"] = {
		"weapon":
		{
			"id": WEAPONS[class_id],
			"rarity": "rare",
			"plus": 5,
			"options": {"attack": 2, "crit_chance": 0.02, "crit_damage": 0.1}
		},
		"head":
		{
			"id": "verdant_headband",
			"rarity": "uncommon",
			"plus": 2,
			"options": {"max_hp": 7, "attack_speed": 0.05}
		},
		"cape": {"id": "verdant_cape"},
		"gloves": {"id": "verdant_gloves"},
		"boots": {"id": "verdant_boots"},
	}
	data["bag"] = [{"id": "red_potion", "count": 4}, {"id": "moon_stone", "count": 2}]
	if case >= 2:
		data["advanced"] = true
	if case >= 3:
		data["counters"] = {"kills:green_slime": 40, "kills": 40}
		data["achievements"] = ["first_hunt", "slime_hunter"]
		data["title"] = "slime_hunter"
	return data


## A mixed bag and how it sorts for a warrior and an archer, and the level
## every piece of gear needs.
func _bag() -> Dictionary:
	var mixed: Array = [
		{"id": "ember_stone", "count": 2},
		ItemDb.gear("short_bow"),
		{"id": "red_potion", "count": 3},
		ItemDb.gear("leather_boots"),
		ItemDb.gear("training_sword"),
		ItemDb.gear("crimson_sword"),
		ItemDb.gear("training_sword", "rare"),
		ItemDb.gear("swift_boots", "epic", 2),
		{"id": "book_ground_slam", "count": 1},
	]
	var levels := {}
	for item_id in ItemDb.items:
		if ItemDb.is_gear(item_id):
			levels[item_id] = ItemDb.required_level(item_id)
	return {
		"input": mixed,
		"warrior": ItemDb.sorted_bag(mixed, "warrior"),
		"archer": ItemDb.sorted_bag(mixed, "archer"),
		"levels": levels,
	}


## Loot (item_db.gd): the gear pool of every monster level, and the range of
## every random option on pieces of different levels and rarities.
func _loot() -> Dictionary:
	var pools := {}
	for level in range(1, 21):
		pools[str(level)] = ItemDb.drop_pool(level)
	var ranges: Array = []
	for item_id in ["training_sword", "crimson_sword", "duelist_cape", "elderwood_blade"]:
		for rarity in ItemDb.rarities:
			for stat in ItemDb.random_options:
				var span: Vector2 = ItemDb.option_range(stat, item_id, rarity)
				ranges.append([item_id, rarity, stat, span.x, span.y])
	return {"pools": pools, "ranges": ranges}


## M5 upgrades: the next + of pieces of different levels, pluses and misses,
## and what the pluses add.
func _upgrades() -> Array:
	var rows: Array = []
	for item_id in ["training_sword", "crimson_plate", "elderwood_blade", "elderwood_band"]:
		for plus in [0, 3, 9, 14, 15]:
			for misses in [0, 2]:
				var stack: Dictionary = ItemDb.gear(item_id, "common", plus)
				if misses > 0:
					stack["misses"] = misses
				var row := {"stack": stack, "step": ItemDb.upgrade_step(stack)}
				for stat in ["attack", "max_hp", "defense"]:
					row[stat] = ItemDb.stat_of(stack, stat)
				rows.append(row)
	return rows
