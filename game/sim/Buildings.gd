class_name Buildings
extends RefCounted
## Buildings as rows (ADR 0017 section 1), kept out of World.gd so that file stays under gdlint's
## 1,000 lines: static helpers over the World passed in. World.add_building() and
## World.footprint_origin() wrap add() and footprint_origin(), World.remove_dead() calls
## unblock_dead(), Power.run calls rebuild_lists(). A building is a row of a type with a footprint
## (`type_foot_w` and `type_foot_h` above 0) whose position is the footprint centre, `origin * 1000
## + foot * 500` on each axis, so the origin is derived and no column stores it. Event cadence
## throughout, but rebuild_lists(): one scan on a tick where `rows_version` moved.


## Appends a building of `type` for `owner` with its top-left tile at (col, line) and returns its
## id, or 0 when it is refused: a type with no footprint or one that is not wholly on the map (both
## counted in `spawn_refused`), or add_unit's own refusals. The row comes through add_unit (the
## SPAWNED event, `rows_version`, the row cap). Then every footprint tile costs 0 for every class,
## `map_version` goes up once, the flow cache is invalidated, and an owner whose building produces
## a tab has had a producer for good (`had_producer`, ADR 0018 section 7). A world with a size but
## no grid yet gets the open grass prepare() would make. The ground is not checked: Placement
## judges that for a PLACE, and data keeps a scenario's buildings apart.
static func add(world: World, owner: int, type: int, col: int, line: int) -> int:
	var width: int = _entry(world.type_foot_w, type, 0)
	var height: int = _entry(world.type_foot_h, type, 0)
	if world.map_cols == 0 and world.map_w > 0 and world.map_h > 0:
		WorldLoad.derive_open_grass(world)
	if (
		width <= 0
		or height <= 0
		or col < 0
		or line < 0
		or col + width > world.map_cols
		or line + height > world.map_rows
	):
		world.spawn_refused += 1
		return 0
	var id: int = world.add_unit(
		owner,
		type,
		col * World.MILLI_PER_TILE + width * World.TILE_CENTRE,
		line * World.MILLI_PER_TILE + height * World.TILE_CENTRE
	)
	if id == 0:
		return 0
	_write_cost(world, col, line, width, height, false)
	world.map_version += 1
	world.flow.invalidate(world.map_version)
	if owner >= 1 and _entry(world.type_produces, type, -1) >= 0:
		if world.had_producer.size() <= owner:
			world.had_producer.resize(owner + 1)  # Before prepare() sizes it; the 1 survives.
		world.had_producer[owner] = 1
	return id


## The top-left tile of row `row`'s footprint; for a row with no footprint, the tile that holds it.
@warning_ignore("integer_division")
static func footprint_origin(world: World, row: int) -> Vector2i:
	var type: int = world.type_index[row]
	var half_w: int = _entry(world.type_foot_w, type, 0) * World.TILE_CENTRE
	var half_h: int = _entry(world.type_foot_h, type, 0) * World.TILE_CENTRE
	return Vector2i(
		(world.pos_x[row] - half_w) / World.MILLI_PER_TILE,
		(world.pos_y[row] - half_h) / World.MILLI_PER_TILE
	)


## Gives the footprint tiles of every dead building (hp of 0 or less) the cost `set_terrain` would
## write for their terrain, and bumps `map_version` once, with the flow cache, when there was one.
## World.remove_dead() calls it before the rows leave, because the origin comes from the position.
static func unblock_dead(world: World) -> void:
	var alive: PackedInt32Array = world.hp
	var types: PackedInt32Array = world.type_index
	var widths: PackedInt32Array = world.type_foot_w
	var died: bool = false
	for row: int in alive.size():
		if alive[row] > 0 or types[row] >= widths.size() or widths[types[row]] <= 0:
			continue
		var origin: Vector2i = footprint_origin(world, row)
		var height: int = _entry(world.type_foot_h, types[row], 0)
		_write_cost(world, origin.x, origin.y, widths[types[row]], height, true)
		died = true
	if died:
		world.map_version += 1
		world.flow.invalidate(world.map_version)


## Rebuilds `building_rows` (rows of a type with a footprint) and `harvester_rows` (mobile rows of
## a type with a cargo capacity, ADR 0018 section 3), both ascending, when `rows_version` has moved
## since the last rebuild, and says whether it did. They are derived (ADR 0016): equal to a scan of
## the rows whenever the version is current, and in no hash section. Power.run calls it first in
## ECONOMY.
static func rebuild_lists(world: World) -> bool:
	if world._lists_version == world.rows_version:
		return false
	world._lists_version = world.rows_version
	var types: PackedInt32Array = world.type_index
	var widths: PackedInt32Array = world.type_foot_w
	var speeds: PackedInt32Array = world.type_speed
	var cargo: PackedInt32Array = world.type_harvest
	var known: int = mini(widths.size(), mini(speeds.size(), cargo.size()))
	var buildings: PackedInt32Array = world.building_rows
	var harvesters: PackedInt32Array = world.harvester_rows
	buildings.clear()
	harvesters.clear()
	for row: int in types.size():
		var type: int = types[row]
		if type >= known:
			continue
		if widths[type] > 0:
			buildings.append(row)
		elif speeds[type] > 0 and cargo[type] > 0:
			harvesters.append(row)
	return true


## `table[type]`, or `missing` for a type past the table (a hand-built world before prepare()
## pads it): 0 for a size, -1 for a tab.
static func _entry(table: PackedInt32Array, type: int, missing: int) -> int:
	return table[type] if type >= 0 and type < table.size() else missing


## Writes the cost of the width x height tiles from (col, line): 0 for every class, or with
## `restore` what `set_terrain` writes for the tile's terrain (none for a terrain with no cost row).
static func _write_cost(
	world: World, col: int, line: int, width: int, height: int, restore: bool
) -> void:
	var classes: int = World.MoveClass.size()
	var cells: int = world.map_cols * world.map_rows
	var costs: PackedByteArray = world.terrain_cost
	var cost: PackedByteArray = world.move_cost
	for y: int in range(line, line + height):
		for x: int in range(col, col + width):
			var cell: int = y * world.map_cols + x
			var kind: int = world.terrain[cell]
			if restore and (kind + 1) * classes > costs.size():
				continue
			for move_class: int in classes:
				cost[move_class * cells + cell] = (
					costs[kind * classes + move_class] if restore else 0
				)
