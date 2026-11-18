extends RefCounted
## Builds a hero's sprite sheet for the gear worn. Each class's art is drawn as
## separate parts (plain body, armour, weapon...) in <class>_parts.png, and this
## lays the parts of the worn gear over each other in the order <class>_parts.gd
## gives for each row (both made by tools/generate_assets.py).

const ItemDb := preload("res://scripts/items/item_db.gd")
const ClassDb := preload("res://scripts/player/class_db.gd")

## Decoded parts atlases by path, kept after the first build.
static var _atlases: Dictionary = {}


## equipment: gear slot -> worn entry (or just its item id), as in player_stats.gd.
static func build(equipment: Dictionary, class_id: String = ClassDb.DEFAULT) -> ImageTexture:
	var parts_path: String = ClassDb.info(class_id)["parts"]
	var parts = load(parts_path + ".gd")  # the generated <class>_parts.gd script
	var atlas: Image = _parts_atlas(parts_path + ".png")
	# Gear with a "look" (items.json) uses the parts of the piece it looks like,
	# in its own colours: the "part@item" pieces.
	var worn: Array = []
	var looks: Array = []
	for entry in equipment.values():
		var item_id: String = entry["id"] if entry is Dictionary else entry
		worn.append(item_id)
		looks.append(ItemDb.items.get(item_id, {}).get("look", item_id))
	var directions: Array = parts.DIRECTIONS
	var cell: int = parts.CELL
	var sheet := Image.create(
		parts.COLUMNS * cell, directions.size() * cell, false, Image.FORMAT_RGBA8
	)
	var pieces: Dictionary = parts.PIECES
	for row in directions.size():
		for part in parts.ORDER[directions[row]]:
			if not _is_worn(parts.REQUIRES.get(part, []), looks):
				continue
			var key: String = part
			for item_id in worn:
				if pieces.has("%s@%s" % [part, item_id]):
					key = "%s@%s" % [part, item_id]
			for piece in pieces[key][row]:
				# piece: [column, atlas x, atlas y, width, height, x in cell, y in cell]
				var source := Rect2i(piece[1], piece[2], piece[3], piece[4])
				var target := Vector2i(piece[0] * cell + piece[5], row * cell + piece[6])
				sheet.blend_rect(atlas, source, target)
	return ImageTexture.create_from_image(sheet)


static func _is_worn(needed: Array, worn: Array) -> bool:
	for item_id in needed:
		if not worn.has(item_id):
			return false
	return true


## The parts atlases are imported as Images (see their .import files), so the
## pixels are read without going through the GPU. A texture import still works,
## by reading the texture back.
static func _parts_atlas(path: String) -> Image:
	if not _atlases.has(path):
		var resource: Resource = load(path)
		var image: Image = null
		if resource is Image:
			image = resource
		elif resource is Texture2D:
			image = (resource as Texture2D).get_image()
		if image == null:
			push_error("HeroLook: cannot read %s" % path)
			image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		if image.is_compressed() or image.get_format() != Image.FORMAT_RGBA8:
			image = image.duplicate()
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
		_atlases[path] = image
	return _atlases[path]
