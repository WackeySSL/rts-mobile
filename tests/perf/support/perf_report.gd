extends RefCounted
## The numbers and the text of the perf harness (plan P38p, ADR 0011 section 4, ADR 0012 section
## 4): statistics over tick times, the best of several runs, the phone estimates and the `PERF`
## line and `reports/perf/sim.json` made from one report dictionary, so the two always agree. Pure:
## no clock, no World. test_perf_report.gd pins it with fake samples. Not a test suite.

## The costliest window of this many consecutive ticks is `worst15_ms` (one second of game time).
const WINDOW_TICKS: int = 15
## The statistics of one run, in the order of the `PERF` line.
const STAT_KEYS: Array[String] = ["mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms", "worst15_ms"]
## The implementation key of the second `PERF` line (plan P38pn, ADR 0013 section 15): `impl=native`
## sits right after `PERF sim`, and the other keys follow in the order of LINE_KEYS. The GDScript
## line (P38p) has no impl key and keeps its format exactly, because P51 parses both lines.
const IMPL_KEY: String = "impl"
const IMPL_NATIVE: String = "native"
## The scalar keys of the `PERF` line in print order; `stats_max=`, `phases=` and `hash=` follow.
const LINE_KEYS: Array[String] = [
	"units",
	"ticks",
	"runs",
	"mean_ms",
	"p50_ms",
	"p95_ms",
	"p99_ms",
	"max_ms",
	"worst15_ms",
	"ticks_per_s",
	"ref_ms",
	"est_phone_mean_ms",
	"est_phone_p95_ms",
	"alive_end",
	"proj_peak",
	"projectile_overflow",
]
## What the caller measures besides the timing: finish() copies these into the report.
const FACT_KEYS: Array[String] = [
	"units", "ticks", "runs", "ref_ms", "alive_end", "proj_peak", "projectile_overflow", "hash"
]
## The sub-lines of plan P49a, printed beside the `PERF` lines: `STEP sim` holds the statistics of
## Sim.step alone (the part of TickJob.run() before the capture and the hash, one line for each
## implementation, `impl=native` after the head on the native one) and the two `WATCH sim` lines
## are the watch items of ADR 0013 section 15, with no bound. None of them starts with `PERF `, so
## the two `PERF` lines that P51 selects stay the only ones it copies.
const STEP_HEAD: String = "STEP sim"
const STEP_KEYS: Array[String] = ["mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms"]
const COMMANDS_HEAD: String = "WATCH sim commands"
const OVERHEAD_HEAD: String = "WATCH sim job_minus_step"
## ADR 0011 section 4: before P49 the only limit on the clock is a catastrophic cap on the best
## mean tick. The wall-clock budget (P49b's budget.cfg) replaces it.
const CATASTROPHIC_MEAN_MS: float = 20.0


## Mean, p50, p95, p99, max and the worst 15-tick window sum of one run's tick times in ms.
static func run_stats(tick_ms: PackedFloat64Array) -> Dictionary:
	var sorted: PackedFloat64Array = tick_ms.duplicate()
	sorted.sort()
	return {
		"mean_ms": PerfStats.mean(tick_ms),
		"p50_ms": PerfStats.percentile(sorted, 50),
		"p95_ms": PerfStats.percentile(sorted, 95),
		"p99_ms": PerfStats.percentile(sorted, 99),
		"max_ms": PerfStats.percentile(sorted, 100),
		"worst15_ms": PerfStats.worst_window_sum(tick_ms, WINDOW_TICKS),
	}


## The best of the runs (ADR 0011 section 4: the minimum over the runs): each statistic's smallest
## value, taken separately, so the best p95 may come from another run than the best mean.
static func best_of(runs: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for key: String in STAT_KEYS:
		var smallest: float = INF
		for run: Dictionary in runs:
			smallest = minf(smallest, run[key])
		best[key] = smallest if not runs.is_empty() else 0.0
	return best


## True when the report's best mean tick is above `cap_ms`. Only the mean is capped: a slow tail
## shows on the line and fails nothing before P49.
static func over_cap(report: Dictionary, cap_ms: float) -> bool:
	return report["mean_ms"] > cap_ms


## Adds one tick's phase times in microseconds (TimingProbe.phase_usec) to the running sums.
static func add_phases(sums: PackedInt64Array, tick_usec: PackedInt64Array) -> void:
	for phase: int in mini(sums.size(), tick_usec.size()):
		sums[phase] += tick_usec[phase]


## The smallest sample, or 0 for none (ref_ms is the smallest timed call of the reference loop).
static func smallest(samples: PackedInt64Array) -> int:
	if samples.is_empty():
		return 0
	var low: int = samples[0]
	for sample: int in samples:
		low = mini(low, sample)
	return low


## The mean ms per tick of every phase, from the sums in microseconds over `ticks` ticks.
static func phase_means_ms(phase_usec_sum: PackedInt64Array, ticks: int) -> PackedFloat64Array:
	var means: PackedFloat64Array = PackedFloat64Array()
	means.resize(phase_usec_sum.size())
	for phase: int in phase_usec_sum.size():
		means[phase] = phase_usec_sum[phase] / 1000.0 / maxf(ticks, 1)
	return means


## For each phase the smallest of the runs' means, like best_of() for the statistics.
static func best_phases(runs: Array[PackedFloat64Array]) -> PackedFloat64Array:
	var best: PackedFloat64Array = PackedFloat64Array()
	best.resize(SimProbe.Phase.COUNT)
	for phase: int in SimProbe.Phase.COUNT:
		var smallest: float = INF
		for run: PackedFloat64Array in runs:
			smallest = minf(smallest, run[phase])
		best[phase] = smallest if not runs.is_empty() else 0.0
	return best


## Raises each entry of `maxima` to the matching entry of `stats` (World.stats of one tick) where
## that is larger.
static func raise_maxima(maxima: PackedInt32Array, stats: PackedInt32Array) -> void:
	for index: int in mini(maxima.size(), stats.size()):
		maxima[index] = maxi(maxima[index], stats[index])


## The projectile slots in use in `world`: a free slot holds id 0 (a prepared world).
static func live_projectiles(world: World) -> int:
	var ids: PackedInt32Array = world.proj_id
	return ids.size() - ids.count(0)


## The names of the World.stats indexes in index order, lower case.
static func stat_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for key: String in World.Stat.keys():
		names.append(key.to_lower())
	return names


## The report: the `facts` (FACT_KEYS), the best statistics, ticks per second, the phone estimates
## from the gate (mean x ci_ratio_mean, p95 x ci_ratio_p95, ADR 0012 section 4), the per-phase
## means and the World.stats maxima. Every float is rounded to a thousandth of a ms, the precision
## the line prints, so the line, the JSON and the checks read the same numbers. `native` is the
## report of the run with the kernels attached (ADR 0013 section 15): its estimates read
## ci_ratio_native_mean and ci_ratio_native_p95 instead, and it carries `impl` = IMPL_NATIVE, which
## line() prints.
static func finish(
	facts: Dictionary,
	best: Dictionary,
	phases_ms: PackedFloat64Array,
	stats_max: PackedInt32Array,
	gate: PerfGateDef,
	native: bool = false
) -> Dictionary:
	var report: Dictionary = {}
	for key: String in FACT_KEYS:
		report[key] = facts[key]
	report["ref_ms"] = _round(facts["ref_ms"])
	for key: String in STAT_KEYS:
		report[key] = _round(best[key])
	report["ticks_per_s"] = _round(1000.0 / best["mean_ms"]) if best["mean_ms"] > 0.0 else 0.0
	var ratio_mean: float = gate.ci_ratio_native_mean if native else gate.ci_ratio_mean
	var ratio_p95: float = gate.ci_ratio_native_p95 if native else gate.ci_ratio_p95
	report["est_phone_mean_ms"] = _round(best["mean_ms"] * ratio_mean)
	report["est_phone_p95_ms"] = _round(best["p95_ms"] * ratio_p95)
	if native:
		report[IMPL_KEY] = IMPL_NATIVE
	var phases: Dictionary = {}
	for phase: int in SimProbe.Phase.COUNT:
		phases[SimProbe.PHASE_NAMES[phase]] = _round(phases_ms[phase])
	report["phases"] = phases
	var maxima: Dictionary = {}
	var names: PackedStringArray = stat_names()
	for index: int in names.size():
		maxima[names[index]] = stats_max[index]
	report["stats_max"] = maxima
	return report


## The one `PERF` line of ADR 0011 section 4 with ref_ms, the phone estimates and the stats maxima:
## `PERF sim units=150 ticks=900 runs=3 mean_ms=... phases=commands:0.050,flow:0.000,... hash=...`.
## A report with an `impl` (finish(..., true)) prints `impl=native` right after `PERF sim`.
static func line(report: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray(["PERF sim"])
	if report.has(IMPL_KEY):
		parts.append("%s=%s" % [IMPL_KEY, report[IMPL_KEY]])
	for key: String in LINE_KEYS:
		parts.append("%s=%s" % [key, _text(report[key])])
	parts.append("stats_max=" + _pairs(report["stats_max"]))
	parts.append("phases=" + _pairs(report["phases"]))
	parts.append("hash=" + report["hash"])
	return " ".join(parts)


## The same numbers as JSON, keys sorted, for reports/perf/sim.json.
static func json(report: Dictionary) -> String:
	return JSON.stringify(report, "\t") + "\n"


## The tick that orders the most units, from a replay's command log (Replay.commands, the layout
## of Command.encode): (tick, units), the units counted over all the commands of that tick; the
## lowest tick on a tie, and (-1, 0) for a log with no command or no unit. A log that stops
## in the middle of a command is read as far as it goes.
static func largest_order_tick(log: PackedInt32Array) -> Vector2i:
	var units_at: Dictionary[int, int] = {}
	var scratch: Command = Command.new()
	var at: int = 0
	while at < log.size():
		var end: int = Command.decode(log, at, scratch)
		if end < 0:
			break
		units_at[scratch.tick] = units_at.get(scratch.tick, 0) + scratch.unit_ids.size()
		at = end
	var best: Vector2i = Vector2i(-1, 0)
	for tick: int in units_at:
		if units_at[tick] > best.y or (units_at[tick] == best.y and best.y > 0 and tick < best.x):
			best = Vector2i(tick, units_at[tick])
	return best


## The time of each tick of a run that TickJob.run() spent outside Sim.step (the capture, the timing
## copies and, on a checkpoint tick, the state hash), in ms: `job_ms` minus `step_ms`, for the ticks
## that are checkpoints (the step that makes the world tick a multiple of Replay.CHECKPOINT_PERIOD)
## when `checkpoint` is true, and for all the others when it is false. Index i is the step that
## ends on tick i + 1.
static func job_minus_step_ms(
	job_ms: PackedFloat64Array, step_ms: PackedFloat64Array, checkpoint: bool
) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	for index: int in mini(job_ms.size(), step_ms.size()):
		var is_checkpoint: bool = (index + 1) % Replay.CHECKPOINT_PERIOD == 0
		if is_checkpoint == checkpoint:
			out.append(job_ms[index] - step_ms[index])
	return out


## The nearest-rank 95th percentile of `values` in any order (0.0 for none).
static func p95(values: PackedFloat64Array) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return PerfStats.percentile(sorted, 95)


## One sub-line: `head`, then `impl=native` for the native run, then `key=value` for each entry of
## `values` in its order (floats with three decimals, like the `PERF` line).
static func sub_line(head: String, values: Dictionary, native: bool) -> String:
	var parts: PackedStringArray = PackedStringArray([head])
	if native:
		parts.append("%s=%s" % [IMPL_KEY, IMPL_NATIVE])
	for key: String in values:
		parts.append("%s=%s" % [key, _text(values[key])])
	return " ".join(parts)


static func _pairs(values: Dictionary) -> String:
	var pairs: PackedStringArray = PackedStringArray()
	for key: String in values:
		pairs.append("%s:%s" % [key, _text(values[key])])
	return ",".join(pairs)


static func _text(value: Variant) -> String:
	return "%.3f" % value if typeof(value) == TYPE_FLOAT else str(value)


static func _round(value: float) -> float:
	return snappedf(value, 0.001)
