extends RefCounted
## Auto hunt (U5) and walking to a quest's target (U6). When the player is not
## moving the hero, the hero (player.gd) asks steer() which way to go each
## physics step; auto hunt also attacks and uses the skills that fit.
## Moving by hand always wins; it also ends a walk.

const QuestLog := preload("res://scripts/player/quest_log.gd")
const MapGuide := preload("res://scripts/maps/map_guide.gd")
## How far from where AUTO was turned on the hero goes hunting.
const HUNT_RADIUS := 650.0
## Loot this close is picked up when there is nothing left to fight.
const LOOT_RADIUS := 260.0
## Close enough to a townsperson, or to the monsters a walk is for.
const ARRIVE := 80.0
const NEAR_MONSTERS := 260.0
const REPATH_SECONDS := 0.5
## Not getting closer for this long: give up on that target for a while.
const STUCK_SECONDS := 1.5
const SKIP_SECONDS := 6.0

## The hero (player.gd).
var hero: Node2D = null
var hunting: bool = false
## The walk under way: {"map", "npc" or "monster", "hunt"}; empty when not walking.
var walk_goal: Dictionary = {}

var _home: Vector2 = Vector2.ZERO
var _path := PackedVector2Array()
var _path_goal: Vector2 = Vector2.INF
var _path_age: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _last_direction: Vector2 = Vector2.ZERO
var _stuck: float = 0.0
var _target: Node2D = null
## Enemy -> seconds to leave it alone (it could not be reached).
var _skipped: Dictionary = {}


func active() -> bool:
	return hunting or not walk_goal.is_empty()


## Hunts around where the hero stands. False on a map without monsters.
func start_hunt() -> bool:
	var map_data: Dictionary = MapGuide.maps().get(hero.stats.map_id, {})
	if map_data.get("safe", false) or MapGuide.monsters_in(hero.stats.map_id).is_empty():
		return false
	hunting = true
	walk_goal = {}
	_home = hero.global_position
	_path = PackedVector2Array()
	return true


func stop() -> void:
	hunting = false
	walk_goal = {}
	_path = PackedVector2Array()
	_target = null


## Leaving a map ends auto hunt (a walk goes on in the next map).
func on_map_changed() -> void:
	hunting = false
	_path = PackedVector2Array()
	_target = null
	_skipped.clear()


## U6: walks to where a quest wants the hero: its giver when it can be handed
## in (or taken), the townsperson to talk to, or the monsters to hunt (then
## hunts them). False when there is no way to get there.
func walk_to_quest(quest_id: String) -> bool:
	var quest: Dictionary = QuestLog.list.get(quest_id, {})
	if quest.is_empty():
		return false
	var stats = hero.stats
	var state: String = stats.quests.state(quest_id, stats, QuestLog.today())
	var goal: Dictionary = {}
	var kind: String = quest["goal"]["type"]
	if state != "active":
		goal["npc"] = quest["giver"]
	elif kind == "talk":
		goal["npc"] = quest["goal"]["npc"]
	elif kind == "kill":
		goal["monster"] = quest["goal"]["monster"]
	else:
		goal["monster"] = MapGuide.monster_dropping(quest["goal"]["item"])
	if goal.has("npc"):
		goal["map"] = MapGuide.map_with_npc(goal["npc"])
	else:
		goal["map"] = MapGuide.map_with_monster(goal["monster"], stats.map_id)
		goal["hunt"] = true
	if goal["map"] == "" or MapGuide.next_map(stats.map_id, goal["map"]) == "":
		return false
	walk_goal = goal
	hunting = false
	_path = PackedVector2Array()
	return true


## The direction to walk this step (zero: stand). May attack or cast.
func steer(delta: float) -> Vector2:
	_tick(delta)
	var direction := Vector2.ZERO
	if not walk_goal.is_empty():
		direction = _walk()
	elif hunting:
		direction = _hunt()
	_last_direction = direction
	return direction


func _tick(delta: float) -> void:
	_path_age += delta
	for enemy in _skipped.keys():
		_skipped[enemy] = float(_skipped[enemy]) - delta
		if _skipped[enemy] <= 0.0 or not is_instance_valid(enemy):
			_skipped.erase(enemy)
	var moved: float = hero.global_position.distance_to(_last_position)
	_last_position = hero.global_position
	if _last_direction != Vector2.ZERO and moved < 0.5:
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck >= STUCK_SECONDS:
		_stuck = 0.0
		_path = PackedVector2Array()
		if is_instance_valid(_target):
			_skipped[_target] = SKIP_SECONDS
		_target = null


func _hunt() -> Vector2:
	_target = _pick_target()
	if _target == null:
		var loot: Node2D = _nearest_loot()
		if loot != null:
			return _go(loot.global_position)
		if hero.global_position.distance_to(_home) > ARRIVE:
			return _go(_home)
		return Vector2.ZERO
	var distance: float = hero.global_position.distance_to(_target.global_position)
	if _fight(distance):
		return Vector2.ZERO
	return _go(_target.global_position)


## Uses the first skill that fits, else attacks when in reach. False when the
## target is too far for anything: then the hero walks closer.
func _fight(distance: float) -> bool:
	for skill_id in hero.class_skills():
		if hero.can_use(skill_id) and _fits(hero.skills_data()[skill_id], distance):
			hero.use_skill(skill_id)
			return true
	if distance > hero.attack_range * 0.9:
		return false
	if float(hero.get("_attack_ready_in")) == 0.0:
		hero.call("_attack")
	return true


func _fits(skill: Dictionary, distance: float) -> bool:
	match skill["type"]:
		"buff":
			if skill.has("damage_bonus"):
				return distance < 220.0 and not hero.has_damage_bonus()
			return distance < 320.0 and float(hero.get("_crit_bonus")) == 0.0
		"shield":
			return distance < 250.0 and float(hero.get("_guard")) == 0.0
		"spin", "nova", "slam":
			return distance <= float(skill["radius"]) * 0.85
		"cleave":
			return distance <= float(skill["radius"]) * 0.8
	return distance <= float(skill.get("range", hero.attack_range))


func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for enemy in hero.enemies_near(_home, HUNT_RADIUS):
		if _skipped.has(enemy):
			continue
		var distance: float = enemy.global_position.distance_to(hero.global_position)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


func _nearest_loot() -> Node2D:
	var best: Node2D = null
	var best_distance: float = LOOT_RADIUS
	for pickup in hero.get_tree().get_nodes_in_group("pickups"):
		var distance: float = pickup.global_position.distance_to(hero.global_position)
		if distance < best_distance and not pickup.is_queued_for_deletion():
			best = pickup
			best_distance = distance
	return best


func _walk() -> Vector2:
	var here: String = hero.stats.map_id
	if here != walk_goal["map"]:
		var next: String = MapGuide.next_map(here, walk_goal["map"])
		for portal in hero.get_tree().get_nodes_in_group("portals"):
			if portal.get("to_map") == next:
				return _go(portal.global_position)
		stop()
		return Vector2.ZERO
	if walk_goal.has("npc"):
		return _walk_to_npc(walk_goal["npc"])
	var monster: Node2D = _nearest_monster(walk_goal["monster"])
	if monster == null or hero.global_position.distance_to(monster.global_position) < NEAR_MONSTERS:
		start_hunt()
		return Vector2.ZERO
	return _go(monster.global_position)


## Stands in front of the townsperson, then the walk is over.
func _walk_to_npc(npc_id: String) -> Vector2:
	for npc in hero.get_tree().get_nodes_in_group("npcs"):
		if npc.get("npc_id") == npc_id:
			var spot: Vector2 = npc.global_position + Vector2(0, 70)
			if hero.global_position.distance_to(spot) > ARRIVE:
				return _go(spot)
	walk_goal = {}
	return Vector2.ZERO


func _nearest_monster(monster_id: String) -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for enemy in hero.enemies_near(hero.global_position, 100000.0):
		if monster_id != "any" and enemy.get("monster_id") != monster_id:
			continue
		var distance: float = enemy.global_position.distance_to(hero.global_position)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


## The way to a point: along the map's navigation (around trees and rocks),
## or straight when the map has none yet.
func _go(point: Vector2) -> Vector2:
	if _path.is_empty() or _path_goal.distance_to(point) > 32.0 or _path_age > REPATH_SECONDS:
		_path = _find_path(point)
		_path_goal = point
		_path_age = 0.0
	while _path.size() > 1 and hero.global_position.distance_to(_path[0]) < 14.0:
		_path.remove_at(0)
	var next: Vector2 = _path[0] if not _path.is_empty() else point
	var offset: Vector2 = next - hero.global_position
	return Vector2.ZERO if offset.length() < 6.0 else offset.normalized()


func _find_path(point: Vector2) -> PackedVector2Array:
	var nav_map: RID = hero.get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(nav_map) == 0:
		return PackedVector2Array([point])
	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		nav_map, hero.global_position, point, true
	)
	return path if not path.is_empty() else PackedVector2Array([point])
