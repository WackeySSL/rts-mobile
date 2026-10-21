extends GdUnitTestSuite
## PerfHud part 3 (plan P50a3, ADR 0011 section 5, ADR 0014 section 3), the two buttons under the
## card's text. "Copy report" passes the summary as JSON, every key of it, to the injected
## `clipboard_sink` (the test never reads the DisplayServer clipboard: headless it logs an error).
## "Run again" calls `runner.wait_idle()`, then the burst seam alone (never the self-check), then
## `runner.start()` and `restart()`, so runs 2 and 3 each normalise against a peak measured right
## before them, with no job in flight and outside every timed window. The runner is a SYNC spy that
## logs its calls into the same list as the seams. The layout of the buttons: test_perf_hud_card.gd.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const SpyRunner: GDScript = preload("res://tests/ui/support/spy_runner.gd")
## What a second burst measures, in us: its p25 and p95 differ from the rig's 25.
const SECOND_BURST: PackedFloat64Array = [40.0, 50.0, 60.0, 70.0]

var _calls: Array[String] = []
var _sent: Array[String] = []


func after_test() -> void:
	_calls.clear()
	_sent.clear()
	CommandQueue.clear()


## Every summary key the plan names for this report, as ADR 0013 section 15 and ADR 0014 section 4
## list them, and the INVALID reasons, checkpoints and the per-phase p95s.
func test_copy_report_passes_valid_json_with_every_summary_key_to_the_sink() -> void:
	var hud: PerfHud = _finished_hud(null, true)  # A pause in the run: INVALID, with its reason.
	hud.copy_report()
	assert_array(_sent).has_size(1)
	var json: JSON = JSON.new()
	assert_int(json.parse(_sent[0])).is_equal(OK)
	var report: Dictionary = json.data
	var summary: Dictionary = hud.summary()
	var want: Array = summary.keys()
	var got: Array = report.keys()
	want.sort()
	got.sort()
	assert_array(got).is_equal(want)  # Every key, and no other.
	for key: String in [
		"phases_p95_noncp_ms",
		"job_p95_noncp_ms",
		"job_minus_step_p95_cp_ms",
		"job_minus_step_p95_noncp_ms",
		"sim_impl",
		"native_phases",
		"native_build",
		"self_check",
		"ref_peak_us",
		"ref_peak_p95_us",
		"work_p95_norm_ms",
		"extra_slots",
		"verdicts",
		"checkpoints",
	]:
		assert_bool(report.has(key)).override_failure_message(key).is_true()
	assert_array(report["invalid_reasons"]).is_equal([PerfHud.REASON_APP_PAUSED])
	assert_bool(report["invalid"]).is_true()
	assert_bool(report["gate_pass"]).is_false()
	assert_array(report["phases_p95_noncp_ms"]).has_size(SimProbe.Phase.COUNT)
	assert_float(report["ref_peak_us"]).is_equal(25.0)
	assert_array(report["checkpoints"]).has_size(6)  # Ticks 150 to 900, with their hash text.
	assert_int(int(report["checkpoints"][0]["tick"])).is_equal(150)
	assert_str(report["checkpoints"][0]["hash_hex"]).is_equal(World.hash_hex(Rig.last_hash(150)))
	assert_str(_sent[0]).is_equal(JSON.stringify(summary, "", true))  # The summary as it is.


func test_copy_report_of_a_run_without_samples_is_valid_json_too() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.clipboard_sink = _sink
	hud.copy_report()  # No frame, no tick: every division of the summary meets an empty run.
	var json: JSON = JSON.new()
	assert_int(json.parse(_sent[0])).is_equal(OK)
	assert_array((json.data as Dictionary).keys()).contains(["frames", "gate_pass", "checkpoints"])
	assert_bool(json.data["gate_pass"]).is_false()


func test_the_copy_button_sends_the_report_and_says_so_until_the_next_run() -> void:
	var hud: PerfHud = _finished_hud()
	var button: Button = hud.get_node("Column/Buttons/CopyReport")
	assert_str(button.text).is_equal("Copy report")
	button.pressed.emit()
	assert_array(_sent).has_size(1)
	assert_str(_sent[0]).is_equal(JSON.stringify(hud.summary(), "", true))
	assert_str(button.text).is_equal("Copied")
	hud.restart()
	assert_str(button.text).is_equal("Copy report")


func test_run_again_waits_for_the_job_then_runs_the_burst_alone_then_starts_and_restarts() -> void:
	var runner: SpyRunner = _spy_runner()
	var hud: PerfHud = _finished_hud(runner)
	assert_bool(hud.visible).is_true()  # The card is up and the runner paused.
	assert_bool(runner.paused).is_true()
	var serial: int = runner.match_serial
	_watch(hud, runner)
	runner.busy = true  # A job in flight: a preflight that comes before wait_idle() is refused.
	var button: Button = hud.get_node("Column/Buttons/RunAgain")
	assert_str(button.text).is_equal("Run again")
	button.pressed.emit()
	# The burst once, the self-check never, both before the runner's start(), then restart().
	assert_array(_calls).is_equal(["wait_idle", "burst", "start", "restart"])
	var s: Dictionary = hud.summary()
	assert_array(s["invalid_reasons"]).is_empty()
	assert_int(s["runs"]).is_equal(2)
	assert_int(runner.match_serial).is_equal(serial + 1)  # A new match, on the same seed.
	assert_int(runner.match_seed).is_equal(42)
	assert_bool(hud.visible).is_false()
	assert_bool(runner.paused).is_false()


func test_run_again_takes_ref_peak_from_the_new_burst_and_keeps_the_self_check() -> void:
	var runner: SpyRunner = _spy_runner()
	var hud: PerfHud = _finished_hud(runner)
	hud.self_check_step = func() -> String:
		_calls.append("self_check")
		return PerfHud.SELF_CHECK_MATCH
	hud.run_preflight(false, true)  # The scene entry's preflight.
	assert_float(hud.summary()["ref_peak_us"]).is_equal(25.0)
	_calls.clear()
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return SECOND_BURST
	hud.run_again()
	assert_array(_calls).is_equal(["burst"])  # No self_check: it does not repeat.
	var s: Dictionary = hud.summary()
	assert_float(s["ref_peak_us"]).is_equal(40.0)  # Rank 1 of 4, not the first burst's 25.
	assert_float(s["ref_peak_p95_us"]).is_equal(70.0)
	assert_str(s["self_check"]).is_equal(PerfHud.SELF_CHECK_MATCH)  # The results stay.
	assert_float(hud.summary()["ref_peak_us"]).is_equal(40.0)
	Rig.run(hud)  # The next run normalises against the new peak: 40 us, not 25.
	assert_float(hud.summary()["speed_main_pct"]).is_equal(100.0 * 40.0 / 25.0)


func test_run_again_without_a_runner_only_restarts() -> void:
	var hud: PerfHud = _finished_hud()
	hud.run_again()
	assert_int(hud.summary()["runs"]).is_equal(2)
	assert_bool(hud.visible).is_false()
	assert_bool(hud.summary()["finished"]).is_false()


## A hud whose run is over (the card is up), on `runner` when there is one, with its clipboard sink,
## the app paused during the run when `paused`.
func _finished_hud(runner: MatchRunner = null, paused: bool = false) -> PerfHud:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.runner = runner
	hud.clipboard_sink = _sink
	Rig.pass_frames(hud)
	if paused:
		hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	Rig.ticks(hud, hud.run_ticks)
	return hud


func _sink(text: String) -> void:
	_sent.append(text)


## Logs the burst, the self-check and restart() (which reads the panel rate) into `_calls`, the list
## the runner spy logs wait_idle() and start() into.
func _watch(hud: PerfHud, runner: SpyRunner) -> void:
	runner.calls = _calls
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return Rig.BURST
	hud.self_check_step = func() -> String:
		_calls.append("self_check")
		return PerfHud.SELF_CHECK_NOT_RUN
	hud.refresh_source = func() -> float:
		_calls.append("restart")
		return 60.0


## A SYNC runner on the seed-42 perf arena, started, freed with the case.
func _spy_runner() -> SpyRunner:
	var runner: SpyRunner = auto_free(SpyRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.tick_mode = MatchRunner.TickMode.SYNC
	runner.start()
	runner.calls.clear()
	return runner
