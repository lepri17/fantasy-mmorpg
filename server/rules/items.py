"""Every item, from client/data/items.json: a port of client/scripts/items/item_db.gd.
Bag and worn entries are {"id", "count"}; gear also keeps "rarity", "plus"
(upgrade level) and "options" (random bonuses)."""

from __future__ import annotations

import math
import random

from ..data import roundi, snapped, table

# Bonuses written as fractions (0.03 = 3%); the rest are whole numbers.
PERCENT_STATS = ("crit_chance", "crit_damage", "evasion", "accuracy", "attack_speed", "skill_damage")
MAX_MISSES = 20  # misses kept on a piece (item_db.gd MAX_MISSES)


def data() -> dict:
    return table("items")


def items() -> dict:
    return data()["items"]


def rarities() -> dict:
    return data()["rarities"]


def random_options() -> dict:
    return data()["random_options"]


def upgrades() -> dict:
    return data().get("upgrades", {})


def sets() -> dict:
    return data().get("sets", {})


def exists(item_id: str) -> bool:
    return item_id in items()


def price(item_id: str) -> int:
    return int(items()[item_id].get("price", 0))


def is_gear(item_id: str) -> bool:
    return item_id in items() and items()[item_id].get("slot", "") != ""


def usable_by(item_id: str, class_id: str) -> bool:
    classes = items().get(item_id, {}).get("classes", [])
    return not classes or class_id in classes


def required_level(item_id: str) -> int:
    """The level a hero needs to wear the item (items.json "level"; 1 when not set)."""
    return max(1, int(items().get(item_id, {}).get("level", 1)))


def can_wear(item_id: str, class_id: str, level: int) -> bool:
    return is_gear(item_id) and usable_by(item_id, class_id) and level >= required_level(item_id)


def rarity_rank(rarity: str) -> int:
    keys = list(rarities())
    return keys.index(rarity) if rarity in keys else -1


def sell_price(stack: dict) -> int:
    """What a shop pays for one of this entry; more for rarer and upgraded gear."""
    value = price(stack["id"]) * float(data().get("sell_fraction", 0.25))
    if is_gear(stack["id"]):
        value *= 1.0 + rarity_rank(stack.get("rarity", "")) * 0.75
        value += int(stack.get("plus", 0)) * 10
    return max(1, math.floor(value))


def sorted_bag(bag: list, class_id: str) -> list:
    """The bag in a tidy order (item_db.gd sorted_bag): gear this class can wear
    by slot, then the highest level, rarity and upgrade; other gear; things to
    use; the rest. Entries that tie keep their order."""
    keyed = sorted(enumerate(bag), key=lambda pair: (_sort_key(pair[1], class_id), pair[0]))
    return [stack for _, stack in keyed]


def _sort_key(stack: dict, class_id: str) -> int:
    item_id = stack["id"]
    item = items()[item_id]
    if is_gear(item_id):
        group = 0 if usable_by(item_id, class_id) else 1
        return (
            group * 10_000_000
            + data()["gear_slots"].index(item["slot"]) * 100_000
            + (99 - required_level(item_id)) * 1000
            + (9 - rarity_rank(stack.get("rarity", ""))) * 100
            + (99 - int(stack.get("plus", 0)))
        )
    group = 2 if item.get("usable", False) else 3
    return group * 10_000_000 + list(items()).index(item_id)


def gear(item_id: str, rarity: str = "common", plus: int = 0, options: dict | None = None) -> dict:
    return {"id": item_id, "count": 1, "rarity": rarity, "plus": plus, "options": dict(options or {})}


def roll_rarity(rng: random.Random = random) -> str:
    table_ = rarities()
    roll = rng.random() * sum(float(r["weight"]) for r in table_.values())
    for rarity, info in table_.items():
        roll -= float(info["weight"])
        if roll < 0.0:
            return rarity
    return next(iter(table_))


def roll_gear(item_id: str, rolls: int = 1, rng: random.Random = random, min_rarity: str = "") -> dict:
    """A dropped piece: a rarity by weight (rolled `rolls` times, the best kept,
    never below min_rarity), then that many different random options, each in
    its option_range (item_db.gd roll_gear)."""
    rarity = roll_rarity(rng)
    for _ in range(rolls - 1):
        other = roll_rarity(rng)
        if rarity_rank(other) > rarity_rank(rarity):
            rarity = other
    if rarity_rank(min_rarity) > rarity_rank(rarity):
        rarity = min_rarity
    stats_left = list(random_options())
    rng.shuffle(stats_left)
    options = {}
    for stat in stats_left[: int(rarities()[rarity]["options"])]:
        low, high = option_range(stat, item_id, rarity)
        if stat in PERCENT_STATS:
            options[stat] = snapped(rng.uniform(low, high), 0.005)
        else:
            options[stat] = rng.randint(int(low), int(high))
    return gear(item_id, rarity, 0, options)


def option_range(stat: str, item_id: str, rarity: str) -> tuple[float, float]:
    """What a random option can roll on this piece: the range grown with the
    piece's level, starting higher for rarer pieces (item_db.gd option_range)."""
    growth = data().get("option_growth", {})
    per_level = float(growth.get("percent" if stat in PERCENT_STATS else "whole", 0.0))
    grown = 1.0 + (required_level(item_id) - 1) * per_level
    low = float(random_options()[stat][0]) * grown
    high = float(random_options()[stat][1]) * grown
    low += (high - low) * float(rarities().get(rarity, {}).get("roll_floor", 0.0))
    if stat in PERCENT_STATS:
        return snapped(low, 0.005), snapped(high, 0.005)
    return float(roundi(low)), float(roundi(high))


def drop_pool(monster_level: int) -> list:
    """The gear a monster of this level can drop (item_db.gd drop_pool)."""
    below, above = data().get("drop_levels", [-6, 2])
    return [
        item_id for item_id, item in items().items()
        if is_gear(item_id) and not item.get("no_drop", False)
        and monster_level + below <= required_level(item_id) <= monster_level + above
    ]


def stat_of(stack: dict, stat: str) -> float:
    """One stat of one entry: the item's own value, its option and its upgrades."""
    item = items()[stack["id"]]
    total = float(item.get(stat, 0.0)) + float(stack.get("options", {}).get(stat, 0.0))
    plus = int(stack.get("plus", 0))
    if plus > 0:
        per_plus = upgrades().get("per_plus", {}).get(item.get("slot", ""), {})
        total += plus * float(per_plus.get(stat, 0.0)) * upgrade_growth(stack["id"])
    return total


def upgrade_growth(item_id: str) -> float:
    """Each + is worth more on higher-level gear (item_db.gd upgrade_growth)."""
    return 1.0 + float(upgrades().get("per_plus_growth", 0.0)) * (required_level(item_id) - 1)


def upgrade_step(stack: dict) -> dict:
    """The next + of a piece, or {} at the top: plus, cost (gold), chance (with
    the bonus its misses earned), misses, the stone that can be added ("" when
    the chance is sure) and stone_bonus (item_db.gd upgrade_step)."""
    plus = int(stack.get("plus", 0))
    if not is_gear(stack.get("id", "")) or plus >= int(upgrades().get("max_plus", 0)):
        return {}
    chances = upgrades().get("chances", [1.0])
    misses = int(stack.get("misses", 0))
    chance = min(1.0, float(chances[min(plus, len(chances) - 1)]) + misses * float(upgrades().get("miss_bonus", 0.0)))
    stone = ""
    if chance < 1.0:
        for rule in upgrades().get("stones", []):
            if plus < int(rule["up_to"]):
                stone = rule["stone"]
                break
    return {
        "plus": plus + 1, "cost": upgrade_cost(stack), "chance": chance, "misses": misses,
        "stone": stone, "stone_bonus": float(upgrades().get("stone_bonus", 0.0)),
    }


def upgrade_cost(stack: dict) -> int:
    """Gold for a piece's next +, rounded to 5 (item_db.gd upgrade_cost)."""
    rule = upgrades().get("gold", {})
    level_part = 1.0 + float(rule.get("per_item_level", 0.0)) * (required_level(stack["id"]) - 1)
    growth = math.pow(float(rule.get("growth", 1.0)), int(stack.get("plus", 0)))
    return roundi(float(rule.get("base", 0.0)) * level_part * growth / 5.0) * 5


def display_name(stack: dict, with_rarity: bool = False) -> str:
    """"Training Sword +3"; "Rare Training Sword +3" with_rarity, above common."""
    text = items()[stack["id"]]["name"]
    plus = int(stack.get("plus", 0))
    if plus > 0:
        text += f" +{plus}"
    if with_rarity and rarity_rank(stack.get("rarity", "")) > 0:
        text = f"{rarities()[stack['rarity']]['name']} {text}"
    return text


def clean_stack(stack) -> dict:
    """A safe copy of a saved, sent or dropped entry, or {} for an unknown item."""
    if not isinstance(stack, dict) or stack.get("id", "") not in items():
        return {}
    item_id = stack["id"]
    if not is_gear(item_id):
        return {"id": item_id, "count": max(1, _int(stack.get("count", 1)))}
    rarity = str(stack.get("rarity", ""))
    if rarity not in rarities():
        rarity = next(iter(rarities()))
    options = {}
    saved = stack.get("options", {})
    if isinstance(saved, dict):
        for stat, value in saved.items():
            if stat in random_options():
                options[stat] = float(value) if stat in PERCENT_STATS else roundi(float(value))
    plus = min(max(_int(stack.get("plus", 0)), 0), int(upgrades().get("max_plus", 15)))
    entry = gear(item_id, rarity, plus, options)
    misses = min(max(_int(stack.get("misses", 0)), 0), MAX_MISSES)
    if misses > 0:
        entry["misses"] = misses  # upgrade tries missed since its last +
    return entry


def _int(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0
