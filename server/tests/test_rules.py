"""The ported rules give the same numbers as the client."""

import random

from server.data import roundi, table
from server.rules import combat, items
from server.rules.stats import Stats, kill_xp, level_gap_factor, xp_for_level


def test_godot_rounding():
    assert [roundi(v) for v in (0.5, 1.5, 2.5, -0.5, -1.5, 2.4)] == [1, 2, 3, -1, -2, 2]


def test_new_warrior_numbers():
    hero = Stats("warrior")
    assert hero.max_hp() == 100 and hero.attack_damage() == 10
    assert hero.potions == 2 and len(hero.equipment) == 6


def test_levels_and_stat_points():
    hero = Stats("archer")
    first = xp_for_level(1)
    assert hero.add_xp(first) == 1 and hero.level == 2 and hero.xp == 0
    assert hero.total_xp() == first and hero.free_points() == 5
    assert hero.add_stat_point("vitality") and hero.max_hp() == Stats("archer").max_hp() + 13 + 5
    assert hero.reset_cost() == 0 and hero.reset_stats(True) and hero.free_points() == 5
    hero.level, hero.gold = 10, 250
    assert hero.add_stat_point("dexterity") and hero.reset_cost() == 200
    assert hero.reset_stats(True) and hero.gold == 50


def test_gear_needs_a_level():
    hero = Stats()
    hero.bag = [items.gear("verdant_headband")]
    assert items.required_level("verdant_headband") == 3
    assert not hero.equip(0) and len(hero.bag) == 1
    hero.level = 3
    assert hero.equip(0) and hero.equipment["head"]["id"] == "verdant_headband"


def test_xp_curve_and_level_gap():
    needs = [xp_for_level(level) for level in range(1, 41)]
    assert all(a < b for a, b in zip(needs, needs[1:], strict=False))
    assert level_gap_factor(5, 5) == level_gap_factor(7, 5) == 1.0
    assert level_gap_factor(8, 5) < 1.0 and level_gap_factor(60, 1) == 0.1
    assert level_gap_factor(1, 3) > 1.0 and level_gap_factor(1, 60) == 1.25
    assert kill_xp(20, 1, 1) == 20 and kill_xp(1, 60, 1) == 1


def test_old_save_gets_its_stat_points_back():
    hero = Stats()
    hero.from_dict({"version": 10, "class": "archer", "level": 3, "stat_points": {"agility": 4, "strength": 3}})
    assert hero.stat_points == {} and hero.free_points() == 10 and hero.notice
    hero.from_dict({"version": 11, "class": "archer", "level": 3, "stat_points": {"dexterity": 2, "agility": 1}})
    assert hero.stat_points == {"dexterity": 3} and hero.notice == ""


def test_bag_equip_and_save_round_trip():
    hero = Stats("warrior")
    hero.add_stack(items.gear("training_sword", "rare", 3, {"attack": 2}))
    assert hero.equip(1) and hero.equipment["weapon"]["plus"] == 3
    per_plus = items.upgrades()["per_plus"]["weapon"]["attack"] * items.upgrade_growth("training_sword")
    assert hero.attack_damage() == roundi(10 + 2 + 3 * per_plus)
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


def test_meadow_objects():
    """Green Meadow is built from maps.json like every map (since 2026-11-20)."""
    things = table("maps")["maps"]["field"]["objects"]
    kinds = {t["type"] for t in things}
    assert {"tree", "rock", "monster"} <= kinds
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

    fixture = json.loads((Path(__file__).parent / "fixtures" / "godot_stats.json").read_text())
    cases = fixture["heroes"]
    assert len(cases) == 15
    for case in cases:
        hero = Stats()
        hero.from_dict(case["input"])  # the same save Godot loaded
        mine = {
            "max_hp": hero.max_hp(), "attack": hero.attack_damage(), "defense": hero.defense(),
            "crit": hero.crit_chance(), "evasion": hero.evasion(), "stamina": hero.max_stamina(),
            "skill": hero.skill_damage_bonus(), "free": hero.free_points(),
            "crit_damage": hero.total("crit_damage"), "accuracy": hero.total("accuracy"),
            "attack_speed": hero.total("attack_speed"), "xp_to_next": hero.xp_to_next(),
        }
        for key, value in mine.items():
            assert math.isclose(float(value), float(case[key]), abs_tol=1e-9), (case["class"], key)
        assert hero.notice == case["notice"]
        assert norm(hero.to_dict()) == norm(case["dict"])
        again = Stats()
        again.from_dict(case["dict"])  # and Godot's save of it loads the same
        assert norm(again.to_dict()) == norm(case["dict"]) and again.notice == ""
    assert [xp_for_level(level) for level in range(1, 31)] == [int(n) for n in fixture["xp_for_level"]]
    bag = fixture["bag"]
    for class_id in ("warrior", "archer"):
        mine = [stack["id"] for stack in items.sorted_bag(bag["input"], class_id)]
        assert mine == [stack["id"] for stack in bag[class_id]], class_id
    assert {item_id: items.required_level(item_id) for item_id in bag["levels"]} == {
        item_id: int(level) for item_id, level in bag["levels"].items()
    }
    loot = fixture["loot"]
    for level, pool in loot["pools"].items():
        assert sorted(items.drop_pool(int(level))) == sorted(pool), level
    for item_id, rarity, stat, low, high in loot["ranges"]:  # Godot's Vector2 is 32-bit: 1e-6
        mine = items.option_range(stat, item_id, rarity)
        assert math.isclose(mine[0], low, abs_tol=1e-6) and math.isclose(mine[1], high, abs_tol=1e-6), (
            item_id, rarity, stat, mine, (low, high))
    for row in fixture["upgrades"]:  # M5: cost, chance and stone of the next +, and what a + adds
        stack = row["stack"]
        mine = items.upgrade_step(stack)
        assert set(mine) == set(row["step"]), stack
        for key, value in row["step"].items():
            assert mine[key] == value if isinstance(value, str) else math.isclose(mine[key], value, abs_tol=1e-9), (
                stack, key)
        for stat in ("attack", "max_hp", "defense"):
            assert math.isclose(items.stat_of(stack, stat), row[stat], abs_tol=1e-9), (stack, stat)
    hero = Stats("warrior")
    hero.gold = 100000
    piece = items.gear("crimson_plate", "common", 9)
    assert hero.upgrade(piece, 0.99) == "same" and piece["misses"] == 1 and piece["plus"] == 9
    assert items.clean_stack(piece) == piece  # misses are kept in a save
    assert hero.upgrade(piece, 0.0) == "up" and "misses" not in piece and piece["plus"] == 10
    for hero_level, monster_level, factor, xp in fixture["gap"]:
        hero_level, monster_level = int(hero_level), int(monster_level)
        assert math.isclose(level_gap_factor(hero_level, monster_level), factor, abs_tol=1e-9)
        assert kill_xp(37, hero_level, monster_level) == int(xp)
