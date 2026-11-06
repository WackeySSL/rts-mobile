class_name AiIntel
extends RefCounted
## The opponent AI's intel manager (ADR 0030 sections 1, 3 and 6, plan row P177): the sector map,
## the memory of sightings and the enemy base estimate. The scout is the split row P177b. It reads
## the `PlayerView` of the think and `AiMemory` and writes only the intel part of the memory. A
## hidden enemy row never enters the memory: the passes below walk `own_rows`, `seen_rows` and the
## view's ghosts, nothing else.
##
## `refresh` (ARMY slot) rebuilds the sector map, one pass over the own rows and one over the seen
## rows. `run` (INTEL slot) keeps the sightings and the base estimate, again two passes. Sectors are
## squares of `sector_tiles`, grown only when the map would need more than `sectors_max` of them.

## Copied from the defs when the manager is made.
var hq_type: StringName = &""
var sector_tiles: int = 0
var sectors_max: int = 0

## The sector grid of the map last seen: tiles per side, and sectors per row and column.
var sector_side: int = 0
var sector_cols: int = 0
var sector_rows: int = 0

## Counted work for the suites: passes over the own and seen rows by the last call.
var passes: int = 0

var _map_cols: int = 0
var _map_rows: int = 0


## A manager for `player_id` that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, _level: AiDifficultyDef, _player_id: int) -> AiIntel:
	var intel: AiIntel = AiIntel.new()
	intel.hq_type = def.hq_type
	intel.sector_tiles = maxi(def.sector_tiles, 1)
	intel.sectors_max = maxi(def.sectors_max, 1)
	return intel


## The sector of the tile (`col`, `line`), clamped to the map.
@warning_ignore("integer_division")
func sector_at(col: int, line: int) -> int:
	var inside_col: int = clampi(col, 0, maxi(_map_cols - 1, 0))
	var inside_line: int = clampi(line, 0, maxi(_map_rows - 1, 0))
	return inside_line / sector_side * sector_cols + inside_col / sector_side


## The number of sectors of the map last seen.
func sector_count() -> int:
	return sector_cols * sector_rows


## The sector map: own value and seen enemy value per sector, from this view alone. Value is the
## type's cost scaled by the row's hit points; a remembered building (a ghost nothing now shows)
## counts at its full cost.
func refresh(view: PlayerView, memory: AiMemory) -> void:
	passes = 0
	_fit(view, memory)
	memory.sector_own.fill(0)
	memory.sector_enemy.fill(0)
	for row: int in view.own_rows:
		var at: Vector2i = _tile(view.row_pos(row))
		memory.sector_own[sector_at(at.x, at.y)] += _value(view, row)
	passes = 1
	for row: int in view.seen_rows:
		if view.row_owner(row) <= 0:
			continue
		var at: Vector2i = _tile(view.row_pos(row))
		memory.sector_enemy[sector_at(at.x, at.y)] += _value(view, row)
	passes = 2
	for record: int in view.ghost_count:
		if view.ghost_owner[record] == view.player or view.row_of(view.ghost_id[record]) >= 0:
			continue
		var at: Vector2i = _tile(view.ghost_pos(record))
		memory.sector_enemy[sector_at(at.x, at.y)] += _entry(
			view.type_cost, view.ghost_type[record]
		)


## The sightings and the base estimate. Sends no Command in this row (the scout is P177b).
func run(view: PlayerView, memory: AiMemory, _rng: DetRandom, _out: Array[Command]) -> void:
	passes = 0
	_fit(view, memory)
	var home: Vector2i = Vector2i(PlayerView.MISSING, PlayerView.MISSING)
	var hq_id: int = 0x7FFFFFFF
	var hq: int = view.type_index_of(hq_type)
	for row: int in view.own_rows:
		var id: int = view.row_id(row)
		if view.row_type(row) == hq and id < hq_id:
			hq_id = id
			home = _tile(view.row_pos(row))
	passes = 1
	var found: Vector2i = _sight(view, memory, home)
	passes = 2
	if found.x >= 0:
		memory.base_x = found.x
		memory.base_y = found.y
	elif home.x >= 0:
		memory.base_x = view.map_cols - 1 - home.x
		memory.base_y = view.map_rows - 1 - home.y


## Counts the seen enemy rows and the remembered buildings per type into the sightings, and returns
## the tile of the enemy producer nearest to `home` (the map's centre while the Headquarters is
## gone), (-1, -1) for none. A remembered building a seen row now shows is read once, as a row.
@warning_ignore("integer_division")
func _sight(view: PlayerView, memory: AiMemory, home: Vector2i) -> Vector2i:
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(memory.seen_count.size())
	var from: Vector2i = home if home.x >= 0 else Vector2i(view.map_cols / 2, view.map_rows / 2)
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = -1
	var best_id: int = 0
	var seen_now: PackedInt32Array = counts.duplicate()
	for row: int in view.seen_rows:
		var owner: int = view.row_owner(row)
		if owner <= 0:
			continue
		var type: int = view.row_type(row)
		counts[type] += 1
		seen_now[type] += 1
		if _is_producer(view, type):
			var at: Vector2i = _tile(view.row_pos(row))
			var id: int = view.row_id(row)
			var distance: int = _distance(at, from)
			if _nearer(distance, id, best_distance, best_id):
				best = at
				best_distance = distance
				best_id = id
	for record: int in view.ghost_count:
		if view.ghost_owner[record] == view.player or view.row_of(view.ghost_id[record]) >= 0:
			continue
		var type: int = view.ghost_type[record]
		if type < 0 or type >= counts.size():
			continue
		counts[type] += 1
		if _is_producer(view, type):
			var at: Vector2i = _tile(view.ghost_pos(record))
			var id: int = view.ghost_id[record]
			var distance: int = _distance(at, from)
			if _nearer(distance, id, best_distance, best_id):
				best = at
				best_distance = distance
				best_id = id
	for type: int in counts.size():
		if counts[type] == 0:
			continue
		memory.seen_count[type] = counts[type]
		if memory.seen_first_tick[type] == AiMemory.NONE:
			memory.seen_first_tick[type] = view.tick
		if seen_now[type] > 0:
			memory.seen_last_tick[type] = view.tick
	return best


## The sector grid of this map, and the memory's arrays sized to it and to the view's types.
func _fit(view: PlayerView, memory: AiMemory) -> void:
	if view.map_cols != _map_cols or view.map_rows != _map_rows or sector_side == 0:
		_map_cols = view.map_cols
		_map_rows = view.map_rows
		var side: int = sector_tiles
		var longest: int = maxi(maxi(_map_cols, _map_rows), 1)
		while side < longest and _blocks(side) > sectors_max:
			side += 1
		sector_side = side
		sector_cols = _span(_map_cols, side)
		sector_rows = _span(_map_rows, side)
	var size: int = maxi(sectors_max, sector_count())
	if memory.sector_own.size() != size:
		memory.sector_own.resize(size)
		memory.sector_enemy.resize(size)
	var types: int = view.type_cost.size()
	if memory.seen_count.size() != types:
		memory.seen_count.resize(types)
		memory.seen_first_tick.resize(types)
		memory.seen_last_tick.resize(types)
		memory.seen_count.fill(0)
		memory.seen_first_tick.fill(AiMemory.NONE)
		memory.seen_last_tick.fill(AiMemory.NONE)


func _blocks(side: int) -> int:
	return _span(_map_cols, side) * _span(_map_rows, side)


@warning_ignore("integer_division")
static func _span(tiles: int, side: int) -> int:
	return (maxi(tiles, 1) + side - 1) / side


## The tile of a position in milli-tiles.
@warning_ignore("integer_division")
static func _tile(pos: Vector2i) -> Vector2i:
	var per: int = PlayerView.MILLI_PER_TILE
	return Vector2i(maxi(pos.x, 0) / per, maxi(pos.y, 0) / per)


## Whether `type` produces a tab (a building with a queue).
static func _is_producer(view: PlayerView, type: int) -> bool:
	var tab: int = (
		view.type_produces[type] if type >= 0 and type < view.type_produces.size() else -1
	)
	return tab >= 0 and tab < PlayerView.TABS


## Whether a producer at `distance` with `id` beats the best so far (none yet: a negative best);
## equal distances go to the lower id.
static func _nearer(distance: int, id: int, best_distance: int, best_id: int) -> bool:
	return (
		best_distance < 0
		or distance < best_distance
		or (distance == best_distance and id < best_id)
	)


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)


## The row's army value: its type's cost scaled by its hit points.
static func _value(view: PlayerView, row: int) -> int:
	var type: int = view.row_type(row)
	var cost: int = _entry(view.type_cost, type)
	var max_hp: int = _entry(view.type_max_hp, type)
	if max_hp <= 0:
		return cost
	return cost * clampi(view.row_hp(row), 0, max_hp) / max_hp


static func _entry(table: PackedInt32Array, index: int) -> int:
	return table[index] if index >= 0 and index < table.size() else 0
