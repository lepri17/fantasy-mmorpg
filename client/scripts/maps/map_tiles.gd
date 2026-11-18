extends RefCounted
## The ground of a map as a TileMapLayer, from rows of letters in maps.json
## ("g" grass, "p" path, ...). tiles.png has two variants of every kind; each
## cell picks one by its place, so the ground does not look like a grid.

const GameData := preload("res://scripts/data/game_data.gd")
const TEXTURE := preload("res://assets/environment/tiles.png")

static var _tileset: TileSet = null


## A TileMapLayer named "Ground" with one cell per letter of the rows.
static func build(rows: Array) -> TileMapLayer:
	var maps: Dictionary = GameData.table("maps")
	var legend: Dictionary = maps["legend"]
	var kinds: Array = maps["tile_kinds"]
	var layer := TileMapLayer.new()
	layer.name = "Ground"
	layer.tile_set = tileset()
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var kind: int = kinds.find(legend[row[x]])
			var variant: int = posmod(hash(Vector2i(x, y)), 2)
			layer.set_cell(Vector2i(x, y), 0, Vector2i(kind * 2 + variant, 0))
	return layer


## One atlas source with every tile of tiles.png, made once.
static func tileset() -> TileSet:
	if _tileset == null:
		var size: int = int(GameData.table("maps")["tile_size"])
		_tileset = TileSet.new()
		_tileset.tile_size = Vector2i(size, size)
		var source := TileSetAtlasSource.new()
		source.texture = TEXTURE
		source.texture_region_size = Vector2i(size, size)
		for column in floori(TEXTURE.get_width() / float(size)):
			source.create_tile(Vector2i(column, 0))
		_tileset.add_source(source, 0)
	return _tileset
