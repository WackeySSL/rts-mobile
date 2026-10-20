extends GdUnitTestSuite
## Movement v2, part 2 (P37a2; ADR 0008 sections 2 and 4, ADR 0007 section 4): the intent phase
## (`Movement.run`) and the integrate phase (`Movement.integrate`) with `DIRECT`, `HOLD` and
## `CHASE`, the staggered line checks and the slide. Maps are built in code (GridWorld); a unit has
## speed 120, radius 400 and formation spacing 1200 unless a case changes the type table. The
## exactness cases use one unit per lane, or units that never come within their radii sum, so they
## stay valid when P39b adds separation (plan, "File ownership", the first audited table). The
## slide's per-class, clamp, push and no-map cases are in test_movement_integrate.gd.
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const MovementV1: GDScript = preload("res://tests/sim/support/movement_v1.gd")
const PhaseViewProbe: GDScript = preload("res://tests/sim/support/phase_view_probe.gd")
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const NONE: int = World.NavMode.NONE

## Filled by _run_script: the hash after every tick.
var _hashes: PackedInt64Array = PackedInt64Array()


## Eight lanes of one unit each on an open 30 x 30 map, with the orders written by hand (nav_mode
## stays NONE, so a unit with an order starts DIRECT by itself). The new phases and Phase 1's
## frozen mover give the same positions and orders after every one of 80 ticks: a snap, the
## truncating step on axes and diagonals, a goal that d2 puts a tick later than the rounded
## distance does ((1, 120) away), a speed 0 unit that never arrives, an ATTACK unit that keeps its
## order and a unit already on its goal.
func test_on_an_open_map_every_tick_equals_phase_1(impl: int, _test_parameters := _both()) -> void:
	var lanes: Array[Array] = [
		# type, order, start, goal
		[0, MOVE, Vector2i(500, 1500), Vector2i(7001, 1502)],
		[1, World.Order.ATTACK_MOVE, Vector2i(500, 4500), Vector2i(4500, 4800)],
		[0, MOVE, Vector2i(9000, 7500), Vector2i(1000, 7900)],
		[0, World.Order.ATTACK_MOVE, Vector2i(2000, 10500), Vector2i(2001, 10620)],
		[2, MOVE, Vector2i(3000, 13500), Vector2i(3500, 13500)],
		[0, ATTACK, Vector2i(5000, 16500), Vector2i(8000, 17500)],
		[0, MOVE, Vector2i(5000, 19500), Vector2i(5000, 19500)],
		[1, MOVE, Vector2i(9500, 25500), Vector2i(9200, 22400)],
	]
	var now: World = _lanes(lanes, impl)
	var then: World = _lanes(lanes, impl)
	for tick: int in 80:
		Movement.run(now)
		assert_bool(_within_speed(now)).override_failure_message("tick %d" % tick).is_true()
		Movement.integrate(now)
		now.tick += 1
		MovementV1.move_units(then)
		then.tick += 1
		var label: String = "tick %d" % tick
		assert_array(now.pos_x).override_failure_message(label).is_equal(then.pos_x)
		assert_array(now.pos_y).override_failure_message(label).is_equal(then.pos_y)
		assert_array(now.order).override_failure_message(label).is_equal(then.order)
	# Not vacuous: everything that can arrive did, the ATTACK unit stands on its goal and kept its
	# order, and the speed 0 unit (type 2) stayed where it was.
	assert_array(now.order).is_equal([IDLE, IDLE, IDLE, IDLE, MOVE, ATTACK, IDLE, IDLE])
	assert_array([now.pos_x[5], now.pos_y[5]]).is_equal([8000, 17500])
	assert_array([now.pos_x[4], now.pos_y[4]]).is_equal([3000, 13500])
	assert_array([now.pos_x[0], now.pos_y[0]]).is_equal([7001, 1502])
	assert_int(now.nav_mode.count(DIRECT)).is_equal(2)


## A tank steers diagonally into a wall of rock (tile column 5, every row of a 12 x 8 map) and
## slides down it: when the x step would enter the rock, the y step alone is taken, so it ends on
## the goal's row against the wall. Its centre is on a passable tile after every tick, it never
## goes IDLE (the goal is behind the wall: part 3 gives it a field), and its blocked line keeps it
## DIRECT.
func test_a_direct_unit_steering_into_a_wall_slides_and_is_never_on_a_blocked_tile(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 8:
		rock.append(Vector2i(5, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(12, 8, rock)), impl)
	world.add_unit(1, 0, 3500, 2500)
	assert_bool(FixedMath.line_clear(world, 3500, 2500, 7500, 6500, TRACKED)).is_false()
	var slid: int = 0
	var checks: int = 0
	var last: Vector2i = Vector2i(3500, 2500)
	for tick: int in 120:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 7500, 6500), 0))
		Sim.step(world, commands)
		checks += world.stats[World.Stat.LINE_CHECKS]
		var here: Vector2i = Vector2i(world.pos_x[0], world.pos_y[0])
		(
			assert_bool(world.is_passable(world.cell_of(here.x, here.y), TRACKED))
			. override_failure_message("tick %d at %s" % [tick, here])
			. is_true()
		)
		if here.x == last.x and here.y != last.y:
			slid += 1
		last = here
	# The y step truncates to 0 once the goal's row is less than a step per 2500 away.
	assert_int(slid).is_greater(10)
	assert_bool(last.x > 4800 and last.x < 5000).override_failure_message(str(last)).is_true()
	assert_bool(last.y > 6450 and last.y <= 6500).override_failure_message(str(last)).is_true()
	# P37b: the blocked line gives it a field, which reaches nothing on its side of the wall, so it
	# steers at its goal and slides on. One DIRECT check, then one per tile it enters (rows 3 to 6).
	# The field names no next tile (NO_NEXT) and the unit is 4000 from its goal, outside the stall
	# range: with no progress for `stall_ticks` its order ends where it stands, field and all.
	assert_array([world.order[0], world.nav_mode[0], checks]).is_equal([IDLE, NONE, 5])
	assert_array([world.field[0], world.nav_next[0]]).is_equal([-1, -1])


## 150 tanks ordered at once: the first line checks of `(tick + id) % 5 == 0` units come one fifth
## per tick, 30 on each of the first five ticks and none after, so no tick checks all 150 and each
## unit checks first exactly once. Some of the lines cross the rock and some do not: a clear line
## stays clear and keeps the unit DIRECT, a blocked one makes it FIELD (P37b), and a FIELD unit
## checks again each time it enters a tile. `stats[LINE_CHECKS]` counts every line test, and a unit
## that needs a field takes its group's, so there is no test beyond the first checks and the tile
## entries.
func test_a_150_unit_order_spreads_its_line_checks(impl: int, _test_parameters := _both()) -> void:
	var rock: Array[Vector2i] = []
	for row: int in range(10, 30):
		rock.append(Vector2i(20, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(40, 40, rock)), impl)
	var rows: PackedInt32Array = GridWorld.add_block(world, 150, 15, 2000, 2000, 1000, 0)
	var ids: PackedInt32Array = PackedInt32Array(range(1, 151))
	var per_tick: Array[int] = []
	var first_per_tick: Array[int] = []
	for tick: int in 10:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, ids, 34000, 20000), 0))
		var before: PackedInt32Array = _cells(world)
		var unchecked: PackedInt32Array = world.nav_cell.duplicate()
		Sim.step(world, commands)
		var entered: int = 0
		var first: int = 0
		for row: int in rows:
			entered += 1 if world.cell_of(world.pos_x[row], world.pos_y[row]) != before[row] else 0
			first += 1 if unchecked[row] == -1 and world.nav_cell[row] != -1 else 0
		var checks: int = world.stats[World.Stat.LINE_CHECKS]
		per_tick.append(checks)
		first_per_tick.append(first)
		(
			assert_int(checks)
			. override_failure_message("tick %d checked %d, %d entered" % [tick, checks, entered])
			. is_less_equal(first + entered)
		)
		assert_int(checks).is_greater_equal(first)
	assert_array(first_per_tick).is_equal([30, 30, 30, 30, 30, 0, 0, 0, 0, 0])
	# The first five ticks hold the first checks; after them only FIELD units checking again as they
	# enter a tile (tick 9). Nobody waits for a slot (nav_cell -1) because the group shares one field,
	# which completes on tick 4: from then on all 103 FIELD units steer on tile centres and 19 of them
	# cross a tile boundary on tick 9 (26 before P39b: the pushes of the block moved the others).
	assert_array(per_tick).is_equal([30, 30, 30, 30, 30, 0, 0, 0, 0, 19])
	assert_int(world.nav_cell.count(-1)).is_equal(0)
	assert_int(world.nav_mode.count(DIRECT) + world.nav_mode.count(FIELD)).is_equal(150)
	assert_int(world.nav_mode.count(FIELD)).is_equal(103)


## A check writes the unit's cell at that moment and counts once; the unit is not checked again
## while it moves on to other tiles. Unit 5 checks on the order's tick (5 % 5 == 0), unit 1 on
## tick 4 ((4 + 1) % 5 == 0), from the tile it has reached by then. A new order marks the line
## unchecked again, and the next check follows the cadence of the tick it was given on.
func test_a_line_check_writes_the_cell_and_a_new_order_marks_the_line_unchecked(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	GridWorld.add_block(world, 5, 1, 2800, 2500, 1000, 0)
	var ids: PackedInt32Array = PackedInt32Array([1, 5])
	var counts: Array[int] = []
	var first_cell: int = world.cell_of(world.pos_x[0], world.pos_y[0])
	for tick: int in 10:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, ids, 18000, 5000), 0))
		if tick == 5:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 18000, 2500), 5))
		var cells: PackedInt32Array = _cells(world)
		Sim.step(world, commands)
		counts.append(world.stats[World.Stat.LINE_CHECKS])
		if tick == 0:
			assert_array([world.nav_cell[0], world.nav_cell[4]]).is_equal([-1, cells[4]])
		if tick == 3:
			assert_int(world.nav_cell[0]).is_equal(-1)
		if tick == 4:
			assert_int(world.nav_cell[0]).is_equal(cells[0])
			assert_int(cells[0]).is_not_equal(first_cell)
		if tick == 5:
			assert_int(world.nav_cell[0]).is_equal(-1)
		if tick == 9:
			assert_int(world.nav_cell[0]).is_equal(cells[0])
	assert_array(counts).is_equal([1, 0, 0, 0, 1, 0, 0, 0, 0, 1])
	assert_array(world.nav_cell.slice(1, 4)).is_equal([-1, -1, -1])
	# A period of 0 (a hand-built rule) is read as 1: the unit checks on its first tick.
	var every: World = _in(GridWorld.from_rows(GridWorld.grass(20, 10)), impl)
	every.line_check_period_ticks = 0
	every.add_unit(1, 0, 2800, 2500)
	every.order[0] = MOVE
	every.goal_x[0] = 9000
	every.goal_y[0] = 2500
	Movement.run(every)
	assert_array([every.stats[World.Stat.LINE_CHECKS], every.nav_cell[0]]).is_equal([1, 42])


## Arrival sets IDLE on the tick the goal is within one step at the start of the tick (d2 <=
## speed^2): the unit is on the goal, its navigation state is cleared. An ATTACK unit snaps to its
## goal and keeps its order and mode. A goal one milli further takes one more tick, because it is
## not within one step after the first.
func test_arrival_sets_idle_at_the_goal(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 10)), impl)
	GridWorld.add_block(world, 3, 1, 1000, 1000, 2000, 0)
	for row: int in 3:
		world.order[row] = MOVE
		world.goal_x[row] = 1000 + 2 * 120 + (1 if row == 2 else 0)
		world.goal_y[row] = world.pos_y[row]
	world.order[1] = ATTACK
	_step_phases(world)
	assert_array([world.pos_x[0], world.order[0], world.nav_mode[0]]).is_equal([1120, MOVE, DIRECT])
	_step_phases(world)
	assert_array([world.pos_x[0], world.order[0], world.nav_mode[0], world.nav_cell[0]]).is_equal(
		[1240, IDLE, NONE, -1]
	)
	assert_array([world.pos_x[1], world.order[1], world.nav_mode[1]]).is_equal(
		[1240, ATTACK, DIRECT]
	)
	assert_array([world.pos_x[2], world.order[2]]).is_equal([1240, MOVE])
	_step_phases(world)
	assert_array([world.pos_x[2], world.order[2], world.nav_mode[2]]).is_equal([1241, IDLE, NONE])
	assert_array([world.pos_x[1], world.order[1], world.nav_mode[1]]).is_equal(
		[1240, ATTACK, DIRECT]
	)


## HOLD produces no intent: the unit keeps its order and its place, and a stale intent in the
## scratch arrays is overwritten, also on an idle row. Back to DIRECT it moves at once.
func test_hold_produces_no_intent(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 10)), impl)
	GridWorld.add_block(world, 3, 1, 1000, 1000, 2000, 0)
	for row: int in 3:
		world.intent_x[row] = 77
		world.intent_y[row] = -77
	world.order[0] = MOVE
	world.nav_mode[0] = World.NavMode.HOLD
	world.goal_x[0] = 8000
	world.goal_y[0] = 1000
	world.order[2] = MOVE
	world.nav_mode[2] = DIRECT
	world.goal_x[2] = 8000
	world.goal_y[2] = 5000
	# A fourth unit holds with its goal within one step: it is not steering at it, so it has not
	# arrived and its order stays.
	world.add_unit(1, 0, 1000, 7000)
	world.order[3] = MOVE
	world.nav_mode[3] = World.NavMode.HOLD
	world.goal_x[3] = 1050
	world.goal_y[3] = 7000
	for _tick: int in 10:
		Movement.run(world)
		assert_array([world.intent_x[0], world.intent_y[0]]).is_equal([0, 0])
		assert_array([world.intent_x[1], world.intent_y[1]]).is_equal([0, 0])
		assert_array([world.intent_x[2], world.intent_y[2]]).is_equal([120, 0])
		Movement.integrate(world)
		world.tick += 1
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([1000, 1000, MOVE])
	assert_array([world.pos_x[1], world.pos_y[1], world.order[1]]).is_equal([1000, 3000, IDLE])
	assert_int(world.pos_x[2]).is_equal(1000 + 1200)
	assert_array([world.pos_x[3], world.order[3], world.nav_mode[3]]).is_equal(
		[1000, MOVE, World.NavMode.HOLD]
	)
	world.nav_mode[0] = DIRECT
	Movement.run(world)
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.intent_x[0]]).is_equal([1120, 120])


## CHASE steers straight at the unit in `target`, by where it stands at the start of the tick, and
## not at the goal; within one step it reaches the target's point without ending the order, and a
## goal within one step does not end it either (the unit is not steering at it). The target is found
## by id: unit 2 is removed first, so the target, id 3, is row 1. A target that is gone (an id no
## row has, or 0) leaves the unit on its goal. The tick is 4, unit 1's line-check tick ((4 + 1) % 5
## is 0): a DIRECT unit with an unchecked line would check now, a CHASE unit never does, so nothing
## is counted and its cell stays -1.
func test_chase_steers_at_the_target(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 10)), impl)
	world.add_unit(1, 0, 2000, 2000)
	world.add_unit(1, 0, 7000, 7000)
	world.add_unit(1, 0, 2000, 5000)
	world.hp[1] = 0
	world.remove_dead()
	assert_array(world.unit_id).is_equal([1, 3])
	world.tick = 4
	assert_int(world.line_check_period_ticks).is_equal(5)
	world.order[0] = World.Order.ATTACK_MOVE
	world.nav_mode[0] = World.NavMode.CHASE
	world.target[0] = 3
	world.goal_x[0] = 9000
	world.goal_y[0] = 2000
	Movement.run(world)
	assert_array([world.intent_x[0], world.intent_y[0]]).is_equal([0, 120])
	Movement.integrate(world)
	# The target moves by hand: a 3-4-5 vector from the chaser's new place gives (72, 96).
	world.pos_x[1] = 2000 + 300
	world.pos_y[1] = 2120 + 400
	Movement.run(world)
	assert_array([world.intent_x[0], world.intent_y[0]]).is_equal([72, 96])
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([2072, 2216])
	# Within one step the intent is the whole vector; the chaser neither idles nor changes mode.
	world.pos_x[1] = 2072 + 50
	world.pos_y[1] = 2216 - 60
	Movement.run(world)
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([2122, 2156])
	assert_array([world.order[0], world.nav_mode[0]]).is_equal(
		[World.Order.ATTACK_MOVE, World.NavMode.CHASE]
	)
	# The goal is within one step now, and the target is far: the chase goes on, the order stays.
	world.goal_x[0] = 2122 + 50
	world.goal_y[0] = 2156
	world.pos_x[1] = 2122
	world.pos_y[1] = 8000
	Movement.run(world)
	Movement.integrate(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([2122, 2276])
	assert_array([world.order[0], world.nav_mode[0]]).is_equal(
		[World.Order.ATTACK_MOVE, World.NavMode.CHASE]
	)
	world.goal_x[0] = 9000
	world.goal_y[0] = 2000
	for gone: int in [99, 0]:
		world.target[0] = gone
		var expected: Vector2i = FixedMath.step_toward(2122, 2276, 9000, 2000, 120)
		Movement.run(world)
		assert_array([world.intent_x[0], world.intent_y[0]]).is_equal(
			[expected.x - 2122, expected.y - 2276]
		)
	assert_int(world.stats[World.Stat.LINE_CHECKS]).is_equal(0)
	assert_array([world.nav_cell[0], world.nav_mode[0]]).is_equal([-1, World.NavMode.CHASE])


## A CHASE unit whose target is gone steers at its goal and, once there, still has its order and its
## mode: `integrate` never ends a CHASE unit's order, and combat (`Targeting._engage`, P41b: see
## test_engagement.gd, through `Sim.step`) is what takes a unit out of CHASE when its target goes
## (the fallback documented in Movement.run, which these phases alone leave in CHASE). A DIRECT
## unit in the next lane, on the same errand, arrives and goes idle.
func test_a_chase_unit_with_no_target_reaches_its_goal_and_keeps_its_order(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 10)), impl)
	world.add_unit(1, 0, 2000, 2000)
	world.add_unit(1, 0, 2000, 4000)
	for row: int in 2:
		world.order[row] = World.Order.ATTACK_MOVE
		world.goal_x[row] = 3000
		world.goal_y[row] = world.pos_y[row]
	world.nav_mode[0] = World.NavMode.CHASE
	world.target[0] = 99
	world.nav_mode[1] = DIRECT
	for _tick: int in 20:
		_step_phases(world)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([3000, 2000])
	assert_array([world.order[0], world.nav_mode[0]]).is_equal(
		[World.Order.ATTACK_MOVE, World.NavMode.CHASE]
	)
	assert_array([world.pos_x[1], world.pos_y[1], world.order[1]]).is_equal([3000, 4000, IDLE])


## Sim.step marks INTENTS after `Movement.run` and INTEGRATE after `Movement.integrate`, so the PERF
## split books the time of each under its own phase (the split compares between PRs, plan P38p). A
## probe that reads the World at each mark sees it: at COMMANDS the MOVE order is applied and the
## intent is not written, at FLOW (P37b), GRIDS (P39b) and TARGETING (P41) nothing has moved yet,
## at INTENTS the intent is written and the unit has not moved, and so at SEPARATION (P39b, which
## comes between INTENTS and INTEGRATE), at INTEGRATE the unit has moved.
func test_the_intents_mark_follows_movement_run_and_the_integrate_mark_follows_the_move(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 10)), impl)
	world.add_unit(1, 0, 1000, 5000)
	var probe: SimProbe = PhaseViewProbe.new()
	probe.world = world
	var command: Command = _stamped(Command.move(1, PackedInt32Array([1]), 8000, 5000), 0)
	Sim.step(world, [command], probe)
	assert_int(world.dropped_commands).is_equal(0)
	var phases: Array[int] = [
		SimProbe.Phase.COMMANDS,
		SimProbe.Phase.FLOW,
		SimProbe.Phase.GRIDS,
		SimProbe.Phase.TARGETING,
		SimProbe.Phase.INTENTS,
		SimProbe.Phase.SEPARATION,
		SimProbe.Phase.INTEGRATE,
		SimProbe.Phase.REMOVE
	]
	assert_array(probe.phases).is_equal(phases)
	assert_array(probe.intents_x).is_equal([0, 0, 0, 0, 120, 120, 120, 120])
	assert_array(probe.positions_x).is_equal([1000, 1000, 1000, 1000, 1000, 1000, 1120, 1120])


## A new order makes the unit DIRECT with its line unchecked, whatever it was doing, and a STOP
## makes it NONE. Units that are not in the command keep their state (unit 3, a FIELD unit: since
## P41b a HOLD or CHASE unit without a target resumes its path on the next tick, so the bystander
## cannot be one). The tick is 1, which is nobody's line-check tick for ids 1 and 2 ((1 + 1) % 5
## and (1 + 2) % 5 are not 0).
func test_orders_reset_the_navigation_state(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 10)), impl)
	world.player_count = 2
	world.type_weapon[0] = 0
	world.add_unit(1, 0, 1000, 1000)
	world.add_unit(1, 0, 1000, 3000)
	world.add_unit(1, 0, 1000, 5000)
	world.add_unit(2, 0, 8000, 8000)
	var ids: PackedInt32Array = PackedInt32Array([1, 2])
	var orders: Array[Command] = [
		Command.move(1, ids, 5000, 5000),
		Command.attack_move(1, ids, 5000, 5000),
		Command.attack(1, ids, 4),
		Command.stop(1, ids),
	]
	for command: Command in orders:
		world.tick = 1
		command.tick = 1
		world.nav_mode[0] = World.NavMode.CHASE
		world.nav_cell[0] = 17
		world.nav_mode[1] = World.NavMode.HOLD
		world.nav_cell[1] = 18
		world.nav_mode[2] = World.NavMode.FIELD
		world.nav_cell[2] = 19
		Sim.step(world, [command])
		var mode: int = NONE if command.type == Command.Type.STOP else DIRECT
		var label: String = "command type %d" % command.type
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(0)
		assert_array(world.nav_mode.slice(0, 3)).is_equal([mode, mode, World.NavMode.FIELD])
		assert_array(world.nav_cell.slice(0, 3)).is_equal([-1, -1, 19])


## The same commands twice give the same hash after every one of 200 ticks, on a map with a wall,
## and the run is not trivial: units took their fields round the wall, some arrived, every ordered
## unit checked. The equality of the hashes is the rule. The count of arrived units pins this
## phase's behaviour; P39b's separation moves others, so it re-pinned the count (13 to 12: with the
## pushes of the crowd one unit fewer has arrived by tick 200, the rest are still on their way).
## P37b changed it from 18 to 13: the tanks that were ordered back west at tick 60 had followed
## their fields towards the wall's north end, so more of them are still on the way at tick 200; no
## unit is still FIELD then (the infantry's lines are clear by tick 200).
func test_two_runs_give_the_same_hashes(impl: int, _test_parameters := _both()) -> void:
	var first: World = _run_script(impl)
	var first_hashes: PackedInt64Array = _hashes.duplicate()
	var second: World = _run_script(impl)
	assert_array(_hashes).is_equal(first_hashes)
	assert_array(second.pos_x).is_equal(first.pos_x)
	assert_int(first_hashes.size()).is_equal(200)
	assert_int(first.order.count(IDLE)).is_equal(12)
	assert_int(first.nav_mode.count(FIELD)).is_equal(0)
	# Arrival clears the line check with the rest of the navigation state; nobody else is unchecked.
	assert_int(first.nav_cell.count(-1)).is_equal(first.order.count(IDLE))


## 20 tanks and 20 infantry on a 30 x 30 map with a wall (tile column 15, rows 5 to 24), all ordered
## east behind the wall at tick 0 and the tanks back west at tick 60. Leaves the hash of every tick
## in `_hashes` and returns the world.
func _run_script(impl: int) -> World:
	var rock: Array[Vector2i] = []
	for row: int in range(5, 25):
		rock.append(Vector2i(15, row))
	var world: World = _in(
		GridWorld.from_rows(GridWorld.grass(30, 30, rock), [TRACKED, World.MoveClass.FOOT]), impl
	)
	GridWorld.add_block(world, 20, 5, 2000, 8000, 1100, 0)
	GridWorld.add_block(world, 20, 5, 2000, 14000, 1100, 1)
	_hashes = PackedInt64Array()
	for tick: int in 200:
		var commands: Array[Command] = []
		if tick == 0:
			var all: PackedInt32Array = PackedInt32Array(range(1, 41))
			commands.append(_stamped(Command.move(1, all, 25000, 12000), 0))
		if tick == 60:
			var tanks: PackedInt32Array = PackedInt32Array(range(1, 21))
			commands.append(_stamped(Command.attack_move(1, tanks, 3000, 20000), 60))
		Sim.step(world, commands)
		_hashes.append(world.state_hash())
	return world


## A World with one unit type per entry of the type column of `lanes` (speeds 120, 61 and 0), one
## unit per lane with its order and goal set by hand, on an open 30 x 30 map.
func _lanes(lanes: Array[Array], impl: int) -> World:
	var world: World = _in(
		GridWorld.from_rows(GridWorld.grass(30, 30), [TRACKED, TRACKED, TRACKED]), impl
	)
	world.type_speed[1] = 61
	world.type_speed[2] = 0
	for lane: Array in lanes:
		var start: Vector2i = lane[2]
		var goal: Vector2i = lane[3]
		var row: int = world.add_unit(1, int(lane[0]), start.x, start.y) - 1
		world.order[row] = int(lane[1])
		world.goal_x[row] = goal.x
		world.goal_y[row] = goal.y
	return world


## Whether every intent is within -speed..speed on both axes (the contract of the scratch arrays).
func _within_speed(world: World) -> bool:
	for row: int in world.unit_count():
		var speed: int = world.type_speed[world.type_index[row]]
		if absi(world.intent_x[row]) > speed or absi(world.intent_y[row]) > speed:
			return false
	return true


## One tick of the two movement phases on their own.
func _step_phases(world: World) -> void:
	Movement.run(world)
	Movement.integrate(world)
	world.tick += 1


## The cell of every unit.
func _cells(world: World) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		cells.append(world.cell_of(world.pos_x[row], world.pos_y[row]))
	return cells


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
