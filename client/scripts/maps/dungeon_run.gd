extends Node
## W6: a run through a dungeon map (maps.json "dungeon"). Waves of monsters
## come one after another; when a wave is beaten the next one starts, then
## the boss. Beating the boss pays the reward and opens a portal out. The
## monsters of a run do not come back. Entries per day are counted by the
## warrior (player_base.gd enter_dungeon) before the map loads.

const GameData := preload("res://scripts/data/game_data.gd")
const SLIME_SCENE := preload("res://scenes/enemies/slime.tscn")
const PORTAL_SCENE := preload("res://scenes/maps/portal.tscn")

## Seconds between a beaten wave and the next one (shorter in the tests).
var wave_delay: float = 3.0
## Waves beaten so far; the boss comes after the last one.
var wave: int = 0
var cleared: bool = false
var _rules: Dictionary = {}
var _alive: Array = []
var _wait_left: float = 0.0
var _boss_out: bool = false


## rules: the map's "dungeon" entry.
func setup(rules: Dictionary) -> void:
	_rules = rules
	_wait_left = wave_delay


func _process(delta: float) -> void:
	if cleared or _rules.is_empty():
		return
	_alive = _alive.filter(_still_fighting)
	if not _alive.is_empty():
		return
	if _boss_out:
		_finish()
		return
	_wait_left -= delta
	if _wait_left > 0.0:
		return
	_wait_left = wave_delay
	var waves: Array = _rules["waves"]
	if wave < waves.size():
		_spawn_wave(waves[wave])
		wave += 1
		_banner("Wave %d / %d" % [wave, waves.size()], "")
	else:
		_boss_out = true
		_spawn(_rules["boss"])
		var boss_name: String = GameData.table("monsters")[_rules["boss"]]["name"]
		_banner("%s awakens!" % boss_name, "")


static func _still_fighting(monster) -> bool:
	return is_instance_valid(monster) and not monster.is_dead


func _spawn_wave(groups: Array) -> void:
	for group in groups:
		for i in int(group["count"]):
			_spawn(group["monster"])


func _spawn(monster_id: String) -> void:
	var area: Array = _rules["area"]
	var monster: Node2D = SLIME_SCENE.instantiate()
	monster.set("monster_id", monster_id)
	monster.set("respawns", false)
	monster.position = Vector2(randf_range(area[0], area[2]), randf_range(area[1], area[3]))
	get_parent().add_child(monster)
	_alive.append(monster)


func _finish() -> void:
	cleared = true
	var map_name: String = get_parent().call("display_name")
	_banner("%s cleared!" % map_name, "A way out has opened")
	get_tree().call_group("player", "dungeon_reward", _rules.get("reward", {}))
	var exit: Dictionary = _rules["exit"]
	var portal: Node2D = PORTAL_SCENE.instantiate()
	portal.set("to_map", exit["to"])
	portal.set("to_spawn", exit.get("spawn", "default"))
	portal.position = Vector2(exit["pos"][0], exit["pos"][1])
	get_parent().call_deferred("add_child", portal)


func _banner(title: String, subtitle: String) -> void:
	get_tree().call_group("hud", "show_banner", title, subtitle)
