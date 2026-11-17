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
    "buff": ("seconds", "damage_bonus"),
    "slam": ("radius", "damage_multiplier", "stun_seconds"),
}
SKILL_ACTIONS = {"skill", "skill_2", "skill_3", "skill_4"}


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
        elif action in used_actions:
            error(f"{where}: action '{action}' is used by two skills")
        used_actions.add(action)
        for key in ("stamina", "cooldown"):
            need_number(where, skill, key)
        need_number(where, skill, "unlock_level", 1)
        kind = skill.get("type")
        if kind not in SKILL_TYPES:
            error(f"{where}: type '{kind}' is not one of {sorted(SKILL_TYPES)}")
            continue
        for key in SKILL_TYPES[kind]:
            need_number(where, skill, key)


def check_art(items: dict) -> None:
    """The warrior's gear parts must name real items."""
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import generate_assets  # noqa: PLC0415 - needs Pillow, optional here
    except ImportError as exc:
        print(f"note: art not checked ({exc})")
        return
    for part, needed in generate_assets.PART_REQUIRES.items():
        for item_id in needed:
            if item_id not in items:
                error(f"generate_assets.py: part '{part}' needs unknown item '{item_id}'")


def main() -> int:
    items_data = load("items")
    items = check_items(items_data)
    check_items_cache.update(items)
    check_character(load("character"), items, items_data.get("gear_slots", []))
    check_monsters(load("monsters"), items)
    check_skills(load("skills"))
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
