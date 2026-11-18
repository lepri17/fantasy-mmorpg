"""Checks the game data in client/data/*.json without Godot.

What it checks:
  - every file parses and has the fields the game reads, with the right types
  - every item, icon, slot and drop the data refers to exists
  - the starting gear fits its slots and the starting bag fits the bag
  - the warrior art (tools/generate_assets.py) only asks for items that exist

Run:  python tools/check_data.py        (exit code 1 when something is wrong)
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLIENT = ROOT / "client"
DATA = CLIENT / "data"

errors: list[str] = []
check_items_cache: dict = {}


def error(message: str) -> None:
    errors.append(message)


def load(name: str) -> dict:
    path = DATA / f"{name}.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        error(f"{name}.json: cannot read ({exc})")
        return {}
    if not isinstance(data, dict):
        error(f"{name}.json: the top level must be an object")
        return {}
    return data


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def need_number(where: str, data: dict, key: str, low: float = 0.0, high: float | None = None):
    value = data.get(key)
    if not is_number(value):
        error(f"{where}: '{key}' must be a number (got {value!r})")
        return None
    if value < low or (high is not None and value > high):
        error(f"{where}: '{key}' = {value} is outside {low}..{high if high is not None else 'any'}")
    return value


def res_exists(path: str) -> bool:
    return path.startswith("res://") and (CLIENT / path[len("res://"):]).exists()


def check_items(items_data: dict) -> dict:
    gear_slots = items_data.get("gear_slots", [])
    if not isinstance(gear_slots, list) or not all(isinstance(s, str) for s in gear_slots):
        error("items.json: 'gear_slots' must be a list of names")
        gear_slots = []
    slot_names = items_data.get("slot_names", {})
    if set(slot_names) != set(gear_slots):
        error("items.json: 'slot_names' must name exactly the gear slots")
    items = items_data.get("items", {})
    if not isinstance(items, dict) or not items:
        error("items.json: 'items' must be a non-empty object")
        return {}
    for item_id, item in items.items():
        where = f"items.json: item '{item_id}'"
        if not isinstance(item.get("name"), str) or not item["name"]:
            error(f"{where}: needs a 'name'")
        if not isinstance(item.get("text"), str):
            error(f"{where}: needs a 'text'")
        slot = item.get("slot")
        if slot != "" and slot not in gear_slots:
            error(f"{where}: slot '{slot}' is not a gear slot")
        for key in ("icon", "world_icon"):
            if key in item and not res_exists(item[key]):
                error(f"{where}: {key} '{item[key]}' does not exist")
        if "icon" not in item:
            error(f"{where}: needs an 'icon'")
        for key in ("attack", "max_hp", "defense"):
            if key in item:
                value = need_number(where, item, key)
                if value is not None and value != int(value):
                    error(f"{where}: '{key}' must be a whole number")
        for key in ("crit_chance", "evasion"):
            if key in item:
                need_number(where, item, key, 0.0, 1.0)
        if item.get("usable"):
            if slot != "":
                error(f"{where}: gear cannot be 'usable'")
            if "heal_fraction" in item:
                need_number(where, item, "heal_fraction", 0.01, 1.0)
    return items


def check_classes(classes: dict, character: dict, items: dict, skills: dict) -> None:
    """classes.json: each class's art, attack, numbers over character.json, stats,
    starting gear (its own) and skills (one per button)."""
    where = "classes.json"
    table = classes.get("classes", {})
    if not isinstance(table, dict) or not table:
        error(f"{where}: 'classes' must be a non-empty object")
        return
    if classes.get("order") != list(table):
        error(f"{where}: 'order' must list every class once, in the same order")
    for class_id, info in table.items():
        place = f"{where}: '{class_id}'"
        for key in ("name", "text", "resource", "resource_short"):
            if not isinstance(info.get(key), str) or not info[key]:
                error(f"{place}: needs a '{key}'")
        for ext in (".png", ".gd"):
            if not res_exists(str(info.get("parts", "")) + ext):
                error(f"{place}: parts '{info.get('parts')}{ext}' does not exist")
        color = info.get("resource_color")
        if not (isinstance(color, list) and len(color) == 3 and all(is_number(c) for c in color)):
            error(f"{place}: 'resource_color' must be three numbers")
        attack = info.get("attack", {})
        if attack.get("type") == "shot":
            if attack.get("kind") not in ("bolt", "arrow"):
                error(f"{place}: a shot attack's kind must be 'bolt' or 'arrow'")
            for key in ("speed", "radius"):
                need_number(place + " attack", attack, key, 1)
        elif attack.get("type") != "melee":
            error(f"{place}: attack type must be 'melee' or 'shot'")
        rules = info.get("rules", {})
        for key in rules:
            if key not in character:
                error(f"{place}: rule '{key}' is not in character.json")
        for slot, item_id in rules.get("starting_gear", {}).items():
            item = items.get(item_id)
            if item is None or item.get("slot") != slot:
                error(f"{place}: starting gear '{item_id}' is not worn in '{slot}'")
            elif class_id not in item.get("classes", [class_id]):
                error(f"{place}: starting gear '{item_id}' is not for this class")
        for stat_id, rule in info.get("stats", {}).items():
            if stat_id not in character.get("stats", {}):
                error(f"{place}: stat '{stat_id}' is not in character.json")
            check_bonus(f"{place}: stat '{stat_id}'",
                        {k: v for k, v in rule.items() if k not in ("short", "text")})
        actions = sorted(s.get("action") for s in skills.values() if s.get("class") == class_id)
        if actions != sorted(BASIC_ACTIONS + [JOB_ACTION]):
            error(f"{place}: needs exactly one skill for each of "
                  f"{BASIC_ACTIONS + [JOB_ACTION]}, has {actions}")
        advanced = info.get("advanced", {})
        if not isinstance(advanced.get("name"), str) or len(advanced.get("color", [])) != 3:
            error(f"{place}: 'advanced' needs a 'name' and a 'color'")
    for skill_id, skill in skills.items():
        if skill.get("class") not in table:
            error(f"skills.json: '{skill_id}' class '{skill.get('class')}' is not a class")
    for item_id, item in items.items():
        for class_id in item.get("classes", []):
            if class_id not in table:
                error(f"items.json: '{item_id}' names unknown class '{class_id}'")
        if "classes" in item and item.get("slot", "") == "":
            error(f"items.json: '{item_id}' is not gear, so it cannot be for some classes only")


def check_character(character: dict, items: dict, gear_slots: list) -> None:
    where = "character.json"
    for key in ("base_max_hp", "base_damage", "xp_per_level", "move_speed", "attack_range",
                "attack_cooldown", "max_stamina", "bag_size", "respawn_seconds"):
        need_number(where, character, key, 0.01)
    for key in ("hp_per_level", "damage_per_level", "stamina_regen_per_second",
                "regen_delay_seconds", "regen_hp_per_second", "hit_invincible_seconds",
                "defense"):
        need_number(where, character, key)
    for key in ("crit_chance", "evasion"):
        need_number(where, character, key, 0.0, 1.0)
    gear = character.get("starting_gear", {})
    for slot, item_id in gear.items():
        if slot not in gear_slots:
            error(f"{where}: starting gear slot '{slot}' is not a gear slot")
        elif item_id not in items:
            error(f"{where}: starting gear '{item_id}' is not an item")
        elif items[item_id].get("slot") != slot:
            error(f"{where}: '{item_id}' is not worn in '{slot}'")
    bag = character.get("starting_bag", [])
    if len(bag) > character.get("bag_size", 0):
        error(f"{where}: the starting bag has more stacks than the bag holds")
    for stack in bag:
        if stack.get("id") not in items:
            error(f"{where}: starting bag item '{stack.get('id')}' is not an item")
        if not is_number(stack.get("count")) or stack["count"] < 1:
            error(f"{where}: starting bag count must be at least 1")


def check_monsters(monsters: dict, items: dict) -> None:
    if not monsters:
        error("monsters.json: no monsters")
    for monster_id, monster in monsters.items():
        where = f"monsters.json: '{monster_id}'"
        if not isinstance(monster.get("name"), str):
            error(f"{where}: needs a 'name'")
        for key in ("level", "max_hp", "move_speed", "detect_radius", "attack_range",
                    "attack_damage", "attack_cooldown", "respawn_seconds", "xp"):
            need_number(where, monster, key, 0.01 if key != "xp" else 0)
        need_number(where, monster, "defense")
        need_number(where, monster, "evasion", 0.0, 1.0)
        if "frames" in monster and not res_exists(monster["frames"]):
            error(f"{where}: frames {monster['frames']} do not exist")
        if "scale" in monster:
            need_number(where, monster, "scale", 0.5, 4.0)
        boss = monster.get("boss")
        if boss is not None:
            need_number(where + " boss", boss, "enrage_at", 0.05, 0.95)
            need_number(where + " boss", boss, "enrage_speed", 1.0, 3.0)
            need_number(where + " boss", boss, "rarity_rolls", 1, 5)
            summon = boss.get("summon", {})
            if summon:
                if summon.get("monster") not in monsters or summon.get("monster") == monster_id:
                    error(f"{where}: boss summons must be another monster")
                need_number(where + " summon", summon, "count", 1, 10)
                need_number(where + " summon", summon, "every", 1.0)
                need_number(where + " summon", summon, "most", summon.get("count", 1), 20)
        ranged = monster.get("ranged")
        if ranged is not None:
            keep = need_number(where + " ranged", ranged, "keep_distance", 0)
            need_number(where + " ranged", ranged, "projectile_speed", 50)
            if keep is not None and keep >= monster.get("attack_range", 0):
                error(f"{where}: ranged keep_distance must be less than attack_range")
            hit = ranged.get("on_hit")
            if hit is not None and hit.get("status") not in ("poison", "slow", "stun"):
                error(f"{where}: ranged on_hit status must be poison, slow or stun")
        gold = monster.get("gold")
        if not (isinstance(gold, list) and len(gold) == 2 and all(map(is_number, gold))
                and 0 <= gold[0] <= gold[1]):
            error(f"{where}: 'gold' must be [min, max] with 0 <= min <= max")
        for drop in monster.get("drops", []):
            if drop.get("item") not in items:
                error(f"{where}: drop '{drop.get('item')}' is not an item")
            need_number(f"{where} drop", drop, "chance", 0.0, 1.0)
        tint = monster.get("tint", [1, 1, 1, 1])
        if not (isinstance(tint, list) and len(tint) == 4 and all(map(is_number, tint))):
            error(f"{where}: 'tint' must be four numbers")


SKILL_TYPES = {
    "spin": ("radius", "damage_multiplier"),
    "strike": ("range", "damage_multiplier"),
    "buff": ("seconds",),
    "slam": ("radius", "damage_multiplier", "stun_seconds"),
    "bolt": ("range", "speed", "damage_multiplier", "blast_radius"),
    "nova": ("radius", "damage_multiplier", "slow_seconds", "slow"),
    "shield": ("seconds", "damage_cut"),
    "meteor": ("range", "radius", "delay", "damage_multiplier", "stun_seconds"),
    "fan": ("arrows", "spread_degrees", "range", "speed", "damage_multiplier"),
    "pierce": ("range", "speed", "damage_multiplier"),
    "rain": ("range", "radius", "waves", "every", "damage_multiplier"),
    "cleave": ("radius", "arc_degrees", "damage_multiplier"),
    "chain": ("range", "jump_range", "jumps", "damage_multiplier"),
}
SKILL_ACTIONS = {"skill", "skill_2", "skill_3", "skill_4", "skill_5"}
# A class's five skill buttons: four basic ones, and one after the job advancement.
BASIC_ACTIONS = ["skill", "skill_2", "skill_3", "skill_4"]
JOB_ACTION = "skill_5"


def check_skills(skills: dict) -> None:
    used_actions = set()
    for skill_id, skill in skills.items():
        where = f"skills.json: '{skill_id}'"
        for key in ("name", "button", "text"):
            if not isinstance(skill.get(key), str):
                error(f"{where}: needs a '{key}'")
        action = skill.get("action")
        if action not in SKILL_ACTIONS:
            error(f"{where}: action '{action}' is not one of {sorted(SKILL_ACTIONS)}")
        elif (skill.get("class"), action) in used_actions:
            error(f"{where}: action '{action}' is used by two {skill.get('class')} skills")
        used_actions.add((skill.get("class"), action))
        if (action == JOB_ACTION) != bool(skill.get("job", False)):
            error(f"{where}: only job skills (\"job\": true) go on '{JOB_ACTION}'")
        if skill.get("type") == "buff" and not any(
            k in skill for k in ("damage_bonus", "crit_bonus")
        ):
            error(f"{where}: a buff needs 'damage_bonus' or 'crit_bonus'")
        for key in ("stamina", "cooldown"):
            need_number(where, skill, key)
        need_number(where, skill, "unlock_level", 1)
        kind = skill.get("type")
        if kind not in SKILL_TYPES:
            error(f"{where}: type '{kind}' is not one of {sorted(SKILL_TYPES)}")
            continue
        for key in SKILL_TYPES[kind]:
            need_number(where, skill, key)


# What stat points and titles may add (player_stats.gd extra_bonus()).
BONUS_KEYS = {"attack", "max_hp", "defense", "crit_chance", "evasion", "max_stamina",
              "skill_damage"}
# Counters the game adds to (player.gd), plus "kills:<monster id>".
COUNTERS = {"level", "kills", "elite_kills", "gold_earned", "potions_used", "deaths",
            "books_read"}


def check_bonus(where: str, bonus: dict) -> None:
    if not isinstance(bonus, dict):
        error(f"{where}: bonus must be an object")
        return
    for key in bonus:
        if key not in BONUS_KEYS:
            error(f"{where}: '{key}' is not one of {sorted(BONUS_KEYS)}")
        else:
            need_number(where, bonus, key)


def check_progress(character: dict, items: dict, skills: dict, monsters: dict,
                   achievements: dict) -> None:
    """Stat points, skill books, the Rebirth Scroll and the achievements."""
    where = "character.json"
    choices = character.get("auto_potion_choices", [])
    if not (isinstance(choices, list) and 0 in choices
            and all(is_number(c) and 0 <= c < 100 for c in choices)):
        error(f"{where}: 'auto_potion_choices' must be percents below 100, with 0 for off")
    need_number(where, character, "auto_potion_seconds", 0.1)
    for key in ("stat_points_per_level", "stat_reset_gold_per_level"):
        value = need_number(where, character, key)
        if value is not None and value != int(value):
            error(f"{where}: '{key}' must be a whole number")
    stats = character.get("stats", {})
    if not isinstance(stats, dict) or not stats:
        error(f"{where}: 'stats' must be a non-empty object")
        stats = {}
    for stat_id, rule in stats.items():
        for key in ("short", "text"):
            if not isinstance(rule.get(key), str):
                error(f"{where}: stat '{stat_id}' needs a '{key}'")
        check_bonus(f"{where}: stat '{stat_id}'",
                    {k: v for k, v in rule.items() if k not in ("short", "text")})
    for item_id, item in items.items():
        if item.get("usable") and not any(k in item for k in
                                          ("heal_fraction", "stamina_fraction", "teaches",
                                           "resets_stats")):
            error(f"items.json: '{item_id}' is usable but does nothing")
        if "teaches" in item:
            skill = skills.get(item["teaches"])
            if skill is None:
                error(f"items.json: '{item_id}' teaches unknown skill '{item['teaches']}'")
            elif skill.get("book") != item_id:
                error(f"items.json: '{item_id}' teaches '{item['teaches']}', "
                      "but that skill does not name it as its book")
    for skill_id, skill in skills.items():
        book = skill.get("book")
        if book is not None and items.get(book, {}).get("teaches") != skill_id:
            error(f"skills.json: '{skill_id}' book '{book}' is not an item that teaches it")
    if not isinstance(achievements, dict) or not achievements:
        error("achievements.json: must be a non-empty object")
        return
    for achievement_id, achievement in achievements.items():
        place = f"achievements.json: '{achievement_id}'"
        for key in ("name", "text", "title"):
            if not isinstance(achievement.get(key), str) or not achievement[key]:
                error(f"{place}: needs a '{key}'")
        counter = achievement.get("counter", "")
        if counter.startswith("kills:"):
            if counter[len("kills:"):] not in monsters:
                error(f"{place}: '{counter}' names an unknown monster")
        elif counter not in COUNTERS:
            error(f"{place}: counter '{counter}' is not one of {sorted(COUNTERS)}")
        goal = need_number(place, achievement, "goal", 1)
        if goal is not None and goal != int(goal):
            error(f"{place}: 'goal' must be a whole number")
        check_bonus(place, achievement.get("bonus", {}))


def check_gear(items_data: dict, monsters: dict, elite: dict) -> None:
    """Rarities, the random options on dropped gear, and the gear drop tables."""
    rarities = items_data.get("rarities", {})
    if not isinstance(rarities, dict) or not rarities:
        error("items.json: 'rarities' must be a non-empty object")
        rarities = {}
    for rarity_id, rarity in rarities.items():
        where = f"items.json: rarity '{rarity_id}'"
        if not isinstance(rarity.get("name"), str):
            error(f"{where}: needs a 'name'")
        color = rarity.get("color")
        if not (isinstance(color, list) and len(color) == 4 and all(is_number(c) for c in color)):
            error(f"{where}: 'color' must be [r, g, b, a]")
        need_number(where, rarity, "options", 0, len(items_data.get("random_options", {})))
        need_number(where, rarity, "weight", 0.0001)
    for stat, span in items_data.get("random_options", {}).items():
        if stat not in BONUS_KEYS:
            error(f"items.json: random option '{stat}' is not one of {sorted(BONUS_KEYS)}")
        if not (isinstance(span, list) and len(span) == 2 and all(is_number(v) for v in span)
                and 0 < span[0] <= span[1]):
            error(f"items.json: random option '{stat}' must be [low, high] with 0 < low <= high")
    gear_ids = {i for i, item in items_data.get("items", {}).items() if item.get("slot")}
    for monster_id, monster in monsters.items():
        table = monster.get("gear_drops")
        if table is None:
            continue
        where = f"monsters.json: '{monster_id}' gear_drops"
        need_number(where, table, "chance", 0.0, 1.0)
        pool = table.get("items", [])
        if not pool:
            error(f"{where}: 'items' must list gear")
        for item_id in pool:
            if item_id not in gear_ids:
                error(f"{where}: '{item_id}' is not gear")
    need_number("combat.json elite", elite, "gear_chance", 0.0, 1.0)
    need_number("combat.json elite", elite, "rarity_rolls", 1, 5)
    for item_id, item in items_data.get("items", {}).items():
        if "stamina_fraction" in item:
            need_number(f"items.json: '{item_id}'", item, "stamina_fraction", 0.01, 1.0)
    check_upgrades(items_data)
    check_sets(items_data)


def check_sets(items_data: dict) -> None:
    """Look-alike gear ("look") and sets ("set", with bonuses by pieces worn)."""
    items = items_data.get("items", {})
    sets = items_data.get("sets", {})
    for item_id, item in items.items():
        where = f"items.json: '{item_id}'"
        if "look" in item:
            base = items.get(item["look"], {})
            if not base.get("slot") or base.get("slot") != item.get("slot") or "look" in base:
                error(f"{where}: look '{item['look']}' must be plain gear of the same slot")
        if "set" in item and item["set"] not in sets:
            error(f"{where}: set '{item['set']}' is not in 'sets'")
    for set_id, set_data in sets.items():
        where = f"items.json: set '{set_id}'"
        size = sum(1 for item in items.values() if item.get("set") == set_id)
        if not isinstance(set_data.get("name"), str):
            error(f"{where}: needs a 'name'")
        for needed, bonus in set_data.get("bonuses", {}).items():
            if not needed.isdigit() or not 2 <= int(needed) <= size:
                error(f"{where}: bonus key '{needed}' must be a piece count from 2 to {size}")
            check_bonus(f"{where} bonus {needed}", bonus)


def check_upgrades(items_data: dict) -> None:
    """+1..+15 upgrades: the steps, their stones and what each level adds."""
    upgrades = items_data.get("upgrades", {})
    where = "items.json upgrades"
    max_plus = need_number(where, upgrades, "max_plus", 1, 99)
    items = items_data.get("items", {})
    last = 0
    for step in upgrades.get("steps", []):
        up_to = need_number(where, step, "up_to", last + 1, max_plus)
        last = up_to if up_to is not None else last
        if not items.get(step.get("stone"), {}).get("upgrade_stone"):
            error(f"{where}: stone '{step.get('stone')}' is not an item with \"upgrade_stone\"")
        need_number(where, step, "chance", 0.01, 1.0)
        if step.get("on_fail", "stay") not in ("stay", "down"):
            error(f"{where}: on_fail must be 'stay' or 'down'")
    if max_plus is not None and last != max_plus:
        error(f"{where}: the last step must reach max_plus ({max_plus})")
    for slot, bonus in upgrades.get("per_plus", {}).items():
        if slot not in items_data.get("gear_slots", []):
            error(f"{where}: per_plus slot '{slot}' is not a gear slot")
        check_bonus(f"{where} per_plus '{slot}'", bonus)


OBJECT_TYPES = {"tree", "rock", "monster", "portal", "npc", "torch"}
SERVICES = {"shop", "heal", "storage", "teleport", "quests"}


def check_quests(quests: dict, npcs: dict, items: dict, monsters: dict) -> None:
    """quests.json: givers, goals, rewards and the order quests open in."""
    for quest_id, quest in quests.items():
        where = f"quests.json: '{quest_id}'"
        for key in ("name", "text", "done_text"):
            if not isinstance(quest.get(key), str) or not quest[key]:
                error(f"{where}: needs a '{key}'")
        if quest.get("giver") not in npcs:
            error(f"{where}: giver '{quest.get('giver')}' is not in npcs.json")
        need_number(where, quest, "level", 1, 999)
        if "after" in quest and quest["after"] not in quests:
            error(f"{where}: comes after unknown quest '{quest['after']}'")
        goal = quest.get("goal", {})
        kind = goal.get("type")
        if kind == "kill":
            if goal.get("monster") != "any" and goal.get("monster") not in monsters:
                error(f"{where}: kills unknown monster '{goal.get('monster')}'")
            need_number(where + " goal", goal, "count", 1)
        elif kind == "collect":
            if goal.get("item") not in items:
                error(f"{where}: collects unknown item '{goal.get('item')}'")
            need_number(where + " goal", goal, "count", 1)
        elif kind == "talk":
            if goal.get("npc") not in npcs:
                error(f"{where}: talks to unknown npc '{goal.get('npc')}'")
        else:
            error(f"{where}: goal type must be kill, collect or talk")
        reward = quest.get("reward", {})
        for key in ("xp", "gold"):
            if key in reward:
                need_number(where + " reward", reward, key, 0)
        for entry in reward.get("items", []):
            if entry.get("id") not in items:
                error(f"{where}: rewards unknown item '{entry.get('id')}'")
            need_number(where + " reward", entry, "count", 1)


def check_npcs(npcs: dict, items: dict) -> None:
    """npcs.json: names, looks with art, services, and what shops sell."""
    for npc_id, npc in npcs.items():
        where = f"npcs.json: '{npc_id}'"
        for key in ("name", "title", "greeting"):
            if not isinstance(npc.get(key), str) or not npc[key]:
                error(f"{where}: needs a '{key}'")
        if not res_exists(f"res://assets/characters/npcs/{npc.get('look')}.png"):
            error(f"{where}: look '{npc.get('look')}' has no picture")
        for service in npc.get("services", []):
            if service not in SERVICES:
                error(f"{where}: service '{service}' is not one of {sorted(SERVICES)}")
        if "shop" in npc.get("services", []) and not npc.get("shop"):
            error(f"{where}: a shop needs a 'shop' list")
        for item_id in npc.get("shop", []):
            if item_id not in items or items[item_id].get("price", 0) <= 0:
                error(f"{where}: sells '{item_id}', which is not an item with a price")


def check_maps(maps_data: dict, monsters: dict, npcs: dict) -> None:
    """maps.json: ground rows, spawns, and objects; portals lead to a real spawn."""
    maps = maps_data.get("maps", {})
    for key in ("start", "town"):
        if maps_data.get(key) not in maps:
            error(f"maps.json: '{key}' must name a map")
    tile = need_number("maps.json", maps_data, "tile_size", 16) or 128
    kinds = maps_data.get("tile_kinds", [])
    legend = maps_data.get("legend", {})
    for letter, kind in legend.items():
        if len(letter) != 1 or kind not in kinds:
            error(f"maps.json: legend '{letter}' -> '{kind}' is not one letter and a tile kind")
    for map_id, data in maps.items():
        where = f"maps.json: map '{map_id}'"
        if not isinstance(data.get("name"), str):
            error(f"{where}: needs a 'name'")
        need_number(where, data, "teleport_price", 0)
        if "music" in data and not res_exists(f"res://assets/audio/{data['music']}.wav"):
            error(f"{where}: music '{data['music']}' has no file in assets/audio")
        if not isinstance(data.get("indoor", False), bool):
            error(f"{where}: 'indoor' must be true or false")
        if "ground" in data:
            rows = data["ground"]
            if not rows or any(len(row) != len(rows[0]) for row in rows):
                error(f"{where}: ground rows must all be the same length")
                continue
            for row in rows:
                for letter in row:
                    if letter not in legend:
                        error(f"{where}: ground letter '{letter}' is not in the legend")
            size = (len(rows[0]) * tile, len(rows) * tile)
        elif "scene" in data:
            if not res_exists(data["scene"]):
                error(f"{where}: scene {data['scene']} does not exist")
            size = tuple(data.get("size", (0, 0)))
        else:
            error(f"{where}: needs 'ground' rows or a 'scene'")
            continue

        def inside(point, what):
            if not (isinstance(point, list) and len(point) == 2 and all(is_number(v) for v in point)
                    and 0 <= point[0] <= size[0] and 0 <= point[1] <= size[1]):
                error(f"{where}: {what} {point} is not a point on the map")
                return False
            return True

        invasion = data.get("invasion")
        if invasion is not None:
            if invasion.get("monster") not in monsters:
                error(f"{where}: invasion monster '{invasion.get('monster')}' is unknown")
            need_number(where + " invasion", invasion, "count", 1, 30)
            every = need_number(where + " invasion", invasion, "every_minutes", 2, 60)
            need_number(where + " invasion", invasion, "lasts_minutes", 1, (every or 60) - 1)
            area = invasion.get("area", [])
            if not (len(area) == 4 and inside(area[:2], "invasion area corner")
                    and inside(area[2:], "invasion area corner") and area[0] < area[2]
                    and area[1] < area[3]):
                error(f"{where}: invasion area must be [left, top, right, bottom] on the map")
        dungeon = data.get("dungeon")
        if dungeon is not None:
            need_number(where + " dungeon", dungeon, "entries_per_day", 1, 50)
            area = dungeon.get("area", [])
            if not (len(area) == 4 and inside(area[:2], "dungeon area corner")
                    and inside(area[2:], "dungeon area corner")):
                error(f"{where}: dungeon area must be [left, top, right, bottom] on the map")
            if not dungeon.get("waves"):
                error(f"{where}: a dungeon needs waves")
            for wave in dungeon.get("waves", []):
                for group in wave:
                    if group.get("monster") not in monsters:
                        error(f"{where}: dungeon wave monster '{group.get('monster')}' is unknown")
                    need_number(where + " wave", group, "count", 1, 30)
            if dungeon.get("boss") not in monsters:
                error(f"{where}: dungeon boss '{dungeon.get('boss')}' is unknown")
            exit_portal = dungeon.get("exit", {})
            if exit_portal.get("to") not in maps:
                error(f"{where}: dungeon exit leads to unknown map '{exit_portal.get('to')}'")
            inside(exit_portal.get("pos"), "dungeon exit")
        spawns = data.get("spawns", {})
        if "default" not in spawns:
            error(f"{where}: needs a 'default' spawn")
        for spawn_name, point in spawns.items():
            inside(point, f"spawn '{spawn_name}'")
        for thing in data.get("objects", []):
            kind = thing.get("type")
            if kind not in OBJECT_TYPES:
                error(f"{where}: object type '{kind}' is not one of {sorted(OBJECT_TYPES)}")
                continue
            if not inside(thing.get("pos"), kind):
                continue
            if kind == "npc" and thing.get("id") not in npcs:
                error(f"{where}: npc '{thing.get('id')}' is not in npcs.json")
            if kind == "monster" and thing.get("id") not in monsters:
                error(f"{where}: monster '{thing.get('id')}' is not in monsters.json")
            if kind == "portal":
                target = maps.get(thing.get("to"), {})
                if not target:
                    error(f"{where}: portal to unknown map '{thing.get('to')}'")
                elif thing.get("spawn", "default") not in target.get("spawns", {}):
                    error(f"{where}: portal to '{thing['to']}' names no spawn there")
                for spawn_name, point in spawns.items():
                    if isinstance(point, list) and len(point) == 2 and all(
                            is_number(v) for v in point) and math.dist(point, thing["pos"]) < 80:
                        error(f"{where}: spawn '{spawn_name}' is too close to a portal")


def check_art(items: dict) -> None:
    """The warrior's gear parts must name real items."""
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import generate_assets  # noqa: PLC0415 - needs Pillow, optional here
    except ImportError as exc:
        print(f"note: art not checked ({exc})")
        return
    requires = {}  # part -> items it needs, in any class
    for hero, info in generate_assets.HEROES.items():
        for item_id in info["gear"]:
            if item_id not in items:
                error(f"generate_assets.py: {hero} gear '{item_id}' is not an item")
        for part, needed in generate_assets.requires_for(hero).items():
            requires.setdefault(part, set()).update(needed)
    for part, needed in requires.items():
        for item_id in needed:
            if item_id not in items:
                error(f"generate_assets.py: part '{part}' needs unknown item '{item_id}'")
    variants = generate_assets.LOOK_VARIANTS
    for item_id, (base, _, parts, _) in variants.items():
        if items.get(item_id, {}).get("look") != base:
            error(f"generate_assets.py: '{item_id}' is drawn like '{base}', "
                  "but items.json does not give it that look")
        for part in parts:
            if base not in requires.get(part, set()):
                error(f"generate_assets.py: '{item_id}' recolours '{part}', not a part of '{base}'")
    for item_id, item in items.items():
        if "look" in item and item_id not in variants:
            error(f"items.json: '{item_id}' has a look but no recoloured art in LOOK_VARIANTS")


def main() -> int:
    items_data = load("items")
    items = check_items(items_data)
    check_items_cache.update(items)
    check_character(load("character"), items, items_data.get("gear_slots", []))
    check_monsters(load("monsters"), items)
    check_skills(load("skills"))
    check_classes(load("classes"), load("character"), items, load("skills"))
    dash = load("character").get("dash", {})
    for key in ("stamina", "cooldown", "seconds", "speed_multiplier"):
        need_number("character.json dash", dash, key, 0.01)
    combat = load("combat")
    need_number("combat.json", combat, "damage_spread", 0.0, 1.0)
    need_number("combat.json", combat, "crit_multiplier", 1.0)
    for key in ("combo_window_seconds", "combo_finisher_multiplier", "combo_finisher_knockback",
                "hit_stop_seconds", "crit_hit_stop_seconds"):
        need_number("combat.json", combat, key)
    elite = combat.get("elite", {})
    need_number("combat.json elite", elite, "chance", 0.0, 1.0)
    for key in ("hp", "damage", "xp", "gold", "scale"):
        need_number("combat.json elite", elite, key, 1.0)
    for drop in elite.get("extra_drops", []):
        if drop.get("item") not in check_items_cache:
            error(f"combat.json elite: drop '{drop.get('item')}' is not an item")
    check_progress(load("character"), items, load("skills"), load("monsters"),
                   load("achievements"))
    check_gear(items_data, load("monsters"), elite)
    check_npcs(load("npcs"), items_data.get("items", {}))
    check_quests(load("quests"), load("npcs"), items_data.get("items", {}), load("monsters"))
    check_maps(load("maps"), load("monsters"), load("npcs"))
    need_number("character.json", load("character"), "storage_size", 1, 200)
    need_number("items.json", items_data, "sell_fraction", 0.01, 1.0)
    for item_id, item in items_data.get("items", {}).items():
        need_number(f"items.json: '{item_id}'", item, "price", 0)
    check_art(items)
    if errors:
        print("DATA PROBLEMS:")
        for message in errors:
            print(" -", message)
        return 1
    print(f"OK: {len(items)} items, data files valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
