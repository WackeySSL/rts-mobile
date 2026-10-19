extends GdUnitTestSuite
## The INTEGRATE kernel against its GDScript twin over long runs (ADR 0013 section 4, plan P37n3).
## Two Worlds are built from the seed-42 perf arena, the first stepped with the GDScript phases and
## the second with the C++ kernels (SimImpls), each through its own MatchLoop with the same
## orders, and after every tick the state hash and the full state (StateDiff: every column, scalar,
## the flow cache and its slots) are compared. The orders keep INTEGRATE busy for the whole run:
## the scenario's two attack-moves, MatchScript's eight commands and, from tick 160, a seeded
## wave every 25 ticks (a group of one side sent to a point or at an enemy), so that units cross
## the wall, follow fields, re-key ATTACK fields, take their own fields, stall and arrive. The run
## repeats on the arena with slow ground, scrub, rock and water painted in (more blocked tiles,
## more fields), on non-default rules (every rule int changed, so a rule value written as a C++
## literal fails), with the kernels' World running INTEGRATE alone (FLOW in GDScript, so only the
## INTEGRATE kernel can differ) and on a cache of two slots, where the slot tables that the C++
## and the GDScript FlowCache.acquire produce are also compared on their own. The last case plays
## 600 seeded random states (a random map, cache and rows, garbage in the navigation columns).
## The crafted cases are in test_integrate_lockstep_cases.gd and test_integrate_lockstep_off_map.gd.
## That Movement.integrate hands the phase to the kernel at all is pinned by the spy case of
## tests/sim/test_kernel_dispatch.gd.

const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const TICKS: int = 900
## The waves start at this tick, every WAVE_EVERY ticks, at tick % WAVE_EVERY == WAVE_AT.
const WAVE_FIRST: int = 160
const WAVE_EVERY: int = 25
const WAVE_AT: int = 7
## The cost of grass, slow sand (12 foot, 41 wheeled, 255 tracked, the cap of the bucket ring),
## scrub (foot only), rock and water for foot, wheeled and tracked, as World.terrain_cost holds
## them: a painted cell turns to one of these five.
const GROUND_COST: Array[int] = [10, 10, 10, 12, 41, 255, 13, 0, 0, 0, 0, 0, 0, 0, 0]
const SMALL_CACHE: int = 2
const SOUP_WORLDS: int = 600
const SOUP_TICKS: int = 6
const TRACKED: int = World.MoveClass.TRACKED
const FOOT: int = World.MoveClass.FOOT
const WHEELED: int = World.MoveClass.WHEELED
## What the random states must reach, in all of them together.
const TALLY_REACHED: Array[StringName] = [
	&"field", &"named", &"no_next", &"rekeys", &"own_fields", &"ended", &"recycles", &"holds"
]
## The orders and navigation modes a random unit draws from, with FIELD and ATTACK twice or more
## (an order of 4 is none of the orders the sim knows).
## Three move classes, and two the cache does not have (3 and -1), whose units have a speed of 0.
const SOUP_CLASSES: Array[int] = [TRACKED, FOOT, WHEELED, 3, -1]
const SOUP_ORDERS: Array[int] = [0, 1, 2, 3, 3, 3, 2, 4]
const SOUP_MODES: Array[int] = [2, 2, 2, 1, 1, 0, 3, 4]
## The characters of GridWorld.GROUND that a random map is made of: grass most of the time.
const SOUP_GROUND: String = "........^^#wt24"


func test_900_arena_ticks_match_after_every_tick() -> void:
	var rig: RefCounted = LockstepRig.new().setup(_arena)
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"field": 20000, &"named": 15000, &"ended": 100, &"rekeys": 15})
	assert_int(rig.tally[&"own_fields"]).is_greater(0)
	assert_int(rig.worlds[0].flow.requests).is_greater(30)


func test_the_same_run_with_only_integrate_in_c_plus_plus_matches() -> void:
	var rig: RefCounted = LockstepRig.new().setup(_arena, true)
	assert_array(rig.problems).is_empty()
	assert_bool(rig.worlds[1].native_phases == 1 << SimProbe.Phase.INTEGRATE).is_true()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"field": 20000, &"named": 15000, &"ended": 100, &"rekeys": 15})


func test_900_ticks_on_the_arena_with_slow_ground_scrub_rock_and_water_painted_in_match() -> void:
	var rig: RefCounted = LockstepRig.new().setup(_arena.bind(null, true))
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"field": 30000, &"named": 25000, &"no_next": 800, &"ended": 100})
	_assert_reached(rig, {&"rekeys": 20, &"own_fields": 5, &"recycles": 1})


func test_the_same_run_on_changed_rules_matches() -> void:
	var rules: RulesDef = _rules().duplicate() as RulesDef
	for info: Dictionary in rules.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and info["type"] == TYPE_INT:
			rules.set(info["name"], int(rules.get(info["name"])) + 3)
	# The rules INTEGRATE reads move far from the data: a literal of the data fails on all of them.
	rules.line_check_period_ticks = 3
	rules.stall_ticks = 6
	rules.stall_range_spacings = 4
	rules.attack_rekey_milli = 2500
	rules.flow_cache_size = 5
	var rig: RefCounted = LockstepRig.new().setup(_arena.bind(rules, true))
	assert_array(rig.problems).is_empty()
	assert_str(rig.run(TICKS, _orders)).is_empty()
	_assert_reached(rig, {&"field": 20000, &"named": 20000, &"no_next": 500, &"ended": 100})
	_assert_reached(rig, {&"rekeys": 2, &"own_fields": 2})


## The arena with a cache of two slots, so that the units of a wave ask for more fields than the
## cache has: every slot is referenced for most of the run, so an ATTACK re-key and a unit's own
## field are mostly refused, and the slots change hands only when a group lets one go. The tables
## of acquire (key, class, version, last use, references, request number, status) and the request
## counter are compared on their own after every tick, apart from the full state.
func test_a_cache_of_two_slots_gives_the_same_slot_tables_after_every_tick() -> void:
	var rules: RulesDef = _rules().duplicate() as RulesDef
	rules.flow_cache_size = SMALL_CACHE
	var rig: RefCounted = LockstepRig.new().setup(_arena.bind(rules, true))
	assert_array(rig.problems).is_empty()
	assert_int(rig.worlds[0].flow.status.size()).is_equal(SMALL_CACHE)
	for _tick: int in TICKS:
		assert_str(rig.step(_chase_orders)).is_empty()
		assert_array(_tables(rig.worlds[1])).is_equal(_tables(rig.worlds[0]))
	_assert_reached(rig, {&"contended": 500, &"fresh": 2, &"holds": 10, &"recycles": 1})


## 600 random states, each stepped 6 ticks: a map of 3 to 14 columns and 3 to 12 rows of mostly
## grass with scrub, rock and slow ground; a cache of 1 to 4 slots, some fields integrated, some
## still waiting; 1 to 40 units of three move classes with random orders (an unknown one among
## them), modes, slots (a number past the cache too), best distances, stall counts, `nav_next`
## and `nav_cell` marks, group targets and goals (off the map too), and random rule ints (a
## negative line-check period, a stall of no ticks, a re-key distance of 0) and a negative tick.
## The twin takes every one of these without error, so a difference is the kernel's.
func test_random_states_match() -> void:
	var total: Dictionary[StringName, int] = {}
	for name: StringName in LockstepRig.TALLY:
		total[name] = 0
	for index: int in SOUP_WORLDS:
		var rig: RefCounted = LockstepRig.new().setup(_random_world.bind(index), index % 2 == 0)
		assert_array(rig.problems).is_empty()
		assert_str(rig.run(SOUP_TICKS)).override_failure_message("state %d" % index).is_empty()
		for name: StringName in LockstepRig.TALLY:
			total[name] += rig.tally[name]
	for name: StringName in TALLY_REACHED:
		assert_int(total[name]).override_failure_message(String(name)).is_greater(10)


func _rules() -> RulesDef:
	return load("res://data/rules.tres") as RulesDef


## Asserts that a run reached each rule at least as often as `least` (by tally name) says.
func _assert_reached(rig: RefCounted, least: Dictionary) -> void:
	for name: StringName in least:
		assert_int(rig.tally[name]).override_failure_message("reached %s" % name).is_greater(
			int(least[name]) - 1
		)


## The slot tables of acquire, as arrays, with the request counter last.
func _tables(world: World) -> Array:
	var flow: FlowCache = world.flow
	return [
		Array(flow.key_goal),
		Array(flow.key_class),
		Array(flow.key_version),
		Array(flow.last_used),
		Array(flow.ref_count),
		Array(flow.requested),
		Array(flow.status),
		flow.requests,
	]


## The seed-42 arena (the jitter drawn as the runner draws it) with `rules` (null: data/rules.tres)
## and, with `paint`, a tenth of its cells turned to slow ground, scrub, rock or water.
func _arena(rules: RulesDef = null, paint: bool = false) -> World:
	var scenario: ScenarioDef = (load(ARENA_PATH) as ScenarioDef).duplicate() as ScenarioDef
	if rules != null:
		scenario.rules = rules
	var world: World = World.from_scenario(scenario, DetRandom.create(42, DetRandom.STREAM_SIM))
	if paint:
		world.terrain_cost = PackedByteArray(GROUND_COST)
		var rng: DetRandom = DetRandom.create(42, 9)
		var cells: int = world.map_cols * world.map_rows
		for _paint: int in cells / 10:
			world.set_terrain(rng.next_int(cells), rng.next_int(5))
	return world


## The commands of `tick` for one World of the arena run (a fresh Command each call).
func _orders(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		# The two orders of the scenario: each side attack-moves to the other's side of the wall.
		out.append(Command.attack_move(1, LockstepRig.ids_of(world, 1), 39500, 32500))
		out.append(Command.attack_move(2, LockstepRig.ids_of(world, 2), 24500, 32500))
	out.append_array(MatchScript.commands_at(tick))
	if tick >= WAVE_FIRST and tick % WAVE_EVERY == WAVE_AT:
		out.append(_wave(world, tick))
	return out


## The orders of the two-slot run: the same two first orders, then every 20 ticks a group of 10 of
## one side sent at one unit of the other, so that ATTACK fields re-key all the time.
func _chase_orders(world: World, tick: int) -> Array[Command]:
	var out: Array[Command] = []
	if tick == 0:
		out.append(Command.attack_move(1, LockstepRig.ids_of(world, 1), 39500, 32500))
		out.append(Command.attack_move(2, LockstepRig.ids_of(world, 2), 24500, 32500))
	if tick >= 20 and tick % 20 == 0:
		var rng: DetRandom = DetRandom.create(42, 900 + tick)
		var player: int = 1 + tick / 20 % 2
		var mine: PackedInt32Array = LockstepRig.ids_of(world, player)
		var theirs: PackedInt32Array = LockstepRig.ids_of(world, 3 - player)
		var first: int = rng.next_int(mine.size() - 10)
		var group: PackedInt32Array = mine.slice(first, first + 10)
		out.append(Command.attack(player, group, theirs[rng.next_int(theirs.size())]))
	return out


## One seeded order of a side: 6 to 20 consecutive ids of its units, sent (MOVE or ATTACK_MOVE) to
## a point anywhere on the map, rock and wall included, or (ATTACK) at one unit of the other side.
func _wave(world: World, tick: int) -> Command:
	var rng: DetRandom = DetRandom.create(42, 500 + tick)
	var player: int = 1 + rng.next_int(2)
	var mine: PackedInt32Array = LockstepRig.ids_of(world, player)
	var theirs: PackedInt32Array = LockstepRig.ids_of(world, 3 - player)
	var count: int = 6 + rng.next_int(15)
	var first: int = rng.next_int(mine.size() - count)
	var group: PackedInt32Array = mine.slice(first, first + count)
	var x: int = rng.next_int(world.map_w)
	var y: int = rng.next_int(world.map_h)
	match rng.next_int(3):
		0:
			return Command.move(player, group, x, y)
		1:
			return Command.attack_move(player, group, x, y)
	return Command.attack(player, group, theirs[rng.next_int(theirs.size())])


## State number `index` of the random states (the same World each call).
func _random_world(index: int) -> World:
	var rng: DetRandom = DetRandom.create(42, 7000 + index)
	var cols: int = 3 + rng.next_int(12)
	var rows: int = 3 + rng.next_int(10)
	var lines: PackedStringArray = PackedStringArray()
	for _row: int in rows:
		var line: String = ""
		for _column: int in cols:
			line += SOUP_GROUND[rng.next_int(SOUP_GROUND.length())]
		lines.append(line)
	var world: World = GridWorld.from_rows(lines, SOUP_CLASSES)
	world.player_count = 2
	var slots: int = 1 + rng.next_int(4)
	world.flow_cache_size = slots
	world.flow.configure(cols, rows, World.MoveClass.size(), slots)
	world.line_check_period_ticks = rng.range_int(-2, 7)
	world.stall_ticks = rng.range_int(-1, 6)
	world.stall_range_spacings = rng.range_int(0, 5)
	world.attack_rekey_milli = rng.range_int(0, 6000)
	world.tick = rng.range_int(-30, 400)
	var speeds: Array[int] = [0, 1, 60, 120, 500]
	for type: int in SOUP_CLASSES.size():
		world.type_speed[type] = speeds[rng.next_int(speeds.size())] if type < 3 else 0
		world.type_spacing[type] = rng.range_int(0, 3000)
	var cells: int = cols * rows
	var keys: Array[int] = []
	for _key: int in rng.range_int(1, slots + 1):
		keys.append(rng.next_int(cells))
		world.flow.acquire(keys[-1], rng.next_int(3), world.map_version, rng.next_int(9))
	FlowCache.run(world, [0, 5, 40, 100000, 100000][rng.next_int(5)])
	for slot: int in slots:
		if rng.next_int(4) == 0:
			# A key of the map version before this one holds no unit's key: acquire() skips it.
			world.flow.key_version[slot] = world.map_version - 1
	for _unit: int in 1 + rng.next_int(40):
		_add_random_unit(world, rng, cols, rows, slots, keys)
	return world


## One unit of `world` with a random position on the map and random navigation columns.
func _add_random_unit(
	world: World, rng: DetRandom, cols: int, rows: int, slots: int, keys: Array[int]
) -> void:
	var cells: int = cols * rows
	var id: int = world.add_unit(
		1 + rng.next_int(2),
		rng.next_int(SOUP_CLASSES.size()),
		rng.next_int(cols * 1000),
		rng.next_int(rows * 1000)
	)
	var row: int = world.index_of(id)
	var unit_count: int = world.unit_count()
	world.order[row] = SOUP_ORDERS[rng.next_int(SOUP_ORDERS.size())]
	world.nav_mode[row] = SOUP_MODES[rng.next_int(SOUP_MODES.size())]
	world.field[row] = _soup_slot(rng, slots)
	world.nav_cell[row] = rng.range_int(-1, cells - 1)
	world.nav_next[row] = _soup_next(rng, cells)
	world.best_dist[row] = FlowField.UNREACHED if rng.next_int(2) == 0 else rng.next_int(3000)
	world.stall[row] = rng.next_int(7)
	world.group_cell[row] = -1 if rng.next_int(2) == 0 else rng.range_int(-2, cells + 3)
	world.goal_x[row] = rng.range_int(-1500, cols * 1000 + 1500)
	world.goal_y[row] = rng.range_int(-1500, rows * 1000 + 1500)
	if rng.next_int(6) == 0:
		# In the tile of one of the cache's keys, so that a field is held for it.
		var key: int = keys[rng.next_int(keys.size())]
		world.goal_x[row] = key % cols * 1000 + rng.range_int(0, 999)
		world.goal_y[row] = key / cols * 1000 + rng.range_int(0, 999)
	world.order_target[row] = 1 + rng.next_int(unit_count + 2)
	world.target[row] = 1 + rng.next_int(unit_count + 2)
	if rng.next_int(6) == 0 and world.type_speed[world.type_index[row]] > 0:
		world.push_x[row] = rng.range_int(-40, 40)
		world.push_y[row] = rng.range_int(-40, 40)


## The slot of a random unit: a slot of the cache (five times in seven), a number one past the cache
## or none.
func _soup_slot(rng: DetRandom, slots: int) -> int:
	var pick: int = rng.next_int(7)
	if pick < 5:
		return rng.next_int(slots)
	return slots if pick == 5 else -1


## The `nav_next` of a random unit: none yet, no next tile, or any number a tile has.
func _soup_next(rng: DetRandom, cells: int) -> int:
	var pick: int = rng.next_int(4)
	if pick == 0:
		return -1
	return Movement.NO_NEXT if pick == 1 else rng.range_int(-3, cells + 1)
