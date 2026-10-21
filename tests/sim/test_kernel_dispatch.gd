extends GdUnitTestSuite
## The dispatch harness of ADR 0013 section 3 (plan P54). A World's `kernels` is an untyped Object
## and `native_phases` has one bit per SimProbe.Phase; a phase entry that finds its bit set calls
## the method of its phase on the kernels and skips the GDScript rule. A KernelSpy takes the place
## of the library here, so these cases need no build. P54 has the mask-0 case; a port PR adds one
## case that sets its bit and asserts exactly its spy call (FLOW since P30n, INTEGRATE since P37n,
## SEPARATION since P39n, TARGETING since P41n, FOG since P46n).

const KernelSpy: GDScript = preload("res://tests/sim/support/kernel_spy.gd")
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const TICKS: int = 30


func test_the_spy_records_each_kernel_call_in_order_with_its_budget() -> void:
	var spy: RefCounted = KernelSpy.new()
	spy.flow(null, 512)
	spy.separation(null)
	spy.integrate(null)
	spy.targeting(null)
	spy.fog(null)
	spy.flow(null, 0)
	var expected: Array[String] = [
		"flow:512", "separation", "integrate", "targeting", "fog", "flow:0"
	]
	assert_array(spy.calls).is_equal(expected)


func test_a_zero_mask_calls_no_kernel_while_the_tick_runs_every_phase_in_gdscript() -> void:
	var spy: RefCounted = KernelSpy.new()
	var world: World = _moving_world(spy, 0)
	var start_x: int = world.pos_x[0]
	_run(world)
	assert_array(spy.calls).is_empty()
	assert_int(world.tick).is_equal(TICKS)
	assert_int(world.pos_x[0]).is_not_equal(start_x)  # The tick did move the unit.


## FLOW (P30n): FlowCache.run starts with the dispatch. With its bit set it calls the kernel once
## with the budget and does nothing else; with the other four bits it runs the GDScript phase.
func test_flow_run_calls_the_flow_kernel_once_and_skips_the_gdscript_phase() -> void:
	var spy: RefCounted = KernelSpy.new()
	var world: World = _moving_world(spy, 1 << SimProbe.Phase.FLOW)
	world.flow.acquire(0, 0, world.map_version, 1)
	world.field[0] = 0
	world.field[1] = 0
	FlowCache.run(world, 7)
	FlowCache.run(world, 0)
	# The first call is the FLOW line of the tick `_moving_world` ran (P37b): `Sim.step` passes
	# `flow_cells_per_tick` (512) on a tick that MatchLoop does not hash.
	assert_array(spy.calls).is_equal(["flow:512", "flow:7", "flow:0"])
	# Untouched: the acquire() reference is not recounted (2 rows) and the field is still WAITING.
	assert_array([world.flow.refs(0), world.flow.status[0]]).is_equal([1, 1])
	world.native_phases = 0x46A & ~(1 << SimProbe.Phase.FLOW)  # The other four phases of ADR 0013.
	FlowCache.run(world, 7)
	assert_array(spy.calls).is_equal(["flow:512", "flow:7", "flow:0"])
	assert_array([world.flow.refs(0), world.stats[World.Stat.FLOW_CELLS]]).is_equal([2, 7])


## INTEGRATE (P37n): Movement.integrate starts with the dispatch. With its bit set it calls the
## kernel once and does nothing else (the unit that Movement.run gave an intent stays where it is);
## with the other four bits it runs the GDScript phase.
func test_integrate_calls_the_integrate_kernel_once_and_skips_the_gdscript_phase() -> void:
	var spy: RefCounted = KernelSpy.new()
	var world: World = _moving_world(spy, 1 << SimProbe.Phase.INTEGRATE)
	# The first call is the INTEGRATE line of the tick `_moving_world` ran; the order was queued
	# for tick 0, so Movement.run had given the tanks an intent, which nothing integrated.
	assert_array(spy.calls).is_equal(["integrate"])
	assert_int(world.intent_x[0] + world.intent_y[0]).is_not_equal(0)
	var start: Vector2i = Vector2i(world.pos_x[0], world.pos_y[0])
	Movement.integrate(world)
	assert_array(spy.calls).is_equal(["integrate", "integrate"])
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([start.x, start.y])
	# The other four phases of ADR 0013.
	world.native_phases = 0x46A & ~(1 << SimProbe.Phase.INTEGRATE)
	Movement.integrate(world)
	assert_array(spy.calls).is_equal(["integrate", "integrate"])
	assert_array([world.pos_x[0], world.pos_y[0]]).is_not_equal([start.x, start.y])


## SEPARATION (P39n): Separation.run starts with the dispatch. With its bit set it calls the kernel
## once and does nothing else (the pushes the GDScript phase wrote stay what they were, even
## though two tanks on one point were there to be pushed); with the other four bits it runs the
## GDScript phase.
func test_separation_calls_the_separation_kernel_once_and_skips_the_gdscript_phase() -> void:
	var spy: RefCounted = KernelSpy.new()
	var world: World = _moving_world(spy, 1 << SimProbe.Phase.SEPARATION)
	# The first call is the SEPARATION line of the tick `_moving_world` ran.
	assert_array(spy.calls).is_equal(["separation"])
	world.pos_x[1] = world.pos_x[0]
	world.pos_y[1] = world.pos_y[0]
	world.sep_grid.rebuild(world.pos_x, world.pos_y, world.unit_count())
	world.push_x.fill(7)
	world.stats[World.Stat.SEP_PAIRS] = 0
	Separation.run(world)
	assert_array(spy.calls).is_equal(["separation", "separation"])
	assert_array([world.push_x[0], world.push_x[1], world.stats[World.Stat.SEP_PAIRS]]).is_equal(
		[7, 7, 0]
	)
	# The other four phases of ADR 0013.
	world.native_phases = 0x46A & ~(1 << SimProbe.Phase.SEPARATION)
	Separation.run(world)
	assert_array(spy.calls).is_equal(["separation", "separation"])
	assert_array([world.push_x[0], world.push_x[1]]).is_not_equal([7, 7])
	assert_int(world.stats[World.Stat.SEP_PAIRS]).is_greater(1)


## TARGETING (P41n): Targeting.run starts with the dispatch, and the one call covers acquisition and
## engagement. With its bit set it calls the kernel once and does nothing else (a MOVE row, whose
## target the GDScript phase clears on every tick, keeps the target written by hand); with the other
## four bits it runs the GDScript phase and clears it.
func test_targeting_calls_the_targeting_kernel_once_and_skips_the_gdscript_phase() -> void:
	var spy: RefCounted = KernelSpy.new()
	var world: World = _moving_world(spy, 1 << SimProbe.Phase.TARGETING)
	# The first call is the TARGETING line of the tick `_moving_world` ran.
	assert_array(spy.calls).is_equal(["targeting"])
	world.order[0] = World.Order.MOVE
	world.target[0] = 7
	world.stats[World.Stat.LINE_CHECKS] = 0
	Targeting.run(world)
	assert_array(spy.calls).is_equal(["targeting", "targeting"])
	assert_array([world.target[0], world.stats[World.Stat.TARGET_CANDIDATES]]).is_equal([7, 0])
	# The other four phases of ADR 0013.
	world.native_phases = 0x46A & ~(1 << SimProbe.Phase.TARGETING)
	Targeting.run(world)
	assert_array(spy.calls).is_equal(["targeting", "targeting"])
	assert_int(world.target[0]).is_equal(0)


## FOG (P46n): FogUpdate.run starts with the dispatch. With its bit set it calls the kernel once and
## does nothing else (the unit that moved a tile keeps the cell it was stamped at); with the other
## four bits it runs the GDScript phase and stamps the new cell. FogUpdate.begin has no dispatch
## and runs with the bit set (it empties the dirty list of the player whose turn it is).
func test_fog_calls_the_fog_kernel_once_and_skips_the_gdscript_phase() -> void:
	var spy: RefCounted = KernelSpy.new()
	var world: World = _moving_world(spy, 1 << SimProbe.Phase.FOG)
	# The first call is the FOG line of the tick `_moving_world` ran.
	assert_array(spy.calls).is_equal(["fog"])
	var stamped: int = world.fog_cell[0]
	world.pos_x[0] += 3000
	world.tick = 3  # Player 1's turn again.
	world.fog.dirty_count[0] = 5
	world.stats[World.Stat.FOG_CELLS] = 0
	FogUpdate.begin(world)
	assert_int(world.fog.dirty_count[0]).is_equal(0)
	FogUpdate.run(world)
	assert_array(spy.calls).is_equal(["fog", "fog"])
	assert_array([world.fog_cell[0], world.stats[World.Stat.FOG_CELLS]]).is_equal([stamped, 0])
	# The other four phases of ADR 0013.
	world.native_phases = 0x46A & ~(1 << SimProbe.Phase.FOG)
	FogUpdate.run(world)
	assert_array(spy.calls).is_equal(["fog", "fog"])
	assert_int(world.fog_cell[0]).is_not_equal(stamped)
	assert_int(world.stats[World.Stat.FOG_CELLS]).is_greater(0)


## The controls scenario with `kernels` and `mask` attached after prepare(), and an attack-move
## order for three tanks queued for tick 0.
func _moving_world(kernels: Object, mask: int) -> World:
	var world: World = World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)
	world.kernels = kernels
	world.native_phases = mask
	var order: Command = Command.attack_move(1, PackedInt32Array([1, 2, 3]), 30000, 30000)
	order.tick = 0
	Sim.step(world, [order])
	return world


## Steps `world` `ticks` more ticks (all of TICKS minus the first, by default).
func _run(world: World, ticks: int = TICKS - 1) -> void:
	for _t: int in ticks:
		Sim.step(world, [])
