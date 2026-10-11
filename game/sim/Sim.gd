class_name Sim
extends RefCounted
## One simulation tick (ADR 0003 sections 3 to 5). Integers only. An invalid command is
## dropped and counted in `world.dropped_commands`; nothing here calls push_error.

const TICK_RATE: int = 15
## Same value as World.MILLI_PER_TILE (a test pins the pair).
const MILLI_PER_TILE: int = 1000


## Sorts `commands` in place with Command.compare and applies those whose tick is `world.tick`.
## A null or any other command is dropped and counted. Then ordered units move, and the tick counts.
static func step(world: World, commands: Array[Command]) -> void:
	while commands.has(null):
		commands.erase(null)
		world.dropped_commands += 1
	commands.sort_custom(Command.compare)
	for command: Command in commands:
		if command.tick == world.tick:
			_apply(world, command)
		else:
			world.dropped_commands += 1
	_move_units(world)
	world.tick += 1


## Attack-move for the command's valid units. An unknown type, or no valid unit left, drops it.
static func _apply(world: World, command: Command) -> void:
	var rows: PackedInt32Array = PackedInt32Array()
	if command.type == Command.Type.ATTACK_MOVE:
		rows = _valid_rows(world, command)
	if rows.is_empty():
		world.dropped_commands += 1
		return
	# Formation.assign clamps the target, but checks no owner and sets no order.
	Formation.assign(world, rows, command.target_x, command.target_y)
	for row: int in rows:
		world.order[row] = World.Order.ATTACK_MOVE


## Rows of the command's units, ascending and without duplicates. An id is valid when the unit
## exists, belongs to the issuing player and can move. Other ids are skipped silently.
static func _valid_rows(world: World, command: Command) -> PackedInt32Array:
	var ids: PackedInt32Array = command.unit_ids.duplicate()
	ids.sort()
	var rows: PackedInt32Array = PackedInt32Array()
	var previous: int = 0
	for id: int in ids:
		if id == previous:
			continue
		previous = id
		var row: int = world.index_of(id)
		if row >= 0 and world.owner[row] == command.player_id:
			if world.type_speed[world.type_index[row]] > 0:
				rows.append(row)
	return rows


## Each unit with an order steps towards its goal, in ascending id order. Within one step it
## snaps to the goal and goes idle. Division truncates toward zero.
@warning_ignore("integer_division")
static func _move_units(world: World) -> void:
	for row: int in world.unit_count():
		if world.order[row] == World.Order.IDLE:
			continue
		var speed: int = world.type_speed[world.type_index[row]]
		var dx: int = world.goal_x[row] - world.pos_x[row]
		var dy: int = world.goal_y[row] - world.pos_y[row]
		var d2: int = dx * dx + dy * dy
		if d2 <= speed * speed:
			world.pos_x[row] = world.goal_x[row]
			world.pos_y[row] = world.goal_y[row]
			world.order[row] = World.Order.IDLE
		else:
			var distance: int = FixedMath.isqrt(d2)
			world.pos_x[row] += dx * speed / distance
			world.pos_y[row] += dy * speed / distance
