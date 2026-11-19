"""Logging in, characters, the shared world, moving, fighting, loot and saving."""

from server.tests.helpers import FakeSession, new_game, place, player, run
from server.world.maps import maps


def test_accounts_login_and_tokens():
    game, clock = new_game()
    first = player(game, "mor", play=False)
    token = first.last("auth")["token"]
    again = FakeSession()
    game.handle(again, {"t": "login", "user": "MOR", "pass": "wrong!"})
    assert again.last("auth")["ok"] is False
    game.handle(again, {"t": "login", "user": "mor", "pass": "secret1"})
    assert again.last("auth")["ok"] and first.closed  # the older device is logged out
    third = FakeSession()
    game.handle(third, {"t": "resume", "token": token})
    assert third.last("auth")["ok"] and len(third.last("auth")["chars"]) == 1
    blocked = FakeSession(ip="10.9.9.9")
    for _ in range(9):
        game.handle(blocked, {"t": "login", "user": "mor", "pass": "nope!!"})
    assert "Too many" in blocked.last("auth")["error"]
    taken = FakeSession()
    game.handle(taken, {"t": "register", "user": "mor", "pass": "secret1"})
    assert taken.last("auth")["error"] == "That name is taken."


def test_characters_create_delete_and_names():
    game, clock = new_game()
    session = player(game, "ann", play=False)
    game.handle(session, {"t": "create", "slot": 2, "class": "archer", "name": "annhero"})
    assert session.last("error")["text"] == "That name is taken."
    game.handle(session, {"t": "create", "slot": 2, "class": "mage", "name": "Wizz"})
    assert "Pick a class" in session.last("error")["text"]  # the mage is not offered for now
    game.handle(session, {"t": "create", "slot": 2, "class": "archer", "name": "Kesh"})
    chars = session.last("chars")["chars"]
    assert [c["slot"] for c in chars] == [1, 2] and chars[1]["data"]["class"] == "archer"
    game.handle(session, {"t": "delete", "slot": 1})
    assert [c["slot"] for c in session.last("chars")["chars"]] == [2]


def test_two_heroes_see_each_other_move():
    game, clock = new_game()
    a, b = player(game, "alpha"), player(game, "bravo")
    enter = a.last("enter")
    assert enter["map"] == "field" and enter["monsters"] and (enter["x"], enter["y"]) == maps()["field"].spawn()
    assert b.last("enter")["players"][0]["name"] == "alphaHero"
    assert a.last("pjoin")["p"]["name"] == "bravoHero"
    clock.t += 0.2
    game.handle(a, {"t": "move", "x": enter["x"] + 30, "y": enter["y"], "f": "right", "a": "walk"})
    run(game, clock, 0.1)
    row = next(r for r in b.last("snap")["p"] if r[0] == a.hero.id)
    assert row[1] == enter["x"] + 30 and row[3] == "right" and row[4] == "walk"


def test_moving_too_fast_is_refused():
    game, clock = new_game()
    a = player(game, "speedy")
    start = (a.hero.x, a.hero.y)
    clock.t += 0.1
    game.handle(a, {"t": "move", "x": start[0] + 20, "y": start[1]})
    clock.t += 0.1
    game.handle(a, {"t": "move", "x": start[0] + 900, "y": start[1]})
    assert a.last("pos") is not None and a.hero.x == start[0] + 20


def test_attacks_are_checked_and_kills_pay():
    game, clock = new_game()
    a = player(game, "fighter")
    hero = a.hero
    slime = next(m for m in hero.inst.monsters.values() if m.monster_id == "green_slime")
    place(game, a, "field", slime.x - 40, slime.y)
    game.handle(a, {"t": "hit", "k": "attack", "m": [slime.id]})
    assert slime.hp == slime.max_hp  # no swing, no hit
    game.handle(a, {"t": "cast", "k": "attack"})
    game.handle(a, {"t": "cast", "k": "attack"})
    assert a.last("nocast")["why"] == "cooldown"
    slime.hp = 1
    gold_before = hero.stats.gold
    game.handle(a, {"t": "hit", "k": "attack", "m": [slime.id]})
    assert slime.dead and hero.stats.xp == 20 and "+20 EXP" in a.texts()
    assert hero.stats.record.counters["kills"] == 1
    gold = next(l for l in hero.inst.loot.values() if l.kind == "gold")
    game.handle(a, {"t": "pick", "id": gold.id})
    assert hero.stats.gold == gold_before + gold.amount and gold.id not in hero.inst.loot
    run(game, clock, 6.0)
    assert not slime.dead and a.every("mspawn")


def test_far_hits_and_locked_skills_do_nothing():
    game, clock = new_game()
    a = player(game, "archie", "archer")
    slime = next(m for m in a.hero.inst.monsters.values())
    place(game, a, "field", slime.x - 900, slime.y)
    game.handle(a, {"t": "cast", "k": "attack"})
    game.handle(a, {"t": "hit", "k": "attack", "m": [slime.id]})
    assert slime.hp == slime.max_hp
    game.handle(a, {"t": "cast", "k": "arrow_rain"})
    assert a.last("nocast")["why"] == "locked"
    game.handle(a, {"t": "cast", "k": "spin_slash"})
    assert a.last("nocast")["why"] == "unknown skill"
    stamina = a.hero.stamina
    game.handle(a, {"t": "cast", "k": "multi_shot"})
    assert a.hero.stamina == stamina - 22


def test_monsters_hurt_heroes_who_die_and_get_up():
    game, clock = new_game()
    a = player(game, "tank")
    hero = a.hero
    slime = next(m for m in hero.inst.monsters.values() if m.monster_id == "green_slime")
    place(game, a, "field", slime.x + 20, slime.y)
    hero.stats.stat_points = {}
    run(game, clock, 3.0)
    assert any(m.get("p") == hero.id and not m["miss"] for m in a.every("dmg"))
    assert hero.hp < hero.max_hp()
    hero.hp = 1
    hero.invincible_until = 0.0
    run(game, clock, 3.0)
    assert a.last("die")["id"] == hero.id
    run(game, clock, 3.0)
    assert not hero.dead and hero.hp == hero.max_hp() and a.last("revive")


def test_portals_towns_and_shops():
    game, clock = new_game()
    a = player(game, "trader")
    hero = a.hero
    portal = next(p for p in maps()["field"].portals if p["to"] == "town")
    place(game, a, "field", portal["pos"][0] + 30, portal["pos"][1])
    game.handle(a, {"t": "portal", "to": "town"})
    assert hero.inst.map.id == "town" and a.last("enter")["map"] == "town"
    game.handle(a, {"t": "buy", "npc": "merchant", "item": "red_potion"})
    assert hero.stats.potions == 2  # Mira is in the market, behind the town's gate
    gate = next(p for p in maps()["town"].portals if p["to"] == "willow_market")
    place(game, a, "town", *gate["pos"])
    game.handle(a, {"t": "portal", "to": "willow_market"})
    assert hero.inst.map.id == "willow_market"
    place(game, a, "willow_market", *maps()["willow_market"].npcs["merchant"])
    hero.stats.gold = 100
    game.handle(a, {"t": "buy", "npc": "merchant", "item": "red_potion"})
    assert hero.stats.potions == 3 and hero.stats.gold == 80 and "Bought Red Potion for 20 gold." in a.texts()
    game.handle(a, {"t": "buy", "npc": "merchant", "item": "rebirth_scroll"})
    assert hero.stats.gold == 80  # Mira does not sell it
    forest = maps()["forest"]
    cellar_portal = next(p for p in forest.portals if p["to"] == "cellar")
    place(game, a, "forest", *cellar_portal["pos"])
    game.handle(a, {"t": "portal", "to": "cellar"})
    assert hero.inst.map.id == "forest" and "not open online yet" in a.texts()[-1]


def test_link_drop_resume_and_saving():
    game, clock = new_game()
    a = player(game, "steady")
    hero_id = a.hero.id
    place(game, a, "field", 900.0, 700.0)
    a.hero.stats.gold = 77
    token = a.last("auth")["token"]
    game.disconnected(a)
    assert hero_id not in game.heroes
    row = game.db.character(hero_id)
    assert '"gold": 77' in row["data"]
    back = FakeSession()
    game.handle(back, {"t": "resume", "token": token})
    assert back.hero is not None and back.last("enter")["x"] == 900.0
    game.handle(back, {"t": "leave"})
    assert back.hero is None and back.last("chars")


def test_channels():
    game, clock = new_game()
    a = player(game, "chan")
    assert a.hero.inst.channel == 1
    game.handle(a, {"t": "channel", "ch": 2})
    assert a.hero.inst.channel == 2 and a.last("enter")["ch"] == 2
    assert game.population("field") == [0, 1, 0]
