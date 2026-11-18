"""One character's progress and the numbers that follow from it. A port of
client/scripts/player/player_stats.gd, with class_db.gd, achievement_record.gd,
quest_log.gd and dungeon_log.gd. to_dict() writes the client's save format
(version 10), so the client shows what the server sends with from_dict()."""

from __future__ import annotations

import datetime
import random

from ..data import roundi, table
from . import items as item_db

SAVE_VERSION = 11
# Version 11 reworked the stats (AGI became DEX): older saves get their points back.
STATS_REWORK_VERSION = 11
STATS_REWORK_NOTICE = "The stats were reworked: all your stat points are free to spend again."
POTION_ID = "red_potion"
DEFAULT_CLASS = "warrior"


def today() -> str:
    """The server's date, for daily quests and dungeon entries."""
    return datetime.date.today().isoformat()


def _int(value, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


# --- classes (class_db.gd)


def character_rules() -> dict:
    return table("character")


def classes() -> dict:
    return table("classes")["classes"]


def class_exists(class_id: str) -> bool:
    return class_id in classes()


def playable() -> list:
    return list(table("classes").get("playable", table("classes")["order"]))


def class_info(class_id: str) -> dict:
    return classes().get(class_id, classes()[DEFAULT_CLASS])


def class_rule(class_id: str, key: str):
    own = class_info(class_id).get("rules", {})
    return own[key] if key in own else character_rules()[key]


def stat_rule(class_id: str, stat_id: str) -> dict:
    merged = dict(character_rules()["stats"].get(stat_id, {}))
    merged.update(class_info(class_id).get("stats", {}).get(stat_id, {}))
    return merged


def class_name(class_id: str, advanced: bool = False) -> str:
    info = class_info(class_id)
    return info["advanced"]["name"] if advanced else info["name"]


def class_skills(class_id: str) -> list:
    skills = table("skills")
    owned = [s for s in skills if skills[s].get("class", DEFAULT_CLASS) == class_id]
    return sorted(owned, key=lambda s: skills[s]["action"])


def level_gap_factor(hero_level: int, monster_level: int) -> float:
    """Part of a monster's XP a hero gets: full up to a few levels above it,
    then less for every level more (never below the lowest), and a little
    more for monsters above the hero (character.json "xp_level_gap")."""
    gap = character_rules()["xp_level_gap"]
    difference = hero_level - monster_level
    if difference < 0:
        return min(1.0 + float(gap["gain_per_level"]) * -difference, float(gap["highest"]))
    extra = difference - int(gap["free_levels"])
    if extra <= 0:
        return 1.0
    return max(1.0 - float(gap["loss_per_level"]) * extra, float(gap["lowest"]))


def xp_for_level(level: int) -> int:
    """XP to finish a level: base x level^exponent (character.json "xp_curve")."""
    curve = character_rules()["xp_curve"]
    return roundi(float(curve["base"]) * level ** float(curve["exponent"]))


def kill_xp(xp: int, hero_level: int, monster_level: int) -> int:
    """The XP one kill gives, never less than 1 (leveling.gd kill_xp)."""
    return max(1, roundi(xp * level_gap_factor(hero_level, monster_level)))


def with_article(word: str) -> str:
    return ("an " if word[:1] in "AEIOU" else "a ") + word


# --- achievements and titles (achievement_record.gd)


class Record:
    def __init__(self) -> None:
        self.counters: dict = {}
        self.earned: list = []
        self.title: str = ""

    @staticmethod
    def list() -> dict:
        return table("achievements")

    def count(self, counter: str, amount: int, level: int) -> list:
        self.counters[counter] = _int(self.counters.get(counter, 0)) + max(amount, 0)
        return self.check(level)

    def progress(self, achievement_id: str, level: int) -> int:
        counter = self.list()[achievement_id]["counter"]
        return level if counter == "level" else _int(self.counters.get(counter, 0))

    def check(self, level: int) -> list:
        new_ones = []
        for achievement_id, achievement in self.list().items():
            done = self.progress(achievement_id, level) >= _int(achievement["goal"])
            if achievement_id not in self.earned and done:
                self.earned.append(achievement_id)
                new_ones.append(achievement_id)
        if self.title == "" and new_ones:
            self.title = new_ones[0]
        return new_ones

    def set_title(self, achievement_id: str) -> bool:
        if achievement_id != "" and achievement_id not in self.earned:
            return False
        self.title = achievement_id
        return True

    def title_bonus(self, stat: str) -> float:
        if self.title == "":
            return 0.0
        return float(self.list()[self.title].get("bonus", {}).get(stat, 0.0))

    def to_dict(self) -> dict:
        return {"counters": dict(self.counters), "achievements": list(self.earned), "title": self.title}

    def from_dict(self, data: dict) -> None:
        saved = data.get("counters", {})
        self.counters = (
            {str(k): max(0, _int(v)) for k, v in saved.items()} if isinstance(saved, dict) else {}
        )
        self.earned = []
        saved = data.get("achievements", [])
        for achievement_id in saved if isinstance(saved, list) else []:
            if achievement_id in self.list() and achievement_id not in self.earned:
                self.earned.append(achievement_id)
        self.title = str(data.get("title", ""))
        if self.title not in self.earned:
            self.title = ""


# --- quests (quest_log.gd)


class QuestLog:
    def __init__(self) -> None:
        self.active: dict = {}
        self.done: dict = {}

    @staticmethod
    def list() -> dict:
        return table("quests")

    def state(self, quest_id: str, stats: "Stats", day: str) -> str:
        if quest_id in self.active:
            ready = self.progress(quest_id, stats) >= self.goal_count(quest_id)
            return "ready" if ready else "active"
        quest = self.list()[quest_id]
        if quest_id in self.done and (not quest.get("daily", False) or self.done[quest_id] == day):
            return "done"
        if stats.level < _int(quest.get("level", 1)):
            return "locked"
        if "after" in quest and quest["after"] not in self.done:
            return "locked"
        return "available"

    def start(self, quest_id: str, stats: "Stats", day: str) -> bool:
        if quest_id not in self.list() or self.state(quest_id, stats, day) != "available":
            return False
        self.active[quest_id] = 0
        return True

    def progress(self, quest_id: str, stats: "Stats") -> int:
        goal = self.list()[quest_id]["goal"]
        if goal["type"] == "collect":
            return stats.count_of(goal["item"])
        return _int(self.active.get(quest_id, 0))

    def goal_count(self, quest_id: str) -> int:
        return _int(self.list()[quest_id]["goal"].get("count", 1))

    def on_kill(self, monster_id: str) -> list:
        counted = []
        for quest_id in self.active:
            goal = self.list()[quest_id]["goal"]
            wanted = goal["type"] == "kill" and goal["monster"] in ("any", monster_id)
            if wanted and _int(self.active[quest_id]) < self.goal_count(quest_id):
                self.active[quest_id] = _int(self.active[quest_id]) + 1
                counted.append(quest_id)
        return counted

    def on_talk(self, npc_id: str) -> list:
        reached = []
        for quest_id in self.active:
            goal = self.list()[quest_id]["goal"]
            if goal["type"] == "talk" and goal["npc"] == npc_id and _int(self.active[quest_id]) < 1:
                self.active[quest_id] = 1
                reached.append(quest_id)
        return reached

    def finish(self, quest_id: str, day: str) -> None:
        self.active.pop(quest_id, None)
        self.done[quest_id] = day

    @classmethod
    def given_by(cls, npc_id: str) -> list:
        return [q for q, quest in cls.list().items() if quest["giver"] == npc_id]

    def to_dict(self) -> dict:
        return {"quests": {"active": dict(self.active), "done": dict(self.done)}}

    def from_dict(self, data: dict) -> None:
        self.active, self.done = {}, {}
        saved = data.get("quests", {})
        if not isinstance(saved, dict):
            return
        for quest_id, value in (saved.get("active") or {}).items():
            if quest_id in self.list():
                self.active[quest_id] = max(0, _int(value))
        for quest_id, value in (saved.get("done") or {}).items():
            if quest_id in self.list():
                self.done[quest_id] = str(value)


# --- the character (player_stats.gd)


class Stats:
    def __init__(self, class_id: str = DEFAULT_CLASS, rng: random.Random = random) -> None:
        self.rng = rng
        self.class_id = class_id if class_exists(class_id) else DEFAULT_CLASS
        self.advanced = False
        self.hero_name = ""
        self.tutorial = 0
        self.level = 1
        self.xp = 0
        self.gold = 0
        self.equipment: dict = {}
        self.bag: list = []
        self.stat_points: dict = {}
        self.learned_skills: list = []
        self.storage: list = []
        self.dungeon_runs: dict = {}
        self.map_id = ""
        self.auto_potion = 0
        self.quests = QuestLog()
        self.record = Record()
        self.notice = ""  # a message for the player after loading an older save
        self._start_fresh()

    # numbers

    @staticmethod
    def bag_size() -> int:
        return _int(character_rules()["bag_size"])

    @staticmethod
    def storage_size() -> int:
        return _int(character_rules()["storage_size"])

    @staticmethod
    def auto_potion_choices() -> list:
        return [_int(v) for v in character_rules()["auto_potion_choices"]]

    def rule(self, key: str):
        return class_rule(self.class_id, key)

    def max_hp(self) -> int:
        return (
            _int(self.rule("base_max_hp"))
            + _int(self.rule("hp_per_level")) * (self.level - 1)
            + self.gear_bonus("max_hp")
            + int(self.extra_bonus("max_hp"))
        )

    def attack_damage(self) -> int:
        return (
            _int(self.rule("base_damage"))
            + _int(self.rule("damage_per_level")) * (self.level - 1)
            + self.gear_bonus("attack")
            + int(self.extra_bonus("attack"))
        )

    def defense(self) -> int:
        return _int(self.rule("defense")) + self.gear_bonus("defense") + int(self.extra_bonus("defense"))

    def crit_chance(self) -> float:
        return float(self.rule("crit_chance")) + self.gear_total("crit_chance") + self.extra_bonus("crit_chance")

    def evasion(self) -> float:
        return float(self.rule("evasion")) + self.gear_total("evasion") + self.extra_bonus("evasion")

    def total(self, stat: str) -> float:
        """crit_damage, accuracy, attack_speed...: rules + gear + bonuses."""
        return float(self.rule(stat)) + self.gear_total(stat) + self.extra_bonus(stat)

    def attack_interval(self) -> float:
        limit = float(table("combat").get("max_attack_speed", 1.0))
        speed = min(max(self.total("attack_speed"), 0.0), limit)
        return float(self.rule("attack_cooldown")) / (1.0 + speed)

    def max_stamina(self) -> float:
        return float(self.rule("max_stamina")) + self.gear_total("max_stamina") + self.extra_bonus("max_stamina")

    def skill_damage_bonus(self) -> float:
        return self.gear_total("skill_damage") + self.extra_bonus("skill_damage")

    def extra_bonus(self, stat: str) -> float:
        total = 0.0
        for stat_id, points in self.stat_points.items():
            total += float(points) * float(stat_rule(self.class_id, stat_id).get(stat, 0.0))
        if self.advanced:
            total += float(class_info(self.class_id)["advanced"].get("bonus", {}).get(stat, 0.0))
        return total + self.record.title_bonus(stat)

    # stat points

    def free_points(self) -> int:
        return (self.level - 1) * _int(character_rules()["stat_points_per_level"]) - self.spent_points()

    def spent_points(self) -> int:
        return sum(_int(v) for v in self.stat_points.values())

    def add_stat_point(self, stat_id: str) -> bool:
        if self.free_points() <= 0 or stat_id not in character_rules()["stats"]:
            return False
        self.stat_points[stat_id] = _int(self.stat_points.get(stat_id, 0)) + 1
        return True

    def reset_cost(self) -> int:
        rules = character_rules()
        if self.level < _int(rules["stat_reset_free_below_level"]):
            return 0
        return _int(rules["stat_reset_gold_per_level"]) * self.level

    def reset_stats(self, pay_gold: bool) -> bool:
        if self.spent_points() == 0 or (pay_gold and self.gold < self.reset_cost()):
            return False
        if pay_gold:
            self.gold -= self.reset_cost()
        self.stat_points = {}
        return True

    def knows_skill(self, skill_id: str) -> bool:
        return skill_id in self.learned_skills

    def learn_skill(self, skill_id: str) -> bool:
        if self.knows_skill(skill_id):
            return False
        self.learned_skills.append(skill_id)
        return True

    # gear

    def gear_bonus(self, stat: str) -> int:
        return roundi(self.gear_total(stat))

    def gear_total(self, stat: str) -> float:
        total = self._set_bonus(stat)
        for stack in self.equipment.values():
            total += item_db.stat_of(stack, stat)
        return total

    def set_pieces(self) -> dict:
        counts: dict = {}
        for stack in self.equipment.values():
            set_id = item_db.items()[stack["id"]].get("set", "")
            if set_id:
                counts[set_id] = counts.get(set_id, 0) + 1
        return counts

    def _set_bonus(self, stat: str) -> float:
        total = 0.0
        for set_id, count in self.set_pieces().items():
            for needed, bonus in item_db.sets()[set_id]["bonuses"].items():
                if count >= _int(needed):
                    total += float(bonus.get(stat, 0.0))
        return total

    # the bag

    def count_of(self, item_id: str) -> int:
        index = self._stack_index(item_id)
        return _int(self.bag[index]["count"]) if index >= 0 else 0

    @property
    def potions(self) -> int:
        return self.count_of(POTION_ID)

    def has_room_for(self, item_id: str) -> bool:
        return (self._stacks(item_id) and self._stack_index(item_id) >= 0) or len(self.bag) < self.bag_size()

    def add_item(self, item_id: str, count: int = 1) -> bool:
        if count <= 0 or not item_db.exists(item_id):
            return False
        if self._stacks(item_id):
            index = self._stack_index(item_id)
            if index >= 0:
                self.bag[index]["count"] = _int(self.bag[index]["count"]) + count
                return True
            if len(self.bag) >= self.bag_size():
                return False
            self.bag.append({"id": item_id, "count": count})
            return True
        if len(self.bag) + count > self.bag_size():
            return False
        for _ in range(count):
            self.bag.append(item_db.gear(item_id))
        return True

    def add_stack(self, stack: dict) -> bool:
        entry = item_db.clean_stack(stack)
        if not entry:
            return False
        if not item_db.is_gear(entry["id"]):
            return self.add_item(entry["id"], _int(entry["count"]))
        if len(self.bag) >= self.bag_size():
            return False
        self.bag.append(entry)
        return True

    def take_from_bag(self, index: int) -> dict:
        if index < 0 or index >= len(self.bag):
            return {}
        stack = self.bag[index]
        left = _int(stack["count"]) - 1
        if left <= 0:
            self.bag.pop(index)
            return stack
        stack["count"] = left
        return {"id": stack["id"], "count": 1}

    def take_stack(self, index: int) -> dict:
        """A whole bag slot (all of a stack), for trading."""
        if index < 0 or index >= len(self.bag):
            return {}
        return self.bag.pop(index)

    def equip(self, index: int) -> bool:
        if index < 0 or index >= len(self.bag):
            return False
        stack = self.bag[index]
        slot = item_db.items()[stack["id"]].get("slot", "")
        if slot == "" or not item_db.can_wear(stack["id"], self.class_id, self.level):
            return False
        worn = self.equipment.get(slot, {})
        self.equipment[slot] = stack
        if worn:
            self.bag[index] = worn
        else:
            self.bag.pop(index)
        return True

    def unequip(self, slot: str) -> bool:
        worn = self.equipment.get(slot, {})
        if not worn or len(self.bag) >= self.bag_size():
            return False
        del self.equipment[slot]
        self.bag.append(worn)
        return True

    def remove_equipped(self, slot: str) -> dict:
        return self.equipment.pop(slot, {}) if isinstance(slot, str) else {}

    def upgrade(self, stack: dict, roll: float, use_stone: bool = False) -> str:
        """For gold, with a stone if use_stone: "up", "same" (missed: the level
        is kept and the next try is likelier), or "" (player_stats.gd upgrade)."""
        step = item_db.upgrade_step(stack)
        if not step or self.gold < int(step["cost"]):
            return ""
        chance = float(step["chance"])
        if use_stone:
            if step["stone"] == "" or self.count_of(step["stone"]) <= 0:
                return ""
            self._set_count(step["stone"], self.count_of(step["stone"]) - 1)
            chance += float(step["stone_bonus"])
        self.gold -= int(step["cost"])
        if roll < chance:
            stack["plus"] = _int(stack.get("plus", 0)) + 1
            stack.pop("misses", None)
            return "up"
        stack["misses"] = min(_int(stack.get("misses", 0)) + 1, item_db.MAX_MISSES)
        return "same"

    def remove_items(self, item_id: str, count: int) -> bool:
        if self.count_of(item_id) < count:
            return False
        self._set_count(item_id, self.count_of(item_id) - count)
        return True

    def room_for(self, entries: list) -> bool:
        slots_needed = 0
        for entry in entries:
            if item_db.is_gear(entry["id"]):
                slots_needed += _int(entry.get("count", 1))
            elif self._stack_index(entry["id"]) < 0:
                slots_needed += 1
        return len(self.bag) + slots_needed <= self.bag_size()

    def store(self, index: int) -> bool:
        if index < 0 or index >= len(self.bag):
            return False
        stack = self.bag[index]
        if not item_db.is_gear(stack["id"]):
            for stored in self.storage:
                if stored["id"] == stack["id"]:
                    stored["count"] = _int(stored["count"]) + _int(stack["count"])
                    self.bag.pop(index)
                    return True
        if len(self.storage) >= self.storage_size():
            return False
        self.storage.append(stack)
        self.bag.pop(index)
        return True

    def take_stored(self, index: int) -> bool:
        if index < 0 or index >= len(self.storage):
            return False
        stack = self.storage[index]
        if not item_db.is_gear(stack["id"]):
            if not self.add_item(stack["id"], _int(stack["count"])):
                return False
        elif len(self.bag) >= self.bag_size():
            return False
        else:
            self.bag.append(stack)
        self.storage.pop(index)
        return True

    # levels

    def xp_to_next(self) -> int:
        return xp_for_level(self.level)

    def add_xp(self, amount: int) -> int:
        gained = 0
        self.xp += max(amount, 0)
        while self.xp >= self.xp_to_next():
            self.xp -= self.xp_to_next()
            self.level += 1
            gained += 1
        return gained

    def total_xp(self) -> int:
        """All XP ever earned, for the leaderboard."""
        return sum(xp_for_level(level) for level in range(1, self.level)) + self.xp

    # saving

    def to_dict(self) -> dict:
        data = {
            "version": SAVE_VERSION,
            "class": self.class_id,
            "advanced": self.advanced,
            "name": self.hero_name,
            "tutorial": self.tutorial,
            "level": self.level,
            "xp": self.xp,
            "gold": self.gold,
            "bag": [dict(s, options=dict(s["options"])) if "options" in s else dict(s) for s in self.bag],
            "equipment": {k: dict(v, options=dict(v.get("options", {}))) for k, v in self.equipment.items()},
            "stat_points": dict(self.stat_points),
            "learned_skills": list(self.learned_skills),
            "auto_potion": self.auto_potion,
            "map": self.map_id,
            "storage": [dict(s) for s in self.storage],
            "dungeon_runs": {k: dict(v) for k, v in self.dungeon_runs.items()},
        }
        data.update(self.record.to_dict())
        data.update(self.quests.to_dict())
        return data

    def from_dict(self, data: dict) -> None:
        self.class_id = str(data.get("class", DEFAULT_CLASS))
        if not class_exists(self.class_id):
            self.class_id = DEFAULT_CLASS
        self.advanced = data.get("advanced", False) is True
        self.hero_name = str(data.get("name", ""))[:16]
        self.tutorial = min(max(_int(data.get("tutorial", 99 if "equipment" in data else 0)), 0), 99)
        self.level = max(1, _int(data.get("level", 1), 1))
        self.xp = max(0, _int(data.get("xp", 0)))
        self.gold = max(0, _int(data.get("gold", 0)))
        self._load_progress(data)
        if _int(data.get("version", 1), 1) < 2 or "equipment" not in data:
            potions = _int(data.get("potions", -1), -1)
            self._start_fresh()
            if potions >= 0:
                self._set_count(POTION_ID, potions)
            return
        self.bag, self.equipment = [], {}
        saved_gear = data.get("equipment", {})
        if isinstance(saved_gear, dict):
            for slot, saved in saved_gear.items():
                worn = item_db.clean_stack(saved if isinstance(saved, dict) else {"id": saved})
                if (
                    worn
                    and item_db.items()[worn["id"]].get("slot", "") == slot
                    and item_db.usable_by(worn["id"], self.class_id)
                ):
                    self.equipment[slot] = worn
        saved_bag = data.get("bag", [])
        for stack in saved_bag if isinstance(saved_bag, list) else []:
            self.add_stack(stack if isinstance(stack, dict) else {})

    def _load_progress(self, data: dict) -> None:
        self.stat_points = {}
        self.notice = ""
        saved = data.get("stat_points", {})
        if isinstance(saved, dict):
            for stat_id, value in saved.items():
                stat_id = "dexterity" if stat_id == "agility" else stat_id
                if stat_id in character_rules()["stats"] and _int(value) > 0:
                    self.stat_points[stat_id] = self.stat_points.get(stat_id, 0) + _int(value)
        if self.free_points() < 0:
            self.stat_points = {}
        if self.stat_points and _int(data.get("version", 1), 1) < STATS_REWORK_VERSION:
            self.stat_points = {}
            self.notice = STATS_REWORK_NOTICE
        skills = table("skills")
        self.learned_skills = []
        saved = data.get("learned_skills", [])
        for skill_id in saved if isinstance(saved, list) else []:
            if (
                skill_id in skills
                and skills[skill_id].get("class", DEFAULT_CLASS) == self.class_id
                and skill_id not in self.learned_skills
            ):
                self.learned_skills.append(skill_id)
        self.record.from_dict(data)
        self.quests.from_dict(data)
        runs = data.get("dungeon_runs", {})
        self.dungeon_runs = {}
        if isinstance(runs, dict):
            for dungeon, run in runs.items():
                if isinstance(run, dict):
                    self.dungeon_runs[str(dungeon)] = {
                        "date": str(run.get("date", "")),
                        "count": max(0, _int(run.get("count", 0))),
                    }
        self.map_id = str(data.get("map", ""))
        self.storage = []
        saved = data.get("storage", [])
        for stack in saved if isinstance(saved, list) else []:
            entry = item_db.clean_stack(stack)
            if entry and len(self.storage) < self.storage_size():
                self.storage.append(entry)
        self.auto_potion = _int(data.get("auto_potion", 0))
        if self.auto_potion not in self.auto_potion_choices():
            self.auto_potion = 0

    def _start_fresh(self) -> None:
        self.equipment = {}
        for slot, item_id in self.rule("starting_gear").items():
            self.equipment[slot] = item_db.gear(item_id)
        self.bag = []
        for stack in self.rule("starting_bag"):
            self.add_item(stack["id"], _int(stack["count"]))

    def _stacks(self, item_id: str) -> bool:
        return item_db.items()[item_id].get("slot", "") == ""

    def _stack_index(self, item_id: str) -> int:
        for index, stack in enumerate(self.bag):
            if stack["id"] == item_id:
                return index
        return -1

    def _set_count(self, item_id: str, count: int) -> None:
        index = self._stack_index(item_id)
        if index < 0:
            self.add_item(item_id, count)
        elif count == 0:
            self.bag.pop(index)
        else:
            self.bag[index]["count"] = count
