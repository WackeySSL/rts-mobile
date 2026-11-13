class_name Carry
extends RefCounted
## Carriers (ADR 0036 section 8; P263 is the loading half, P263b adds UNLOAD and the unloading).
## A boarded squad is not a row: its id, type, hp and owner are a record of the passenger table
## (`pass_*`, `pass_count` live records, in boarding order), so every kernel, the grids, the fog and
## targeting ignore it. Integers only, no allocation but the command's own row lists.
##
## LOAD: the carrier and the squads all get MOVE to the lowest-id squad's point, and each squad's
## `order_target` is the carrier's id: "board on arrival" (`board`). A plain MOVE or ATTACK_MOVE
## takes that mark off again (`release`), as does a new order to the carrier; STOP clears it with
## the rest, ATTACK overwrites it.
##
## UNLOAD: the carriers get MOVE to the point with `carry_mode` 1 (`apply_unload`). `run`, in
## ECONOMY after `Air.run`, unloads each carrier of mode 1 that has stopped (order IDLE): its
## squads, in table order, are inserted on the free FOOT cells of a ring walk round it, up to
## `unload_reach_tiles` away, each at the cell centre with order IDLE and an `UNLOADED` event
## (kind 6: id, x, y, type, owner, carrier id at index 6). A squad with no cell, or refused by
## `World.insert_row`, stays aboard with its record. `perish`, in the REMOVE mark after `board`,
## kills the squads of a carrier that dies with it (ADR 0036 section 8).

## The `build_left` of a row that boarded a carrier: `hp` 0 as well, so REMOVE takes the row out in
## the same tick with DIED flag 2 (`Removal.died_flag`) and counts no loss (`Outcome.count_losses`).
## A mobile row's `build_left` is 0 otherwise.
const BOARDED: int = -2


## LOAD: `unit_ids` are the squads, `target_id` is an own carrier (a mobile row of a type with
## `type_carry_slots` above 0, alive, complete). A squad is valid when it is an own, complete,
## living mobile row other than the carrier whose move class bit is in its `type_carry_classes`;
## the lowest ids fill the slots still free (`type_carry_slots` less the squads aboard). With none
## valid, or no slot free, the command is dropped and counted. The carrier cancels a pending unload
## (`carry_mode` 0).
static func apply_load(world: World, command: Command) -> bool:
	if command.unit_ids.size() > Command.MAX_UNITS:
		return false
	var carrier: int = world.index_of(command.target_id)
	if carrier < 0 or not _usable(world, carrier, command.player_id):
		return false
	var type: int = world.type_index[carrier]
	if type >= world.type_carry_slots.size() or world.type_speed[type] <= 0:
		return false
	var free: int = world.type_carry_slots[type] - aboard(world, command.target_id)
	if free <= 0:
		return false
	var classes: int = world.type_carry_classes[type]
	var ids: PackedInt32Array = command.unit_ids.duplicate()
	ids.sort()
	var squads: PackedInt32Array = PackedInt32Array()
	var previous: int = 0
	for id: int in ids:
		if id == previous or squads.size() >= free:
			continue
		previous = id
		var row: int = world.index_of(id)
		if row < 0 or row == carrier or not _usable(world, row, command.player_id):
			continue
		var squad_type: int = world.type_index[row]
		if _boards(world, squad_type, classes):
			squads.append(row)
	if squads.is_empty():
		return false
	var at: int = squads[0]  # G: the lowest-id squad's point.
	var gx: int = world.pos_x[at]
	var gy: int = world.pos_y[at]
	_go(world, PackedInt32Array([carrier]), gx, gy, 0)
	world.carry_mode[carrier] = 0
	_go(world, squads, gx, gy, command.target_id)
	Harvest.release(world, squads)
	return true


## UNLOAD: `unit_ids` are the carriers and the target is a point in milli-tiles. A carrier is valid
## when it is an own, complete, living mobile row of a type with `type_carry_slots` above 0 and has
## a squad aboard; the valid ones get MOVE to the point in formation with `carry_mode` 1, which ends
## the marks of squads waiting for them. With none valid the command is dropped and counted.
static func apply_unload(world: World, command: Command) -> bool:
	if command.unit_ids.size() > Command.MAX_UNITS:
		return false
	var ids: PackedInt32Array = command.unit_ids.duplicate()
	ids.sort()
	var carriers: PackedInt32Array = PackedInt32Array()
	var previous: int = 0
	for id: int in ids:
		if id == previous:
			continue
		previous = id
		var row: int = world.index_of(id)
		if row < 0 or not _usable(world, row, command.player_id):
			continue
		var type: int = world.type_index[row]
		if (
			type < world.type_carry_slots.size()
			and world.type_carry_slots[type] > 0
			and world.type_speed[type] > 0
			and aboard(world, id) > 0
		):
			carriers.append(row)
	if carriers.is_empty():
		return false
	release(world, carriers)
	_go(world, carriers, command.target_x, command.target_y, 0)
	for row: int in carriers:
		world.carry_mode[row] = 1
	return true


## A MOVE, ATTACK_MOVE or STOP on `rows` takes the "board on arrival" mark off the ones that
## carry it (an `order_target` that names an own row; an ATTACK's names an enemy). Sim calls it with
## the rows it accepted, as `Harvest.release`.
static func release(world: World, rows: PackedInt32Array) -> void:
	var targets: PackedInt32Array = world.order_target
	for row: int in rows:
		world.carry_mode[row] = 0  # A new order cancels a pending unload.
		if targets[row] != 0:
			var other: int = world.index_of(targets[row])
			if other >= 0 and world.owner[other] == world.owner[row]:
				targets[row] = 0
	# A carrier that gets a new order lets go of the squads that wait for it.
	var slots: PackedInt32Array = world.type_carry_slots
	for row: int in rows:
		if slots[world.type_index[row]] > 0:
			for other: int in targets.size():
				if targets[other] == world.unit_id[row] and world.owner[other] == world.owner[row]:
					targets[other] = 0


## Boarding, in the REMOVE mark after `FogUpdate.begin` and before `World.remove_dead`. A row with
## an order MOVE or IDLE and an `order_target` that names an own living carrier boards when it is
## alive, complete, of a class the carrier takes, within `load_reach_milli` of it and a slot is
## free (the table has room too). The checks run in ascending row order. Its record joins the table
## and the row is marked for this tick's REMOVE (`hp` 0, `build_left` `BOARDED`). A carrier with no
## slot free ends the mark. Inert at `load_reach_milli` or `passenger_cap` 0.
static func board(world: World) -> void:
	var reach: int = world.load_reach_milli
	var room: int = mini(world.passenger_cap, world.pass_id.size())
	if reach <= 0 or room <= 0:
		return
	var targets: PackedInt32Array = world.order_target
	var orders: PackedInt32Array = world.order
	var life: PackedInt32Array = world.hp
	var pending: PackedInt32Array = world.build_left
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	for row: int in ids.size():
		if targets[row] == 0 or orders[row] == World.Order.ATTACK or life[row] <= 0:
			continue
		if pending[row] != 0 or orders[row] == World.Order.ATTACK_MOVE:
			continue
		var carrier: int = world.index_of(targets[row])
		if (
			carrier < 0
			or owners[carrier] != owners[row]
			or not _usable(world, carrier, owners[row])
		):
			continue
		var carrier_type: int = types[carrier]
		var slots: int = world.type_carry_slots[carrier_type]
		if slots <= 0 or aboard(world, ids[carrier]) >= slots:
			targets[row] = 0  # Nothing to board: a plain MOVE from here.
			continue
		var type: int = types[row]
		var dx: int = pos_x[row] - pos_x[carrier]
		var dy: int = pos_y[row] - pos_y[carrier]
		if (
			dx * dx + dy * dy > reach * reach
			or world.pass_count >= room
			or not _boards(world, type, world.type_carry_classes[carrier_type])
		):
			continue
		var at: int = world.pass_count
		world.pass_carrier[at] = ids[carrier]
		world.pass_id[at] = ids[row]
		world.pass_type[at] = type
		world.pass_hp[at] = life[row]
		world.pass_owner[at] = owners[row]
		world.pass_count += 1
		life[row] = 0
		pending[row] = BOARDED


## ECONOMY, after `Air.run`: every carrier of `carry_mode` 1 whose order is IDLE unloads (`_unload`)
## and goes back to mode 0. Inserting rows moves the ones above, so the walk finds the carrier again
## by id. The derived building lists are rebuilt after the inserts (a no-op when nothing was
## inserted), before `Repair.run` and `Mend.run` read `building_rows`.
static func run(world: World) -> void:
	if world.pass_count <= 0:
		return
	var row: int = 0
	while row < world.unit_id.size():
		if (
			world.carry_mode[row] == 1
			and world.order[row] == World.Order.IDLE
			and world.hp[row] > 0
		):
			var id: int = world.unit_id[row]
			_unload(world, id)
			world.carry_mode[world.index_of(id)] = 0
			row = world.index_of(id)
		row += 1
	Buildings.rebuild_lists(world)


## The REMOVE mark, after `board` and before `World.remove_dead`: the squads aboard a carrier whose
## `hp` is 0 or less die with it (ADR 0036 section 8). Each gets a DIED record (flag 0) at the
## carrier's point and counts as a lost unit as `Outcome.count_losses` counts one; its record leaves
## the table, the others keep their order. One resize of the event list, no other allocation.
static func perish(world: World) -> void:
	var count: int = mini(world.pass_count, world.pass_id.size())
	var dying: int = 0
	for at: int in count:
		var carrier: int = world.index_of(world.pass_carrier[at])
		if carrier >= 0 and world.hp[carrier] <= 0:
			dying += 1
	if dying == 0:
		return
	var events: PackedInt32Array = world.events
	var write: int = events.size()
	events.resize(write + dying * World.EVENT_STRIDE)  # The eighth int and the flag stay 0.
	var kept: int = 0
	var players: int = mini(
		world.had_producer.size(),
		mini(world.stat_lost_units.size(), world.stat_lost_buildings.size())
	)
	for at: int in count:
		var carrier: int = world.index_of(world.pass_carrier[at])
		if carrier < 0 or world.hp[carrier] > 0:
			for name: StringName in World.PASSENGER_ARRAYS:
				var column: PackedInt32Array = world.get(name)
				column[kept] = column[at]
			kept += 1
			continue
		var owner: int = world.pass_owner[at]
		events[write] = World.Event.DIED
		events[write + 1] = world.pass_id[at]
		events[write + 2] = world.pos_x[carrier]
		events[write + 3] = world.pos_y[carrier]
		events[write + 4] = world.pass_type[at]
		events[write + 5] = owner
		write += World.EVENT_STRIDE
		if owner >= 1 and owner < players and world.had_producer[owner] == 1:
			world.stat_lost_units[owner] += 1
	for at: int in range(kept, count):
		for name: StringName in World.PASSENGER_ARRAYS:
			var column: PackedInt32Array = world.get(name)
			column[at] = 0
	world.pass_count = kept


## How many squads are aboard the carrier `carrier_id` (a pass over the live records).
static func aboard(world: World, carrier_id: int) -> int:
	var count: int = 0
	for at: int in mini(world.pass_count, world.pass_carrier.size()):
		if world.pass_carrier[at] == carrier_id:
			count += 1
	return count


## How many squads of `player` are aboard any carrier: they count toward `unit_cap` (ADR 0036
## section 8; `ProductionSpawn.mobile_rows`).
static func passengers_of(world: World, player: int) -> int:
	var count: int = 0
	for at: int in mini(world.pass_count, world.pass_owner.size()):
		if world.pass_owner[at] == player:
			count += 1
	return count


## Unloads the squads aboard carrier `carrier_id` (mode 1, stopped), in table order. A ring walk
## round the carrier's tile, ring 1 up to `unload_reach_tiles`, each ring clockwise from its
## top-left corner, gives each squad the next FOOT-passable cell (every on-map tile looked at counts
## one `Stat.EXIT_SCANNED`), so the squads never share a cell. The squad's row is inserted at the
## cell's centre with its old id and hp (`World.insert_row`), and its record leaves the table. The
## squads that find no cell, or that `insert_row` refuses, stay aboard with their records.
static func _unload(world: World, carrier_id: int) -> void:
	var carrier: int = world.index_of(carrier_id)
	var tile_x: int = world.pos_x[carrier] / 1000
	var tile_y: int = world.pos_y[carrier] / 1000
	var cols: int = world.map_cols
	var lines: int = world.map_rows
	var reach: int = world.unload_reach_tiles
	var ring: int = 1
	var step: int = 0
	var at: int = 0
	while at < world.pass_count:
		if world.pass_carrier[at] != carrier_id:
			at += 1
			continue
		var found: Vector2i = Vector2i(-1, -1)
		while ring <= reach and found.x < 0:
			var tile: Vector2i = _ring_tile(tile_x, tile_y, ring, step)
			step += 1
			if step >= 8 * ring:
				step = 0
				ring += 1
			if tile.x < 0 or tile.y < 0 or tile.x >= cols or tile.y >= lines:
				continue
			world.stats[World.Stat.EXIT_SCANNED] += 1
			if world.is_passable(tile.y * cols + tile.x, World.MoveClass.FOOT):
				found = tile
		if found.x < 0:
			return
		var made: int = world.insert_row(
			world.pass_id[at],
			world.pass_owner[at],
			world.pass_type[at],
			world.pass_hp[at],
			found.x * 1000 + 500,
			found.y * 1000 + 500
		)
		if made < 0:
			return
		var events: PackedInt32Array = world.events
		WorldRows.push_unit_event(world, World.Event.UNLOADED, made)
		events[events.size() - World.EVENT_STRIDE + Production.DIED_CANCEL_FLAG_AT] = carrier_id
		_drop(world, at)


## Takes record `at` out of the passenger table; the later records move down one, in order.
static func _drop(world: World, at: int) -> void:
	var last: int = world.pass_count - 1
	for name: StringName in World.PASSENGER_ARRAYS:
		var column: PackedInt32Array = world.get(name)
		for index: int in range(at, last):
			column[index] = column[index + 1]
		column[last] = 0
	world.pass_count = last


## Tile `step` (0 up to 8 * ring - 1) of the square ring `ring` tiles round (x, y), clockwise on
## the screen from the top-left corner; each side holds its starting corner and not the next.
static func _ring_tile(x: int, y: int, ring: int, step: int) -> Vector2i:
	var side: int = 2 * ring
	if step < side:
		return Vector2i(x - ring + step, y - ring)
	step -= side
	if step < side:
		return Vector2i(x + ring, y - ring + step)
	step -= side
	if step < side:
		return Vector2i(x + ring - step, y + ring)
	step -= side
	return Vector2i(x - ring, y + ring - step)


## Whether a squad of `type` may board a carrier whose class mask is `classes`: a mobile FOOT type
## whose bit is in the mask (ADR 0036 section 8). So a carrier never boards a carrier and a
## harvester never boards, whatever the mask.
static func _boards(world: World, type: int, classes: int) -> bool:
	return (
		world.type_speed[type] > 0
		and world.type_move_class[type] == World.MoveClass.FOOT
		and ((classes >> World.MoveClass.FOOT) & 1) == 1
	)


## Whether `row` is the player's, alive and complete (a mobile row's `build_left` is 0).
static func _usable(world: World, row: int, player: int) -> bool:
	return world.owner[row] == player and world.hp[row] > 0 and world.build_left[row] == 0


## MOVE to the point for `rows`, in formation, with `mark` as their `order_target` (0 for none):
## what `Sim._apply_point` does for a MOVE.
static func _go(world: World, rows: PackedInt32Array, x: int, y: int, mark: int) -> void:
	Formation.assign(world, rows, x, y)
	for row: int in rows:
		world.order[row] = World.Order.MOVE
		world.order_target[row] = mark
	Movement.reset_nav(world, rows, World.NavMode.DIRECT)
