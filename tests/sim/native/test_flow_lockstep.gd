extends GdUnitTestSuite
## The FLOW kernel against its GDScript twin (ADR 0013 section 4, plan P30n). Two Worlds are built
## from the seed-42 perf arena with slow, scrub and rock cells painted in. World A runs
## FlowCache.run in GDScript and World B in C++, through 900 ticks of the same scripted requests (12
## keys over 8 slots, units taking and leaving fields), terrain changes (re-integration) and odd
## budgets, and the full state is compared after every call. Then the same on maps that are not
## square (wide, then tall), where a mix-up of columns and rows shows.

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
## The ticks of a terrain change, which re-integrates the referenced fields.
const REPAINT_TICKS: Array[int] = [200, 450, 700]
## The cost of grass, slow sand (up to the 255 of the bucket ring), scrub (foot only), rock and
## water for foot, wheeled and tracked, as World.terrain_cost holds them.
const GROUND_COST: Array[int] = [10, 10, 10, 20, 40, 255, 10, 0, 0, 0, 0, 0, 0, 0, 0]


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
	for world: World in worlds:
		for slot: int in 4:
			world.flow.acquire(100 + slot * 900, slot % 3, 0, 1)
		world.flow.key_goal[1] = world.map_cols * world.map_rows
		world.flow.key_class[2] = 3
		world.flow.key_class[3] = -1
		FlowCache.run(world, 100000)
	assert_str(StateDiff.first(worlds[0], worlds[1])).is_empty()
	assert_array(worlds[1].flow.status).is_equal([2, 2, 2, 2, 0, 0, 0, 0])
	assert_int(worlds[1].flow.field(1).cost.count(FlowField.UNREACHED)).is_equal(4356)
	assert_bool(worlds[1].flow.field(0).cost.count(FlowField.UNREACHED) < 4356).is_true()


## begin()'s key rule: a served slot that is made to wait again keeps serving its cost while the
## same key re-integrates, and serves nothing while another goal or class integrates.
func test_a_served_slot_re_keyed_by_hand_matches() -> void:
	var worlds: Array[World] = [_world(_arena_scenario(null)), _world(_arena_scenario(null))]
	assert_array(SimImpls.use(worlds[1], SimImpls.Impl.NATIVE)).is_empty()
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


## {diff: the first member that differed after a call ("" if none), settled: the cells integrated,
## served: the most fields served at once, again: the calls that found a served field being
## re-integrated}.
func _lockstep(scenario: ScenarioDef, ticks: int) -> Dictionary:
	var a: World = _world(scenario)
	var b: World = _world(scenario)
	assert_array(SimImpls.use(a, SimImpls.Impl.GDSCRIPT)).is_empty()
	assert_array(SimImpls.use(b, SimImpls.Impl.NATIVE)).is_empty()
	assert_bool(SimImpls.is_native(b, FlowCache.PHASE_FLOW)).is_true()
	var rng: DetRandom = DetRandom.create(42, 7)
	var cells: int = a.map_cols * a.map_rows
	var keys: Array[Vector2i] = []
	for key: int in KEYS:
		keys.append(Vector2i(rng.next_int(cells), key % 3))
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
## when every slot is referenced.
func _take_field(world: World, group: int, key: Vector2i) -> void:
	var first: int = group * GROUP_ROWS
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
