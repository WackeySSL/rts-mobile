class_name PlayerView
extends RefCounted
## One player's legal view of a World (ADR 0020 section 1, plan row P78): what that player may know
## and may ask, in one pure object, so the AI (`game/ai`, which never names the World) and any
## other reader play by the player's rules. `PlayerView.of(world, player)` makes one, once per
## think, inside the tick job (ADR 0020 section 3: on the worker in WORKER, inline in SYNC). It
## reads the World and writes nothing, and keeps no reference to it.
##
## What it gives:
## - `own_rows`: the rows with `owner == player`, and `seen_rows`: the rows of any other owner (an
##   enemy, or the neutral 0) whose cell the player's fog shows visible now, the rule of
##   `Targeting.sees` (the cell holding the row, in the player's block of `fog.visible`). Both are
##   ascending World rows, built in one pass over the table. A row is the index the per-row getters
##   take. It is only good for the tick the view was made on (the table compacts when a row dies).
## - Per-row getters. The public columns (`row_id`, `row_owner`, `row_type`, `row_pos`, `row_hp`) of
##   an own or a seen row; the own columns (`row_order`, `row_harvest_mode`, `row_home`) of an own
##   row only. Any other row, a row index outside the table and an own column of an enemy row all
##   answer MISSING (`row_pos` as (MISSING, MISSING)), as if the row did not exist. `row_of(id)`
##   is the way back from an id and answers MISSING for an id the player does not see.
## - The player's own state: `credits`; its queues per tab (`queue_count`, `queue_progress`,
##   `queue_type`, `rally_x`, `rally_y`, indexed by tab, and `queue_type` by `tab * queue_slots +
##   slot`, as the World's arrays with the player stripped off) and `structure_ready()`; the
##   power totals `power_made` and `power_used` and `low_power` (`Power.is_low`, as ECONOMY left
##   them).
## - The map as the player knows it: `is_explored(cell)`, and `placement(type_index, col, row)`,
##   which is `Placement.reason` for this player (the answer a PLACE would get now). Placement
##   reads every row, as the sim's PLACE does, so a tile held by a mobile enemy row that the
##   player does not see answers OCCUPIED: the sim would refuse that PLACE too, and a controller
##   that never sends a refused Command needs the same answer.
## - The last-seen records (plan row P77, ADR 0017 section 3): the buildings the player saw and has
##   not seen gone (`LastSeen`), as its own block of the World's ghost arrays with the player
##   stripped off, copied in `of` like the queue slices: `ghost_count` records, record `i` being
##   `ghost_id[i]`, `ghost_type[i]`, `ghost_owner[i]` and `ghost_cell[i]` (the tile that holds the
##   building), in the order the sim keeps them. A record is the player's own memory, so no fog
##   hides it: it may be stale (the building died out of sight) and it may be of a building the
##   player sees now, which `seen_rows` lists as well. `ghost_of(id)` finds a record by building id
##   and `ghost_pos(i)` gives its position, the footprint centre in milli-tiles as `row_pos` gives
##   it for a live building.
## - The rules, which no fog hides: the type tables the AI reads (`type_cost`, `type_tab`, ...),
##   `type_index_of(id)`, `is_refinery(type)`, and the World's constants it needs, re-exported
##   (`Tab`, `HarvestMode`, `Order`, `TABS`, `MILLI_PER_TILE`, `TILE_CENTRE`).
##
## Aliasing (ADR 0012 section 2, as `PlacementInput`): GDScript passes a packed array by reference,
## so an array the view takes from the World without copying is the World's own and live: it shows
## the World's later writes, and a write through it would be the World's. So nothing a caller can
## reach is an alias. Every public field is a copy (the two lists, the slices of the player's state
## and last-seen records, the type tables, the type ids); the row columns and the placement input,
## which a think reads a few rows of and so are not worth a copy of the table, are aliases behind an
## underscore, read only by the getters below and written by nothing. A view is made, read and
## dropped within one think, never kept across a tick: its aliases follow the World, its lists and
## slices do not, and a row index is good only for the tick it was made on (the table compacts when
## a row dies). The per-row getters are for event cadence, a few reads per row of a think, not a
## per-tick loop.

## The World's enums the AI names, re-exported with the World's values (a test pins each pair), so
## that `game/ai` never names `World`: the production tabs, the harvest modes of a harvester row
## and the orders of a row.
enum Tab {
	STRUCTURES = World.Tab.STRUCTURES,
	INFANTRY = World.Tab.INFANTRY,
	VEHICLES = World.Tab.VEHICLES,
}
enum HarvestMode {
	IDLE = World.HarvestMode.IDLE,
	SEEK = World.HarvestMode.SEEK,
	MINE = World.HarvestMode.MINE,
	RETURN = World.HarvestMode.RETURN,
	UNLOAD = World.HarvestMode.UNLOAD,
}
enum Order {
	IDLE = World.Order.IDLE,
	ATTACK_MOVE = World.Order.ATTACK_MOVE,
	MOVE = World.Order.MOVE,
	ATTACK = World.Order.ATTACK,
}

## The answer for what the player cannot see or ask: a hidden row, a row index outside the table, an
## own column of someone else's row, an id or a type name that no row or type has.
const MISSING: int = -1
## How many production tabs there are, and the units of a position: 1 tile is 1,000 milli-tiles
## and a building's position is its footprint centre (origin * 1000 + foot * 500).
const TABS: int = World.TABS
const MILLI_PER_TILE: int = World.MILLI_PER_TILE
const TILE_CENTRE: int = World.TILE_CENTRE
## The values of `_shown`, one byte per row of the table.
const _HIDDEN: int = 0
const _OWN: int = 1
const _SEEN: int = 2
## The largest id a column of the World can hold (its ids are 32-bit ints, counted up from 1).
const _MAX_ID: int = 0x7FFFFFFF

## The player the view is for, the World's tick it was made on, and the map's size in tiles. A cell
## is `tile_row * map_cols + tile_col`, as `World.cell_of`.
var player: int = 0
var tick: int = 0
var map_cols: int = 0
var map_rows: int = 0
## The player's credits, and its power: the totals of the buildings' `type_power` (made is the
## positive entries, used the negative ones as positive numbers) and whether it is on low power.
var credits: int = 0
var power_made: int = 0
var power_used: int = 0
var low_power: bool = false
## The rows the player owns, and the rows of other owners that it sees: ascending World rows.
var own_rows: PackedInt32Array = PackedInt32Array()
var seen_rows: PackedInt32Array = PackedInt32Array()
## The player's queues: `queue_slots` places per tab, `queue_count[tab]` of them in use with the
## head first in `queue_type[tab * queue_slots]` (-1 in a free place), and `queue_progress[tab]` the
## head's progress in hundredths of a tick (`Production.PROGRESS_PER_TICK` a tick). `rally_x` and
## `rally_y` are the tab's rally point in milli-tiles, -1 for none. Copies, one entry per tab.
var queue_slots: int = 0
var queue_count: PackedInt32Array = PackedInt32Array()
var queue_progress: PackedInt32Array = PackedInt32Array()
var queue_type: PackedInt32Array = PackedInt32Array()
var rally_x: PackedInt32Array = PackedInt32Array()
var rally_y: PackedInt32Array = PackedInt32Array()
## The player's last-seen records: how many, and the four columns, one entry per record, in the
## order of the World's block (`LastSeen`). Copies; a column is as long as `ghost_count`.
var ghost_count: int = 0
var ghost_id: PackedInt32Array = PackedInt32Array()
var ghost_type: PackedInt32Array = PackedInt32Array()
var ghost_owner: PackedInt32Array = PackedInt32Array()
var ghost_cell: PackedInt32Array = PackedInt32Array()
## Copies of the World's type tables, one entry per type index (its names and meanings): a cost in
## credits, the tab a type is built on and the type it requires (-1 for none), the tab a building
## produces (-1), the footprint in tiles (0 for a unit), the speed in milli-tiles a tick (0 for a
## building), the weapon index (-1 for none), a harvester's cargo capacity (0), the power a
## building makes (positive) or uses (negative), and the ticks a type takes to build.
var type_cost: PackedInt32Array = PackedInt32Array()
var type_tab: PackedInt32Array = PackedInt32Array()
var type_requires: PackedInt32Array = PackedInt32Array()
var type_produces: PackedInt32Array = PackedInt32Array()
var type_foot_w: PackedInt32Array = PackedInt32Array()
var type_foot_h: PackedInt32Array = PackedInt32Array()
var type_speed: PackedInt32Array = PackedInt32Array()
var type_weapon: PackedInt32Array = PackedInt32Array()
var type_harvest: PackedInt32Array = PackedInt32Array()
var type_power: PackedInt32Array = PackedInt32Array()
var type_build_ticks: PackedInt32Array = PackedInt32Array()

## The row columns, aliases of the World's (see the header): behind the getters, which hide the rows
## the player does not see. `_shown` holds `_OWN`, `_SEEN` or `_HIDDEN` for each row.
var _ids: PackedInt32Array = PackedInt32Array()
var _owner: PackedInt32Array = PackedInt32Array()
var _type: PackedInt32Array = PackedInt32Array()
var _pos_x: PackedInt32Array = PackedInt32Array()
var _pos_y: PackedInt32Array = PackedInt32Array()
var _hp: PackedInt32Array = PackedInt32Array()
var _order: PackedInt32Array = PackedInt32Array()
var _harvest_mode: PackedInt32Array = PackedInt32Array()
var _home: PackedInt32Array = PackedInt32Array()
var _shown: PackedByteArray = PackedByteArray()
## The type ids (a copy: the World's own typed array is shared by reference), and the dock offsets
## that make a type a refinery.
var _type_ids: Array[StringName] = []
var _dock_x: PackedInt32Array = PackedInt32Array()
var _dock_y: PackedInt32Array = PackedInt32Array()
## What `Placement.reason` and `is_explored` read: its arrays are aliases too; it keeps no World.
var _input: PlacementInput = null


## The view of `player` on `world` as it stands. One pass over the rows (`_take_rows`) and a few
## slices of the player's own state; nothing is written to the World.
static func of(world: World, player: int) -> PlayerView:
	var view: PlayerView = PlayerView.new()
	view.player = player
	view.tick = world.tick
	view.map_cols = world.map_cols
	view.map_rows = world.map_rows
	view._input = PlacementInput.of_world(world)
	view._take_tables(world)
	view._take_player(world)
	view._take_ghosts(world)
	view._take_rows(world)
	return view


## The row of unit `id`, or MISSING when no row of the player's view has that id.
func row_of(id: int) -> int:
	var at: int = _ids.bsearch(id)
	if at < _ids.size() and _ids[at] == id and _level(at) != _HIDDEN:
		return at
	return MISSING


## The public columns of an own or a seen row: its id, owner (0 is neutral), type index, position
## in milli-tiles and hit points.
func row_id(row: int) -> int:
	return _ids[row] if _level(row) != _HIDDEN else MISSING


func row_owner(row: int) -> int:
	return _owner[row] if _level(row) != _HIDDEN else MISSING


func row_type(row: int) -> int:
	return _type[row] if _level(row) != _HIDDEN else MISSING


func row_pos(row: int) -> Vector2i:
	if _level(row) == _HIDDEN:
		return Vector2i(MISSING, MISSING)
	return Vector2i(_pos_x[row], _pos_y[row])


func row_hp(row: int) -> int:
	return _hp[row] if _level(row) != _HIDDEN else MISSING


## The own columns of an own row, MISSING for any other: its order (`Order`), its harvest mode
## (`HarvestMode`) and its home, the id of the refinery a harvester unloads at (0 for none).
func row_order(row: int) -> int:
	return _order[row] if _level(row) == _OWN else MISSING


func row_harvest_mode(row: int) -> int:
	return _harvest_mode[row] if _level(row) == _OWN else MISSING


func row_home(row: int) -> int:
	return _home[row] if _level(row) == _OWN else MISSING


## Whether the head of the STRUCTURES queue is built and waits for a PLACE: the condition
## `Production.apply_place` tests first (the placement's own answer is `placement`).
func structure_ready() -> bool:
	var tab: int = Tab.STRUCTURES
	if tab >= queue_count.size() or queue_count[tab] == 0:
		return false
	var head: int = queue_type[tab * queue_slots]
	if head < 0 or head >= type_build_ticks.size():
		return false
	return queue_progress[tab] >= type_build_ticks[head] * Production.PROGRESS_PER_TICK


## Whether the cell (`tile_row * map_cols + tile_col`) has been explored by the player: false
## outside the map. A player the fog has no block for (the neutral 0, or past the fog's players),
## and a fog whose block is not the map's, have hidden nothing (`Placement` reads it alike).
func is_explored(cell: int) -> bool:
	var cells: int = map_cols * map_rows
	if cell < 0 or cell >= cells:
		return false
	if player < 1 or player > _input.fog_player_count or _input.fog_cells != cells:
		return true
	var at: int = (player - 1) * cells + cell
	return at < _input.explored.size() and _input.explored[at] != 0


## `Placement.reason` for this player: the `Placement.Reason` that a building of `type_index` with
## its top-left tile at (`col`, `row`) gets now, 0 (OK) when a PLACE there would be applied.
func placement(type_index: int, col: int, row: int) -> int:
	return Placement.reason(_input, player, type_index, col, row)


## The type index of the type id `id` (`&"refinery"`), MISSING when the roster has none.
func type_index_of(id: StringName) -> int:
	return _type_ids.find(id)


## Whether `type` is a refinery: a building type whose dock is not (0, 0), the tile that harvesters
## unload at (`Harvest` asks the same). False for a type outside the table.
func is_refinery(type: int) -> bool:
	return _entry(_dock_x, type) != 0 or _entry(_dock_y, type) != 0


## The record of the building `id` in the player's memory, MISSING when it has none (an id is a
## positive 32-bit int; a wider one would be compared by its low 32 bits, so it has no record).
func ghost_of(id: int) -> int:
	if id < 1 or id > _MAX_ID:
		return MISSING
	return ghost_id.find(id)


## The position, in milli-tiles, of the building that record `record` remembers: the centre of its
## footprint, which is where `Buildings.add` puts a building whose tile `ghost_cell` is (a footprint
## of odd width has its centre in the middle of the tile, one of even width on the tile's west
## edge, and the same for the height). (MISSING, MISSING) for a record outside the list and for a
## type without a footprint.
@warning_ignore("integer_division")
func ghost_pos(record: int) -> Vector2i:
	if record < 0 or record >= ghost_cell.size() or map_cols < 1:
		return Vector2i(MISSING, MISSING)
	var type: int = ghost_type[record]
	var width: int = _entry(type_foot_w, type)
	var height: int = _entry(type_foot_h, type)
	if width < 1 or height < 1:
		return Vector2i(MISSING, MISSING)
	var cell: int = ghost_cell[record]
	return Vector2i(
		cell % map_cols * MILLI_PER_TILE + width % 2 * TILE_CENTRE,
		cell / map_cols * MILLI_PER_TILE + height % 2 * TILE_CENTRE
	)


## Copies of the World's type tables and type ids: a dozen entries each, so a caller that writes
## one writes its own.
func _take_tables(world: World) -> void:
	type_cost = world.type_cost.duplicate()
	type_tab = world.type_tab.duplicate()
	type_requires = world.type_requires.duplicate()
	type_produces = world.type_produces.duplicate()
	type_foot_w = world.type_foot_w.duplicate()
	type_foot_h = world.type_foot_h.duplicate()
	type_speed = world.type_speed.duplicate()
	type_weapon = world.type_weapon.duplicate()
	type_harvest = world.type_harvest.duplicate()
	type_power = world.type_power.duplicate()
	type_build_ticks = world.type_build_ticks.duplicate()
	_dock_x = world.type_dock_x.duplicate()
	_dock_y = world.type_dock_y.duplicate()
	_type_ids = world.type_ids.duplicate()


## The player's credits, power and queues. A player past the World's per-player arrays (a hand-built
## World, or the neutral 0 whose entries nothing writes) keeps the empty queues and the zeros.
func _take_player(world: World) -> void:
	queue_slots = world.queue_slots
	if player < 1 or player >= world.credits.size():
		return
	credits = world.credits[player]
	power_made = _entry(world.power_made, player)
	power_used = _entry(world.power_used, player)
	low_power = Power.is_low(world, player)
	var first: int = player * TABS
	queue_count = world.queue_count.slice(first, first + TABS)
	queue_progress = world.queue_progress.slice(first, first + TABS)
	queue_type = world.queue_type.slice(first * queue_slots, (first + TABS) * queue_slots)
	rally_x = world.rally_x.slice(first, first + TABS)
	rally_y = world.rally_y.slice(first, first + TABS)


## The player's block of the last-seen records, as `ghost_*` copies. A player past the World's
## arrays (the neutral 0, a hand-built World) and a count that the arrays cannot hold keep none.
func _take_ghosts(world: World) -> void:
	var cap: int = world.ghost_cap
	if player < 1 or player >= world.ghost_count.size() or cap < 1:
		return
	var first: int = player * cap
	var count: int = clampi(world.ghost_count[player], 0, cap)
	if first + count > world.ghost_id.size():
		return
	ghost_count = count
	ghost_id = world.ghost_id.slice(first, first + count)
	ghost_type = world.ghost_type.slice(first, first + count)
	ghost_owner = world.ghost_owner.slice(first, first + count)
	ghost_cell = world.ghost_cell.slice(first, first + count)


## The one pass over the rows: aliases the columns, then sorts each row into `own_rows`,
## `seen_rows` or neither, in ascending order, and records which in `_shown`. A row of another owner
## is seen when the visible count of its cell is above 0 in the player's block, as
## `Targeting.sees` says (the rule, inlined over aliased arrays); a player the fog has no block for
## sees every row, as there. The lists are built in locals, so that the loop reads no member, and
## stored last.
@warning_ignore("integer_division")
func _take_rows(world: World) -> void:
	_ids = world.unit_id
	_owner = world.owner
	_type = world.type_index
	_pos_x = world.pos_x
	_pos_y = world.pos_y
	_hp = world.hp
	_order = world.order
	_harvest_mode = world.harvest_mode
	_home = world.home
	var fog: FogGrid = world.fog
	var cols: int = fog.cols
	var lines: int = fog.rows
	var cells: int = fog.cells
	var visible: PackedInt32Array = fog.visible
	var sees_all: bool = (
		player < 1
		or player > fog.player_count
		or cols < 1
		or lines < 1
		or cells % cols != 0
		or cells / cols != lines
	)
	var block: int = (player - 1) * cells
	var owners: PackedInt32Array = _owner
	var xs: PackedInt32Array = _pos_x
	var ys: PackedInt32Array = _pos_y
	var count: int = _ids.size()
	var shown: PackedByteArray = PackedByteArray()
	shown.resize(count)
	var own: PackedInt32Array = PackedInt32Array()
	var seen: PackedInt32Array = PackedInt32Array()
	for row: int in count:
		if owners[row] == player:
			own.append(row)
			shown[row] = _OWN
			continue
		var is_seen: bool = sees_all
		if not is_seen:
			var cell: int = (
				clampi(ys[row] / MILLI_PER_TILE, 0, lines - 1) * cols
				+ clampi(xs[row] / MILLI_PER_TILE, 0, cols - 1)
			)
			is_seen = visible[block + cell] > 0
		if is_seen:
			seen.append(row)
			shown[row] = _SEEN
	_shown = shown
	own_rows = own
	seen_rows = seen


## What the player may read of `row`: `_OWN`, `_SEEN`, or `_HIDDEN` for a row outside the table.
func _level(row: int) -> int:
	return _shown[row] if row >= 0 and row < _shown.size() else _HIDDEN


## `table[index]`, or 0 past the table.
static func _entry(table: PackedInt32Array, index: int) -> int:
	return table[index] if index >= 0 and index < table.size() else 0
