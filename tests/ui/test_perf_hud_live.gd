extends GdUnitTestSuite
## PerfHud part 1 (plan P50a, ADR 0014 sections 1 and 3), the live path and `restart()`: which frame
## is a publish frame, the interval anchor that `restart()` resets, every sample column it clears,
## the runner counts that freeze with the run, the reference runs on the gate's iterations, the
## frame's own reference sample, the units of the render and draw-call readings, the wiring of
## `_ready` and what a HUD without a runner or outside the tree does. Headless Godot never emits
## `frame_pre_draw` or `frame_post_draw` (no frame is drawn), so these cases call `_process`,
## `_on_pre_draw` and `_on_post_draw` themselves, in the order of a real frame, on a scripted clock.
## The samples are in test_perf_hud.gd, the verdicts in test_perf_hud_verdicts.gd and
## test_perf_hud_gate.gd, the normalisation in test_perf_hud_norm.gd.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")

## The scripted clock of the cases: each call returns the next time of the script (us).
var _times: Array[int] = []
var _log: Array[String] = []


func after_test() -> void:
	_times.clear()
	_log.clear()
	CommandQueue.clear()


func test_ready_wires_the_probe_the_draw_signals_and_the_top_of_the_frame() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var hud: PerfHud = auto_free(Rig.hud())
	hud.runner = runner
	add_child(hud)
	assert_int(hud.process_priority).is_equal(-1000)
	assert_bool(runner.ticked.is_connected(hud._on_ticked)).is_true()
	assert_bool(RenderingServer.frame_pre_draw.is_connected(hud._on_pre_draw)).is_true()
	assert_bool(RenderingServer.frame_post_draw.is_connected(hud._on_post_draw)).is_true()


func test_a_frame_that_published_a_tick_is_a_publish_frame_and_the_next_is_not() -> void:
	var runner: MatchRunner = _arena_runner()
	var hud: PerfHud = _live(runner)
	# Frame 1 only anchors. Frame 2 (top at 17667, sample 17700 to 17725) publishes tick 1 between
	# the top of the frame and the draw, so it is a publish frame with 8 ms of work. Frame 3 (top
	# at 34334) publishes nothing and has 2 ms of work. Each frame reads the clock at its top, twice
	# more for the reference runs from the second frame, and at the draw.
	_times = [1000, 1100, 17667, 17700, 17725, 25725, 34334, 34360, 34385, 36385]
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	hud._process(0.0)
	runner.run_ticks(1)
	hud._on_pre_draw()
	hud._on_post_draw()
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	assert_array(_times).is_empty()
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(2)
	assert_int(s["heavy_publish_frames"]).is_equal(1)
	assert_float(s["work_tick_p95_ms"]).is_equal_approx(8.0, 0.0001)
	assert_float(s["work_other_p95_ms"]).is_equal_approx(2.0, 0.0001)
	assert_float(s["work_p95_ms"]).is_equal_approx(8.0, 0.0001)


func test_restart_after_a_finished_run_anchors_the_next_interval_again() -> void:
	var hud: PerfHud = _live(_arena_runner())
	_times = [1000, 1100, 17667, 17700, 17725, 21725]
	hud._process(0.0)
	hud._on_pre_draw()
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	assert_int(hud.summary()["frames"]).is_equal(1)
	hud.record_snapshot(Rig.snapshot(hud.run_ticks))  # The run ends; the card is up.
	hud._process(0.0)  # A finished run reads no clock: the anchor stays at frame 2.
	assert_array(_times).is_empty()
	hud.restart()  # "Run again": a burst and a match start lie between the two runs.
	_times = [900_000, 900_100]
	hud._process(0.0)  # The anchor alone: no interval, no reference runs, no frame.
	hud._on_pre_draw()
	hud._on_post_draw()
	assert_array(_times).is_empty()
	assert_int(hud.summary()["frames"]).is_equal(0)
	_times = [916_667, 916_700, 916_725, 920_725]
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(1)
	assert_float(s["frame_max_ms"]).is_equal_approx(16.667, 0.0001)  # Not the 900 ms gap.
	assert_int(s["hitches"]).is_equal(0)


func test_a_frame_in_progress_at_a_restart_is_not_recorded() -> void:
	var hud: PerfHud = _live(_arena_runner())
	_times = [1000, 1100, 17667, 17700, 17725, 21725]
	hud._process(0.0)
	hud._on_pre_draw()
	hud._process(0.0)  # The second frame has its interval and its sample.
	hud.restart()  # The burst of a "Run again" may lie in this frame: it belongs to no run.
	hud._on_pre_draw()
	hud._on_post_draw()
	assert_array(_times).is_empty()
	assert_int(hud.summary()["frames"]).is_equal(0)


func test_restart_clears_phases_flow_alive_checkpoints_and_the_mode() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var rules: RulesDef = RulesDef.new()
	for tick: int in range(1, 301):  # Two checkpoints, every column filled.
		var snap: MatchSnapshot = Rig.snapshot(tick)
		snap.unit_id = PackedInt32Array([1, 2, 3])
		snap.phase_usec = PackedInt64Array()
		snap.phase_usec.resize(SimProbe.Phase.COUNT)
		snap.phase_usec.fill(500)
		snap.stats.resize(World.Stat.ROWS_COMPACTED + 1)
		snap.stats[World.Stat.FLOW_CELLS] = rules.flow_cells_per_tick
		hud.record_snapshot(snap)
	var before: Dictionary = hud.summary()
	assert_float(before["flow_slice_p95_ms"]).is_equal_approx(0.5, 0.0001)
	assert_float(before["phases_ms"][0]).is_equal_approx(0.5, 0.0001)
	assert_int(before["alive"]).is_equal(3)
	assert_array(before["checkpoints"]).has_size(2)
	assert_str(before["hash_hex"]).is_not_empty()
	assert_str(before["tick_mode"]).is_equal("WORKER")
	hud.restart()
	var s: Dictionary = hud.summary()
	assert_float(s["flow_slice_p95_ms"]).is_equal(0.0)
	assert_int(s["alive"]).is_equal(0)
	assert_array(s["checkpoints"]).is_empty()
	assert_str(s["hash_hex"]).is_empty()
	assert_str(s["tick_mode"]).is_equal("SYNC")
	for ms: float in s["phases_ms"]:
		assert_float(ms).is_equal(0.0)
	# The next run keeps nothing of this one: its own hash at tick 150 is the first checkpoint, and
	# its phase mean is over its own tick.
	var next: MatchSnapshot = Rig.snapshot(150)
	next.phase_usec = PackedInt64Array()
	next.phase_usec.resize(SimProbe.Phase.COUNT)
	next.phase_usec.fill(1000)
	next.last_hash = 999
	hud.record_snapshot(next)
	var t: Dictionary = hud.summary()
	assert_array(t["checkpoints"]).has_size(1)
	assert_str(t["checkpoints"][0]["hash_hex"]).is_equal(World.hash_hex(999))
	assert_float(t["phases_ms"][0]).is_equal_approx(1.0, 0.0001)


func test_the_runner_counts_freeze_when_the_run_ends() -> void:
	var runner: MatchRunner = _arena_runner()
	var hud: PerfHud = _live(runner)
	hud.run_ticks = 3
	runner.run_ticks(2)
	runner.held_ticks = 4
	runner.run_ticks(1)  # Tick 3 ends the run; its counts are copied at the publish.
	var frozen: Array = [runner.late_ticks, runner.held_ticks, runner.latency_usec_max]
	runner.late_ticks = 9  # Counted after the end: the card must not move.
	runner.held_ticks = 7
	runner.latency_usec_max = 5_000_000_000
	runner.run_ticks(2)
	var s: Dictionary = hud.summary()
	assert_array([s["late_ticks"], s["held_ticks"], s["latency_usec_max"]]).is_equal(frozen)
	assert_int(s["held_ticks"]).is_equal(4)


func test_the_reference_runs_use_the_gates_iterations() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	gate.ref_iterations = 7
	var hud: PerfHud = _live(_arena_runner(), gate)
	_times = [1000, 17667, 17700, 17725]
	hud._process(0.0)
	hud._process(0.0)
	assert_array(_log).is_equal(["clock", "clock", "ref 7", "clock", "ref 7", "clock"])


func test_a_frame_files_its_own_reference_sample_and_the_normalisation_uses_it() -> void:
	var hud: PerfHud = _live(_arena_runner())  # The rig's burst peak is 25 us.
	hud.fog_source = func() -> int: return 250
	# Frame 2: top at 17667, warm-up to 17700, the sample from 17700 to 17750 (50 us: half the speed
	# of the burst, unlike the 25 us of every other case), 4 ms of work, drawn at 21750.
	_times = [1000, 17667, 17700, 17750, 21750]
	hud._process(0.0)
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	var s: Dictionary = hud.summary()
	assert_int(s["frames"]).is_equal(1)
	assert_float(s["work_p95_ms"]).is_equal_approx(4.0, 0.0001)
	assert_float(s["work_p95_norm_ms"]).is_equal_approx(2.0, 0.0001)  # x 25 / 50.
	assert_float(s["fog_update_p95_norm_ms"]).is_equal_approx(0.125, 0.0001)
	assert_float(s["speed_main_pct"]).is_equal_approx(50.0, 0.0001)


func test_the_render_and_draw_call_readings_enter_the_frame_in_their_own_units() -> void:
	var hud: PerfHud = _live(_arena_runner())
	hud.render_source = func() -> float: return 2.5  # ms, as the viewport reports it.
	hud.calls_source = func() -> int: return 55
	_times = [1000, 17667, 17700, 17725, 21725]  # 4 ms between the sample and the draw.
	hud._process(0.0)
	hud._process(0.0)
	hud._on_pre_draw()
	hud._on_post_draw()
	var s: Dictionary = hud.summary()
	assert_float(s["render_cpu_p95_ms"]).is_equal_approx(2.5, 0.0001)
	assert_float(s["view_p95_ms"]).is_equal_approx(4.0, 0.0001)
	assert_float(s["work_p95_ms"]).is_equal_approx(6.5, 0.0001)  # Process plus render.
	assert_int(s["draw_calls_p95"]).is_equal(55)


func test_a_hud_without_a_runner_in_the_tree_stays_inactive() -> void:
	var hud: PerfHud = auto_free(Rig.hud())  # The card's layout cases place one so.
	hud.clock = func() -> int:
		_log.append("clock")
		return 1
	add_child(hud)
	assert_int(hud.process_priority).is_equal(-1000)
	hud._process(0.0)
	hud._on_post_draw()
	assert_array(_log).is_empty()
	assert_int(hud.summary()["frames"]).is_equal(0)


func test_a_hud_that_leaves_the_tree_takes_no_more_frames() -> void:
	var hud: PerfHud = _live(_arena_runner())
	remove_child(hud)
	_times = [1000, 2000, 3000, 4000]
	hud._process(0.0)
	hud._process(0.0)
	hud._on_post_draw()
	assert_array(_log).is_empty()
	assert_int(hud.summary()["frames"]).is_equal(0)


func test_an_auto_runner_that_resolved_to_sync_is_a_sync_run() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.tick_mode = MatchRunner.TickMode.AUTO  # P50b sets AUTO: SYNC headless and on web.
	runner.start()
	assert_bool(runner.worker_active()).is_false()
	var hud: PerfHud = auto_free(Rig.hud())
	hud.runner = runner
	add_child(hud)
	hud.restart()
	runner.late_ticks = 3  # An inline tick counted late; the gate allows 0.
	runner.run_ticks(1)
	var s: Dictionary = hud.summary()
	assert_str(s["tick_mode"]).is_equal("SYNC")  # The resolved mode, not the requested one.
	# At least the 3 set: an inline tick slower than a tick period counts late too under load.
	assert_int(s["late_ticks"]).is_greater_equal(3)
	assert_bool(Rig.failed(s).has("late_ticks_max")).is_false()
	assert_array(s["verdicts"]).contains(
		["late_ticks_max: n/a (SYNC: late_ticks counts inline ticks)"]
	)


func _scripted_clock() -> int:
	_log.append("clock")
	return _times.pop_front()


## A started runner on the seed-42 perf arena, in SYNC: `run_ticks` publishes inline.
func _arena_runner() -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.start()
	return runner


## A HUD on `runner` in the tree, 140 rigs drawn per frame, the scripted clock and a reference step
## that only logs; restarted, so the next `_process` is the anchor.
func _live(runner: MatchRunner, gate: PerfGateDef = null) -> PerfHud:
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.runner = runner
	hud.clock = _scripted_clock
	hud.rigs_source = func() -> int: return 140
	hud.ref_step = func(iterations: int) -> void: _log.append("ref %d" % iterations)
	add_child(hud)
	hud.restart()
	return hud
