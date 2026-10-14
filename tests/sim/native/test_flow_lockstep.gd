extends GdUnitTestSuite
## The FLOW kernel against its GDScript twin (ADR 0013 section 4, plan P30n). Two Worlds are built
## from the seed-42 perf arena with slow, scrub and rock cells painted in. World A runs
## FlowCache.run in GDScript and World B in C++, through 900 ticks of the same scripted requests (12
## keys over 8 slots, units taking and leaving fields), terrain changes (re-integration) and odd
## budgets, and the full state is compared after every call. Then the same on maps that are not
## square (wide, then tall), where a mix-up of columns and rows shows, and a crafted map where one
## settled cell queues a diagonal and an orthogonal neighbour into the same bucket. That
## FlowCache.run hands the phase to the kernel at all is pinned by the spy case in
## tests/sim/test_kernel_dispatch.gd: without it this comparison would be GDScript against GDScript.

const FlowRig: GDScript = preload("res://tests/sim/support/flow_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const TICKS: int = 900
const SMALL_TICKS: int = 300
## Odd budgets, 0 (a checkpoint tick) and 509 (nearly the 512 of data/rules.tres).
const BUDGETS: Array[int] = [7, 61, 1, 127, 13, 0, 31, 509, 3, 97, 251, 63]
const KEYS: int = 12
## A group of units takes the field of the next key every REQUEST_EVERY ticks.
const REQUEST_EVERY: int = 30
const GROUPS: int = 10
const FOOT: int = World.MoveClass.FOOT
const TRACKED: int = World.MoveClass.TRACKED
const GROUP_ROWS: int = 5
## The cost of grass and of a terrain (1) that costs 14 for every class: a diagonal step onto grass
## costs 10 * 14 / 10 = 14 as well, so the scan order of the neighbours decides the bucket order.
const SCAN_COST: Array[int] = [10, 10, 10, 14, 14, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0]
## The ticks of a terrain change, which re-integrates the referenced fields.
const REPAINT_TICKS: Array[int] = [200, 450, 700]
## The cost of grass, slow sand (255 tracked, the cap of the bucket ring), scrub (foot only), rock
## and water for foot, wheeled and tracked, as World.terrain_cost holds them. Sand 12 and 41 and
## scrub 13 make a diagonal step of 16.8, 57.4 and 18.2: the integer division truncates, and a
## ceiling or a rounding half up shows.
const GROUND_COST: Array[int] = [10, 10, 10, 12, 41, 255, 13, 0, 0, 0, 0, 0, 0, 0, 0]


func test_900_arena_ticks_of_requests_terrain_changes_and_odd_budgets_match_gdscript() -> void:
	var run: Dictionary = _lockstep(_arena_scenario(null), TICKS)
	assert_str(run.diff).is_empty()
	# Not vacuous: whole fields were integrated and served, some re-integrated while still serving.
	assert_int(run.settled).is_between(40000, 200000)
	assert_int(run.served).is_greater(3)
	assert_int(run.again).is_greater(0)


func test_the_same_run_on_changed_rules_matches() -> void:
	var rules: RulesDef = _rules().duplicate() as RulesDef
	for info: Dictionary in rules.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and info["type"] == TYPE_INT:
			rules.set(info["name"], int(rules.get(info["name"])) + 3)
	rules.flow_cache_size = 5
	var run: Dictionary = _lockstep(_arena_scenario(rules), TICKS)
	assert_str(run.diff).is_empty()
	assert_int(run.settled).is_between(40000, 200000)


func test_maps_wider_and_taller_than_square_match() -> void:
	for size: Vector2i in [Vector2i(40, 24), Vector2i(24, 40)]:
		var run: Dictionary = _lockstep(_small_scenario(size), SMALL_TICKS)
		assert_str(run.diff).override_failure_message("%s" % size).is_empty()
		assert_int(run.settled).is_between(8000, 100000)


## A key whose goal is off the map, or whose class `move_cost` has no list for, completes at once
## with everything UNREACHED (the contract's key rule), and the same call goes on to the next field.
func test_keys_the_costs_cannot_integrate_match() -> void:
	var worlds: Array[World] = [_world(_arena_scenario(null)), _world(_arena_scenario(null))]
	assert_array(SimImpls.use(worlds[1], SimImpls.Impl.NATIVE)).is_empty()
	assert_bool(SimImpls.is_native(worlds[1], SimProbe.Phase.FLOW)).is_true()
	for world: World in worlds:
		for slot: int in 5:
			world.flow.acquire(100 + slot * 900, slot % 3, 0, 1)
		world.flow.key_goal[1] = world.map_cols * world.map_rows
		world.flow.key_class[2] = 3
		world.flow.key_class[3] = -1
		world.flow.key_goal[4] = -1
		FlowCache.run(world, 100000)
	assert_str(StateDiff.first(worlds[0], worlds[1])).is_empty()
	assert_array(worlds[1].flow.status).is_equal([2, 2, 2, 2, 2, 0, 0, 0])
	for slot: int in range(1, 5):
		assert_int(worlds[1].flow.field(slot).cost.count(FlowField.UNREACHED)).is_equal(4356)
	assert_bool(worlds[1].flow.field(0).cost.count(FlowField.UNREACHED) < 4356).is_true()


## begin()'s key rule: a served slot that is made to wait again keeps serving its cost while the
## same key re-integrates, and serves nothing while another goal or class integrates.
func test_a_served_slot_re_keyed_by_hand_matches() -> void:
	var worlds: Array[World] = [_world(_arena_scenario(null)), _world(_arena_scenario(null))]
	assert_array(SimImpls.use(worlds[1], SimImpls.Impl.NATIVE)).is_empty()
	assert_bool(SimImpls.is_native(worlds[1], SimProbe.Phase.FLOW)).is_true()
	for world: World in worlds:
		world.flow.acquire(100, FOOT, 0, 1)
		FlowCache.run(world, 100000)
	# [goal, class, whether it is the key the slot has]
	for key: Array in [[100, FOOT, true], [2000, FOOT, false], [2000, TRACKED, false]]:
		for budget: int in [50, 100000]:
			for world: World in worlds:
				if budget == 50:
					world.flow.key_goal[0] = key[0]
					world.flow.key_class[0] = key[1]
					world.flow.status[0] = FlowCache.Status.WAITING
				FlowCache.run(world, budget)
			var served: bool = worlds[1].flow.field(0).complete
			assert_bool(served).is_equal(budget != 50 or key[2])
			assert_str(StateDiff.first(worlds[0], worlds[1])).is_empty()


## The goal in the middle of a 3x3 map, the four orthogonal neighbours costing 14 and the four
## corners 10: settling the goal queues all eight at distance 14, in the scan order of FlowField.DX
## and DY (north-west, north, north-east, west, east, south-west, south, south-east). A bucket pops
## last in first out, so the chain of the bucket shows the order, which no other map has: a diagonal
## step (14) never equals an orthogonal one in the 900-tick run, so swapping a diagonal with its
## orthogonal neighbour in the scan changes nothing there. One cell of budget per call, from a
## WAITING slot, so that the begin of the field is the first thing the kernel does.
@warning_ignore("integer_division")
func test_a_diagonal_and_an_orthogonal_neighbour_queue_in_scan_order() -> void:
	var rigs: Array[RefCounted] = []
	for impl: int in SimImpls.IMPLS:
		var rig: RefCounted = FlowRig.new().setup(impl, 3, 3, 2)
		assert_array(rig.problems).is_empty()
		assert_bool(SimImpls.is_native(rig.world, SimProbe.Phase.FLOW)).is_equal(
			impl == SimImpls.Impl.NATIVE
		)
		rig.world.terrain_cost = PackedByteArray(SCAN_COST)
		for cell: int in [1, 3, 5, 7]:
			rig.world.set_terrain(cell, 1)
		rig.acquire(4, FOOT, rig.world.map_version, 1)
		rigs.append(rig)
	var queued: Array[int] = []
	var calls: int = 0
	while not rigs[0].field(0).complete and calls < 12:
		for rig: RefCounted in rigs:
			assert_int(rig.run(1)).is_equal(1)
		assert_str(StateDiff.first(rigs[0].world, rigs[1].world)).is_empty()
		calls += 1
		if calls == 1:
			# The chain of bucket 14 from its head, in plain cell numbers (the padded map is 5 wide).
			var field: FlowField = rigs[0].field(0)
			var cell: int = field.bucket_head[14]
			while cell != -1 and queued.size() < 9:
				queued.append((cell / 5 - 1) * 3 + cell % 5 - 1)
				cell = field.link_next[cell]
	assert_array(queued).is_equal([8, 7, 6, 5, 3, 2, 1, 0])
	assert_int(calls).is_equal(9)
	for rig: RefCounted in rigs:
		var served: Array[int] = []
		for cell: int in 9:
			served.append(rig.field(0).cost[(cell / 3 + 1) * 5 + cell % 3 + 1])
		assert_array(served).is_equal([14, 14, 14, 14, 0, 14, 14, 14, 14])


## {diff: the first member that differed after a call ("" if none), settled: the cells integrated,
## served: the most fields served at once, again: the calls that found a served field being
## re-integrated}.
func _lockstep(scenario: ScenarioDef, ticks: int) -> Dictionary:
	var a: World = _world(scenario)
	var b: World = _world(scenario)
	assert_array(SimImpls.use(a, SimImpls.Impl.GDSCRIPT)).is_empty()
	assert_array(SimImpls.use(b, SimImpls.Impl.NATIVE)).is_empty()
	assert_bool(SimImpls.is_native(b, SimProbe.Phase.FLOW)).is_true()
	var rng: DetRandom = DetRandom.create(42, 7)
	var cells: int = a.map_cols * a.map_rows
	var keys: Array[Vector2i] = []
	for key: int in KEYS:
		keys.append(Vector2i(rng.next_int(cells), key % 3))
	# The first two keys sit in opposite corners: cell 0 and the last cell are goals, and their
	# fields cross the whole map.
	keys[0] = Vector2i(0, keys[0].y)
	keys[1] = Vector2i(cells - 1, keys[1].y)
	var repaints: Array[Vector2i] = []
	for _tick: int in REPAINT_TICKS:
		repaints.append(Vector2i(rng.next_int(cells), 3))
	var run: Dictionary = {"diff": "", "settled": 0, "served": 0, "again": 0}
	for tick: int in ticks:
		for world: World in [a, b]:
			Sim.step(world, [])
			if tick % REQUEST_EVERY == 0:
				var request: int = tick / REQUEST_EVERY
				_take_field(world, request % GROUPS, keys[request % KEYS])
			if tick in REPAINT_TICKS:
				var paint: Vector2i = repaints[REPAINT_TICKS.find(tick)]
				world.set_terrain(paint.x, paint.y)
		# Every fifth tick calls twice, so that the stat adds up.
		var calls: Array[int] = [BUDGETS[tick % BUDGETS.size()]]
		if tick % 5 == 0:
			calls.append(2)
		for budget: int in calls:
			FlowCache.run(a, budget)
			FlowCache.run(b, budget)
			run.diff = StateDiff.first(a, b)
			if run.diff != "":
				run.diff = "tick %d, budget %d: %s" % [tick, budget, run.diff]
				return run
		run.settled += a.stats[World.Stat.FLOW_CELLS]
		var served: int = 0
		var again: bool = false
		for field: FlowField in a.flow.fields:
			served += int(field.complete)
			again = again or (field.complete and field.pending > 0)
		run.served = maxi(run.served, served)
		run.again += int(again)
	return run


## The rows of `group` leave their fields and take the field of `key` (goal cell, move class), or -1
## when every slot is referenced. Group 0 holds the last rows of the World, group 1 the rows before
## them and so on; the last group holds the first rows, 0 to GROUP_ROWS - 1, so that a recount that
## starts at row 1 shows.
func _take_field(world: World, group: int, key: Vector2i) -> void:
	var first: int = 0
	if group < GROUPS - 1:
		first = maxi(world.unit_count() - (group + 1) * GROUP_ROWS, 0)
	for row: int in range(first, first + GROUP_ROWS):
		world.field[row] = -1
	var slot: int = world.flow.acquire(key.x, key.y, world.map_version, world.tick)
	for row: int in range(first, first + GROUP_ROWS):
		world.field[row] = slot


func _rules() -> RulesDef:
	return load("res://data/rules.tres") as RulesDef


## The perf arena with `rules` (null: data/rules.tres).
func _arena_scenario(rules: RulesDef) -> ScenarioDef:
	var scenario: ScenarioDef = (load(ARENA_PATH) as ScenarioDef).duplicate() as ScenarioDef
	if rules != null:
		scenario.rules = rules
	return scenario


## Sixty tanks on an open map of `size` tiles.
func _small_scenario(size: Vector2i) -> ScenarioDef:
	var tank: UnitDef = load("res://data/units/light_tank.tres") as UnitDef
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.unit = tank
	spawn.count = 60
	spawn.origin_tile = Vector2i(2, 2)
	spawn.columns = 8
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = size
	scenario.rules = _rules()
	scenario.player_count = 1
	scenario.roster.assign([tank])
	scenario.spawns.assign([spawn])
	return scenario


## The World of `scenario` with slow sand, scrub, rock and water painted over a tenth of its
## cells, the same on every call.
func _world(scenario: ScenarioDef) -> World:
	var world: World = World.from_scenario(scenario)
	world.terrain_cost = PackedByteArray(GROUND_COST)
	var rng: DetRandom = DetRandom.create(42, 9)
	var cells: int = world.map_cols * world.map_rows
	for _paint: int in cells / 10:
		world.set_terrain(rng.next_int(cells), rng.next_int(5))
	return world
