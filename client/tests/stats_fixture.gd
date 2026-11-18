extends SceneTree
## Writes the numbers player_stats.gd gives for a few heroes (every class, with
## stat points, upgraded and set gear, job advancement, a title) to a JSON file.
## The server's tests compare its Python port with it (server/tests/fixtures).
## Run: godot --headless -s res://tests/stats_fixture.gd -- <output.json>

const PlayerStats = preload("res://scripts/player/player_stats.gd")
const WEAPONS := {"warrior": "training_sword", "mage": "oak_staff", "archer": "short_bow"}


func _initialize() -> void:
	var out: Array = []
	for class_id in ["warrior", "mage", "archer"]:
		for case in range(4):
			var hero = PlayerStats.new()
			hero.from_dict(_case_dict(class_id, case))
			out.append(
				{
					"class": class_id,
					"case": case,
					"max_hp": hero.max_hp(),
					"attack": hero.attack_damage(),
					"defense": hero.defense(),
					"crit": hero.crit_chance(),
					"evasion": hero.evasion(),
					"stamina": hero.max_stamina(),
					"skill": hero.skill_damage_bonus(),
					"free": hero.free_points(),
					"dict": hero.to_dict(),
				}
			)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "user://stats.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	quit()


func _case_dict(class_id: String, case: int) -> Dictionary:
	var data := {"version": 10, "class": class_id, "name": "Test", "level": 1, "xp": 3, "gold": 50}
	if case == 0:
		return data
	data["level"] = 7
	data["stat_points"] = {"strength": 3, "agility": 4, "vitality": 2, "energy": 3}
	data["equipment"] = {
		"weapon":
		{
			"id": WEAPONS[class_id],
			"rarity": "rare",
			"plus": 5,
			"options": {"attack": 2, "crit_chance": 0.02}
		},
		"head": {"id": "verdant_headband", "rarity": "uncommon", "plus": 2, "options": {"max_hp": 7}},
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
