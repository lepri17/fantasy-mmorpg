extends Node
## Roaming bosses (Mor's wish, 2026-11-19): a few bosses, each only in the
## maps that are its own land (slimes in the meadow and the woods, the storm
## bird on the ridge, the ice dragon in the hollow), and not always there. A
## monster whose "boss" in monsters.json has a "roam" part waits a random time
## ("first", later "wait": [shortest, longest] seconds), then appears in one of
## its "maps", at one of that map's
## "boss_spots" (maps.json). It stays "stay" seconds, then leaves, unless it is
## in a fight. Beaten, it waits again. The clock runs wherever the hero is;
## the boss itself is made only while the hero is in its map. game.gd makes
## this node and calls map_arrived() each time a map comes in.

const GameData := preload("res://scripts/data/game_data.gd")
const Burst := preload("res://scripts/combat/burst.gd")
const SLIME_SCENE_PATH := "res://scenes/enemies/slime.tscn"
## Seconds a boss in a fight waits before it thinks of leaving again.
const FIGHT_DELAY := 15.0

## Off in the smoke test and the screenshots: there a boss comes only when
## appear() is called.
static var enabled: bool = true

## boss id -> {"wait": seconds before it appears, "map": the map it is in ("" while
## away), "spot": where it stands there, "left": seconds before it leaves}
var bosses: Dictionary = {}
var _game = null
var _here: Dictionary = {}  # boss id -> its node in the map shown now


func setup(game) -> void:
	_game = game
	var monsters: Dictionary = GameData.table("monsters")
	for id in monsters:
		var roam: Dictionary = monsters[id].get("boss", {}).get("roam", {})
		if not roam.is_empty():
			bosses[id] = {
				"wait": _roll(roam.get("first", roam["wait"])),
				"map": "",
				"spot": Vector2.ZERO,
				"left": 0.0
			}


func _process(delta: float) -> void:
	for id in bosses:
		var state: Dictionary = bosses[id]
		var node = _here.get(id)
		if node != null and (not is_instance_valid(node) or node.get("is_dead")):
			_here.erase(id)
			if is_instance_valid(node):  # beaten: it rests before it comes again
				_rest(id)
				continue
			node = null
		if state["map"] == "":
			if enabled:
				state["wait"] -= delta
				if state["wait"] <= 0.0:
					appear(id)
			continue
		state["left"] -= delta
		if state["left"] > 0.0:
			continue
		if node != null and node.hp < node.max_hp:
			state["left"] = FIGHT_DELAY  # it does not run from a fight
		else:
			leave(id)


## Brings a boss out now in map_id (else in one of its maps, at random), at a
## random one of that map's boss spots. The clock calls this; so can a test.
func appear(id: String, map_id: String = "") -> void:
	var roam: Dictionary = _roam(id)
	var maps: Array = roam["maps"]
	if map_id == "":
		map_id = maps.pick_random()
	if not map_id in maps or spots(map_id).is_empty():
		push_error("%s does not come to %s" % [id, map_id])
		return
	var spot: Vector2 = spots(map_id).pick_random()
	var state: Dictionary = bosses[id]
	state["map"] = map_id
	state["spot"] = spot
	state["left"] = float(roam["stay"])
	var map_name: String = _maps()[map_id]["name"]
	if _game.map.map_id == map_id:
		_make(id)
		_tell("%s appears!" % _name(id), "Right here, in %s" % map_name)
	elif _game.map.map_id in maps:
		_tell("%s appears!" % _name(id), "Somewhere in %s" % map_name)


## The boss goes away: with a puff, if it is in the map shown now.
func leave(id: String) -> void:
	var node = node_of(id)
	_here.erase(id)
	if node != null and not node.get("is_dead"):
		Burst.spawn(node.get_parent(), node.position, Color(0.86, 0.88, 0.96), 40, 240.0)
		node.queue_free()
		_tell("%s has gone" % _name(id), "It will be back another time")
	_rest(id)


## A map came in: a boss that is out in it stands at its spot. Returns the
## boss's name ("" if none), for the map's banner.
func map_arrived(map_id: String) -> String:
	_here.clear()
	var names: Array = []
	for id in bosses:
		if bosses[id]["map"] == map_id:
			_make(id)
			names.append(_name(id))
	return ", ".join(names)


## The maps that are a boss's own land: the only ones it comes to.
func maps_of(id: String) -> Array:
	return _roam(id)["maps"]


## True while the boss is out, in some map.
func is_out(id: String) -> bool:
	return bosses.has(id) and bosses[id]["map"] != ""


## The boss in the map shown now, or null.
func node_of(id: String):
	var node = _here.get(id)
	return node if node != null and is_instance_valid(node) else null


## Where a boss can appear in a map (maps.json "boss_spots").
static func spots(map_id: String) -> Array:
	var points: Array = []
	for spot in _maps()[map_id].get("boss_spots", []):
		points.append(Vector2(spot[0], spot[1]))
	return points


func _make(id: String) -> void:
	var boss: Node2D = load(SLIME_SCENE_PATH).instantiate()
	boss.set("monster_id", id)
	boss.set("respawns", false)
	boss.position = bosses[id]["spot"]
	_game.map.add_child(boss)
	_here[id] = boss
	Burst.spawn(_game.map, boss.position, Color(1.0, 0.86, 0.4), 50, 260.0)


func _rest(id: String) -> void:
	bosses[id]["map"] = ""
	bosses[id]["wait"] = _roll(_roam(id)["wait"])


func _tell(title: String, subtitle: String) -> void:
	get_tree().call_group("hud", "show_banner", title, subtitle)


func _roam(id: String) -> Dictionary:
	return GameData.table("monsters")[id]["boss"]["roam"]


func _name(id: String) -> String:
	return GameData.table("monsters")[id]["name"]


static func _maps() -> Dictionary:
	return GameData.table("maps")["maps"]


static func _roll(span: Array) -> float:
	return randf_range(float(span[0]), float(span[1]))
