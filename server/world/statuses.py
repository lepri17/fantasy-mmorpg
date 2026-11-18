"""Timed effects on a hero or monster, like client/scripts/combat/status_effects.gd:
"poison" (value = damage per second), "slow" (value = how much slower, 0..1)
and "stun" (cannot move or act)."""

from __future__ import annotations


class Statuses:
    def __init__(self) -> None:
        self.effects: dict = {}  # name -> [seconds left, value]
        self._poison_carry = 0.0

    def apply(self, effect: str, seconds: float, value: float = 0.0) -> None:
        left, old_value = self.effects.get(effect, (0.0, 0.0))
        self.effects[effect] = [max(seconds, left), max(value, old_value)]

    def active(self, effect: str) -> bool:
        return effect in self.effects

    def speed_factor(self) -> float:
        if "slow" not in self.effects:
            return 1.0
        return min(max(1.0 - self.effects["slow"][1], 0.1), 1.0)

    def update(self, delta: float) -> int:
        """Counts down; returns the whole points of poison damage due now."""
        for effect in list(self.effects):
            entry = self.effects[effect]
            entry[0] -= delta
            if effect == "poison":
                self._poison_carry += entry[1] * delta
            if entry[0] <= 0.0:
                del self.effects[effect]
        damage = int(self._poison_carry)
        self._poison_carry -= damage
        return damage

    def clear(self) -> None:
        self.effects.clear()
        self._poison_carry = 0.0
