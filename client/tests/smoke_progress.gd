extends RefCounted
## The character progression part of the smoke test: the XP curve, less XP
## from monsters far below the hero, every stat point doing something for every
## class, old saves (AGI became DEX) and the STATS window.
## smoke_test.gd runs it after the combat part; t is the test (a SceneTree).

const Leveling = preload("res://scripts/player/leveling.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const ClassDb = preload("res://scripts/player/class_db.gd")

var t = null


func run(test, _main, player, hud) -> void:
	t = test
	_check_xp_curve()
	_check_level_gap()
	_check_every_point()
	_check_old_saves()
	_check_kill_xp(player)
	_check_window(player, hud)


func _check_xp_curve() -> void:
	var growing: bool = true
	for level in range(1, 40):
		growing = growing and Leveling.xp_for_level(level + 1) > Leveling.xp_for_level(level)
	t._check(
		Leveling.xp_for_level(1) == int(PlayerStats.rules["xp_curve"]["base"]) and growing,
		(
			"every level needs more XP (%d, %d, %d ... %d)"
			% [
				Leveling.xp_for_level(1),
				Leveling.xp_for_level(2),
				Leveling.xp_for_level(3),
				Leveling.xp_for_level(10)
			]
		)
	)
	var hero = PlayerStats.new()
	hero.level = 4
	var two_levels: int = Leveling.xp_for_level(4) + Leveling.xp_for_level(5)
	t._check(
		hero.xp_to_next() == Leveling.xp_for_level(4) and hero.add_xp(two_levels + 7) == 2,
		"XP for two levels raises two levels"
	)
	t._check(hero.level == 6 and hero.xp == 7, "the XP left over stays (%d)" % hero.xp)


func _check_level_gap() -> void:
	var gap: Dictionary = PlayerStats.rules["xp_level_gap"]
	var free: int = int(gap["free_levels"])
	t._check(
		Leveling.gap_factor(5, 5) == 1.0 and Leveling.gap_factor(5 + free, 5) == 1.0,
		"a monster up to %d levels below the hero gives all its XP" % free
	)
	t._check(
		(
			is_equal_approx(Leveling.gap_factor(6 + free, 5), 1.0 - float(gap["loss_per_level"]))
			and is_equal_approx(Leveling.gap_factor(60, 1), float(gap["lowest"]))
		),
		"then less for every level more, but never under %d%%" % roundi(gap["lowest"] * 100.0)
	)
	t._check(
		(
			is_equal_approx(Leveling.gap_factor(1, 2), 1.0 + float(gap["gain_per_level"]))
			and is_equal_approx(Leveling.gap_factor(1, 60), float(gap["highest"]))
		),
		"a monster above the hero gives a little more"
	)
	t._check(Leveling.kill_xp(1, 60, 1) == 1, "a kill always gives at least 1 XP")


## One point in any stat changes a number the player sees, for every class.
func _check_every_point() -> void:
	var nothing: Array = []
	for class_id in ClassDb.ids():
		for stat_id in PlayerStats.stat_rules:
			var hero = PlayerStats.new()
			hero.from_dict({"version": PlayerStats.SAVE_VERSION, "class": class_id, "level": 2})
			var before: Array = _numbers(hero)
			hero.add_stat_point(stat_id)
			if _numbers(hero) == before:
				nothing.append("%s %s" % [class_id, stat_id])
	t._check(
		nothing.is_empty(), "one point in any stat changes a number (%s)" % ", ".join(nothing)
	)


func _numbers(hero) -> Array:
	return [
		hero.attack_damage(),
		hero.max_hp(),
		hero.defense(),
		hero.crit_chance(),
		hero.total("accuracy"),
		hero.total("attack_speed"),
		hero.max_stamina(),
		hero.skill_damage_bonus(),
	]


func _check_old_saves() -> void:
	var old = PlayerStats.new()
	old.from_dict(
		{
			"version": 10,
			"class": "archer",
			"level": 3,
			"stat_points": {"agility": 4, "strength": 3},
		}
	)
	t._check(
		(
			old.stat_points.is_empty()
			and old.free_points() == 10
			and old.notice == PlayerStats.STATS_REWORK_NOTICE
		),
		"a save from before the stat rework gets all its points back, with a message"
	)
	var no_points = PlayerStats.new()
	no_points.from_dict({"version": 10, "class": "warrior", "level": 3})
	t._check(no_points.notice == "", "an old save with no points gets no message")
	var renamed = PlayerStats.new()
	renamed.from_dict(
		{
			"version": PlayerStats.SAVE_VERSION,
			"class": "archer",
			"level": 3,
			"stat_points": {"dexterity": 2, "agility": 1, "luck": 3, "vitality": -2},
		}
	)
	t._check(
		renamed.stat_points == {"dexterity": 3} and renamed.notice == "",
		"AGI points count as DEX, and unknown stats are left out"
	)
	var newer = PlayerStats.new()
	newer.from_dict(
		{
			"version": PlayerStats.SAVE_VERSION + 5,
			"level": 4,
			"xp": 12,
			"pets": ["owl"],
			"stat_points": {"strength": 2},
		}
	)
	t._check(
		newer.level == 4 and newer.xp == 12 and newer.points_in("strength") == 2,
		"a save with fields this version does not know still loads"
	)


func _check_kill_xp(player) -> void:
	var said: Array = []
	var listen := func(text: String, _color: Color) -> void: said.append(text)
	player.message.connect(listen)
	var level: int = player.stats.level
	var xp: int = player.stats.xp
	player.stats.level = 6
	player.stats.xp = 0
	player.gain_kill_xp(20, 1)
	var expected: int = Leveling.kill_xp(20, 6, 1)
	var percent: int = roundi(Leveling.gap_factor(6, 1) * 100.0)
	player.message.disconnect(listen)
	t._check(
		(
			expected < 20
			and player.stats.xp == expected
			and said.has("+%d EXP (%d%%)" % [expected, percent])
		),
		"a slime far below the hero gives less XP, and the chat says so (%s)" % ", ".join(said)
	)
	player.stats.level = level
	player.stats.xp = xp


func _check_window(player, hud) -> void:
	var character = hud.get_node("Character")
	var buttons: Dictionary = character.get("_plus_buttons")
	t._check(
		buttons.has("dexterity") and not buttons.has("agility"),
		"the STATS window has STR, DEX, VIT and ENE"
	)
	var texts: Array = []
	for level in [3, 12]:
		var hero = PlayerStats.new()
		hero.level = level
		hero.add_stat_point("strength")
		character.refresh(hero)
		texts.append(character.get("_reset_button").text)
	character.refresh(player.stats)
	t._check(
		"FREE" in texts[0] and "240 G" in texts[1],
		"the stat reset is free below level 10, then costs gold (%s)" % " / ".join(texts)
	)
