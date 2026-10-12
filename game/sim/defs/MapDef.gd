class_name MapDef
extends Resource
## A tile map as text (ADR 0008 section 1): one string per tile row, one character per tile, all
## rows the same length, every character a symbol of `terrain`.

## The entries a TerrainDef.cost must have: one per movement class (foot, wheeled, tracked).
const _COST_ENTRIES: int = 3
## The largest cost (ADR 0008 section 1). World keeps a cost in a byte.
const _COST_MAX: int = 40

@export var rows: PackedStringArray = PackedStringArray()
@export var terrain: TerrainSetDef


## Width (the length of the first row) and height in tiles. Zero without rows.
func size_tiles() -> Vector2i:
	if rows.is_empty():
		return Vector2i.ZERO
	return Vector2i(len(rows[0]), rows.size())


## One text per problem, empty when the map is valid: an empty map, a missing terrain set, a null,
## repeated-symbol or wrong-cost-count terrain, a cost outside 0..40, a row of the wrong length,
## and the first unknown symbol of a row. It runs at load time, so its messages are reviewed
## allocations (`# alloc-ok`).
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var size: Vector2i = size_tiles()
	if size.x == 0 or size.y == 0:
		problems.append("map has no tiles")
	if terrain == null:
		problems.append("map has no terrain set")
	var symbols: Dictionary[String, bool] = {}
	if terrain != null:
		for i: int in terrain.terrains.size():
			var def: TerrainDef = terrain.terrains[i]
			if def == null:
				problems.append("terrain %d is null" % i)
				continue
			if symbols.has(def.symbol):
				problems.append("terrain %d repeats symbol '%s'" % [i, def.symbol])  # alloc-ok
			symbols[def.symbol] = true
			if def.cost.size() != _COST_ENTRIES:
				problems.append(
					"terrain %d has %d costs, expected %d" % [i, def.cost.size(), _COST_ENTRIES]  # alloc-ok
				)
			for entry: int in def.cost.size():
				var cost: int = def.cost[entry]
				if cost < 0 or cost > _COST_MAX:
					problems.append(
						"terrain %d cost %d is %d, expected 0..%d" % [i, entry, cost, _COST_MAX]  # alloc-ok
					)
	for y: int in rows.size():
		var row: String = rows[y]
		if len(row) != size.x:
			problems.append("row %d has %d tiles, expected %d" % [y, len(row), size.x])  # alloc-ok
		if terrain == null:
			continue
		for x: int in len(row):
			if not symbols.has(row[x]):
				problems.append("row %d column %d: unknown symbol '%s'" % [y, x, row[x]])  # alloc-ok
				break
	return problems
