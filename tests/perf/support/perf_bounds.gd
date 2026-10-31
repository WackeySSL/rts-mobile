extends RefCounted
## The deterministic bounds of the perf arena (plan P49a, ADR 0011 section 4, ADR 0012 section 4):
## what one tick may cost in World.stats, what the run must still be (150 units, no projectile
## overflow, a fight that is still going at the end) and how much static memory it may grow by.
## Pure: no clock, no World and no engine monitor; the caller reads those and passes the numbers.
## test_perf_bounds.gd pins every bound on hand-made numbers. Not a test suite.
##
## Who may move what (plan exception 3): a sim PR never raises a cost bound here. If a bound is
## exceeded, that PR stops and asks qa-engineer in its Requests section, because catching that rise
## is what the bounds are for; a legitimate rise (a new tick phase) is a qa-engineer PR with before
## and after numbers. The run-outcome pins (alive_end and the projectile peak) are not here: they
## are the first constants of test_sim_perf.gd, where the first sim PR that moves the arena run
## re-pins them with the same margin.

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
## The units the arena starts with: 30 tanks, 27 rifle and 18 rocket squads for each of two players.
const ARENA_UNITS: int = 150
## The margin on a measured value, in percent of it, rounded up: the cost bounds that no rule gives
## stand at the measured maximum plus this, and the run-outcome pins sit this far to either side.
const MARGIN_PERCENT: int = 25
## The maxima of the World.stats counters over the 900 ticks of the seed-42 arena with fog in the
## tick (PR #129, equal under both implementations): the per-tick maxima of line_checks,
## target_candidates and fog_cells. flow_cells (512) and sep_pairs (1,231) have a rule instead.
## The line checks follow the brief and the plan's list of P49a (34 plus the margin, 43), which is
## stricter than the "at most the moving units" of ADR 0011 section 4: engagement line checks are
## counted in LINE_CHECKS, so a change to who fires (P46b) is the likeliest to reach this bound.
## The ADR's wording is for the lead's next docs PR to bring in line with the pin.
const MEASURED_LINE_CHECKS: int = 34
const MEASURED_TARGET_CANDIDATES: int = 2193
const MEASURED_FOG_CELLS: int = 7798
## The maxima of the Phase 3 counters over the 900 ticks of the seed-42 base arena (plan P93, ADR
## 0021 section 2; equal under both implementations, because ECONOMY, PRODUCTION and MEMORY are
## GDScript phases): ore cells looked at, exit cells walked and last-seen checks in one tick. The
## arena has no building death, so MEMORY_CHECKS here is the MEMORY phase alone (28 building rows on
## the 600 ticks of a fog turn); a death in sight adds the in-sight drop's looks (LastSeen). They
## carry P49a's margin like the perf arena's measured maxima.
const MEASURED_ORE_SCANNED: int = 72
const MEASURED_EXIT_SCANNED: int = 3
const MEASURED_MEMORY_CHECKS: int = 28
## The two ticks at which Performance.MEMORY_STATIC is read, and how much it may have grown between
## them. The arena run does not grow it: the static memory of the 900 ticks through TickJob falls
## by 2.5 KB with the kernels and by 63.6 KB with the GDScript twins between tick 100 and tick 900
## (the rows of the dead units and the projectile slots in flight shrink), the same bytes in every
## run. The bound is 64 KiB of growth on top of that fall, so a run that keeps memory for each tick
## (a snapshot or a copy of a World array kept) is over it from about 85 bytes a tick with the
## kernels ((65,536 + 2,524) / 800 ticks) and from about 161 bytes a tick in GDScript-only code
## ((65,536 + 63,604) / 800), with room for the engine's own allocations to move the reading.
const MEMORY_FIRST_TICK: int = 100
const MEMORY_LAST_TICK: int = 900
const MEMORY_GROWTH_MAX: int = 65536

## `percent` percent of `measured`, rounded up (integer arithmetic, so no float moves it).
@warning_ignore("integer_division")
static func margin(measured: int, percent: int = MARGIN_PERCENT) -> int:
	return (measured * percent + 99) / 100


## `measured` plus its margin.
static func with_margin(measured: int, percent: int = MARGIN_PERCENT) -> int:
	return measured + margin(measured, percent)


## The bound of every World.Stat that is bounded, by the stat's index: the flow cells settled at
## most the budget of the rules, the separation pairs at most the scan length times the units, and
## the line checks, targeting candidates and fog cells stamped at most their measured maxima plus
## the margin. The other stats (projectile steps, compacted rows) have no cost bound here.
static func cost_bounds(
	flow_cells_per_tick: int, separation_scan: int, units: int
) -> Dictionary[int, int]:
	return {
		World.Stat.FLOW_CELLS: flow_cells_per_tick,
		World.Stat.SEP_PAIRS: separation_scan * units,
		World.Stat.LINE_CHECKS: with_margin(MEASURED_LINE_CHECKS),
		World.Stat.TARGET_CANDIDATES: with_margin(MEASURED_TARGET_CANDIDATES),
		World.Stat.FOG_CELLS: with_margin(MEASURED_FOG_CELLS),
	}


## The bound of each Phase 3 counter that the base arena bounds (plan P93): the measured maxima
## plus the margin. The three have no rule that bounds them, and the perf arena never moves them.
static func base_cost_bounds() -> Dictionary[int, int]:
	return {
		World.Stat.ORE_SCANNED: with_margin(MEASURED_ORE_SCANNED),
		World.Stat.EXIT_SCANNED: with_margin(MEASURED_EXIT_SCANNED),
		World.Stat.MEMORY_CHECKS: with_margin(MEASURED_MEMORY_CHECKS),
	}


## One line for each bounded stat whose maximum over a run is above its bound.
static func cost_violations(
	stats_max: PackedInt32Array, bounds: Dictionary[int, int]
) -> Array[String]:
	var found: Array[String] = []
	var names: PackedStringArray = PerfReport.stat_names()
	for stat: int in bounds:
		if stats_max[stat] > bounds[stat]:
			found.append(
				"%s %d is above its bound %d" % [names[stat], stats_max[stat], bounds[stat]]
			)
	return found


## The run itself: the unit count at tick 0 is `ARENA_UNITS`, no projectile overflowed, and
## `alive_end` and `proj_peak` are within the margin of their pins (`alive_pin` and `proj_pin`, the
## values measured when the arena run last changed). A balance change that empties the fight or
## stops the shooting would otherwise shrink the load unseen.
static func load_violations(
	units: int, overflow: int, alive_end: int, proj_peak: int, alive_pin: int, proj_pin: int
) -> Array[String]:
	var found: Array[String] = []
	if units != ARENA_UNITS:
		found.append("%d units at tick 0, not %d" % [units, ARENA_UNITS])
	if overflow != 0:
		found.append("projectile_overflow is %d, not 0" % overflow)
	_check_pin(found, "alive_end", alive_end, alive_pin)
	_check_pin(found, "projectile peak", proj_peak, proj_pin)
	return found


## The growth of Performance.MEMORY_STATIC from `first` (read at MEMORY_FIRST_TICK) to `last` (at
## MEMORY_LAST_TICK). The monitor exists in debug builds only, so a release build (`debug_build`
## false) is not judged; in a debug build a reading of 0 at either tick means the monitor is not
## live, or the run never reached the tick, and fails (a missing `last` would otherwise read as a
## shrink and pass).
static func memory_violations(first: int, last: int, debug_build: bool) -> Array[String]:
	var found: Array[String] = []
	if not debug_build:
		return found
	if first <= 0 or last <= 0:
		found.append(
			(
				"MEMORY_STATIC reads %d at tick %d and %d at tick %d in a debug build"
				% [first, MEMORY_FIRST_TICK, last, MEMORY_LAST_TICK]
			)
		)
	elif last - first > MEMORY_GROWTH_MAX:
		found.append(
			(
				"static memory grew by %d bytes from tick %d to tick %d, above %d"
				% [last - first, MEMORY_FIRST_TICK, MEMORY_LAST_TICK, MEMORY_GROWTH_MAX]
			)
		)
	return found


## Adds a line to `found` when `value` is further than the margin of `pin` from it.
static func _check_pin(found: Array[String], label: String, value: int, pin: int) -> void:
	var low: int = pin - margin(pin)
	var high: int = pin + margin(pin)
	if value < low or value > high:
		found.append(
			(
				"%s %d is outside %d..%d (%d plus or minus %d)"
				% [label, value, low, high, pin, margin(pin)]
			)
		)
