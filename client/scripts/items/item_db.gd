extends RefCounted
## Every item in the game: its name, the gear slot it is worn in ("" = not
## worn), icon, bonuses and a short text. Pure data with no scene
## dependencies, so the server can use the same table later.
##
## Bonuses: "attack" adds to the sword damage, "max_hp" to maximum health.

## Gear slots in the order the inventory shows them: left column, then right.
const GEAR_SLOTS := ["head", "weapon", "gloves", "cape", "armor", "boots"]

const SLOT_NAMES := {
	"head": "Head",
	"weapon": "Weapon",
	"gloves": "Gloves",
	"cape": "Cape",
	"armor": "Armor",
	"boots": "Boots",
}

const ITEMS := {
	"red_headband": {
		"name": "Red Headband",
		"slot": "head",
		"max_hp": 5,
		"icon": "res://assets/items/icons/headband.png",
		"text": "Cloth band with a small gold plate.",
	},
	"training_sword": {
		"name": "Training Sword",
		"slot": "weapon",
		"attack": 4,
		"icon": "res://assets/items/icons/sword.png",
		"text": "Plain steel. Every warrior starts with one.",
	},
	"leather_gloves": {
		"name": "Leather Gloves",
		"slot": "gloves",
		"attack": 1,
		"icon": "res://assets/items/icons/gloves.png",
		"text": "Steel bracers keep the grip steady.",
	},
	"red_cape": {
		"name": "Red Cape",
		"slot": "cape",
		"max_hp": 5,
		"icon": "res://assets/items/icons/cape.png",
		"text": "Warm wool with a gold trim.",
	},
	"blue_plate": {
		"name": "Blue Plate Armor",
		"slot": "armor",
		"max_hp": 20,
		"icon": "res://assets/items/icons/armor.png",
		"text": "Light plates over padded cloth.",
	},
	"leather_boots": {
		"name": "Leather Boots",
		"slot": "boots",
		"max_hp": 5,
		"icon": "res://assets/items/icons/boots.png",
		"text": "Good for long walks.",
	},
	"red_potion": {
		"name": "Red Potion",
		"slot": "",
		"usable": true,
		"icon": "res://assets/items/icons/potion.png",
		# Keep in step with POTION_HEAL_FRACTION in player.gd.
		"text": "Heals 40% of max HP.",
	},
}
