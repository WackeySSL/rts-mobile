extends GdUnitTestSuite
## Separation in the tick (P39b; ADR 0007 section 4, ADR 0008 section 4), through Sim.step. The
## pushes themselves are pinned in test_separation.gd, test_separation_edges.gd and
## test_separation_signs.gd; this suite pins what the tick does with them: the GRIDS rebuild comes
## after FLOW and `Separation.run` after INTENTS and before INTEGRATE (the pushes use this tick's
## intents and move this tick's units), and crowds that cross, drive into other units or turn back
## settle idle with no pair closer than 90% of the radii sum (720 milli for two tanks). The crowds
## are the controls_test scenario: 30 blue tanks (ids 1 to 30) at (8000, 18500) in six columns 1500
## apart, 10 red tanks (ids 31 to 40) far to the east. The tick counts are measured and rounded up
## to a multiple of 15.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const ViewProbe: GDScript = preload("res://tests/sim/support/separation_view_probe.gd")
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
## 90% of the radii sum.
const APART_PERCENT: int = 90
## Two groups of 15 whose paths cross: the north half of the block is sent south of the point, the
## south half north of it, 2000 apart, so the two destinations overlap and the groups drive through
## each other. All idle at tick 178.
const NORTH_TARGET: Vector2i = Vector2i(26000, 24500)
const SOUTH_TARGET: Vector2i = Vector2i(26000, 22500)
const CROSSING_TICKS: int = 180
## The controls_test tap-ground order of test_controls_flow (30 tanks to the point, 450 ticks) and
## the Phase 1 bound on how far a tank may stand from it (the nearest 30 slots of a 1200 lattice
## reach 3795). Measured maximum with separation: 3795.
const TAP_POINT: Vector2i = Vector2i(20016, 21516)
const TAP_TICKS: int = 450
const TAP_CENTRE_BOUND: int = 3800
## The block driven into the red group (all idle at tick 279), and out and back again through
## itself (the turn at tick 200, all idle at tick 378).
const RED_POINT: Vector2i = Vector2i(34500, 10500)
const RED_TICKS: int = 285
const OUT_POINT: Vector2i = Vector2i(26000, 22000)
const BACK_POINT: Vector2i = Vector2i(12000, 22000)
const TURN_TICK: int = 200
const BACK_TICKS: int = 390
## How far a tank of a group of 15 stands from its point at most (measured 3003).
const GROUP_CENTRE_BOUND: int = 3400


## Row 0 is a tank sent east and row 1 an idle tank 300 ahead of it (overlapping, so the pair is
## pushed). The marks of the one tick show the order of the phases: the grid holds a row only from
## GRIDS on; the pushes appear at SEPARATION, with the intent that INTENTS wrote this tick (the
## mover takes 25% of the pair push of 128, -32, the idle tank 75%, 96, cut to the 60 a unit may
## take; with the intents of the tick before, both idle, the mover would take -60); the positions
## move at INTEGRATE only, by intent plus push.
func test_the_grid_is_rebuilt_after_flow_and_the_pushes_use_this_ticks_intents() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(10, 6))
	world.add_unit(1, 0, 5000, 3000)
	world.add_unit(1, 0, 5300, 3000)
	var probe: ViewProbe = ViewProbe.new(world)
	var order: Command = Command.move(1, PackedInt32Array([1]), 9000, 3000)
	order.tick = world.tick
	Sim.step(world, [order], probe)
	var phases: Array[int] = [SimProbe.Phase.COMMANDS, SimProbe.Phase.FLOW, SimProbe.Phase.GRIDS]
	phases.append_array([SimProbe.Phase.INTENTS, SimProbe.Phase.SEPARATION])
	phases.append_array([SimProbe.Phase.INTEGRATE, SimProbe.Phase.REMOVE])
	assert_array(probe.phases).is_equal(phases)
	assert_array(probe.occupied).is_equal([0, 0, 1, 1, 1, 1, 1])
	var none: Vector2i = Vector2i.ZERO
	var pushed: Vector2i = Vector2i(-32, 60)
	assert_array(probe.pushes).is_equal([none, none, none, none, pushed, pushed, pushed])
	assert_array(probe.intents).is_equal([0, 0, 0, 120, 120, 120, 120])
	var start: Vector2i = Vector2i(5000, 5300)
	var moved: Vector2i = Vector2i(5000 + 120 - 32, 5300 + 60)
	assert_array(probe.positions).is_equal([start, start, start, start, start, moved, moved])
	assert_array(probe.pairs).is_equal([0, 0, 0, 0, 2, 2, 2])


## The grid is rebuilt every tick from where the units are then: a tank that drives up to an idle
## one from the other end of the map is found in its new cell, shoves the idle tank aside (the
## idle tank takes 75% of the push) and ends idle at least 720 apart, where a grid built once, at
## the first tick, would leave the two on one point.
func test_a_tank_that_drives_up_to_an_idle_one_is_pushed_off_it() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(12, 6))
	world.add_unit(1, 0, 2000, 3000)
	world.add_unit(1, 0, 8000, 3000)
	var order: Command = Command.move(1, PackedInt32Array([1]), 8000, 3000)
	order.tick = world.tick
	var commands: Array[Command] = [order]
	var pushed_on_the_way: bool = false
	for _tick: int in 120:
		Sim.step(world, commands)
		commands.clear()
		pushed_on_the_way = pushed_on_the_way or world.pos_x[1] != 8000
	assert_bool(pushed_on_the_way).is_true()
	assert_array(world.order).is_equal([World.Order.IDLE, World.Order.IDLE])
	assert_array(Rig.pairs_closer_than(world, APART_PERCENT)).is_empty()
	assert_int(Rig.distance2(world, 0, 1)).is_less_equal(800 * 800)


## Two groups of 15 on crossing paths: after both settle idle, no pair of the 40 units is closer
## than 90% of the radii sum. The groups really met on the way (a tank of one overlapped a tank of
## the other) and the tick counted the pairs it looked at.
func test_two_groups_of_15_on_crossing_paths_settle_with_no_pair_under_90_percent() -> void:
	var world: World = _scenario_world()
	var commands: Array[Command] = _crossing_orders(world)
	var met: bool = false
	var most_pairs: int = 0
	for _tick: int in CROSSING_TICKS:
		Sim.step(world, commands)
		commands.clear()
		most_pairs = maxi(most_pairs, world.stats[World.Stat.SEP_PAIRS])
		met = met or _groups_overlap(world)
	assert_bool(met).is_true()
	assert_int(most_pairs).is_greater(0)
	assert_int(world.tick).is_equal(CROSSING_TICKS)
	assert_int(world.order.count(World.Order.IDLE)).is_equal(40)
	assert_array(Rig.pairs_closer_than(world, APART_PERCENT)).is_empty()
	for row: int in 30:
		var point: Vector2i = NORTH_TARGET if row < 15 else SOUTH_TARGET
		var gap: Vector2i = Vector2i(world.pos_x[row] - point.x, world.pos_y[row] - point.y)
		(
			assert_int(gap.x * gap.x + gap.y * gap.y)
			. override_failure_message("tank %d" % (row + 1))
			. is_less(GROUP_CENTRE_BOUND * GROUP_CENTRE_BOUND)
		)


## The tap-ground order of test_controls_flow through Sim.step: 30 tanks to (20016, 21516), 450
## ticks. All idle, every pair at least 90% of the radii sum apart, every tank within the Phase 1
## centre bound of the point, and the red tanks, far away, where they were.
func test_the_controls_tap_ground_order_settles_apart_and_within_the_centre_bound() -> void:
	var world: World = _scenario_world()
	var order: Command = Command.attack_move(1, _ids(1, 30), TAP_POINT.x, TAP_POINT.y)
	order.tick = world.tick
	var commands: Array[Command] = [order]
	for _tick: int in TAP_TICKS:
		Sim.step(world, commands)
		commands.clear()
	assert_int(world.tick).is_equal(TAP_TICKS)
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.order.count(World.Order.IDLE)).is_equal(40)
	assert_array(Rig.pairs_closer_than(world, APART_PERCENT)).is_empty()
	for row: int in 30:
		var gap: Vector2i = Vector2i(world.pos_x[row] - TAP_POINT.x, world.pos_y[row] - TAP_POINT.y)
		(
			assert_int(gap.x * gap.x + gap.y * gap.y)
			. override_failure_message("tank %d" % (row + 1))
			. is_less(TAP_CENTRE_BOUND * TAP_CENTRE_BOUND)
		)
	var scenario: World = _scenario_world()
	assert_array(world.pos_x.slice(30, 35)).is_equal(scenario.pos_x.slice(30, 35))


## The block driven into the red group: the red tanks are shoved aside (idle ones take 75% of a
## push against a mover) and everything ends idle with no pair of the 40 closer than 90%.
func test_driving_into_the_red_group_shoves_it_aside_and_nobody_overlaps() -> void:
	var world: World = _scenario_world()
	var red_before: PackedInt32Array = world.pos_x.slice(30) + world.pos_y.slice(30)
	var order: Command = Command.attack_move(1, _ids(1, 30), RED_POINT.x, RED_POINT.y)
	order.tick = world.tick
	var commands: Array[Command] = [order]
	for _tick: int in RED_TICKS:
		Sim.step(world, commands)
		commands.clear()
	assert_int(world.order.count(World.Order.IDLE)).is_equal(40)
	assert_array(Rig.pairs_closer_than(world, APART_PERCENT)).is_empty()
	assert_bool(world.pos_x.slice(30) + world.pos_y.slice(30) == red_before).is_false()


## The block sent east and, at tick 200, back through where it stood: the tanks drive through each
## other twice and still end idle, apart.
func test_turning_the_block_back_through_itself_ends_apart() -> void:
	var world: World = _scenario_world()
	var out: Command = Command.attack_move(1, _ids(1, 30), OUT_POINT.x, OUT_POINT.y)
	out.tick = world.tick
	var commands: Array[Command] = [out]
	for tick: int in BACK_TICKS:
		if tick == TURN_TICK:
			var back: Command = Command.attack_move(1, _ids(1, 30), BACK_POINT.x, BACK_POINT.y)
			back.tick = world.tick
			commands.append(back)
		Sim.step(world, commands)
		commands.clear()
	assert_int(world.order.count(World.Order.IDLE)).is_equal(40)
	assert_array(Rig.pairs_closer_than(world, APART_PERCENT)).is_empty()
	var home: Vector2i = Vector2i(world.pos_x[0] - BACK_POINT.x, world.pos_y[0] - BACK_POINT.y)
	assert_int(home.x * home.x + home.y * home.y).is_less(GROUP_CENTRE_BOUND * GROUP_CENTRE_BOUND)


## Two runs of the crossing groups give the same state hash at every checkpoint tick (every 15
## ticks), and the hashes are not the ones of a run without pushes: separation is part of the state.
func test_two_runs_give_the_same_hashes() -> void:
	var first: PackedInt64Array = _crossing_hashes(-1)
	var second: PackedInt64Array = _crossing_hashes(-1)
	assert_int(first.size()).is_equal(12)  # Every 15th tick of 180.
	assert_array(second).is_equal(first)
	var still: PackedInt64Array = _crossing_hashes(0)
	assert_array(still).is_not_equal(first)
	assert_int(still[-1]).is_not_equal(first[-1])


## The crossing run's state hash after each 15th tick; with `push_max` of 0 or more the world's
## `separation_push_max` is set to it first (0: no pushes).
func _crossing_hashes(push_max: int) -> PackedInt64Array:
	var world: World = _scenario_world()
	if push_max >= 0:
		world.separation_push_max = push_max
	var commands: Array[Command] = _crossing_orders(world)
	var hashes: PackedInt64Array = PackedInt64Array()
	for _tick: int in CROSSING_TICKS:
		Sim.step(world, commands)
		commands.clear()
		if world.tick % 15 == 0:
			hashes.append(world.state_hash())
	return hashes


## The two orders of the crossing groups for tick `world.tick`: the north half of the block (ids 1
## to 15) south of the point, the south half (ids 16 to 30) north of it.
func _crossing_orders(world: World) -> Array[Command]:
	var north: Command = Command.attack_move(1, _ids(1, 15), NORTH_TARGET.x, NORTH_TARGET.y)
	var south: Command = Command.attack_move(1, _ids(16, 30), SOUTH_TARGET.x, SOUTH_TARGET.y)
	north.tick = world.tick
	south.tick = world.tick
	south.sequence = 1
	var orders: Array[Command] = [north, south]
	return orders


## Whether a tank of the north half (rows 0 to 14) overlaps one of the south half (rows 15 to 29).
func _groups_overlap(world: World) -> bool:
	for a: int in range(0, 15):
		for b: int in range(15, 30):
			if Rig.distance2(world, a, b) < 800 * 800:
				return true
	return false


func _ids(first: int, last: int) -> PackedInt32Array:
	return PackedInt32Array(range(first, last + 1))


func _scenario_world() -> World:
	return World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)
