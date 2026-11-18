"""What a hero does with items and townspeople, checked on the server (N12):
the same rules and messages as client/scripts/player/player_base.gd."""

from __future__ import annotations

from .data import roundi, table
from .rules import items as item_db
from .rules.stats import class_info, class_name, today, with_article
from .world.maps import town

NPC_REACH = 260.0
DROP_DISTANCE = 56.0
FACING = {"down": (0, 1), "up": (0, -1), "left": (-1, 0), "right": (1, 0)}


def _index(message: dict, size: int, key: str = "i") -> int | None:
    value = message.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    index = int(value)
    return index if 0 <= index < size else None


def _changed(hero, limits: bool = False) -> None:
    if limits:
        hero.limits_changed()
    hero.char_changed()


# --- gear and the bag


def equip(session, message) -> None:
    hero = session.hero
    index = _index(message, len(hero.stats.bag))
    if hero.dead or index is None:
        return
    piece = hero.stats.bag[index]
    if not item_db.usable_by(piece["id"], hero.stats.class_id):
        names = " or ".join(with_article(class_name(c)) for c in item_db.items()[piece["id"]].get("classes", []))
        hero.say(f"Only {names} can use that.", "warn")
        return
    if hero.stats.equip(index):
        hero.say(f"Equipped {item_db.display_name(piece)}.")
        _gear_changed(hero)


def unequip(session, message) -> None:
    hero = session.hero
    worn = hero.stats.equipment.get(message.get("slot"), {})
    if hero.dead or not worn:
        return
    if not hero.stats.unequip(message["slot"]):
        hero.say("Your bag is full.", "warn")
        return
    hero.say(f"Took off {item_db.display_name(worn)}.")
    _gear_changed(hero)


def _gear_changed(hero) -> None:
    _changed(hero, limits=True)
    if hero.inst is not None:
        hero.inst.broadcast({"t": "look", "p": hero.public()}, exclude=hero)


def drop(session, message) -> None:
    hero = session.hero
    index = _index(message, len(hero.stats.bag))
    if hero.dead or index is None or hero.trade is not None:
        return
    _on_ground(hero, hero.stats.take_from_bag(index))
    _changed(hero)


def drop_worn(session, message) -> None:
    hero = session.hero
    if hero.dead or hero.trade is not None or not isinstance(message.get("slot"), str):
        return
    worn = hero.stats.remove_equipped(message["slot"])
    if worn:
        _on_ground(hero, worn)
        _gear_changed(hero)


def _on_ground(hero, stack: dict) -> None:
    if not stack or hero.inst is None:
        return
    dx, dy = FACING.get(hero.facing, (0, 1))
    x, y = hero.x + dx * DROP_DISTANCE, hero.y + dy * DROP_DISTANCE
    hero.inst.drop(x, y, "item", amount=int(stack.get("count", 1)), stack=stack, lifetime=120.0, delay=1.0, spread=False)
    hero.say(f"Dropped {item_db.display_name(stack)}.")


def use(session, message) -> None:
    hero = session.hero
    index = _index(message, len(hero.stats.bag))
    if hero.dead or index is None:
        return
    item_id = hero.stats.bag[index]["id"]
    item = item_db.items()[item_id]
    if item_id == "red_potion":
        hero.drink_potion()
    elif "stamina_fraction" in item:
        if hero.stamina >= hero.stats.max_stamina():
            hero.say("Your stamina is full.", "warn")
            return
        hero.stats.take_from_bag(index)
        hero.stamina = min(hero.stats.max_stamina(), hero.stamina + hero.stats.max_stamina() * float(item["stamina_fraction"]))
        hero.fx("stamina", "STAMINA", "stamina")
        hero.announce(hero.stats.record.count("potions_used", 1, hero.stats.level))
        _changed(hero)
    elif "teaches" in item:
        _read_book(hero, index, item)
    elif item.get("resets_stats", False):
        if hero.stats.spent_points() == 0:
            hero.say("There are no stat points to give back.", "warn")
            return
        hero.stats.take_from_bag(index)
        hero.stats.reset_stats(False)
        hero.say("All stat points are free again.", "level")
        _changed(hero, limits=True)


def potion(session, message) -> None:
    session.hero.drink_potion()


def _read_book(hero, index: int, item: dict) -> None:
    skill_id = item["teaches"]
    skill = table("skills")[skill_id]
    needed = int(skill["unlock_level"])
    skill_class = skill.get("class", "warrior")
    if skill_class != hero.stats.class_id:
        hero.say(f"Only {with_article(class_name(skill_class))} can learn {skill['name']}.", "warn")
    elif hero.stats.knows_skill(skill_id):
        hero.say(f"You already know {skill['name']}.", "warn")
    elif hero.stats.level < needed:
        hero.say(f"Reach level {needed} to learn {skill['name']}.", "warn")
    else:
        hero.stats.take_from_bag(index)
        hero.stats.learn_skill(skill_id)
        hero.fx("skill", "NEW SKILL!", "level")
        hero.say(f"You learned {skill['name']}!", "level")
        hero.announce(hero.stats.record.count("books_read", 1, hero.stats.level))
        _changed(hero)


def upgrade(session, message) -> None:
    hero = session.hero
    index = _index(message, len(hero.stats.bag))
    if index is not None:
        _upgrade(hero, hero.stats.bag[index], message.get("stone") is True)


def upgrade_worn(session, message) -> None:
    hero = session.hero
    if message.get("slot") in hero.stats.equipment:
        _upgrade(hero, hero.stats.equipment[message["slot"]], message.get("stone") is True)


def _upgrade(hero, stack: dict, use_stone: bool = False) -> None:
    """For gold, with a stone if asked and there is one (player_base.gd _upgrade)."""
    if hero.dead or hero.trade is not None:
        return
    step = item_db.upgrade_step(stack)
    if not step:
        hero.say(f"{item_db.display_name(stack)} cannot go any higher.", "warn")
        return
    if hero.stats.gold < int(step["cost"]):
        hero.say(f"You need {step['cost']} gold.", "warn")
        return
    use_stone = use_stone and step["stone"] != "" and hero.stats.count_of(step["stone"]) > 0
    result = hero.stats.upgrade(stack, hero.game.rng.random(), use_stone)
    if result == "up":
        hero.fx("upgrade", f"+{stack['plus']}!", "level")
        hero.say(f"Success! {item_db.display_name(stack)}.", "level")
    elif result == "same":
        name = item_db.items()[stack["id"]]["name"]
        next_try = roundi(float(item_db.upgrade_step(stack)["chance"]) * 100.0)
        hero.say(f"It missed. {name} stays at +{stack['plus']}. Next try: {next_try}%.", "warn")
    _gear_changed(hero)


def auto_potion(session, message) -> None:
    hero = session.hero
    choices = hero.stats.auto_potion_choices()
    current = choices.index(hero.stats.auto_potion) if hero.stats.auto_potion in choices else 0
    hero.stats.auto_potion = choices[(current + 1) % len(choices)]
    if hero.stats.auto_potion == 0:
        hero.say("Auto potion is off.")
    else:
        hero.say(f"Auto potion: below {hero.stats.auto_potion}% HP.")
    _changed(hero)


def stat(session, message) -> None:
    hero = session.hero
    if hero.stats.add_stat_point(str(message.get("s"))):
        _changed(hero, limits=True)


def reset_stats(session, message) -> None:
    hero = session.hero
    if hero.stats.spent_points() == 0:
        hero.say("There are no stat points to give back.", "warn")
    elif not hero.stats.reset_stats(True):
        hero.say(f"A stat reset costs {hero.stats.reset_cost()} gold.", "warn")
    else:
        hero.say("All stat points are free again.", "level")
        _changed(hero, limits=True)


def title(session, message) -> None:
    hero = session.hero
    if hero.stats.record.set_title(str(message.get("a", ""))):
        _changed(hero, limits=True)
        if hero.inst is not None:
            hero.inst.broadcast({"t": "look", "p": hero.public()}, exclude=hero)


def tutorial(session, message) -> None:
    hero = session.hero
    hero.stats.tutorial = min(max(int(message.get("step", 0)), 0), 99)
    hero.dirty = True


# --- townspeople


def _near(hero, npc_id, service: str = "") -> bool:
    if hero.dead or hero.inst is None or hero.inst.map.id != town() or not isinstance(npc_id, str):
        return False
    place = hero.inst.map.npcs.get(npc_id)
    if place is None or hero.distance_to(*place) > NPC_REACH:
        return False
    return service == "" or service in table("npcs")[npc_id].get("services", [])


def talk(session, message) -> None:
    hero = session.hero
    npc_id = message.get("npc")
    if not _near(hero, npc_id):
        return
    quests = hero.stats.quests
    reached = quests.on_talk(npc_id)
    for quest_id in reached:
        hero.say(f"{quests.list()[quest_id]['name']}: done! Go back for the reward.", "quest")
    if reached:
        _changed(hero)


def buy(session, message) -> None:
    hero = session.hero
    npc_id, item_id = message.get("npc"), message.get("item")
    if not _near(hero, npc_id, "shop") or item_id not in table("npcs")[npc_id].get("shop", []):
        return
    cost = item_db.price(item_id)
    if hero.stats.gold < cost:
        hero.say(f"That costs {cost} gold.", "warn")
    elif not hero.stats.has_room_for(item_id):
        hero.say("Your bag is full.", "warn")
    else:
        hero.stats.gold -= cost
        hero.stats.add_item(item_id)
        hero.fx("coin")
        hero.say(f"Bought {item_db.items()[item_id]['name']} for {cost} gold.", "gold")
        _changed(hero)


def sell(session, message) -> None:
    hero = session.hero
    index = _index(message, len(hero.stats.bag))
    if index is None or hero.trade is not None or not _near(hero, message.get("npc"), "shop"):
        return
    stack = hero.stats.bag[index]
    paid = item_db.sell_price(stack)
    sold = item_db.display_name(stack, True)
    hero.stats.take_from_bag(index)
    hero.stats.gold += paid
    hero.fx("coin")
    hero.say(f"Sold {sold} for {paid} gold.", "gold")
    _changed(hero)


def store(session, message) -> None:
    hero = session.hero
    index = _index(message, len(hero.stats.bag))
    if index is None or hero.trade is not None or not _near(hero, message.get("npc"), "storage"):
        return
    if hero.stats.store(index):
        _changed(hero)
    else:
        hero.say("Your storage is full.", "warn")


def unstore(session, message) -> None:
    hero = session.hero
    index = _index(message, len(hero.stats.storage))
    if index is None or hero.trade is not None or not _near(hero, message.get("npc"), "storage"):
        return
    if hero.stats.take_stored(index):
        _changed(hero)
    else:
        hero.say("Your bag is full.", "warn")


def heal(session, message) -> None:
    hero = session.hero
    if not _near(hero, message.get("npc"), "heal"):
        return
    hero.statuses.clear()
    hero.hp = hero.max_hp()
    hero.stamina = hero.stats.max_stamina()
    hero.fx("heal", "HEALED", "heal")
    hero.say("You feel rested and whole again.", "heal")


def travel(session, message) -> None:
    from .world.maps import maps

    hero = session.hero
    destination = maps().get(message.get("map"))
    if destination is None or not _near(hero, message.get("npc"), "teleport"):
        return
    if destination.dungeon is not None:
        hero.say(f"{destination.name} is not open online yet.", "warn")
        return
    if hero.stats.gold < destination.teleport_price:
        hero.say(f"The trip costs {destination.teleport_price} gold.", "warn")
        return
    hero.stats.gold -= destination.teleport_price
    _changed(hero)
    hero.game.move_hero(hero, destination.id, *destination.spawn())


def quest_accept(session, message) -> None:
    hero = session.hero
    quest_id = message.get("q")
    quests = hero.stats.quests
    if quest_id not in quests.list() or not _near(hero, quests.list()[quest_id]["giver"]):
        return
    if quests.start(quest_id, hero.stats, today()):
        hero.say(f"New quest: {quests.list()[quest_id]['name']}.", "quest")
        _changed(hero)


def quest_turn_in(session, message) -> None:
    hero = session.hero
    quest_id = message.get("q")
    quests = hero.stats.quests
    if quest_id not in quests.list() or not _near(hero, quests.list()[quest_id]["giver"]):
        return
    if quests.state(quest_id, hero.stats, today()) != "ready":
        return
    quest = quests.list()[quest_id]
    reward = quest.get("reward", {})
    reward_items = list(reward.get("items", []))
    if reward.get("advance", False):
        reward_items.append({"id": class_info(hero.stats.class_id)["advanced"]["item"], "count": 1})
    if not hero.stats.room_for(reward_items):
        hero.say("Make room in your bag for the reward first.", "warn")
        return
    if quest["goal"]["type"] == "collect":
        hero.stats.remove_items(quest["goal"]["item"], int(quest["goal"]["count"]))
    quests.finish(quest_id, today())
    hero.fx("quest", "QUEST COMPLETE!", "quest")
    hero.say(f"Quest complete: {quest['name']}!", "quest")
    for entry in reward.get("items", []):
        hero.stats.add_item(entry["id"], int(entry["count"]))
        hero.say(f"Got {item_db.items()[entry['id']]['name']} x{int(entry['count'])}.", "quest")
    if int(reward.get("gold", 0)) > 0:
        hero.stats.gold += int(reward["gold"])
        hero.say(f"+{int(reward['gold'])} gold", "gold")
        hero.announce(hero.stats.record.count("gold_earned", int(reward["gold"]), hero.stats.level))
    if int(reward.get("xp", 0)) > 0:
        hero.gain_xp(int(reward["xp"]))
    if reward.get("advance", False) and not hero.stats.advanced:
        hero.stats.advanced = True
        info = class_info(hero.stats.class_id)["advanced"]
        hero.stats.add_item(info["item"], 1)
        new_name = class_name(hero.stats.class_id, True)
        hero.say(f"You are now a {new_name}! Got {item_db.items()[info['item']]['name']}.", "quest")
        hero.send({"t": "banner", "text": f"You are now a {new_name}!", "sub": "A new skill opens"})
        hero.fx("advance")
        hero.limits_changed()
        if hero.inst is not None:
            hero.inst.broadcast({"t": "look", "p": hero.public()}, exclude=hero)
    _changed(hero)


HANDLERS = {
    "equip": equip, "unequip": unequip, "drop": drop, "drop_worn": drop_worn, "use": use,
    "potion": potion, "upgrade": upgrade, "upgrade_worn": upgrade_worn, "auto_potion": auto_potion,
    "stat": stat, "reset_stats": reset_stats, "title": title, "tutorial": tutorial, "talk": talk,
    "buy": buy, "sell": sell, "store": store, "unstore": unstore, "heal": heal, "travel": travel,
    "quest_accept": quest_accept, "quest_turn_in": quest_turn_in,
}
