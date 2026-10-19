extends GdUnitTestSuite
## The FLOW line of Sim.step (P37b; ADR 0007 section 4, ADR 0012 section 5): `FlowCache.run` with
## `flow_cells_per_tick`, and a budget of 0 on the step after which MatchLoop adds a checkpoint.
## Inside Sim.step that tick is `world.tick + 1`, because Sim.step counts the tick last. The cases
## step through MatchLoop, the only tick driver, on a map built in code (GridWorld).
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.
## The case of the spy kernel stays as it is: it needs no library.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const KernelSpy: GDScript = preload("res://tests/sim/support/kernel_spy.gd")
const BUDGET: int = 25
const COLS: int = 40
const ROWS: int = 40


## A 40 x 40 map with a wall in column 20 (a gap in rows 30 to 33), one tank ordered across it, and
## a budget of 25 cells a tick: a field of about 1500 cells takes about 60 ticks, so it is pending
## across the checkpoints at ticks 15, 30, 45 and 60. On every step after which `loop.replay` has a
## new checkpoint `stats[FLOW_CELLS]` is exactly 0; on every other step while the field is pending
## it is exactly the budget, except on the one step that finishes the field, which settles what was
## left; and the field completes with every reachable cell settled once. A rule that tests
## `world.tick` instead of `world.tick + 1` fails on the first checkpoint step (the budget would be
## 25 there).
func test_no_flow_slice_runs_on_the_steps_that_take_a_checkpoint(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _wall_world(impl)
	world.flow_cells_per_tick = BUDGET
	var loop: MatchLoop = MatchLoop.create(null, "", 1, world)
	var reachable: int = COLS * ROWS - world.move_cost.slice(0, COLS * ROWS).count(0)
	var total: int = 0
	var checkpoint_steps_pending: int = 0
	var pending_steps: int = 0
	var full_steps: int = 0
	var finished_at: int = -1
	for tick: int in 150:
		var queued: Array[Command] = []
		if tick == 0:
			var order: Command = Command.move(1, PackedInt32Array([1]), 33500, 5500)
			queued.append(order)
		var checkpoints: int = loop.replay.checkpoint_ticks.size()
		var pending: bool = _pending(world)
		loop.step(world, queued)
		var cells: int = world.stats[World.Stat.FLOW_CELLS]
		total += cells
		var label: String = "step from tick %d" % tick
		if loop.replay.checkpoint_ticks.size() > checkpoints:
			assert_int(cells).override_failure_message(label).is_equal(0)
			assert_int(loop.replay.checkpoint_ticks[-1]).is_equal(world.tick)
			checkpoint_steps_pending += 1 if pending else 0
		elif pending:
			pending_steps += 1
			full_steps += 1 if cells == BUDGET else 0
			assert_int(cells).override_failure_message(label).is_between(1, BUDGET)
			if cells < BUDGET:
				finished_at = tick
		elif tick > 100:
			assert_int(cells).override_failure_message(label).is_equal(0)
	assert_int(checkpoint_steps_pending).is_equal(4)
	assert_int(pending_steps).is_greater(50)
	assert_int(full_steps).is_equal(pending_steps - 1)
	assert_int(finished_at).is_greater(50)
	assert_int(total).is_equal(reachable)
	assert_bool(world.flow.field(0).complete).is_true()
	assert_int(loop.replay.checkpoint_ticks.size()).is_equal(10)


## The budget Sim.step hands to the FLOW phase, seen by a kernel spy standing where the library
## would: `flow_cells_per_tick` on every step, and 0 on the steps that MatchLoop follows with a
## checkpoint, whose tick (the tick after the step) is a multiple of the period. No units needed.
func test_the_budget_is_zero_exactly_when_the_tick_after_the_step_is_a_multiple_of_the_period(
) -> void:
	var world: World = _wall_world(SimImpls.Impl.GDSCRIPT)
	var spy: RefCounted = KernelSpy.new()
	world.kernels = spy
	world.native_phases = 1 << SimProbe.Phase.FLOW
	world.flow_cells_per_tick = BUDGET
	var expected: Array[String] = []
	for tick: int in 60:
		Sim.step(world, [])
		var hashed: bool = (tick + 1) % Replay.CHECKPOINT_PERIOD == 0
		expected.append("flow:0" if hashed else "flow:%d" % BUDGET)
	assert_array(spy.calls).is_equal(expected)
	assert_int(expected.count("flow:0")).is_equal(4)


func _pending(world: World) -> bool:
	var field: FlowField = world.flow.field(0)
	return world.flow.status[0] == FlowCache.Status.WAITING or field.pending > 0


## 40 x 40 grass with rock in tile column 20 except rows 30 to 33, and one tank at (3500, 5500).
func _wall_world(impl: int) -> World:
	var rock: Array[Vector2i] = []
	for row: int in ROWS:
		if row < 30 or row > 33:
			rock.append(Vector2i(20, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(COLS, ROWS, rock)), impl)
	world.add_unit(1, 0, 3500, 5500)
	return world


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and INTEGRATE in the implementation asked for.
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	return world
