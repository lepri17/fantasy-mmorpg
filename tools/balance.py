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
from server.rules.stats import Stats, class_name, class_skills  # noqa: E402

OUT = ROOT / "docs" / "BALANCE.md"
LEVELS = (1, 2, 3, 4, 5, 6, 8, 10, 12, 15)
# Where a hero of each level hunts (the monster used for "time to kill").
HUNT = [(1, "green_slime"), (3, "blue_slime"), (4, "spore_shroom"), (8, "slime_king")]
MAIN_STAT = {"warrior": "strength", "archer": "agility", "mage": "energy"}
BETWEEN_FIGHTS = 3.0  # seconds of walking and looting per kill, for the pace table


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
             "ציוד ההתחלה, וכל נקודות הסטטים במאפיין הראשי של המקצוע (STR ללוחם, AGI לקשת, ENE לקוסם). "
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


def pace_section() -> str:
    monsters = table("monsters")
    rows = []
    total_minutes = 0.0
    for level in range(1, 16):
        stats = hero("warrior", level)
        monster_id = prey(level)
        monster = monsters[monster_id]
        kills = stats.xp_to_next() / int(monster["xp"])
        seconds = kills * (monster["max_hp"] / basic_dps(stats, monster) + BETWEEN_FIGHTS)
        total_minutes += seconds / 60
        rows.append([level, stats.xp_to_next(), monster["name"], f"{kills:.1f}", f"{seconds / 60:.1f}", f"{total_minutes:.0f}"])
    return "\n".join([
        "## קצב עליית רמות (לוחם)", "",
        f"הריגות עד הרמה הבאה, וזמן משוער: זמן ההריגה ועוד {BETWEEN_FIGHTS:.0f} שנ' הליכה ואיסוף לכל מפלצת.", "",
        md_table(["רמה", "EXP לרמה הבאה", "מפלצת", "הריגות", "דקות", "דקות מההתחלה"], rows), "",
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
    return "\n".join([head, heroes_section(), monsters_section(), pace_section(), skills_section(),
                      crit_section(), upgrade_section(), economy_section()]).rstrip() + "\n"


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
