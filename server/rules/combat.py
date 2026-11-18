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


def hit_evasion(evasion: float, accuracy: float = 0.0) -> float:
    """The chance to miss: the target's evasion less the attacker's accuracy."""
    return min(max(evasion - accuracy, 0.0), float(settings().get("max_evasion", 0.75)))


def mitigate(damage: int, defense: int) -> int:
    """Damage after defense: never below the defense floor part of it, nor below 1."""
    floor = roundi(damage * float(settings().get("defense_floor", 0.0)))
    return max(1, damage - defense, floor)


def resolve_hit(
    base_damage: int, crit_chance: float, defense: int, evasion: float, rng: random.Random = random,
    crit_damage: float = 0.0, accuracy: float = 0.0,
) -> dict:
    """One attack on one target, the same as combat_rules.gd resolve_hit()."""
    if rng.random() < hit_evasion(evasion, accuracy):
        return {"damage": 0, "crit": False, "miss": True}
    damage = roll_damage(base_damage, rng)
    crit = rng.random() < crit_chance
    if crit:
        damage = roundi(damage * (float(settings()["crit_multiplier"]) + crit_damage))
    return {"damage": mitigate(damage, defense), "crit": crit, "miss": False}


def expected_damage(
    base_damage: int, crit_chance: float, defense: int, evasion: float, crit_damage: float = 0.0, accuracy: float = 0.0
) -> float:
    """What one hit does on average (misses, crits, spread and defense counted)."""
    spread = _spread(base_damage)
    multiplier = float(settings()["crit_multiplier"]) + crit_damage
    chance = min(max(crit_chance, 0.0), 1.0)
    rolls = [max(1, r) for r in range(base_damage - spread, base_damage + spread + 1)]
    total = sum(mitigate(r, defense) * (1 - chance) + mitigate(roundi(r * multiplier), defense) * chance for r in rolls)
    return total / len(rolls) * (1.0 - hit_evasion(evasion, accuracy))
