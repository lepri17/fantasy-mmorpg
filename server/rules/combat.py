"""Combat math: the same rules as client/scripts/combat/combat_rules.gd."""

from __future__ import annotations

import random

from ..data import roundi, table


def settings() -> dict:
    return table("combat")


def _spread(base_damage: int) -> int:
    return max(1, roundi(base_damage * float(settings()["damage_spread"])))


def roll_damage(base_damage: int, rng: random.Random = random) -> int:
    """The base value plus or minus a small random spread. Never below 1."""
    spread = _spread(base_damage)
    return max(1, base_damage + rng.randint(-spread, spread))


def damage_range(base_damage: int) -> tuple[int, int]:
    spread = _spread(base_damage)
    return max(1, base_damage - spread), max(1, base_damage + spread)


def resolve_hit(
    base_damage: int, crit_chance: float, defense: int, evasion: float, rng: random.Random = random
) -> dict:
    """One attack on one target: a miss (its evasion), or the rolled damage,
    times the crit multiplier on a critical hit, minus its defense, at least 1."""
    if rng.random() < evasion:
        return {"damage": 0, "crit": False, "miss": True}
    damage = roll_damage(base_damage, rng)
    crit = rng.random() < crit_chance
    if crit:
        damage = roundi(damage * float(settings()["crit_multiplier"]))
    return {"damage": max(1, damage - defense), "crit": crit, "miss": False}
