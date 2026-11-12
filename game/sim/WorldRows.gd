class_name WorldRows
extends RefCounted
## The row writers of a World, split out of World.gd (P232c) so that file keeps room under gdlint's
## 1,000 lines. Pure static helpers: they write the World passed in and keep nothing.
## `World.add_unit`, `World._push_unit_event` and `World.write_unit_event` are one-line delegates
## to the functions of the same names here, so no caller names this class. The code is World.gd's
## own, moved with no change. This is the home of every other function that appends or inserts a
## row (P262's `World.insert_row` is one more delegate to here); ADR 0007 section 2 keeps every
## column, list and rule int in World itself.


## Appends an idle unit at (x, y) at its type's max hp (at least 1; 1 for a type with no entry)
## and returns its new id. `type_index` must be an index into type_ids. It writes one SPAWNED
## event and raises player_count to the owner. After prepare() an owner above player_count or a
## row beyond max_rows is refused instead: 0, and spawn_refused counts it.
static func add_unit(world: World, owner: int, type_index: int, x: int, y: int) -> int:
	if world.prepared and (owner > world.player_count or world.unit_id.size() >= world.max_rows):
		world.spawn_refused += 1
		return 0
	var id: int = world.next_id
	world.next_id += 1
	var type_hp: int = 1
	if type_index < world.type_max_hp.size():
		type_hp = maxi(world.type_max_hp[type_index], 1)
	_append_columns(world, id, owner, type_index, type_hp, x, y)
	push_unit_event(world, World.Event.SPAWNED, world.unit_id.size() - 1)
	world.rows_version += 1
	world.player_count = maxi(world.player_count, owner)
	return id


## Inserts a squad that left a carrier as an idle row with its old `id` at `hp`, so that the rows
## stay ascending by id, and returns its row (ADR 0036 section 8; Carry.run calls it in ECONOMY,
## at event cadence: O(rows x columns)). It returns -1 and changes nothing when the table already
## holds `max_rows` rows (the squad then stays aboard), when `hp` is below 1 (REMOVE would take the
## row at once), when `owner` is not a player 1..player_count, when `type_index` is not a type or
## when a row already has `id`. It bumps `rows_version`, writes no event and does not touch
## `next_id`, `spawn_refused` or `player_count`: the id is the one the squad always had.
static func insert_row(
	world: World, id: int, owner: int, type_index: int, hp: int, x: int, y: int
) -> int:
	if (
		world.unit_id.size() >= world.max_rows
		or hp < 1
		or owner < 1
		or owner > world.player_count
		or type_index < 0
		or type_index >= world.type_ids.size()
	):
		return -1
	var row: int = world.unit_id.bsearch(id)
	if row < world.unit_id.size() and world.unit_id[row] == id:
		return -1
	var last: int = world.unit_id.size()
	_append_columns(world, id, owner, type_index, hp, x, y)
	if row < last:  # Rotate the appended record down to its place, column by column.
		for column_name: StringName in World.ROW_ARRAYS:
			var column: PackedInt32Array = world.get(column_name)
			column.insert(row, column[last])
			column.resize(last + 1)
	world.rows_version += 1
	return row


## Appends one idle row at (x, y) to every ROW_ARRAYS column, the start values of a new unit
## (add_unit and insert_row share it). `type_index` may lie beyond the type tables (hand-built).
static func _append_columns(
	world: World, id: int, owner: int, type_index: int, hp: int, x: int, y: int
) -> void:
	world.unit_id.append(id)
	world.owner.append(owner)
	world.type_index.append(type_index)
	world.pos_x.append(x)
	world.pos_y.append(y)
	world.goal_x.append(x)
	world.goal_y.append(y)
	world.group_cell.append(-1)
	world.order.append(World.Order.IDLE)
	world.hp.append(hp)
	world.order_target.append(0)
	world.target.append(0)
	world.cooldown.append(0)
	world.nav_mode.append(World.NavMode.NONE)
	world.field.append(-1)
	world.nav_cell.append(-1)
	world.nav_next.append(-1)
	world.best_dist.append(0x3FFFFFFF)  # No distance yet; equals FlowField.UNREACHED.
	world.stall.append(0)
	world.fog_cell.append(-1)
	world.harvest_mode.append(World.HarvestMode.IDLE)
	world.cargo.append(0)
	world.harvest_slot.append(-1)
	world.home.append(0)
	world.ready_tick.append(0)
	world.offline_until.append(0)
	world.build_left.append(0)
	world.ammo.append(world.type_ammo[type_index] if type_index < world.type_ammo.size() else 0)
	world.carry_mode.append(0)


## Appends the `kind` record (SPAWNED) of row `row` to `events` (ADR 0007 section 10), in place.
static func push_unit_event(world: World, kind: int, row: int) -> void:
	var at: int = world.events.size()
	world.events.resize(at + World.EVENT_STRIDE)  # The last two ints of the record stay 0.
	write_unit_event(world, at, kind, row)


## Writes the SPAWNED or DIED record of row `row` at `events[at]`, which is already sized.
static func write_unit_event(world: World, at: int, kind: int, row: int) -> void:
	world.events[at] = kind
	world.events[at + 1] = world.unit_id[row]
	world.events[at + 2] = world.pos_x[row]
	world.events[at + 3] = world.pos_y[row]
	world.events[at + 4] = world.type_index[row]
	world.events[at + 5] = world.owner[row]
