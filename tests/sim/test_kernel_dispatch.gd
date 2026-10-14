extends GdUnitTestSuite
## The dispatch harness of ADR 0013 section 3 (plan P54). A World's `kernels` is an untyped Object
## and `native_phases` has one bit per SimProbe.Phase; a phase entry that finds its bit set calls
## the method of its phase on the kernels and skips the GDScript rule. A KernelSpy takes the place
## of the library here, so these cases need no build. P54 has the mask-0 case; a port PR adds one
## case that sets its bit and asserts exactly its spy call (FLOW since P30n; the other entries have
## no dispatch line yet).

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
	var world: World = _moving_world(spy, 1 << FlowCache.PHASE_FLOW)
	world.flow.acquire(0, 0, world.map_version, 1)
	world.field[0] = 0
	world.field[1] = 0
	FlowCache.run(world, 7)
	FlowCache.run(world, 0)
	assert_array(spy.calls).is_equal(["flow:7", "flow:0"])
	# Untouched: the acquire() reference is not recounted (2 rows) and the field is still WAITING.
	assert_array([world.flow.refs(0), world.flow.status[0]]).is_equal([1, 1])
	world.native_phases = 0x46A & ~(1 << FlowCache.PHASE_FLOW)  # The other four phases of ADR 0013.
	FlowCache.run(world, 7)
	assert_array(spy.calls).is_equal(["flow:7", "flow:0"])
	assert_array([world.flow.refs(0), world.stats[World.Stat.FLOW_CELLS]]).is_equal([2, 7])


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
