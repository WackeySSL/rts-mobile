class_name Sim
extends RefCounted
## One simulation tick (ADR 0003 sections 3 to 5, ADR 0007 sections 4 and 5). Integers only. An
## invalid command is dropped and counted in `world.dropped_commands`; nothing here calls
## push_error.

const TICK_RATE: int = 15
## Same value as World.MILLI_PER_TILE (a test pins the pair).
const MILLI_PER_TILE: int = 1000


## Prepares the world, clears the last tick's events and stats, sorts `commands` in place with
## Command.compare and applies those whose tick is `world.tick`. A null or any other command is
## dropped and counted. Then the flow cache advances (FLOW), ordered units move (intents, then
## integrate), dead rows leave, and the tick counts. A probe gets `begin()` first and a `mark` after
## each phase that exists (ADR 0007 section 4); it never sees the World.
## `_follow_targets` stands in for TARGETING until P41, so its time falls inside INTENTS.
static func step(world: World, commands: Array[Command], probe: SimProbe = null) -> void:
	if probe != null:
		probe.begin()
	world.prepare()
	world.events.clear()
	world.stats.fill(0)
	while commands.has(null):
		commands.erase(null)
		world.dropped_commands += 1
	commands.sort_custom(Command.compare)
	for command: Command in commands:
		if command.tick == world.tick:
			_apply(world, command)
		else:
			world.dropped_commands += 1
	if probe != null:
		probe.mark(SimProbe.Phase.COMMANDS)
	# MatchLoop hashes after this step, on the tick this one counts last: no flow slice on that step
	# (ADR 0012 section 5).
	var hashing: bool = (world.tick + 1) % Replay.CHECKPOINT_PERIOD == 0
	FlowCache.run(world, 0 if hashing else world.flow_cells_per_tick)
	if probe != null:
		probe.mark(SimProbe.Phase.FLOW)
	_follow_targets(world)
	Movement.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.INTENTS)
	Movement.integrate(world)
	if probe != null:
		probe.mark(SimProbe.Phase.INTEGRATE)
	world.remove_dead()
	if probe != null:
		probe.mark(SimProbe.Phase.REMOVE)
	world.tick += 1


## Applies a command of the right tick by type (ADR 0007 section 5), or drops and counts it. Every
## type needs a player in 1..player_count and at most MAX_PAYLOAD payload ints; a type without a
## branch (NONE, 5-29, anything else) is dropped as unknown before any id rule runs. Each
## `_apply_*` is the ADR's per-type validation: it checks the ids through the shared helpers and
## applies the rows it accepted.
static func _apply(world: World, command: Command) -> void:
	var applied: bool = false
	if (
		command.player_id >= 1
		and command.player_id <= world.player_count
		and command.payload.size() <= Command.MAX_PAYLOAD
	):
		match command.type:
			Command.Type.ATTACK_MOVE:
				applied = _apply_point(world, command, World.Order.ATTACK_MOVE)
			Command.Type.MOVE:
				applied = _apply_point(world, command, World.Order.MOVE)
			Command.Type.ATTACK:
				applied = _apply_attack(world, command)
			Command.Type.STOP:
				applied = _apply_stop(world, command)
	if not applied:
		world.dropped_commands += 1


## ATTACK_MOVE and MOVE: the valid units take `order` and a formation slot around the target.
static func _apply_point(world: World, command: Command, order: int) -> bool:
	var rows: PackedInt32Array = _own_rows(world, command, false)
	if rows.is_empty():
		return false
	# Formation.assign clamps the target, but checks no owner and sets no order.
	Formation.assign(world, rows, command.target_x, command.target_y)
	var orders: PackedInt32Array = world.order
	for row: int in rows:
		orders[row] = order
	Movement.reset_nav(world, rows, World.NavMode.DIRECT)
	return true


## ATTACK: the armed valid units take the order and the target (the goal: _follow_targets).
static func _apply_attack(world: World, command: Command) -> bool:
	if not _enemy_target(world, command):
		return false
	var rows: PackedInt32Array = _own_rows(world, command, true)
	if rows.is_empty():
		return false
	var orders: PackedInt32Array = world.order
	var order_target: PackedInt32Array = world.order_target
	var group_of: PackedInt32Array = world.group_cell
	for row: int in rows:
		orders[row] = World.Order.ATTACK
		order_target[row] = command.target_id
		group_of[row] = -1
	Movement.reset_nav(world, rows, World.NavMode.DIRECT)
	return true


## STOP: the valid units go idle where they stand, with no target and no flow field.
static func _apply_stop(world: World, command: Command) -> bool:
	var rows: PackedInt32Array = _own_rows(world, command, false)
	if rows.is_empty():
		return false
	var orders: PackedInt32Array = world.order
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	var order_target: PackedInt32Array = world.order_target
	var target: PackedInt32Array = world.target
	var group_of: PackedInt32Array = world.group_cell
	for row: int in rows:
		orders[row] = World.Order.IDLE
		goal_x[row] = pos_x[row]
		goal_y[row] = pos_y[row]
		group_of[row] = -1
		order_target[row] = 0
		target[row] = 0
	Movement.reset_nav(world, rows, World.NavMode.NONE)  # Also drops the flow field.
	return true


## Rows of the command's units, ascending and without duplicates; none when it holds more than
## MAX_UNITS ids. An id is valid when the unit exists, is the player's and can move (and, with
## `armed`, has a weapon); other ids are skipped silently.
static func _own_rows(world: World, command: Command, armed: bool) -> PackedInt32Array:
	var rows: PackedInt32Array = PackedInt32Array()
	if command.unit_ids.size() > Command.MAX_UNITS:
		return rows
	var ids: PackedInt32Array = command.unit_ids.duplicate()
	ids.sort()
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var speeds: PackedInt32Array = world.type_speed
	var weapons: PackedInt32Array = world.type_weapon
	var previous: int = 0
	for id: int in ids:
		if id == previous:
			continue
		previous = id
		var row: int = world.index_of(id)
		if row >= 0 and owners[row] == command.player_id:
			var type: int = types[row]
			if speeds[type] > 0 and (not armed or weapons[type] >= 0):
				rows.append(row)
	return rows


## Whether `target_id` is a unit of another, non-neutral player (from P46b on: a visible one).
static func _enemy_target(world: World, command: Command) -> bool:
	var row: int = world.index_of(command.target_id)
	return row >= 0 and world.owner[row] != command.player_id and world.owner[row] != 0


## Before P41 an ATTACK unit's goal is where its target stood at the start of the tick (read before
## anyone moves, so row order cannot matter). A target that is gone makes it attack-move to the
## last goal (ADR 0009 section 2). The lookup is inlined over the aliased ids (P41 replaces this).
static func _follow_targets(world: World) -> void:
	var orders: PackedInt32Array = world.order
	var order_target: PackedInt32Array = world.order_target
	var ids: PackedInt32Array = world.unit_id
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	var count: int = ids.size()
	for row: int in count:
		if orders[row] != World.Order.ATTACK:
			continue
		var at: int = ids.bsearch(order_target[row])
		if at >= count or ids[at] != order_target[row]:
			orders[row] = World.Order.ATTACK_MOVE
		else:
			goal_x[row] = pos_x[at]
			goal_y[row] = pos_y[at]
