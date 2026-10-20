extends GdUnitTestSuite
## Separation in the tick (P39b; ADR 0007 section 4, ADR 0008 section 4), through Sim.step. The
## pushes themselves are pinned in test_separation.gd, test_separation_edges.gd and
## test_separation_signs.gd; this suite pins what the tick does with them: the GRIDS rebuild comes
## after FLOW (P41's TARGETING follows it) and `Separation.run` after INTENTS and before INTEGRATE
## (the pushes use this tick's intents and move this tick's units), and crowds that cross, drive
## into other units or turn back settle idle with no pair closer than 90% of the radii sum (720
## milli for two tanks). The crowds are the controls_test scenario: 30 blue tanks (ids 1 to 30) at
## (8000, 18500) in six columns 1500 apart, 10 red tanks (ids 31 to 40) far to the east. The tick
## counts are measured and rounded up to a multiple of 15.
##
## Separation does not stop tanks from overlapping while they drive. A push is at most 60 milli a
## tick, half a tank's speed of 120 (ADR 0008 section 4), so tanks on crossing paths still slide
## through one another for a while and settle apart afterwards. The cases bound how long a pair
## stays closer than 90% of the radii sum (MAX_OVERLAP_TICKS) and count the pairs the tick looked
## at (SEP_PAIRS), so a tick without the rebuild or without `Separation.run` fails them, even where
## the formation slots alone would end apart.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Rig: GDScript = preload("res://tests/sim/support/separation_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const ViewProbe: GDScript = preload("res://tests/sim/support/separation_view_probe.gd")
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
## 90% of the radii sum.
const APART_PERCENT: int = 90
## The most ticks in a row that a pair of the 40 units may stand closer than 90% of the radii sum
## while the crowds drive (3 s). Measured at most 34 ticks (2.3 s) with the pushes of the tick,
## 47 to 123 ticks without them (separation_push_max = 0).
const MAX_OVERLAP_TICKS: int = 45
## The radii sum of two tanks: closer than this they overlap.
const REACH: int = 800
## The ATTACK case: the target is the first red tank (id 31, row 30) at (34500, 10500), 600 ticks.
## The tank's sight is raised above the 27,700 milli between the two, so that the vision check of
## the fog PR (P46b) leaves the case green (its authoring rule).
const ATTACK_TARGET_ID: int = 31
const ATTACK_TICKS: int = 600
const ATTACK_SIGHT: int = 30000
## P42a: the pair fire at each other for the 600 ticks (18 damage a shot, 25 ticks apart), and a
## tank has 300 hp, so one would die before the end. The hp is raised so that nothing dies here and
## the case stays about the pushes; the deaths are test_combat's.
const ATTACK_HP: int = 1000000
## A `retarget_period_ticks` that no tick of a test reaches: nobody scans.
const NEVER_DUE: int = 1000000
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
## move at INTEGRATE only, by intent plus push. P41's TARGETING mark sits between GRIDS and INTENTS
## and changes none of the columns.
func test_the_grid_is_rebuilt_after_flow_and_the_pushes_use_this_ticks_intents(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 6)), impl)
	world.add_unit(1, 0, 5000, 3000)
	world.add_unit(1, 0, 5300, 3000)
	var probe: ViewProbe = ViewProbe.new(world)
	var order: Command = Command.move(1, PackedInt32Array([1]), 9000, 3000)
	order.tick = world.tick
	Sim.step(world, [order], probe)
	var phases: Array[int] = [SimProbe.Phase.COMMANDS, SimProbe.Phase.FLOW, SimProbe.Phase.GRIDS]
	phases.append_array([SimProbe.Phase.TARGETING, SimProbe.Phase.INTENTS])
	phases.append(SimProbe.Phase.SEPARATION)
	phases.append_array([SimProbe.Phase.INTEGRATE, SimProbe.Phase.PROJECTILES])
	phases.append_array([SimProbe.Phase.FIRE, SimProbe.Phase.REMOVE, SimProbe.Phase.FOG])
	assert_array(probe.phases).is_equal(phases)
	assert_array(probe.occupied).is_equal([0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	var none: Vector2i = Vector2i.ZERO
	var pushed: Vector2i = Vector2i(-32, 60)
	var pushes: Array[Vector2i] = [none, none, none, none, none, pushed, pushed, pushed, pushed]
	pushes.append_array([pushed, pushed])
	assert_array(probe.pushes).is_equal(pushes)
	assert_array(probe.intents).is_equal([0, 0, 0, 0, 120, 120, 120, 120, 120, 120, 120])
	var start: Vector2i = Vector2i(5000, 5300)
	var moved: Vector2i = Vector2i(5000 + 120 - 32, 5300 + 60)
	var positions: Array[Vector2i] = [start, start, start, start, start, start, moved, moved, moved]
	positions.append_array([moved, moved])
	assert_array(probe.positions).is_equal(positions)
	assert_array(probe.pairs).is_equal([0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2])


## The grid is rebuilt every tick from where the units are then: a tank that drives up to an idle
## one from the other end of the map is found in its new cell, shoves the idle tank aside (the
## idle tank takes 75% of the push) and ends idle at least 720 apart, where a grid built once, at
## the first tick, would leave the two on one point.
func test_a_tank_that_drives_up_to_an_idle_one_is_pushed_off_it(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(12, 6)), impl)
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
	assert_int(Rig.distance2(world, 0, 1)).is_less_equal(REACH * REACH)


## Two groups of 15 on crossing paths: after both settle idle, no pair of the 40 units is closer
## than 90% of the radii sum. The groups really met on the way (a tank of one overlapped a tank of
## the other), no pair stayed overlapped for more than MAX_OVERLAP_TICKS in a row, and the tick
## counted the pairs it looked at.
func test_two_groups_of_15_on_crossing_paths_settle_with_no_pair_under_90_percent(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _scenario_world(impl)
	var commands: Array[Command] = _crossing_orders(world)
	var met: bool = false
	var most_pairs: int = 0
	var longest: int = 0
	var runs: PackedInt32Array = _overlap_runs()
	for _tick: int in CROSSING_TICKS:
		Sim.step(world, commands)
		commands.clear()
		most_pairs = maxi(most_pairs, world.stats[World.Stat.SEP_PAIRS])
		met = met or _groups_overlap(world)
		longest = maxi(longest, Rig.track_overlaps(world, APART_PERCENT, runs))
	assert_bool(met).is_true()
	assert_int(most_pairs).is_greater(0)
	assert_int(longest).is_less_equal(MAX_OVERLAP_TICKS)
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
## centre bound of the point, and the red tanks, far away, where they were. The formation slots
## are 1200 apart, so the end state alone would hold without separation (the tanks drive up to
## their slots through one another and stand 322 milli apart at the closest, tick 92): the tick
## must have looked at pairs (SEP_PAIRS) and no pair may have stayed overlapped for long.
func test_the_controls_tap_ground_order_settles_apart_and_within_the_centre_bound(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _scenario_world(impl)
	var order: Command = Command.attack_move(1, _ids(1, 30), TAP_POINT.x, TAP_POINT.y)
	order.tick = world.tick
	var commands: Array[Command] = [order]
	var most_pairs: int = 0
	var longest: int = 0
	var runs: PackedInt32Array = _overlap_runs()
	for _tick: int in TAP_TICKS:
		Sim.step(world, commands)
		commands.clear()
		most_pairs = maxi(most_pairs, world.stats[World.Stat.SEP_PAIRS])
		longest = maxi(longest, Rig.track_overlaps(world, APART_PERCENT, runs))
	assert_int(most_pairs).is_greater(0)
	assert_int(longest).is_less_equal(MAX_OVERLAP_TICKS)
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
	var scenario: World = _scenario_world(impl)
	assert_array(world.pos_x.slice(30, 35)).is_equal(scenario.pos_x.slice(30, 35))


## The block driven into the red group: the red tanks are shoved aside (idle ones take 75% of a
## push against a mover), no pair stays overlapped for more than MAX_OVERLAP_TICKS in a row, and
## everything ends idle with no pair of the 40 closer than 90%. Acquisition is off (a retarget
## period that no tick reaches): since P41b an attack-moving tank stops at weapon range of the
## enemy it meets, so with targeting on the block would hold short of the red group and never push
## it, and this case is about the crowd driving through.
func test_driving_into_the_red_group_shoves_it_aside_and_ends_with_nobody_overlapping(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _scenario_world(impl)
	world.retarget_period_ticks = NEVER_DUE
	var red_before: PackedInt32Array = world.pos_x.slice(30) + world.pos_y.slice(30)
	var order: Command = Command.attack_move(1, _ids(1, 30), RED_POINT.x, RED_POINT.y)
	order.tick = world.tick
	var commands: Array[Command] = [order]
	var longest: int = 0
	var runs: PackedInt32Array = _overlap_runs()
	for _tick: int in RED_TICKS:
		Sim.step(world, commands)
		commands.clear()
		longest = maxi(longest, Rig.track_overlaps(world, APART_PERCENT, runs))
	assert_int(longest).is_less_equal(MAX_OVERLAP_TICKS)
	assert_int(world.order.count(World.Order.IDLE)).is_equal(40)
	assert_array(Rig.pairs_closer_than(world, APART_PERCENT)).is_empty()
	assert_bool(world.pos_x.slice(30) + world.pos_y.slice(30) == red_before).is_false()


## The block sent east and, at tick 200, back through where it stood: the tanks drive through each
## other twice and still end idle, apart. Some pair really overlaps after the turn (the block did
## drive through itself), the tick looked at pairs, and no pair stayed overlapped for long; the
## formation slots are 1200 apart, so only these checks tell a tick with separation from one
## without (it ends 798 at the closest with the pushes, 1200 without).
func test_turning_the_block_back_through_itself_ends_apart(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _scenario_world(impl)
	var out: Command = Command.attack_move(1, _ids(1, 30), OUT_POINT.x, OUT_POINT.y)
	out.tick = world.tick
	var commands: Array[Command] = [out]
	var met_after_the_turn: bool = false
	var most_pairs: int = 0
	var longest: int = 0
	var runs: PackedInt32Array = _overlap_runs()
	for tick: int in BACK_TICKS:
		if tick == TURN_TICK:
			var back: Command = Command.attack_move(1, _ids(1, 30), BACK_POINT.x, BACK_POINT.y)
			back.tick = world.tick
			commands.append(back)
		Sim.step(world, commands)
		commands.clear()
		most_pairs = maxi(most_pairs, world.stats[World.Stat.SEP_PAIRS])
		longest = maxi(longest, Rig.track_overlaps(world, APART_PERCENT, runs))
		if tick >= TURN_TICK:
			met_after_the_turn = (
				met_after_the_turn or not Rig.pairs_closer_than(world, 100).is_empty()
			)
	assert_bool(met_after_the_turn).is_true()
	assert_int(most_pairs).is_greater(0)
	assert_int(longest).is_less_equal(MAX_OVERLAP_TICKS)
	assert_int(world.order.count(World.Order.IDLE)).is_equal(40)
	assert_array(Rig.pairs_closer_than(world, APART_PERCENT)).is_empty()
	var home: Vector2i = Vector2i(world.pos_x[0] - BACK_POINT.x, world.pos_y[0] - BACK_POINT.y)
	assert_int(home.x * home.x + home.y * home.y).is_less(GROUP_CENTRE_BOUND * GROUP_CENTRE_BOUND)


## The step before a checkpoint is a step like any other for the grid and the pushes. MatchLoop
## hashes after the Sim.step that starts at tick 14 (Replay.CHECKPOINT_PERIOD is 15) and FLOW takes
## no slice on it; a rebuild or `Separation.run` that copied that guard would leave a pair that
## overlaps on that tick unpushed. Two overlapping idle tanks move the same on tick 14 as on tick 0.
func test_the_step_before_a_checkpoint_rebuilds_the_grid_and_pushes_like_any_other(
	impl: int, _test_parameters := _both()
) -> void:
	var by_tick: Array[World] = []
	for start_tick: int in [0, Replay.CHECKPOINT_PERIOD - 1]:
		var world: World = _in(GridWorld.from_rows(GridWorld.grass(10, 6)), impl)
		world.add_unit(1, 0, 5000, 3000)
		world.add_unit(1, 0, 5300, 3000)
		world.tick = start_tick
		Sim.step(world, [])
		assert_int(world.tick).is_equal(start_tick + 1)
		assert_int(world.stats[World.Stat.SEP_PAIRS]).is_equal(2)
		assert_array([world.pos_x[0], world.pos_x[1]]).is_not_equal([5000, 5300])
		by_tick.append(world)
	assert_array(by_tick[1].pos_x).is_equal(by_tick[0].pos_x)
	assert_array(by_tick[1].pos_y).is_equal(by_tick[0].pos_y)


## An ATTACK order on an idle enemy (P41b): the attacker drives to the cannon's range of 4500 and
## holds there (`HOLD`, intent 0, still on its `ATTACK` order and target), and the idle target
## stays at (34500, 10500), holding too, with the pushes of the tick on and off alike: the pair
## never comes within the radii sum, so the attacker's pushes do not reach the target (the attacker
## itself is pushed a little on its way by the tanks of the block it starts in, so its end point
## differs between the two runs).
## Until P41b the attacker drove onto the target's point every tick (`Sim._follow_targets` set the
## goal there and Movement never ends ATTACK) and, with separation in the tick, each push of the
## pair moved the idle target by its 75% share, away from the attacker, tick after tick, until it
## was stuck in the corner (47999, 0) with the attacker on top of it, still on ATTACK: what a tap on
## an enemy did from P39b to P41b.
func test_an_attack_on_an_idle_tank_holds_at_weapon_range_and_does_not_shove_it(
	impl: int, _test_parameters := _both()
) -> void:
	var pushed: World = _attack_the_first_red_tank(-1, impl)
	var still: World = _attack_the_first_red_tank(0, impl)
	for world: World in [pushed, still]:
		assert_array([world.pos_x[30], world.pos_y[30]]).is_equal([34500, 10500])
		assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal(
			[World.Order.ATTACK, ATTACK_TARGET_ID, ATTACK_TARGET_ID]
		)
		assert_array([world.nav_mode[0], world.intent_x[0], world.intent_y[0]]).is_equal(
			[World.NavMode.HOLD, 0, 0]
		)
		assert_int(world.nav_mode[30]).is_equal(World.NavMode.HOLD)
		assert_int(Rig.distance2(world, 0, 30)).is_between(4380 * 4380, 4500 * 4500)


## Two runs of the crossing groups give the same state hash at every checkpoint tick (every 15
## ticks), and the hashes are not the ones of a run without pushes: separation is part of the state.
## The C++ run (the tick runs FLOW, TARGETING, SEPARATION and INTEGRATE in the kernels) has the
## hashes of the GDScript run, the whole 180 ticks through.
func test_two_runs_give_the_same_hashes(impl: int, _test_parameters := _both()) -> void:
	var first: PackedInt64Array = _crossing_hashes(-1, impl)
	var second: PackedInt64Array = _crossing_hashes(-1, impl)
	assert_int(first.size()).is_equal(12)  # Every 15th tick of 180.
	assert_array(second).is_equal(first)
	assert_array(_crossing_hashes(-1, SimImpls.Impl.GDSCRIPT)).is_equal(first)
	var still: PackedInt64Array = _crossing_hashes(0, impl)
	assert_array(still).is_not_equal(first)
	assert_int(still[-1]).is_not_equal(first[-1])


## The crossing run's state hash after each 15th tick; with `push_max` of 0 or more the world's
## `separation_push_max` is set to it first (0: no pushes).
func _crossing_hashes(push_max: int, impl: int) -> PackedInt64Array:
	var world: World = _scenario_world(impl)
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
			if Rig.distance2(world, a, b) < REACH * REACH:
				return true
	return false


## One counter per pair of the 40 units for Rig.track_overlaps, all 0.
func _overlap_runs() -> PackedInt32Array:
	var runs: PackedInt32Array = PackedInt32Array()
	runs.resize(40 * 40)
	return runs


## The scenario with the first blue tank (id 1) ordered to attack the first red tank (id 31, idle),
## after ATTACK_TICKS ticks; `push_max` of 0 or more is set as the world's `separation_push_max`
## first (0: no pushes).
func _attack_the_first_red_tank(push_max: int, impl: int) -> World:
	var world: World = _scenario_world(impl)
	world.type_sight.fill(ATTACK_SIGHT)
	world.hp.fill(ATTACK_HP)
	if push_max >= 0:
		world.separation_push_max = push_max
	var order: Command = Command.attack(1, _ids(1, 1), ATTACK_TARGET_ID)
	order.tick = world.tick
	var commands: Array[Command] = [order]
	for _tick: int in ATTACK_TICKS:
		Sim.step(world, commands)
		commands.clear()
	return world


func _ids(first: int, last: int) -> PackedInt32Array:
	return PackedInt32Array(range(first, last + 1))


func _scenario_world(impl: int) -> World:
	return _in(World.from_scenario(load(SCENARIO_PATH) as ScenarioDef), impl)


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and SEPARATION in the implementation asked for.
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.SEPARATION)).is_empty()
	return world
