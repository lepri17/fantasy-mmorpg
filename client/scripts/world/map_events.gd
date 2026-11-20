extends Node
## O19: random events in the hunting maps (Mor: "the maps feel the same all
## the time"). After a few minutes of hunting (data/events.json "first", then
## "wait": [shortest, longest] seconds, counted only in a hunting map),
## something happens in the hero's map:
## - treasure: a chest appears near him for a while (and may hold gear);
## - swarm: a pack of the map's monsters comes at him; beat them all in time
##   for bonus EXP and gold;
## - lucky: a golden Lucky monster shows up, sure to drop good gear, and soon
##   runs off.
## game.gd makes this node and calls map_arrived() on each new map; leaving the
## map ends the event.

const GameData := preload("res://scripts/data/game_data.gd")
const Chest := preload("res://scripts/world/chest.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const SLIME_SCENE_PATH := "res://scenes/enemies/slime.tscn"
## How far from the hero an event's things appear.
const NEAR := 230.0
## Nothing an event brings comes this close to the map's edge, where the roads
## leave (a chest there sent the hero on to the next map).
const EDGE_KEEP := 230.0
## A chest that was opened stays this long, then fades out.
const OPENED_SECONDS := 8.0

## Off in the smoke test and the screenshots: there events come only when
## start() is called.
static var enabled: bool = true

## Seconds of hunting before the next event.
var wait: float = 0.0
## The event going on now ("treasure", "swarm", "lucky"), or "".
var kind: String = ""
## Seconds it has left.
var left: float = 0.0
## Its chest or its monsters.
var things: Array = []
var _game = null
var _player = null
var _gone_in: float = -1.0


func setup(game, player) -> void:
	_game = game
	_player = player
	wait = _roll(_data()["first"])


func _process(delta: float) -> void:
	if _game == null or _game.map == null:
		return
	if kind != "":
		_tick(delta)
		return
	if _gone_in >= 0.0:
		_gone_in -= delta
		if _gone_in < 0.0:
			_clear_things()
	if not enabled or not huntable():
		return
	wait -= delta
	if wait <= 0.0:
		start(_pick())


## A map where events happen: one with monsters to hunt, not a town or dungeon.
func huntable() -> bool:
	var data: Dictionary = GameData.table("maps")["maps"].get(_game.map.map_id, {})
	return not data.get("safe", false) and not data.has("dungeon") and not prey().is_empty()


## The map's own monsters out now (not bosses, nor those an event brought).
func prey() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(
		func(enemy) -> bool:
			return (
				not enemy.get("is_dead")
				and enemy.get("boss").is_empty()
				and not enemy.has_meta("event")
				and _game.map.is_ancestor_of(enemy)
			)
	)


## A new map: an event in the old one is over.
func map_arrived(_map_id: String) -> void:
	kind = ""
	things.clear()
	_gone_in = -1.0


## Starts an event in the hero's map now. Returns false when none can start.
func start(event: String) -> bool:
	if kind != "" or not huntable() or not _data()["events"].has(event):
		return false
	var info: Dictionary = _data()["events"][event]
	kind = event
	left = float(info["seconds"])
	things.clear()
	match event:
		"treasure":
			var chest = Chest.new()
			chest.level = map_level()
			chest.gear_chance = float(info.get("gear_chance", 0.5))
			chest.refill_seconds = 99999.0
			chest.position = _spot(NEAR + 80.0)
			_add(chest)
			_tell("A treasure chest appeared!", "Find it within %d seconds." % roundi(left))
		"swarm":
			var monster_id: String = prey().pick_random().monster_id
			for i in int(info["count"]):
				var angle: float = TAU * i / float(info["count"]) + randf_range(-0.3, 0.3)
				_add(_monster(monster_id, _spot(NEAR, angle)))
			var monster_name: String = GameData.table("monsters")[monster_id]["name"]
			_tell("A swarm of %ss!" % monster_name, "Beat them all within %d seconds." % roundi(left))
		"lucky":
			var monster_id: String = prey().pick_random().monster_id
			var lucky = _monster(monster_id, _spot(NEAR + 120.0))
			_add(lucky)
			lucky.make_lucky(String(info["min_rarity"]), float(info["gold"]))
			_tell("A %s appeared!" % lucky.display_name, "Catch it before it runs off!")
	return true


## The highest level among the map's monsters: what the event's chest gives.
func map_level() -> int:
	var best: int = 1
	for enemy in prey():
		best = maxi(best, int(enemy.get("level")))
	return best


func _tick(delta: float) -> void:
	left -= delta
	var alive: Array = things.filter(func(thing) -> bool: return is_instance_valid(thing))
	match kind:
		"treasure":
			if alive.is_empty() or alive[0].is_open:
				_end("", "")
				_gone_in = OPENED_SECONDS
				return
		"swarm":
			if alive.all(func(monster) -> bool: return monster.is_dead):
				_reward_swarm()
				return
		"lucky":
			if alive.is_empty() or alive[0].is_dead:
				_end("You caught the Lucky one!", "")
				return
	if left <= 0.0:
		var lines := {
			"treasure": "The chest is gone.",
			"swarm": "The swarm got away.",
			"lucky": "The Lucky one ran off."
		}
		_end(lines[kind], "")
		_clear_things()


func _reward_swarm() -> void:
	var info: Dictionary = _data()["events"]["swarm"]
	var xp: int = 0
	for monster in things:
		if is_instance_valid(monster):
			xp += int(monster.get("xp_reward"))
	xp = roundi(xp * float(info["xp_bonus"]))
	var gold: int = int(info["gold_per_level"]) * map_level()
	_end("Swarm cleared!", "+%d EXP, +%d gold" % [xp, gold])
	if _player != null:
		_player.gain_xp(xp)
		_player.add_gold(gold)


func _end(title: String, subtitle: String) -> void:
	kind = ""
	wait = _roll(_data()["wait"])
	if title != "":
		_tell(title, subtitle)


func _clear_things() -> void:
	for thing in things:
		if is_instance_valid(thing) and not thing.get("is_dead"):
			Burst.spawn(_game.map, thing.position, Color(0.9, 0.9, 1.0), 24, 160.0)
			thing.queue_free()
	things.clear()


func _monster(monster_id: String, spot: Vector2) -> Node2D:
	var monster: Node2D = load(SLIME_SCENE_PATH).instantiate()
	monster.set("monster_id", monster_id)
	monster.set("respawns", false)
	monster.set_meta("event", true)
	monster.position = spot
	return monster


func _add(thing: Node2D) -> void:
	_game.map.add_child(thing)
	things.append(thing)
	Burst.spawn(_game.map, thing.position, Color(1.0, 0.9, 0.5), 30, 200.0)


## A place on open ground about `distance` from the hero (the map's navigation
## mesh, so not in a tree, the water or a cliff), or where one of the map's
## monsters stands when there is none.
func _spot(distance: float, angle: float = -1.0) -> Vector2:
	var hero: Vector2 = _player.global_position
	var nav: RID = _game.map.get_world_2d().navigation_map
	var bounds: Rect2 = _game.map.bounds().grow(-EDGE_KEEP)
	for attempt in 10:
		var turn: float = (angle if angle >= 0.0 else randf() * TAU) + attempt * 0.7
		var want: Vector2 = hero + Vector2.RIGHT.rotated(turn) * distance
		want = want.clamp(bounds.position, bounds.end)
		var ground: Vector2 = NavigationServer2D.map_get_closest_point(nav, want)
		if ground != Vector2.ZERO and ground.distance_to(want) < 40.0:
			return ground
	var monster = prey().pick_random()
	return monster.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))


func _pick() -> String:
	var events: Dictionary = _data()["events"]
	var total: float = 0.0
	for event in events:
		total += float(events[event]["weight"])
	var roll: float = randf() * total
	for event in events:
		roll -= float(events[event]["weight"])
		if roll < 0.0:
			return event
	return events.keys()[0]


func _tell(title: String, subtitle: String) -> void:
	get_tree().call_group("hud", "show_banner", title, subtitle)


func _roll(span: Array) -> float:
	return randf_range(float(span[0]), float(span[1]))


func _data() -> Dictionary:
	return GameData.table("events")
