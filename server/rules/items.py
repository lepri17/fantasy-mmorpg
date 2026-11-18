"""Every item, from client/data/items.json: a port of client/scripts/items/item_db.gd.
Bag and worn entries are {"id", "count"}; gear also keeps "rarity", "plus"
(upgrade level) and "options" (random bonuses)."""

from __future__ import annotations

import math
import random

from ..data import roundi, snapped, table

# Bonuses written as fractions (0.03 = 3%); the rest are whole numbers.
PERCENT_STATS = ("crit_chance", "evasion", "skill_damage")


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


def roll_gear(item_id: str, rolls: int = 1, rng: random.Random = random) -> dict:
    """A dropped piece: a rarity by weight (rolled `rolls` times, the best kept),
    then that many different random options."""
    rarity = roll_rarity(rng)
    for _ in range(rolls - 1):
        other = roll_rarity(rng)
        if rarity_rank(other) > rarity_rank(rarity):
            rarity = other
    stats_left = list(random_options())
    rng.shuffle(stats_left)
    options = {}
    for stat in stats_left[: int(rarities()[rarity]["options"])]:
        low, high = (float(v) for v in random_options()[stat])
        if stat in PERCENT_STATS:
            options[stat] = snapped(rng.uniform(low, high), 0.005)
        else:
            options[stat] = rng.randint(int(low), int(high))
    return gear(item_id, rarity, 0, options)


def stat_of(stack: dict, stat: str) -> float:
    """One stat of one entry: the item's own value, its option and its upgrades."""
    item = items()[stack["id"]]
    total = float(item.get(stat, 0.0)) + float(stack.get("options", {}).get(stat, 0.0))
    plus = int(stack.get("plus", 0))
    if plus > 0:
        per_plus = upgrades().get("per_plus", {}).get(item.get("slot", ""), {})
        total += plus * float(per_plus.get(stat, 0.0))
    return total


def upgrade_step(stack: dict) -> dict:
    """The rule for the next level of a piece, or {} when it cannot go higher."""
    plus = int(stack.get("plus", 0))
    if not is_gear(stack.get("id", "")) or plus >= int(upgrades().get("max_plus", 0)):
        return {}
    for step in upgrades().get("steps", []):
        if plus < int(step["up_to"]):
            return step
    return {}


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
    return gear(item_id, rarity, plus, options)


def _int(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0
