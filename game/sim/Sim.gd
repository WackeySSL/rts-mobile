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
## dropped and counted. Then the flow cache advances (FLOW), the separation and targeting grids are
## rebuilt (GRIDS), units pick their targets and engage them (TARGETING: acquisition, the ATTACK
## lock, holding and chasing), ordered units choose their steps (intents), overlapping units are
## pushed apart (SEPARATION), the steps and pushes are integrated, shells in flight move and those
## that arrive hit (PROJECTILES: `Combat.advance_projectiles`), armed units with a target in range
## fire (FIRE: `Combat.fire`, a hitscan hit or a new shell), dead rows leave and their vision ends
## (REMOVE), the players whose turn it is move their fog (FOG: `FogUpdate.run`, every
## `fog_period_ticks`, after `FogUpdate.begin` emptied their dirty lists), the economy runs
## (ECONOMY: `Power.run`, `Harvest.run`), the queues advance and the match outcome is checked
## (PRODUCTION: `Production.run`, `Outcome.run`), the last-seen records update (MEMORY:
## `LastSeen.run`; ADR 0017 section 5), and the tick counts. Of those five modules only `Power.run`
## (it rebuilds the derived row lists, P71) and `Harvest.run` (the ore and the harvest loop, P75) do
## anything yet; the others are skeletons until plan rows P73 to P77. A probe gets `begin()` first
## and a `mark` after each phase that exists (ADR 0007 section 4); it never sees the World.
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
	world.sep_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	world.target_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	if probe != null:
		probe.mark(SimProbe.Phase.GRIDS)
	Targeting.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.TARGETING)
	Movement.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.INTENTS)
	Separation.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.SEPARATION)
	Movement.integrate(world)
	if probe != null:
		probe.mark(SimProbe.Phase.INTEGRATE)
	Combat.advance_projectiles(world)
	if probe != null:
		probe.mark(SimProbe.Phase.PROJECTILES)
	Combat.fire(world)
	if probe != null:
		probe.mark(SimProbe.Phase.FIRE)
	FogUpdate.begin(world)
	world.remove_dead()
	if probe != null:
		probe.mark(SimProbe.Phase.REMOVE)
	FogUpdate.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.FOG)
	Power.run(world)
	Harvest.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.ECONOMY)
	Production.run(world)
	Outcome.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.PRODUCTION)
	LastSeen.run(world)
	if probe != null:
		probe.mark(SimProbe.Phase.MEMORY)
	world.tick += 1


## Applies a command of the right tick by type (ADR 0007 section 5), or drops and counts it. Every
## type needs a player in 1..player_count and at most MAX_PAYLOAD payload ints; a type without a
## branch (NONE, 5-9, 15-19, 21-29, anything else) is dropped as unknown before any id rule runs.
## The Phase 3 types (ADR 0017 section 4) also need a player who is not defeated. Each `_apply_*`
## and each module's `apply_*` is the ADR's per-type validation: it checks the ids through the
## shared helpers and applies the rows it accepted.
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
			Command.Type.PLACE:
				applied = _playing(world, command) and Production.apply_place(world, command)
			Command.Type.QUEUE:
				applied = _playing(world, command) and Production.apply_queue(world, command)
			Command.Type.CANCEL:
				applied = _playing(world, command) and Production.apply_cancel(world, command)
			Command.Type.RALLY:
				applied = _playing(world, command) and Outcome.apply_rally(world, command)
			Command.Type.HARVEST:
				applied = _playing(world, command) and Harvest.apply_harvest(world, command)
			Command.Type.SURRENDER:
				applied = _playing(world, command) and Outcome.apply_surrender(world, command)
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
	Harvest.release(world, rows)
	return true


## ATTACK: the armed valid units take the order and the target, when the target is an enemy their
## player sees (`_enemy_target`). The goal of a mobile target is `Targeting.run`'s, every tick; a
## target that stands still gets its goal here (`Buildings.aim`: a building's approach point, ADR
## 0017 section 1), and a unit with no passable ring tile around a building is left out.
static func _apply_attack(world: World, command: Command) -> bool:
	if not _enemy_target(world, command):
		return false
	var rows: PackedInt32Array = _own_rows(world, command, true)
	rows = Buildings.aim(world, rows, world.index_of(command.target_id))
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
	Harvest.release(world, rows)
	return true


## Whether the command's player has not been defeated (`defeated_tick` 0). False for a player past
## the arrays, which a hand-built world may have raised `player_count` to after prepare().
static func _playing(world: World, command: Command) -> bool:
	var defeated: PackedInt32Array = world.defeated_tick
	return command.player_id < defeated.size() and defeated[command.player_id] == 0


## Rows of the command's units, ascending and without duplicates; none when it holds more than
## MAX_UNITS ids. An id is valid when the unit exists, is the player's and can move (and, with
## `armed`, names a weapon: an index of 0 or more, though a hand-built World may name one that its
## weapon tables lack, which `Targeting` reads as unarmed); other ids are skipped silently.
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


## Whether `target_id` is a unit of another, non-neutral player that the command's player sees
## (P46b, ADR 0010 section 1 "Users": the cell it stands in is visible to that player, by the fog as
## the previous tick left it; `Targeting.sees`). An ATTACK on an unseen enemy is dropped and counted
## like any invalid command.
static func _enemy_target(world: World, command: Command) -> bool:
	var row: int = world.index_of(command.target_id)
	if row < 0 or world.owner[row] == command.player_id or world.owner[row] == 0:
		return false
	return Targeting.sees(world, command.player_id, world.pos_x[row], world.pos_y[row])
