extends GdUnitTestSuite
## PerfHud part 2 (plan P50a2, ADR 0013 section 3), the preflight's self-check seam and the `impl`
## verdict. `preflight(runner)` reads the implementation the runner asked for (`sim_impl`), resolves
## it with `MatchRunner.resolve_impl` against the library (`kernels_source`) and the OS name, then
## calls the self-check seam and the burst seam, in that order; a seam that is not set is skipped;
## `with_self_check` false ("Run again") calls the burst seam alone and keeps the self-check
## results; a refusal (a job in flight) calls neither and logs no error. On Android a resolved
## implementation other than NATIVE gives `impl: FAIL (gdscript)` and a self-check other than a
## match `impl: FAIL (self-check ...)`, each failing the gate alone; elsewhere the line is n/a. The
## default seam runs the real 60-tick lockstep of the seed-42 arena when the library is loaded.
## Nothing here logs an error (gdUnit4 fails a test that does): the OS name is injected, so no case
## reaches the Android `push_error` of the runner.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
## The phases a fake library reports: FLOW (1), SEPARATION (5) and FOG (10), and its build info.
const FAKE_PHASES: int = (1 << 1) | (1 << 5) | (1 << 10)
const FAKE_BUILD: String = "Android, template_release, arm64, O2, clang 17"

var _calls: Array[String] = []


## A library that reports `FAKE_PHASES` and `FAKE_BUILD`: the two methods the HUD reads.
class FakeKernels:
	extends RefCounted

	func phases() -> int:
		return FAKE_PHASES

	func build_info() -> String:
		return FAKE_BUILD


func after_test() -> void:
	_calls.clear()
	CommandQueue.clear()


func test_the_self_check_seam_runs_before_the_burst_seam() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	_record(hud)
	hud.run_preflight(false, true)
	assert_array(_calls).is_equal(["self_check", "burst"])
	assert_str(hud.summary()["self_check"]).is_equal("match")
	assert_float(hud.summary()["ref_peak_us"]).is_equal(30.0)


func test_a_seam_that_is_not_set_is_skipped_and_the_self_check_reads_not_run() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	_record(hud)
	hud.self_check_step = Callable()
	hud.run_preflight(false, true)
	assert_array(_calls).is_equal(["burst"])
	assert_str(hud.summary()["self_check"]).is_equal("not run")
	hud.burst_step = Callable()
	_calls.clear()
	hud.run_preflight(false, true)
	assert_array(_calls).is_empty()
	assert_float(hud.summary()["ref_peak_us"]).is_equal(0.0)


func test_without_the_self_check_only_the_burst_seam_runs_and_the_results_stay() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	_record(hud)
	hud.run_preflight(false, true)
	_calls.clear()
	hud.self_check_step = func() -> String:
		_calls.append("self_check")
		return "mismatch"
	hud.run_preflight(false, false)  # "Run again".
	assert_array(_calls).is_equal(["burst"])
	assert_str(hud.summary()["self_check"]).is_equal("match")  # Replaced by the next full preflight.
	hud.run_preflight(false, true)
	assert_str(hud.summary()["self_check"]).is_equal("mismatch")


func test_a_refused_preflight_calls_no_seam_and_restart_keeps_the_self_check() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	_record(hud)
	hud.run_preflight(false, true)
	_calls.clear()
	hud.run_preflight(true, true)  # A job in flight.
	assert_array(_calls).is_empty()
	assert_array(hud.summary()["invalid_reasons"]).is_equal(["preflight_job_in_flight"])
	assert_str(hud.summary()["self_check"]).is_equal("match")  # Kept: nothing replaced it.
	hud.run_preflight(false, true)
	hud.restart()  # The results of a preflight survive a restart.
	assert_str(hud.summary()["self_check"]).is_equal("match")
	assert_float(hud.summary()["ref_peak_us"]).is_equal(30.0)


func test_preflight_reads_the_runners_implementation_and_the_library() -> void:
	var flow: Array = ["flow", "separation", "fog"]
	var cases: Array = [  # asked, library, OS, the resolved name, the phases, the build
		[MatchRunner.SimImpl.GDSCRIPT, true, "Linux", "GDSCRIPT", [], ""],
		[MatchRunner.SimImpl.NATIVE, true, "Linux", "NATIVE", flow, FAKE_BUILD],
		[MatchRunner.SimImpl.AUTO, true, "Android", "NATIVE", flow, FAKE_BUILD],
		[MatchRunner.SimImpl.AUTO, false, "Web", "GDSCRIPT", [], ""],  # The web packs no library.
		[MatchRunner.SimImpl.AUTO, false, "Linux", "GDSCRIPT", [], ""],
	]
	for c: Array in cases:
		var hud: PerfHud = _preflighted(c[0], c[1], c[2], "match")
		var s: Dictionary = hud.summary()
		var label: String = str(c)
		assert_str(s["sim_impl"]).override_failure_message(label).is_equal(c[3])
		assert_array(s["native_phases"]).override_failure_message(label).is_equal(c[4])
		assert_str(s["native_build"]).override_failure_message(label).is_equal(c[5])
		assert_str(s["os"]).is_equal(c[2])


func test_on_android_a_gdscript_run_fails_the_impl_verdict_alone() -> void:
	var hud: PerfHud = _preflighted(MatchRunner.SimImpl.AUTO, false, "Android", "not run")
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	assert_array(s["verdicts"]).contains(["impl: FAIL (gdscript)"])
	assert_array(Rig.failed(s)).is_equal(["impl"])
	assert_bool(s["gate_pass"]).is_false()
	assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")


func test_on_android_a_native_run_needs_a_matching_self_check() -> void:
	var cases: Array = [  # the self-check, the line, whether the gate passes
		["match", "impl: PASS (self-check match)", true],
		["mismatch", "impl: FAIL (self-check mismatch)", false],
		["not run", "impl: FAIL (self-check not run)", false],
	]
	for c: Array in cases:
		var hud: PerfHud = _preflighted(MatchRunner.SimImpl.NATIVE, true, "Android", c[0])
		Rig.run(hud)
		var s: Dictionary = hud.summary()
		assert_array(s["verdicts"]).override_failure_message(c[0]).contains([c[1]])
		assert_array(Rig.failed(s)).is_equal([] if c[2] else ["impl"])
		assert_bool(s["gate_pass"]).override_failure_message(c[0]).is_equal(c[2])


func test_off_android_the_impl_line_is_not_applicable_whatever_runs() -> void:
	for os_name: String in ["Linux", "Web", "Windows", "macOS", "iOS"]:
		for asked: int in [MatchRunner.SimImpl.GDSCRIPT, MatchRunner.SimImpl.NATIVE]:
			var hud: PerfHud = _preflighted(
				asked, asked == MatchRunner.SimImpl.NATIVE, os_name, "mismatch"
			)
			Rig.run(hud)
			var s: Dictionary = hud.summary()
			assert_array(s["verdicts"]).contains(["impl: n/a (only Android requires the library)"])
			assert_array(Rig.failed(s)).is_empty()
			assert_bool(s["gate_pass"]).override_failure_message(os_name).is_true()


func test_the_card_prints_the_implementation_phases_and_the_self_check_line() -> void:
	var native: String = "sim impl: native (%s, phases flow, separation, fog)" % FAKE_BUILD
	var cases: Array = [  # asked, library, OS, the self-check, the line
		[
			MatchRunner.SimImpl.NATIVE,
			true,
			"Android",
			"match",
			native + " | C++ matches GDScript: yes (60 ticks)",
		],
		[
			MatchRunner.SimImpl.NATIVE,
			true,
			"Android",
			"mismatch",
			native + " | C++ matches GDScript: NO (60 ticks)",
		],
		[
			MatchRunner.SimImpl.GDSCRIPT,
			false,
			"Linux",
			"not run",
			"sim impl: gdscript | C++ matches GDScript: not run",
		],
	]
	for c: Array in cases:
		var hud: PerfHud = _preflighted(c[0], c[1], c[2], c[3])
		Rig.run(hud)
		assert_array(Array(hud.card_lines())).contains([c[4]])


func test_the_default_seam_runs_the_real_lockstep_on_the_native_library() -> void:
	var library: Object = NativeKernels.create()
	assert_object(library).is_not_null()  # run-tests.sh refuses a missing library, so it is built.
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.sim_impl = MatchRunner.SimImpl.NATIVE
	var hud: PerfHud = auto_free(Rig.hud())
	hud.kernels_source = NativeKernels.create
	hud.preflight(runner)  # The seed-42 arena, 60 ticks, every phase the library reports.
	var s: Dictionary = hud.summary()
	assert_str(s["sim_impl"]).is_equal("NATIVE")
	assert_str(s["self_check"]).is_equal("match")
	assert_int(s["native_phases"].size()).is_greater(0)
	assert_str(s["native_build"]).is_equal(str(library.build_info()))  # What the library reports.
	assert_str(s["native_build"]).is_not_empty()
	for phase: String in s["native_phases"]:
		assert_array(SimProbe.PHASE_NAMES).contains([phase])
	runner.sim_impl = MatchRunner.SimImpl.GDSCRIPT  # The twins run: nothing to compare.
	hud.preflight(runner, true)
	assert_str(hud.summary()["sim_impl"]).is_equal("GDSCRIPT")
	assert_str(hud.summary()["self_check"]).is_equal("not run")
	assert_array(hud.summary()["native_phases"]).is_empty()
	assert_str(hud.summary()["native_build"]).is_empty()
	assert_float(hud.summary()["ref_peak_us"]).is_equal(25.0)  # The rig's burst, after both.


## A HUD on `os_name`, preflighted with a runner that asks for `asked`, a library or none, and a
## self-check seam that answers `check`. The burst seam is the rig's.
func _preflighted(asked: int, library: bool, os_name: String, check: String) -> PerfHud:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.sim_impl = asked
	var hud: PerfHud = auto_free(Rig.hud())
	hud.os_name = os_name
	hud.kernels_source = func() -> Object: return FakeKernels.new() if library else null
	hud.self_check_step = func() -> String: return check
	hud.preflight(runner)
	return hud


## Recording seams: a self-check that matches and a burst of 30 us.
func _record(hud: PerfHud) -> void:
	hud.self_check_step = func() -> String:
		_calls.append("self_check")
		return "match"
	hud.burst_step = func() -> PackedFloat64Array:
		_calls.append("burst")
		return PackedFloat64Array([30.0, 30.0])
