"""Fake sessions and a hand-turned clock, to drive the game without a network."""

from __future__ import annotations

import random

from server.db import Database
from server.game import Game


class Clock:
    def __init__(self) -> None:
        self.t = 1000.0

    def __call__(self) -> float:
        return self.t


class FakeSession:
    def __init__(self, ip: str = "10.0.0.1") -> None:
        self.ip = ip
        self.account_id = None
        self.username = ""
        self.token = None
        self.hero = None
        self.sent: list = []
        self.closed = False
        self.strikes = 0
        self.last_strike = ""

    def send(self, message: dict) -> None:
        self.sent.append(message)

    def close(self, reason: str) -> None:
        self.closed = True

    def strike(self, reason: str) -> None:
        self.strikes += 1
        self.last_strike = reason

    def last(self, kind: str) -> dict | None:
        return next((m for m in reversed(self.sent) if m.get("t") == kind), None)

    def every(self, kind: str) -> list:
        return [m for m in self.sent if m.get("t") == kind]

    def texts(self) -> list:
        return [m["text"] for m in self.sent if m.get("t") == "msg"]


def new_game(elite: float = 0.0) -> tuple:
    clock = Clock()
    game = Game(Database(), clock=clock, wall_clock=lambda: 1_700_000_000.0 + clock.t, rng=random.Random(7), elite_chance=elite)
    return game, clock


def run(game: Game, clock: Clock, seconds: float, dt: float = 0.1) -> None:
    for _ in range(round(seconds / dt)):
        clock.t += dt
        game.tick(dt)


def player(game: Game, name: str, class_id: str = "warrior", play: bool = True) -> FakeSession:
    session = FakeSession()
    game.handle(session, {"t": "register", "user": name, "pass": "secret1"})
    assert session.last("auth")["ok"], session.last("auth")
    game.handle(session, {"t": "create", "slot": 1, "class": class_id, "name": name + "Hero"})
    if play:
        game.handle(session, {"t": "play", "slot": 1})
        assert session.hero is not None, session.sent[-1]
    return session


def place(game: Game, session: FakeSession, map_id: str, x: float, y: float) -> None:
    """Puts a hero somewhere at once (tests only)."""
    hero = session.hero
    if hero.inst is None or hero.inst.map.id != map_id:
        game.move_hero(hero, map_id, x, y)
    hero.x, hero.y = x, y
    hero.last_move = None
