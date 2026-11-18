"""One copy of a map on one channel (N11): the heroes and monsters in it, the
loot on the ground, and the timers (slams, shots, respawns). Ten times a second
it moves the monsters, then sends every hero what moved."""

from __future__ import annotations

import heapq
import itertools
import math

from ..data import roundi, table
from ..rules import combat
from ..rules import items as item_db
from ..rules.stats import character_rules
from .monster import Monster

PICK_REACH = 150.0  # loot magnet (90) plus the network delay
LOOT_SECONDS = 30.0
GEAR_LOOT_SECONDS = 60.0
DROPPED_SECONDS = 120.0
OWNER_SECONDS = 15.0  # loot belongs to the killer (and party) this long
PARTY_SHARE_DISTANCE = 1000.0
PVP_DAMAGE = 0.5  # heroes hit each other for half damage, so fights last


class Loot:
    def __init__(self, loot_id, kind, x, y, amount=0, stack=None, owners=None, free_at=0.0, expires=0.0, pick_after=0.0):
        self.id, self.kind, self.x, self.y = loot_id, kind, x, y
        self.amount, self.stack = amount, stack
        self.owners = owners  # hero ids, or None for anyone
        self.free_at, self.expires, self.pick_after = free_at, expires, pick_after

    def info(self) -> dict:
        info = {"id": self.id, "k": self.kind, "x": round(self.x, 1), "y": round(self.y, 1), "n": self.amount}
        if self.stack is not None:
            info["stack"] = self.stack
        return info


class Instance:
    def __init__(self, game, map_info, channel: int) -> None:
        self.game = game
        self.map = map_info
        self.channel = channel
        self.heroes: dict = {}
        self.monsters: dict = {}
        self.loot: dict = {}
        self._ids = itertools.count(1)
        self._timers: list = []
        self._order = itertools.count()
        for monster_id, x, y in map_info.monsters:
            self.add_monster(monster_id, x, y, announce=False)

    @property
    def now(self) -> float:
        return self.game.now

    @property
    def rng(self):
        return self.game.rng

    def elite_chance(self) -> float:
        return self.game.elite_chance

    def new_id(self) -> int:
        return next(self._ids)

    def schedule(self, at: float, callback) -> None:
        heapq.heappush(self._timers, (at, next(self._order), callback))

    def broadcast(self, message: dict, exclude=None) -> None:
        for hero in list(self.heroes.values()):
            if hero is not exclude:
                hero.send(message)

    # --- monsters

    def add_monster(self, monster_id: str, x: float, y: float, respawns: bool = True, announce: bool = True) -> Monster:
        monster = Monster(self, self.new_id(), monster_id, x, y, respawns)
        self.monsters[monster.id] = monster
        if announce:
            self.broadcast({"t": "mspawn", "m": monster.info()})
        return monster

    def remove_monster(self, monster: Monster) -> None:
        if self.monsters.pop(monster.id, None) is not None:
            self.broadcast({"t": "mgone", "id": monster.id})

    # --- heroes coming and going

    def add_hero(self, hero, x: float, y: float) -> None:
        hero.inst = self
        hero.x, hero.y = self.map.clamp(x, y)
        hero.last_move = None
        hero.changed = True
        hero.stats.map_id = self.map.id
        self.heroes[hero.id] = hero
        self.broadcast({"t": "pjoin", "p": hero.public()}, exclude=hero)
        hero.char_dirty = False
        hero.send(self.enter_message(hero))

    def enter_message(self, hero) -> dict:
        return {
            "t": "enter", "map": self.map.id, "ch": self.channel, "x": round(hero.x, 1), "y": round(hero.y, 1),
            "you": hero.id, "char": hero.stats.to_dict(), "hp": hero.hp, "mhp": hero.max_hp(),
            "st": roundi(hero.stamina), "mst": roundi(hero.stats.max_stamina()), "dead": hero.dead,
            "players": [h.public() for h in self.heroes.values() if h is not hero],
            "monsters": [m.info() for m in self.monsters.values()],
            "loot": [loot.info() for loot in self.loot.values()],
        }

    def remove_hero(self, hero) -> None:
        if self.heroes.pop(hero.id, None) is None:
            return
        for monster in self.monsters.values():
            monster.threat.pop(hero.id, None)
        self.broadcast({"t": "pgone", "id": hero.id})
        hero.inst = None

    # --- the tick

    def tick(self, now: float, dt: float) -> None:
        for monster in list(self.monsters.values()):
            monster.step(now, dt)
        for hero in list(self.heroes.values()):
            hero.tick(now, dt)
            if hero.dead and now >= hero.died_at + float(character_rules()["respawn_seconds"]):
                self.revive(hero, *self.map.spawn())
        while self._timers and self._timers[0][0] <= now:
            _, _, callback = heapq.heappop(self._timers)
            callback()
        for loot in list(self.loot.values()):
            if now >= loot.expires:
                self.remove_loot(loot)
        self._send_snapshot()

    def _send_snapshot(self) -> None:
        heroes = [h for h in self.heroes.values() if h.changed]
        monster_rows = [m.snapshot() for m in self.monsters.values() if m.changed]
        if not heroes and not monster_rows:
            return
        for viewer in list(self.heroes.values()):
            hero_rows = [h.snapshot() for h in heroes if h is not viewer]
            if hero_rows or monster_rows:
                viewer.send({"t": "snap", "p": hero_rows, "m": monster_rows})
        for hero in heroes:
            hero.changed = False
        for monster in self.monsters.values():
            monster.changed = False

    # --- damage to heroes, death and getting up

    def hurt_hero(self, hero, hit: dict, by) -> None:
        """A hit on a hero, already worked out. by: the monster or hero, or None."""
        if hero.dead:
            return
        now = self.now
        poison = hit.get("poison", False)
        if not poison and now < hero.invincible_until:
            return
        if hit["miss"]:
            self.broadcast({"t": "dmg", "p": hero.id, "n": 0, "crit": False, "miss": True, "hp": hero.hp})
            return
        damage = hit["damage"]
        cut = hero.guard_cut(now)
        if cut > 0.0 and not poison:
            damage = max(1, roundi(damage * (1.0 - cut)))
        if hero.duel is not None and by is not None and by is hero.duel.other(hero):
            damage = min(damage, hero.hp - 1)  # a duel ends at 1 HP, not in death
        hero.hp = max(hero.hp - damage, 0)
        hero.last_hurt = now
        if not poison:
            hero.invincible_until = now + float(character_rules()["hit_invincible_seconds"])
        self.broadcast(
            {"t": "dmg", "p": hero.id, "n": damage, "crit": hit["crit"], "miss": False, "hp": hero.hp, "poison": poison}
        )
        if hero.duel is not None and hero.hp <= 1 and by is hero.duel.other(hero):
            self.game.social.duel_over(hero.duel, winner=by)
        elif hero.hp <= 0:
            self.hero_died(hero)

    def hero_died(self, hero) -> None:
        hero.dead = True
        hero.died_at = self.now
        hero.statuses.clear()
        hero.casts.clear()
        hero.anim = "die"
        hero.changed = True
        self.broadcast({"t": "die", "id": hero.id})
        if hero.duel is not None:
            self.game.social.duel_over(hero.duel, winner=hero.duel.other(hero))

    def revive(self, hero, x: float, y: float) -> None:
        hero.x, hero.y = self.map.clamp(x, y)
        hero.hp = hero.max_hp()
        hero.stamina = hero.stats.max_stamina()
        hero.dead = False
        hero.invincible_until = 0.0
        hero.anim = "idle"
        hero.last_move = None
        hero.changed = True
        self.broadcast({"t": "revive", "id": hero.id, "x": round(hero.x, 1), "y": round(hero.y, 1), "hp": hero.hp})
        hero.announce(hero.stats.record.count("deaths", 1, hero.stats.level))
        hero.char_changed()

    # --- a hero's hits (after cast() was accepted)

    def land_hits(self, hero, kind: str, monster_ids: list, hero_ids: list) -> None:
        now = self.now
        cast = hero.open_cast(kind, now)
        if cast is None or hero.dead:
            return
        for monster_id in monster_ids:
            monster = self.monsters.get(monster_id)
            if cast.hits_left <= 0:
                break
            if monster is None or monster.dead or hero.distance_to(monster.x, monster.y) > cast.reach:
                continue
            cast.hits_left -= 1
            boosted = roundi(cast.base * hero.damage_factor(now))
            hit = combat.resolve_hit(boosted, hero.crit_chance(now), monster.defense, monster.evasion, self.rng)
            monster.take_hit(hero, hit, cast.knockback, cast.status)
        for hero_id in hero_ids:
            target = self.heroes.get(hero_id)
            if cast.hits_left <= 0:
                break
            if target is None or target.dead or target is hero or not self.game.social.may_fight(hero, target):
                continue
            if hero.distance_to(target.x, target.y) > cast.reach:
                continue
            cast.hits_left -= 1
            boosted = roundi(cast.base * hero.damage_factor(now) * PVP_DAMAGE)
            hit = combat.resolve_hit(boosted, hero.crit_chance(now), target.stats.defense(), target.stats.evasion(), self.rng)
            self.hurt_hero(target, hit, hero)

    # --- rewards

    def monster_killed(self, monster: Monster, killer) -> None:
        if killer is None:
            return
        sharers = [
            h for h in self.game.social.party_members(killer)
            if h.inst is self and not h.dead and h.distance_to(monster.x, monster.y) <= PARTY_SHARE_DISTANCE
        ] or [killer]
        if killer not in sharers:
            sharers.append(killer)
        share = monster.xp if len(sharers) == 1 else roundi(monster.xp * (1.0 + 0.1 * (len(sharers) - 1)) / len(sharers))
        for hero in sharers:
            hero.gain_xp(share)
        killer.record_kill(monster.monster_id, monster.elite)
        owners = frozenset(h.id for h in sharers)
        low, high = monster.gold
        self.drop(monster.x, monster.y, "gold", amount=self.rng.randint(low, high), owners=owners)
        for drop in monster.drops:
            if _for_class(drop["item"], killer.stats.class_id) and self.rng.random() < float(drop["chance"]):
                self.drop(monster.x, monster.y, "item", amount=1, stack={"id": drop["item"], "count": 1}, owners=owners)
        self._maybe_drop_gear(monster, killer, owners)
        if monster.boss:
            self.broadcast({"t": "banner", "text": f"{monster.name} is defeated!", "sub": ""})

    def _maybe_drop_gear(self, monster: Monster, killer, owners) -> None:
        pool = [i for i in monster.gear_drops.get("items", []) if _for_class(i, killer.stats.class_id)]
        chance = float(monster.gear_drops.get("chance", 0.0))
        rolls = int(monster.boss.get("rarity_rolls", 1))
        if monster.elite:
            elite = combat.settings()["elite"]
            chance += float(elite.get("gear_chance", 0.0))
            rolls = int(elite.get("rarity_rolls", 1))
        if pool and self.rng.random() < chance:
            piece = item_db.roll_gear(self.rng.choice(pool), rolls, self.rng)
            self.drop(monster.x, monster.y, "item", amount=1, stack=piece, owners=owners, lifetime=GEAR_LOOT_SECONDS)

    # --- loot on the ground

    def drop(self, x, y, kind, amount=0, stack=None, owners=None, lifetime=LOOT_SECONDS, delay=0.0, spread=True) -> Loot:
        if spread:
            x, y = x + self.rng.uniform(-24, 24), y + self.rng.uniform(-16, 16)
        x, y = self.map.clamp(x, y)
        now = self.now
        loot = Loot(self.new_id(), kind, x, y, amount, stack, owners, now + OWNER_SECONDS, now + lifetime, now + delay)
        self.loot[loot.id] = loot
        self.broadcast({"t": "loot", "l": loot.info()})
        return loot

    def remove_loot(self, loot: Loot) -> None:
        if self.loot.pop(loot.id, None) is not None:
            self.broadcast({"t": "unloot", "id": loot.id})

    def pick(self, hero, loot_id) -> None:
        loot = self.loot.get(loot_id)
        now = self.now
        if loot is None or hero.dead or now < loot.pick_after or hero.distance_to(loot.x, loot.y) > PICK_REACH:
            return
        if loot.owners is not None and hero.id not in loot.owners and now < loot.free_at:
            hero.say("That is not yours yet.", "warn")
            return
        if loot.kind == "gold":
            hero.stats.gold += loot.amount
            hero.fx("gold", f"+{loot.amount} G", "gold")
            hero.say(f"+{loot.amount} gold", "gold")
            hero.announce(hero.stats.record.count("gold_earned", loot.amount, hero.stats.level))
        else:
            stack = loot.stack or {}
            if not hero.stats.add_stack(stack):
                hero.say("Your bag is full.", "warn")
                return
            if item_db.is_gear(stack["id"]):
                text = item_db.display_name(stack, True)
                hero.say(f"Picked up {text}.", "rarity:" + stack.get("rarity", "common"))
            else:
                count = int(stack.get("count", 1))
                text = item_db.items()[stack["id"]]["name"] + (f" x{count}" if count > 1 else "")
                hero.say(f"Picked up {text}.")
            hero.fx("item", "+" + text, "rarity:" + stack.get("rarity", "common"))
        hero.char_changed()
        self.remove_loot(loot)


def _for_class(item_id: str, class_id: str) -> bool:
    """Loot is for the killer's class: no gear it cannot wear, no other class's books."""
    item = item_db.items().get(item_id, {})
    if "teaches" in item:
        return table("skills")[item["teaches"]].get("class", "warrior") == class_id
    return item_db.usable_by(item_id, class_id)


def distance(a, b) -> float:
    return math.dist((a.x, a.y), (b.x, b.y))
