"""The ported rules give the same numbers as the client."""

import random

from server.data import roundi, scene_objects
from server.rules import combat, items
from server.rules.stats import Stats


def test_godot_rounding():
    assert [roundi(v) for v in (0.5, 1.5, 2.5, -0.5, -1.5, 2.4)] == [1, 2, 3, -1, -2, 2]


def test_new_warrior_numbers():
    hero = Stats("warrior")
    assert hero.max_hp() == 100 and hero.attack_damage() == 10
    assert hero.potions == 2 and len(hero.equipment) == 6


def test_levels_and_stat_points():
    hero = Stats("archer")
    assert hero.add_xp(50) == 1 and hero.level == 2 and hero.xp == 0
    assert hero.free_points() == 5
    assert hero.add_stat_point("vitality") and hero.max_hp() == Stats("archer").max_hp() + 17 + 3
    hero.gold = 100
    assert hero.reset_stats(True) and hero.gold == 60 and hero.free_points() == 5
    assert hero.total_xp() == 50


def test_bag_equip_and_save_round_trip():
    hero = Stats("warrior")
    hero.add_stack(items.gear("training_sword", "rare", 3, {"attack": 2}))
    assert hero.equip(1) and hero.equipment["weapon"]["plus"] == 3
    assert hero.attack_damage() == 10 + 2 + 3 * 2
    copy = Stats()
    copy.from_dict(hero.to_dict())
    assert copy.to_dict() == hero.to_dict()
    assert not hero.equip(0)  # potions are not gear


def test_other_class_gear_is_refused():
    hero = Stats("archer")
    hero.add_item("training_sword")
    index = len(hero.bag) - 1
    assert not hero.equip(index)


def test_resolve_hit_and_gear_rolls_are_in_range():
    rng = random.Random(4)
    low, high = combat.damage_range(10)
    for _ in range(200):
        hit = combat.resolve_hit(10, 0.0, 0, 0.0, rng)
        assert low <= hit["damage"] <= high and not hit["crit"]
    piece = items.roll_gear("training_sword", 3, rng)
    assert items.clean_stack(piece) == piece


def test_meadow_scene_objects():
    things = scene_objects("res://scenes/maps/field.tscn")
    kinds = {t["type"] for t in things}
    assert kinds == {"tree", "rock", "monster"}
    assert any(t.get("id") == "blue_slime" for t in things)


def test_same_numbers_as_godot():
    """fixtures/godot_stats.json comes from client/tests/stats_fixture.gd."""
    import json
    import math
    from pathlib import Path

    def norm(value):
        if isinstance(value, dict):
            return {k: norm(v) for k, v in value.items()}
        if isinstance(value, list):
            return [norm(v) for v in value]
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return float(value)
        return value

    cases = json.loads((Path(__file__).parent / "fixtures" / "godot_stats.json").read_text())
    assert len(cases) == 12
    for case in cases:
        hero = Stats()
        hero.from_dict(case["dict"])
        mine = {
            "max_hp": hero.max_hp(), "attack": hero.attack_damage(), "defense": hero.defense(),
            "crit": hero.crit_chance(), "evasion": hero.evasion(), "stamina": hero.max_stamina(),
            "skill": hero.skill_damage_bonus(), "free": hero.free_points(),
            "crit_damage": hero.total("crit_damage"), "accuracy": hero.total("accuracy"),
            "attack_speed": hero.total("attack_speed"),
        }
        for key, value in mine.items():
            assert math.isclose(float(value), float(case[key]), abs_tol=1e-9), (case["class"], key)
        assert norm(hero.to_dict()) == norm(case["dict"])
