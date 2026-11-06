extends GdUnitTestSuite
## The INTEGRATE kernel's reading of the flow cache's slots, and the largest distances its stall
## takes a root of (ADR 0013 sections 2 and 4, plan P37n, fix round 1). The pass asks a slot for
## `complete` once per call and keeps the answer (a bind layer pays an Object::get for each ask,
## and a FIELD unit that waits for a pending field asks on every tick, so a get per row would be
## forbidden), updated by the recycle of a slot that takes a new key; a slot past the answers it
## can keep (integrate::MEMO_SLOTS, 63) is asked on each use. The number of asks is counted by the
## sanitizer harness (native/sim_kernels/sanitizer/integrate_cases.cpp); here the answers are:
## every case builds two identical Worlds, one running the GDScript phase and one the C++ kernel,
## and compares their full state (StateDiff) as well as the values the rule gives.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const INTEGRATE: int = SimProbe.Phase.INTEGRATE
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const FIELD: int = World.NavMode.FIELD
const NO_NEXT: int = -2
## A `nav_next` that is neither -1 (no look-up yet) nor a tile: a row that carries it shows whether
## a look-up ran, because a look-up replaces it with a tile, NO_NEXT or -1.
const MARK: int = -3
const BIG: int = 100000
const INTEGRATE_HEADER: String = "res://native/sim_kernels/src/core/integrate.h"
## integrate::MEMO_SLOTS as core/integrate.h writes it, and its value: a slot's answer is a bit of
## an int64_t, shifted by 0 to 62.
const MEMO_EXPRESSION: String = "std::numeric_limits<int64_t>::digits"
const MEMO_SLOTS: int = 63
## The slots of the wide cache: the last one the pass keeps an answer for is 62.
const WIDE_SLOTS: int = 70
const WIDE_COMPLETE: int = 65
## The slots that rows follow in the wide cache, in row order. Slots 0, 1 and 5 come before 64, 65
## and 69, the slots that a shift past the width of a word would read as them.
const WIDE_ROWS: Array[int] = [0, 1, 5, 62, 63, 64, 65, 69]


## The stall of a unit on a complete field that names no next tile takes the root at any distance:
## unit 1 stands in one corner of the largest map (64 x 64) and its goal in the opposite one is
## walled in by rock, so the squared distance is 7.9e9, past 2^32, where isqrt takes its first
## step. The rule gives the floor of 63000 x sqrt(2), 89095.
func test_the_stall_takes_the_root_of_a_squared_distance_past_2_pow_32() -> void:
	var pair: Array[World] = _pair(_walled_goal_world)
	for world: World in pair:
		Movement.integrate(world)
		var label: String = "native %s" % (world.native_phases != 0)
		(
			assert_array([world.nav_next[0], world.best_dist[0], world.stall[0]])
			. override_failure_message(label)
			. is_equal([NO_NEXT, 89095, 0])
		)
		assert_int(world.order[0]).is_equal(MOVE)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A slot that takes a new key in the pass reads as pending to the rows after it. Unit 1 reads
## slot 1 complete, then unit 2, which stands on the key of slot 0 with a goal in another tile,
## takes the field of that tile (_take_own_field) on the least recently used slot that nothing
## references, slot 1, which is recycled. Unit 3 follows slot 1 with its look-up due: the field is
## pending now, so its `nav_next` keeps the mark. An answer kept from before the recycle would send
## it to a look-up that rewrites the mark.
func test_a_slot_recycled_in_the_pass_reads_as_pending_for_the_rows_after_it() -> void:
	var pair: Array[World] = _pair(_recycled_world)
	for world: World in pair:
		Movement.integrate(world)
		var label: String = "native %s" % (world.native_phases != 0)
		assert_bool(world.nav_next[0] != MARK).override_failure_message(label).is_true()
		assert_array(Array(world.field.slice(0, 3))).override_failure_message(label).is_equal(
			[1, 1, 1]
		)
		(
			assert_array([world.nav_next[1], world.nav_next[2]])
			. override_failure_message(label)
			. is_equal([-1, MARK])
		)
		assert_array([world.flow.key_goal[1], world.flow.field(1).complete]).is_equal([195, false])
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## A cache of 70 slots, 65 of them complete and the last five pending, with a row on each of eight
## slots on both sides of the 63 that the pass keeps an answer for. Every row carries the mark with
## its look-up due: after the pass the rows on complete slots have been looked up, the ones on
## pending slots keep the mark (a slot read as another slot would give one of them a look-up).
## Then the cache completes the last five and the pass looks up every row.
func test_slots_past_the_answers_the_pass_keeps_are_asked_on_each_use() -> void:
	var pair: Array[World] = _pair(_wide_world)
	for world: World in pair:
		Movement.integrate(world)
		for row: int in WIDE_ROWS.size():
			var label: String = "slot %d, native %s" % [WIDE_ROWS[row], world.native_phases != 0]
			var looked_up: bool = WIDE_ROWS[row] < WIDE_COMPLETE
			assert_bool(world.nav_next[row] != MARK).override_failure_message(label).is_equal(
				looked_up
			)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
	for world: World in pair:
		FlowCache.run(world, BIG)
		Movement.integrate(world)
		for row: int in WIDE_ROWS.size():
			var label: String = (
				"slot %d done, native %s" % [WIDE_ROWS[row], world.native_phases != 0]
			)
			assert_bool(world.nav_next[row] != MARK).override_failure_message(label).is_true()
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The number of slots the pass keeps an answer for is the value bits of an int64_t (63), and it
## covers the cache of data/rules.tres. The states are the same for any number (a slot past it is
## asked on each use, correct and slower), so no state comparison sees a smaller one: with a
## MEMO_SLOTS of 4 and the 8 slots of the rules, the rows on slots 4 to 7 would pay an Object::get
## of `complete` each again, the per-row get that ADR 0013 section 2 forbids and that the next
## kernels copy. The count of asks is the sanitizer harness's; here the constant is read as text.
func test_the_slots_the_pass_keeps_an_answer_for_are_the_value_bits_of_an_int64() -> void:
	var declaration: RegEx = RegEx.create_from_string(
		"inline constexpr int64_t MEMO_SLOTS = ([^;]+);"
	)
	var found: RegExMatch = declaration.search(FileAccess.get_file_as_string(INTEGRATE_HEADER))
	assert_object(found).is_not_null()
	if found == null:
		return
	assert_str(found.get_string(1).strip_edges()).is_equal(MEMO_EXPRESSION)
	var rules: RulesDef = load("res://data/rules.tres") as RulesDef
	assert_int(rules.flow_cache_size).is_less_equal(MEMO_SLOTS)


## The pairs: a builder gives the same World twice, the first running the GDScript phase and the
## second the C++ kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		assert_array(SimImpls.attach(world, impl, INTEGRATE)).is_empty()
		pair.append(world)
	return pair


## A 64 x 64 open map with a field keyed on tile (63, 63), complete, whose three neighbours are
## rock: nothing else is reached. One tank in FIELD at the middle of tile (0, 0) with its goal at
## the middle of the goal's tile.
func _walled_goal_world() -> World:
	var rock: Array[Vector2i] = [Vector2i(62, 62), Vector2i(62, 63), Vector2i(63, 62)]
	var world: World = GridWorld.from_rows(GridWorld.grass(64, 64, rock))
	assert_int(world.flow.acquire(63 * 64 + 63, TRACKED, world.map_version, 0)).is_equal(0)
	FlowCache.run(world, BIG)
	assert_bool(world.flow.field(0).complete).is_true()
	world.add_unit(1, 0, 500, 500)
	world.order[0] = MOVE
	world.nav_mode[0] = FIELD
	world.field[0] = 0
	world.goal_x[0] = 63500
	world.goal_y[0] = 63500
	return world


## A 20 x 12 map and a cache of 2 slots, keys 30 and 31, complete, that nobody references, last
## used at ticks 5 and 1. Every tick is a look-up turn (a period of 1). Three MOVE tanks in FIELD:
## tank 1 follows slot 1 with the mark, tank 2 stands on tile 30, the key of slot 0, with its goal
## in tile 195 (it takes that key, on slot 1), and tank 3 follows slot 1 with the mark. The tick
## is 9.
func _recycled_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12))
	world.flow_cache_size = 2
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 2)
	world.line_check_period_ticks = 1
	for key: int in [30, 31]:
		assert_int(world.flow.acquire(key, TRACKED, world.map_version, 0)).is_greater(-1)
	FlowCache.run(world, BIG)
	world.flow.last_used[0] = 5
	world.flow.last_used[1] = 1
	var starts: Array[Vector2i] = [
		Vector2i(10500, 2500), Vector2i(10500, 1500), Vector2i(5500, 5500)
	]
	var goals: Array[Vector2i] = [Vector2i(500, 10500), Vector2i(15500, 9500), Vector2i(500, 5500)]
	var slots: Array[int] = [1, 0, 1]
	for index: int in 3:
		var row: int = world.add_unit(1, 0, starts[index].x, starts[index].y) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = slots[index]
		world.nav_next[row] = MARK if index != 1 else -1
		world.goal_x[row] = goals[index].x
		world.goal_y[row] = goals[index].y
	world.tick = 9
	return world


## A 10 x 10 open map and a cache of 70 slots: slots 0 to 64 hold tiles 0 to 64 and are complete,
## slots 65 to 69 hold tiles 65 to 69 and wait. One MOVE tank in FIELD in tile (5, 5) for each of
## WIDE_ROWS, on that slot, with the mark and its look-up due (a period of 1).
func _wide_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(10, 10))
	world.flow_cache_size = WIDE_SLOTS
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), WIDE_SLOTS)
	world.line_check_period_ticks = 1
	for key: int in WIDE_COMPLETE:
		assert_int(world.flow.acquire(key, TRACKED, world.map_version, 0)).is_equal(key)
	FlowCache.run(world, BIG)
	for key: int in range(WIDE_COMPLETE, WIDE_SLOTS):
		assert_int(world.flow.acquire(key, TRACKED, world.map_version, 0)).is_equal(key)
	for slot: int in WIDE_ROWS:
		var row: int = world.add_unit(1, 0, 5500, 5500) - 1
		world.order[row] = MOVE
		world.nav_mode[row] = FIELD
		world.field[row] = slot
		world.nav_next[row] = MARK
		world.goal_x[row] = 500
		world.goal_y[row] = 500
	assert_bool(world.flow.field(WIDE_COMPLETE - 1).complete).is_true()
	assert_bool(world.flow.field(WIDE_COMPLETE).complete).is_false()
	world.tick = 9
	return world
