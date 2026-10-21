extends GdUnitTestSuite
## The deterministic bounds of the perf arena (plan P49a), pinned on hand-made numbers:
## tests/perf/support/perf_bounds.gd holds them, test_sim_perf.gd applies them to the real arena.
## Every bound is tried at its edge: the value on the bound passes, the value one over it is named.
## The literals here are the plan's numbers; a sim PR never changes them (plan exception 3), so a
## change to perf_bounds.gd shows up as a change to this file as well.

const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const Run: GDScript = preload("res://tests/perf/support/perf_run.gd")
## The pins of test_sim_perf.gd, as the load cases use them: any pair will do for the edges.
const ALIVE_PIN: int = 71
const PROJ_PIN: int = 28
## The buffer of the static memory test: 1 MiB.
const HELD_BYTES: int = 1 << 20


## A quarter of the measured value, rounded up, in integer arithmetic: the measured maxima of the
## arena and the two pins each have a fraction there, so a margin that rounded down or went through
## a float shows.
func test_the_margin_is_a_quarter_of_the_value_rounded_up() -> void:
	assert_int(PerfBounds.MARGIN_PERCENT).is_equal(25)
	assert_int(PerfBounds.margin(34)).is_equal(9)
	assert_int(PerfBounds.margin(2193)).is_equal(549)
	assert_int(PerfBounds.margin(7798)).is_equal(1950)
	assert_int(PerfBounds.margin(71)).is_equal(18)
	assert_int(PerfBounds.margin(28)).is_equal(7)
	assert_int(PerfBounds.margin(100)).is_equal(25)
	assert_int(PerfBounds.margin(4)).is_equal(1)
	assert_int(PerfBounds.margin(0)).is_equal(0)
	assert_int(PerfBounds.margin(100, 10)).is_equal(10)
	assert_int(PerfBounds.with_margin(34)).is_equal(43)
	assert_int(PerfBounds.with_margin(100, 10)).is_equal(110)


## The flow cells are the rules' budget and the separation pairs the scan length times the units;
## the other three are the measured maxima plus the margin. The measured maxima are the arena's
## (flow_cells 512 and sep_pairs 1,231 have the rules; line_checks 34, target_candidates 2,193 and
## fog_cells 7,798 are the numbers of PR #129).
func test_the_cost_bounds_are_the_rules_and_the_measured_maxima_plus_a_quarter() -> void:
	var bounds: Dictionary[int, int] = PerfBounds.cost_bounds(512, 16, 150)
	(
		assert_array(bounds.keys())
		. contains_exactly_in_any_order(
			[
				World.Stat.FLOW_CELLS,
				World.Stat.SEP_PAIRS,
				World.Stat.LINE_CHECKS,
				World.Stat.TARGET_CANDIDATES,
				World.Stat.FOG_CELLS,
			]
		)
	)
	assert_int(bounds[World.Stat.FLOW_CELLS]).is_equal(512)
	assert_int(bounds[World.Stat.SEP_PAIRS]).is_equal(2400)
	assert_int(bounds[World.Stat.LINE_CHECKS]).is_equal(43)
	assert_int(bounds[World.Stat.TARGET_CANDIDATES]).is_equal(2742)
	assert_int(bounds[World.Stat.FOG_CELLS]).is_equal(9748)
	assert_int(PerfBounds.MEASURED_LINE_CHECKS).is_equal(34)
	assert_int(PerfBounds.MEASURED_TARGET_CANDIDATES).is_equal(2193)
	assert_int(PerfBounds.MEASURED_FOG_CELLS).is_equal(7798)
	# The two that come from the rules follow them.
	var other: Dictionary[int, int] = PerfBounds.cost_bounds(100, 4, 10)
	assert_int(other[World.Stat.FLOW_CELLS]).is_equal(100)
	assert_int(other[World.Stat.SEP_PAIRS]).is_equal(40)
	assert_int(other[World.Stat.FOG_CELLS]).is_equal(9748)


## A counter at its bound passes, one over it is named with its value and bound, several are all
## named, and the counters without a bound (projectile steps, compacted rows) never fail.
func test_a_counter_over_its_bound_is_named_and_one_on_it_is_not() -> void:
	var bounds: Dictionary[int, int] = PerfBounds.cost_bounds(512, 16, 150)
	var names: PackedStringArray = PerfReport.stat_names()
	var stats: PackedInt32Array = PackedInt32Array()
	stats.resize(World.Stat.size())
	assert_array(PerfBounds.cost_violations(stats, bounds)).is_empty()
	for stat: int in bounds:
		stats.fill(0)
		stats[stat] = bounds[stat]
		assert_array(PerfBounds.cost_violations(stats, bounds)).is_empty()
		stats[stat] = bounds[stat] + 1
		var found: Array[String] = PerfBounds.cost_violations(stats, bounds)
		assert_int(found.size()).is_equal(1)
		assert_str(found[0]).contains(names[stat]).contains(str(bounds[stat] + 1))
		assert_str(found[0]).contains(str(bounds[stat]))
	stats.fill(0)
	stats[World.Stat.PROJ_STEPS] = 1_000_000
	stats[World.Stat.ROWS_COMPACTED] = 1_000_000
	assert_array(PerfBounds.cost_violations(stats, bounds)).is_empty()
	stats[World.Stat.FLOW_CELLS] = 513
	stats[World.Stat.FOG_CELLS] = 9749
	assert_int(PerfBounds.cost_violations(stats, bounds).size()).is_equal(2)


## 150 units at tick 0 and no projectile overflow, exactly; alive_end and the projectile peak at
## most a quarter (rounded up: 18 and 7) from their pins on either side, and the first value past
## that named with its range.
func test_the_run_must_start_with_150_units_and_end_within_the_margin_of_its_pins() -> void:
	assert_int(PerfBounds.ARENA_UNITS).is_equal(150)
	assert_array(_load(150, 0, ALIVE_PIN, PROJ_PIN)).is_empty()
	assert_str(_only(_load(149, 0, ALIVE_PIN, PROJ_PIN))).contains("149 units")
	assert_str(_only(_load(151, 0, ALIVE_PIN, PROJ_PIN))).contains("151 units")
	assert_str(_only(_load(150, 1, ALIVE_PIN, PROJ_PIN))).contains("projectile_overflow")
	assert_array(_load(150, 0, ALIVE_PIN - 18, PROJ_PIN)).is_empty()
	assert_array(_load(150, 0, ALIVE_PIN + 18, PROJ_PIN)).is_empty()
	assert_array(_load(150, 0, ALIVE_PIN, PROJ_PIN - 7)).is_empty()
	assert_array(_load(150, 0, ALIVE_PIN, PROJ_PIN + 7)).is_empty()
	var low: String = _only(_load(150, 0, ALIVE_PIN - 19, PROJ_PIN))
	assert_str(low).contains("alive_end").contains("53..89")
	assert_str(_only(_load(150, 0, ALIVE_PIN + 19, PROJ_PIN))).contains("alive_end")
	var peak: String = _only(_load(150, 0, ALIVE_PIN, PROJ_PIN - 8))
	assert_str(peak).contains("projectile peak").contains("21..35")
	assert_str(_only(_load(150, 0, ALIVE_PIN, PROJ_PIN + 8))).contains("projectile peak")
	# A run with nothing alive and no shot fired is no arena: both pins catch it.
	assert_int(_load(150, 0, 0, 0).size()).is_equal(2)
	# The pins are a parameter: another pair moves the range with it.
	assert_array(PerfBounds.load_violations(150, 0, 100, 10, 100, 10)).is_empty()
	assert_int(PerfBounds.load_violations(150, 0, 71, 28, 100, 10).size()).is_equal(2)


## The static memory may grow by 64 KiB between tick 100 and tick 900 and no more; a shrink is
## fine; a reading of 0 at either tick in a debug build means the monitor is not live, or the run
## never reached that tick, and fails (a missing last reading is no shrink); a release build (no
## monitor) is not judged at all.
func test_static_memory_may_grow_by_64_kib_in_a_debug_build_and_is_not_judged_otherwise() -> void:
	assert_int(PerfBounds.MEMORY_FIRST_TICK).is_equal(100)
	assert_int(PerfBounds.MEMORY_LAST_TICK).is_equal(900)
	assert_int(PerfBounds.MEMORY_GROWTH_MAX).is_equal(65536)
	var first: int = 48_000_000
	assert_array(PerfBounds.memory_violations(first, first, true)).is_empty()
	assert_array(PerfBounds.memory_violations(first, first - 60_000, true)).is_empty()
	assert_array(PerfBounds.memory_violations(first, first + 65536, true)).is_empty()
	var found: Array[String] = PerfBounds.memory_violations(first, first + 65537, true)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("65537").contains("tick 100").contains("tick 900")
	found = PerfBounds.memory_violations(0, 0, true)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("MEMORY_STATIC reads 0 at tick 100 and 0 at tick 900")
	# One missing reading is enough, whichever tick it is: the last one missing is no shrink.
	found = PerfBounds.memory_violations(first, 0, true)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("reads %d at tick 100 and 0 at tick 900" % first)
	found = PerfBounds.memory_violations(0, first, true)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("reads 0 at tick 100 and %d at tick 900" % first)
	assert_int(PerfBounds.memory_violations(first, -1, true).size()).is_equal(1)
	assert_array(PerfBounds.memory_violations(first, 0, false)).is_empty()
	assert_array(PerfBounds.memory_violations(0, 0, false)).is_empty()
	assert_array(PerfBounds.memory_violations(first, first + 10_000_000, false)).is_empty()


## Run.bound_lines, which test_sim_perf.gd applies to the arena, passes the readings of a run to
## every bound above and nothing else, tried on a run made by hand that sits on all of them (each
## cost counter on its bound, the pins, 150 units, the memory unchanged): that run has no line, and
## each move over one bound gives exactly one line, so a bound that is left out of bound_lines, a
## reading taken from the wrong field and a memory check that is switched off show. The memory is
## judged in a debug build only, as the engine counts it there only.
func test_a_run_is_judged_by_every_bound_and_a_move_over_one_gives_one_line() -> void:
	var run: Run = _run_on_its_bounds()
	assert_array(run.bound_lines(ALIVE_PIN, PROJ_PIN)).is_empty()
	var bounds: Dictionary[int, int] = PerfBounds.cost_bounds(run.flow_budget, run.sep_scan, 150)
	var names: PackedStringArray = PerfReport.stat_names()
	for stat: int in bounds:
		run = _run_on_its_bounds()
		run.stats_max[stat] += 1
		assert_str(_only(run.bound_lines(ALIVE_PIN, PROJ_PIN))).contains(names[stat]).contains(
			"above"
		)
		run = _run_on_its_bounds()
		run.stats_max[stat] = 0
		assert_str(_only(run.bound_lines(ALIVE_PIN, PROJ_PIN))).contains(names[stat]).contains(
			"reads 0"
		)
	# The units also move the bound of the separation pairs, upwards, so the pairs stay inside it.
	run = _run_on_its_bounds()
	run.units += 1
	run.stats_max[World.Stat.SEP_PAIRS] = run.sep_scan * run.units
	assert_str(_only(run.bound_lines(ALIVE_PIN, PROJ_PIN))).contains("151 units")
	run = _run_on_its_bounds()
	run.overflow = 1
	assert_str(_only(run.bound_lines(ALIVE_PIN, PROJ_PIN))).contains("projectile_overflow")
	run = _run_on_its_bounds()
	run.alive_end = 0
	assert_str(_only(run.bound_lines(ALIVE_PIN, PROJ_PIN))).contains("alive_end")
	run = _run_on_its_bounds()
	run.proj_peak = 0
	assert_str(_only(run.bound_lines(ALIVE_PIN, PROJ_PIN))).contains("projectile peak")
	# The pins are the caller's: the same run is outside another pair.
	assert_int(_run_on_its_bounds().bound_lines(ALIVE_PIN + 40, PROJ_PIN).size()).is_equal(1)
	assert_int(_run_on_its_bounds().bound_lines(ALIVE_PIN, PROJ_PIN + 40).size()).is_equal(1)
	var judged: int = 1 if OS.is_debug_build() else 0
	run = _run_on_its_bounds()
	run.memory_last = run.memory_first + PerfBounds.MEMORY_GROWTH_MAX + 1
	assert_int(run.bound_lines(ALIVE_PIN, PROJ_PIN).size()).is_equal(judged)
	run = _run_on_its_bounds()
	run.memory_last = 0
	assert_int(run.bound_lines(ALIVE_PIN, PROJ_PIN).size()).is_equal(judged)
	run = _run_on_its_bounds()
	run.memory_first = 0
	assert_int(run.bound_lines(ALIVE_PIN, PROJ_PIN).size()).is_equal(judged)


## Run.static_memory, the reading that test_sim_perf.gd takes at tick 100 and tick 900, is the live
## static memory, so it falls when memory is released. A buffer of 1 MiB is allocated and filled,
## read, released and read again, and the reading falls by at least half of the buffer (the margin
## is for the engine's own small allocations in between; the fall measured is the buffer plus 32
## bytes). The high-water mark MEMORY_STATIC_MAX never falls and reads 0 here: it holds the peak of
## the whole process, so a run that keeps memory from tick 100 to tick 900 would read as no growth
## and pass the memory bound. Debug builds only: the engine has no monitor elsewhere.
func test_the_static_memory_reading_is_the_live_one_and_falls_when_memory_is_released() -> void:
	if not OS.is_debug_build():
		return
	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(HELD_BYTES)
	buffer.fill(1)
	var held: int = Run.static_memory()
	buffer = PackedByteArray()
	var released: int = held - Run.static_memory()
	assert_int(released).is_greater_equal(HELD_BYTES >> 1)


## A run that no match produced and that is inside every bound: 150 units, the rules of the arena
## (512 flow cells a tick, a separation scan of 16), every bounded counter on its bound, alive_end
## and the projectile peak on their pins and the static memory unchanged.
func _run_on_its_bounds() -> Run:
	var run: Run = Run.new()
	run.units = PerfBounds.ARENA_UNITS
	run.flow_budget = 512
	run.sep_scan = 16
	run.alive_end = ALIVE_PIN
	run.proj_peak = PROJ_PIN
	run.memory_first = 48_000_000
	run.memory_last = run.memory_first
	run.stats_max.resize(World.Stat.size())
	var bounds: Dictionary[int, int] = PerfBounds.cost_bounds(
		run.flow_budget, run.sep_scan, run.units
	)
	for stat: int in bounds:
		run.stats_max[stat] = bounds[stat]
	return run


func _load(units: int, overflow: int, alive_end: int, proj_peak: int) -> Array[String]:
	return PerfBounds.load_violations(units, overflow, alive_end, proj_peak, ALIVE_PIN, PROJ_PIN)


## The one line of `found`, which must hold exactly one.
func _only(found: Array[String]) -> String:
	assert_int(found.size()).is_equal(1)
	return found[0] if found.size() == 1 else ""
