extends RefCounted
## Builds the warrior's sprite sheet for the gear he wears. The art is drawn as
## separate parts (plain body, armour, sword...), and this lays the parts of the
## worn gear over each other in the order warrior_parts.gd gives for each row.

const Parts := preload("res://assets/characters/warrior/warrior_parts.gd")
const ItemDb := preload("res://scripts/items/item_db.gd")
const ATLAS_PATH := "res://assets/characters/warrior/warrior_parts.png"

## The decoded parts atlas, kept after the first build.
static var _atlas: Image = null


## equipment: gear slot -> worn entry (or just its item id), as in player_stats.gd.
static func build(equipment: Dictionary) -> ImageTexture:
	var atlas: Image = _parts_atlas()
	# Gear with a "look" (items.json) uses the parts of the piece it looks like,
	# in its own colours: the "part@item" pieces.
	var worn: Array = []
	var looks: Array = []
	for entry in equipment.values():
		var item_id: String = entry["id"] if entry is Dictionary else entry
		worn.append(item_id)
		looks.append(ItemDb.items.get(item_id, {}).get("look", item_id))
	var sheet := Image.create(
		Parts.COLUMNS * Parts.CELL, Parts.DIRECTIONS.size() * Parts.CELL, false, Image.FORMAT_RGBA8
	)
	for row in Parts.DIRECTIONS.size():
		for part in Parts.ORDER[Parts.DIRECTIONS[row]]:
			if not _is_worn(Parts.REQUIRES.get(part, []), looks):
				continue
			var key: String = part
			for item_id in worn:
				if Parts.PIECES.has("%s@%s" % [part, item_id]):
					key = "%s@%s" % [part, item_id]
			for piece in Parts.PIECES[key][row]:
				# piece: [column, atlas x, atlas y, width, height, x in cell, y in cell]
				var source := Rect2i(piece[1], piece[2], piece[3], piece[4])
				var target := Vector2i(piece[0] * Parts.CELL + piece[5], row * Parts.CELL + piece[6])
				sheet.blend_rect(atlas, source, target)
	return ImageTexture.create_from_image(sheet)


static func _is_worn(needed: Array, worn: Array) -> bool:
	for item_id in needed:
		if not worn.has(item_id):
			return false
	return true


## warrior_parts.png is imported as an Image (see its .import file), so the
## pixels are read without going through the GPU. A texture import still works,
## by reading the texture back.
static func _parts_atlas() -> Image:
	if _atlas == null:
		var resource: Resource = load(ATLAS_PATH)
		var image: Image = null
		if resource is Image:
			image = resource
		elif resource is Texture2D:
			image = (resource as Texture2D).get_image()
		if image == null:
			push_error("WarriorLook: cannot read %s" % ATLAS_PATH)
			image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		if image.is_compressed() or image.get_format() != Image.FORMAT_RGBA8:
			image = image.duplicate()
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
		_atlas = image
	return _atlas
