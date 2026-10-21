extends GdUnitTestSuite
## PerfHud part 2 (plan P50a2, ADR 0013 section 15), the four keys that split checkpoint ticks (a
## published tick with `tick % Replay.CHECKPOINT_PERIOD == 0`, the ticks MatchLoop hashes) from the
## others: `phases_p95_noncp_ms` (each phase's p95 over the others, in id order),
## `job_p95_noncp_ms`, `job_minus_step_p95_cp_ms` and `job_minus_step_p95_noncp_ms` (the p95 of
## `job_usec - step_usec` on each kind). They are printed without PASS or FAIL and never change
## `gate_pass`: the lead reads them on a release perf-arena card. The names match P49a's
## `WATCH sim job_minus_step` line, which splits on the same period the way
## tests/perf/support/perf_report.gd does.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
## The ticks of an ordinary job, in us: 10 ms of job, 8 ms of Sim.step, 100 us per phase.
const JOB_USEC: int = 10_000
const STEP_USEC: int = 8_000
const PHASE_USEC: int = 100


func after_test() -> void:
	CommandQueue.clear()


func test_the_non_checkpoint_p95s_skip_the_slow_checkpoint_ticks() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	# Every 15th tick is slow: a 40 ms job on a 7 ms step, and 30 ms in the COMMANDS phase (a hash).
	for tick: int in range(1, 901):
		var slow: bool = tick % Replay.CHECKPOINT_PERIOD == 0
		var phases: Dictionary = {SimProbe.Phase.COMMANDS: 30_000} if slow else {}
		hud.record_snapshot(
			_snapshot(tick, 40_000 if slow else JOB_USEC, 7_000 if slow else STEP_USEC, phases)
		)
	var s: Dictionary = hud.summary()
	assert_float(s["job_p95_noncp_ms"]).is_equal(10.0)
	assert_float(s["job_minus_step_p95_cp_ms"]).is_equal(33.0)
	assert_float(s["job_minus_step_p95_noncp_ms"]).is_equal(2.0)
	var phases_p95: Array = s["phases_p95_noncp_ms"]
	assert_int(phases_p95.size()).is_equal(SimProbe.Phase.COUNT)
	for phase: int in SimProbe.Phase.COUNT:
		assert_float(phases_p95[phase]).override_failure_message(str(phase)).is_equal_approx(
			0.1, 0.00001
		)
	# Why the keys exist: 60 of 900 ticks are checkpoints (6.7 %, above the 5 % a p95 ignores), so
	# the p95 of every tick lands on a hash tick, and the phase mean carries it too.
	assert_float(s["job_p95_ms"]).is_equal(40.0)
	assert_float(s["phases_ms"][SimProbe.Phase.COMMANDS]).is_equal_approx(0.1 + 29.9 / 15.0, 0.001)


func test_the_split_follows_the_tick_number_of_the_snapshot_not_the_sample_count() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	# Ticks 14 to 16: only tick 15 is a checkpoint, however many samples come before it.
	hud.record_snapshot(_snapshot(14, 12_000, 8_000, {}))
	hud.record_snapshot(_snapshot(15, 50_000, 8_000, {}))
	hud.record_snapshot(_snapshot(16, 13_000, 8_000, {}))
	var s: Dictionary = hud.summary()
	assert_float(s["job_p95_noncp_ms"]).is_equal(13.0)  # Rank 2 of 2: 12 and 13.
	assert_float(s["job_minus_step_p95_cp_ms"]).is_equal(42.0)
	assert_float(s["job_minus_step_p95_noncp_ms"]).is_equal(5.0)
	assert_float(s["job_p95_ms"]).is_equal(50.0)


func test_a_run_without_checkpoint_ticks_or_samples_reads_zero_and_restart_clears() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var s: Dictionary = hud.summary()
	assert_float(s["job_p95_noncp_ms"]).is_equal(0.0)
	assert_float(s["job_minus_step_p95_cp_ms"]).is_equal(0.0)
	assert_float(s["job_minus_step_p95_noncp_ms"]).is_equal(0.0)
	assert_array(s["phases_p95_noncp_ms"]).has_size(SimProbe.Phase.COUNT)
	hud.record_snapshot(_snapshot(1, JOB_USEC, STEP_USEC, {}))  # Not a checkpoint tick.
	assert_float(hud.summary()["job_minus_step_p95_cp_ms"]).is_equal(0.0)
	assert_float(hud.summary()["job_minus_step_p95_noncp_ms"]).is_equal(2.0)
	hud.restart()
	s = hud.summary()
	assert_float(s["job_p95_noncp_ms"]).is_equal(0.0)
	assert_float(s["job_minus_step_p95_noncp_ms"]).is_equal(0.0)
	for ms: float in s["phases_p95_noncp_ms"]:
		assert_float(ms).is_equal(0.0)


func test_a_snapshot_without_a_phase_split_adds_no_phase_sample() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var snap: MatchSnapshot = Rig.snapshot(1)  # No probe installed: phase_usec is empty.
	hud.record_snapshot(snap)
	var s: Dictionary = hud.summary()
	for ms: float in s["phases_p95_noncp_ms"]:
		assert_float(ms).is_equal(0.0)
	assert_float(s["job_p95_noncp_ms"]).is_equal(10.0)  # The job samples are there all the same.


func test_the_four_keys_are_printed_without_a_verdict_and_never_change_the_gate() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	# Far past ADR 0013 section 15's triggers, yet inside every gate limit: the checkpoint ticks
	# take 12.5 ms of job on a 1 ms step (job minus step 11.5 ms, above 3.3 ms), and COMMANDS takes
	# 9 ms of an ordinary 10 ms job (90 %, above 25 %).
	for tick: int in range(1, 901):
		var cp: bool = tick % Replay.CHECKPOINT_PERIOD == 0
		var phases: Dictionary = {} if cp else {SimProbe.Phase.COMMANDS: 9_000}
		hud.record_snapshot(
			_snapshot(tick, 12_500 if cp else JOB_USEC, 1_000 if cp else 9_500, phases)
		)
	var s: Dictionary = hud.summary()
	assert_float(s["job_minus_step_p95_cp_ms"]).is_equal(11.5)
	assert_float(s["phases_p95_noncp_ms"][SimProbe.Phase.COMMANDS]).is_equal(9.0)
	assert_array(Rig.failed(s)).is_empty()
	assert_bool(s["gate_pass"]).is_true()
	for line: String in s["verdicts"]:
		assert_bool(line.contains("noncp") or line.contains("job_minus_step")).is_false()
	var found: Array[String] = []
	for line: String in hud.card_lines():
		if line.contains("without checkpoint ticks"):
			found.append(line)
			assert_bool(line.contains(PerfHud.PASS) or line.contains(PerfHud.FAIL)).is_false()
	assert_array(found).has_size(2)  # The job line and the phase line.
	var job_line: String = "p95 ms without checkpoint ticks: job 10.00 | job minus step: "
	job_line += "checkpoint 11.50, other 0.50"
	assert_array(found).contains([job_line])
	(
		assert_array(found.filter(func(l: String) -> bool: return l.contains("commands 9.00")))
		. has_size(1)
	)


## Published tick `tick`: `job_usec` of job, `step_usec` of Sim.step, and every phase PHASE_USEC
## except those of `phases` (a phase id -> us).
func _snapshot(tick: int, job_usec: int, step_usec: int, phases: Dictionary) -> MatchSnapshot:
	var snap: MatchSnapshot = Rig.snapshot(tick, job_usec, step_usec)
	snap.phase_usec = PackedInt64Array()
	snap.phase_usec.resize(SimProbe.Phase.COUNT)
	snap.phase_usec.fill(PHASE_USEC)
	for phase: int in phases:
		snap.phase_usec[phase] = phases[phase]
	return snap
