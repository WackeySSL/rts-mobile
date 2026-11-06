class_name PerfCard
extends RefCounted
## The text of the perf card (plan P184, split out of PerfHud): the verdict rows and the rows
## without a verdict, their keys, and the lines the card shows over `hud.summary()`. It reads the
## hud's gate, run and preflight state and holds none of its own. The summary itself, the samples
## and the buttons stay in PerfHud.

const PASS: String = "PASS"
const FAIL: String = "FAIL"
const SYNC: String = "SYNC"
const WORKER: String = "WORKER"
## The self-check seam's results (ADR 0013 section 3): the 60-tick lockstep of the seed-42 arena.
const SELF_CHECK_MATCH: String = "match"
const SELF_CHECK_MISMATCH: String = "mismatch"
const SELF_CHECK_NOT_RUN: String = "not run"
const SELF_CHECK_TICKS: int = 60

## The verdict rows that compare one summary key with one PerfGateDef field: the row's name, the
## key judged, the field, the unit printed, and whether the key must be at least the field (else at
## most).
const ROWS: Array = [
	["heavy_frames_min", "heavy_frames", "heavy_frames_min", "frames", true],
	["dropped_pct_max", "dropped_pct", "dropped_pct_max", "% of frames", false],
	["heavy_dropped_pct", "heavy_dropped_pct", "dropped_pct_max", "% of heavy frames", false],
	["cadence_pct_min", "cadence_pct", "cadence_pct_min", "% cadence", true],
	["heavy_cadence_pct", "heavy_cadence_pct", "cadence_pct_min", "% heavy cadence", true],
	["hitches_max", "heavy_hitches", "hitches_max", "heavy hitches", false],
	["work_p95_ms", "work_p95_norm_ms", "work_p95_ms", "ms normalised", false],
	["work_tick_p95_ms", "work_tick_p95_norm_ms", "work_tick_p95_ms", "ms normalised", false],
	["sim_p95_ms", "job_p95_ms", "sim_p95_ms", "ms raw job p95", false],
	["job_p99_ms", "job_p99_ms", "job_p99_ms", "ms raw job p99", false],
	["draw_calls_max", "draw_calls_p95", "draw_calls_max", "calls p95", false],
]
## The card's rows without a verdict (ADR 0014 section 4's pacing and CPU rows, the job rows and
## ADR 0013 section 15's four keys): a format and the summary keys it prints, in order. Raw and
## normalised values sit side by side.
const CARD_ROWS: Array = [
	[
		"refresh %.2f to %.2f Hz | P %.2f ms | dropped above %.2f ms",
		"refresh_hz_start",
		"refresh_hz_end",
		"period_ms",
		"drop_ms",
	],
	[
		"intervals p50 %.1f p95 %.1f p99 %.1f max %.1f ms | extra slots %s | jitter %.1f %%",
		"frame_p50_ms",
		"frame_p95_ms",
		"frame_p99_ms",
		"frame_max_ms",
		"extra_slots",
		"jitter_pct",
	],
	[
		"dropped %d (heavy %d) | hitches %d (heavy %d)",
		"dropped",
		"heavy_dropped",
		"hitches",
		"heavy_hitches",
	],
	[
		"ref peak %.1f us (p95 %.1f) | speed main %.0f %%, tick %.0f %%, fog %.0f %%",
		"ref_peak_us",
		"ref_peak_p95_us",
		"speed_main_pct",
		"speed_tick_pct",
		"speed_fog_pct",
	],
	[
		(
			"work p95 raw / normalised ms: heavy %.2f / %.2f, publish %.2f / %.2f, other %.2f / %.2f, "
			+ "fog %.2f / %.2f"
		),
		"work_p95_ms",
		"work_p95_norm_ms",
		"work_tick_p95_ms",
		"work_tick_p95_norm_ms",
		"work_other_p95_ms",
		"work_other_p95_norm_ms",
		"fog_update_p95_ms",
		"fog_update_p95_norm_ms",
	],
	[
		"job ms mean %.2f p50 %.2f p95 %.2f p99 %.2f max %.2f | latency max %d us",
		"job_mean_ms",
		"job_p50_ms",
		"job_p95_ms",
		"job_p99_ms",
		"job_max_ms",
		"latency_usec_max",
	],
	[
		(
			"Sim.step ms p50 %.2f p95 %.2f max %.2f | flow slice p95 %.2f ms | "
			+ "render CPU p95 %.2f ms"
		),
		"tick_p50_ms",
		"tick_p95_ms",
		"tick_max_ms",
		"flow_slice_p95_ms",
		"render_cpu_p95_ms",
	],
	[
		"p95 ms without checkpoint ticks: job %.2f | job minus step: checkpoint %.2f, other %.2f",
		"job_p95_noncp_ms",
		"job_minus_step_p95_cp_ms",
		"job_minus_step_p95_noncp_ms",
	],
	["atlas bake %.1f ms | page %s (no verdict)", "atlas_bake_ms", "atlas_page"],
	["%s | %s | %s | screen %s | zoom %.2f", "model", "os", "engine", "screen", "zoom"],
	["last hash %s | units alive %d", "hash_hex", "alive"],
]
## Rows that fail without samples of their own (a missing measurement never passes): the row's name
## and the summary key that counts its samples. The publish frames of the heavy window are a class
## apart, so a run in which no frame published leaves the window full and the class empty. The job
## rows read published ticks: frames alone leave them empty.
const NEEDS: Dictionary = {
	"work_tick_p95_ms": "heavy_publish_frames", "sim_p95_ms": "job_ticks", "job_p99_ms": "job_ticks"
}

var hud: PerfHud


func _init(of: PerfHud) -> void:
	hud = of


## The card's lines: the run, the build and mode; the verdict lines; the rows without a verdict
## (CARD_ROWS, the implementation and the four keys of ADR 0013 section 15, `held_ticks`); GATE
## last.
func card_lines() -> PackedStringArray:
	var s: Dictionary = hud.summary()
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		(
			"PERF run %d | %s | %s build | %s"
			% [hud._runs, s["tick_mode"], hud._build(), hud.layer_mode]
		)
	)
	lines.append_array(PackedStringArray(s["verdicts"]))
	lines.append("held_ticks %d (no verdict)" % hud.held_ticks)
	var lockstep: String = "not run"
	if s["self_check"] != SELF_CHECK_NOT_RUN:
		lockstep = (
			"%s (%d ticks)"
			% ["yes" if s["self_check"] == SELF_CHECK_MATCH else "NO", SELF_CHECK_TICKS]
		)
	lines.append(_impl_line(s, lockstep))
	for row: Array in CARD_ROWS:
		lines.append(row[0] % row.slice(1).map(func(key: String) -> Variant: return s[key]))
	if hud.arena_kind == PerfBases.ARENA_BASES:
		lines.append(PerfBases.calls_line(s["draw_calls_p95"]))
	lines.append(_phase_line("phase means per tick", s["phases_ms"]))
	lines.append(_phase_line("p95 per phase without checkpoint ticks", s["phases_p95_noncp_ms"]))
	lines.append("GATE: %s" % (PASS if s["gate_pass"] else FAIL))
	return lines


## ADR 0013 section 3's line: the implementation that runs, for the library its build and phases,
## and the self-check text.
func _impl_line(s: Dictionary, lockstep: String) -> String:
	var impl: String = "gdscript"
	if hud._sim_impl == MatchRunner.SimImpl.NATIVE:
		var phases: String = ", ".join(PackedStringArray(s["native_phases"]))
		impl = "native (%s, phases %s)" % [s["native_build"], phases if phases != "" else "none"]
	return "sim impl: %s | C++ matches GDScript: %s" % [impl, lockstep]


## One phase value per phase, in id order: `title` and `values` (ms).
func _phase_line(title: String, values: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for phase: int in SimProbe.Phase.COUNT:
		parts.append("%s %.2f" % [SimProbe.PHASE_NAMES[phase], values[phase]])
	return "%s (ms): %s" % [title, ", ".join(parts)]


## The verdict lines (ADR 0012 section 4, ADR 0014 sections 1 and 3) over a summary: INVALID first,
## the table's rows (pacing on the raw intervals, the main-thread CPU limits on the normalised
## values, the worker limits on the raw job times), late ticks for a worker run only, the fog
## update (none sampled fails: the measurement is missing), the build, the implementation and the
## golden hashes.
func verdicts(s: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for reason: String in s["invalid_reasons"]:
		rows.append("INVALID: %s" % reason)
	for row: Array in ROWS:
		var needs: String = NEEDS.get(row[0], "")
		if needs != "" and s[needs] == 0:
			rows.append(_check(row[0], false, "no %s" % needs))
		else:
			rows.append(_judge(row[0], s[row[1]], hud.gate.get(row[2]), row[3], row[4]))
	if s["tick_mode"] == WORKER:
		rows.append(_judge("late_ticks_max", hud.late_ticks, hud.gate.late_ticks_max, "late ticks"))
	else:
		rows.append("late_ticks_max: n/a (SYNC: late_ticks counts inline ticks)")
	var fog: float = s["fog_update_p95_norm_ms"]
	var fog_ok: bool = s["fog_updates"] > 0 and fog <= hud.gate.fog_update_p95_ms
	var fog_text: String = "%.2f ms normalised, %d updates, limit %.2f"
	fog_text = fog_text % [fog, s["fog_updates"], hud.gate.fog_update_p95_ms]
	rows.append(_check("fog_update_p95_ms", fog_ok, fog_text))
	rows.append(
		_check(
			"build", not (hud.gate.release_only and hud.debug_build), "%s template" % hud._build()
		)
	)
	rows.append(_impl_row())
	rows.append(_golden_row())
	return rows


## `impl` (ADR 0013 section 3), like `build` a verdict that fails the gate alone. Android needs the
## library: the implementation that runs must be NATIVE and its self-check a match. Elsewhere the
## twins are allowed (the web runs them), so the line is n/a.
func _impl_row() -> String:
	if hud.os_name != MatchRunner.OS_ANDROID:
		return "impl: n/a (only Android requires the library)"
	if hud._sim_impl != MatchRunner.SimImpl.NATIVE:
		return _check("impl", false, "gdscript")
	var matched: bool = hud._self_check_result == SELF_CHECK_MATCH
	return _check("impl", matched, "self-check %s" % hud._self_check_result)


## `golden_hashes`: MATCH, or MISMATCH with the first differing tick; no golden checkpoint to
## compare never passes.
func _golden_row() -> String:
	var golden: Dictionary = hud.golden_result()
	var detail: String = "no golden checkpoint up to tick %d" % hud.run_ticks
	if golden["tick"] >= 0:
		detail = (
			"MISMATCH at tick %d, got %s, golden %s"
			% [golden["tick"], golden["got"], golden["want"]]
		)
	elif golden["checked"] > 0:
		detail = "MATCH, %d checkpoints" % golden["checked"]
	if not golden["match"]:
		detail += PerfBases.fields(hud.arena_kind)
	return _check("golden_hashes", golden["match"], detail)


func _check(name: String, ok: bool, detail: String) -> String:
	return "%s: %s (%s)" % [name, PASS if ok else FAIL, detail]


func _judge(name: String, value: float, limit: float, unit: String, lower: bool = false) -> String:
	var ok: bool = value >= limit if lower else value <= limit
	return _check(name, ok, "%.2f %s, limit %.2f" % [value, unit, limit])


static func failed(line: String) -> bool:
	return line.contains(": %s (" % FAIL)
