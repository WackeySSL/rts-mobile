class_name ProductionSpawn
extends RefCounted
## A finished unit joins the map (ADR 0018 section 5), split out of Production.gd: the holds, the
## exit walk, the new row and its first order. Static helpers over the World passed in, at event
## cadence (one call per finished unit, and per tick while a finished unit waits).


## Spawns one finished unit of `type` for `player` at the exit of `producer` (a building row) and
## returns true, or returns false and changes nothing but `stats` when it has to wait: `max_rows`
## rows exist, the player has `unit_cap` mobile rows (type speed above 0, harvesters among them) or
## no exit tile is free. The holds are tested before the walk, so a held unit counts no
## `EXIT_SCANNED`, and before `add_unit`, so a wait is not a `spawn_refused`. The new row gets its
## first order (`_start`).
static func spawn(world: World, player: int, type: int, producer: int) -> bool:
	if world.unit_id.size() >= world.max_rows or mobile_rows(world, player) >= world.unit_cap:
		return false
	var tile: Vector2i = exit_tile(world, producer, world.type_move_class[type])
	if tile.x < 0:
		return false
	var id: int = world.add_unit(
		player,
		type,
		tile.x * World.MILLI_PER_TILE + World.TILE_CENTRE,
		tile.y * World.MILLI_PER_TILE + World.TILE_CENTRE
	)
	if id == 0:
		return false
	_start(world, player, type, world.unit_id.size() - 1)
	return true


## How many rows of `player` can move (their type's speed is above 0): what `unit_cap` counts.
static func mobile_rows(world: World, player: int) -> int:
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var speeds: PackedInt32Array = world.type_speed
	var count: int = 0
	for row: int in owners.size():
		if owners[row] == player and speeds[types[row]] > 0:
			count += 1
	return count


## The tile where a unit of `move_class` appears at building row `producer`: the exit tile (the
## footprint's origin plus the type's `type_exit_x`, `type_exit_y`) when its cost for the class is
## above 0, else the first such tile of the ring around the footprint, walked clockwise from the
## exit (ring_tile). Every ring tile on the map that it looks at counts one `Stat.EXIT_SCANNED`;
## a ring tile outside the map is skipped without a count. (-1, -1) when none is open. An exit that
## is not on the ring (data keeps it so) starts the walk at ring tile 0.
static func exit_tile(world: World, producer: int, move_class: int) -> Vector2i:
	var type: int = world.type_index[producer]
	var size: Vector2i = Vector2i(world.type_foot_w[type], world.type_foot_h[type])
	var origin: Vector2i = world.footprint_origin(producer)
	var exit: Vector2i = origin + Vector2i(world.type_exit_x[type], world.type_exit_y[type])
	var length: int = ring_length(size)
	var first: int = 0
	for at: int in length:
		if ring_tile(origin, size, at) == exit:
			first = at
			break
	var cols: int = world.map_cols
	var lines: int = world.map_rows
	var stats: PackedInt32Array = world.stats
	for step: int in length:
		var tile: Vector2i = ring_tile(origin, size, (first + step) % length)
		if tile.x < 0 or tile.y < 0 or tile.x >= cols or tile.y >= lines:
			continue
		stats[World.Stat.EXIT_SCANNED] += 1
		if world.is_passable(tile.y * cols + tile.x, move_class):
			return tile
	return Vector2i(-1, -1)


## The number of tiles in the ring around a footprint of `size` tiles: the 8-neighbours of the
## rectangle that lie outside it, 2 * (width + height) + 4.
static func ring_length(size: Vector2i) -> int:
	return 2 * (size.x + size.y) + 4


## Ring tile `at` (0 up to ring_length - 1) of the footprint whose top-left tile is `origin`,
## clockwise on the screen (y grows downwards): along the top row from the top-left corner tile,
## down the right column from the top-right corner, back along the bottom row from the bottom-right
## corner and up the left column from the bottom-left corner. Each side holds its starting corner
## and not the next one, so no tile repeats. Tiles off the map are included.
static func ring_tile(origin: Vector2i, size: Vector2i, at: int) -> Vector2i:
	var across: int = size.x + 1
	var down: int = size.y + 1
	var left: int = origin.x - 1
	var top: int = origin.y - 1
	var right: int = origin.x + size.x
	var bottom: int = origin.y + size.y
	if at < across:
		return Vector2i(left + at, top)
	at -= across
	if at < down:
		return Vector2i(right, top + at)
	at -= down
	if at < across:
		return Vector2i(right - at, bottom)
	at -= across
	return Vector2i(left, bottom - at)


## The first order of the new row `row` of `player`'s `type`: a harvester starts in SEEK with no
## home (ADR 0018 section 3) and ignores the rally point; any other unit gets a MOVE to its tab's
## rally point, when one is set, through the rule of a one-unit MOVE (Formation.assign takes the
## nearest open tile, then the order and a fresh DIRECT navigation as Sim._apply_point gives them).
static func _start(world: World, player: int, type: int, row: int) -> void:
	if world.type_harvest[type] > 0:
		world.harvest_mode[row] = World.HarvestMode.SEEK
		return
	var queue: int = player * World.TABS + world.type_tab[type]
	var point_x: int = world.rally_x[queue]
	var point_y: int = world.rally_y[queue]
	if point_x < 0 or point_y < 0:
		return
	var rows: PackedInt32Array = PackedInt32Array([row])
	Formation.assign(world, rows, point_x, point_y)
	world.order[row] = World.Order.MOVE
	Movement.reset_nav(world, rows, World.NavMode.DIRECT)
