class_name Removal
extends RefCounted
## REMOVE (ADR 0007 section 3), moved out of World.gd in P271 so that file keeps room under gdlint's
## 1,000 lines (`World.remove_dead` wraps `run`). Integers only, no allocation but the one resize of
## the event list.

## Where in a DIED record the flag is (the seventh int); `died_flag` says what it holds.
const DIED_FLAG_AT: int = Production.DIED_CANCEL_FLAG_AT
## The flags `died_flag` gives (the seventh int of a DIED record); view readers compare with these.
const FLAG_CANCELLED: int = 1
const FLAG_BOARDED: int = 2
const FLAG_SOLD: int = 3


## The DIED flag of a row whose `build_left` is `pending` (ADR 0037 section 2):
## `Production.CANCELLED` (-1) gives 1, `Carry.BOARDED` (-2) gives 2, `Production.SOLD` (-3) gives
## 3 and anything else 0. A reader compares the flag with the value it means, never with `!= 0`.
static func died_flag(pending: int) -> int:
	match pending:
		Production.CANCELLED:
			return FLAG_CANCELLED
		Carry.BOARDED:
			return FLAG_BOARDED
		Production.SOLD:
			return FLAG_SOLD
	return 0


## Removes every row with hp of 0 or less: a DIED record per dead row, in row order, and its fog
## unstamped, then a stable compaction of every ROW_ARRAYS column, so the rows stay ascending by id.
## It bumps rows_version once and adds the rows that changed place to stats[ROWS_COMPACTED]. The
## records of a building that dies in sight go before the rows do (`LastSeen.forget_dead`, P77b).
## The seventh int of a record is `died_flag` of the row's `build_left`. A tick without a death
## costs one scan. It prepares the world first (O(1) once prepared), so a hand-built world works:
## stats is sized by prepare().
static func run(world: World) -> void:
	world.prepare()
	var count: int = world.unit_id.size()
	var alive: PackedInt32Array = world.hp
	var first: int = 0
	while first < count and alive[first] > 0:
		first += 1
	if first == count:
		return
	Buildings.unblock_dead(world)  # Before the compaction: the origin comes from the position.
	Outcome.count_losses(world)  # Likewise: the owner and the type of a dying row (ADR 0018 s. 7).
	LastSeen.forget_dead(world, first)  # Likewise: the fog is still the sight the building fell in.
	var dead: int = 0
	for row: int in range(first, count):
		if alive[row] <= 0:
			dead += 1
	# One resize for all the records, then the writes: the loops allocate nothing. A stamped row's
	# vision ends here (ADR 0010 section 1); `explored` stays.
	var events: PackedInt32Array = world.events
	var at: int = events.size()
	events.resize(at + dead * World.EVENT_STRIDE)  # The eighth int stays 0, the seventh is the flag.
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var stamped: PackedInt32Array = world.fog_cell
	var pending: PackedInt32Array = world.build_left
	var pad: int = world.type_sight.size()
	var fog: FogGrid = world.fog
	var has_fog: bool = fog.cells > 0
	for row: int in range(first, count):
		if alive[row] <= 0:
			world.write_unit_event(at, World.Event.DIED, row)
			events[at + DIED_FLAG_AT] = died_flag(pending[row])
			at += World.EVENT_STRIDE
			if has_fog and stamped[row] >= 0:
				fog.stamp(owners[row], stamped[row], mini(types[row], pad), -1)
	# hp is the test for every column, so it goes last.
	for column_name: StringName in World.ROW_ARRAYS:
		if column_name != &"hp":
			var column: PackedInt32Array = world.get(column_name)
			_compact(column, alive, first, count)
	_compact(alive, alive, first, count)
	world.stats[World.Stat.ROWS_COMPACTED] += count - first - dead
	world.rows_version += 1


## Moves the entries of `col` whose `alive` is above 0 down over the dead ones, in order, and cuts
## it to the survivors. Rows before `first`, the first dead row, stay. `alive` may be `col` itself:
## a write never reaches a row still to be read.
static func _compact(col: PackedInt32Array, alive: PackedInt32Array, first: int, end: int) -> void:
	var to: int = first
	for row: int in range(first + 1, end):
		if alive[row] > 0:
			col[to] = col[row]
			to += 1
	col.resize(to)
