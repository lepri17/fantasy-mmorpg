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
        for key in ("attack", "max_hp", "defense", "max_stamina"):
            if key in item:
                value = need_number(where, item, key)
                if value is not None and value != int(value):
                    error(f"{where}: '{key}' must be a whole number")
        for key in ("crit_chance", "crit_damage", "evasion", "accuracy", "attack_speed", "skill_damage"):
            if key in item:
                need_number(where, item, key, 0.0, 1.0)
        if "level" in item:
            if slot == "":
                error(f"{where}: only gear has a 'level'")
            value = need_number(where, item, "level", 1, 99)
            if value is not None and value != int(value):
                error(f"{where}: 'level' must be a whole number")
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
    playable = classes.get("playable", [])
    if not playable or any(class_id not in table for class_id in playable):
        error(f"{where}: 'playable' must name classes from 'classes'")
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
        look_item = items.get(advanced.get("item"), {})
        if not look_item or class_id not in look_item.get("classes", [class_id]):
            error(f"{place}: the advancement item '{advanced.get('item')}' is not gear for it")
        check_bonus(f"{place} advanced", advanced.get("bonus", {}))
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
    for key in ("base_max_hp", "base_damage", "move_speed", "attack_range",
                "attack_cooldown", "max_stamina", "bag_size", "respawn_seconds"):
        need_number(where, character, key, 0.01)
    curve = character.get("xp_curve", {})
    need_number(f"{where} xp_curve", curve, "base", 1.0)
    need_number(f"{where} xp_curve", curve, "exponent", 1.0, 4.0)
    gap = character.get("xp_level_gap", {})
    for key in ("free_levels", "loss_per_level", "gain_per_level"):
        need_number(f"{where} xp_level_gap", gap, key)
    need_number(f"{where} xp_level_gap", gap, "lowest", 0.0, 1.0)
    need_number(f"{where} xp_level_gap", gap, "highest", 1.0, 3.0)
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
        for move, keys in MONSTER_MOVES.items():
            if move in monster:
                for key in keys:
                    need_number(f"{where} {move}", monster[move], key, 0.01)
        if "shell" in monster:
            need_number(f"{where} shell", monster["shell"], "damage_taken", 0.01, 1.0)
        split = monster.get("split")
        if split is not None:
            into = split.get("into")
            if into not in monsters or into == monster_id or "split" in monsters.get(into, {}):
                error(f"{where}: split 'into' must be another monster that does not split")
            need_number(where + " split", split, "count", 1, 6)
        if "hover" in monster:
            need_number(where, monster, "hover", 0, 30)
        if "knockback_resist" in monster:
            need_number(where, monster, "knockback_resist", 0.0, 1.0)


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
              "skill_damage", "crit_damage",
              "accuracy", "attack_speed"}
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
    for key in ("stat_points_per_level", "stat_reset_gold_per_level", "stat_reset_free_below_level"):
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


def check_gear(items_data: dict, monsters: dict, elite: dict, classes_data: dict) -> None:
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
        need_number(where, rarity, "roll_floor", 0.0, 0.95)
        need_number(where, rarity, "ground_seconds", 10, 600)
    growth = items_data.get("option_growth", {})
    for key in ("whole", "percent"):
        need_number("items.json option_growth", growth, key, 0.0, 1.0)
    window = items_data.get("drop_levels")
    if not (isinstance(window, list) and len(window) == 2 and all(isinstance(v, int) for v in window)
            and window[0] <= 0 <= window[1]):
        error("items.json: 'drop_levels' must be [below, above] whole numbers round 0, such as [-6, 2]")
        window = [-6, 2]
    for stat, span in items_data.get("random_options", {}).items():
        if stat not in BONUS_KEYS:
            error(f"items.json: random option '{stat}' is not one of {sorted(BONUS_KEYS)}")
        if not (isinstance(span, list) and len(span) == 2 and all(is_number(v) for v in span)
                and 0 < span[0] <= span[1]):
            error(f"items.json: random option '{stat}' must be [low, high] with 0 < low <= high")
    gear = {i: item for i, item in items_data.get("items", {}).items() if item.get("slot")}
    for item_id, item in gear.items():
        if not isinstance(item.get("no_drop", False), bool):
            error(f"items.json: '{item_id}' 'no_drop' must be true or false")
    playable = classes_data.get("playable", [])
    for monster_id, monster in monsters.items():
        table = monster.get("gear_drops")
        if table is None:
            continue
        where = f"monsters.json: '{monster_id}' gear_drops"
        need_number(where, table, "chance", 0.0, 1.0)
        for item_id in table.get("items", []):  # an optional hand-picked pool instead of the level's
            if item_id not in gear:
                error(f"{where}: '{item_id}' is not gear")
        level = int(monster.get("level", 1))
        pool = [i for i, item in gear.items() if not item.get("no_drop", False)
                and level + window[0] <= int(item.get("level", 1)) <= level + window[1]]
        for class_id in [] if "items" in table else playable:  # else from its level (item_db.gd drop_pool)
            if not any(class_id in gear[i].get("classes", [class_id]) for i in pool):
                error(f"{where}: no gear of levels {level + window[0]}..{level + window[1]} for {class_id}")
        boss = monster.get("boss", {})
        if "gear_count" in boss:
            need_number(where + " boss", boss, "gear_count", 1, 6)
        if "min_rarity" in boss and boss["min_rarity"] not in rarities:
            error(f"{where}: boss min_rarity '{boss['min_rarity']}' is not a rarity")
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
    """M5 upgrades for gold: the cost, the chance of each +, the bonus a miss
    adds, the stones that add more, and what each + adds."""
    upgrades = items_data.get("upgrades", {})
    where = "items.json upgrades"
    max_plus = need_number(where, upgrades, "max_plus", 1, 99)
    items = items_data.get("items", {})
    gold = upgrades.get("gold", {})
    need_number(where + " gold", gold, "base", 1, 100000)
    need_number(where + " gold", gold, "growth", 1.0, 3.0)
    need_number(where + " gold", gold, "per_item_level", 0.0, 5.0)
    chances = upgrades.get("chances")
    if not (isinstance(chances, list) and len(chances) == max_plus
            and all(is_number(c) and 0.01 <= c <= 1.0 for c in chances)):
        error(f"{where}: 'chances' must list {max_plus} chances from 0.01 to 1, one for each +")
    elif any(later > earlier for earlier, later in zip(chances, chances[1:], strict=False)):
        error(f"{where}: 'chances' must not grow with the +")
    need_number(where, upgrades, "miss_bonus", 0.0, 1.0)
    need_number(where, upgrades, "stone_bonus", 0.0, 1.0)
    need_number(where, upgrades, "per_plus_growth", 0.0, 1.0)
    last = 0
    for rule in upgrades.get("stones", []):
        up_to = need_number(where + " stones", rule, "up_to", last + 1, max_plus)
        last = up_to if up_to is not None else last
        if not items.get(rule.get("stone"), {}).get("upgrade_stone"):
            error(f"{where}: stone '{rule.get('stone')}' is not an item with \"upgrade_stone\"")
    if max_plus is not None and last != max_plus:
        error(f"{where}: the last stone rule must reach max_plus ({max_plus})")
    for slot, bonus in upgrades.get("per_plus", {}).items():
        if slot not in items_data.get("gear_slots", []):
            error(f"{where}: per_plus slot '{slot}' is not a gear slot")
        check_bonus(f"{where} per_plus '{slot}'", bonus)


OBJECT_TYPES = {"tree", "rock", "monster", "portal", "npc", "torch", "glowcap", "decor", "chest",
                "shrine"}
GLOW_COLORS = {"cyan", "teal", "violet"}
DECOR_KINDS = {"reeds", "cattails", "lily", "flowers", "pebbles", "log", "mushrooms", "bones",
               "crystals"}  # decor.gd
WATER_STYLES = {"water", "chasm"}  # water.gd
CLIFF_HEIGHT = 56  # cliff.gd HEIGHT: the rock face below a cliff's top
SHRINE_GIFTS = {"heal", "power"}  # shrine.gd
# A monster's extra moves (slime.gd) and the numbers each needs.
MONSTER_MOVES = {
    "charge": ("range", "min_range", "warning_seconds", "speed", "distance", "damage_multiplier", "cooldown"),
    "blink": ("when_closer", "distance", "cooldown"),
    "burrow": ("cooldown", "seconds", "speed", "radius", "warning_seconds", "damage_multiplier"),
    "special": ("every", "radius", "warning_seconds", "damage_multiplier"),
    # monster_moves.gd: the open world's moves.
    "shell": ("range", "seconds", "damage_taken", "cooldown", "radius", "warning_seconds",
              "damage_multiplier"),
    "leap": ("range", "min_range", "warning_seconds", "air_seconds", "height", "radius",
             "damage_multiplier", "cooldown"),
    "roll": ("range", "seconds", "speed", "damage_multiplier", "damage_taken", "cooldown"),
    "lob": ("range", "min_range", "flight_seconds", "radius", "damage_multiplier", "cooldown"),
}
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
        if not isinstance(reward.get("advance", False), bool):
            error(f"{where}: reward 'advance' must be true or false")
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
    for map_id, data in maps.items():
        for monster_id in data.get("monsters", []):
            if monster_id not in monsters:
                error(f"maps.json: '{map_id}' lists unknown monster '{monster_id}'")
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
        shade = data.get("shade", [1, 1, 1])
        if not (isinstance(shade, list) and len(shade) == 3 and all(is_number(v) and 0.2 <= v <= 1.0
                                                                     for v in shade)):
            error(f"{where}: 'shade' must be three numbers from 0.2 to 1")
        if "fireflies" in data:
            need_number(where, data, "fireflies", 0, 200)
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
        waters = [w for w in data.get("objects", []) if w.get("type") == "water"]
        cliffs = [cliff_block(c["points"]) for c in data.get("objects", [])
                  if c.get("type") == "cliff" and len(c.get("points", [])) >= 3]
        for spawn_name, point in spawns.items():
            if isinstance(point, list) and len(point) == 2 and any(in_polygon(point, c) for c in cliffs):
                error(f"{where}: spawn '{spawn_name}' is in a cliff")
        for thing in data.get("objects", []):
            kind = thing.get("type")
            if kind == "exit":
                check_exit(where, map_id, thing, size, maps, spawns)
                continue
            if kind == "water":
                check_water(where, thing, inside, spawns)
                continue
            if kind == "cliff":
                top = thing.get("points", [])
                if not (isinstance(top, list) and len(top) >= 3
                        and all(inside(point, "cliff point") for point in top)):
                    error(f"{where}: a cliff needs at least three 'points' on the map")
                continue
            if kind not in OBJECT_TYPES:
                error(f"{where}: object type '{kind}' is not one of {sorted(OBJECT_TYPES)}")
                continue
            if not inside(thing.get("pos"), kind):
                continue
            if "tint" in thing and not (isinstance(thing["tint"], list) and len(thing["tint"]) == 4
                                        and all(map(is_number, thing["tint"]))):
                error(f"{where}: {kind} 'tint' must be four numbers")
            if "scale" in thing:
                need_number(f"{where} {kind}", thing, "scale", 0.5, 2.5)
            if kind != "decor" and any(is_wet(thing["pos"], w) for w in waters):
                error(f"{where}: {kind} at {thing['pos']} is in the water")
            if any(in_polygon(thing["pos"], c) for c in cliffs):
                error(f"{where}: {kind} at {thing['pos']} is in a cliff")
            if kind == "glowcap" and thing.get("color") not in GLOW_COLORS:
                error(f"{where}: glowcap color must be one of {sorted(GLOW_COLORS)}")
            if kind == "decor" and thing.get("kind") not in DECOR_KINDS:
                error(f"{where}: decor kind must be one of {sorted(DECOR_KINDS)}")
            if kind == "chest":
                need_number(f"{where} chest", thing, "level", 1, 999)
            if kind == "shrine" and thing.get("gift", "heal") not in SHRINE_GIFTS:
                error(f"{where}: shrine gift must be one of {sorted(SHRINE_GIFTS)}")
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


def check_water(where: str, water: dict, inside, spawns: dict) -> None:
    """A lake or river (water.gd): a shore of points on the map, islands in it,
    bridges as [x, y, width, height] boxes with both ends on dry land (or an
    island), and no spawn in the water."""
    points = water.get("points", [])
    if water.get("style", "water") not in WATER_STYLES:
        error(f"{where}: water style must be one of {sorted(WATER_STYLES)}")
    if not (isinstance(points, list) and len(points) >= 3):
        error(f"{where}: water needs at least three shore 'points'")
        return
    if not all(inside(point, "water point") for point in points):
        return
    islands = []
    for island in water.get("islands", []):
        if not (isinstance(island, list) and len(island) >= 3
                and all(inside(point, "island point") for point in island)):
            error(f"{where}: an island needs at least three points on the map")
            continue
        if not all(in_polygon(point, points) for point in island):
            error(f"{where}: an island must be in its water")
        islands.append(island)

    def wet(point, bridges=()):
        if any(b[0] <= point[0] <= b[0] + b[2] and b[1] <= point[1] <= b[1] + b[3] for b in bridges):
            return False
        return in_polygon(point, points) and not any(in_polygon(point, i) for i in islands)

    bridges, reached = [], []
    for box in water.get("bridges", []):
        if not (isinstance(box, list) and len(box) == 4 and all(is_number(v) for v in box)
                and box[2] >= 64 and box[3] >= 64 and inside(box[:2], "bridge corner")
                and inside([box[0] + box[2], box[1] + box[3]], "bridge corner")):
            error(f"{where}: a bridge must be [x, y, width, height] on the map, 64 or more wide")
            continue
        x, y, w, h = box
        ends = ([(x + 4, y + h / 2), (x + w - 4, y + h / 2)] if w >= h
                else [(x + w / 2, y + 4), (x + w / 2, y + h - 4)])
        if any(wet(end) for end in ends):
            error(f"{where}: bridge {box} must reach dry land at both ends")
        bridges.append(box)
        for island in islands:
            if any(in_polygon(end, island) for end in ends):
                reached.append(island)
    if any(island not in reached for island in islands):
        error(f"{where}: each island needs a bridge to it (else it is a hole in the water)")
    for spawn_name, point in spawns.items():
        if (isinstance(point, list) and len(point) == 2 and all(is_number(v) for v in point)
                and wet(point, bridges)):
            error(f"{where}: spawn '{spawn_name}' is in the water")


def cliff_block(top: list) -> list:
    """Roughly the ground a cliff stands on (cliff.gd block): its top, stretched
    down by the rock face (the top's outline, with its lowest points moved down)."""
    middle = sum(p[1] for p in top) / len(top)
    return [[x, y + CLIFF_HEIGHT if y >= middle else y] for x, y in top]


def is_wet(point, water: dict) -> bool:
    """Is a point in this water: not on one of its bridges or islands?"""
    for box in water.get("bridges", []):
        if box[0] <= point[0] <= box[0] + box[2] and box[1] <= point[1] <= box[1] + box[3]:
            return False
    if any(in_polygon(point, island) for island in water.get("islands", [])):
        return False
    return in_polygon(point, water.get("points", []))


def in_polygon(point, polygon) -> bool:
    """Is a point inside a shape (even-odd rule)?"""
    x, y = point
    inside_ = False
    for (x1, y1), (x2, y2) in zip(polygon, polygon[1:] + polygon[:1]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside_ = not inside_
    return inside_


EXIT_SIDES = {"north", "south", "east", "west"}
EXIT_DEPTH = 64  # client/scripts/maps/edge_exit.gd DEPTH
EXIT_WALLS = (24, 80, 24, 20)  # edge_exit.gd WALLS: left, top, right, bottom


def check_exit(where: str, map_id: str, exit_: dict, size: tuple, maps: dict, spawns: dict) -> None:
    """A road at a map's edge into the next map (edge_exit.gd): a side, a span
    along that edge, a map and spawn to arrive at, and no spawn inside it (the
    hero would be sent straight back)."""
    side, span = exit_.get("side"), exit_.get("span")
    if side not in EXIT_SIDES:
        error(f"{where}: exit side must be one of {sorted(EXIT_SIDES)}")
        return
    along = size[1] if side in ("east", "west") else size[0]
    if not (isinstance(span, list) and len(span) == 2 and all(is_number(v) for v in span)
            and 0 <= span[0] < span[1] <= along and span[1] - span[0] >= 96):
        error(f"{where}: {side} exit 'span' must be [from, to] on that edge, at least 96 wide")
        return
    target = maps.get(exit_.get("to"), {})
    if not target:
        error(f"{where}: exit to unknown map '{exit_.get('to')}'")
    elif exit_.get("spawn", "default") not in target.get("spawns", {}):
        error(f"{where}: exit to '{exit_['to']}' names no spawn there")
    else:
        if not any(e.get("type") == "exit" and e.get("to") == map_id for e in target.get("objects", [])):
            error(f"{where}: the road to '{exit_['to']}' has no road back from there")
    reach = EXIT_DEPTH + 40  # the trigger, and a hero's body beside it
    if side == "west":
        box = (0, span[0], EXIT_WALLS[0] + reach, span[1])
    elif side == "east":
        box = (size[0] - EXIT_WALLS[2] - reach, span[0], size[0], span[1])
    elif side == "north":
        box = (span[0], 0, span[1], EXIT_WALLS[1] + reach)
    else:
        box = (span[0], size[1] - EXIT_WALLS[3] - reach, span[1], size[1])
    for spawn_name, point in spawns.items():
        if (isinstance(point, list) and len(point) == 2 and box[0] <= point[0] <= box[2]
                and box[1] <= point[1] <= box[3]):
            error(f"{where}: spawn '{spawn_name}' is inside the {side} road out")


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
    check_gear(items_data, load("monsters"), elite, load("classes"))
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
