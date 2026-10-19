extends GdUnitTestSuite
## Stall (P37b; ADR 0008 section 2): a unit that steers at its goal for good tracks `best_dist` and
## goes IDLE where it stands when that has not improved for `stall_ticks` ticks while it is within
## `stall_range_spacings` formation spacings of the goal. A parked enemy is a push written by hand,
## the way test_movement_integrate.gd writes one; since P39b the tick computes the pushes itself, so
## these cases step with a HandPushProbe that puts the hand-written pushes back after SEPARATION.
## Maps are built in code (GridWorld): speed 120, spacing 1200, so the range is 2400.
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const HandPushProbe: GDScript = preload("res://tests/sim/support/hand_push_probe.gd")
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const NONE: int = World.NavMode.NONE
const RANGE: int = 2400


## Two tanks are ordered along their own rows of an open map, to goals 600 apart in x; once a tank
## is within 2400 of its goal a parked enemy pushes it back by exactly its step each tick, so it
## stays where it is. Its distance is recorded at its first tick in range and does not improve, so
## after `stall_ticks` (15) more ticks that tank goes IDLE where it stands: order IDLE, goal where
## it stands, no mode, no field, stall 0, no intent on its last tick. That is stall_ticks after the
## tank's own first tick in range, within stall_ticks + 1, and the two tanks' first ticks differ by
## the 5 ticks that 600 takes: the count is kept per unit.
func test_units_held_back_in_range_of_their_slots_go_idle_within_stall_ticks(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(world, 2, 1, 3040, 2000, 4000, 0)
	var seen: Array[Array] = _hold_back(world, RANGE, 10600)
	var goals: Array[int] = [10000, 10600]
	for row: int in 2:
		var first_in_range: int = seen[row][0]
		var idle_at: int = seen[row][1]
		var stood_at: int = seen[row][2]
		var label: String = "unit %d" % (row + 1)
		assert_int(first_in_range).override_failure_message(label).is_greater(30)
		assert_int(idle_at - first_in_range).override_failure_message(label).is_equal(
			world.stall_ticks
		)
		assert_int(idle_at - first_in_range).is_less_equal(world.stall_ticks + 1)
		assert_int(seen[row][3]).override_failure_message(label).is_equal(0)
		assert_array([world.order[row], world.nav_mode[row], world.stall[row]]).is_equal(
			[IDLE, NONE, 0]
		)
		assert_array([world.goal_x[row], world.goal_y[row]]).is_equal([stood_at, 2000 + row * 4000])
		assert_array([world.field[row], world.nav_next[row], world.nav_cell[row]]).is_equal(
			[-1, -1, -1]
		)
		assert_int(world.best_dist[row]).is_equal(FlowField.UNREACHED)
		assert_int(stood_at).is_between(goals[row] - RANGE, goals[row] - 120)
	assert_int(seen[1][0] - seen[0][0]).is_equal(5)
	assert_int(seen[1][1] - seen[0][1]).is_equal(5)


## The count and the range are the World's rules: with `stall_ticks` 6 and `stall_range_spacings`
## 3 (a range of 3600) the held unit goes IDLE after 6 ticks in range, and its first tick in range
## comes 10 ticks (1200 of 120 a tick) before it did with 2.
func test_stall_follows_the_rules_of_the_world(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(world, 2, 1, 3040, 2000, 4000, 0)
	var normal: Array[Array] = _hold_back(world, RANGE, 10000)
	var other: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(other, 2, 1, 3040, 2000, 4000, 0)
	other.stall_ticks = 6
	other.stall_range_spacings = 3
	var seen: Array[Array] = _hold_back(other, 3600, 10000)
	assert_int(seen[0][1] - seen[0][0]).is_equal(6)
	assert_int(seen[1][1] - seen[1][0]).is_equal(6)
	assert_int(normal[0][0] - seen[0][0]).is_equal(10)


## Progress resets the count. A tank is held back ten ticks in range, let go for one (it gains a
## step, a new best distance), held for ten again, and so on: its count climbs to 10 and falls back
## to 0, never reaching `stall_ticks` (15), and the tank arrives on its goal. Without the reset the
## second cycle would idle it.
func test_progress_resets_the_stall_count(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	world.add_unit(1, 0, 3000, 2000)
	var probe: SimProbe = HandPushProbe.new(world)
	var held: int = 0
	var top: int = 0
	for tick: int in 600:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 10000, 2000), 0))
		var left: int = world.goal_x[0] - world.pos_x[0]
		world.push_x[0] = 0
		if tick > 0 and left <= RANGE and left > 240:
			held += 1
			world.push_x[0] = 0 if held % 11 == 0 else -120
		Sim.step(world, commands, probe)
		top = maxi(top, world.stall[0])
		if world.order[0] == IDLE:
			break
	assert_int(top).is_equal(10)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([10000, 2000, IDLE])


## Out of range, a held unit does not stall: pushed back every tick 9000 from its goal for 80
## ticks it keeps its order and its mode, and tracks no distance. An ATTACK unit in range does not
## stall either (its goal walks away with the target, and combat ends the order, P41), nor a unit of
## speed 0 (it has no step to be held back from).
func test_units_out_of_range_or_attacking_or_unable_to_move_do_not_stall(
	impl: int, _test_parameters := _both()
) -> void:
	var tracked: int = World.MoveClass.TRACKED
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10), [tracked, tracked]), impl)
	world.type_speed[1] = 0
	world.player_count = 2
	world.type_weapon[0] = 0
	GridWorld.add_block(world, 3, 1, 3000, 2000, 2000, 0)
	var enemy: int = world.add_unit(2, 0, 5000, 4000)
	world.type_index[2] = 1
	world.order[0] = MOVE
	world.goal_x[0] = 12000
	world.goal_y[0] = 2000
	world.order[1] = ATTACK
	world.order_target[1] = enemy
	world.order[2] = MOVE
	world.goal_x[2] = 4500
	world.goal_y[2] = 6000
	world.push_x[0] = -120
	world.push_x[1] = -120
	var probe: SimProbe = HandPushProbe.new(world)
	for _tick: int in 80:
		Sim.step(world, [], probe)
	assert_array([world.order[0], world.nav_mode[0], world.stall[0]]).is_equal([MOVE, DIRECT, 0])
	assert_int(world.best_dist[0]).is_equal(FlowField.UNREACHED)
	assert_array([world.order[1], world.nav_mode[1], world.stall[1]]).is_equal([ATTACK, DIRECT, 0])
	assert_int(world.pos_x[1]).is_less(4000)
	assert_array([world.order[2], world.stall[2], world.pos_x[2]]).is_equal([MOVE, 0, 3000])
	assert_int(world.best_dist[2]).is_equal(FlowField.UNREACHED)


## A unit that waits for a field does not stall near its goal. A wall (column 8, rows 0 to 8 of a
## 20 x 10 map) with a gap at the bottom, the goal 1500 behind it, and a flow budget of 0: the
## field of the blocked line never completes, so the unit presses on the wall within range of its
## goal for 60 ticks and keeps its order. When the budget comes back it follows the field to the gap
## and arrives (the stall did not take it). A unit that cannot get a slot (the cache has one, held
## by another goal) is DIRECT with an unchecked line, in range of its goal, and does not stall
## either.
func test_a_unit_waiting_for_a_field_or_a_slot_does_not_stall(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 9:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10, rock)), impl)
	world.flow_cells_per_tick = 0
	world.add_unit(1, 0, 6500, 2500)
	var order: Command = _stamped(Command.move(1, PackedInt32Array([1]), 9500, 2500), 0)
	Sim.step(world, [order])
	for _tick: int in 60:
		Sim.step(world, [])
	assert_array([world.order[0], world.nav_mode[0], world.field[0]]).is_equal([MOVE, FIELD, 0])
	assert_int(world.pos_x[0]).is_between(7500, 7999)
	assert_array([world.stall[0], world.best_dist[0]]).is_equal([0, FlowField.UNREACHED])
	world.flow_cells_per_tick = 512
	for _tick: int in 400:
		Sim.step(world, [])
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([9500, 2500, IDLE])
	var tight: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10, rock)), impl)
	tight.flow_cache_size = 1
	tight.flow.configure(tight.map_cols, tight.map_rows, World.MoveClass.size(), 1)
	tight.flow_cells_per_tick = 0
	tight.add_unit(1, 0, 6500, 2500)
	tight.add_unit(1, 0, 6500, 8500)
	var near: Command = _stamped(Command.move(1, PackedInt32Array([1]), 9500, 2500), 0)
	var far: Command = _stamped(Command.move(1, PackedInt32Array([2]), 15500, 8500), 0)
	Sim.step(tight, [near, far])
	for _tick: int in 60:
		Sim.step(tight, [])
	# Unit 2 checks first ((3 + 2) % 5) and holds the one slot; unit 1 checks after it.
	assert_array([tight.nav_mode[1], tight.field[1]]).is_equal([FIELD, 0])
	assert_array([tight.order[0], tight.nav_mode[0], tight.field[0]]).is_equal([MOVE, DIRECT, -1])
	assert_array([tight.nav_cell[0], tight.stall[0]]).is_equal([-1, 0])
	assert_int(tight.pos_x[0]).is_between(7500, 7999)


## A unit whose goal the field cannot reach (a wall across the whole map, the goal 1500 behind it)
## is FIELD on a complete field with no next tile: it steers at its goal, presses on the wall within
## range of it, and stalls there like any unit that cannot get closer. It is IDLE after about
## `stall_ticks` ticks of pressing, on its side of the wall, with no field.
func test_a_unit_on_ground_the_field_does_not_reach_stalls_in_range_of_its_goal(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10, rock)), impl)
	world.add_unit(1, 0, 3500, 4500)
	var idle_at: int = -1
	for tick: int in 300:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 9500, 4500), 0))
		Sim.step(world, commands)
		if world.order[0] == IDLE:
			idle_at = tick
			break
	assert_int(idle_at).is_greater(0)
	assert_bool(world.flow.field(0).complete).is_true()
	assert_int(world.pos_x[0]).is_between(7800, 7999)
	assert_array([world.field[0], world.nav_mode[0], world.nav_next[0]]).is_equal([-1, NONE, -1])
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([world.pos_x[0], world.pos_y[0]])


## On ground the field does not reach the stall has no range (ADR 0008 section 2, P37b): a tank west
## of a wall across the whole map (column 8) with its goal 6500 behind it, far out of the range,
## presses on the wall; its field names no next tile, so with no progress for `stall_ticks` its
## order ends where it stands and its slot is free.
func test_a_unit_on_ground_the_field_does_not_reach_ends_its_order_at_any_distance(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10, rock)), impl)
	world.add_unit(1, 0, 3500, 4500)
	var pressed_at: int = -1
	var idle_at: int = -1
	for tick: int in 300:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 14500, 4500), 0))
		Sim.step(world, commands)
		if pressed_at == -1 and world.pos_x[0] >= 7800 and world.nav_next[0] == Movement.NO_NEXT:
			pressed_at = tick
		if world.order[0] == IDLE:
			idle_at = tick
			break
	assert_int(pressed_at).is_greater(0)
	assert_int(idle_at).is_between(
		pressed_at + world.stall_ticks, pressed_at + world.stall_ticks + 3
	)
	assert_bool(world.pos_x[0] < 8000).is_true()
	assert_array([world.field[0], world.nav_mode[0], world.group_cell[0]]).is_equal([-1, NONE, -1])
	FlowCache.run(world, 0)
	assert_int(world.flow.refs(0)).is_equal(0)


## An ATTACK unit does not stall on ground the field does not reach either: the same wall, a tank
## ordered to attack an enemy 11000 behind it presses on the wall for 300 ticks with its order, its
## mode and its field, and no next tile (its target may walk into reach, and combat ends the order,
## P41). The rule that frees the slot of a MOVE unit is for orders that have a goal to arrive at.
func test_an_attack_unit_on_ground_the_field_does_not_reach_keeps_its_order(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10, rock)), impl)
	world.player_count = 2
	world.type_weapon[0] = 0
	world.add_unit(1, 0, 3500, 4500)
	world.add_unit(2, 0, 14500, 4500)
	for tick: int in 300:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.attack(1, PackedInt32Array([1]), 2), 0))
		Sim.step(world, commands)
	assert_array([world.order[0], world.nav_mode[0], world.nav_next[0]]).is_equal(
		[ATTACK, FIELD, Movement.NO_NEXT]
	)
	assert_array([world.stall[0], world.best_dist[0]]).is_equal([0, FlowField.UNREACHED])
	assert_int(world.pos_x[0]).is_between(7500, 7999)


## The range of the stall is the formation spacing of the unit's own type, and the tick a unit goes
## IDLE it keeps its whole push and its goal is where it stood. Two tanks of different types
## (spacings 1200 and 3000, so ranges 2400 and 6000) stand 5000 from goals that lie off their rows
## (4000 east, 3000 south of them, a step of (96, 72)); a parked enemy pushes both by (-120, -96)
## each tick, which carries them away from the goal at about 34 a tick. The tank of type 1 is
## within its range from tick 0 and goes IDLE `stall_ticks` ticks later; the tank of type 0 is out
## of its own range and keeps its order, with no distance tracked. On the stall tick the unit of
## type 1 has no intent on either axis, moves by the push on both axes and has its goal where it
## stood, on both axes.
func test_the_stall_range_is_the_spacing_of_the_units_type_and_the_push_is_kept(
	impl: int, _test_parameters := _both()
) -> void:
	var tracked: int = World.MoveClass.TRACKED
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10), [tracked, tracked]), impl)
	world.type_spacing[1] = 3000
	world.add_unit(1, 0, 3000, 2000)
	world.add_unit(1, 1, 3000, 6000)
	for row: int in 2:
		world.order[row] = MOVE
		world.goal_x[row] = 7000
		world.goal_y[row] = world.pos_y[row] + 3000
	Movement.reset_nav(world, PackedInt32Array([0, 1]), DIRECT)
	for row: int in 2:
		world.nav_cell[row] = world.cell_of(world.pos_x[row], world.pos_y[row])
	var probe: SimProbe = HandPushProbe.new(world)
	var first_in_range: int = -1
	var idle_at: int = -1
	for tick: int in 40:
		for row: int in 2:
			world.push_x[row] = -120 if world.order[row] != IDLE else 0
			world.push_y[row] = -96 if world.order[row] != IDLE else 0
		var stood_at: Vector2i = Vector2i(world.pos_x[1], world.pos_y[1])
		Sim.step(world, [], probe)
		if first_in_range == -1 and world.best_dist[1] != FlowField.UNREACHED:
			first_in_range = tick
		if idle_at == -1 and world.order[1] == IDLE:
			idle_at = tick
			assert_array([world.goal_x[1], world.goal_y[1]]).is_equal([stood_at.x, stood_at.y])
			assert_array([world.pos_x[1], world.pos_y[1]]).is_equal(
				[stood_at.x - 120, stood_at.y - 96]
			)
			assert_array([world.intent_x[1], world.intent_y[1]]).is_equal([0, 0])
	assert_int(first_in_range).is_equal(0)
	assert_int(idle_at - first_in_range).is_equal(world.stall_ticks)
	assert_array([world.nav_mode[1], world.field[1], world.stall[1]]).is_equal([NONE, -1, 0])
	assert_array([world.order[0], world.nav_mode[0], world.stall[0]]).is_equal([MOVE, DIRECT, 0])
	assert_int(world.best_dist[0]).is_equal(FlowField.UNREACHED)


## Orders unit 1 along row 2000 to x 10000 and unit 2 along row 6000 to x `second_goal`, and from
## the tick a unit is within `reach` of its goal a parked enemy pushes it back by its whole step
## each tick. Runs 200 ticks and returns, for each unit, [the first tick with a best distance, the
## tick the unit went IDLE, its x at the start of that tick, its x intent at the end of it].
func _hold_back(world: World, reach: int, second_goal: int) -> Array[Array]:
	var found: Array[Array] = [[-1, -1, -1, -1], [-1, -1, -1, -1]]
	var probe: SimProbe = HandPushProbe.new(world)
	for tick: int in 200:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 10000, 2000), 0))
			commands.append(_stamped(Command.move(1, PackedInt32Array([2]), second_goal, 6000), 0))
		var before: Array[int] = [world.pos_x[0], world.pos_x[1]]
		for row: int in 2:
			var left: int = world.goal_x[row] - world.pos_x[row]
			var held: bool = tick > 0 and left <= reach and world.order[row] != IDLE
			world.push_x[row] = -120 if held else 0
		Sim.step(world, commands, probe)
		for row: int in 2:
			if found[row][0] == -1 and world.best_dist[row] != FlowField.UNREACHED:
				found[row][0] = tick
			if found[row][1] == -1 and world.order[row] == IDLE:
				found[row] = [found[row][0], tick, before[row], world.intent_x[row]]
	return found


func _stamped(command: Command, tick: int) -> Command:
	command.tick = tick
	return command


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and INTEGRATE in the implementation asked for.
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	return world
