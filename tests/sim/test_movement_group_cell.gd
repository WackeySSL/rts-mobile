extends GdUnitTestSuite
## The group target of an order (P37b; ADR 0008 section 3, "the goal tile of the group target"): the
## `group_cell` column holds the cell of Formation's centre for every unit of a MOVE or ATTACK_MOVE
## command and is the key of the flow field those units share. Every other order, an idle unit and
## a unit that has just spawned carry -1, which keys the field on the unit's own goal tile. The
## cases follow the column through the commands, the end of an order (arrival and stall) and the
## first line check that reads it. Maps are built in code (GridWorld).
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const FOOT: int = World.MoveClass.FOOT
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD


## MOVE and ATTACK_MOVE write the cell of Formation's centre for every unit of the command, whatever
## the unit's own slot (the slots lie on other tiles). The target is a rock tile (15, 5) of a 20 x
## 10 map, so the centre has moved to the first open tile of ring 1, (14, 4), row by row, and the
## cell is that tile's, not the target's. A unit outside the command keeps -1. Both order types are
## run, a tank and a foot soldier in one command (one cell for the command, whatever the classes).
func test_move_and_attack_move_write_the_cell_of_the_centre_for_every_unit_of_the_command(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(
		GridWorld.from_rows(GridWorld.grass(20, 10, [Vector2i(15, 5)]), [TRACKED, FOOT]), impl
	)
	GridWorld.add_block(world, 3, 3, 3000, 2500, 1000, 0)
	world.add_unit(1, 1, 3000, 4500)
	world.add_unit(1, 0, 3000, 6500)
	assert_array(world.group_cell).is_equal([-1, -1, -1, -1, -1])
	var centre: int = 4 * 20 + 14
	var attack_move: Array[Command] = [
		_stamped(Command.attack_move(1, PackedInt32Array([1, 2, 4]), 15500, 5500), 0)
	]
	Sim.step(world, attack_move)
	assert_array(world.group_cell).is_equal([centre, centre, -1, centre, -1])
	var tiles: Dictionary = {}
	for row: int in [0, 1, 3]:
		tiles[world.cell_of(world.goal_x[row], world.goal_y[row])] = true
	assert_int(tiles.size()).is_equal(3)
	var move: Array[Command] = [_stamped(Command.move(1, PackedInt32Array([3, 5]), 15500, 5500), 1)]
	Sim.step(world, move)
	assert_array(world.group_cell).is_equal([centre, centre, centre, centre, centre])
	assert_array([world.order[0], world.order[2]]).is_equal(
		[World.Order.ATTACK_MOVE, World.Order.MOVE]
	)


## A new MOVE overwrites the cell of its own units and of no others: unit 2 is re-ordered to
## another point, units 1 and 3 keep the cell of the first command.
func test_a_new_point_order_overwrites_the_cell_of_its_own_units_only(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(world, 3, 3, 3000, 2500, 1000, 0)
	var first: Array[Command] = [
		_stamped(Command.move(1, PackedInt32Array([1, 2, 3]), 15500, 5500), 0)
	]
	Sim.step(world, first)
	var old: int = world.cell_of(15500, 5500)
	assert_array(world.group_cell).is_equal([old, old, old])
	var second: Array[Command] = [_stamped(Command.move(1, PackedInt32Array([2]), 6500, 2500), 1)]
	Sim.step(world, second)
	assert_array(world.group_cell).is_equal([old, world.cell_of(6500, 2500), old])


## ATTACK leaves -1 for the units it orders (they key on their target's tile, ADR 0008 section 3)
## and not for others: units 1 and 2 have a group target from a MOVE, unit 1 is given an ATTACK on
## the enemy unit 4.
func test_attack_clears_the_cell_of_the_units_it_orders(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	world.player_count = 2
	world.type_weapon[0] = 0
	GridWorld.add_block(world, 3, 3, 3000, 2500, 1000, 0)
	world.add_unit(2, 0, 15500, 5500)
	var moved: Array[Command] = [
		_stamped(Command.move(1, PackedInt32Array([1, 2, 3]), 10500, 5500), 0)
	]
	Sim.step(world, moved)
	var cell: int = world.cell_of(10500, 5500)
	assert_array(world.group_cell).is_equal([cell, cell, cell, -1])
	var attack: Array[Command] = [_stamped(Command.attack(1, PackedInt32Array([1]), 4), 1)]
	Sim.step(world, attack)
	assert_array(world.order.slice(0, 3)).is_equal([World.Order.ATTACK, MOVE, MOVE])
	assert_array(world.group_cell).is_equal([-1, cell, cell, -1])


## STOP leaves -1 for the units it stops and not for others.
func test_stop_clears_the_cell_of_the_units_it_stops(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(world, 3, 3, 3000, 2500, 1000, 0)
	var moved: Array[Command] = [
		_stamped(Command.move(1, PackedInt32Array([1, 2, 3]), 10500, 5500), 0)
	]
	Sim.step(world, moved)
	var cell: int = world.cell_of(10500, 5500)
	assert_array(world.group_cell).is_equal([cell, cell, cell])
	var stop: Array[Command] = [_stamped(Command.stop(1, PackedInt32Array([2])), 1)]
	Sim.step(world, stop)
	assert_array(world.order).is_equal([MOVE, IDLE, MOVE])
	assert_array(world.group_cell).is_equal([cell, -1, cell])


## The end of an order by arrival leaves -1: a tank ordered 3000 along an open row is IDLE on its
## goal within 30 ticks and the column is -1 again, while a tank ordered farther away still holds
## the cell on the same tick.
func test_arrival_clears_the_cell(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 10)), impl)
	world.add_unit(1, 0, 2500, 2500)
	world.add_unit(1, 0, 2500, 6500)
	var cell: int = world.cell_of(5500, 2500)
	var order: Array[Command] = [_stamped(Command.move(1, PackedInt32Array([1]), 5500, 2500), 0)]
	var far: Command = _stamped(Command.move(1, PackedInt32Array([2]), 27500, 6500), 0)
	far.sequence = 1
	order.append(far)
	Sim.step(world, order)
	assert_array(world.group_cell).is_equal([cell, world.cell_of(27500, 6500)])
	for _tick: int in 30:
		Sim.step(world, [] as Array[Command])
	assert_array([world.order[0], world.pos_x[0]]).is_equal([IDLE, 5500])
	assert_array([world.order[1], world.group_cell[1]]).is_equal([MOVE, world.cell_of(27500, 6500)])
	assert_int(world.group_cell[0]).is_equal(-1)


## The end of an order by stall leaves -1: a tank west of a wall across the map (column 8) with its
## goal behind it presses on the wall and goes IDLE where it stands, short of the wall, and the cell
## it was given goes with the order.
func test_a_stall_clears_the_cell(impl: int, _test_parameters := _both()) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10, rock)), impl)
	world.add_unit(1, 0, 3500, 4500)
	var order: Array[Command] = [_stamped(Command.move(1, PackedInt32Array([1]), 14500, 4500), 0)]
	Sim.step(world, order)
	assert_int(world.group_cell[0]).is_equal(world.cell_of(14500, 4500))
	for _tick: int in 300:
		Sim.step(world, [] as Array[Command])
		if world.order[0] == IDLE:
			break
	assert_array([world.order[0], world.group_cell[0]]).is_equal([IDLE, -1])
	assert_bool(world.pos_x[0] > 6000 and world.pos_x[0] < 8000).is_true()


## `reset_nav` is the navigation state, not the order: it leaves `group_cell` as it is (P41 resumes
## an order through it and the unit keeps its group target).
func test_reset_nav_leaves_the_cell_alone(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(world, 2, 2, 3000, 2500, 1000, 0)
	world.group_cell[0] = 77
	world.group_cell[1] = 0
	Movement.reset_nav(world, PackedInt32Array([0, 1]), DIRECT)
	assert_array(world.group_cell).is_equal([77, 0])
	Movement.reset_nav(world, PackedInt32Array([0, 1]), World.NavMode.NONE)
	assert_array(world.group_cell).is_equal([77, 0])


## The first line check of a blocked line keys the field on the group cell when there is one (one
## check, no sight test: the unit's own goal is in clear sight of the key and 1414 from it), else on
## the cell of the unit's own goal. A group cell of 0 is a key like any other: the unit takes the
## field of cell 0 (the map's corner tile), not of its own goal's tile. A wall in column 8 (rows 0
## to 10 of a 20 x 12 map) blocks every line; every unit checks on tick 0 (period 1).
func test_the_first_check_keys_on_the_group_cell_else_on_the_goal_tile(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, _wall(11))), impl)
	world.line_check_period_ticks = 1
	var goals: Array[Vector2i] = [
		Vector2i(15500, 2500), Vector2i(15500, 4500), Vector2i(15500, 6500)
	]
	for index: int in 3:
		world.add_unit(1, 0, 3500, 2500 + index * 2000)
		world.order[index] = MOVE
		world.goal_x[index] = goals[index].x
		world.goal_y[index] = goals[index].y
	Movement.reset_nav(world, PackedInt32Array([0, 1, 2]), DIRECT)
	world.group_cell[0] = world.cell_of(14500, 3500)
	world.group_cell[2] = 0
	world.tick = 4
	Movement.run(world)
	assert_int(world.stats[World.Stat.LINE_CHECKS]).is_equal(3)
	assert_array(world.nav_mode.slice(0, 3)).is_equal([FIELD, FIELD, FIELD])
	assert_array(world.field.slice(0, 3)).is_equal([0, 1, 2])
	assert_array(world.flow.key_goal.slice(0, 3)).is_equal(
		[world.cell_of(14500, 3500), world.cell_of(15500, 4500), 0]
	)


func _stamped(command: Command, tick: int) -> Command:
	command.tick = tick
	return command


## A wall in column 8, rows 0 to `rows` - 1.
func _wall(rows: int) -> Array[Vector2i]:
	var rock: Array[Vector2i] = []
	for row: int in rows:
		rock.append(Vector2i(8, row))
	return rock


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and INTEGRATE in the implementation asked for.
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	return world
