extends GdUnitTestSuite
## Spike P26n2 (ADR 0014 section 5, never merged): the perf probe's calibration rows. The pure
## helpers of PerfProbeCalib are pinned on hand-made numbers: drop_ms, cadence, hitches, the
## extra-slot histogram, both normalisations (never above raw, clamped at min(1, ...)) and the
## burst's second half. The scene tests prove that the two ref runs open every timed frame outside
## its work with the first one discarded and the second filed with that frame's work, ticks and fog
## patches; that the burst runs at every mode start outside the timed window; that on frames played
## by hand every CALIBRATION line carries its own value (ref_peak's p25 and p95, the tick and other
## frames, the class and per-frame methods, the pacing counts, the refresh rate at start and end,
## the worker job); and that the finished card fits Michael's phone. Mode 5 and the same-state
## check of modes 1, 2, 4 and 5 are in tests/ui/test_perf_probe_native.gd (they need the library).
## Timing is never asserted beyond a long frame being kept out.

const Probe: GDScript = preload("res://game/ui/perf_probe.gd")
const SCENE: String = "res://scenes/dev/perf_probe.tscn"
const SLOW_REF_MS: int = 60  ## A fake ref run this long: two per frame are 120 ms of the interval.
## A fake ref run returns one of these plus the process frame it ran in, so a value names its frame.
const WARM_UP_BASE: int = 1_000_000
const SAMPLE_BASE: int = 2_000_000
## The burst's kept samples in the hand-played tests: p25 50, p50 100, p95 400 us.
const PEAK: Array[float] = [50.0, 100.0, 100.0, 400.0]
## The hand-played frames' samples, in turn: p25, p50 and p95 differ, and so do the two methods.
const SAMPLES: Array[float] = [100.0, 200.0, 300.0, 400.0, 800.0]
const WORKER_MODE: int = 3

var _window_size_before: Vector2i


## Headless Godot draws nothing, so RenderingServer emits no frame_pre_draw or frame_post_draw.
## This node, processed after the probe in the same frame, stands in for the draw. With a real
## draw the probe files the frame once: its `_sampled` flag is cleared by the first post-draw. It
## also notes, per series, the process frame in which each entry was filed.
class FakeDraw:
	extends Node

	var probe: Node2D = null
	var frames_of: Dictionary[int, PackedInt64Array] = {}  ## Series -> the frame of each entry.

	func _init() -> void:
		process_priority = 1000

	func _process(_delta: float) -> void:
		probe._on_pre_draw()
		probe._on_post_draw()
		var frame: int = Engine.get_process_frames()
		for series: int in probe._series.size():
			var filed: PackedInt64Array = frames_of.get(series, PackedInt64Array())
			for _k: int in probe._series[series].size() - filed.size():
				filed.append(frame)
			frames_of[series] = filed


func before() -> void:
	_window_size_before = get_window().size


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	get_window().size = _window_size_before


func test_drop_ms_is_the_period_plus_half_a_slot() -> void:
	assert_float(PerfProbeCalib.drop_ms(60.0, 60)).is_equal_approx(25.0, 1e-9)
	assert_float(PerfProbeCalib.period_ms(120.0, 60)).is_equal_approx(16.6667, 1e-4)
	assert_float(PerfProbeCalib.slot_ms(120.0)).is_equal_approx(8.3333, 1e-4)
	assert_float(PerfProbeCalib.drop_ms(120.0, 60)).is_equal_approx(20.8333, 1e-4)
	# max_fps 0 (unlimited) counts as refresh_hz; a 59.94 Hz panel under max_fps 60 sets P.
	assert_float(PerfProbeCalib.period_ms(120.0, 0)).is_equal_approx(8.3333, 1e-4)
	assert_float(PerfProbeCalib.drop_ms(120.0, 0)).is_equal_approx(12.5, 1e-9)
	assert_float(PerfProbeCalib.period_ms(59.94, 60)).is_equal_approx(16.6834, 1e-4)


func test_steady_24_ms_frames_give_a_cadence_of_about_69_percent_and_no_drop() -> void:
	var slow: PerfProbeCalib.Pacing = PerfProbeCalib.pacing(_steady(24.0, 600), 60.0, 60)
	assert_float(slow.cadence_pct).is_equal_approx(69.444, 0.001)
	assert_int(slow.dropped).is_equal(0)  # 24 ms is under drop_ms: only the cadence sees it.
	assert_int(slow.hitches).is_equal(0)
	var paced: PerfProbeCalib.Pacing = PerfProbeCalib.pacing(_steady(1000.0 / 60.0, 600), 60.0, 60)
	assert_float(paced.cadence_pct).is_equal_approx(100.0, 1e-6)
	# Cadence is P over the mean: three paced frames and one of two periods give 80 %.
	var p: float = 1000.0 / 60.0
	var uneven: PackedFloat64Array = PackedFloat64Array([p, p, p, 2.0 * p])
	assert_float(PerfProbeCalib.pacing(uneven, 60.0, 60).cadence_pct).is_equal_approx(80.0, 1e-6)
	# A 120 Hz panel capped at 60: P is 16.67 ms (not V, 8.33), so paced frames are 100 %.
	var capped: PerfProbeCalib.Pacing = PerfProbeCalib.pacing(_steady(p, 600), 120.0, 60)
	assert_float(capped.cadence_pct).is_equal_approx(100.0, 1e-6)
	assert_float(capped.slot_ms).is_equal_approx(p / 2.0, 1e-9)
	assert_int(capped.dropped).is_equal(0)


func test_a_hitch_is_an_interval_of_at_least_one_tick_period() -> void:
	assert_bool(PerfProbeCalib.is_hitch(66.7)).is_true()
	assert_bool(PerfProbeCalib.is_hitch(66.6)).is_false()
	# 1_000_000 / 15 usec in whole microseconds: 66666 is a hitch, 66665 is not.
	assert_bool(PerfProbeCalib.is_hitch(66666 / 1000.0)).is_true()
	assert_bool(PerfProbeCalib.is_hitch(66665 / 1000.0)).is_false()
	var intervals: PackedFloat64Array = PackedFloat64Array([16.7, 66.6, 66.7, 100.0])
	assert_int(PerfProbeCalib.pacing(intervals, 60.0, 60).hitches).is_equal(2)


func test_jitter_is_the_share_of_intervals_up_to_17_5_ms() -> void:
	var intervals: PackedFloat64Array = PackedFloat64Array([16.0, 17.5, 17.6, 30.0])
	assert_float(PerfProbeCalib.pacing(intervals, 60.0, 60).jitter_pct).is_equal(50.0)


func test_dropped_frames_and_the_extra_slot_histogram() -> void:
	# 60 Hz under max_fps 60: P = V = 16.67 ms, drop_ms 25.0; P + k V lands on k extra slots.
	var intervals: PackedFloat64Array = PackedFloat64Array(
		[16.7, 25.0, 25.1, 33.3, 50.0, 58.3, 66.7, 120.0]
	)
	var pace: PerfProbeCalib.Pacing = PerfProbeCalib.pacing(intervals, 60.0, 60)
	assert_array(pace.slots).is_equal(PackedInt32Array([2, 2, 2, 2]))
	assert_int(pace.dropped).is_equal(6)  # Every interval with an extra slot; 25.0 is not one.
	assert_float(pace.dropped_pct).is_equal_approx(75.0, 1e-9)
	assert_int(pace.frames).is_equal(8)
	assert_float(pace.median_ms).is_equal_approx(33.3, 1e-9)  # Nearest rank: the 4th of 8.
	assert_float(pace.p99_ms).is_equal_approx(120.0, 1e-9)
	assert_float(pace.max_ms).is_equal_approx(120.0, 1e-9)
	assert_float(pace.jitter_pct).is_equal_approx(12.5, 1e-9)  # Only 16.7 is <= 17.5 ms.
	# 120 Hz capped at 60: V = 8.33 ms and drop_ms 20.83, so 25.0 (P + V) is one extra slot.
	var fast: PerfProbeCalib.Pacing = PerfProbeCalib.pacing(
		PackedFloat64Array([16.7, 20.8, 25.0, 33.3, 41.7]), 120.0, 60
	)
	assert_array(fast.slots).is_equal(PackedInt32Array([2, 1, 1, 1]))
	assert_int(fast.dropped).is_equal(3)
	# 200 intervals of 1 to 200 ms: the median, p99 and max are three different ranks.
	var ranks: PackedFloat64Array = PackedFloat64Array()
	for ms: int in range(200, 0, -1):
		ranks.append(ms)
	var ranked: PerfProbeCalib.Pacing = PerfProbeCalib.pacing(ranks, 60.0, 60)
	assert_float(ranked.median_ms).is_equal(100.0)
	assert_float(ranked.p99_ms).is_equal(198.0)
	assert_float(ranked.max_ms).is_equal(200.0)


func test_both_normalisations_never_exceed_raw_and_clamp_at_one() -> void:
	assert_float(PerfProbeCalib.factor(100.0, 125.0)).is_equal_approx(0.8, 1e-9)
	assert_float(PerfProbeCalib.factor(100.0, 80.0)).is_equal(1.0)  # A faster sample: no gain.
	assert_float(PerfProbeCalib.factor(0.0, 80.0)).is_equal(1.0)  # No burst: raw.
	assert_float(PerfProbeCalib.factor(100.0, 0.0)).is_equal(1.0)
	var work: PackedFloat64Array = PackedFloat64Array([1.0, 2.0, 3.0, 4.0])
	# A slow class: every sample 125 us against a 100 us peak, both methods scale by 0.8.
	var slow: PerfProbeCalib.Stats = PerfProbeCalib.stats(work, _steady(125.0, 4), 100.0)
	assert_int(slow.frames).is_equal(4)
	assert_float(slow.ref_span_us).is_equal(125.0)
	assert_float(slow.ref_p50_us).is_equal(125.0)
	assert_float(slow.ref_p95_us).is_equal(125.0)
	assert_float(slow.speed_pct).is_equal_approx(80.0, 1e-9)
	assert_float(slow.p95_raw).is_equal(4.0)
	assert_float(slow.p95_class).is_equal_approx(3.2, 1e-9)
	assert_float(slow.p95_frame).is_equal_approx(3.2, 1e-9)
	assert_float(slow.mean_raw).is_equal_approx(2.5, 1e-9)
	assert_float(slow.mean_class).is_equal_approx(2.0, 1e-9)
	assert_float(slow.mean_frame).is_equal_approx(2.0, 1e-9)
	# Mixed samples against a 75 us peak: the class p25 (50 us, not the median 100) is faster than
	# the peak, so the class factor clamps at 1 and the class p95 stays raw; per frame, 2.0, 3.0 and
	# 4.0 are scaled (by 0.375, 0.75 and 0.1875), and 1.0, sampled faster than the peak, is not
	# scaled up.
	var mixed: PerfProbeCalib.Stats = PerfProbeCalib.stats(
		work, PackedFloat64Array([50.0, 200.0, 100.0, 400.0]), 75.0
	)
	assert_float(mixed.ref_span_us).is_equal(50.0)
	assert_float(mixed.ref_p50_us).is_equal(100.0)
	assert_float(mixed.ref_p95_us).is_equal(400.0)
	assert_float(mixed.speed_pct).is_equal_approx(150.0, 1e-9)
	assert_float(mixed.p95_class).is_equal(4.0)
	assert_float(mixed.p95_frame).is_equal_approx(2.25, 1e-9)
	assert_float(mixed.mean_frame).is_equal_approx(1.1875, 1e-9)
	# Neither method exceeds raw, whatever the samples.
	for peak: float in [10.0, 100.0, 1000.0]:
		var refs: PackedFloat64Array = PackedFloat64Array()
		var times: PackedFloat64Array = PackedFloat64Array()
		for i: int in 40:
			refs.append(20.0 + (i * 37) % 300)
			times.append(0.5 + (i * 53) % 17)
		var any: PerfProbeCalib.Stats = PerfProbeCalib.stats(times, refs, peak)
		assert_float(any.p95_class).is_less_equal(any.p95_raw)
		assert_float(any.p95_frame).is_less_equal(any.p95_raw)
		assert_float(any.mean_class).is_less_equal(any.mean_raw)
		assert_float(any.mean_frame).is_less_equal(any.mean_raw)


func test_the_burst_keeps_exactly_its_second_half() -> void:
	# ADR 0014's `ref_burst_ms` 400, the probe's default (tests shorten it, the phone never does).
	assert_int(PerfProbeCalib.BURST_USEC).is_equal(400000)
	var fresh: Node2D = auto_free(Probe.new())
	assert_int(fresh.burst_usec).is_equal(400000)
	assert_bool(fresh.ref_sampler == Callable(PerfProbeCalib, &"ref_usec")).is_true()
	var samples: PackedFloat64Array = PackedFloat64Array()
	var starts: PackedInt64Array = PackedInt64Array()
	for i: int in 400:
		samples.append(i)
		starts.append(i * 1000)
	var kept: PackedFloat64Array = PerfProbeCalib.second_half(samples, starts, 400000)
	assert_int(kept.size()).is_equal(200)
	assert_float(kept[0]).is_equal(200.0)  # The sample that starts at 200 ms is the first kept.
	assert_float(kept[199]).is_equal(399.0)
	# It is the start time that counts, not the index.
	var uneven: PackedFloat64Array = PerfProbeCalib.second_half(
		PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0]),
		PackedInt64Array([0, 10, 199999, 200000, 399999]),
		400000
	)
	assert_array(uneven).is_equal(PackedFloat64Array([4.0, 5.0]))
	# The real burst: back to back for 40 ms, the calls of its first 20 ms dropped.
	var calls: Array[int] = [0]
	var counting: Callable = func() -> int:
		calls[0] += 1
		OS.delay_usec(1000)
		return calls[0]
	var burst: PackedFloat64Array = PerfProbeCalib.burst(40000, counting)
	assert_int(burst.size()).is_greater(0)
	assert_int(burst.size()).is_less(calls[0])
	assert_float(burst[burst.size() - 1]).is_equal(float(calls[0]))  # The last call is kept.
	for i: int in burst.size() - 1:
		assert_float(burst[i + 1] - burst[i]).is_equal(1.0)  # The kept calls are one run.


func test_the_reference_loop_is_the_one_of_the_evidence() -> void:
	assert_int(PerfProbeCalib.ref_loop(0)).is_equal(1)
	assert_int(PerfProbeCalib.ref_loop(3)).is_equal(29824)  # ((31 + 0) * 31 + 1) * 31 + 2.
	assert_int(PerfProbeCalib.ref_loop(PerfProbeCalib.REF_ITERATIONS)).is_equal(16346357)
	assert_int(PerfProbeCalib.ref_usec()).is_greater_equal(0)


## Two ref runs open every timed frame; both stay out of the frame's work (process + render), the
## first is the discarded warm-up and the second the frame's sample, filed with the work, the ticks
## and the fog patches of that same frame. Every run returns a value that names its frame.
func test_the_ref_runs_open_every_timed_frame_outside_its_work_and_the_first_is_discarded() -> void:
	var runs: Dictionary[int, int] = {}  # Process frame -> ref runs in it.
	var probe: Node2D = load(SCENE).instantiate()
	probe.burst_usec = 0  # No burst: only the per-frame runs call the sampler.
	probe.ref_sampler = func() -> int:
		var frame: int = Engine.get_process_frames()
		runs[frame] = runs.get(frame, 0) + 1
		OS.delay_msec(SLOW_REF_MS)
		return (WARM_UP_BASE if runs[frame] == 1 else SAMPLE_BASE) + frame
	var draw: FakeDraw = _open_drawn(probe)
	await await_millis(1500)
	await await_idle_frame()  # The stand-in has filed the probe's last frame too.
	var series: Array[PackedFloat64Array] = probe._series
	var warm_ups: PackedFloat64Array = PackedFloat64Array()
	for frame: int in runs:
		assert_int(runs[frame]).is_equal(2)  # Two runs per timed frame, none elsewhere.
		warm_ups.append(WARM_UP_BASE + frame)
	assert_int(warm_ups.size()).is_greater_equal(4)
	assert_array(series[Probe.Series.WARMUP]).is_equal(warm_ups)
	for pair: Array in [
		[Probe.Series.WORK_TICK, Probe.Series.WORK_TICK_REF],
		[Probe.Series.WORK_OTHER, Probe.Series.WORK_OTHER_REF],
		[Probe.Series.TICK, Probe.Series.TICK_REF],
		[Probe.Series.FOG, Probe.Series.FOG_REF],
	]:
		var filed: PackedInt64Array = draw.frames_of[pair[0]]
		assert_int(filed.size()).is_greater(0)  # Every frame ticks (two 60 ms runs), the first not.
		var samples: PackedFloat64Array = PackedFloat64Array()
		for frame: int in filed:
			samples.append(SAMPLE_BASE + frame)
		assert_array(series[pair[1]]).is_equal(samples)  # Each value with its own frame's sample.
	var work: PackedFloat64Array = series[Probe.Series.WORK_TICK] + series[Probe.Series.WORK_OTHER]
	assert_int(work.size()).is_greater_equal(3)
	assert_float(PerfProbeTick.percentile(work, 100)).is_less(SLOW_REF_MS)
	assert_float(PerfProbeTick.percentile(series[Probe.Series.PROCESS], 100)).is_less(SLOW_REF_MS)
	# The interval runs from frame start to frame start, the two ref runs included.
	assert_float(PerfProbeTick.percentile(series[Probe.Series.INTERVAL], 50)).is_greater_equal(
		2 * SLOW_REF_MS
	)
	var report: String = probe.report()
	var warm_p25: float = PerfProbeTick.percentile(warm_ups, 25)
	assert_str(report).contains("warm-up p25 %.1f us" % warm_p25)
	_close(probe, draw)


## The burst runs at every mode start, after the mode's reset (with the fresh tick in place), and
## its long frame is in no interval: the first interval is taken after it.
func test_the_burst_runs_at_every_mode_start_outside_the_timed_window() -> void:
	var probe: Node2D = load(SCENE).instantiate()
	probe.burst_usec = 500000
	var ticks_seen: Array[int] = []  # `sim.tick` at every ref run.
	probe.ref_sampler = func() -> int:
		ticks_seen.append(probe.sim.tick)
		return PerfProbeCalib.ref_usec()
	add_child(probe)
	assert_int(probe._ref_peak.size()).is_greater(0)
	assert_int(ticks_seen.size()).is_greater(probe._ref_peak.size())  # Both halves were run.
	await await_millis(400)
	var intervals: PackedFloat64Array = probe._series[Probe.Series.INTERVAL]
	assert_int(intervals.size()).is_greater(0)
	assert_float(PerfProbeTick.percentile(intervals, 100)).is_less(400.0)
	assert_int(probe.sim.tick).is_greater(3)  # Mode 1 ticked on.
	probe._ref_peak = PackedFloat64Array()
	ticks_seen.clear()
	probe.get_node("Hud/Margin/Buttons/RingsButton").pressed.emit()  # No frame runs in between.
	assert_int(probe._ref_peak.size()).is_greater(0)
	assert_int(ticks_seen.min()).is_equal(3)  # Every burst run saw mode 2's fresh tick.
	assert_int(ticks_seen.max()).is_equal(3)
	await await_millis(400)
	intervals = probe._series[Probe.Series.INTERVAL]
	assert_int(intervals.size()).is_greater(0)
	assert_float(PerfProbeTick.percentile(intervals, 100)).is_less(400.0)
	remove_child(probe)
	probe.free()


## ADR 0014 sections 1, 3 and 5 on mode 1 frames played by hand, where every input is known: the
## intervals, the two ref runs of each frame and its work. The tick frames are exactly the frames
## that ran a tick, each value is filed with its own frame's sample, and every C1-C5 line and the
## pacing row carry their own field: ref_peak's p25 and p95, the warm-up p25, the class and the
## per-frame method, the counts, and the refresh rate read at run start and at run end.
func test_the_calibration_lines_carry_their_own_values_on_frames_played_by_hand() -> void:
	var refs: Array[float] = [0.0, 0.0]
	var refresh: Array[float] = [60.0]
	var probe: Node2D = _open_by_hand(refs, refresh)
	var played: Dictionary[String, PackedFloat64Array] = {}
	for key: String in ["interval", "tick_work", "tick_ref", "other_work", "other_ref", "all_work"]:
		played[key] = PackedFloat64Array()
	played["all_ref"] = PackedFloat64Array()
	played["tick_samples"] = PackedFloat64Array()  # Per mock tick, its frame's sample.
	var frames: int = 40
	for i: int in frames:
		var interval: float = {10: 30.0, 20: 45.0, 30: 70.0}.get(i, 17.0)
		var sample: float = SAMPLES[i % SAMPLES.size()]
		var work: float = 1.0 + 0.5 * (i % 4)
		if i == frames - 1:  # This frame ends the run; its work is filed after the end, so not.
			probe.run_seconds = 0
			refresh[0] = 59.94
		var ticks: int = _size(probe, Probe.Series.TICK)
		var ticked: bool = _play(probe, refs, interval, 1000.0 + i, sample, work)
		if i > 0:  # The first frame of a run records no interval.
			played["interval"].append(interval)
		for _t: int in _size(probe, Probe.Series.TICK) - ticks:
			played["tick_samples"].append(sample)
		if i == frames - 1:
			continue
		var kind: String = "tick" if ticked else "other"
		played[kind + "_work"].append(work)
		played[kind + "_ref"].append(sample)
		played["all_work"].append(work)
		played["all_ref"].append(sample)
	refresh[0] = 50.0  # Read after the end: the end value is the one taken at the end.
	assert_int(probe._end_us).is_greater(0)
	var series: Array[PackedFloat64Array] = probe._series
	assert_int(played["tick_work"].size()).is_greater_equal(5)
	assert_int(played["other_work"].size()).is_greater_equal(20)
	assert_array(series[Probe.Series.WORK_TICK]).is_equal(played["tick_work"])
	assert_array(series[Probe.Series.WORK_TICK_REF]).is_equal(played["tick_ref"])
	assert_array(series[Probe.Series.WORK_OTHER]).is_equal(played["other_work"])
	assert_array(series[Probe.Series.WORK_OTHER_REF]).is_equal(played["other_ref"])
	assert_array(series[Probe.Series.TICK_REF]).is_equal(played["tick_samples"])
	assert_int(series[Probe.Series.INTERVAL].size()).is_equal(frames - 1)
	var report: String = probe.report()
	assert_float(_value(report, "C1 refresh_hz_start")).is_equal(60.0)
	assert_float(_value(report, "C1 refresh_hz_end")).is_equal(59.94)
	assert_float(_value(report, "C1 period_ms")).is_equal(16.667)  # From the start's 60.00 Hz.
	assert_float(_value(report, "C1 median_floor_ms")).is_equal(16.333)  # P x 0.98.
	assert_float(_value(report, "C1 median_ms")).is_equal_approx(17.0, 0.05)
	assert_float(_value(report, "C2 ref_peak_p25_us")).is_equal(50.0)
	assert_float(_value(report, "C2 ref_peak_p95_us")).is_equal(400.0)
	assert_float(_value(report, "C2 warmup_p25_us")).is_equal(1009.0)  # 10th of 1000-1039.
	# C3 and C4 with the burst's p25 (50 us) on the values played; the guards keep them apart.
	var other: PerfProbeCalib.Stats = PerfProbeCalib.stats(
		played["other_work"], played["other_ref"], 50.0
	)
	assert_float(other.ref_p50_us).is_greater(other.ref_span_us)
	assert_float(other.ref_p95_us).is_greater(other.ref_p50_us)
	assert_float(other.p95_raw - other.p95_class).is_greater(0.1)
	assert_float(absf(other.p95_frame - other.p95_class)).is_greater(0.1)
	assert_float(_value(report, "C3 other_ref_span_us")).is_equal(snappedf(other.ref_span_us, 0.1))
	assert_float(_value(report, "C3 other_ref_p50_us")).is_equal(snappedf(other.ref_p50_us, 0.1))
	assert_float(_value(report, "C3 other_ref_p95_us")).is_equal(snappedf(other.ref_p95_us, 0.1))
	_expect_ms(report, "C3 other_work_p95_raw_ms", other.p95_raw)
	_expect_ms(report, "C3 other_work_p95_norm_class_ms", other.p95_class)
	_expect_ms(report, "C3 other_work_p95_norm_frame_ms", other.p95_frame)
	var tick: PerfProbeCalib.Stats = PerfProbeCalib.stats(
		series[Probe.Series.TICK], played["tick_samples"], 50.0
	)
	assert_float(tick.mean_raw - tick.mean_class).is_greater(0.001)
	assert_float(absf(tick.mean_frame - tick.mean_class)).is_greater(0.001)
	assert_float(_value(report, "C4 tick_ref_span_us")).is_equal(snappedf(tick.ref_span_us, 0.1))
	assert_float(_value(report, "C4 tick_ref_p50_us")).is_equal(snappedf(tick.ref_p50_us, 0.1))
	assert_float(_value(report, "C4 tick_ref_p95_us")).is_equal(snappedf(tick.ref_p95_us, 0.1))
	_expect_ms(report, "C4 tick_mean_raw_ms", tick.mean_raw)
	_expect_ms(report, "C4 tick_mean_norm_class_ms", tick.mean_class)
	_expect_ms(report, "C4 tick_mean_norm_frame_ms", tick.mean_frame)
	# All frames: each work value still with its own frame's sample.
	var all: PerfProbeCalib.Stats = PerfProbeCalib.stats(
		played["all_work"], played["all_ref"], 50.0
	)
	assert_float(probe._stats_all().p95_frame).is_equal_approx(all.p95_frame, 1e-9)
	assert_float(probe._stats_all().mean_frame).is_equal_approx(all.mean_frame, 1e-9)
	# C5 and the pacing rows: 39 intervals, three above drop_ms (25 ms), one of them a hitch.
	var mean: float = PerfProbeTick.mean(played["interval"])
	assert_float(_value(report, "C5 frames")).is_equal(39.0)
	assert_float(_value(report, "C5 dropped")).is_equal(3.0)
	assert_float(_value(report, "C5 dropped_pct")).is_equal(7.69)
	assert_float(_value(report, "C5 cadence_pct")).is_equal_approx(100.0 * 16.6667 / mean, 0.02)
	assert_float(_value(report, "C5 hitches")).is_equal(1.0)
	assert_str(report).contains("dropped (interval > drop_ms) 3 of 39 (7.69 %) | cadence ")
	assert_str(report).contains("| hitches (>= 66.7 ms) 1\n")
	assert_str(report).contains("extra slots 0/1/2/>=3: 36/1/1/1")
	assert_str(probe._card.text).is_equal(probe.card())
	assert_str(probe._card.text).contains("refresh_hz start 60.00, end 59.94")
	assert_str(probe._card.text).contains("frames 39 | dropped 3 (7.69 %) | cadence ")
	remove_child(probe)
	probe.free()


## Mode 4 played by hand: the frames that publish a tick are the tick frames and every other frame
## is an other frame (C3 compares those), and C5 prints the worker job as ADR 0012 times it, raw:
## the step and the slice, timed around them on the worker. The tick body and the post to done stay
## as diagnostics.
func test_in_the_worker_mode_publish_frames_are_tick_frames_and_c5_is_the_whole_raw_job() -> void:
	var refs: Array[float] = [0.0, 0.0]
	var probe: Node2D = _open_by_hand(refs, [60.0])
	var button: Button = probe.get_node("Hud/Margin/Buttons/RingsButton")
	for _press: int in WORKER_MODE:
		button.pressed.emit()
	assert_bool(probe.worker_active()).is_true()
	probe._ref_peak = PackedFloat64Array(PEAK)  # The mode's start ran its own (empty) burst.
	var published: int = 0
	var other_work: PackedFloat64Array = PackedFloat64Array()
	var other_ref: PackedFloat64Array = PackedFloat64Array()
	for i: int in 36:
		OS.delay_msec(10)  # Time for the posted job; a held tick would still be filed correctly.
		var sample: float = SAMPLES[i % SAMPLES.size()]
		var work: float = 1.0 + 0.5 * (i % 4)
		var tick_frames: int = _size(probe, Probe.Series.WORK_TICK)
		var others: int = _size(probe, Probe.Series.WORK_OTHER)
		var ticked: bool = _play(probe, refs, 17.0, 1000.0 + i, sample, work)
		assert_int(_size(probe, Probe.Series.WORK_TICK) - tick_frames).is_equal(int(ticked))
		assert_int(_size(probe, Probe.Series.WORK_OTHER) - others).is_equal(int(not ticked))
		published += int(ticked)
		if not ticked:
			other_work.append(work)
			other_ref.append(sample)
	assert_int(published).is_greater_equal(4)
	assert_int(other_work.size()).is_greater_equal(10)
	var report: String = probe.report()
	var other: PerfProbeCalib.Stats = PerfProbeCalib.stats(other_work, other_ref, 50.0)
	_expect_ms(report, "C3 other_work_p95_raw_ms", other.p95_raw)
	_expect_ms(report, "C3 other_work_p95_norm_class_ms", other.p95_class)
	_expect_ms(report, "C3 other_work_p95_norm_frame_ms", other.p95_frame)
	var job: PackedFloat64Array = probe._series[Probe.Series.JOB]
	var tick: PackedFloat64Array = probe._series[Probe.Series.TICK]
	var done: PackedFloat64Array = probe._series[Probe.Series.LATENCY]
	assert_int(job.size()).is_equal(published)
	assert_int(tick.size()).is_equal(published)
	assert_int(done.size()).is_equal(published)
	for k: int in job.size():
		assert_float(job[k]).is_greater_equal(tick[k])  # The job holds the tick body,
		assert_float(job[k]).is_less_equal(done[k])  # and starts after the post, at the wake-up.
	_expect_ms(report, "C5 job_mean_ms", PerfProbeTick.mean(job))
	_expect_ms(report, "C5 job_p95_ms", PerfProbeTick.percentile(job, 95))
	_expect_ms(report, "C5 job_tick_mean_ms", PerfProbeTick.mean(tick))
	_expect_ms(report, "C5 job_tick_p95_ms", PerfProbeTick.percentile(tick, 95))
	_expect_ms(report, "C5 job_done_mean_ms", PerfProbeTick.mean(done))
	_expect_ms(report, "C5 job_done_p95_ms", PerfProbeTick.percentile(done, 95))
	remove_child(probe)  # Joins the worker.
	probe.free()


## On Michael's Pixel 9a (420 dpi, stretch 1.5, a 152 px cutout: a 1616x720 view) the finished card
## fits the safe area left of the buttons, so "Next mode" and "Copy report" stay on screen, and
## "Copy report" copies the whole report with its CALIBRATION block. Mode 1, then mode 4.
func test_the_finished_card_fits_michaels_phone_and_copy_report_copies_the_whole_report() -> void:
	var michael: UiMetrics = UiMetrics.create(
		"Android", 420, 1.0, 1.5, Vector2i(2424, 1080), Rect2i(152, 0, 2272, 1080)
	)
	UiScale.set_override(michael)
	get_window().size = michael.window_size
	await await_idle_frame()
	var copied: Array[String] = []
	var probe: Node2D = load(SCENE).instantiate()
	probe.burst_usec = 20000
	probe.run_seconds = 1
	probe.clipboard_sink = func(text: String) -> void: copied.append(text)
	var draw: FakeDraw = _open_drawn(probe)
	for label: String in ["mode 1", "mode 4"]:
		if label == "mode 4":
			for _press: int in WORKER_MODE:
				probe.get_node("Hud/Margin/Buttons/RingsButton").pressed.emit()
		await await_millis(1500)
		await await_idle_frame()
		await await_idle_frame()  # The containers have laid the finished card out.
		assert_int(probe._end_us).override_failure_message(label + ": not done").is_greater(0)
		assert_str(probe._card.text).is_equal(probe.card())
		var safe: Rect2 = UiScale.safe_rect_base()
		var card: Rect2 = probe._card.get_global_rect()
		var why: String = "%s: card %s in %s" % [label, card, safe]
		assert_bool(safe.encloses(card)).override_failure_message(why).is_true()
		for button: Button in [probe._rings_button, probe._copy_button]:
			var rect: Rect2 = button.get_global_rect()
			why = "%s: %s %s in %s, card %s" % [label, button.text, rect, safe, card]
			assert_bool(button.visible).override_failure_message(why).is_true()
			assert_bool(safe.encloses(rect)).override_failure_message(why).is_true()
			assert_float(card.end.x).override_failure_message(why).is_less_equal(rect.position.x)
		probe._copy_button.pressed.emit()
		assert_str(copied.back()).is_equal(probe.report())
		assert_str(copied.back()).contains("CALIBRATION P26n2 | %s" % label)
	_close(probe, draw)


## Every card names its start tick; the report carries the pacing and CPU rows and a CALIBRATION
## block with the values of the checks this mode feeds (C3: modes 1, 4, 5; C4: modes 1, 2; the
## worker's raw job times: modes 4, 5).
func test_each_mode_reports_its_start_tick_pacing_cpu_rows_and_calibration_values() -> void:
	var probe: Node2D = load(SCENE).instantiate()
	probe.burst_usec = 50000
	var draw: FakeDraw = _open_drawn(probe)
	await await_millis(1200)  # About 18 ticks: a fog patch every third.
	var first: String = probe.report()
	assert_str(probe._card.text).contains("start tick 3 (a fresh tick in every mode)")
	for row: String in [
		"start tick 3 (a fresh tick in every mode)",
		"refresh_hz start ",
		"pacing, window = the whole timed run (heavy throughout): P ",
		"dropped (interval > drop_ms) ",
		"| cadence ",
		"| hitches (>= 66.7 ms) ",
		"interval median ",
		"extra slots 0/1/2/>=3: ",
		"jitter (<= 17.5 ms, diagnostic, was on time) ",
		"ref loop (1000 iterations): ref_peak p25 ",
		"cpu all frames, work: n ",
		"cpu tick frames, work: n ",
		"cpu other frames, work: n ",
		"cpu fog patches: n ",
		"in-frame tick mean: raw ",
		"CALIBRATION P26n2 | mode 1 (sprite rings) | start_tick 3",
		"C1 refresh_hz_start=",
		"C1 refresh_hz_end=",
		"C1 median_floor_ms=",
		"C2 ref_peak_p95_us=",
		"C2 warmup_p25_us=",
		"C5 cadence_pct=",
		"C5 hitches=",
	]:
		assert_str(first).contains(row)
	if DisplayServer.screen_get_refresh_rate() <= 0.0:  # Headless: P and V from max_fps 60.
		assert_str(first).contains("drop_ms 25.00 (refresh unknown: max_fps assumed)")
	assert_float(_value(first, "C2 ref_peak_p25_us")).is_greater(0.0)
	assert_float(_value(first, "C4 tick_mean_raw_ms")).is_greater(0.0)
	var raw: float = _value(first, "C3 other_work_p95_raw_ms")
	assert_float(raw).is_greater(0.0)
	assert_float(_value(first, "C3 other_work_p95_norm_class_ms")).is_less_equal(raw)
	assert_float(_value(first, "C3 other_work_p95_norm_frame_ms")).is_less_equal(raw)
	assert_str(first).not_contains("C5 job_")
	var button: Button = probe.get_node("Hud/Margin/Buttons/RingsButton")
	button.pressed.emit()  # Mode 2: the in-frame tick (C4), not C3.
	await await_millis(300)
	var second: String = probe.report()
	assert_str(second).contains("CALIBRATION P26n2 | mode 2 (code rings) | start_tick 3")
	assert_str(second).contains("C4 tick_mean_norm_frame_ms=")
	assert_str(second).not_contains("C3 ")
	button.pressed.emit()
	button.pressed.emit()  # Mode 4: C3 and the raw job times, no in-frame tick.
	await await_millis(1200)
	var fourth: String = probe.report()
	assert_str(fourth).contains("CALIBRATION P26n2 | mode 4 (sprite rings, worker tick)")
	assert_str(fourth).contains("start tick 3 (a fresh tick in every mode)")
	assert_str(fourth).contains("C3 other_work_p95_norm_class_ms=")
	assert_str(fourth).not_contains("C4 ")
	assert_str(fourth).not_contains("in-frame tick mean")
	var tick_mean: float = _value(fourth, "C5 job_tick_mean_ms")
	assert_float(tick_mean).is_greater(0.0)
	assert_float(_value(fourth, "C5 job_tick_p95_ms")).is_greater(0.0)
	# The job (C5) is the tick body and the slice, timed around them on the worker.
	assert_float(_value(fourth, "C5 job_mean_ms")).is_greater_equal(tick_mean)
	assert_float(_value(fourth, "C5 job_p95_ms")).is_greater(0.0)
	assert_float(_value(fourth, "C5 job_done_mean_ms")).is_greater(0.0)
	assert_float(_value(fourth, "C5 job_done_p95_ms")).is_greater(0.0)
	_close(probe, draw)


## The probe in the tree with no burst and no frames of its own (the test plays them): the first
## ref run of a frame returns `refs[0]` (the warm-up) and the second `refs[1]` (the sample); the
## refresh rate is `refresh[0]` whenever the probe reads it; `ref_peak` is `PEAK`.
func _open_by_hand(refs: Array[float], refresh: Array[float]) -> Node2D:
	var probe: Node2D = load(SCENE).instantiate()
	probe.burst_usec = 0
	var calls: Array[int] = [0]
	probe.ref_sampler = func() -> float:
		calls[0] += 1
		return refs[1 - calls[0] % 2]
	probe.refresh_source = func() -> float: return refresh[0]
	add_child(probe)
	probe.set_process(false)
	probe._ref_peak = PackedFloat64Array(PEAK)
	return probe


## One frame played by hand: an interval of `interval_ms`, ref runs that return `warm_up` and
## `sample`, `work_ms` of process time, then the draw. True when the frame ran or published a tick.
func _play(
	probe: Node2D,
	refs: Array[float],
	interval_ms: float,
	warm_up: float,
	sample: float,
	work_ms: float
) -> bool:
	refs[0] = warm_up
	refs[1] = sample
	var ticks: int = _size(probe, Probe.Series.TICK)
	probe._last_us = Time.get_ticks_usec() - roundi(interval_ms * 1000.0)
	probe._process(0.0)
	probe._pre_draw_us = probe._process_start_us + roundi(work_ms * 1000.0)
	probe._on_post_draw()  # Headless render CPU time is 0: the work is `work_ms`.
	return _size(probe, Probe.Series.TICK) > ticks


func _size(probe: Node2D, series: int) -> int:
	return probe._series[series].size()


## The report's "key=value" line in ms with three decimals is `expected`.
func _expect_ms(report: String, key: String, expected: float) -> void:
	assert_float(_value(report, key)).override_failure_message(key).is_equal_approx(expected, 6e-4)


## The probe in the tree with a stand-in for the draw after it.
func _open_drawn(probe: Node2D) -> FakeDraw:
	add_child(probe)
	var draw: FakeDraw = FakeDraw.new()
	draw.probe = probe
	add_child(draw)
	return draw


func _close(probe: Node2D, draw: FakeDraw) -> void:
	remove_child(draw)
	draw.free()
	remove_child(probe)
	probe.free()


func _steady(value: float, count: int) -> PackedFloat64Array:
	var values: PackedFloat64Array = PackedFloat64Array()
	for _i: int in count:
		values.append(value)
	return values


## The number after "key=" on its own line of a report.
func _value(report: String, key: String) -> float:
	var found: RegExMatch = RegEx.create_from_string("(?m)^%s=([-\\d.]+)$" % key).search(report)
	(
		assert_object(found)
		. override_failure_message("no line %s= in:\n%s" % [key, report])
		. is_not_null()
	)
	return found.get_string(1).to_float() if found != null else -1.0
