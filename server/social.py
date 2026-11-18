"""Playing together: chat (N5), parties (N6), trading (N7), guilds (N8), duels
and the PvP zone (N9), and the leaderboard (N10)."""

from __future__ import annotations

import re
import unicodedata

from . import accounts
from .rules import items as item_db
from .rules.stats import Stats

CHAT_LENGTH = 120
CHAT_BURST = 4  # messages in CHAT_WINDOW seconds
CHAT_WINDOW = 8.0
INVITE_SECONDS = 30.0
PARTY_SIZE = 5
GUILD_SIZE = 30
GUILD_LEVEL = 5
GUILD_PRICE = 1000
TRADE_REACH = 300.0
DUEL_REACH = 400.0
DUEL_SECONDS = 120.0
TOP_ROWS = 20
# A short list of words that chat hides behind stars (English and Hebrew).
BLOCKED_WORDS = ("fuck", "shit", "bitch", "cunt", "asshole", "nigger", "faggot", "זונה", "שרמוטה", "מניאק", "בן זונה")
_BLOCKED = re.compile("|".join(re.escape(w) for w in sorted(BLOCKED_WORDS, key=len, reverse=True)), re.IGNORECASE)


def clean_text(text) -> str:
    """No control characters, single spaces, at most CHAT_LENGTH letters, rude words starred."""
    if not isinstance(text, str):
        return ""
    text = "".join(ch for ch in text if unicodedata.category(ch)[0] != "C")
    text = " ".join(text.split())[:CHAT_LENGTH]
    return _BLOCKED.sub(lambda match: "*" * len(match.group(0)), text)


class Party:
    def __init__(self, leader_id: int) -> None:
        self.leader = leader_id
        self.members = [leader_id]


class Trade:
    def __init__(self, a, b) -> None:
        self.heroes = (a, b)
        self.offers = {a.id: ([], 0), b.id: ([], 0)}  # hero id -> ([(index, stack copy)], gold)
        self.locked = {a.id: False, b.id: False}
        self.confirmed = {a.id: False, b.id: False}

    def other(self, hero):
        return self.heroes[1] if hero is self.heroes[0] else self.heroes[0]


class Duel:
    def __init__(self, a, b, until: float) -> None:
        self.heroes = (a, b)
        self.until = until

    def other(self, hero):
        return self.heroes[1] if hero is self.heroes[0] else self.heroes[0]


class Social:
    def __init__(self, game) -> None:
        self.game = game
        self.parties: dict = {}  # character id -> Party
        self.invites: dict = {}  # (kind, invited id) -> (from id, expires, extra)
        self._chat_times: dict = {}
        self._next_party_update = 0.0

    def handlers(self) -> dict:
        return {
            "chat": self.chat, "party_invite": self.party_invite, "party_accept": self.party_accept,
            "party_leave": self.party_leave, "party_kick": self.party_kick, "trade_request": self.trade_request,
            "trade_accept": self.trade_accept, "trade_offer": self.trade_offer, "trade_lock": self.trade_lock,
            "trade_confirm": self.trade_confirm, "trade_cancel": self.trade_cancel, "guild_create": self.guild_create,
            "guild_invite": self.guild_invite, "guild_accept": self.guild_accept, "guild_leave": self.guild_leave,
            "guild_kick": self.guild_kick, "guild_info": self.guild_info, "duel_request": self.duel_request,
            "duel_accept": self.duel_accept, "decline": self.decline, "top": self.top,
        }

    # --- helpers

    def online(self, name) -> object | None:
        if not isinstance(name, str):
            return None
        wanted = name.strip().lower()
        return next((h for h in self.game.heroes.values() if h.name.lower() == wanted), None)

    def _invite(self, kind: str, inviter, invited, extra=None) -> None:
        self.invites[(kind, invited.id)] = (inviter.id, self.game.now + INVITE_SECONDS, extra)

    def _take_invite(self, kind: str, invited, inviter_id) -> object | None:
        entry = self.invites.get((kind, invited.id))
        if entry is None or entry[0] != inviter_id or self.game.now > entry[1]:
            return None
        del self.invites[(kind, invited.id)]
        return entry

    def decline(self, session, message) -> None:
        kind = message.get("kind")
        entry = self.invites.pop((kind, session.hero.id), None)
        inviter = self.game.heroes.get(entry[0]) if entry else None
        if inviter is not None:
            inviter.say(f"{session.hero.name} said no.", "warn")

    # --- hooks from the game

    def entered(self, hero) -> None:
        if hero.guild_id:
            guild = self.game.db.guild(hero.guild_id)
            hero.guild_name = guild["name"] if guild else ""
            if guild is None:
                hero.guild_id = None
        party = self.parties.get(hero.id)
        if party is not None:
            self._send_party(party)

    def left(self, hero) -> None:
        self.moving(hero)
        party = self.parties.get(hero.id)
        if party is not None:
            self._send_party(party)

    def moving(self, hero) -> None:
        """Leaving a map: no more trading or duelling."""
        if hero.trade is not None:
            self._close_trade(hero.trade, "The trade was cancelled.")
        if hero.duel is not None:
            self.duel_over(hero.duel, winner=hero.duel.other(hero))

    def character_deleted(self, row: dict) -> None:
        """Before a character is deleted: out of its party, and its guild gets a new leader."""
        party = self.parties.get(row["id"])
        if party is not None:
            self._remove_from_party(party, row["id"])
        guild = self.game.db.guild(row["guild_id"]) if row.get("guild_id") else None
        if guild is not None and guild["leader_id"] == row["id"]:
            self._pass_leadership(guild["id"], row["id"])

    def tick(self, now: float) -> None:
        if now < self._next_party_update:
            return
        self._next_party_update = now + 1.0
        for party in {id(p): p for p in self.parties.values()}.values():
            self._send_party(party)
        for key, entry in list(self.invites.items()):
            if now > entry[1]:
                del self.invites[key]
        for hero in list(self.game.heroes.values()):
            if hero.duel is not None and now > hero.duel.until:
                self.duel_over(hero.duel, winner=None)

    # --- chat (N5)

    def chat(self, session, message) -> None:
        hero = session.hero
        text = clean_text(message.get("text"))
        if not text:
            return
        now = self.game.now
        times = [t for t in self._chat_times.get(hero.id, []) if now - t < CHAT_WINDOW]
        if len(times) >= CHAT_BURST:
            hero.say("You are sending messages too fast.", "warn")
            return
        self._chat_times[hero.id] = times + [now]
        to = message.get("to", "map")
        line = {"t": "chat", "from": hero.name, "id": hero.id, "text": text}
        if to == "all":
            for other in list(self.game.heroes.values()):
                other.send(dict(line, ch="all"))
        elif to == "party":
            party = self.parties.get(hero.id)
            if party is None:
                hero.say("You are not in a party.", "warn")
                return
            for other in self._online(party.members):
                other.send(dict(line, ch="party"))
        elif to == "guild":
            if not hero.guild_id:
                hero.say("You are not in a guild.", "warn")
                return
            for other in list(self.game.heroes.values()):
                if other.guild_id == hero.guild_id:
                    other.send(dict(line, ch="guild"))
        elif isinstance(to, str) and to.startswith("@"):
            other = self.online(to[1:])
            if other is None:
                hero.say(f"{to[1:]} is not online.", "warn")
                return
            other.send(dict(line, ch="whisper", to=other.name))
            if other is not hero:
                hero.send(dict(line, ch="whisper", to=other.name))
        elif hero.inst is not None:
            hero.inst.broadcast(dict(line, ch="map"))

    # --- parties (N6)

    def _online(self, member_ids) -> list:
        return [self.game.heroes[m] for m in member_ids if m in self.game.heroes]

    def party_members(self, hero) -> list:
        party = self.parties.get(hero.id)
        return self._online(party.members) if party else [hero]

    def party_invite(self, session, message) -> None:
        hero, other = session.hero, self.online(message.get("name"))
        party = self.parties.get(hero.id)
        if other is None or other is hero:
            hero.say("No one by that name is online.", "warn")
        elif other.id in self.parties:
            hero.say(f"{other.name} is already in a party.", "warn")
        elif party is not None and (party.leader != hero.id or len(party.members) >= PARTY_SIZE):
            hero.say("Only the leader can invite, up to 5 heroes.", "warn")
        else:
            self._invite("party", hero, other)
            other.send({"t": "invite", "kind": "party", "from": hero.id, "name": hero.name})
            hero.say(f"You invited {other.name} to your party.")

    def party_accept(self, session, message) -> None:
        hero = session.hero
        inviter = self.game.heroes.get(int(message.get("from", 0)))
        if inviter is None or self._take_invite("party", hero, inviter.id) is None or hero.id in self.parties:
            return
        party = self.parties.get(inviter.id)
        if party is None:
            party = self.parties[inviter.id] = Party(inviter.id)
        if len(party.members) >= PARTY_SIZE:
            hero.say("That party is full.", "warn")
            return
        party.members.append(hero.id)
        self.parties[hero.id] = party
        for member in self._online(party.members):
            member.say(f"{hero.name} joined the party.")
        self._send_party(party)

    def party_leave(self, session, message) -> None:
        party = self.parties.get(session.hero.id)
        if party is not None:
            self._remove_from_party(party, session.hero.id)

    def party_kick(self, session, message) -> None:
        hero = session.hero
        party = self.parties.get(hero.id)
        other = self.online(message.get("name"))
        target = other.id if other else self._member_by_name(party, message.get("name"))
        if party is not None and party.leader == hero.id and target in party.members and target != hero.id:
            self._remove_from_party(party, target)

    def _member_by_name(self, party, name) -> int | None:
        if party is None or not isinstance(name, str):
            return None
        row = self.game.db.character_by_name(name)
        return int(row["id"]) if row and row["id"] in party.members else None

    def _remove_from_party(self, party: Party, char_id: int) -> None:
        if char_id not in party.members:
            return
        party.members.remove(char_id)
        self.parties.pop(char_id, None)
        gone = self.game.heroes.get(char_id)
        if gone is not None:
            gone.send({"t": "party", "members": [], "leader": 0})
            gone.say("You left the party.")
        if len(party.members) <= 1:
            for rest in party.members:
                self.parties.pop(rest, None)
                if rest in self.game.heroes:
                    self.game.heroes[rest].send({"t": "party", "members": [], "leader": 0})
                    self.game.heroes[rest].say("The party broke up.")
            party.members.clear()
            return
        if party.leader == char_id:
            party.leader = party.members[0]
        self._send_party(party)

    def _send_party(self, party: Party) -> None:
        rows = []
        for member_id in party.members:
            hero = self.game.heroes.get(member_id)
            if hero is None:
                rows.append({"id": member_id, "name": self._name_of(member_id), "online": False})
            else:
                rows.append({
                    "id": hero.id, "name": hero.name, "cls": hero.stats.class_id, "lvl": hero.stats.level,
                    "hp": hero.hp, "mhp": hero.max_hp(), "map": hero.inst.map.id if hero.inst else "",
                    "online": True,
                })
        for hero in self._online(party.members):
            hero.send({"t": "party", "members": rows, "leader": party.leader})

    def _name_of(self, char_id: int) -> str:
        row = self.game.db.character(char_id)
        return row["name"] if row else "?"

    # --- trading (N7): offer, LOCK, then CONFIRM on both sides

    def trade_request(self, session, message) -> None:
        hero, other = session.hero, self.online(message.get("name"))
        problem = self._trade_problem(hero, other)
        if problem:
            hero.say(problem, "warn")
            return
        self._invite("trade", hero, other)
        other.send({"t": "invite", "kind": "trade", "from": hero.id, "name": hero.name})
        hero.say(f"You asked {other.name} to trade.")

    def _trade_problem(self, hero, other) -> str:
        if other is None or other is hero:
            return "No one by that name is online."
        if other.inst is not hero.inst or hero.distance_to(other.x, other.y) > TRADE_REACH:
            return f"Stand next to {other.name} to trade."
        if hero.trade is not None or other.trade is not None or hero.dead or other.dead:
            return f"{other.name} cannot trade right now."
        return ""

    def trade_accept(self, session, message) -> None:
        hero = session.hero
        inviter = self.game.heroes.get(int(message.get("from", 0)))
        if inviter is None or self._take_invite("trade", hero, inviter.id) is None:
            return
        problem = self._trade_problem(hero, inviter)
        if problem:
            hero.say(problem, "warn")
            return
        trade = Trade(inviter, hero)
        inviter.trade = hero.trade = trade
        self._send_trade(trade)

    def trade_offer(self, session, message) -> None:
        hero = session.hero
        trade = hero.trade
        if trade is None:
            return
        indices = message.get("items", [])
        gold = int(message.get("gold", 0))
        if not isinstance(indices, list) or len(indices) > hero.stats.bag_size():
            return
        chosen = sorted({int(i) for i in indices if 0 <= int(i) < len(hero.stats.bag)})
        gold = min(max(gold, 0), hero.stats.gold)
        trade.offers[hero.id] = ([(i, item_db.clean_stack(hero.stats.bag[i]) or dict(hero.stats.bag[i])) for i in chosen], gold)
        for key in trade.locked:
            trade.locked[key] = False
            trade.confirmed[key] = False
        self._send_trade(trade)

    def trade_lock(self, session, message) -> None:
        trade = session.hero.trade
        if trade is not None:
            trade.locked[session.hero.id] = True
            self._send_trade(trade)

    def trade_confirm(self, session, message) -> None:
        hero = session.hero
        trade = hero.trade
        if trade is None or not all(trade.locked.values()):
            return
        trade.confirmed[hero.id] = True
        if all(trade.confirmed.values()):
            self._finish_trade(trade)
        else:
            self._send_trade(trade)

    def trade_cancel(self, session, message) -> None:
        if session.hero.trade is not None:
            self._close_trade(session.hero.trade, "The trade was cancelled.")

    def _close_trade(self, trade: Trade, text: str) -> None:
        for hero in trade.heroes:
            hero.trade = None
            hero.send({"t": "trade", "open": False})
            hero.say(text, "warn" if "cancel" in text else "gold")

    def _send_trade(self, trade: Trade) -> None:
        for hero in trade.heroes:
            other = trade.other(hero)
            mine, theirs = trade.offers[hero.id], trade.offers[other.id]
            hero.send({
                "t": "trade", "open": True, "with": other.id, "name": other.name,
                "mine": {"idx": [i for i, _ in mine[0]], "gold": mine[1]},
                "theirs": {"items": [stack for _, stack in theirs[0]], "gold": theirs[1]},
                "locked": [trade.locked[hero.id], trade.locked[other.id]],
                "confirmed": [trade.confirmed[hero.id], trade.confirmed[other.id]],
            })

    def _finish_trade(self, trade: Trade) -> None:
        a, b = trade.heroes
        apart = a.inst is None or a.inst is not b.inst or a.distance_to(b.x, b.y) > TRADE_REACH
        if a.trade is not trade or b.trade is not trade or apart or a.dead or b.dead:
            self._close_trade(trade, "The trade was cancelled.")
            return
        for hero in trade.heroes:
            items, gold = trade.offers[hero.id]
            for index, stack in items:
                if index >= len(hero.stats.bag) or item_db.clean_stack(hero.stats.bag[index]) != stack:
                    self._close_trade(trade, "The trade was cancelled: a bag changed.")
                    return
            if hero.stats.gold < gold:
                self._close_trade(trade, "The trade was cancelled.")
                return
        for hero in trade.heroes:  # check the room in both bags first
            incoming = [stack for _, stack in trade.offers[trade.other(hero).id][0]]
            outgoing = {i for i, _ in trade.offers[hero.id][0]}
            test = Stats(hero.stats.class_id)
            test.bag = [dict(s) for i, s in enumerate(hero.stats.bag) if i not in outgoing]
            if not all(test.add_stack(dict(stack)) for stack in incoming):
                self._close_trade(trade, f"The trade was cancelled: {hero.name}'s bag is full.")
                return
        taken = {}
        for hero in trade.heroes:
            items, gold = trade.offers[hero.id]
            taken[hero.id] = [hero.stats.take_stack(i) for i in sorted((i for i, _ in items), reverse=True)]
            hero.stats.gold -= gold
        for hero in trade.heroes:
            other = trade.other(hero)
            for stack in taken[other.id]:
                hero.stats.add_stack(stack)
            hero.stats.gold += trade.offers[other.id][1]
            hero.char_changed()
        for hero in trade.heroes:
            self.game.save(hero)  # straight away, so nothing can be had twice
        self._close_trade(trade, "Trade complete.")

    # --- guilds (N8)

    def guild_create(self, session, message) -> None:
        hero = session.hero
        name = message.get("name")
        problem = accounts.guild_name_problem(name)
        if hero.guild_id:
            problem = "You are already in a guild."
        elif hero.stats.level < GUILD_LEVEL:
            problem = f"Reach level {GUILD_LEVEL} to found a guild."
        elif hero.stats.gold < GUILD_PRICE:
            problem = f"A guild costs {GUILD_PRICE} gold."
        if problem:
            hero.say(problem, "warn")
            return
        guild_id = self.game.db.create_guild(name.strip(), hero.id)
        if guild_id is None:
            hero.say("That guild name is taken.", "warn")
            return
        hero.stats.gold -= GUILD_PRICE
        hero.char_changed()
        self._join_guild(hero, guild_id)
        hero.say(f"You founded the guild {name.strip()}!", "level")

    def _join_guild(self, hero, guild_id) -> None:
        self.game.db.set_guild(hero.id, guild_id)
        guild = self.game.db.guild(guild_id) if guild_id else None
        hero.guild_id = guild_id
        hero.guild_name = guild["name"] if guild else ""
        self.game.save(hero)
        if hero.inst is not None:
            hero.inst.broadcast({"t": "look", "p": hero.public()})
        self._send_guild(hero)

    def guild_invite(self, session, message) -> None:
        hero, other = session.hero, self.online(message.get("name"))
        guild = self.game.db.guild(hero.guild_id) if hero.guild_id else None
        if guild is None or guild["leader_id"] != hero.id:
            hero.say("Only a guild leader can invite.", "warn")
        elif other is None or other is hero:
            hero.say("No one by that name is online.", "warn")
        elif other.guild_id:
            hero.say(f"{other.name} is already in a guild.", "warn")
        elif len(self.game.db.guild_members(guild["id"])) >= GUILD_SIZE:
            hero.say("Your guild is full.", "warn")
        else:
            self._invite("guild", hero, other, guild["id"])
            other.send({"t": "invite", "kind": "guild", "from": hero.id, "name": hero.name, "guild": guild["name"]})
            hero.say(f"You invited {other.name} to {guild['name']}.")

    def guild_accept(self, session, message) -> None:
        hero = session.hero
        entry = self._take_invite("guild", hero, int(message.get("from", 0)))
        if entry is None or hero.guild_id or self.game.db.guild(entry[2]) is None:
            return
        self._join_guild(hero, entry[2])
        for other in self.game.heroes.values():
            if other.guild_id == hero.guild_id:
                other.say(f"{hero.name} joined {hero.guild_name}.")

    def guild_leave(self, session, message) -> None:
        hero = session.hero
        if not hero.guild_id:
            return
        guild_id = hero.guild_id
        guild = self.game.db.guild(guild_id)
        self._join_guild(hero, None)
        hero.say("You left the guild.")
        if guild and guild["leader_id"] == hero.id:
            self._pass_leadership(guild_id, hero.id)

    def _pass_leadership(self, guild_id: int, old_leader: int) -> None:
        rest = [m for m in self.game.db.guild_members(guild_id) if m["id"] != old_leader]
        if not rest:
            self.game.db.delete_guild(guild_id)
            return
        self.game.db.set_guild_leader(guild_id, rest[0]["id"])

    def guild_kick(self, session, message) -> None:
        hero = session.hero
        guild = self.game.db.guild(hero.guild_id) if hero.guild_id else None
        row = self.game.db.character_by_name(str(message.get("name", "")))
        if guild is None or guild["leader_id"] != hero.id or row is None or row["guild_id"] != guild["id"]:
            return
        if row["id"] == hero.id:
            return
        other = self.game.heroes.get(row["id"])
        if other is not None:
            self._join_guild(other, None)
            other.say("You were removed from the guild.", "warn")
        else:
            self.game.db.set_guild(row["id"], None)
        self._send_guild(hero)

    def guild_info(self, session, message) -> None:
        self._send_guild(session.hero)

    def _send_guild(self, hero) -> None:
        guild = self.game.db.guild(hero.guild_id) if hero.guild_id else None
        if guild is None:
            hero.send({"t": "guild", "id": 0})
            return
        members = [
            {"id": m["id"], "name": m["name"], "cls": m["class"], "lvl": m["level"], "online": m["id"] in self.game.heroes}
            for m in self.game.db.guild_members(guild["id"])
        ]
        hero.send({"t": "guild", "id": guild["id"], "name": guild["name"], "leader": guild["leader_id"], "members": members})

    # --- duels and the PvP zone (N9)

    def may_fight(self, attacker, target) -> bool:
        if attacker.duel is not None and attacker.duel is target.duel:
            return True
        place = attacker.inst.map if attacker.inst else None
        return (
            place is not None and not place.safe and attacker.inst is target.inst
            and place.in_pvp_zone(attacker.x, attacker.y) and place.in_pvp_zone(target.x, target.y)
        )

    def duel_request(self, session, message) -> None:
        hero, other = session.hero, self.online(message.get("name"))
        problem = self._duel_problem(hero, other)
        if problem:
            hero.say(problem, "warn")
            return
        self._invite("duel", hero, other)
        other.send({"t": "invite", "kind": "duel", "from": hero.id, "name": hero.name})
        hero.say(f"You challenged {other.name} to a duel.")

    def _duel_problem(self, hero, other) -> str:
        if other is None or other is hero:
            return "No one by that name is online."
        if other.inst is not hero.inst or hero.distance_to(other.x, other.y) > DUEL_REACH:
            return f"Stand near {other.name} to duel."
        if hero.duel is not None or other.duel is not None or hero.dead or other.dead:
            return f"{other.name} cannot duel right now."
        return ""

    def duel_accept(self, session, message) -> None:
        hero = session.hero
        inviter = self.game.heroes.get(int(message.get("from", 0)))
        if inviter is None or self._take_invite("duel", hero, inviter.id) is None:
            return
        problem = self._duel_problem(hero, inviter)
        if problem:
            hero.say(problem, "warn")
            return
        duel = Duel(inviter, hero, self.game.now + DUEL_SECONDS)
        inviter.duel = hero.duel = duel
        hero.inst.broadcast({"t": "duel", "a": inviter.id, "b": hero.id, "on": True, "s": DUEL_SECONDS})

    def duel_over(self, duel: Duel, winner) -> None:
        a, b = duel.heroes
        if a.duel is not duel:
            return
        a.duel = b.duel = None
        message = {"t": "duel", "a": a.id, "b": b.id, "on": False, "winner": winner.id if winner else 0}
        for hero in (a, b):
            if hero.inst is not None:
                hero.inst.broadcast(message)
                break
        if winner is None:
            for hero in (a, b):
                hero.say("The duel ended in a draw.")
            return
        loser = duel.other(winner)
        winner.announce(winner.stats.record.count("duel_wins", 1, winner.stats.level))
        winner.char_changed()
        winner.say(f"You won the duel against {loser.name}!", "level")
        loser.say(f"{winner.name} won the duel.", "warn")

    # --- the leaderboard (N10)

    def top(self, session, message) -> None:
        by = message.get("by") if message.get("by") in ("level", "kills", "pvp") else "level"
        self.game.save_all()
        rows = [
            {"name": r["name"], "cls": r["class"], "lvl": r["level"], "kills": r["kills"], "pvp": r["pvp_wins"]}
            for r in self.game.db.top(by, TOP_ROWS)
        ]
        session.send({"t": "top", "by": by, "rows": rows})
