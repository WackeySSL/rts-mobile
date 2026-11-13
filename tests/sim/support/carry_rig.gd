extends RefCounted
## Worlds and helpers of the carry suites (P263). Not a test suite.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const RIFLE: int = 0
const TANK: int = 1
const TRUCK: int = 2
const REACH: int = 2500
const DIED_FLAG_AT: int = 6


## Rows, by id: 1, 2 and 3 rifle squads and 4 a tank of player 1 near the left edge, 5 the carrier
## of player 1 at the right, 6 a rifle squad of player 2. A 24 x 6 grass map, two players.
static func world(reach: int = REACH, cap: int = 8) -> World:
	var world: World = GridWorld.from_rows(
		GridWorld.grass(24, 6),
		[World.MoveClass.FOOT, World.MoveClass.TRACKED, World.MoveClass.WHEELED]
	)
	world.player_count = 2
	for type: int in 3:
		world.type_max_hp[type] = 100
	world.type_carry_slots[TRUCK] = 2
	world.type_carry_classes[TRUCK] = 1
	world.passenger_cap = cap
	world.load_reach_milli = reach
	world.unit_cap = 75
	WorldLoad.size_match_state(world)  # The per-player arrays and the passenger table.
	world.add_unit(1, RIFLE, 2500, 2500)
	world.add_unit(1, RIFLE, 3500, 2500)
	world.add_unit(1, RIFLE, 4500, 2500)
	world.add_unit(1, TANK, 2500, 4500)
	world.add_unit(1, TRUCK, 14500, 2500)
	world.add_unit(2, RIFLE, 20500, 4500)
	return world


static func step(world: World, commands: Array = []) -> void:
	var typed: Array[Command] = []
	for command: Command in commands:
		command.tick = world.tick
		typed.append(command)
	Sim.step(world, typed)


static func run(world: World, ticks: int) -> void:
	for _tick: int in ticks:
		step(world)


static func load_command(ids: Array, carrier: int, player: int = 1) -> Array[Command]:
	return [Command.board(player, PackedInt32Array(ids), carrier)]


static func died_flags(world: World) -> Array[int]:
	var flags: Array[int] = []
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == World.Event.DIED:
			flags.append(world.events[at + DIED_FLAG_AT])
		at += World.EVENT_STRIDE
	return flags


## Puts the squad `id` into the table by hand, aboard the carrier `carrier`, and takes its row out.
static func aboard(world: World, id: int, carrier: int) -> void:
	var row: int = world.index_of(id)
	var at: int = world.pass_count
	world.pass_carrier[at] = carrier
	world.pass_id[at] = id
	world.pass_type[at] = world.type_index[row]
	world.pass_hp[at] = world.hp[row]
	world.pass_owner[at] = world.owner[row]
	world.pass_count += 1
	world.hp[row] = 0
	world.remove_dead()


## Puts the carrier (id 5) `dx` east of squad 1 on its row and marks squad `id` for it.
static func near(world: World, id: int, dx: int) -> void:
	var row: int = world.index_of(id)
	var carrier: int = world.index_of(5)
	world.pos_x[carrier] = world.pos_x[row] + dx
	world.pos_y[carrier] = world.pos_y[row]
	world.order_target[row] = 5
