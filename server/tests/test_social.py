"""Chat, parties, trading, guilds, duels, the PvP zone and the leaderboard."""

from server.rules import items as item_db
from server.social import clean_text
from server.tests.helpers import new_game, place, player, run
from server.world.maps import maps


def test_chat_channels_filter_and_flood():
    game, clock = new_game()
    a, b, c = player(game, "ann"), player(game, "ben"), player(game, "cat")
    game.move_hero(c.hero, "town", *maps()["town"].spawn())
    game.handle(a, {"t": "chat", "to": "map", "text": "hi\nthere   friend"})
    assert b.last("chat")["text"] == "hithere friend" and c.last("chat") is None
    game.handle(a, {"t": "chat", "to": "all", "text": "hello all"})
    assert c.last("chat")["ch"] == "all"
    game.handle(a, {"t": "chat", "to": "@CATHERO", "text": "psst"})
    assert c.last("chat")["ch"] == "whisper" and b.last("chat")["text"] != "psst"
    assert clean_text("you shit") == "you ****" and len(clean_text("x" * 500)) == 120
    for _ in range(3):
        game.handle(a, {"t": "chat", "to": "map", "text": "spam"})
    assert a.texts()[-1] == "You are sending messages too fast."


def test_party_invite_share_xp_and_hp():
    game, clock = new_game()
    a, b = player(game, "lead"), player(game, "pal")
    game.handle(a, {"t": "party_invite", "name": "palHero"})
    invite = b.last("invite")
    assert invite["kind"] == "party"
    game.handle(b, {"t": "party_accept", "from": invite["from"]})
    party = a.last("party")
    assert [m["name"] for m in party["members"]] == ["leadHero", "palHero"] and party["leader"] == a.hero.id
    slime = next(m for m in a.hero.inst.monsters.values() if m.monster_id == "green_slime")
    place(game, a, "field", slime.x - 40, slime.y)
    place(game, b, "field", slime.x - 60, slime.y)
    slime.hp = 1
    game.handle(a, {"t": "cast", "k": "attack"})
    game.handle(a, {"t": "hit", "k": "attack", "m": [slime.id]})
    assert a.hero.stats.xp == 11 and b.hero.stats.xp == 11  # 20 XP, +10% for two, split
    gold = next(l for l in a.hero.inst.loot.values() if l.kind == "gold")
    game.handle(b, {"t": "pick", "id": gold.id})
    assert gold.id not in a.hero.inst.loot  # party members may pick the killer's loot
    game.handle(b, {"t": "party_leave"})
    assert b.last("party")["members"] == [] and a.last("party")["members"] == []


def test_trade_needs_both_locks_and_confirms():
    game, clock = new_game()
    a, b = player(game, "seller"), player(game, "buyer")
    place(game, b, "field", a.hero.x + 50, a.hero.y)
    a.hero.stats.add_stack(item_db.gear("training_sword", "rare", 4, {"attack": 3}))
    b.hero.stats.gold = 500
    game.handle(a, {"t": "trade_request", "name": "buyerHero"})
    game.handle(b, {"t": "trade_accept", "from": a.hero.id})
    assert a.last("trade")["open"] and b.last("trade")["name"] == "sellerHero"
    sword_index = len(a.hero.stats.bag) - 1
    game.handle(a, {"t": "trade_offer", "items": [sword_index], "gold": 0})
    game.handle(b, {"t": "trade_offer", "items": [], "gold": 300})
    assert b.last("trade")["theirs"]["items"][0]["plus"] == 4
    game.handle(a, {"t": "trade_lock"})
    game.handle(a, {"t": "trade_confirm"})
    assert a.hero.trade is not None  # the other side has not locked yet
    game.handle(b, {"t": "trade_lock"})
    game.handle(a, {"t": "trade_confirm"})
    game.handle(b, {"t": "trade_offer", "items": [], "gold": 200})  # a change undoes the locks
    assert a.last("trade")["locked"] == [False, False]
    for side in (a, b):
        game.handle(side, {"t": "trade_lock"})
    for side in (a, b):
        game.handle(side, {"t": "trade_confirm"})
    assert a.hero.trade is None and "Trade complete." in a.texts()
    assert a.hero.stats.gold == 200 and b.hero.stats.gold == 300
    assert any(s["id"] == "training_sword" and s["plus"] == 4 for s in b.hero.stats.bag)
    assert '"gold": 300' in game.db.character(b.hero.id)["data"]  # saved straight away


def test_guilds():
    game, clock = new_game()
    a, b = player(game, "boss"), player(game, "newbie")
    game.handle(a, {"t": "guild_create", "name": "Moon Wolves"})
    assert "Reach level 5" in a.texts()[-1]
    a.hero.stats.level, a.hero.stats.gold = 6, 1500
    game.handle(a, {"t": "guild_create", "name": "Moon Wolves"})
    assert a.hero.guild_name == "Moon Wolves" and a.hero.stats.gold == 500
    game.handle(a, {"t": "guild_invite", "name": "newbieHero"})
    game.handle(b, {"t": "guild_accept", "from": a.hero.id})
    assert b.hero.guild_name == "Moon Wolves" and b.last("guild")["name"] == "Moon Wolves"
    assert any(m["t"] == "look" and m["p"]["guild"] == "Moon Wolves" for m in a.every("look"))
    game.handle(b, {"t": "chat", "to": "guild", "text": "hello wolves"})
    assert a.last("chat")["ch"] == "guild"
    game.handle(a, {"t": "guild_leave"})
    assert game.db.guild(b.hero.guild_id)["leader_id"] == b.hero.id  # the leader passed it on


def test_duel_ends_at_one_hp_and_counts_the_win():
    game, clock = new_game()
    a, b = player(game, "duelist"), player(game, "rival")
    place(game, b, "field", a.hero.x + 40, a.hero.y)
    game.handle(a, {"t": "cast", "k": "attack"})
    game.handle(a, {"t": "hit", "k": "attack", "p": [b.hero.id]})
    assert b.hero.hp == b.hero.max_hp()  # no fighting outside a duel
    game.handle(a, {"t": "duel_request", "name": "rivalHero"})
    game.handle(b, {"t": "duel_accept", "from": a.hero.id})
    assert b.last("duel")["on"] is True
    b.hero.hp = 3
    for _ in range(6):
        clock.t += 1.2
        b.hero.invincible_until = 0.0
        game.handle(a, {"t": "cast", "k": "attack"})
        game.handle(a, {"t": "hit", "k": "attack", "p": [b.hero.id]})
        if a.hero.duel is None:
            break
    assert a.hero.duel is None and not b.hero.dead and b.hero.hp == 1
    assert a.hero.stats.record.counters["duel_wins"] == 1 and b.last("duel")["winner"] == a.hero.id


def test_pvp_zone_and_leaderboard():
    game, clock = new_game()
    a, b = player(game, "one"), player(game, "two")
    forest = maps()["forest"]
    assert forest.pvp_zone is not None
    left, top, right, bottom = forest.pvp_zone
    middle = ((left + right) / 2, (top + bottom) / 2)
    place(game, a, "forest", *middle)
    place(game, b, "forest", middle[0] + 40, middle[1])
    assert game.social.may_fight(a.hero, b.hero)
    place(game, b, "forest", right + 200, bottom + 200)
    assert not game.social.may_fight(a.hero, b.hero)
    a.hero.stats.level = 9
    a.hero.char_changed()
    run(game, clock, 0.1)
    game.handle(a, {"t": "top", "by": "level"})
    rows = a.last("top")["rows"]
    assert rows[0]["name"] == "oneHero" and rows[0]["lvl"] == 9
