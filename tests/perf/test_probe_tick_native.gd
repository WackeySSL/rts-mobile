extends GdUnitTestSuite
## Spike P26n: the C++ port of the perf probe's mock tick (native/probe_tick, class ProbeTickNative)
## is bit-identical to game/ui/PerfProbeTick.gd. Both start fresh and play 900 ticks in lockstep,
## the flow slice (512 cells) on every 15th and the dirty drain on every 3rd as the probe's publish
## does (else `dirty_count` sticks at its cap of 4096 from tick 171 and `dirty` is no longer
## written); after every call tick, x, y, target, seen, dirty, dirty_count, flow_cost and
## slice_cells are compared, and the first difference fails the test with the tick, the array and
## the index. The return values of step() and flow_slice() are wall times in microseconds and
## cannot be equal; they are checked to be whole, non-negative times. The library is built by
## scripts/build-native.sh (verify.sh does it first); without it every test here FAILS, never
## skips.
##
## What the 900 natural ticks do not reach, and what covers it instead:
## - The caps of the separation scan (8 hits, 16 looked at) are reached by the crowd test below,
##   which starts both ticks from a crafted layout.
## - An exact squared-distance tie between two enemies in the targeting scan (the `<` that keeps
##   the first of two; the first one is at tick 14790) and a stale entry in the flow queue (the
##   `cost[cell] != dist` skip, which never happens on this map: no cell has a cheaper second way)
##   are covered by reading the port against the GDScript, line by line. The ties are also covered
##   by a 20000-tick run, too slow for verify.sh (about 55 s in the editor build):
##   PerfProbeLockstep.play(PerfProbeTick.new(), ClassDB.instantiate("ProbeTickNative"), 20000,
##   512) returns "", and returns "tick 14790 (step): target[130]..." for a port with `<=`.

const NOT_LOADED: String = "ProbeTickNative not loaded: run scripts/build-native.sh"
const TICKS: int = 900
const CELLS: int = 512
const OPEN_TILES: int = 3980  ## Every open tile of the flow grid: 4096 less the 116 ridge tiles.


func test_900_ticks_and_their_flow_slices_match_bit_for_bit() -> void:
	var cpp: RefCounted = _native()
	if cpp == null:
		return
	var gd: PerfProbeTick = PerfProbeTick.new()
	if not _expect_same(gd, cpp, "start"):
		return
	var last_dirty: PackedInt32Array = gd.dirty.duplicate()
	var dirty_changes: int = 0  # Fog ticks after which the dirty list differs from the last one.
	for _i: int in TICKS:
		var gd_us: int = gd.step()
		var cpp_us: int = cpp.step()
		assert_bool(gd_us >= 0 and cpp_us >= 0).is_true()
		if not _expect_same(gd, cpp, "step"):
			return
		if gd.tick % PerfProbeLockstep.FLOW_PERIOD == 0:
			gd_us = gd.flow_slice(CELLS)
			cpp_us = cpp.flow_slice(CELLS)
			assert_bool(gd_us >= 0 and cpp_us >= 0).is_true()
			if not _expect_same(gd, cpp, "flow_slice"):
				return
		PerfProbeLockstep.drain_dirty(gd, cpp)
		if gd.tick % PerfProbeLockstep.FOG_PERIOD == 0 and gd.dirty != last_dirty:
			dirty_changes += 1
			last_dirty = gd.dirty.duplicate()
	assert_int(gd.tick).is_equal(TICKS + 3)  # Three warm-up ticks in the constructor.
	assert_int(cpp.tick).is_equal(TICKS + 3)
	# A match of two idle states would prove nothing: both did their work.
	assert_int(gd.seen.count(0)).is_less(gd.seen.size())
	assert_int(gd.target.count(-1)).is_less(PerfProbeTick.UNITS)
	# The dirty path stayed live: it is written long after tick 171, where an undrained count
	# sticks at its cap. (298 changes in 900 ticks on the reference run; 55 without the drain.)
	assert_int(dirty_changes).is_greater(100)


func test_flow_fields_run_to_completion_many_times_with_odd_budgets() -> void:
	var cpp: RefCounted = _native()
	if cpp == null:
		return
	var gd: PerfProbeTick = PerfProbeTick.new()
	# Budgets that end a slice on every kind of boundary: tiny, prime, the probe's, huge and zero.
	var budgets: Array[int] = [512, 1, 37, 4096, 0, 511, 513, 100, 1000000]
	var finished: int = 0  # Short slices: a field settled to its last cell.
	var goals: Dictionary = {}
	for call: int in 3000:
		var budget: int = budgets[call % budgets.size()]
		if call % 3 == 2:  # The tick reads the field while it is being integrated.
			gd.step()
			cpp.step()
			if not _expect_same(gd, cpp, "step in field %d" % finished):
				return
		gd.flow_slice(budget)
		cpp.flow_slice(budget)
		if not _expect_same(gd, cpp, "flow_slice(%d) in field %d" % [budget, finished]):
			return
		if budget > 0 and gd.slice_cells < budget:  # Complete: the next call starts a new goal.
			finished += 1
			var reached: int = gd.flow_cost.size() - gd.flow_cost.count(PerfProbeTick.UNREACHED)
			assert_int(reached).is_equal(OPEN_TILES)
			assert_int(cpp.flow_cost.count(PerfProbeTick.UNREACHED)).is_equal(
				gd.flow_cost.count(PerfProbeTick.UNREACHED)
			)
			goals[gd.flow_cost.find(0)] = true
			if finished == 12:
				break
	assert_int(finished).is_equal(12)  # Twelve complete fields: 16 Dial buckets wrapped many times.
	assert_int(goals.size()).is_greater_equal(8)  # And the goal changed every time.


## A crowd fills the pair loops of the separation step to their caps on the very first tick. 149
## units inside one tile are all within the 800 milli-tile radius of each other, so every scan of
## the pack stops at the 8-hit cap. One unit about two tiles off to the side sees the whole pack in
## its 3x3 cells but is out of range of every one of them, so its scan stops at the 16-looked-at
## cap with no hit. The natural 900 ticks never reach either cap. Mutants of the port with
## `hits < 7` and with `looked < 15` fail this test.
@warning_ignore("integer_division")
func test_a_crowd_reaches_the_pair_caps_and_still_matches() -> void:
	var cpp: RefCounted = _native()
	if cpp == null:
		return
	var gd: PerfProbeTick = PerfProbeTick.new()
	var xs: PackedInt32Array = gd.x.duplicate()
	var ys: PackedInt32Array = gd.y.duplicate()
	xs[0] = 30000  # The lone unit: tile (30, 30).
	ys[0] = 30000
	for i: int in range(1, PerfProbeTick.UNITS):  # The pack: tile (31, 30), at least 1900 away.
		xs[i] = 31900 + (i % 10) * 10
		ys[i] = 30000 + (i / 10) * 10
	gd.x = xs
	gd.y = ys
	cpp.x = xs
	cpp.y = ys
	var found: String = PerfProbeLockstep.play(gd, cpp, 45, CELLS)
	assert_str(found).override_failure_message("C++ differs from GDScript: " + found).is_empty()
	assert_int(gd.tick).is_equal(45 + 3)


func test_properties_read_back_what_was_written() -> void:
	var cpp: RefCounted = _native()
	if cpp == null:
		return
	var gd: PerfProbeTick = PerfProbeTick.new()
	for _i: int in 5:
		gd.step()
	cpp.x = gd.x
	cpp.y = gd.y
	cpp.dirty_count = 7
	assert_array(cpp.x).is_equal(gd.x)
	assert_array(cpp.y).is_equal(gd.y)
	assert_int(cpp.dirty_count).is_equal(7)
	assert_str(cpp.get_build_info()).is_not_empty()
	assert_int(cpp.get_last_step_thread()).is_not_equal(0)  # The constructor warm-up ran a step.


## The C++ tick, or null after failing the test: the library is missing or not loaded.
func _native() -> RefCounted:
	var loaded: bool = ClassDB.class_exists(PerfProbeLockstep.NATIVE_CLASS)
	assert_bool(loaded).override_failure_message(NOT_LOADED).is_true()
	if not loaded:
		return null
	return ClassDB.instantiate(PerfProbeLockstep.NATIVE_CLASS)


## Compares everything; on a difference fails with the tick, the array and the index.
func _expect_same(gd: PerfProbeTick, cpp: RefCounted, when: String) -> bool:
	var found: String = PerfProbeLockstep.difference(gd, cpp)
	(
		assert_str(found)
		. override_failure_message(
			"C++ differs from GDScript at tick %d (%s): %s" % [gd.tick, when, found]
		)
		. is_empty()
	)
	return found == ""
