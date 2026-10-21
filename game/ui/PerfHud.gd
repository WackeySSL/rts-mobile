class_name PerfHud
extends PanelContainer
## The perf card (plan P50a and P50a2; ADR 0012 section 4, ADR 0013 sections 3 and 15, ADR 0014):
## one run of `run_ticks` published ticks, the samples it takes on the main thread, `summary()`, the
## verdicts of a PerfGateDef and the card that shows them. A run keeps one row per frame and one per
## published tick, read from `runner.snapshot` only (ADR 0012 section 3, never the World, the loop
## or the replay). Main-thread CPU verdicts use ADR 0014's per-frame normalisation
## (RefLoop.normalised_p95), worker verdicts stay raw. Tests feed record_frame() and
## record_snapshot(); the live path feeds them from `frame_post_draw` and `ticked`. The card is
## hidden while a run records, so it adds no draw call to a measured frame; at `run_ticks` it shows
## and pauses the runner. Put it in a SafeAreaMargin (a full-rect child of a CanvasLayer, as the HUD
## roots are): it fills what that margin leaves, so it lies inside the safe area at any size, and
## its text scrolls. Its look is the inherited theme's (`game/ui/theme.tres`, the `PerfCard`
## variation). P50a3 adds the copy report and "Run again"; P50b the scene that sets the seams below.

const PASS: String = "PASS"
const FAIL: String = "FAIL"
const SYNC: String = "SYNC"
const WORKER: String = "WORKER"
## Why a run is INVALID (a measurement fault, never a verdict): a preflight refused with a job in
## flight; the app paused or lost focus; ADR 0014 section 2's refresh and median rules; ADR 0012
## section 4's monitors that read 0 (a release template compiles them out).
const REASON_JOB_IN_FLIGHT: String = "preflight_job_in_flight"
const REASON_APP_PAUSED: String = "app_paused"
const REASON_REFRESH_CHANGED: String = "refresh_changed"
const REASON_REFRESH_BELOW_CAP: String = "refresh_below_max_fps"
const REASON_MEDIAN_BELOW_PERIOD: String = "median_below_period"
const REASON_NO_DRAW_CALLS: String = "draw_calls_p95_zero"
const REASON_NO_RENDER_CPU: String = "render_cpu_p95_zero"
## The self-check seam's results (ADR 0013 section 3): the 60-tick lockstep of the seed-42 arena.
const SELF_CHECK_MATCH: String = "match"
const SELF_CHECK_MISMATCH: String = "mismatch"
const SELF_CHECK_NOT_RUN: String = "not run"
const SELF_CHECK_SEED: int = 42
const SELF_CHECK_TICKS: int = 60
const ARENA: String = "res://data/scenarios/perf_arena.tres"
## A checkpoint hash is kept at every published tick this divides (the golden ticks).
const CHECKPOINT_EVERY: int = 150
## The card's look is this variation of the theme; its text is the theme's Label, a HUD number the
## header's.
const CARD_VARIATION: StringName = &"PerfCard"
const HEADER_VARIATION: StringName = &"NumberLabel"
const GAP_DP: float = 8.0
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

@export var runner: MatchRunner
@export var gate: PerfGateDef = PerfGateDef.new()
@export var run_ticks: int = 900

## Printed on the card and in the summary; P50b sets them.
var layer_mode: String = "all"
var zoom: float = 1.0
## Seams: clock (us), ref_step (one reference run), refresh_source (the panel rate in Hz, -1
## headless), max_fps_source, burst_step (the kept second half of a burst, in us), render_source
## (the viewport's render CPU time of the frame just drawn, in ms: 0 headless) and calls_source
## (its draw calls: 0 headless). P50b sets the last two: rigs_source (rows shown and inside the
## camera now) and fog_source (the fog layer's update time in us when it uploaded since the last
## call, else -1: one FogLayer.upload_count() rise each). Preflight seams: self_check_step (the
## 60-tick lockstep, a SELF_CHECK_ text) runs before burst_step; kernels_source gives the library's
## kernels or null; os_name is the platform the `impl` verdict judges.
var clock: Callable = Time.get_ticks_usec
var ref_step: Callable = RefLoop.run
var refresh_source: Callable = DisplayServer.screen_get_refresh_rate
var max_fps_source: Callable = Engine.get_max_fps
var burst_step: Callable = _burst
var self_check_step: Callable = _run_self_check
var kernels_source: Callable = NativeKernels.create
var os_name: String = OS.get_name()
var render_source: Callable = _render_ms
var calls_source: Callable = _draw_calls
var rigs_source: Callable = func() -> int: return 0
var fog_source: Callable = func() -> int: return -1
## The build the verdict `build` judges; a release template is false.
var debug_build: bool = OS.is_debug_build()
## The runner's counts and resolved mode, copied at each publish. late_ticks and latency_usec_max
## also count inline ticks, so late_ticks_max is judged for a worker run only.
var late_ticks: int = 0
var held_ticks: int = 0
var latency_usec_max: int = 0
var worker_mode: bool = false
## The panel rate at the start of the run and (set when the run ends) at its end.
var refresh_hz_start: float = 0.0
var refresh_hz_end: float = 0.0
## The FLOW phase is a slice sample on ticks that settled this many cells (RulesDef).
var flow_cells_per_tick: int = RulesDef.new().flow_cells_per_tick

## Sample columns by name, created on first use: per frame (interval, process, render, work in ms;
## calls, rigs, published, ref in us) and per published tick (job, step, flow in ms).
var _series: Dictionary[StringName, PackedFloat64Array] = {}
var _runs: int = 0
var _finished: bool = false
var _active: bool = false
var _timing: TimingProbe = TimingProbe.new()
var _column: VBoxContainer = VBoxContainer.new()
var _header: Label = Label.new()
var _body: Label = Label.new()
var _app_paused: bool = false
var _viewport: RID
var _max_fps: int = 0
var _phase_sum: PackedFloat64Array = PackedFloat64Array()
var _phase_ticks: int = 0
var _alive: int = 0
var _last_hash: int = 0
var _checkpoint_ticks: PackedInt32Array = PackedInt32Array()
var _checkpoint_hex: PackedStringArray = PackedStringArray()
## The preflight's results: kept by restart(), replaced only by the next preflight.
var _ref_peak_us: float = 0.0
var _ref_peak_p95_us: float = 0.0
var _preflight_reason: String = ""
var _asked_impl: int = MatchRunner.SimImpl.GDSCRIPT
var _sim_impl: int = MatchRunner.SimImpl.GDSCRIPT
var _native_phases: Array = []
var _native_build: String = ""
var _self_check_result: String = SELF_CHECK_NOT_RUN
## The frame in progress: its interval (-1 until the second frame after restart()), the clock at the
## top of the last frame, after the reference runs and at the draw, its reference sample.
var _interval_usec: int = -1
var _last_top_usec: int = -1
var _work_start_usec: int = 0
var _pre_draw_usec: int = 0
var _ref_usec: int = 0
var _published: bool = false


func _init() -> void:
	theme_type_variation = CARD_VARIATION
	visible = false  # Shown at the end of a run.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_header.theme_type_variation = HEADER_VARIATION
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label: Label in [_header, _body]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.name = "Column"
	scroll.name = "Scroll"
	_header.name = "Header"
	_body.name = "Body"
	add_child(_column)
	_column.add_child(_header)
	_column.add_child(scroll)
	scroll.add_child(_body)
	_phase_sum.resize(SimProbe.Phase.COUNT)


func _ready() -> void:
	process_priority = -1000  # The top of the frame, before any other work.
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	if runner == null:
		return
	runner.ticked.connect(_on_ticked)
	runner.set_probe(_timing)
	_viewport = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport, true)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_active = true


func _exit_tree() -> void:
	_active = false


## A pause or a lost focus during a run spoils its timing: the run is INVALID (ADR 0011 section 5).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_paused = _app_paused or not _finished


## The top of the frame. While a run is on it times the interval and takes the frame's reference
## sample: a discarded warm-up run, then the sample (ADR 0014 section 3). Both lie before
## `_work_start_usec`, so they are not frame work.
func _process(_delta: float) -> void:
	if not _active or _finished:
		return
	var now: int = int(clock.call())
	_interval_usec = now - _last_top_usec if _last_top_usec >= 0 else -1
	_last_top_usec = now
	_published = false
	if _interval_usec < 0:
		return
	ref_step.call(gate.ref_iterations)
	var began: int = int(clock.call())
	ref_step.call(gate.ref_iterations)
	_work_start_usec = int(clock.call())
	_ref_usec = _work_start_usec - began


## A new run: every sample cleared, the rates read again, the card hidden and the runner (which the
## card paused) running. The preflight's results stay. The first interval comes from the two frames
## after it, so the burst and the match start before it lie in no interval.
func restart() -> void:
	_runs += 1
	_app_paused = false
	visible = false
	if runner != null:
		runner.paused = false
	_series.clear()
	_phase_sum.fill(0.0)
	_phase_ticks = 0
	_alive = 0
	_last_hash = 0
	_checkpoint_ticks.clear()
	_checkpoint_hex.clear()
	late_ticks = 0
	held_ticks = 0
	latency_usec_max = 0
	worker_mode = false
	_finished = false
	_interval_usec = -1
	_last_top_usec = -1
	refresh_hz_start = float(refresh_source.call())
	refresh_hz_end = refresh_hz_start
	_max_fps = int(max_fps_source.call())
	var rules: RulesDef = null
	if runner != null and runner.scenario != null:
		rules = runner.scenario.rules
	flow_cells_per_tick = (rules if rules != null else RulesDef.new()).flow_cells_per_tick


## One frame, microseconds unless noted: the interval since the previous frame, the main thread's
## process and render CPU time (frame work is their sum), draw calls, rigs drawn, whether a tick
## published in it, its reference sample (0 without one) and the fog update (-1 when none ran).
func record_frame(
	interval_usec: int,
	process_usec: int,
	render_usec: int,
	draw_calls: int,
	drawn_rigs: int,
	published: bool,
	ref_usec: int,
	fog_usec: int
) -> void:
	if _finished:
		return
	_col(&"interval").append(interval_usec / 1000.0)
	_col(&"process").append(process_usec / 1000.0)
	_col(&"render").append(render_usec / 1000.0)
	_col(&"work").append((process_usec + render_usec) / 1000.0)
	_col(&"calls").append(draw_calls)
	_col(&"rigs").append(drawn_rigs)
	_col(&"published").append(int(published))
	_col(&"ref").append(ref_usec)
	if fog_usec >= 0:
		_col(&"fog").append(fog_usec / 1000.0)
		_col(&"fog_ref").append(ref_usec)


## One published tick, from the runner's snapshot: the worker job, Sim.step, the per-phase split
## (a probe's), the FLOW slice, the alive count and, every CHECKPOINT_EVERY ticks, the checkpoint
## hash. The tick that reaches `run_ticks` ends the run.
func record_snapshot(snap: MatchSnapshot) -> void:
	if _finished:
		return
	var job_ms: float = snap.job_usec / 1000.0
	_col(&"job").append(job_ms)
	_col(&"step").append(snap.step_usec / 1000.0)
	# ADR 0013 section 15: the ticks MatchLoop hashes (every CHECKPOINT_PERIOD) are kept apart.
	var plain: bool = snap.tick % Replay.CHECKPOINT_PERIOD != 0
	_col(&"diff_plain" if plain else &"diff_cp").append(job_ms - snap.step_usec / 1000.0)
	if plain:
		_col(&"job_plain").append(job_ms)
	var usec: PackedInt64Array = snap.phase_usec
	if usec.size() == SimProbe.Phase.COUNT:
		for phase: int in SimProbe.Phase.COUNT:
			_phase_sum[phase] += usec[phase]
			if plain:
				_col(StringName("phase%d" % phase)).append(usec[phase] / 1000.0)
		_phase_ticks += 1
		var cells: int = snap.stats[World.Stat.FLOW_CELLS] if not snap.stats.is_empty() else -1
		if cells == flow_cells_per_tick:
			_col(&"flow").append(usec[SimProbe.Phase.FLOW] / 1000.0)
	_alive = snap.unit_count()
	_last_hash = snap.last_hash
	if snap.tick % CHECKPOINT_EVERY == 0:
		_checkpoint_ticks.append(snap.tick)
		_checkpoint_hex.append(World.hash_hex(snap.last_hash))
	if snap.tick >= run_ticks:
		_finished = true
		refresh_hz_end = float(refresh_source.call())
		_show_card()


## The preflight before a run (ADR 0013 section 3, ADR 0014 section 3), on the main thread with no
## World and no job: the implementation `target` asked for, the self-check and the burst that gives
## `ref_peak`. It reads the runner's job state once and hands it to run_preflight().
func preflight(target: MatchRunner, with_self_check: bool = true) -> void:
	_asked_impl = target.sim_impl
	run_preflight(target.job_in_flight(), with_self_check)


## The preflight on a job state. With a job in flight it is refused by the pure preflight_allowed():
## no seam is called and the run is INVALID with a reason, never an error. Otherwise the self-check
## seam runs (unless `with_self_check` is false, "Run again": its results then stay), then the burst
## seam, whose kept samples give `ref_peak_us` (their p25) and `ref_peak_p95_us`. Replaces the
## results of the last preflight.
func run_preflight(job_in_flight: bool, with_self_check: bool) -> void:
	_preflight_reason = ""
	_ref_peak_us = 0.0
	_ref_peak_p95_us = 0.0
	if not preflight_allowed(job_in_flight):
		_preflight_reason = REASON_JOB_IN_FLIGHT
		return
	if with_self_check:
		var kernels: Object = kernels_source.call()
		_sim_impl = MatchRunner.resolve_impl(_asked_impl, kernels != null, os_name)
		var native: bool = _sim_impl == MatchRunner.SimImpl.NATIVE
		_native_phases = _phase_names(kernels.phases()) if native else []
		_native_build = str(kernels.build_info()) if native else ""
		_self_check_result = SELF_CHECK_NOT_RUN
		if self_check_step.is_valid():
			_self_check_result = self_check_step.call()
	if burst_step.is_valid():
		var kept: PackedFloat64Array = burst_step.call()
		kept.sort()
		_ref_peak_us = PerfStats.percentile(kept, 25)
		_ref_peak_p95_us = PerfStats.percentile(kept, 95)


## A preflight may run only while no job is in flight.
static func preflight_allowed(job_in_flight: bool) -> bool:
	return not job_in_flight


## Why the run is INVALID, empty when it is not (a measurement fault, so no verdict can stand): a
## refused preflight, a pause, a refresh rate that changed or lies below the frame cap, a median
## interval below P (ADR 0014 section 2: one-sided, slow frames are judged) and a heavy window
## whose draw calls or render CPU read 0 (ADR 0012 section 4). A rule needs samples to judge.
func invalid_reasons() -> PackedStringArray:
	var start: float = refresh_hz_start
	var tolerance: float = gate.refresh_tolerance_pct / 100.0
	var frames: PackedFloat64Array = _col(&"interval")
	var heavy: PackedInt32Array = _rows(true, -1)
	var floor_ms: float = period_ms() * (1.0 - gate.median_tolerance_pct / 100.0)
	var faults: Array = [
		[_preflight_reason, _preflight_reason != ""],
		[REASON_APP_PAUSED, _app_paused],
		[REASON_REFRESH_CHANGED, absf(refresh_hz_end - start) > absf(start) * tolerance],
		[REASON_REFRESH_BELOW_CAP, _max_fps > 0 and start < _max_fps * (1.0 - tolerance)],
		[REASON_MEDIAN_BELOW_PERIOD, not frames.is_empty() and _p(frames, 50) < floor_ms],
		[REASON_NO_DRAW_CALLS, not heavy.is_empty() and _p(_take(&"calls", heavy), 95) == 0.0],
		[REASON_NO_RENDER_CPU, not heavy.is_empty() and _p(_take(&"render", heavy), 95) == 0.0],
	]
	var out: PackedStringArray = PackedStringArray()
	for fault: Array in faults:
		if fault[1]:
			out.append(fault[0])
	return out


## The checkpoints against the gate's golden values (ADR 0011 section 5), the golden ticks up to
## `run_ticks`: `match` is true when at least one was checked and every one agrees. `tick` is the
## first golden tick that differs (-1 for none) with the hash text the run `got` there ("none" when
## a finished run lacks it) and the golden `want`; a tick the unfinished run has not reached is
## skipped.
func golden_result() -> Dictionary:
	var out: Dictionary = {"match": false, "checked": 0, "tick": -1, "got": "", "want": ""}
	var ticks: PackedInt32Array = gate.golden_ticks
	for i: int in mini(ticks.size(), gate.golden_hex.size()):
		var at: int = _checkpoint_ticks.find(ticks[i])
		if ticks[i] > run_ticks or (at < 0 and not _finished):
			continue
		out["checked"] += 1
		var got: String = _checkpoint_hex[at] if at >= 0 else "none"
		if got != gate.golden_hex[i]:
			out["tick"] = ticks[i]
			out["got"] = got
			out["want"] = gate.golden_hex[i]
			return out
	out["match"] = out["checked"] > 0
	return out


## The period P of ADR 0014 section 1, ms: 1000 / min(refresh, max_fps), a `max_fps` of 0 counting
## as the refresh rate. 0.0 when the refresh rate is unknown (headless): every pacing verdict fails.
func period_ms() -> float:
	var rate: float = refresh_hz_start
	if _max_fps > 0 and float(_max_fps) < rate:
		rate = float(_max_fps)
	return 1000.0 / rate if rate > 0.0 else 0.0


## The dropped-frame limit, ms: P + drop_slots x V, with the slot V = 1000 / refresh rate.
func drop_ms() -> float:
	return period_ms() + gate.drop_slots * _slot_ms()


## Everything the card shows, one entry per key (the copy report of P50a3 writes them all). Raw and
## normalised main-thread values sit side by side. `verdicts` are the lines of the card and
## `gate_pass` is its GATE: never true before the run has `finished` (a partial run is no pass).
func summary() -> Dictionary:
	var period: float = period_ms()
	var drop: float = drop_ms()
	var everything: PackedFloat64Array = _col(&"interval")
	var heavy: PackedInt32Array = _rows(true, -1)
	var publish: PackedInt32Array = _rows(true, 1)
	var other: PackedInt32Array = _rows(true, 0)
	var heavy_ms: PackedFloat64Array = _take(&"interval", heavy)
	var tick_ms: float = MatchRunner.TICK_USEC / 1000.0
	var mean_ms: float = PerfStats.mean(everything)
	var heavy_mean_ms: float = PerfStats.mean(heavy_ms)
	var screen: Vector2i = DisplayServer.screen_get_size()
	var checkpoints: Array = []
	for i: int in _checkpoint_ticks.size():
		checkpoints.append({"tick": _checkpoint_ticks[i], "hash_hex": _checkpoint_hex[i]})
	var phases: Array = []
	var phases_plain: Array = []
	for phase: int in SimProbe.Phase.COUNT:
		phases.append(_phase_sum[phase] / 1000.0 / maxi(_phase_ticks, 1))
		phases_plain.append(_p(_col(StringName("phase%d" % phase)), 95))
	var golden: Dictionary = golden_result()
	var reasons: PackedStringArray = invalid_reasons()
	var out: Dictionary = {
		"runs": _runs,
		"frames": everything.size(),
		"fps_avg": 1000.0 / mean_ms if mean_ms > 0.0 else 0.0,
		"frame_p50_ms": _p(everything, 50),
		"frame_p95_ms": _p(everything, 95),
		"frame_p99_ms": _p(everything, 99),
		"frame_max_ms": _p(everything, 100),
		"period_ms": period,
		"drop_ms": drop,
		"dropped": _count(everything, drop, 1),
		"dropped_pct": _pct(_count(everything, drop, 1), everything.size()),
		"heavy_frames": heavy.size(),
		"heavy_publish_frames": publish.size(),
		"heavy_dropped": _count(heavy_ms, drop, 1),
		"heavy_dropped_pct": _pct(_count(heavy_ms, drop, 1), heavy.size()),
		"cadence_pct": 100.0 * period / mean_ms if mean_ms > 0.0 else 0.0,
		"heavy_cadence_pct": 100.0 * period / heavy_mean_ms if heavy_mean_ms > 0.0 else 0.0,
		"hitches": _count(everything, tick_ms, 0),
		"heavy_hitches": _count(heavy_ms, tick_ms, 0),
		"extra_slots": _extra_slots(everything, period),
		"jitter_pct": _pct(_count(everything, gate.jitter_ms, -1), everything.size()),
		"heavy_jitter_pct": _pct(_count(heavy_ms, gate.jitter_ms, -1), heavy.size()),
		"refresh_hz_start": refresh_hz_start,
		"refresh_hz_end": refresh_hz_end,
		"work_p95_ms": _p(_take(&"work", heavy), 95),
		"work_p95_norm_ms": _norm(&"work", &"ref", heavy),
		"work_tick_p95_ms": _p(_take(&"work", publish), 95),
		"work_tick_p95_norm_ms": _norm(&"work", &"ref", publish),
		"work_other_p95_ms": _p(_take(&"work", other), 95),
		"work_other_p95_norm_ms": _norm(&"work", &"ref", other),
		"fog_update_p95_ms": _p(_col(&"fog"), 95),
		"fog_update_p95_norm_ms": _norm_fog(),
		"fog_updates": _col(&"fog").size(),
		"job_ticks": _col(&"job").size(),
		# The main thread's whole process time, not the layers' own _process time that ADR 0011
		# section 5 means: a layer-time seam can narrow it (P50b).
		"view_p95_ms": _p(_take(&"process", heavy), 95),
		"render_cpu_p95_ms": _p(_take(&"render", heavy), 95),
		"draw_calls_p95": roundi(_p(_take(&"calls", heavy), 95)),
		"drawn_rigs_p50": roundi(_p(_col(&"rigs"), 50)),
		"drawn_rigs_max": roundi(_p(_col(&"rigs"), 100)),
		"ref_peak_us": _ref_peak_us,
		"ref_peak_p95_us": _ref_peak_p95_us,
		"speed_main_pct": _speed(_take(&"ref", heavy)),
		"speed_tick_pct": _speed(_take(&"ref", publish)),
		"speed_fog_pct": _speed(_col(&"fog_ref")),
		"tick_p50_ms": _p(_col(&"step"), 50),
		"tick_p95_ms": _p(_col(&"step"), 95),
		"tick_max_ms": _p(_col(&"step"), 100),
		"job_mean_ms": PerfStats.mean(_col(&"job")),
		"job_p50_ms": _p(_col(&"job"), 50),
		"job_p95_ms": _p(_col(&"job"), 95),
		"job_p99_ms": _p(_col(&"job"), 99),
		"job_max_ms": _p(_col(&"job"), 100),
		"late_ticks": late_ticks,
		"held_ticks": held_ticks,
		"latency_usec_max": latency_usec_max,
		"flow_slice_p95_ms": _p(_col(&"flow"), 95),
		"phases_ms": phases,
		# ADR 0013 section 15 (printed, no verdict): the ticks that are not checkpoint ticks, and
		# the job time beyond Sim.step on both kinds.
		"phases_p95_noncp_ms": phases_plain,
		"job_p95_noncp_ms": _p(_col(&"job_plain"), 95),
		"job_minus_step_p95_cp_ms": _p(_col(&"diff_cp"), 95),
		"job_minus_step_p95_noncp_ms": _p(_col(&"diff_plain"), 95),
		"tick_mode": WORKER if worker_mode else SYNC,
		"sim_impl": MatchRunner.SimImpl.keys()[_sim_impl],
		"native_phases": _native_phases,
		"native_build": _native_build,
		"self_check": _self_check_result,
		"alive": _alive,
		"hash_hex": World.hash_hex(_last_hash) if _last_hash != 0 else "",
		"checkpoints": checkpoints,
		"golden_match": golden["match"],
		"golden_checked": golden["checked"],
		"golden_mismatch_tick": golden["tick"],
		"invalid": not reasons.is_empty(),
		"invalid_reasons": Array(reasons),
		"layer_mode": layer_mode,
		"screen": "%dx%d" % [screen.x, screen.y],
		"zoom": zoom,
		"model": OS.get_model_name(),
		"os": os_name,
		"engine": Engine.get_version_info()["string"],
		"debug": debug_build,
		"finished": _finished,
	}
	var lines: Array[String] = _verdicts(out)
	out["verdicts"] = lines
	out["gate_pass"] = _finished and not out["invalid"] and not lines.any(_failed)
	return out


## The card's lines: the run, the build and mode; the verdict lines; the rows without a verdict
## (CARD_ROWS, the implementation and the four keys of ADR 0013 section 15, `held_ticks`); GATE
## last.
func card_lines() -> PackedStringArray:
	var s: Dictionary = summary()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("PERF run %d | %s | %s build | %s" % [_runs, s["tick_mode"], _build(), layer_mode])
	lines.append_array(PackedStringArray(s["verdicts"]))
	lines.append("held_ticks %d (no verdict)" % held_ticks)
	var lockstep: String = "not run"
	if s["self_check"] != SELF_CHECK_NOT_RUN:
		lockstep = (
			"%s (%d ticks)"
			% ["yes" if s["self_check"] == SELF_CHECK_MATCH else "NO", SELF_CHECK_TICKS]
		)
	lines.append(_impl_line(s, lockstep))
	for row: Array in CARD_ROWS:
		lines.append(row[0] % row.slice(1).map(func(key: String) -> Variant: return s[key]))
	lines.append(_phase_line("phase means per tick", s["phases_ms"]))
	lines.append(_phase_line("p95 per phase without checkpoint ticks", s["phases_p95_noncp_ms"]))
	lines.append("GATE: %s" % (PASS if s["gate_pass"] else FAIL))
	return lines


## ADR 0013 section 3's line: the implementation that runs, for the library its build and phases,
## and the self-check text.
func _impl_line(s: Dictionary, lockstep: String) -> String:
	var impl: String = "gdscript"
	if _sim_impl == MatchRunner.SimImpl.NATIVE:
		var phases: String = ", ".join(PackedStringArray(s["native_phases"]))
		impl = "native (%s, phases %s)" % [s["native_build"], phases if phases != "" else "none"]
	return "sim impl: %s | C++ matches GDScript: %s" % [impl, lockstep]


## One phase value per phase, in id order: `title` and `values` (ms).
func _phase_line(title: String, values: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for phase: int in SimProbe.Phase.COUNT:
		parts.append("%s %.2f" % [SimProbe.PHASE_NAMES[phase], values[phase]])
	return "%s (ms): %s" % [title, ", ".join(parts)]


## The run is over: the verdict (with the rows that failed, so a small screen need not scroll for
## them) and the run line on top, the rest below it, and the runner pauses.
func _show_card() -> void:
	var lines: PackedStringArray = card_lines()
	var why: PackedStringArray = PackedStringArray()
	for line: String in lines:
		if line.begins_with("INVALID"):
			why.append(line)
		elif _failed(line):
			why.append(line.get_slice(":", 0))
	var verdict: String = lines[lines.size() - 1]
	_header.text = (
		"%s%s | %s" % [verdict, " (%s)" % ", ".join(why) if not why.is_empty() else "", lines[0]]
	)
	_body.text = "\n".join(lines.slice(1, lines.size() - 1))
	visible = true
	if runner != null:
		runner.paused = true


## Sizes are dp, so they follow a resize like DpMinSize does.
func _apply_dp() -> void:
	_column.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))


func _on_ticked(_tick_number: int) -> void:
	if _finished:
		return
	_published = true
	late_ticks = runner.late_ticks
	held_ticks = runner.held_ticks
	latency_usec_max = runner.latency_usec_max
	worker_mode = runner.worker_active()
	record_snapshot(runner.snapshot)


func _on_pre_draw() -> void:
	_pre_draw_usec = int(clock.call())


## The frame is drawn: files its samples. The four seams run after the work window.
func _on_post_draw() -> void:
	if not _active or _finished or _interval_usec < 0:
		return
	record_frame(
		_interval_usec,
		_pre_draw_usec - _work_start_usec,
		roundi(float(render_source.call()) * 1000.0),
		int(calls_source.call()),
		int(rigs_source.call()),
		_published,
		_ref_usec,
		int(fog_source.call())
	)
	_interval_usec = -1


func _render_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_cpu(_viewport)


func _draw_calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


## The default of `self_check_step` (ADR 0013 section 3): the 60-tick lockstep of the seed-42 arena
## on every phase the library reports, when the implementation that runs is NATIVE.
func _run_self_check() -> String:
	var kernels: Object = kernels_source.call()
	if _sim_impl != MatchRunner.SimImpl.NATIVE or kernels == null:
		return SELF_CHECK_NOT_RUN
	var arena: ScenarioDef = load(ARENA)
	var same: bool = NativeKernels.self_check(
		arena, SELF_CHECK_SEED, SELF_CHECK_TICKS, kernels, kernels.phases()
	)
	return SELF_CHECK_MATCH if same else SELF_CHECK_MISMATCH


## The names of the phases whose bit is set in `mask` (a library's phases()), in id order.
func _phase_names(mask: int) -> Array:
	var names: Array = []
	for phase: int in SimProbe.Phase.COUNT:
		if (mask >> phase) & 1 == 1:
			names.append(SimProbe.PHASE_NAMES[phase])
	return names


## The back-to-back RefLoop runs of one burst (`ref_burst_ms`), keeping the second half: their
## times in us. The default of `burst_step`.
func _burst() -> PackedFloat64Array:
	var kept: PackedFloat64Array = PackedFloat64Array()
	var start: int = int(clock.call())
	var span: int = gate.ref_burst_ms * 1000
	var at: int = start
	while at < start + span:
		var began: int = at
		ref_step.call(gate.ref_iterations)
		at = int(clock.call())
		if began >= start + (span >> 1):
			kept.append(at - began)
	return kept


## The verdict lines (ADR 0012 section 4, ADR 0014 sections 1 and 3) over a summary: INVALID first,
## the table's rows (pacing on the raw intervals, the main-thread CPU limits on the normalised
## values, the worker limits on the raw job times), late ticks for a worker run only, the fog
## update (none sampled fails: the measurement is missing), the build, the implementation and the
## golden hashes.
func _verdicts(s: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for reason: String in s["invalid_reasons"]:
		rows.append("INVALID: %s" % reason)
	for row: Array in ROWS:
		var needs: String = NEEDS.get(row[0], "")
		if needs != "" and s[needs] == 0:
			rows.append(_check(row[0], false, "no %s" % needs))
		else:
			rows.append(_judge(row[0], s[row[1]], gate.get(row[2]), row[3], row[4]))
	if s["tick_mode"] == WORKER:
		rows.append(_judge("late_ticks_max", late_ticks, gate.late_ticks_max, "late ticks"))
	else:
		rows.append("late_ticks_max: n/a (SYNC: late_ticks counts inline ticks)")
	var fog: float = s["fog_update_p95_norm_ms"]
	var fog_ok: bool = s["fog_updates"] > 0 and fog <= gate.fog_update_p95_ms
	var fog_text: String = "%.2f ms normalised, %d updates, limit %.2f"
	fog_text = fog_text % [fog, s["fog_updates"], gate.fog_update_p95_ms]
	rows.append(_check("fog_update_p95_ms", fog_ok, fog_text))
	rows.append(_check("build", not (gate.release_only and debug_build), "%s template" % _build()))
	rows.append(_impl_row())
	rows.append(_golden_row())
	return rows


## `impl` (ADR 0013 section 3), like `build` a verdict that fails the gate alone. Android needs the
## library: the implementation that runs must be NATIVE and its self-check a match. Elsewhere the
## twins are allowed (the web runs them), so the line is n/a.
func _impl_row() -> String:
	if os_name != MatchRunner.OS_ANDROID:
		return "impl: n/a (only Android requires the library)"
	if _sim_impl != MatchRunner.SimImpl.NATIVE:
		return _check("impl", false, "gdscript")
	var matched: bool = _self_check_result == SELF_CHECK_MATCH
	return _check("impl", matched, "self-check %s" % _self_check_result)


## `golden_hashes`: MATCH, or MISMATCH with the first differing tick; no golden checkpoint to
## compare never passes.
func _golden_row() -> String:
	var golden: Dictionary = golden_result()
	var detail: String = "no golden checkpoint up to tick %d" % run_ticks
	if golden["tick"] >= 0:
		detail = (
			"MISMATCH at tick %d, got %s, golden %s"
			% [golden["tick"], golden["got"], golden["want"]]
		)
	elif golden["checked"] > 0:
		detail = "MATCH, %d checkpoints" % golden["checked"]
	return _check("golden_hashes", golden["match"], detail)


func _build() -> String:
	return "debug" if debug_build else "release"


func _slot_ms() -> float:
	return 1000.0 / refresh_hz_start if refresh_hz_start > 0.0 else 0.0


func _col(name: StringName) -> PackedFloat64Array:
	if not _series.has(name):
		_series[name] = PackedFloat64Array()
	return _series[name]


## The frames to judge, as rows of the frame columns: those of the heavy window (at least
## `heavy_rigs` rigs) or all, and those that published (1), did not (0) or either (-1).
func _rows(heavy: bool, published: int) -> PackedInt32Array:
	var rows: PackedInt32Array = PackedInt32Array()
	var rigs: PackedFloat64Array = _col(&"rigs")
	var flags: PackedFloat64Array = _col(&"published")
	var heavy_rigs: int = gate.heavy_rigs
	for i: int in rigs.size():
		if (not heavy or rigs[i] >= heavy_rigs) and (published < 0 or flags[i] == published):
			rows.append(i)
	return rows


func _take(name: StringName, rows: PackedInt32Array) -> PackedFloat64Array:
	var column: PackedFloat64Array = _col(name)
	var out: PackedFloat64Array = PackedFloat64Array()
	for i: int in rows:
		out.append(column[i])
	return out


func _p(values: PackedFloat64Array, p: int) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return PerfStats.percentile(sorted, p)


## The p95 of a work column over `rows`, each value scaled by its frame's own reference sample
## against `ref_peak_us` (ADR 0014 section 3, the per-frame method).
func _norm(work: StringName, ref: StringName, rows: PackedInt32Array) -> float:
	return RefLoop.normalised_p95(_take(work, rows), _take(ref, rows), _ref_peak_us)


func _norm_fog() -> float:
	return RefLoop.normalised_p95(_col(&"fog"), _col(&"fog_ref"), _ref_peak_us)


## 100 x ref_peak / ref_span, the span being the p25 of a class's reference samples: the class
## clock factor, a diagnostic. 0 without samples.
func _speed(refs: PackedFloat64Array) -> float:
	var span: float = _p(refs, 25)
	return 100.0 * _ref_peak_us / span if span > 0.0 else 0.0


## How many of `values` are above `limit` (`op` 1), at least it (0) or up to it (-1).
func _count(values: PackedFloat64Array, limit: float, op: int) -> int:
	var n: int = 0
	for value: float in values:
		n += int(value > limit if op > 0 else (value >= limit if op == 0 else value <= limit))
	return n


func _pct(count: int, total: int) -> float:
	return 100.0 * count / total if total > 0 else 0.0


## The intervals by slots beyond P, rounded up from `drop_slots` of a slot (so a dropped frame has
## one extra slot at least): 0, 1, 2 and 3 or more.
func _extra_slots(intervals: PackedFloat64Array, period: float) -> Array:
	var bins: Array = [0, 0, 0, 0]
	var slot: float = _slot_ms()
	var slots: float = gate.drop_slots
	for interval: float in intervals:
		var extra: int = floori((interval - period) / slot + slots) if slot > 0.0 else 0
		bins[clampi(extra, 0, 3)] += 1
	return bins


func _check(name: String, ok: bool, detail: String) -> String:
	return "%s: %s (%s)" % [name, PASS if ok else FAIL, detail]


func _judge(name: String, value: float, limit: float, unit: String, lower: bool = false) -> String:
	var ok: bool = value >= limit if lower else value <= limit
	return _check(name, ok, "%.2f %s, limit %.2f" % [value, unit, limit])


func _failed(line: String) -> bool:
	return line.contains(": %s (" % FAIL)
