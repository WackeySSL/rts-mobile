class_name MapDef
extends Resource
## A tile map as text (ADR 0008 section 1): one string per tile row, one character per tile, all
## rows the same length, every character a symbol of `terrain`.

@export var rows: PackedStringArray = PackedStringArray()
@export var terrain: TerrainSetDef


## Width (the length of the first row) and height in tiles. Zero without rows.
func size_tiles() -> Vector2i:
	if rows.is_empty():
		return Vector2i.ZERO
	return Vector2i(len(rows[0]), rows.size())


## One text per problem, empty when the map is valid. Reports an empty map, a missing terrain
## set, a row whose length differs from the first row's, and the first unknown symbol of a row.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var size: Vector2i = size_tiles()
	if size.x == 0 or size.y == 0:
		problems.append("map has no tiles")
	if terrain == null:
		problems.append("map has no terrain set")
	var symbols: Dictionary[String, bool] = {}
	if terrain != null:
		for def: TerrainDef in terrain.terrains:
			if def != null:
				symbols[def.symbol] = true
	for y: int in rows.size():
		var row: String = rows[y]
		if len(row) != size.x:
			problems.append("row %d has %d tiles, expected %d" % [y, len(row), size.x])
		if terrain == null:
			continue
		for x: int in len(row):
			if not symbols.has(row[x]):
				problems.append("row %d column %d: unknown symbol '%s'" % [y, x, row[x]])
				break
	return problems
