"""A hero in the online world: the character (rules.stats.Stats) plus what only
matters while playing: where it is, HP and stamina, cooldowns, buffs, statuses,
and the attacks it may still land. The server checks every attack and skill
here: cooldown, cost, level and reach (N2, N12)."""

from __future__ import annotations

import math
from dataclasses import dataclass

from ..data import roundi, table
from ..rules import combat
from ..rules import items as item_db
from ..rules.stats import POTION_ID, Stats, character_rules
from .statuses import Statuses

# How long the server waits for the hits of an attack, and how much farther
# than its range a target may be (the client and server see positions a
# little apart because of the network delay).
REACH_SLACK = 80.0
COOLDOWN_SLACK = 0.12
STAMINA_SLACK = 2.0
# skill type -> (hits per cast, seconds the hits may come in, default knockback)
SKILL_HITS = {
    "spin": (15, 0.8, 1.0),
    "strike": (1, 0.8, 2.5),
    "slam": (15, 0.8, 1.5),
    "cleave": (15, 0.8, 3.0),
    "bolt": (10, 2.5, 1.0),
    "nova": (15, 0.8, 1.2),
    "meteor": (15, 2.5, 2.0),
    "fan": (5, 2.5, 0.6),
    "pierce": (15, 2.5, 1.0),
    "rain": (60, 3.5, 0.4),
    "chain": (6, 1.0, 0.8),
}


@dataclass
class Cast:
    kind: str  # "attack" or a skill id
    base: int  # damage before buffs, crit and defense
    hits_left: int
    until: float
    reach: float
    knockback: float
    status: dict | None = None


class Hero:
    def __init__(self, game, char_id: int, account_id: int, slot: int, stats: Stats, session=None):
        self.game = game
        self.id = char_id
        self.account_id = account_id
        self.slot = slot
        self.stats = stats
        self.session = session
        self.inst = None
        self.x = self.y = 0.0
        self.facing, self.anim = "down", "idle"
        self.changed = True
        self.hp = stats.max_hp()
        self.stamina = stats.max_stamina()
        self.dead = False
        self.died_at = 0.0
        self.statuses = Statuses()
        self.last_hurt = -1000.0
        self._regen_carry = 0.0
        self.invincible_until = 0.0
        self.cooldowns: dict = {}
        self.casts: list = []
        self.combo_step = 0
        self.combo_until = 0.0
        self.damage_bonus = (0.0, 0.0)  # (value, until)
        self.crit_bonus = (0.0, 0.0)
        self.guard = (0.0, 0.0)
        self.dash_until = 0.0
        self.last_move = None
        self.bad_moves: list = []
        self.auto_potion_ready = 0.0
        self.party = None
        self.trade = None
        self.duel = None
        self.guild_id = None
        self.guild_name = ""
        self.dirty = False
        self.char_dirty = True
        self._vitals_sent = None

    @property
    def name(self) -> str:
        return self.stats.hero_name

    # --- talking to the client

    def send(self, message: dict) -> None:
        if self.session is not None:
            self.session.send(message)

    def say(self, text: str, color: str = "") -> None:
        self.send({"t": "msg", "text": text, "c": color})

    def fx(self, kind: str, text: str = "", color: str = "") -> None:
        """An effect on the hero's screen (floating text, sound, sparks)."""
        self.send({"t": "fx", "k": kind, "text": text, "c": color})

    def char_changed(self) -> None:
        """The character changed: resend it, and save it soon."""
        self.char_dirty = True
        self.dirty = True

    def flush(self) -> None:
        """Sends what changed since the last tick: the character and HP/stamina."""
        if self.char_dirty:
            self.char_dirty = False
            self.send({"t": "char", "data": self.stats.to_dict()})
        vitals = (self.hp, self.max_hp(), roundi(self.stamina), roundi(self.stats.max_stamina()))
        if vitals != self._vitals_sent:
            self._vitals_sent = vitals
            self.send({"t": "me", "hp": vitals[0], "mhp": vitals[1], "st": vitals[2], "mst": vitals[3]})

    def public(self) -> dict:
        """What other players see."""
        return {
            "id": self.id, "name": self.name, "cls": self.stats.class_id, "adv": self.stats.advanced,
            "lvl": self.stats.level, "x": round(self.x, 1), "y": round(self.y, 1), "f": self.facing,
            "a": self.anim, "hp": self.hp, "mhp": self.max_hp(), "dead": self.dead,
            "guild": self.guild_name, "title": self._title_name(),
            "eq": {slot: {"id": s["id"], "rarity": s.get("rarity", "common")} for slot, s in self.stats.equipment.items()},
        }

    def snapshot(self) -> list:
        return [self.id, round(self.x, 1), round(self.y, 1), self.facing, self.anim]

    def _title_name(self) -> str:
        title = self.stats.record.title
        return self.stats.record.list()[title]["title"] if title else ""

    # --- numbers

    def max_hp(self) -> int:
        return self.stats.max_hp()

    def limits_changed(self) -> None:
        self.hp = min(self.hp, self.max_hp())
        self.stamina = min(self.stamina, self.stats.max_stamina())

    def move_speed(self) -> float:
        return float(self.stats.rule("move_speed"))

    def damage_factor(self, now: float) -> float:
        value, until = self.damage_bonus
        return 1.0 + (value if now < until else 0.0)

    def crit_chance(self, now: float) -> float:
        value, until = self.crit_bonus
        return self.stats.crit_chance() + (value if now < until else 0.0)

    def guard_cut(self, now: float) -> float:
        value, until = self.guard
        return value if now < until else 0.0

    # --- every tick

    def tick(self, now: float, dt: float) -> None:
        if self.dead:
            return
        poison = self.statuses.update(dt)
        if poison > 0:
            self.inst.hurt_hero(self, {"damage": poison, "crit": False, "miss": False, "poison": True}, None)
            if self.dead:
                return
        rules = character_rules()
        regen = float(self.stats.rule("stamina_regen_per_second"))
        self.stamina = min(self.stats.max_stamina(), self.stamina + regen * dt)
        if now - self.last_hurt >= float(rules["regen_delay_seconds"]) and self.hp < self.max_hp():
            self._regen_carry += float(rules["regen_hp_per_second"]) * dt
            whole = int(self._regen_carry)
            self._regen_carry -= whole
            self.hp = min(self.max_hp(), self.hp + whole)
        self.casts = [cast for cast in self.casts if cast.until >= now and cast.hits_left > 0]
        self._auto_potion(now)

    def _auto_potion(self, now: float) -> None:
        percent = self.stats.auto_potion
        if percent <= 0 or now < self.auto_potion_ready or self.stats.potions <= 0:
            return
        if self.hp * 100 < self.max_hp() * percent:
            self.auto_potion_ready = now + float(character_rules()["auto_potion_seconds"])
            self.drink_potion()

    def drink_potion(self) -> bool:
        if self.dead or self.stats.potions <= 0 or self.hp >= self.max_hp():
            return False
        self.stats.remove_items(POTION_ID, 1)
        fraction = float(item_db.items()[POTION_ID]["heal_fraction"])
        healed = min(roundi(self.max_hp() * fraction), self.max_hp() - self.hp)
        self.hp += healed
        self.fx("potion", f"+{healed}", "heal")
        self.announce(self.stats.record.count("potions_used", 1, self.stats.level))
        self.char_changed()
        return True

    def add_status(self, effect: str, seconds: float, value: float = 0.0) -> None:
        if self.dead:
            return
        self.statuses.apply(effect, seconds, value)
        self.send({"t": "status", "st": effect, "s": seconds, "v": value})

    def announce(self, earned: list) -> None:
        """Tells the player about achievements just earned."""
        for achievement_id in earned:
            achievement = self.stats.record.list()[achievement_id]
            self.say(f'Achievement: {achievement["name"]}! Title "{achievement["title"]}".', "ach")
        if earned:
            self.fx("achievement", "ACHIEVEMENT!", "ach")
            self.limits_changed()
            self.char_changed()

    def gain_xp(self, amount: int) -> None:
        levels = self.stats.add_xp(amount)
        self.say(f"+{amount} EXP", "xp")
        if levels > 0:
            self.hp = self.max_hp()
            self.fx("levelup", "LEVEL UP!", "level")
            self.say(f"Level up! You are now level {self.stats.level}.", "level")
            self.say(f"{self.stats.free_points()} stat points to spend: open STATS (C).", "level")
            self.announce(self.stats.record.check(self.stats.level))
            if self.inst is not None:
                self.inst.broadcast({"t": "lvl", "id": self.id, "lvl": self.stats.level}, exclude=self)
        self.char_changed()

    def record_kill(self, monster_id: str, elite: bool) -> None:
        """Quest kill counts and achievement counters of the hero who got the kill."""
        quests = self.stats.quests
        for quest_id in quests.on_kill(monster_id):
            counted, needed = quests.progress(quest_id, self.stats), quests.goal_count(quest_id)
            self.say(f"{quests.list()[quest_id]['name']} {counted}/{needed}", "quest")
        level = self.stats.level
        earned = self.stats.record.count("kills", 1, level)
        earned += self.stats.record.count("kills:" + monster_id, 1, level)
        if elite:
            earned += self.stats.record.count("elite_kills", 1, level)
        self.announce(earned)
        self.char_changed()

    # --- attacks and skills (checked here, landed by the instance)

    def cast(self, kind: str, now: float) -> str:
        """Starts an attack ("attack") or a skill. Returns why not, or ""."""
        if self.dead:
            return "dead"
        if self.statuses.active("stun"):
            return "stunned"
        if kind == "attack":
            return self._cast_attack(now)
        skills = table("skills")
        skill = skills.get(kind)
        if skill is None or skill.get("class", "warrior") != self.stats.class_id:
            return "unknown skill"
        if self.stats.level < int(skill.get("unlock_level", 1)):
            return "locked"
        if "book" in skill and not self.stats.knows_skill(kind):
            return "locked"
        if skill.get("job", False) and not self.stats.advanced:
            return "locked"
        if now < self.cooldowns.get(kind, 0.0) - COOLDOWN_SLACK:
            return "cooldown"
        cost = float(skill.get("stamina", 0.0))
        if self.stamina < cost - STAMINA_SLACK:
            return "stamina"
        self.stamina = max(0.0, self.stamina - cost)
        self.cooldowns[kind] = now + float(skill["cooldown"])
        self.announce(self.stats.record.count("skills_used", 1, self.stats.level))
        kind_of = skill["type"]
        if kind_of == "buff":
            seconds = float(skill["seconds"])
            if "damage_bonus" in skill:
                self.damage_bonus = (float(skill["damage_bonus"]), now + seconds)
            if "crit_bonus" in skill:
                self.crit_bonus = (float(skill["crit_bonus"]), now + seconds)
            return ""
        if kind_of == "shield":
            self.guard = (min(max(float(skill["damage_cut"]), 0.0), 0.9), now + float(skill["seconds"]))
            return ""
        hits, seconds, knockback = SKILL_HITS.get(kind_of, (10, 2.5, 1.0))
        reach = self._skill_reach(skill)
        status = None
        if "stun_seconds" in skill:
            status = {"effect": "stun", "seconds": float(skill["stun_seconds"])}
        elif "slow_seconds" in skill:
            status = {"effect": "slow", "seconds": float(skill["slow_seconds"]), "value": float(skill.get("slow", 0.5))}
        self.casts.append(
            Cast(kind, self.skill_damage(skill), hits, now + seconds + float(skill.get("delay", 0.0)),
                 reach, float(skill.get("knockback", knockback)), status)
        )
        return ""

    def _cast_attack(self, now: float) -> str:
        cooldown = float(self.stats.rule("attack_cooldown"))
        if now < self.cooldowns.get("attack", 0.0) - COOLDOWN_SLACK:
            return "cooldown"
        self.cooldowns["attack"] = now + cooldown
        settings = combat.settings()
        self.combo_step = self.combo_step % 3 + 1 if now <= self.combo_until else 1
        self.combo_until = now + float(settings["combo_window_seconds"])
        base = self.stats.attack_damage()
        finisher = self.combo_step == 3
        if finisher:
            base = roundi(base * float(settings["combo_finisher_multiplier"]))
        reach = float(self.stats.rule("attack_range"))
        if self._class_attack()["type"] == "shot":
            self.casts.append(Cast("attack", base, 1, now + 2.5, reach + 60 + REACH_SLACK, 1.6 if finisher else 0.6))
        else:
            knockback = float(settings["combo_finisher_knockback"]) if finisher else 1.0
            self.casts.append(Cast("attack", base, 10, now + 0.8, reach + REACH_SLACK, knockback))
        return ""

    def _class_attack(self) -> dict:
        return table("classes")["classes"][self.stats.class_id]["attack"]

    def skill_damage(self, skill: dict) -> int:
        multiplier = float(skill["damage_multiplier"]) * (1.0 + self.stats.skill_damage_bonus())
        return roundi(self.stats.attack_damage() * multiplier)

    @staticmethod
    def _skill_reach(skill: dict) -> float:
        reach = float(skill.get("range", 0.0)) + float(skill.get("radius", 0.0))
        reach += float(skill.get("blast_radius", 0.0))
        reach += float(skill.get("jump_range", 0.0)) * float(skill.get("jumps", 0))
        return reach + REACH_SLACK

    def open_cast(self, kind: str, now: float) -> Cast | None:
        """The oldest attack of this kind that may still land a hit."""
        for cast in self.casts:
            if cast.kind == kind and cast.hits_left > 0 and cast.until >= now:
                return cast
        return None

    def dash(self, now: float) -> bool:
        dash = self.stats.rule("dash")
        cost = float(dash["stamina"])
        if self.dead or self.statuses.active("stun") or now < self.cooldowns.get("dash", 0.0) - COOLDOWN_SLACK:
            return False
        if self.stamina < cost - STAMINA_SLACK:
            return False
        self.stamina = max(0.0, self.stamina - cost)
        self.cooldowns["dash"] = now + float(dash["cooldown"])
        seconds = float(dash["seconds"])
        self.dash_until = now + seconds + 0.35
        self.invincible_until = max(self.invincible_until, now + seconds)
        return True

    def allowed_step(self, now: float, seconds: float) -> float:
        """How far the hero may have walked in this many seconds (N12)."""
        speed = self.move_speed()
        if now <= self.dash_until:
            speed *= float(self.stats.rule("dash")["speed_multiplier"])
        return speed * min(seconds, 1.5) * 1.35 + 40.0

    def distance_to(self, x: float, y: float) -> float:
        return math.dist((self.x, self.y), (x, y))
