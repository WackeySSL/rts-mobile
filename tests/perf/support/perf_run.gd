extends RefCounted
## What one match of the perf arena leaves (plan P38p and P49a): the tick times (the job, and
## Sim.step inside it), the per-phase sums, the World.stats maxima, the checkpoints and the readings
## that the deterministic bounds judge (bound_lines). test_sim_perf.gd fills it from the arena and
## test_perf_bounds.gd builds it by hand. It sits in a file of its own, because test_sim_perf.gd
## reached gdlint's limit of 1,000 lines. Not a test suite.

const PerfBounds: GDScript = preload("res://tests/perf/support/perf_bounds.gd")
const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")

## TickJob.run() of each tick, in ms (the snapshot's job_usec), and Sim.step alone (step_usec).
var tick_ms: PackedFloat64Array = PackedFloat64Array()
var step_ms: PackedFloat64Array = PackedFloat64Array()
## The COMMANDS phase of each tick in microseconds, and the replay's command log, which says
## which tick ordered the most units.
var commands_usec: PackedInt64Array = PackedInt64Array()
var order_log: PackedInt32Array = PackedInt32Array()
var phase_usec: PackedInt64Array = PackedInt64Array()
var stats_max: PackedInt32Array = PackedInt32Array()
var units: int = 0
var alive_end: int = 0
var proj_peak: int = 0
var overflow: int = 0
## The rules the World ran with that bound the cost counters.
var flow_budget: int = 0
var sep_scan: int = 0
## Performance.MEMORY_STATIC after tick PerfBounds.MEMORY_FIRST_TICK and MEMORY_LAST_TICK.
var memory_first: int = 0
var memory_last: int = 0
## The ticks whose snapshot slid from the step before: prev_pos_x other than pos_x, and equal to the
## positions the World had before that tick's step (the last published snapshot was `previous`).
var slid_ticks: int = 0
## Whether tick 0's snapshot slid from the start positions (the snapshot published before the loop).
var first_slid: bool = false
## The phases that ran in C++ (World.native_phases after the last tick): 0 for a GDScript run.
var native_mask: int = 0
## pos_x then pos_y of every unit, before the first tick and after the last.
var start_pos: PackedInt32Array = PackedInt32Array()
var final_pos: PackedInt32Array = PackedInt32Array()
var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
var final_hash: int = 0


## Performance.MEMORY_STATIC in bytes, the live reading that the memory bound judges: the engine
## counts it in debug builds only, 0 otherwise. Not MEMORY_STATIC_MAX, which keeps the peak of the
## whole process (63.1 MB at tick 100 and at tick 900 of the arena, set before it starts, against a
## live reading of 48.2 MB) and so reads a run that keeps memory as no growth. test_perf_bounds.gd
## pins it on a buffer that is held and released.
static func static_memory() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))


## The lines that say this run is outside the deterministic bounds of plan P49a: a cost counter
## above its bound or reading 0, the run itself (units, overflow, alive_end and the projectile peak
## against their pins `alive_pin` and `proj_pin`) and the growth of the static memory, which only a
## debug build judges. Empty when the run is inside all of them.
func bound_lines(alive_pin: int, proj_pin: int) -> Array[String]:
	var bounds: Dictionary[int, int] = PerfBounds.cost_bounds(flow_budget, sep_scan, units)
	var lines: Array[String] = PerfBounds.cost_violations(stats_max, bounds)
	for stat: int in bounds:
		if stats_max[stat] <= 0:
			lines.append("%s reads 0" % PerfReport.stat_names()[stat])
	lines.append_array(
		PerfBounds.load_violations(units, overflow, alive_end, proj_peak, alive_pin, proj_pin)
	)
	lines.append_array(PerfBounds.memory_violations(memory_first, memory_last, OS.is_debug_build()))
	return lines
