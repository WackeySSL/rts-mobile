class_name AiIntel
extends RefCounted
## The opponent AI's intel manager (ADR 0030 sections 1, 3 and 6, plan rows P177 and P177b): the
## sector map, the memory of sightings, the enemy base estimate and the scout. It reads the
## `PlayerView` of the think and `AiMemory`, writes only the intel part of the memory and sends only
## `MOVE` for the one scout. A hidden enemy row never enters the memory: the passes below walk
## `own_rows`, `seen_rows` and the view's ghosts, nothing else.
##
## `refresh` (ARMY slot) rebuilds the sector map, one pass over the own rows and one over the seen
## rows. `run` (INTEL slot) keeps the sightings and the base estimate, again two passes (`passes`
## counts them at each loop head), and steers the scout. Sectors are squares of `sector_tiles`,
## grown only when the map would need more than `sectors_max` of them. Draws come from the
## controller's stream, one per scout pick and only among sectors at an equal distance.

## The move classes the scout's goal key names (`World.MoveClass`). The class of a type is its tab's
## (vehicles tracked, the rest on foot); a data test pins that for every roster.
const FOOT: int = AiMemory.FOOT
const TRACKED: int = AiMemory.TRACKED

## The id that no row has, larger than every real id.
const NO_ID: int = 0x7FFFFFFF

## Copied from the defs when the manager is made.
var hq_type: StringName = &""
var scout_type: StringName = &""
var sector_tiles: int = 0
var sectors_max: int = 0
var scout_first_tick: int = 0
var scout_interval_ticks: int = 0

## The sector grid of the map last seen: tiles per side, and sectors per row and column.
var sector_side: int = 0
var sector_cols: int = 0
var sector_rows: int = 0

## Counted work for the suites: passes over the own and seen rows by the last call, and over the
## match the scouts sent and the draws made.
var passes: int = 0
var scouts: int = 0
var draws: int = 0

var _map_cols: int = 0
var _map_rows: int = 0
## Scratch kept between thinks (resized and filled, never remade): the enemy rows per type, those of
## them seen now, and the nearest enemy producer so far.
var _counts: PackedInt32Array = PackedInt32Array()
var _seen_now: PackedInt32Array = PackedInt32Array()
## Per type, 1 when it is a combat unit (`DummyDefence.is_combat`).
var _combat: PackedByteArray = PackedByteArray()
var _best: Vector2i = Vector2i(-1, -1)
var _best_distance: int = -1
var _best_id: int = 0
var _tied: PackedInt32Array = PackedInt32Array()


## A manager for `player_id` that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef, _player_id: int) -> AiIntel:
	var intel: AiIntel = AiIntel.new()
	intel.hq_type = def.hq_type
	intel.scout_type = def.scout_type
	intel.scout_first_tick = level.scout_first_tick
	intel.scout_interval_ticks = level.scout_interval_ticks
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
## counts at its full cost. The same two passes fill the lists `AiArmy` reads (plan row P179).
func refresh(view: PlayerView, memory: AiMemory) -> void:
	passes = 0
	_fit(view, memory)
	memory.sector_own.fill(0)
	memory.sector_enemy.fill(0)
	memory.home_x = AiMemory.NONE
	memory.home_y = AiMemory.NONE
	memory.site_id.clear()
	memory.site_x.clear()
	memory.site_y.clear()
	memory.unit_id.clear()
	memory.unit_hp.clear()
	memory.seen_unit_id.clear()
	memory.seen_site_id.clear()
	var hq: int = view.type_index_of(hq_type)
	var scout: int = view.type_index_of(scout_type)
	var hq_id: int = NO_ID
	passes += 1
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		var pos: Vector2i = view.row_pos(row)
		var at: Vector2i = _tile(pos)
		memory.sector_own[sector_at(at.x, at.y)] += value_of(view, row)
		if _entry(view.type_foot_w, type) > 0:
			var id: int = view.row_id(row)
			memory.site_id.append(id)
			memory.site_x.append(pos.x)
			memory.site_y.append(pos.y)
			if type == hq and id < hq_id:
				hq_id = id
				memory.home_x = at.x
				memory.home_y = at.y
		elif _combat[type] != 0 and type != scout:
			memory.unit_id.append(view.row_id(row))
			memory.unit_hp.append(view.row_hp(row))
	passes += 1
	for row: int in view.seen_rows:
		if view.row_owner(row) <= 0:
			continue
		var at: Vector2i = _tile(view.row_pos(row))
		memory.sector_enemy[sector_at(at.x, at.y)] += value_of(view, row)
		if _combat[view.row_type(row)] != 0:
			memory.seen_unit_id.append(view.row_id(row))
		elif _entry(view.type_foot_w, view.row_type(row)) > 0:
			memory.seen_site_id.append(view.row_id(row))
	for record: int in view.ghost_count:
		if not _remembered(view, record):
			continue
		var at: Vector2i = _tile(view.ghost_pos(record))
		memory.sector_enemy[sector_at(at.x, at.y)] += _entry(
			view.type_cost, view.ghost_type[record]
		)


## The sightings, the base estimate and the scout. Appends at most the scout's `MOVE`, and only
## within `memory.can_send`. Sets `memory.scout_wanted` while a trip is due and nothing could go.
func run(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> void:
	passes = 0
	_fit(view, memory)
	var home: Vector2i = Vector2i(PlayerView.MISSING, PlayerView.MISSING)
	var hq_id: int = NO_ID
	var pick: int = NO_ID
	var scout_rows: int = 0
	var hq: int = view.type_index_of(hq_type)
	var scout: int = view.type_index_of(scout_type)
	passes += 1
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		var id: int = view.row_id(row)
		if type == hq and id < hq_id:
			hq_id = id
			home = _tile(view.row_pos(row))
		elif type == scout:
			scout_rows += 1
			if id < pick and view.row_order(row) == PlayerView.Order.IDLE:
				pick = id
	var found: Vector2i = _sight(view, memory, home)
	if found.x >= 0:
		memory.base_x = found.x
		memory.base_y = found.y
	elif home.x >= 0:
		var mirror: Vector2i = AiMemory.mirror(home, view.map_cols, view.map_rows)
		memory.base_x = mirror.x
		memory.base_y = mirror.y
	memory.scout_wanted = AiMemory.NONE
	if scout_interval_ticks <= 0:
		return
	if memory.scout_id != AiMemory.NONE:
		_steer(view, memory, rng, out, home)
	elif home.x >= 0 and scout >= 0 and _due(view, memory):
		_start(view, memory, out, home, scout, scout_rows, pick)


## Counts the seen enemy rows and the remembered buildings per type into the sightings, and returns
## the tile of the enemy producer, seen or remembered, nearest to `home` (the map's centre while
## the Headquarters is gone; ties to the lower id), (-1, -1) for none.
@warning_ignore("integer_division")
func _sight(view: PlayerView, memory: AiMemory, home: Vector2i) -> Vector2i:
	_counts.fill(0)
	_seen_now.fill(0)
	_best = Vector2i(-1, -1)
	_best_distance = -1
	_best_id = 0
	var from: Vector2i = home if home.x >= 0 else Vector2i(view.map_cols / 2, view.map_rows / 2)
	passes += 1
	for row: int in view.seen_rows:
		if view.row_owner(row) <= 0:
			continue
		var type: int = view.row_type(row)
		_counts[type] += 1
		_seen_now[type] += 1
		if _is_producer(view, type):
			_offer(_tile(view.row_pos(row)), view.row_id(row), from)
	for record: int in view.ghost_count:
		if not _remembered(view, record):
			continue
		var type: int = view.ghost_type[record]
		if type < 0 or type >= _counts.size():
			continue
		_counts[type] += 1
		if _is_producer(view, type):
			_offer(_tile(view.ghost_pos(record)), view.ghost_id[record], from)
	for type: int in _counts.size():
		if _counts[type] == 0:
			continue
		memory.seen_count[type] = _counts[type]
		if memory.seen_first_tick[type] == AiMemory.NONE:
			memory.seen_first_tick[type] = view.tick
		if _seen_now[type] > 0:
			memory.seen_last_tick[type] = view.tick
	return _best


## Takes the producer at `at` with `id` as the nearest to `from` when it beats the best so far
## (equal distances go to the lower id).
func _offer(at: Vector2i, id: int, from: Vector2i) -> void:
	var distance: int = _distance(at, from)
	if (
		_best_distance < 0
		or distance < _best_distance
		or (distance == _best_distance and id < _best_id)
	):
		_best = at
		_best_distance = distance
		_best_id = id


## Whether the ghost `record` is a building of another player that no row of the view shows now (a
## seen building is read as its row, once).
static func _remembered(view: PlayerView, record: int) -> bool:
	return view.ghost_owner[record] != view.player and view.row_of(view.ghost_id[record]) < 0


## Whether a trip may begin now: the first tick has come and the interval since the last trip's
## start has passed.
func _due(view: PlayerView, memory: AiMemory) -> bool:
	if view.tick < scout_first_tick:
		return false
	return (
		memory.scout_trip_tick == AiMemory.NONE
		or view.tick - memory.scout_trip_tick >= scout_interval_ticks
	)


## A trip is due. Asks for a scout (`scout_wanted`, the type index) when the key rule allows a trip
## and no unit of the type lives; with idle units, sends the lowest id first to the point mirror
## of the Headquarters (not the base estimate: the estimate may be a producer already known).
func _start(
	view: PlayerView,
	memory: AiMemory,
	out: Array[Command],
	home: Vector2i,
	scout: int,
	scout_rows: int,
	id: int
) -> void:
	var target: Vector2i = AiMemory.mirror(home, view.map_cols, view.map_rows)
	var move_class: int = AiMemory.class_of(view, scout)
	if not _allowed(memory, target.x, target.y, move_class):
		return
	if scout_rows == 0:
		memory.scout_wanted = scout
		return
	var row: int = view.row_of(id)
	if row < 0 or not _go(view, memory, out, id, target.x, target.y):
		return
	memory.scout_id = id
	memory.scout_waypoint = 0
	memory.scout_trip_tick = view.tick
	memory.scout_hp = view.row_hp(row)
	memory.scout_picked[sector_at(target.x, target.y)] = view.tick
	scouts += 1


## One think of a scout that is out: lost, on its way home, or on its trip.
func _steer(
	view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command], home: Vector2i
) -> void:
	var row: int = view.row_of(memory.scout_id)
	if row < 0:
		_end(memory)
	elif memory.scout_waypoint == AiMemory.NONE:
		memory.scout_hp = view.row_hp(row)
		if view.row_order(row) == PlayerView.Order.IDLE:
			_end(memory)
	elif home.x >= 0:
		_travel(view, memory, rng, out, home, row)
	else:
		_end(memory)  # The Headquarters is gone: nowhere to go home to, the trip is over.


## A scout on its trip: hit (home), travelling, or arrived (the next sector). A hit stays
## remembered until the move home is sent, and an idle scout that cannot move on lets go of its
## goal key.
func _travel(
	view: PlayerView,
	memory: AiMemory,
	rng: DetRandom,
	out: Array[Command],
	home: Vector2i,
	row: int
) -> void:
	var hp: int = view.row_hp(row)
	if memory.scout_hp != AiMemory.NONE and hp < memory.scout_hp:
		if _return(view, memory, out, home):
			memory.scout_hp = hp
		elif view.row_order(row) == PlayerView.Order.IDLE:
			_drop_key(memory)
		return
	memory.scout_hp = hp
	if view.row_order(row) != PlayerView.Order.IDLE:
		return
	if not _may_go(memory):
		_drop_key(memory)
		return
	var next: int = _nearest_unexplored(view, memory, rng, _tile(view.row_pos(row)))
	if next < 0:
		_return(view, memory, out, home)
		return
	var target: Vector2i = _centre(view, next)
	if _go(view, memory, out, memory.scout_id, target.x, target.y):
		memory.scout_picked[next] = view.tick
		memory.scout_waypoint += 1


## Sends the scout home and marks the trip as over once it gets there. True when sent.
func _return(view: PlayerView, memory: AiMemory, out: Array[Command], home: Vector2i) -> bool:
	if not _go(view, memory, out, memory.scout_id, home.x, home.y):
		return false
	memory.scout_waypoint = AiMemory.NONE
	return true


## The unexplored sector, not yet picked on this trip, whose centre is nearest to `at`; a draw
## settles sectors at an equal distance. -1 for none.
func _nearest_unexplored(view: PlayerView, memory: AiMemory, rng: DetRandom, at: Vector2i) -> int:
	_tied.clear()
	var best: int = -1
	for sector: int in sector_count():
		if memory.scout_picked[sector] >= memory.scout_trip_tick:
			continue
		var centre: Vector2i = _centre(view, sector)
		if view.is_explored(centre.y * view.map_cols + centre.x):
			continue
		var distance: int = _distance(centre, at)
		if best < 0 or distance < best:
			best = distance
			_tied.clear()
			_tied.append(sector)
		elif distance == best:
			_tied.append(sector)
	if _tied.is_empty():
		return -1
	if _tied.size() == 1:
		return _tied[0]
	draws += 1
	return _tied[rng.next_int(_tied.size())]


## Whether the scout may order anything now: budget left, the army goal holding at most one key
## (ADR 0030 section 4), and room for a key of its own.
func _may_go(memory: AiMemory) -> bool:
	return (
		memory.can_send()
		and memory.goal_keys_of(AiMemory.Owner.ARMY) <= 1
		and _free_keys(memory) > 0
	)


## Whether a trip to (`col`, `line`) fits the key rule, budget aside.
func _allowed(memory: AiMemory, col: int, line: int, move_class: int) -> bool:
	return (
		memory.goal_keys_of(AiMemory.Owner.ARMY) <= 1 and _key_room(memory, col, line, move_class)
	)


## One `MOVE` of unit `id` to tile (`col`, `line`), with the scout's goal key: only within the
## budget and the key rule. Releases the scout's old key and takes the new one. False, and nothing
## changed, when any of that fails.
func _go(
	view: PlayerView, memory: AiMemory, out: Array[Command], id: int, col: int, line: int
) -> bool:
	var row: int = view.row_of(id)
	if row < 0 or not memory.can_send():
		return false
	var move_class: int = AiMemory.class_of(view, view.row_type(row))
	if not _allowed(memory, col, line, move_class):
		return false
	_drop_key(memory)
	memory.add_goal_key(col, line, move_class, AiMemory.Owner.SCOUT)
	memory.spent()
	out.append(
		Command.move(
			view.player,
			PackedInt32Array([id]),
			col * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE,
			line * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
		)
	)
	return true


## Whether the key (`col`, `line`, `move_class`) is live or fits once the scout's own is released.
func _key_room(memory: AiMemory, col: int, line: int, move_class: int) -> bool:
	for at: int in memory.goal_keys():
		if (
			memory.goal_x[at] == col
			and memory.goal_y[at] == line
			and memory.goal_class[at] == move_class
		):
			return true
	return _free_keys(memory) > 0


## The keys that fit under the cap once the scout's own key (when only it uses it) is released.
func _free_keys(memory: AiMemory) -> int:
	var live: int = memory.goal_keys()
	for mask: int in memory.goal_owner:
		if mask == 1 << AiMemory.Owner.SCOUT:
			live -= 1
	return memory.goal_keys_max - live


## Releases the scout's goal key, if it holds one.
func _drop_key(memory: AiMemory) -> void:
	for at: int in range(memory.goal_keys() - 1, -1, -1):
		if memory.goal_owner[at] & (1 << AiMemory.Owner.SCOUT) != 0:
			memory.release_goal_key(at, AiMemory.Owner.SCOUT)


## The trip is over: the scout is lost or home, its key is free and it is no one's scout.
func _end(memory: AiMemory) -> void:
	_drop_key(memory)
	memory.scout_id = AiMemory.NONE
	memory.scout_waypoint = 0
	memory.scout_hp = AiMemory.NONE


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
	if memory.scout_picked.size() != size:
		memory.scout_picked.resize(size)
		memory.scout_picked.fill(AiMemory.NONE)
	var types: int = view.type_cost.size()
	if memory.seen_count.size() != types:
		memory.seen_count.resize(types)
		memory.seen_first_tick.resize(types)
		memory.seen_last_tick.resize(types)
		memory.seen_count.fill(0)
		memory.seen_first_tick.fill(AiMemory.NONE)
		memory.seen_last_tick.fill(AiMemory.NONE)
	if _counts.size() != types:
		_counts.resize(types)
		_seen_now.resize(types)
	if _combat.size() != types:
		_combat.resize(types)
		for type: int in types:
			_combat[type] = 1 if DummyDefence.is_combat(view, type) else 0


func _blocks(side: int) -> int:
	return _span(_map_cols, side) * _span(_map_rows, side)


@warning_ignore("integer_division")
static func _span(tiles: int, side: int) -> int:
	return (maxi(tiles, 1) + side - 1) / side


## The centre tile of `sector`, inside the map.
@warning_ignore("integer_division")
func _centre(view: PlayerView, sector: int) -> Vector2i:
	var col: int = sector % sector_cols * sector_side + sector_side / 2
	var line: int = sector / sector_cols * sector_side + sector_side / 2
	return Vector2i(mini(col, view.map_cols - 1), mini(line, view.map_rows - 1))


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


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)


## The row's army value: its type's cost scaled by its hit points.
static func value_of(view: PlayerView, row: int) -> int:
	var type: int = view.row_type(row)
	var cost: int = _entry(view.type_cost, type)
	var max_hp: int = _entry(view.type_max_hp, type)
	if max_hp <= 0:
		return cost
	return cost * clampi(view.row_hp(row), 0, max_hp) / max_hp


static func _entry(table: PackedInt32Array, index: int) -> int:
	return table[index] if index >= 0 and index < table.size() else 0
