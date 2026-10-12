extends GdUnitTestSuite
## Spike P26n2 (ADR 0014 section 5, never merged): the perf probe's calibration rows. The pure
## helpers of PerfProbeCalib are pinned on hand-made numbers: drop_ms, cadence, hitches, the
## extra-slot histogram, both normalisations (never above raw, clamped at min(1, ...)) and the
## burst's second half. The scene tests prove that the two ref runs open every timed frame outside
## its work with the first one discarded, that the burst runs at every mode start outside the timed
## window, and that each mode's report carries the rows its checks need. Mode 5 and the same-state
## check of modes 1, 2, 4 and 5 are in tests/ui/test_perf_probe_native.gd (they need the library).
## Timing is never asserted beyond a long frame being kept out.

const Probe: GDScript = preload("res://game/ui/perf_probe.gd")
const SCENE: String = "res://scenes/dev/perf_probe.tscn"
const SLOW_REF_MS: int = 60  ## A fake ref run this long: two per frame are 120 ms of the interval.
const WARM_UP_US: int = 111
const SAMPLE_US: int = 222


## Headless Godot draws nothing, so RenderingServer emits no frame_pre_draw or frame_post_draw.
## This node, processed after the probe in the same frame, stands in for the draw. With a real
## draw the probe files the frame once: its `_sampled` flag is cleared by the first post-draw.
class FakeDraw:
	extends Node

	var probe: Node2D = null

	func _init() -> void:
		process_priority = 1000

	func _process(_delta: float) -> void:
		probe._on_pre_draw()
		probe._on_post_draw()


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
## first is the discarded warm-up and the second the frame's sample, filed with the frame's work.
func test_the_ref_runs_open_every_timed_frame_outside_its_work_and_the_first_is_discarded() -> void:
	var calls: Array[int] = [0]
	var probe: Node2D = load(SCENE).instantiate()
	probe.burst_usec = 0  # No burst: only the per-frame runs call the sampler.
	probe.ref_sampler = func() -> int:
		calls[0] += 1
		OS.delay_msec(SLOW_REF_MS)
		return WARM_UP_US if calls[0] % 2 == 1 else SAMPLE_US
	var draw: FakeDraw = _open_drawn(probe)
	await await_millis(1500)
	var series: Array[PackedFloat64Array] = probe._series
	var warm: PackedFloat64Array = series[Probe.Series.WARMUP]
	var work: PackedFloat64Array = series[Probe.Series.WORK_TICK] + series[Probe.Series.WORK_OTHER]
	var refs: PackedFloat64Array = (
		series[Probe.Series.WORK_TICK_REF] + series[Probe.Series.WORK_OTHER_REF]
	)
	assert_int(warm.size()).is_greater_equal(4)
	assert_int(calls[0]).is_equal(2 * warm.size())  # Two runs per timed frame, none elsewhere.
	assert_array(warm).is_equal(_steady(WARM_UP_US, warm.size()))
	assert_int(work.size()).is_greater_equal(3)
	assert_array(refs).is_equal(_steady(SAMPLE_US, work.size()))
	assert_array(series[Probe.Series.TICK_REF]).is_equal(
		_steady(SAMPLE_US, series[Probe.Series.TICK].size())
	)
	assert_float(PerfProbeTick.percentile(work, 100)).is_less(SLOW_REF_MS)
	assert_float(PerfProbeTick.percentile(series[Probe.Series.PROCESS], 100)).is_less(SLOW_REF_MS)
	# The interval runs from frame start to frame start, the two ref runs included.
	assert_float(PerfProbeTick.percentile(series[Probe.Series.INTERVAL], 50)).is_greater_equal(
		2 * SLOW_REF_MS
	)
	var report: String = probe.report()
	assert_str(report).contains("warm-up p25 %.1f us" % WARM_UP_US)
	assert_str(report).contains("ref_span p25 %.1f us" % SAMPLE_US)
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
	assert_float(_value(fourth, "C5 job_tick_mean_ms")).is_greater(0.0)
	assert_float(_value(fourth, "C5 job_tick_p95_ms")).is_greater(0.0)
	assert_float(_value(fourth, "C5 job_done_mean_ms")).is_greater(0.0)
	assert_float(_value(fourth, "C5 job_done_p95_ms")).is_greater(0.0)
	_close(probe, draw)


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
