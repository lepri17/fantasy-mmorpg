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
LEVELS = (1, 2, 3, 4, 5, 6, 8, 10, 12, 15)
# Where a hero of each level hunts (the monster used for "time to kill").
HUNT = [(1, "green_slime"), (3, "blue_slime"), (4, "spore_shroom"), (8, "slime_king")]
MAIN_STAT = {"warrior": "strength", "archer": "dexterity", "mage": "energy"}
# Monsters a hero hunts for XP (not the boss nor the event's golden slimes).
REGULAR = ("green_slime", "blue_slime", "spore_shroom")
BUILD_LEVEL = 10
BETWEEN_FIGHTS = 5.0  # seconds of walking, looting and waiting for respawns per kill (pace table)


def hero(class_id: str, level: int) -> Stats:
    """A hero with its starting gear and every stat point in its main stat."""
    stats = Stats(class_id)
    stats.level = level
    stats.stat_points = {MAIN_STAT[class_id]: stats.free_points()} if level > 1 else {}
    return stats


def prey(level: int) -> str:
    chosen = HUNT[0][1]
    for from_level, monster_id in HUNT:
        if level >= from_level and monster_id != "slime_king":
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
    reference = hero("warrior", 1)
    for monster in table("monsters").values():
        gold = sum(monster["gold"]) / 2
        level_hero = hero("warrior", int(monster["level"]))
        dps = basic_dps(level_hero, monster)
        rows.append([
            monster["name"], monster["level"], monster["max_hp"], monster["attack_damage"], monster.get("defense", 0),
            f"{float(monster.get('evasion', 0)) * 100:.0f}%", monster["xp"], f"{gold:.1f}",
            f"{monster['xp'] / monster['max_hp']:.2f}", f"{monster['max_hp'] / dps:.1f}",
            f"{monster_hit(monster, reference):.1f}",
        ])
    return "\n".join([
        "## מפלצות", "",
        "\"שנ' להריגה\": לוחם ברמה של המפלצת, תקיפה רגילה בלבד. \"פגיעה בלוחם רמה 1\": נזק ממוצע למכה (אחרי הגנה והתחמקות).", "",
        md_table(["מפלצת", "רמה", "HP", "נזק", "הגנה", "התחמקות", "EXP", "זהב (ממוצע)", "EXP ל-HP",
                  "שנ' להריגה", "פגיעה בלוחם רמה 1"], rows), "",
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
    for level in range(1, 16):
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
    rarity_rows = [[name, info["weight"], info["options"]] for name, info in item_db.rarities().items()]
    option_rows = [[stat, f"{low} ~ {high}"] for stat, (low, high) in item_db.random_options().items()]
    return "\n".join([
        "## כלכלה ושלל", "", md_table(["פריט", "מחיר", "הריגות Slime", "הריגות Blue Slime"], rows), "",
        md_table(["דרגה", "משקל", "בונוסים אקראיים"], rarity_rows), "", md_table(["בונוס אקראי", "טווח"], option_rows), "",
    ])


def build() -> str:
    head = "\n".join([
        "# BALANCE – טבלאות איזון", "",
        "נוצר אוטומטית מקובצי הנתונים (`client/data/*.json`) על ידי `tools/balance.py`. לא לערוך ידנית: "
        "משנים את הנתונים ומריצים את הכלי מחדש. המספרים הם ממוצעים לפי חוקי המשחק.", "",
    ])
    return "\n".join([head, heroes_section(), monsters_section(), pace_section(), points_section(), builds_section(),
                      skills_section(), crit_section(), upgrade_section(), economy_section()]).rstrip() + "\n"


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
