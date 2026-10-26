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
## a tab has had a producer for good (`had_producer`, ADR 0018 section 7), and every ATTACK row
## whose goal tile is now inside the footprint re-picks its approach point. A world with a size but
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
	_repick(world, col, line, width, height)
	return id


## The top-left tile of row `row`'s footprint; for a row with no footprint, the tile that holds it.
static func footprint_origin(world: World, row: int) -> Vector2i:
	var type: int = world.type_index[row]
	return _origin(
		world.pos_x[row],
		world.pos_y[row],
		_entry(world.type_foot_w, type, 0),
		_entry(world.type_foot_h, type, 0)
	)


## Gives the footprint tiles of every dead building (hp of 0 or less) the cost `set_terrain` would
## write for their terrain, and bumps `map_version` once, with the flow cache, when there was one.
## World.remove_dead() calls it before the rows leave, because the origin comes from the position.
static func unblock_dead(world: World) -> void:
	var alive: PackedInt32Array = world.hp
	var types: PackedInt32Array = world.type_index
	var widths: PackedInt32Array = world.type_foot_w
	var heights: PackedInt32Array = world.type_foot_h
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var died: bool = false
	for row: int in alive.size():
		if alive[row] > 0 or types[row] >= widths.size() or widths[types[row]] <= 0:
			continue
		var width: int = widths[types[row]]
		var height: int = _entry(heights, types[row], 0)
		var origin: Vector2i = _origin(pos_x[row], pos_y[row], width, height)
		_write_cost(world, origin.x, origin.y, width, height, true)
		died = true
	if died:
		world.map_version += 1
		world.flow.invalidate(world.map_version)


## The point an ATTACK on building row `target_row` aims `row` at (ADR 0017 section 1): the
## centre of the ring tile (8-adjacent to the footprint, outside it, inside the map) that is
## passable for the row's class and nearest to the row's position by squared distance, then by
## the lower tile index. (-1, -1) when no ring tile is passable.
@warning_ignore("integer_division")
static func approach_point(world: World, row: int, target_row: int) -> Vector2i:
	var cols: int = world.map_cols
	var lines: int = world.map_rows
	var type: int = world.type_index[target_row]
	var origin: Vector2i = footprint_origin(world, target_row)
	var width: int = _entry(world.type_foot_w, type, 0)
	var height: int = _entry(world.type_foot_h, type, 0)
	var base: int = world.type_move_class[world.type_index[row]] * cols * lines
	var tile: int = World.MILLI_PER_TILE
	var best: int = -1
	var best_d2: int = 0
	for line: int in range(maxi(origin.y - 1, 0), mini(origin.y + height, lines - 1) + 1):
		for col: int in range(maxi(origin.x - 1, 0), mini(origin.x + width, cols - 1) + 1):
			var inside: bool = (
				col >= origin.x
				and col < origin.x + width
				and line >= origin.y
				and line < origin.y + height
			)
			var cell: int = line * cols + col
			if inside or world.move_cost[base + cell] == 0:
				continue
			var dx: int = col * tile + World.TILE_CENTRE - world.pos_x[row]
			var dy: int = line * tile + World.TILE_CENTRE - world.pos_y[row]
			if best < 0 or dx * dx + dy * dy < best_d2:
				best = cell
				best_d2 = dx * dx + dy * dy
	if best < 0:
		return Vector2i(-1, -1)
	return Vector2i(best % cols * tile + World.TILE_CENTRE, best / cols * tile + World.TILE_CENTRE)


## What an ATTACK on `target_row` does to the goals of `rows`, and which of them it keeps. A mobile
## target (speed above 0) leaves them alone: TARGETING writes the goal from its position every tick.
## A target that stands still gets no such write (TARGETING skips it, in both twins), so the command
## writes it once: a building's approach point, a row without one left out; any other speed-0 target
## is aimed at where it stands, as the lock did before buildings.
static func aim(world: World, rows: PackedInt32Array, target_row: int) -> PackedInt32Array:
	var type: int = world.type_index[target_row]
	if world.type_speed[type] > 0:
		return rows
	var footprint: bool = _entry(world.type_foot_w, type, 0) > 0
	var kept: PackedInt32Array = PackedInt32Array()
	for row: int in rows:
		var point: Vector2i = Vector2i(world.pos_x[target_row], world.pos_y[target_row])
		if footprint:
			point = approach_point(world, row, target_row)
			if point.x < 0:
				continue
		world.goal_x[row] = point.x
		world.goal_y[row] = point.y
		kept.append(row)
	return kept


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


## The top-left tile of a footprint of width x height tiles whose centre is (x, y) milli-tiles.
@warning_ignore("integer_division")
static func _origin(x: int, y: int, width: int, height: int) -> Vector2i:
	return Vector2i(
		(x - width * World.TILE_CENTRE) / World.MILLI_PER_TILE,
		(y - height * World.TILE_CENTRE) / World.MILLI_PER_TILE
	)


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
	var cols: int = world.map_cols
	var cells: int = cols * world.map_rows
	var kinds: PackedByteArray = world.terrain
	var costs: PackedByteArray = world.terrain_cost
	var cost: PackedByteArray = world.move_cost
	for y: int in range(line, line + height):
		for x: int in range(col, col + width):
			var cell: int = y * cols + x
			var kind: int = kinds[cell]
			if restore and (kind + 1) * classes > costs.size():
				continue
			for move_class: int in classes:
				cost[move_class * cells + cell] = (
					costs[kind * classes + move_class] if restore else 0
				)


## The re-pick of `add()`: every ATTACK row whose goal tile lies in the new footprint and whose
## target is a building takes a new approach point; a row with no passable ring tile keeps its goal.
## A mobile target needs nothing: TARGETING rewrites the goal from its position every tick.
@warning_ignore("integer_division")
static func _repick(world: World, col: int, line: int, width: int, height: int) -> void:
	var orders: PackedInt32Array = world.order
	for row: int in orders.size():
		if orders[row] != World.Order.ATTACK:
			continue
		var cell: int = world.cell_of(world.goal_x[row], world.goal_y[row])
		var x: int = cell % world.map_cols
		var y: int = cell / world.map_cols
		if x < col or x >= col + width or y < line or y >= line + height:
			continue
		var at: int = world.index_of(world.order_target[row])
		if at < 0 or _entry(world.type_foot_w, world.type_index[at], 0) <= 0:
			continue
		var point: Vector2i = approach_point(world, row, at)
		if point.x >= 0:
			world.goal_x[row] = point.x
			world.goal_y[row] = point.y
