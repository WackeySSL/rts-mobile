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


## A MOVE, ATTACK_MOVE or STOP on `rows` takes the "board on arrival" mark off the ones that
## carry it (an `order_target` that names an own row; an ATTACK's names an enemy). Sim calls it with
## the rows it accepted, as `Harvest.release`.
static func release(world: World, rows: PackedInt32Array) -> void:
	var targets: PackedInt32Array = world.order_target
	for row: int in rows:
		if targets[row] != 0:
			var other: int = world.index_of(targets[row])
			if other >= 0 and world.owner[other] == world.owner[row]:
				targets[row] = 0
	# A carrier that gets a new order lets go of the squads that wait for it.
	var slots: PackedInt32Array = world.type_carry_slots
	for row: int in rows:
		if slots[world.type_index[row]] > 0:
			for other: int in targets.size():
				if targets[other] == world.unit_id[row]:
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
