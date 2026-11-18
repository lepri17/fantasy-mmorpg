extends RefCounted
## The combat core part of the smoke test: the shared hit rules (defense floor,
## crit damage, accuracy, averages), attack speed, one hit per target per cast,
## gentle knockback, reach to a body's edge and the DPS meter.
## smoke_test.gd runs it last; t is the test (a SceneTree) with _check and _frames.

const CombatRules = preload("res://scripts/combat/combat_rules.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const Settings = preload("res://scripts/settings.gd")
const SLIME_SCENE := preload("res://scenes/enemies/slime.tscn")
const HeroShot = preload("res://scripts/combat/hero_shot.gd")

var t = null


func run(test, main, player, hud) -> void:
	t = test
	_check_rules()
	_check_attack_speed(player)
	var slimes: Array = await _spawn(main, player, ["green_slime", "green_slime", "slime_king"])
	_check_one_hit_per_cast(player, slimes[0])
	_check_knockback(slimes)
	_check_reach(player, slimes)
	await _check_dps_meter(player, hud, slimes[1])
	for slime in slimes:
		slime.queue_free()
	await t._frames(2)


func _check_rules() -> void:
	t._check(
		(
			CombatRules.mitigate(10, 3) == 7
			and CombatRules.mitigate(10, 50) == 2
			and CombatRules.mitigate(1, 9) == 1
		),
		"defense takes off its value, but a hit keeps at least 20% (and 1)"
	)
	var lowest: int = 9999
	for _i in 40:
		lowest = mini(lowest, CombatRules.resolve_hit(100, 1.0, 0, 0.0, 0.5)["damage"])
	t._check(lowest >= 160, "crit damage +50%%: crits do 2x (lowest crit %d)" % lowest)
	t._check(
		(
			is_equal_approx(CombatRules.hit_evasion(0.3, 0.1), 0.2)
			and is_equal_approx(CombatRules.hit_evasion(0.95, 0.0), CombatRules.max_evasion)
			and CombatRules.hit_evasion(0.1, 0.5) == 0.0
		),
		"accuracy takes off evasion, and evasion has a ceiling"
	)
	t._check(
		(
			is_equal_approx(CombatRules.expected_damage(10, 0.0, 0, 0.0), 10.0)
			and CombatRules.expected_damage(10, 0.5, 0, 0.0) > 12.0
			and is_equal_approx(CombatRules.expected_damage(10, 0.0, 0, 0.5), 5.0)
		),
		"the average hit counts crits and misses"
	)


func _check_attack_speed(player) -> void:
	var base: float = float(player.stats.rule("attack_cooldown"))
	t._check(is_equal_approx(player.attack_interval(), base), "no attack speed: the class's own pace")
	var gloves: Dictionary = player.stats.equipment.get("gloves", {})
	player.stats.equipment["gloves"] = ItemDb.gear("leather_gloves", "rare", 0, {"attack_speed": 0.25})
	t._check(
		is_equal_approx(player.attack_interval(), base / 1.25),
		"+25%% attack speed: %.3f s between swings" % player.attack_interval()
	)
	player.stats.equipment["gloves"] = ItemDb.gear("leather_gloves", "rare", 0, {"attack_speed": 9.0})
	t._check(
		is_equal_approx(player.attack_interval(), base / 2.0), "attack speed stops at +100%"
	)
	if gloves.is_empty():
		player.stats.equipment.erase("gloves")
	else:
		player.stats.equipment["gloves"] = gloves


func _spawn(main, player, kinds: Array) -> Array:
	var slimes: Array = []
	for i in kinds.size():
		var slime: Node2D = SLIME_SCENE.instantiate()
		slime.set("monster_id", kinds[i])
		slime.position = player.position + Vector2(2000 + i * 300, 0)
		main.map.add_child(slime)
		slimes.append(slime)
	await t._frames(2)
	t._freeze(slimes, true)
	for slime in slimes:
		slime.evasion = 0.0
		slime.max_hp = 100000
		slime.hp = slime.max_hp
	return slimes


func _check_one_hit_per_cast(player, slime) -> void:
	var cast: int = player.begin_cast()
	var first: Dictionary = player.call("_strike", slime, 10, 1.0, cast)
	var again: Dictionary = player.call("_strike", slime, 10, 1.0, cast)
	t._check(
		not first["miss"] and again.get("repeat", false) and slime.hp == slime.max_hp - first["damage"],
		"a cast hits each target once (the second hit of the same cast is ignored)"
	)
	var hp_before: int = slime.hp
	var multi: int = player.begin_cast()
	for _arrow in 5:
		var shot = HeroShot.new()
		shot.damage = 10
		shot.cast = multi
		player.shot_hit(shot, slime)
		shot.free()
	t._check(
		slime.hp < hp_before and hp_before - slime.hp <= 30,
		"Multi Shot: five arrows of one cast hit a monster once (%d damage)" % (hp_before - slime.hp)
	)
	var next: int = player.begin_cast()
	t._check(
		not player.call("_strike", slime, 10, 1.0, next).get("repeat", false),
		"a new cast may hit it again"
	)


func _check_knockback(slimes: Array) -> void:
	var slime = slimes[0]
	var from: Vector2 = slime.global_position + Vector2(-50, 0)
	var light: float = slime.call("_push", from, 1.0).length()
	var hard: float = slime.call("_push", from, 3.0).length()
	var limit: float = sqrt(2.0 * 1400.0 * float(CombatRules.settings["knockback_max_distance"]))
	t._check(
		light > 0.0 and hard <= limit + 0.01 and hard >= light,
		"knockback is gentle: a heavy hit is capped (%.0f, %.0f px/s)" % [light, hard]
	)
	slime.call("make_elite")
	t._check(
		is_equal_approx(slime.call("_push", from, 1.0).length(), light * 0.5),
		"an elite is pushed half as far"
	)
	var king = slimes[2]
	t._check(
		king.call("_push", king.global_position + Vector2(-50, 0), 3.0).length() == 0.0,
		"the Slime King does not move when hit"
	)


func _check_reach(player, slimes: Array) -> void:
	var small = slimes[1]
	var king = slimes[2]
	var reach: float = float(player.attack_range)
	small.global_position = player.global_position + Vector2(reach + small.body_radius() - 4, 0)
	king.global_position = player.global_position + Vector2(reach + king.body_radius() - 4, 0)
	t._check(
		player.call("_can_hit", small, Vector2.RIGHT) and player.call("_can_hit", king, Vector2.RIGHT),
		"a swing reaches the edge of a body: the big king is hit from farther away"
	)
	small.global_position = player.global_position + Vector2(reach + small.body_radius() + 6, 0)
	t._check(not player.call("_can_hit", small, Vector2.RIGHT), "but not past its edge")
	small.global_position = player.global_position + Vector2(-40, 0)
	t._check(not player.call("_can_hit", small, Vector2.RIGHT), "nor behind the swing")
	for slime in slimes:
		slime.global_position = player.global_position + Vector2(3000, 0)


func _check_dps_meter(player, hud, slime) -> void:
	player.combat_log.reset()
	for i in 4:
		player.call("_strike", slime, 20, 1.0, player.begin_cast())
	t._check(
		player.combat_log.hits == 4 and player.combat_log.dps(5.0) > 0.0,
		"the DPS meter counts the hits (%.1f a second)" % player.combat_log.dps(5.0)
	)
	Settings.set_value("show_dps", true)
	hud.call("_update_dps")
	var meter: Label = hud.get_node("DpsMeter")
	t._check(meter.visible and meter.text.begins_with("DPS"), "Show DPS puts the meter on the screen")
	Settings.set_value("show_dps", false)
	hud.call("_update_dps")
	t._check(not meter.visible, "and takes it off again")
	await t._frames(1)
