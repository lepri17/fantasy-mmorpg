#!/usr/bin/env python3
"""Balance tables from the game data (client/data/*.json), written to
docs/BALANCE.md. It uses the same rules as the game (server/rules, which a
test keeps equal to the GDScript). Run after changing numbers:

    python3 tools/balance.py            # writes docs/BALANCE.md
    python3 tools/balance.py --check    # fails if docs/BALANCE.md is out of date

The averages count the damage spread, crits, misses, defense and the basic
attack's combo. Movement and the time between fights are left out."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from server.data import roundi, table  # noqa: E402
from server.rules import combat  # noqa: E402
from server.rules import items as item_db  # noqa: E402
from server.rules.stats import (  # noqa: E402
    Stats, class_name, class_skills, kill_xp, level_gap_factor, stat_rule,
)

OUT = ROOT / "docs" / "BALANCE.md"
LEVELS = (1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18)
# Where a hero of each level hunts (the monster used for "time to kill").
HUNT = [(1, "green_slime"), (3, "blue_slime"), (4, "spore_shroom"), (8, "slime_king"), (9, "bramble_boar"),
        (10, "lantern_wisp"), (13, "rootling"), (15, "moss_golem"), (18, "elder_treant")]
MAIN_STAT = {"warrior": "strength", "archer": "dexterity", "mage": "energy"}
# Monsters a hero hunts for XP (not the boss nor the event's golden slimes).
REGULAR = ("green_slime", "blue_slime", "spore_shroom", "bramble_boar", "lantern_wisp", "rootling", "moss_golem")
BUILD_LEVEL = 10
GEAR_TARGET = "blue_slime"  # the monster the gear table measures DPS and survival against
BETWEEN_FIGHTS = 5.0  # seconds of walking, looting and waiting for respawns per kill (pace table)
LOOT_LEVELS = (1, 3, 5, 8, 10, 13, 15)  # hero levels in the loot-per-hour table
SHOWN_DROPS = ("red_potion", "blue_potion", "ember_stone", "moon_stone")


def hero(class_id: str, level: int) -> Stats:
    """A hero with its starting gear and every stat point in its main stat."""
    stats = Stats(class_id)
    stats.level = level
    stats.stat_points = {MAIN_STAT[class_id]: stats.free_points()} if level > 1 else {}
    return stats


def prey(level: int) -> str:
    chosen = HUNT[0][1]
    for from_level, monster_id in HUNT:
        if level >= from_level and "boss" not in table("monsters")[monster_id]:
            chosen = monster_id
    return chosen


def combo_factor() -> float:
    finisher = float(combat.settings()["combo_finisher_multiplier"])
    return (2 + finisher) / 3


def basic_dps(stats: Stats, monster: dict) -> float:
    hit = combat.expected_damage(
        stats.attack_damage(), stats.crit_chance(), int(monster.get("defense", 0)),
        float(monster.get("evasion", 0.0)), stats.total("crit_damage"), stats.total("accuracy"),
    )
    return hit * combo_factor() / stats.attack_interval()


def monster_hit(monster: dict, stats: Stats) -> float:
    return combat.expected_damage(int(monster["attack_damage"]), 0.0, stats.defense(), stats.evasion())


def md_table(headers: list, rows: list) -> str:
    lines = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    lines += ["| " + " | ".join(str(cell) for cell in row) + " |" for row in rows]
    return "\n".join(lines)


def heroes_section() -> str:
    monsters = table("monsters")
    parts = ["## הגיבור לפי רמה", "",
             "ציוד ההתחלה, וכל נקודות הסטטים במאפיין הראשי של המקצוע (STR ללוחם, DEX לקשת, ENE לקוסם). "
             "DPS = נזק לשנייה בתקיפה רגילה נגד המפלצת של אותה רמה, כולל קומבו, קריטי, החטאות והגנה.", ""]
    for class_id in ("warrior", "archer", "mage"):
        rows = []
        for level in LEVELS:
            stats = hero(class_id, level)
            monster_id = prey(level)
            monster = monsters[monster_id]
            low, high = combat.damage_range(stats.attack_damage())
            dps = basic_dps(stats, monster)
            survive = stats.max_hp() / max(monster_hit(monster, stats), 0.1) * float(monster["attack_cooldown"])
            rows.append([
                level, stats.max_hp(), f"{low}~{high}", stats.defense(), f"{stats.crit_chance() * 100:.1f}%",
                f"{stats.attack_interval():.2f}", monsters[monster_id]["name"], f"{dps:.1f}",
                f"{monster['max_hp'] / dps:.1f}", f"{survive:.0f}",
            ])
        hidden = " (מוסתר כרגע)" if class_id == "mage" else ""
        parts += [f"### {class_name(class_id)}{hidden}", "", md_table(
            ["רמה", "HP", "התקפה", "הגנה", "קריטי", "שנ' בין מכות", "מפלצת", "DPS", "שנ' להריגה", "שנ' עד שהיא הורגת"], rows), ""]
    return "\n".join(parts)


def monsters_section() -> str:
    rows = []
    for monster in table("monsters").values():
        gold = sum(monster["gold"]) / 2
        level_hero = hero("warrior", int(monster["level"]))
        dps = basic_dps(level_hero, monster)
        rows.append([
            monster["name"], monster["level"], monster["max_hp"], monster["attack_damage"], monster.get("defense", 0),
            f"{float(monster.get('evasion', 0)) * 100:.0f}%", monster["xp"], f"{gold:.1f}",
            f"{monster['xp'] / monster['max_hp']:.2f}", f"{monster['max_hp'] / dps:.1f}",
            f"{monster_hit(monster, level_hero):.1f}", f"{survive_seconds(level_hero, monster):.0f}",
        ])
    return "\n".join([
        "## מפלצות", "",
        "מול לוחם ברמה של המפלצת, עם ציוד ההתחלה: \"שנ' להריגה\" בתקיפה רגילה בלבד, \"פגיעה בלוחם\" "
        "נזק ממוצע למכה רגילה (אחרי הגנה והתחמקות), ו\"שנ' עד שהיא הורגת\" בלי לרפא. מכות מיוחדות (הסתערות, "
        "מכת קרקע, התפרצות) חזקות יותר אבל מסומנות מראש.", "",
        md_table(["מפלצת", "רמה", "HP", "נזק", "הגנה", "התחמקות", "EXP", "זהב (ממוצע)", "EXP ל-HP",
                  "שנ' להריגה", "פגיעה בלוחם", "שנ' עד שהיא הורגת"], rows), "",
    ])


def best_hunt(stats: Stats) -> tuple:
    """The regular monster that gives the most XP a second: (id, XP a kill, seconds a kill)."""
    monsters = table("monsters")
    best = None
    for monster_id in REGULAR:
        monster = monsters[monster_id]
        if int(monster["level"]) > stats.level + 1:
            continue  # too dangerous to farm
        xp = kill_xp(int(monster["xp"]), stats.level, int(monster["level"]))
        seconds = monster["max_hp"] / basic_dps(stats, monster) + BETWEEN_FIGHTS
        if best is None or xp / seconds > best[1] / best[2]:
            best = (monster_id, xp, seconds)
    return best


def pace_section() -> str:
    monsters = table("monsters")
    rows = []
    total_minutes = 0.0
    for level in range(1, 21):
        stats = hero("warrior", level)
        monster_id, xp, seconds_each = best_hunt(stats)
        kills = stats.xp_to_next() / xp
        minutes = kills * seconds_each / 60
        total_minutes += minutes
        factor = level_gap_factor(level, int(monsters[monster_id]["level"]))
        rows.append([level, stats.xp_to_next(), monsters[monster_id]["name"], f"{xp} ({factor * 100:.0f}%)",
                     f"{kills:.0f}", f"{minutes:.1f}", f"{total_minutes:.0f}"])
    return "\n".join([
        "## קצב עליית רמות (לוחם)", "",
        f"EXP לרמה: {table('character')['xp_curve']['base']} x רמה^{table('character')['xp_curve']['exponent']}. "
        "מפלצת שרמתה נמוכה בהרבה נותנת פחות EXP (באחוזים בטבלה). בכל רמה נבחרה המפלצת שנותנת הכי הרבה EXP לדקה, "
        "מבין המפלצות שרמתן לכל היותר רמה אחת מעל הגיבור. "
        f"זמן לכל מפלצת: זמן ההריגה ועוד {BETWEEN_FIGHTS:.0f} שנ' הליכה ואיסוף. בלי משימות, בוס ומבוך.", "",
        md_table(["רמה", "EXP לרמה הבאה", "מפלצת", "EXP להריגה", "הריגות", "דקות", "דקות מההתחלה"], rows), "",
        gap_table(),
    ])


def gap_table() -> str:
    rows = [[f"{d:+d}", f"{level_gap_factor(10, 10 - d) * 100:.0f}%"] for d in (-5, -3, -1, 0, 2, 3, 4, 5, 6, 8, 10)]
    return "\n".join(["", "EXP לפי פער הרמות (רמת הגיבור פחות רמת המפלצת):", "",
                      md_table(["פער", "EXP"], rows), ""])


def points_section() -> str:
    monster = table("monsters")["blue_slime"]
    stat_names = {"strength": "STR", "dexterity": "DEX", "vitality": "VIT", "energy": "ENE"}
    rows = []
    for class_id in ("warrior", "archer", "mage"):
        for stat_id, short in stat_names.items():
            gives = {k: v for k, v in stat_rule(class_id, stat_id).items() if k not in ("short", "text")}
            base = hero(class_id, BUILD_LEVEL)
            base.stat_points = {}
            plus = hero(class_id, BUILD_LEVEL)
            plus.stat_points = {stat_id: 10}
            change = basic_dps(plus, monster) / basic_dps(base, monster) - 1
            rows.append([class_name(class_id), short, ", ".join(f"{k} {v:g}" for k, v in gives.items()),
                         f"{plus.max_hp() - base.max_hp():+d}", f"{plus.defense() - base.defense():+d}",
                         f"{change * 100:+.0f}%"])
    return "\n".join([
        "## מה נותנת כל נקודה", "",
        f"לכל נקודה (מתוך 5 בכל רמה). העמודות האחרונות: מה משנות 10 נקודות לגיבור ברמה {BUILD_LEVEL}.", "",
        md_table(["מקצוע", "סטט", "לכל נקודה", "HP (10 נק')", "הגנה (10 נק')", "DPS (10 נק')"], rows), "",
    ])


def builds_section() -> str:
    monster = table("monsters")["blue_slime"]
    rows = []
    for class_id in ("warrior", "archer", "mage"):
        main = MAIN_STAT[class_id]
        points = (BUILD_LEVEL - 1) * int(table("character")["stat_points_per_level"])
        builds = {
            "הכול בסטט הראשי": {main: points},
            "מאוזן": {main: points * 6 // 10, "vitality": points * 2 // 10,
                      "dexterity" if main != "dexterity" else "strength": points - points * 6 // 10 - points * 2 // 10},
            "הכול ב-VIT": {"vitality": points},
        }
        for name, spread in builds.items():
            stats = hero(class_id, BUILD_LEVEL)
            stats.stat_points = spread
            hit = monster_hit(monster, stats)
            survive = stats.max_hp() / max(hit, 0.1) * float(monster["attack_cooldown"])
            rows.append([class_name(class_id), name, stats.max_hp(), stats.attack_damage(), stats.defense(),
                         f"{stats.crit_chance() * 100:.0f}%", f"{stats.attack_interval():.2f}",
                         f"{basic_dps(stats, monster):.0f}", f"{survive:.0f}"])
    return "\n".join([
        f"## בניות לדוגמה (רמה {BUILD_LEVEL}, נגד Blue Slime)", "",
        "\"מאוזן\": 60% בסטט הראשי, 20% ב-VIT, והשאר ב-DEX (לקשת: ב-STR).", "",
        md_table(["מקצוע", "בנייה", "HP", "התקפה", "הגנה", "קריטי", "שנ' בין מכות", "DPS", "שנ' עד שהיא הורגת"], rows), "",
    ])


def skills_section() -> str:
    skills = table("skills")
    monster = table("monsters")["blue_slime"]
    rows = []
    for class_id in ("warrior", "archer", "mage"):
        stats = hero(class_id, 5)
        regen = float(stats.rule("stamina_regen_per_second"))
        basic = basic_dps(stats, monster)
        interval = f"{stats.attack_interval():.2f}"
        rows.append([class_name(class_id), "תקיפה רגילה", "-", interval, "-", f"{basic:.1f}", "1 / קשת", "-"])
        for skill_id in class_skills(class_id):
            skill = skills[skill_id]
            if "damage_multiplier" not in skill:
                rows.append([class_name(class_id), skill["name"], "-", skill["cooldown"], skill["stamina"], "-", "באף", "-"])
                continue
            base = roundi(stats.attack_damage() * float(skill["damage_multiplier"]) * (1 + stats.skill_damage_bonus()))
            hit = combat.expected_damage(
                base, stats.crit_chance(), int(monster.get("defense", 0)), float(monster.get("evasion", 0)),
                stats.total("crit_damage"), stats.total("accuracy"),
            )
            waves = int(skill.get("waves", 1))
            per_use = hit * waves
            every = max(float(skill["cooldown"]), float(skill["stamina"]) / regen)
            targets = "אזור" if any(k in skill for k in ("radius", "blast_radius", "arrows", "jumps")) else "אחת"
            if skill["type"] == "pierce":
                targets = "קו"
            power = f"x{skill['damage_multiplier']}" + (f" x{waves}" if waves > 1 else "")
            rows.append([class_name(class_id), skill["name"], power, skill["cooldown"], skill["stamina"],
                         f"{per_use / every:.1f}", targets, f"{per_use:.0f}"])
    return "\n".join([
        "## סקילים (רמה 5, נגד Blue Slime)", "",
        "\"DPS למטרה\": הנזק של שימוש אחד לחלק בזמן עד השימוש הבא, לפי ה-Cooldown או לפי קצב המילוי של ה-Stamina, הארוך מביניהם. "
        "הסקילים מצטרפים לתקיפה הרגילה, ולא באים במקומה.", "",
        md_table(["מקצוע", "סקיל", "נזק", "Cooldown", "עלות", "DPS למטרה", "מטרות", "נזק לשימוש"], rows), "",
    ])


def crit_section() -> str:
    settings = combat.settings()
    multiplier = float(settings["crit_multiplier"])
    rows = []
    for chance in (0.05, 0.08, 0.10, 0.15, 0.30):
        for bonus in (0.0, 0.15, 0.3):
            rows.append([f"{chance * 100:.0f}%", f"x{multiplier + bonus:.2f}", f"x{1 + chance * (multiplier + bonus - 1):.3f}"])
    return "\n".join([
        "## קריטי", "",
        f"מכה קריטית = x{multiplier} ועוד ה-Critical Damage. ההגנה יורדת מהמכה, אבל נשאר לפחות "
        f"{float(settings.get('defense_floor', 0)) * 100:.0f}% ממנה. "
        f"ההתחמקות פחות הדיוק, עד {float(settings.get('max_evasion', 0.75)) * 100:.0f}%.", "",
        md_table(["סיכוי", "מכפיל", "תוספת ממוצעת לנזק"], rows), "",
    ])


def survive_seconds(stats: Stats, monster: dict) -> float:
    """How long the hero lives while the monster keeps hitting him."""
    return stats.max_hp() / max(monster_hit(monster, stats), 0.1) * float(monster["attack_cooldown"])


def best_gear(class_id: str, level: int, plus: int = 0) -> Stats:
    """The hero wearing, in every slot, the common piece he may wear at this level
    that gives the most DPS x seconds alive against the gear target."""
    stats = hero(class_id, level)
    monster = table("monsters")[GEAR_TARGET]
    for _ in range(2):  # a second pass, so set bonuses can count
        for slot in item_db.data()["gear_slots"]:
            best = None
            for item_id, item in item_db.items().items():
                if item.get("slot") != slot or not item_db.can_wear(item_id, class_id, level):
                    continue
                stats.equipment[slot] = item_db.gear(item_id, "common", plus)
                score = basic_dps(stats, monster) * survive_seconds(stats, monster)
                if best is None or score > best[0]:
                    best = (score, item_id)
            if best is not None:
                stats.equipment[slot] = item_db.gear(best[1], "common", plus)
    return stats


def gear_section() -> str:
    monster = table("monsters")[GEAR_TARGET]
    rows = []
    for class_id in ("warrior", "archer", "mage"):
        for level in (1, 6, 10, 12):
            start = hero(class_id, level)
            loadouts = [("התחלה", start), ("הכי טוב", best_gear(class_id, level))]
            if level > 1:
                loadouts.append(("הכי טוב +6", best_gear(class_id, level, 6)))
            for name, stats in loadouts:
                pieces = ", ".join(item_db.items()[stack["id"]]["name"] for stack in stats.equipment.values())
                rows.append([class_name(class_id), level, name, stats.attack_damage(), stats.max_hp(),
                             stats.defense(), f"{basic_dps(stats, monster):.0f}",
                             f"{basic_dps(stats, monster) / basic_dps(start, monster) * 100 - 100:+.0f}%",
                             f"{survive_seconds(stats, monster):.0f}", pieces])
    return "\n".join([
        f"## ציוד (נגד {monster['name']})", "",
        "\"הכי טוב\": בכל משבצת, הפריט הרגיל (Common) שהגיבור יכול ללבוש ברמה הזאת ונותן הכי הרבה "
        "DPS כפול שניות חיים. כולל ציוד שדרוג המקצוע ברמה 10 וציוד העץ הקדום (רק משלל) ברמה 12. "
        "\"+6\": אותו ציוד משודרג לכל +6 (אבני Ember, בלי סיכון). "
        "נקודות הסטטים כולן בסטט הראשי.", "",
        md_table(["מקצוע", "רמה", "ציוד", "התקפה", "HP", "הגנה", "DPS", "DPS מול ההתחלה", "שנ' בחיים", "פריטים"],
                 rows), "",
    ])


def upgrade_section() -> str:
    upgrades = item_db.upgrades()
    rows = []
    for plus in range(int(upgrades.get("max_plus", 0))):
        step = item_db.upgrade_step({"id": "training_sword", "plus": plus})
        chance = float(step["chance"])
        rows.append([f"+{plus} -> +{plus + 1}", item_db.items()[step["stone"]]["name"], f"{chance * 100:.0f}%",
                     f"{1 / chance:.1f}", "יורד רמה" if step.get("on_fail") == "down" else "נשאר"])
    per_plus = upgrades.get("per_plus", {})
    bonus_rows = [[slot, ", ".join(f"+{v} {k}" for k, v in bonus.items())] for slot, bonus in per_plus.items()]
    return "\n".join([
        "## שדרוג ציוד", "", md_table(["שלב", "אבן", "סיכוי", "אבנים בממוצע", "בכישלון"], rows), "",
        md_table(["משבצת", "תוספת לכל +1"], bonus_rows), "",
    ])


def economy_section() -> str:
    monsters = table("monsters")
    rows = []
    shown = ("red_potion", "blue_potion", "ember_stone", "training_sword", "blue_plate", "book_ground_slam", "rebirth_scroll")
    for item_id in shown:
        if not item_db.exists(item_id):
            continue
        price = item_db.price(item_id)
        cells = [item_db.items()[item_id]["name"], price]
        for monster_id in ("green_slime", "blue_slime"):
            gold = sum(monsters[monster_id]["gold"]) / 2
            cells.append(f"{price / gold:.0f}")
        rows.append(cells)
    return "\n".join([
        "## כלכלה", "", md_table(["פריט", "מחיר", "הריגות Slime", "הריגות Blue Slime"], rows), "",
    ])


def rarity_odds(rolls: int, min_rarity: str = "") -> dict:
    """The chance of each rarity when the best of `rolls` rolls is kept, never
    below min_rarity (item_db.roll_gear)."""
    rarities = item_db.rarities()
    total = sum(float(info["weight"]) for info in rarities.values())
    odds, at_most, before = {}, 0.0, 0.0
    for rarity, info in rarities.items():
        at_most += float(info["weight"]) / total
        odds[rarity] = at_most**rolls - before
        before = at_most**rolls
    for rarity in list(odds):
        if item_db.rarity_rank(rarity) < item_db.rarity_rank(min_rarity):
            odds[min_rarity] += odds[rarity]
            odds[rarity] = 0.0
    return odds


def loot_per_kill(monster: dict) -> dict:
    """What one kill drops on average, elites counted (combat.json "elite"):
    gold, items {id: count}, gear pieces, rare-or-better pieces and epic pieces."""
    elite = combat.settings()["elite"]
    boss = monster.get("boss", {})
    elite_share = 0.0 if boss else float(elite["chance"])
    rare_rank = item_db.rarity_rank("rare")
    out = {"gold": 0.0, "items": {}, "gear": 0.0, "rare": 0.0, "epic": 0.0}
    for share, is_elite in ((1.0 - elite_share, False), (elite_share, True)):
        out["gold"] += share * sum(monster["gold"]) / 2 * (float(elite["gold"]) if is_elite else 1.0)
        for drop in monster.get("drops", []) + (elite.get("extra_drops", []) if is_elite else []):
            out["items"][drop["item"]] = out["items"].get(drop["item"], 0.0) + share * float(drop["chance"])
        if "gear_drops" not in monster:
            continue
        chance = float(monster["gear_drops"]["chance"]) + (float(elite["gear_chance"]) if is_elite else 0.0)
        rolls = int(elite["rarity_rolls"]) if is_elite else int(boss.get("rarity_rolls", 1))
        odds = rarity_odds(rolls, boss.get("min_rarity", ""))
        pieces = share * min(chance, 1.0) * int(boss.get("gear_count", 1))
        out["gear"] += pieces
        out["rare"] += pieces * sum(p for r, p in odds.items() if item_db.rarity_rank(r) >= rare_rank)
        out["epic"] += pieces * odds.get("epic", 0.0)
    return out


def _span(stat: str, low: float, high: float) -> str:
    if stat in item_db.PERCENT_STATS:
        return f"{low * 100:g}~{high * 100:g}%"
    return f"{low:.0f}~{high:.0f}"


def loot_section() -> str:
    monsters = table("monsters")
    names = item_db.items()
    window = item_db.data()["drop_levels"]
    rows = []
    for monster in monsters.values():
        loot = loot_per_kill(monster)
        levels = sorted({item_db.required_level(i) for i in item_db.drop_pool(int(monster["level"]))})
        gear_levels = f"{levels[0]}-{levels[-1]}" if "gear_drops" in monster and levels else "-"
        rows.append([monster["name"], monster["level"], f"{loot['gold']:.0f}"]
                    + [f"{loot['items'].get(item_id, 0.0) * 100:.0f}" for item_id in SHOWN_DROPS]
                    + [f"{loot['gear'] * 100:.1f}", f"{loot['rare'] * 100:.1f}", f"{loot['epic'] * 100:.2f}",
                       gear_levels])
    hour_rows = []
    elite_hp = 1.0 + float(combat.settings()["elite"]["chance"]) * (float(combat.settings()["elite"]["hp"]) - 1.0)
    for level in LOOT_LEVELS:
        stats = hero("warrior", level)
        monster_id = best_hunt(stats)[0]
        monster = monsters[monster_id]
        seconds = monster["max_hp"] * elite_hp / basic_dps(stats, monster) + BETWEEN_FIGHTS
        kills = 3600 / seconds
        loot = loot_per_kill(monster)
        hour_rows.append([level, monster["name"], f"{kills:.0f}", f"{loot['gold'] * kills:.0f}",
                          f"{loot['gear'] * kills:.1f}", f"{loot['rare'] * kills:.1f}",
                          f"{1 / (loot['epic'] * kills):.1f}" if loot["epic"] > 0 else "-"])
    elite = combat.settings()["elite"]
    king = monsters["slime_king"]["boss"]
    boss_odds = rarity_odds(int(king.get("rarity_rolls", 1)), king.get("min_rarity", ""))
    rarity_rows = []
    for rarity, info in item_db.rarities().items():
        rarity_rows.append([info["name"], info["options"], f"{float(info['roll_floor']) * 100:.0f}%",
                            info["ground_seconds"], f"{rarity_odds(1)[rarity] * 100:.1f}%",
                            f"{rarity_odds(int(elite['rarity_rolls']))[rarity] * 100:.1f}%",
                            f"{boss_odds[rarity] * 100:.1f}%"])
    sample = {}
    for item_id in names:
        if item_db.is_gear(item_id):
            sample.setdefault(item_db.required_level(item_id), item_id)
    columns = [(1, "common"), (6, "common"), (12, "common"), (12, "rare"), (12, "epic")]
    option_rows = []
    for stat in item_db.random_options():
        option_rows.append([stat] + [_span(stat, *item_db.option_range(stat, sample[level], rarity))
                                     for level, rarity in columns])
    return "\n".join([
        "## שלל", "",
        f"כל מפלצת זורקת ציוד ברמות {window[0]} עד +{window[1]} מהרמה שלה (`drop_levels` ב-items.json), "
        "רק ציוד שהמקצוע של הגיבור יכול ללבוש. ציוד שמקבלים רק במשימה (`no_drop`) לא נופל. "
        "ל-100 הריגות, כולל מפלצות עילית. בוס זורק כמה פריטים (`gear_count`), כולם לפחות בדרגה `min_rarity`.", "",
        md_table(["מפלצת", "רמה", "זהב להריגה"] + [names[i]["name"] for i in SHOWN_DROPS]
                 + ["ציוד", "נדיר ומעלה", "אפי", "רמות הציוד"], rows), "",
        "### שלל בשעה (לוחם, ציוד התחלה, אותה מפלצת כמו בקצב עליית הרמות)", "",
        md_table(["רמה", "מפלצת", "הריגות בשעה", "זהב בשעה", "ציוד בשעה", "נדיר ומעלה בשעה", "שעות לפריט אפי"],
                 hour_rows), "",
        "### דרגות", "",
        "רגיל: הטלה אחת. עילית: הטוב מבין "
        f"{elite['rarity_rolls']} הטלות. בוס: הטוב מבין {king.get('rarity_rolls', 1)}, ולפחות {king.get('min_rarity')}. "
        "\"התחלת הטווח\": כמה מהטווח של כל בונוס דרגה גבוהה מדלגת (פריט נדיר מקבל בונוסים גבוהים יותר).", "",
        md_table(["דרגה", "בונוסים", "התחלת הטווח", "שניות על הרצפה", "רגיל", "עילית", "בוס"], rarity_rows), "",
        "### טווחי הבונוסים האקראיים", "",
        "הטווח גדל עם רמת הפריט: מספרים שלמים ב-"
        f"{item_db.data()['option_growth']['whole'] * 100:g}% לכל רמה, אחוזים ב-"
        f"{item_db.data()['option_growth']['percent'] * 100:g}% לכל רמה (`option_growth`).", "",
        md_table(["בונוס", "רמה 1", "רמה 6", "רמה 12", "רמה 12 נדיר", "רמה 12 אפי"], option_rows), "",
    ])


def build() -> str:
    head = "\n".join([
        "# BALANCE – טבלאות איזון", "",
        "נוצר אוטומטית מקובצי הנתונים (`client/data/*.json`) על ידי `tools/balance.py`. לא לערוך ידנית: "
        "משנים את הנתונים ומריצים את הכלי מחדש. המספרים הם ממוצעים לפי חוקי המשחק.", "",
    ])
    return "\n".join([head, heroes_section(), monsters_section(), pace_section(), points_section(), builds_section(),
                      skills_section(), crit_section(), gear_section(), upgrade_section(),
                      economy_section(), loot_section()]).rstrip() + "\n"


def main() -> int:
    text = build()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print("docs/BALANCE.md is out of date: run python3 tools/balance.py")
            return 1
        print("OK: docs/BALANCE.md matches the data")
        return 0
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
