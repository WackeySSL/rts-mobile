extends GdUnitTestSuite
## The deterministic bounds of the perf arena (plan P49a), pinned on hand-made numbers:
## tests/perf/support/perf_bounds.gd holds them, test_sim_perf.gd applies them to the real arena.
## Every bound is tried at its edge: the value on the bound passes, the value one over it is named.
## The literals here are the plan's numbers; a sim PR never changes them (plan exception 3), so a
## change to perf_bounds.gd shows up as a change to this file as well.

const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
## The pins of test_sim_perf.gd, as the load cases use them: any pair will do for the edges.
const ALIVE_PIN: int = 71
const PROJ_PIN: int = 28


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
## fine; a reading of 0 in a debug build means the monitor is not live and fails; a release build
## (no monitor) is not judged at all.
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
	assert_str(found[0]).contains("MEMORY_STATIC reads 0")
	assert_array(PerfBounds.memory_violations(0, 0, false)).is_empty()
	assert_array(PerfBounds.memory_violations(first, first + 10_000_000, false)).is_empty()


func _load(units: int, overflow: int, alive_end: int, proj_peak: int) -> Array[String]:
	return PerfBounds.load_violations(units, overflow, alive_end, proj_peak, ALIVE_PIN, PROJ_PIN)


## The one line of `found`, which must hold exactly one.
func _only(found: Array[String]) -> String:
	assert_int(found.size()).is_equal(1)
	return found[0] if found.size() == 1 else ""
