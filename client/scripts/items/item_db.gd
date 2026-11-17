extends RefCounted
## Every item in the game, from res://data/items.json: its name, the gear slot
## it is worn in ("" = not worn), icon, bonuses and a short text.
##
## Bonuses: "attack" adds to the sword damage, "max_hp" to maximum health.
## "usable" items can be used from the bag; "world_icon" is the picture on the
## ground when it should differ from the inventory icon; potions have
## "heal_fraction".

const GameData := preload("res://scripts/data/game_data.gd")

## Item id -> its fields.
static var items: Dictionary = GameData.table("items")["items"]
## Gear slots in the order the inventory shows them: left column, then right.
static var gear_slots: Array = GameData.table("items")["gear_slots"]
static var slot_names: Dictionary = GameData.table("items")["slot_names"]
