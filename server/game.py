"""The game: sessions, accounts, characters, the map instances, and what each
message from a client does. net.py brings the messages in over WebSocket; the
tests call handle() directly with fake sessions.

Protocol: JSON objects with "t" (the type). Before login: hello, register,
login, resume. Then: chars, create, delete, play, logout. In the world: move,
dash, cast, hit, pick, portal, respawn, channel, leave, plus the item and
townspeople actions (actions.py) and chat, party, trade, guild, duel and top
(social.py). The server answers with events such as auth, chars, enter, snap,
dmg, char, me, msg and fx (see docs/SERVER.md)."""

from __future__ import annotations

import math
import random
import time

from . import accounts, actions
from .rules import combat
from .rules.stats import Stats, playable
from .social import Social
from .world.hero import Hero
from .world.instance import Instance
from .world.maps import maps, start, town

PROTOCOL = 1
SLOTS = (1, 2, 3)
TOKEN_DAYS = 30
RESUME_SECONDS = 120.0
SAVE_EVERY = 30.0
CHANNEL_SIZE = 50
PORTAL_REACH = 220.0
FACINGS = ("down", "up", "left", "right")
ANIMS = ("idle", "walk", "attack", "hurt", "dash")
MOVE_STRIKES = 40  # moves refused in a minute before the connection is closed
LOGIN_TRIES = 8  # failed logins per address in five minutes


class Game:
    def __init__(self, db, channels: int = 3, clock=time.monotonic, wall_clock=time.time, rng=None, elite_chance=None):
        self.db = db
        self.channels = channels
        self._clock = clock
        self._wall = wall_clock
        self.rng = rng or random.Random()
        self.elite_chance = float(combat.settings()["elite"]["chance"]) if elite_chance is None else elite_chance
        self.instances: dict = {}
        self.heroes: dict = {}  # character id -> Hero in the world
        self.sessions: dict = {}  # account id -> Session
        self.resumable: dict = {}  # account id -> where its hero was when the link dropped
        self.social = Social(self)
        self._login_failures: dict = {}
        self._last_save = self.now
        self.auth_handlers = {"hello": self._hello, "register": self._register, "login": self._login, "resume": self._resume}
        self.lobby_handlers = {
            "chars": self._chars, "create": self._create, "delete": self._delete, "play": self._play,
            "logout": self._logout, "top": self.social.top,
        }
        self.world_handlers = {
            "move": self._move, "dash": self._dash, "cast": self._cast, "hit": self._hit, "pick": self._pick,
            "portal": self._portal, "respawn": self._respawn, "channel": self._channel, "leave": self._leave,
        }
        self.world_handlers.update(actions.HANDLERS)
        self.world_handlers.update(self.social.handlers())

    @property
    def now(self) -> float:
        return self._clock()

    # --- messages in

    def handle(self, session, message) -> None:
        kind = message.get("t") if isinstance(message, dict) else None
        if not isinstance(kind, str):
            session.strike("bad message")
            return
        if kind == "ping":
            session.send({"t": "pong", "c": message.get("c")})
            return
        if session.account_id is None:
            handler = self.auth_handlers.get(kind)
        elif session.hero is None:
            handler = self.lobby_handlers.get(kind)
        else:
            handler = self.world_handlers.get(kind)
        if handler is None:
            session.strike("unexpected " + kind)
            return
        try:
            handler(session, message)
        except (KeyError, TypeError, ValueError, IndexError, AttributeError) as problem:
            session.strike(f"{kind}: {problem!r}")
        if session.hero is not None:
            session.hero.flush()

    def disconnected(self, session) -> None:
        hero = session.hero
        if hero is not None:
            self.resumable[session.account_id] = {
                "char": hero.id, "map": hero.inst.map.id if hero.inst else "", "ch": hero.inst.channel if hero.inst else 1,
                "x": hero.x, "y": hero.y, "hp": hero.hp, "dead": hero.dead, "until": self.now + RESUME_SECONDS,
            }
            self._leave_world(hero)
            session.hero = None
        if session.account_id is not None and self.sessions.get(session.account_id) is session:
            del self.sessions[session.account_id]

    # --- the clock

    def tick(self, dt: float) -> None:
        now = self.now
        for inst in list(self.instances.values()):
            if inst.heroes:
                inst.tick(now, dt)
        for hero in list(self.heroes.values()):
            hero.flush()
        self.social.tick(now)
        if now - self._last_save >= SAVE_EVERY:
            self._last_save = now
            self.save_all()
        for account_id, place in list(self.resumable.items()):
            if now > place["until"]:
                del self.resumable[account_id]

    def save(self, hero) -> None:
        data = hero.stats.to_dict()
        if hero.inst is not None:
            data["online_pos"] = [round(hero.x, 1), round(hero.y, 1)]
        counters = hero.stats.record.counters
        self.db.save_character(
            hero.id, hero.stats.level, hero.stats.total_xp(), int(counters.get("kills", 0)),
            int(counters.get("duel_wins", 0)), data,
        )
        hero.dirty = False

    def save_all(self) -> None:
        for hero in list(self.heroes.values()):
            if hero.dirty:
                self.save(hero)

    def shutdown(self) -> None:
        for hero in list(self.heroes.values()):
            self.save(hero)

    # --- logging in

    def _hello(self, session, message) -> None:
        session.send({"t": "hello", "v": PROTOCOL, "channels": self.channels, "classes": playable()})

    def _register(self, session, message) -> None:
        username, password = message.get("user"), message.get("pass")
        problem = accounts.username_problem(username) or accounts.password_problem(password)
        if problem:
            session.send({"t": "auth", "ok": False, "error": problem})
            return
        salt, digest = accounts.hash_password(password)
        account_id = self.db.create_account(username, salt, digest)
        if account_id is None:
            session.send({"t": "auth", "ok": False, "error": "That name is taken."})
            return
        self._logged_in(session, account_id, username)

    def _login(self, session, message) -> None:
        now = self._wall()
        tries = [t for t in self._login_failures.get(session.ip, []) if now - t < 300]
        self._login_failures[session.ip] = tries
        if len(tries) >= LOGIN_TRIES:
            session.send({"t": "auth", "ok": False, "error": "Too many tries. Wait a few minutes."})
            return
        username, password = message.get("user"), message.get("pass")
        account = self.db.account_by_name(username) if isinstance(username, str) else None
        if (
            account is None
            or not isinstance(password, str)
            or not accounts.check_password(password, account["salt"], account["pass_hash"])
        ):
            tries.append(now)
            session.send({"t": "auth", "ok": False, "error": "Wrong name or password."})
            return
        self._logged_in(session, int(account["id"]), account["username"])

    def _resume(self, session, message) -> None:
        token = message.get("token")
        account_id = None
        if isinstance(token, str):
            account_id = self.db.account_for_token(accounts.token_hash(token), self._wall())
        if account_id is None:
            session.send({"t": "auth", "ok": False, "error": "Please log in again.", "expired": True})
            return
        self._logged_in(session, account_id, self.db.account_name(account_id), token)
        place = self.resumable.pop(account_id, None)
        if place is not None and self.now <= place["until"]:
            row = self.db.character(place["char"])
            if row is not None:
                self._enter_world(session, row, place)

    def _logged_in(self, session, account_id: int, username: str, token: str | None = None) -> None:
        old = self.sessions.get(account_id)
        if old is not None and old is not session:
            old.send({"t": "kicked", "text": "You logged in from another device."})
            self.disconnected(old)
            old.close("logged in elsewhere")
        if token is None:
            token = accounts.new_token()
            self.db.save_token(accounts.token_hash(token), account_id, self._wall() + TOKEN_DAYS * 86400)
        session.account_id = account_id
        session.username = username
        session.token = token
        self.sessions[account_id] = session
        session.send({"t": "auth", "ok": True, "user": username, "token": token, "chars": self._char_list(account_id)})

    def _logout(self, session, message) -> None:
        if session.token:
            self.db.delete_token(accounts.token_hash(session.token))
        self.disconnected(session)
        session.account_id = None
        session.token = None
        session.send({"t": "loggedout"})

    # --- characters

    def _char_list(self, account_id: int) -> list:
        listed = []
        for row in self.db.characters(account_id):
            stats = Stats()
            stats.from_dict(_data(row))
            listed.append({"slot": row["slot"], "data": stats.to_dict()})
        return listed

    def _chars(self, session, message) -> None:
        session.send({"t": "chars", "chars": self._char_list(session.account_id)})

    def _create(self, session, message) -> None:
        slot, class_id, name = int(message.get("slot", 0)), message.get("class"), message.get("name")
        problem = accounts.hero_name_problem(name)
        if slot not in SLOTS or class_id not in playable():
            problem = problem or "Pick a class and an empty slot."
        if problem:
            session.send({"t": "error", "text": problem})
            return
        stats = Stats(class_id)
        stats.hero_name = name
        if self.db.create_character(session.account_id, slot, name, class_id, stats.to_dict()) is None:
            taken = self.db.character_by_name(name) is not None
            session.send({"t": "error", "text": "That name is taken." if taken else "That slot is in use."})
            return
        self._chars(session, message)

    def _delete(self, session, message) -> None:
        slot = int(message.get("slot", 0))
        row = next((r for r in self.db.characters(session.account_id) if r["slot"] == slot), None)
        if row is not None:
            self.social.character_deleted(row)
            self.db.delete_character(session.account_id, slot)
        self._chars(session, message)

    def _play(self, session, message) -> None:
        slot = int(message.get("slot", 0))
        row = next((r for r in self.db.characters(session.account_id) if r["slot"] == slot), None)
        if row is None:
            session.send({"t": "error", "text": "There is no hero in that slot."})
            return
        place = self.resumable.pop(session.account_id, None)
        if place is None or place["char"] != row["id"]:
            place = None
        channel = message.get("ch")
        self._enter_world(session, row, place, int(channel) if isinstance(channel, (int, float)) else None)

    def _enter_world(self, session, row: dict, place: dict | None, channel: int | None = None) -> None:
        if row["id"] in self.heroes:
            session.send({"t": "error", "text": "That hero is already playing."})
            return
        data = _data(row)
        stats = Stats()
        stats.from_dict(data)
        hero = Hero(self, int(row["id"]), session.account_id, int(row["slot"]), stats, session)
        hero.guild_id = row.get("guild_id")
        map_id = place["map"] if place else stats.map_id
        info = maps().get(map_id)
        if info is None or info.dungeon is not None:
            map_id = start() if not stats.map_id else town()
            info = maps()[map_id]
        if place:
            x, y = place["x"], place["y"]
            hero.hp = min(int(place["hp"]), hero.max_hp())
            channel = channel or place["ch"]
        elif data.get("online_pos") and data.get("map") == map_id:
            x, y = (float(v) for v in data["online_pos"])
        else:
            x, y = info.spawn()
        if hero.hp <= 0:
            hero.hp = hero.max_hp()
            x, y = maps()[town()].spawn()
            map_id = town()
        session.hero = hero
        self.heroes[hero.id] = hero
        self.social.entered(hero)
        self.instance(map_id, self._pick_channel(map_id, channel)).add_hero(hero, x, y)

    def _leave_world(self, hero) -> None:
        self.social.left(hero)
        if hero.inst is not None:
            self.save(hero)
            hero.inst.remove_hero(hero)
        else:
            self.save(hero)
        self.heroes.pop(hero.id, None)
        hero.session = None

    def _leave(self, session, message) -> None:
        self._leave_world(session.hero)
        session.hero = None
        self._chars(session, message)

    # --- instances and channels

    def instance(self, map_id: str, channel: int) -> Instance:
        key = (map_id, channel)
        if key not in self.instances:
            self.instances[key] = Instance(self, maps()[map_id], channel)
        return self.instances[key]

    def population(self, map_id: str) -> list:
        return [len(self.instances[(map_id, ch)].heroes) if (map_id, ch) in self.instances else 0
                for ch in range(1, self.channels + 1)]

    def _pick_channel(self, map_id: str, wanted: int | None) -> int:
        counts = self.population(map_id)
        if wanted is not None and 1 <= wanted <= self.channels and counts[wanted - 1] < CHANNEL_SIZE:
            return wanted
        return min(range(1, self.channels + 1), key=lambda ch: (counts[ch - 1] >= CHANNEL_SIZE, ch))

    def move_hero(self, hero, map_id: str, x: float, y: float, channel: int | None = None) -> None:
        """To another map (or channel): out of one instance and into another."""
        channel = channel or (hero.inst.channel if hero.inst else 1)
        self.social.moving(hero)
        if hero.inst is not None:
            hero.inst.remove_hero(hero)
        self.instance(map_id, channel).add_hero(hero, x, y)
        self.save(hero)

    # --- moving and fighting

    def _move(self, session, message) -> None:
        hero = session.hero
        x, y = float(message["x"]), float(message["y"])
        if hero.dead or hero.inst is None or not (math.isfinite(x) and math.isfinite(y)):
            return
        now = self.now
        allowed = 80.0 if hero.last_move is None else hero.allowed_step(now, now - hero.last_move)
        hero.last_move = now
        if hero.distance_to(x, y) > allowed:
            hero.bad_moves = [t for t in hero.bad_moves if now - t < 60.0] + [now]
            hero.send({"t": "pos", "x": round(hero.x, 1), "y": round(hero.y, 1)})
            if len(hero.bad_moves) > MOVE_STRIKES:
                session.close("moving too fast")
            return
        hero.x, hero.y = hero.inst.map.clamp(x, y)
        facing, anim = message.get("f"), message.get("a")
        hero.facing = facing if facing in FACINGS else hero.facing
        hero.anim = anim if anim in ANIMS else "idle"
        hero.changed = True

    def _dash(self, session, message) -> None:
        session.hero.dash(self.now)

    def _cast(self, session, message) -> None:
        hero = session.hero
        kind = str(message["k"])
        why = hero.cast(kind, self.now)
        if why:
            hero.send({"t": "nocast", "k": kind, "why": why})
        elif hero.inst is not None:
            hero.inst.broadcast({"t": "pcast", "id": hero.id, "k": kind}, exclude=hero)

    def _hit(self, session, message) -> None:
        hero = session.hero
        monsters = [int(v) for v in message.get("m", [])[:60]]
        heroes = [int(v) for v in message.get("p", [])[:20]]
        if hero.inst is not None:
            hero.inst.land_hits(hero, str(message["k"]), monsters, heroes)

    def _pick(self, session, message) -> None:
        hero = session.hero
        if hero.inst is not None:
            hero.inst.pick(hero, int(message["id"]))

    def _portal(self, session, message) -> None:
        hero = session.hero
        if hero.dead or hero.inst is None:
            return
        target = message.get("to")
        for portal in hero.inst.map.portals:
            if portal["to"] == target and hero.distance_to(*portal["pos"]) <= PORTAL_REACH:
                destination = maps()[target]
                if destination.dungeon is not None:
                    hero.say(f"{destination.name} is not open online yet.", "warn")
                    hero.send({"t": "pos", "x": round(hero.x, 1), "y": round(hero.y, 1)})
                    return
                self.move_hero(hero, target, *destination.spawn(portal["spawn"]))
                return
        hero.send({"t": "pos", "x": round(hero.x, 1), "y": round(hero.y, 1)})

    def _respawn(self, session, message) -> None:
        hero = session.hero
        if not hero.dead:
            return
        if message.get("town"):
            self.move_hero(hero, town(), *maps()[town()].spawn())
            hero.inst.revive(hero, hero.x, hero.y)
        else:
            hero.inst.revive(hero, *hero.inst.map.spawn())

    def _channel(self, session, message) -> None:
        hero = session.hero
        channel = int(message["ch"])
        if hero.inst is None or hero.dead or not 1 <= channel <= self.channels or channel == hero.inst.channel:
            return
        if self.population(hero.inst.map.id)[channel - 1] >= CHANNEL_SIZE:
            hero.say("That channel is full.", "warn")
            return
        self.move_hero(hero, hero.inst.map.id, hero.x, hero.y, channel)


def _data(row: dict) -> dict:
    import json

    data = json.loads(row["data"]) if isinstance(row["data"], str) else dict(row["data"])
    data["name"] = row["name"]
    data["class"] = row["class"]
    return data
