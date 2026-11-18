extends CharacterBody2D
## The warrior's state and everything he does with items and in town: the
## bag and gear, potions, books and scrolls, upgrades, stat points, titles,
## shops, storage, the healer and the guide, XP and gold. player.gd extends
## this with moving, fighting, skills, falling and changing maps.

signal hp_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal stats_changed
signal died
signal respawned
## A line for the message log, such as "+20 EXP" or "Your bag is full."
signal message(text: String, color: Color)

const CombatRules = preload("res://scripts/combat/combat_rules.gd")
const PlayerStats = preload("res://scripts/player/player_stats.gd")
const SaveFile = preload("res://scripts/player/save_file.gd")
const FloatingText = preload("res://scripts/ui/floating_text.gd")
const ItemDb = preload("res://scripts/items/item_db.gd")
const WarriorLook = preload("res://scripts/player/warrior_look.gd")
const HitSpark = preload("res://scripts/combat/hit_spark.gd")
const TargetMarker = preload("res://scripts/combat/target_marker.gd")
const StatusEffects = preload("res://scripts/combat/status_effects.gd")
const GameData = preload("res://scripts/data/game_data.gd")
const AchievementRecord = preload("res://scripts/player/achievement_record.gd")
const PICKUP_SCENE = preload("res://scenes/items/pickup.tscn")

const ACTION_LEFT := "move_left"
const ACTION_RIGHT := "move_right"
const ACTION_UP := "move_up"
const ACTION_DOWN := "move_down"
const ACTION_ATTACK := "attack"
const ACTION_DASH := "dash"
const ACTION_POTION := "use_potion"

const FACING_VECTORS := {
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
	"up": Vector2.UP,
}

## How long the swing animation keeps priority over walk / idle
## (5 frames at 18 fps in warrior_frames.tres).
const ATTACK_ANIMATION_SECONDS := 0.28
## Dropped items land this far in front of the warrior and stay this long.
const DROP_DISTANCE := 56.0
const DROPPED_ITEM_SECONDS := 120.0
const DAMAGE_TAKEN_COLOR := Color(0.8, 0.55, 1.0)
const XP_COLOR := Color(0.6, 0.85, 1.0)
const GOLD_COLOR := Color(1.0, 0.86, 0.4)
const LEVEL_COLOR := Color(1.0, 0.9, 0.3)
const WARNING_COLOR := Color(1.0, 0.5, 0.45)
const MISS_COLOR := Color(0.8, 0.85, 0.95)
## The ring under the auto-aim target shows for enemies this much past the reach.
const TARGET_MARKER_REACH := 1.6
const HURT_ANIMATION_SECONDS := 0.2
const STATUS_COLOR := Color(0.75, 0.9, 1.0)
const ACHIEVEMENT_COLOR := Color(1.0, 0.72, 0.95)
const QUEST_COLOR := Color(0.6, 0.9, 1.0)
const QuestLog = preload("res://scripts/player/quest_log.gd")

## Walking speed in pixels per second.
@export var move_speed: float = 220.0
## How far from the warrior a hit can land, in pixels.
@export var attack_range: float = 90.0
## Seconds between swings.
@export var attack_cooldown: float = 0.45
## Area the camera may show. Set by the map; an empty rect means no limits.
@export var camera_limits: Rect2 = Rect2()

## "down", "left", "right" or "up".
var facing: String = "down"
var stats = PlayerStats.new()
var hp: int = 0
var max_hp: int = 0
var stamina: float = 100.0
var max_stamina: float = 100.0
var is_dead: bool = false
## The sprite sheet built for the gear worn now (see warrior_look.gd).
var look_texture: Texture2D = null
## 1, 2 or 3: which swing of the combo comes next counts from here. The third is
## the finisher: stronger, with more knockback.
var combo_step: int = 0
## Poison, slow and stun on the warrior.
var statuses = StatusEffects.new()

var _attack_ready_in: float = 0.0
## Skill id -> seconds until it can be used again.
var _skill_cooldowns: Dictionary = {}
var _hurt_animation_left: float = 0.0
var _damage_bonus: float = 0.0
var _damage_bonus_left: float = 0.0
var _dash: Dictionary = {}
var _dash_left: float = 0.0
var _dash_ready_in: float = 0.0
var _dash_direction: Vector2 = Vector2.DOWN
var _attack_animation_left: float = 0.0
var _seconds_since_damage: float = 0.0
var _regen_progress: float = 0.0
var _spawn_position: Vector2 = Vector2.ZERO
var _invincible_left: float = 0.0
## Seconds before auto-potion may drink again.
var _auto_potion_ready_in: float = 0.0
var _combo_left: float = 0.0
var _target_marker: Node2D = null
# Tuning from res://data/character.json (see _load_tuning).
var _stamina_regen: float = 12.0
var _regen_delay: float = 5.0
var _regen_per_second: float = 2.0
var _respawn_seconds: float = 2.5
## After a hit the warrior blinks and cannot be hurt for this long.
var _hit_invincible_seconds: float = 1.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _camera: Camera2D = $Camera
@onready var _slash = $Slash


## Called by enemies when they die.
func gain_xp(amount: int) -> void:
	var levels_gained: int = stats.add_xp(amount)
	_say("+%d EXP" % amount, XP_COLOR)
	if levels_gained > 0:
		max_hp = stats.max_hp()
		hp = max_hp
		hp_changed.emit(hp, max_hp)
		FloatingText.spawn(self, "LEVEL UP!", LEVEL_COLOR, 120.0, 32)
		_sfx("levelup")
		_say("Level up! You are now level %d." % stats.level, LEVEL_COLOR)
		_say("%d stat points to spend: open STATS (C)." % stats.free_points(), LEVEL_COLOR)
		_announce(stats.record.check(stats.level))
	_progress_changed()


## Called by gold pickups.
func add_gold(amount: int) -> void:
	stats.gold += amount
	FloatingText.spawn(self, "+%d G" % amount, Color(1.0, 0.85, 0.3), 100.0, 22)
	_sfx("coin")
	_say("+%d gold" % amount, GOLD_COLOR)
	_announce(_count("gold_earned", amount))
	_progress_changed()


## Called by item pickups. Returns false, and the item stays on the ground,
## when the bag is full.
func add_item(item_id: String, count: int = 1) -> bool:
	if not stats.add_item(item_id, count):
		_say("Your bag is full.", WARNING_COLOR)
		return false
	var text: String = _item_name(item_id) + (" x%d" % count if count > 1 else "")
	FloatingText.spawn(self, "+" + text, Color(1.0, 0.6, 0.65), 100.0, 22)
	_sfx("coin")
	_say("Picked up %s." % text)
	_progress_changed()
	return true


## Buys one item from a shop. Only items the shop sells are offered (hud.gd).
func buy_item(item_id: String) -> void:
	var cost: int = ItemDb.price(item_id)
	if stats.gold < cost:
		_say("That costs %d gold." % cost, WARNING_COLOR)
	elif not stats.has_room_for(item_id):
		_say("Your bag is full.", WARNING_COLOR)
	else:
		stats.gold -= cost
		stats.add_item(item_id)
		_sfx("coin")
		_say("Bought %s for %d gold." % [_item_name(item_id), cost], GOLD_COLOR)
		_progress_changed()


## Sells one item from a bag slot (a whole piece of gear) to a shop.
func sell_from_bag(index: int) -> void:
	if index < 0 or index >= stats.bag.size():
		return
	var stack: Dictionary = stats.bag[index]
	var paid: int = ItemDb.sell_price(stack)
	var sold: String = ItemDb.display_name(stack, true)
	stats.take_from_bag(index)
	stats.gold += paid
	_sfx("coin")
	_say("Sold %s for %d gold." % [sold, paid], GOLD_COLOR)
	_progress_changed()


## Leaves a bag slot with the storage keeper.
func store_item(index: int) -> void:
	if stats.store(index):
		_progress_changed()
	else:
		_say("Your storage is full.", WARNING_COLOR)


## Takes a storage slot back into the bag.
func take_stored(index: int) -> void:
	if stats.take_stored(index):
		_progress_changed()
	else:
		_say("Your bag is full.", WARNING_COLOR)


## The town healer: full health and stamina, and no more poison or slow.
func heal_at_npc(_unused: Variant = null) -> void:
	statuses.clear()
	hp = max_hp
	stamina = max_stamina
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	FloatingText.spawn(self, "HEALED", Color(0.5, 1.0, 0.55), 110.0, 26)
	_sfx("potion")
	_say("You feel rested and whole again.", Color(0.5, 1.0, 0.55))


## The town guide sends the warrior to a map for its teleport price.
func travel(map_id: String) -> void:
	var map_data: Dictionary = GameData.table("maps")["maps"].get(map_id, {})
	if map_data.is_empty():
		return
	var cost: int = int(map_data.get("teleport_price", 0))
	if stats.gold < cost:
		_say("The trip costs %d gold." % cost, WARNING_COLOR)
		return
	stats.gold -= cost
	_progress_changed()
	get_tree().call_group("game", "change_map", map_id, "default")


## Picks up an entry as it is: gear keeps its rarity, upgrades and options.
func add_stack(stack: Dictionary) -> bool:
	if not ItemDb.is_gear(stack.get("id", "")):
		return add_item(stack.get("id", ""), int(stack.get("count", 1)))
	if not stats.add_stack(stack):
		_say("Your bag is full.", WARNING_COLOR)
		return false
	var text: String = ItemDb.display_name(stack, true)
	var color: Color = ItemDb.rarity_color(stack)
	FloatingText.spawn(self, "+" + text, color, 100.0, 22)
	_sfx("coin")
	_say("Picked up %s." % text, color)
	_progress_changed()
	return true


## Puts on the gear in a bag slot. Gear worn in that place goes to the bag.
func equip_from_bag(index: int) -> void:
	if is_dead or index < 0 or index >= stats.bag.size():
		return
	var piece: Dictionary = stats.bag[index]
	if stats.equip(index):
		_say("Equipped %s." % ItemDb.display_name(piece))
		_gear_changed()


## Moves worn gear (by gear slot, such as "weapon") into the bag.
func unequip(slot: String) -> void:
	var worn: Dictionary = stats.equipment.get(slot, {})
	if is_dead or worn.is_empty():
		return
	if not stats.unequip(slot):
		_say("Your bag is full.", WARNING_COLOR)
		return
	_say("Took off %s." % ItemDb.display_name(worn))
	_gear_changed()


## Drops one item from a bag slot on the ground in front of the warrior.
func drop_from_bag(index: int) -> void:
	if is_dead:
		return
	var taken: Dictionary = stats.take_from_bag(index)
	if taken.is_empty():
		return
	_drop_on_ground(taken)
	_progress_changed()


## Takes worn gear off and drops it on the ground.
func drop_equipped(slot: String) -> void:
	if is_dead:
		return
	var worn: Dictionary = stats.remove_equipped(slot)
	if worn.is_empty():
		return
	_drop_on_ground(worn)
	_gear_changed()


## Uses the item in a bag slot. Potions are the only usable item so far.
func use_from_bag(index: int) -> void:
	if index < 0 or index >= stats.bag.size():
		return
	var item_id: String = stats.bag[index]["id"]
	var item: Dictionary = ItemDb.items[item_id]
	if item_id == PlayerStats.POTION_ID:
		use_potion()
	elif item.has("stamina_fraction"):
		_drink_stamina_potion(index, item)
	elif item.has("teaches"):
		_read_book(index, item)
	elif item.get("resets_stats", false):
		_read_rebirth_scroll(index)


## Upgrades the gear in a bag slot with a stone from the bag.
func upgrade_bag_item(index: int) -> void:
	if index >= 0 and index < stats.bag.size():
		_upgrade(stats.bag[index])


## Upgrades worn gear (by gear slot, such as "weapon") with a stone from the bag.
func upgrade_equipped(slot: String) -> void:
	if stats.equipment.has(slot):
		_upgrade(stats.equipment[slot])


## Off -> 30% -> 50% -> 70% -> off: below that much HP a red potion is drunk by itself.
func cycle_auto_potion(_unused: Variant = null) -> void:
	var choices: Array = PlayerStats.auto_potion_choices()
	stats.auto_potion = choices[(choices.find(stats.auto_potion) + 1) % choices.size()]
	if stats.auto_potion == 0:
		_say("Auto potion is off.")
	else:
		_say("Auto potion: below %d%% HP." % stats.auto_potion)
	_progress_changed()


## W6: going into a dungeon uses one of its entries for today. Returns false,
## and says so, when none are left.
func enter_dungeon(map_id: String) -> bool:
	var map_data: Dictionary = GameData.table("maps")["maps"][map_id]
	var per_day: int = int(map_data["dungeon"]["entries_per_day"])
	var today: String = QuestLog.today()
	var left: int = stats.dungeons.entries_left(map_id, per_day, today)
	if left <= 0:
		_say(
			"%s lets you in %d times a day. Come back tomorrow." % [map_data["name"], per_day],
			WARNING_COLOR
		)
		return false
	stats.dungeons.count_entry(map_id, today)
	_say("Entering %s (%d entries left today)." % [map_data["name"], left - 1], QUEST_COLOR)
	_progress_changed()
	return true


## A cleared dungeon's reward: items (if they fit), gold and XP.
func dungeon_reward(reward: Dictionary) -> void:
	if stats.room_for(reward.get("items", [])):
		for entry in reward.get("items", []):
			stats.add_item(entry["id"], int(entry["count"]))
			_say("Got %s x%d." % [_item_name(entry["id"]), int(entry["count"])], QUEST_COLOR)
	else:
		_say("Your bag was full, so the reward items stayed behind.", WARNING_COLOR)
	if int(reward.get("gold", 0)) > 0:
		add_gold(int(reward["gold"]))
	if int(reward.get("xp", 0)) > 0:
		gain_xp(int(reward["xp"]))
	_progress_changed()


## Takes a quest a townsperson offers.
func accept_quest(quest_id: String) -> void:
	if stats.quests.start(quest_id, stats, QuestLog.today()):
		_say("New quest: %s." % QuestLog.list[quest_id]["name"], QUEST_COLOR)
		_progress_changed()


## Hands a finished quest back to its giver: collected items go, the reward comes.
func turn_in_quest(quest_id: String) -> void:
	if stats.quests.state(quest_id, stats, QuestLog.today()) != "ready":
		return
	var quest: Dictionary = QuestLog.list[quest_id]
	var reward: Dictionary = quest.get("reward", {})
	if not stats.room_for(reward.get("items", [])):
		_say("Make room in your bag for the reward first.", WARNING_COLOR)
		return
	if quest["goal"]["type"] == "collect":
		stats.remove_items(quest["goal"]["item"], int(quest["goal"]["count"]))
	stats.quests.finish(quest_id, QuestLog.today())
	FloatingText.spawn(self, "QUEST COMPLETE!", QUEST_COLOR, 130.0, 28)
	_say("Quest complete: %s!" % quest["name"], QUEST_COLOR)
	for entry in reward.get("items", []):
		stats.add_item(entry["id"], int(entry["count"]))
		_say("Got %s x%d." % [_item_name(entry["id"]), int(entry["count"])], QUEST_COLOR)
	if int(reward.get("gold", 0)) > 0:
		add_gold(int(reward["gold"]))
	if int(reward.get("xp", 0)) > 0:
		gain_xp(int(reward["xp"]))
	_progress_changed()


## Talking to a townsperson finishes the "talk" goals about them.
func talked_to(npc_id: String) -> void:
	var reached: Array = stats.quests.on_talk(npc_id)
	for quest_id in reached:
		_say("%s: done! Go back for the reward." % QuestLog.list[quest_id]["name"], QUEST_COLOR)
	if not reached.is_empty():
		_progress_changed()


## Called by a monster as it dies, just before it gives its XP (which saves).
func record_kill(monster_id: String, elite: bool) -> void:
	for quest_id in stats.quests.on_kill(monster_id):
		var counted: int = stats.quests.progress(quest_id, stats)
		var needed: int = stats.quests.goal_count(quest_id)
		_say("%s %d/%d" % [QuestLog.list[quest_id]["name"], counted, needed], QUEST_COLOR)
	var earned: Array = _count("kills")
	earned += _count("kills:" + monster_id)
	if elite:
		earned += _count("elite_kills")
	_announce(earned)


## Puts one free stat point into "strength", "agility", "vitality" or "energy".
func add_stat_point(stat_id: String) -> void:
	if stats.add_stat_point(stat_id):
		_limits_changed()
		_progress_changed()


## Gives every stat point back, for gold (STATS window).
func reset_stats(_unused: Variant = null) -> void:
	if stats.spent_points() == 0:
		_say("There are no stat points to give back.", WARNING_COLOR)
	elif not stats.reset_stats(true):
		_say("A stat reset costs %d gold." % stats.reset_cost(), WARNING_COLOR)
	else:
		_limits_changed()
		_say("All stat points are free again.", LEVEL_COLOR)
		_progress_changed()


## Shows an earned title, or none for "".
func choose_title(achievement_id: String) -> void:
	if stats.record.set_title(achievement_id):
		_limits_changed()
		_progress_changed()


## All skills from skills.json.
static func skills_data() -> Dictionary:
	return GameData.table("skills")


## Drinks one potion. Does nothing at full health or with no potions left.
func use_potion() -> void:
	if is_dead or stats.potions <= 0 or hp >= max_hp:
		return
	stats.potions -= 1
	var heal_fraction: float = float(ItemDb.items[PlayerStats.POTION_ID]["heal_fraction"])
	var healed: int = mini(roundi(max_hp * heal_fraction), max_hp - hp)
	hp += healed
	hp_changed.emit(hp, max_hp)
	FloatingText.spawn(self, "+%d" % healed, Color(0.5, 1.0, 0.55), 100.0)
	_sfx("potion")
	_announce(_count("potions_used"))
	_progress_changed()


func _progress_changed() -> void:
	SaveFile.save_data(stats.to_dict())
	stats_changed.emit()


## After the gear changed: health limits, look, save.
func _gear_changed() -> void:
	_limits_changed()
	_apply_look()
	_progress_changed()


## Rebuilds the sprite sheet for the gear worn now and points every frame at it.
func _apply_look() -> void:
	look_texture = WarriorLook.build(stats.equipment)
	var frames: SpriteFrames = _sprite.sprite_frames
	for animation in frames.get_animation_names():
		for i in frames.get_frame_count(animation):
			var frame := frames.get_frame_texture(animation, i) as AtlasTexture
			if frame != null:
				frame.atlas = look_texture


## After gear, stat points or the title changed: the health and stamina limits.
func _limits_changed() -> void:
	max_hp = stats.max_hp()
	hp = mini(hp, max_hp)
	max_stamina = stats.max_stamina()
	stamina = minf(stamina, max_stamina)
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)


func _count(counter: String, amount: int = 1) -> Array:
	return stats.record.count(counter, amount, stats.level)


## Tells the player about achievements just earned.
func _announce(earned: Array) -> void:
	if earned.is_empty():
		return
	for achievement_id in earned:
		var achievement: Dictionary = AchievementRecord.list[achievement_id]
		_say(
			'Achievement: %s! Title "%s".' % [achievement["name"], achievement["title"]],
			ACHIEVEMENT_COLOR
		)
	FloatingText.spawn(self, "ACHIEVEMENT!", ACHIEVEMENT_COLOR, 140.0, 28)
	_sfx("levelup")
	_limits_changed()


## A skill book teaches its skill once the level is high enough.
func _read_book(index: int, item: Dictionary) -> void:
	var skill_id: String = item["teaches"]
	var skill: Dictionary = skills_data()[skill_id]
	var needed_level: int = int(skill["unlock_level"])
	if stats.knows_skill(skill_id):
		_say("You already know %s." % skill["name"], WARNING_COLOR)
	elif stats.level < needed_level:
		_say("Reach level %d to learn %s." % [needed_level, skill["name"]], WARNING_COLOR)
	else:
		stats.take_from_bag(index)
		stats.learn_skill(skill_id)
		FloatingText.spawn(self, "NEW SKILL!", LEVEL_COLOR, 120.0, 30)
		_sfx("levelup")
		_say("You learned %s!" % skill["name"], LEVEL_COLOR)
		_announce(_count("books_read"))
		_progress_changed()


func _upgrade(stack: Dictionary) -> void:
	if is_dead:
		return
	var step: Dictionary = ItemDb.upgrade_step(stack)
	if step.is_empty():
		_say("%s cannot go any higher." % ItemDb.display_name(stack), WARNING_COLOR)
		return
	if stats.count_of(step["stone"]) <= 0:
		_say("You need a %s." % _item_name(step["stone"]), WARNING_COLOR)
		return
	var item_name: String = _item_name(stack["id"])
	match stats.upgrade(stack, randf()):
		"up":
			FloatingText.spawn(self, "+%d!" % int(stack["plus"]), LEVEL_COLOR, 120.0, 30)
			_sfx("levelup")
			_say("Success! %s." % ItemDb.display_name(stack), LEVEL_COLOR)
		"down":
			_sfx("hurt")
			_say("It failed, and %s fell to +%d." % [item_name, stack["plus"]], WARNING_COLOR)
		_:
			_say("It failed. %s stays at +%d." % [item_name, stack["plus"]], WARNING_COLOR)
	_limits_changed()
	_progress_changed()


## A Blue Potion gives back part of the stamina.
func _drink_stamina_potion(index: int, item: Dictionary) -> void:
	if stamina >= max_stamina:
		_say("Your stamina is full.", WARNING_COLOR)
		return
	stats.take_from_bag(index)
	stamina = minf(max_stamina, stamina + max_stamina * float(item["stamina_fraction"]))
	stamina_changed.emit(stamina, max_stamina)
	FloatingText.spawn(self, "STAMINA", Color(0.5, 0.75, 1.0), 100.0)
	_sfx("potion")
	_announce(_count("potions_used"))
	_progress_changed()


## A Rebirth Scroll gives every stat point back for free.
func _read_rebirth_scroll(index: int) -> void:
	if stats.spent_points() == 0:
		_say("There are no stat points to give back.", WARNING_COLOR)
		return
	stats.take_from_bag(index)
	stats.reset_stats(false)
	_limits_changed()
	_say("All stat points are free again.", LEVEL_COLOR)
	_progress_changed()


## stack: the entry dropped; gear keeps its rarity, upgrades and options.
func _drop_on_ground(stack: Dictionary) -> void:
	var pickup: Node2D = PICKUP_SCENE.instantiate()
	pickup.set("kind", "item")
	pickup.set("item_id", stack["id"])
	pickup.set("amount", int(stack.get("count", 1)))
	if ItemDb.is_gear(stack["id"]):
		pickup.set("stack", stack)
	pickup.set("lifetime", DROPPED_ITEM_SECONDS)
	pickup.set("pickup_delay", 1.0)
	pickup.position = position + FACING_VECTORS[facing] * DROP_DISTANCE
	var current_map: Node = get_tree().get_first_node_in_group("maps")
	(current_map if current_map != null else get_parent()).call_deferred("add_child", pickup)
	_say("Dropped %s." % ItemDb.display_name(stack))


func _say(text: String, color: Color = Color.WHITE) -> void:
	message.emit(text, color)


func _item_name(item_id: String) -> String:
	return ItemDb.items[item_id]["name"]


func _sfx(sound_name: String) -> void:
	get_tree().call_group("sfx", "play", sound_name)
