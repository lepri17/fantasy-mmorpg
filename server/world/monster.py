"""A monster on the server: client/scripts/enemies/slime.gd without the drawing.
It wanders near home, chases the nearest hero (or whoever hurt it most), gives
up past the leash, attacks, slams after a warning, shoots, enrages and calls
help (bosses), and comes back after it dies. Numbers from monsters.json."""

from __future__ import annotations

import math

from ..data import roundi, table
from ..rules import combat
from .statuses import Statuses

WANDER_RADIUS = 90.0
LEASH_RADIUS = 480.0
KNOCKBACK_SPEED = 240.0
KNOCKBACK_DECAY = 1400.0
ATTACK_ANIMATION = 0.4
DODGE_DISTANCE = 48.0


def facing_for(dx: float, dy: float) -> str:
    if abs(dx) > abs(dy):
        return "right" if dx > 0 else "left"
    return "down" if dy > 0 else "up"


class Monster:
    def __init__(self, inst, net_id: int, monster_id: str, x: float, y: float, respawns: bool = True):
        self.inst = inst
        self.id = net_id
        self.monster_id = monster_id
        self.home = (x, y)
        self.x, self.y = x, y
        self.respawns = respawns
        self.statuses = Statuses()
        self.dead = False
        self.respawn_at = 0.0
        self.threat: dict = {}  # hero id -> damage done
        self.knock = (0.0, 0.0)
        self.facing, self.anim, self.anim_until = "down", "idle", 0.0
        self.changed = True  # position or animation, for the next snapshot
        self.minions: list = []
        self._reset(inst.now)

    # --- data

    def _reset(self, now: float) -> None:
        data = table("monsters")[self.monster_id]
        self.name = data["name"]
        self.level = int(data["level"])
        self.max_hp = int(data["max_hp"])
        self.move_speed = float(data["move_speed"])
        self.detect_radius = float(data["detect_radius"])
        self.attack_range = float(data["attack_range"])
        self.attack_damage = int(data["attack_damage"])
        self.defense = int(data.get("defense", 0))
        self.evasion = float(data.get("evasion", 0.0))
        self.attack_cooldown = float(data["attack_cooldown"])
        self.respawn_seconds = float(data["respawn_seconds"])
        self.xp = int(data["xp"])
        self.gold = (int(data["gold"][0]), int(data["gold"][1]))
        self.drops = list(data.get("drops", []))
        self.gear_drops = data.get("gear_drops", {})
        self.ranged = data.get("ranged", {})
        self.on_hit = data.get("on_hit", {})
        self.special = data.get("special", {})
        self.boss = data.get("boss", {})
        self.elite = False
        self.attack_ready = now + self.attack_cooldown
        self.attack_count = 0
        self.casting_until = 0.0
        self.returning = False
        self.wander_target = self.home
        self.wander_timer = 0.0
        self.enraged = False
        self.summon_at = 0.0
        if not self.boss and self.inst.rng.random() < self.inst.elite_chance():
            self.make_elite()
        self.hp = self.max_hp

    def make_elite(self) -> None:
        if self.elite:
            return
        elite = combat.settings()["elite"]
        self.elite = True
        self.max_hp = roundi(self.max_hp * float(elite["hp"]))
        self.hp = self.max_hp
        self.attack_damage = roundi(self.attack_damage * float(elite["damage"]))
        self.xp = roundi(self.xp * float(elite["xp"]))
        self.gold = (roundi(self.gold[0] * float(elite["gold"])), roundi(self.gold[1] * float(elite["gold"])))
        self.drops = self.drops + list(elite.get("extra_drops", []))
        self.name = "Elite " + self.name

    def info(self) -> dict:
        """What a client needs to draw it."""
        return {
            "id": self.id, "mid": self.monster_id, "x": round(self.x, 1), "y": round(self.y, 1),
            "hp": self.hp, "mhp": self.max_hp, "elite": self.elite, "dead": self.dead,
            "minion": not self.respawns,
        }

    def snapshot(self) -> list:
        return [self.id, round(self.x, 1), round(self.y, 1), self.facing, self.anim]

    # --- the brain, ten times a second

    def step(self, now: float, dt: float) -> None:
        if self.dead:
            if self.respawns and now >= self.respawn_at:
                self.respawn(now)
            return
        self.statuses.update(dt)
        if self.enraged:
            self._summon_tick(now)
        stunned = self.statuses.active("stun")
        vx = vy = 0.0
        target = None if stunned else self._chase_target()
        if stunned or now < self.casting_until:
            pass
        elif target is None:
            vx, vy = self._wander(dt)
        else:
            distance = math.dist((self.x, self.y), (target.x, target.y))
            speed = self.move_speed * self.statuses.speed_factor()
            if self.ranged:
                vx, vy = self._ranged_move(target, distance, speed, now)
            elif distance > self.attack_range:
                vx, vy = self._toward(target.x, target.y, speed)
            elif now >= self.attack_ready:
                self._attack(target, now)
        kx, ky = self.knock
        moved = self._move(vx + kx, vy + ky, dt)
        if self.knock != (0.0, 0.0):
            length = math.hypot(kx, ky)
            left = max(0.0, length - KNOCKBACK_DECAY * dt)
            self.knock = (kx / length * left, ky / length * left) if left > 0 else (0.0, 0.0)
        if self.anim != "attack" or now >= self.anim_until:
            self._set_anim("walk" if moved else "idle")

    def _chase_target(self):
        from_home = math.dist((self.x, self.y), self.home)
        if from_home > LEASH_RADIUS:
            self.returning = True
        elif from_home <= WANDER_RADIUS:
            self.returning = False
        if self.returning:
            self.threat.clear()
            return None
        best, best_threat = None, 0
        for hero_id, threat in list(self.threat.items()):
            hero = self.inst.heroes.get(hero_id)
            if hero is None or hero.dead:
                del self.threat[hero_id]
            elif threat > best_threat:
                best, best_threat = hero, threat
        if best is not None:
            return best
        nearest, nearest_distance = None, self.detect_radius
        for hero in self.inst.heroes.values():
            distance = math.dist((self.x, self.y), (hero.x, hero.y))
            if not hero.dead and distance <= nearest_distance:
                nearest, nearest_distance = hero, distance
        return nearest

    def _wander(self, dt: float) -> tuple[float, float]:
        if math.dist((self.x, self.y), self.home) > WANDER_RADIUS:
            return self._toward(*self.home, self.move_speed)
        self.wander_timer -= dt
        rng = self.inst.rng
        if self.wander_timer <= 0.0:
            self.wander_timer = rng.uniform(1.5, 3.5)
            self.wander_target = (self.x, self.y)
            if rng.random() < 0.6:
                self.wander_target = (
                    self.home[0] + rng.uniform(-1.0, 1.0) * WANDER_RADIUS * 0.7,
                    self.home[1] + rng.uniform(-1.0, 1.0) * WANDER_RADIUS * 0.7,
                )
        if math.dist((self.x, self.y), self.wander_target) < 4.0:
            return 0.0, 0.0
        return self._toward(*self.wander_target, self.move_speed * 0.5)

    def _toward(self, x: float, y: float, speed: float) -> tuple[float, float]:
        dx, dy = x - self.x, y - self.y
        length = math.hypot(dx, dy)
        if length < 1.0:
            return 0.0, 0.0
        return dx / length * speed, dy / length * speed

    def _move(self, vx: float, vy: float, dt: float) -> bool:
        """Walks, sliding around trees and rocks. Returns True if it moved."""
        sx, sy = vx * dt, vy * dt
        if abs(sx) < 0.01 and abs(sy) < 0.01:
            return False
        nx, ny = self.x + sx, self.y + sy
        for ox, oy, radius in self.inst.map.obstacles:
            dx, dy = nx - ox, ny - oy
            if dx * dx + dy * dy >= radius * radius:
                continue
            length = math.hypot(dx, dy) or 0.001
            rx, ry = dx / length, dy / length
            tx, ty = -ry, rx
            if tx * sx + ty * sy < 0:
                tx, ty = -tx, -ty
            step = math.hypot(sx, sy) * 0.8
            nx, ny = ox + rx * radius + tx * step, oy + ry * radius + ty * step
        nx, ny = self.inst.map.clamp(nx, ny)
        if math.hypot(nx - self.x, ny - self.y) < 0.01:
            return False
        if abs(vx) + abs(vy) > 1.0:
            self.facing = facing_for(vx, vy)
        self.x, self.y = nx, ny
        self.changed = True
        return True

    def _set_anim(self, anim: str, seconds: float = 0.0) -> None:
        if anim != self.anim:
            self.anim = anim
            self.changed = True
        if seconds:
            self.anim_until = self.inst.now + seconds

    # --- attacks

    def _attack(self, target, now: float) -> None:
        self.attack_ready = now + self.attack_cooldown
        self.attack_count += 1
        self._set_anim("attack", ATTACK_ANIMATION)
        self.facing = facing_for(target.x - self.x, target.y - self.y)
        self.inst.broadcast({"t": "matk", "id": self.id})
        if self.special and self.attack_count % int(self.special["every"]) == 0:
            self._start_slam(now)
            return
        hit = combat.resolve_hit(self.attack_damage, 0.0, target.stats.defense(), target.stats.evasion(), self.inst.rng)
        self.inst.hurt_hero(target, hit, self)
        if not hit["miss"] and self.on_hit and self.inst.rng.random() < float(self.on_hit["chance"]):
            target.add_status(self.on_hit["status"], float(self.on_hit["seconds"]), float(self.on_hit.get("value", 0.0)))

    def _start_slam(self, now: float) -> None:
        warning = float(self.special["warning_seconds"])
        radius = float(self.special["radius"])
        center = (self.x, self.y)
        self.casting_until = now + warning
        self.inst.broadcast({"t": "tele", "x": round(center[0], 1), "y": round(center[1], 1), "r": radius, "s": warning})
        damage = roundi(self.attack_damage * float(self.special["damage_multiplier"]))

        def land() -> None:
            if self.dead:
                return
            for hero in list(self.inst.heroes.values()):
                if not hero.dead and math.dist((hero.x, hero.y), center) <= radius:
                    hit = combat.resolve_hit(damage, 0.0, hero.stats.defense(), 0.0, self.inst.rng)
                    self.inst.hurt_hero(hero, hit, self)

        self.inst.schedule(now + warning, land)

    def _ranged_move(self, target, distance: float, speed: float, now: float) -> tuple[float, float]:
        if distance <= self.attack_range and now >= self.attack_ready:
            self._shoot(target, now)
        if distance > self.attack_range:
            return self._toward(target.x, target.y, speed)
        if distance < float(self.ranged.get("keep_distance", 0.0)):
            vx, vy = self._toward(target.x, target.y, speed)
            return -vx, -vy
        return 0.0, 0.0

    def _shoot(self, target, now: float) -> None:
        self.attack_ready = now + self.attack_cooldown
        self._set_anim("attack", ATTACK_ANIMATION)
        speed = float(self.ranged.get("projectile_speed", 260.0))
        aim = (target.x, target.y)
        travel = math.dist((self.x, self.y), aim) / speed
        self.inst.broadcast(
            {"t": "mshot", "id": self.id, "x": round(self.x, 1), "y": round(self.y, 1),
             "tx": round(aim[0], 1), "ty": round(aim[1], 1), "sp": speed}
        )
        on_hit = self.ranged.get("on_hit", {})

        def land() -> None:
            if target.dead or self.inst.heroes.get(target.id) is not target:
                return
            if math.dist((target.x, target.y), aim) > DODGE_DISTANCE:
                return  # it walked out of the way
            hit = combat.resolve_hit(self.attack_damage, 0.0, target.stats.defense(), target.stats.evasion(), self.inst.rng)
            self.inst.hurt_hero(target, hit, self)
            if not hit["miss"] and on_hit and self.inst.rng.random() < float(on_hit["chance"]):
                target.add_status(on_hit["status"], float(on_hit["seconds"]), float(on_hit.get("value", 0.0)))

        self.inst.schedule(now + travel, land)

    # --- taking hits, dying, coming back

    def take_hit(self, hero, hit: dict, knockback: float, status: dict | None) -> None:
        """A hero's hit, already worked out (miss, crit, defense)."""
        if self.dead:
            return
        if not hit["miss"]:
            self.hp = max(self.hp - hit["damage"], 0)
            self.threat[hero.id] = self.threat.get(hero.id, 0) + hit["damage"]
            dx, dy = self.x - hero.x, self.y - hero.y
            length = math.hypot(dx, dy) or 1.0
            push = KNOCKBACK_SPEED * knockback
            self.knock = (dx / length * push, dy / length * push)
            if status and self.hp > 0:
                self.statuses.apply(status["effect"], float(status["seconds"]), float(status.get("value", 0.0)))
        self.inst.broadcast(
            {"t": "dmg", "m": self.id, "n": hit["damage"], "crit": hit["crit"], "miss": hit["miss"],
             "hp": self.hp, "by": hero.id, "st": status["effect"] if status and not hit["miss"] else ""}
        )
        if self.hp <= 0:
            self.die(hero)
        elif self.boss and not self.enraged and self.hp <= self.max_hp * float(self.boss.get("enrage_at", 0.5)):
            self.enraged = True
            self.move_speed *= float(self.boss.get("enrage_speed", 1.3))
            self.attack_cooldown *= 0.8
            self.summon_at = self.inst.now
            self.inst.broadcast({"t": "enrage", "id": self.id})

    def die(self, killer) -> None:
        self.dead = True
        self.hp = 0
        self.statuses.clear()
        self.knock = (0.0, 0.0)
        self.respawn_at = self.inst.now + self.respawn_seconds
        self._set_anim("die")
        best = max(self.threat.items(), key=lambda item: item[1], default=None)
        owner = self.inst.heroes.get(best[0]) if best else None
        self.inst.monster_killed(self, owner or killer)
        if not self.respawns:
            self.inst.schedule(self.inst.now + 1.0, lambda: self.inst.remove_monster(self))

    def respawn(self, now: float) -> None:
        self.x, self.y = self.home
        self.threat.clear()
        self.statuses.clear()
        self._reset(now)
        self.dead = False
        self.anim = "idle"
        self.changed = True
        self.inst.broadcast({"t": "mspawn", "m": self.info()})

    def _summon_tick(self, now: float) -> None:
        summon = self.boss.get("summon", {})
        if not summon or now < self.summon_at:
            return
        self.summon_at = now + float(summon.get("every", 12.0))
        self.minions = [m for m in self.minions if not m.dead and m.id in self.inst.monsters]
        room = int(summon.get("most", 4)) - len(self.minions)
        rng = self.inst.rng
        for _ in range(min(int(summon.get("count", 2)), room)):
            x, y = self.inst.map.clamp(self.x + rng.uniform(-90, 90), self.y + rng.uniform(-60, 60))
            self.minions.append(self.inst.add_monster(summon["monster"], x, y, respawns=False))
