extends GdUnitTestSuite
## PerfHud part 2 (plan P50a2, ADR 0011 section 5, ADR 0013 section 3), the golden comparison: the
## checkpoint hashes of a run (the snapshot's `last_hash` at every 150th published tick, as
## World.hash_hex text) against the golden ticks and values of the PerfGateDef, shown as the verdict
## `golden_hashes`: MATCH, or MISMATCH with the first differing tick, which fails the gate. A golden
## tick beyond `run_ticks` is not compared, a tick that an unfinished run has not reached is not
## compared yet, a finished run that lacks one has a mismatch there, and a gate with nothing to
## compare never passes. The last case runs the real seed-42 arena against data/dev/perf_gate.tres.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const GATE: String = "res://data/dev/perf_gate.tres"


func after_test() -> void:
	CommandQueue.clear()


func test_a_run_whose_checkpoints_equal_the_golden_values_matches() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	assert_bool(s["golden_match"]).is_true()
	assert_int(s["golden_checked"]).is_equal(6)  # Ticks 150 to 900.
	assert_int(s["golden_mismatch_tick"]).is_equal(-1)
	assert_array(s["verdicts"]).contains(["golden_hashes: PASS (MATCH, 6 checkpoints)"])
	assert_bool(s["gate_pass"]).is_true()


func test_the_first_differing_golden_tick_is_reported_and_fails_the_gate_alone() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	Rig.pin_golden(gate)
	gate.golden_hex[2] = "00000000000000ff"  # Tick 450.
	gate.golden_hex[4] = "00000000000000fe"  # Tick 750: not the first.
	var hud: PerfHud = auto_free(Rig.hud(gate))
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	var got: String = World.hash_hex(Rig.last_hash(450))
	var line: String = "golden_hashes: FAIL (MISMATCH at tick 450, got %s, golden %s)"
	assert_array(s["verdicts"]).contains([line % [got, "00000000000000ff"]])
	assert_bool(s["golden_match"]).is_false()
	assert_int(s["golden_mismatch_tick"]).is_equal(450)
	assert_int(s["golden_checked"]).is_equal(3)  # It stops at the first.
	assert_array(Rig.failed(s)).is_equal(["golden_hashes"])
	assert_bool(s["gate_pass"]).is_false()
	assert_str(hud.card_lines()[-1]).is_equal("GATE: FAIL")


func test_a_hash_that_the_run_gets_wrong_is_a_mismatch_at_its_tick() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	for tick: int in range(1, 901):
		var snap: MatchSnapshot = Rig.snapshot(tick)
		if tick == 300:
			snap.last_hash = 12345
		hud.record_snapshot(snap)
	var s: Dictionary = hud.summary()
	assert_int(s["golden_mismatch_tick"]).is_equal(300)
	assert_array(Rig.failed(s)).is_equal(["golden_hashes"])
	(
		assert_str(
			Array(s["verdicts"]).filter(func(l: String) -> bool: return l.begins_with("golden"))[0]
		)
		. contains("MISMATCH at tick 300, got " + World.hash_hex(12345))
	)


func test_golden_ticks_beyond_run_ticks_are_not_compared() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.run_ticks = 450
	Rig.pass_frames(hud)
	Rig.ticks(hud, 450)
	var s: Dictionary = hud.summary()
	assert_int(s["golden_checked"]).is_equal(3)  # 150, 300 and 450.
	assert_array(s["verdicts"]).contains(["golden_hashes: PASS (MATCH, 3 checkpoints)"])
	assert_bool(s["gate_pass"]).is_true()
	var short: PerfHud = auto_free(Rig.hud())
	short.run_ticks = 100  # No golden tick lies within it: nothing to compare.
	Rig.pass_frames(short)
	Rig.ticks(short, 100)
	assert_bool(short.summary()["golden_match"]).is_false()
	assert_array(short.summary()["verdicts"]).contains(
		["golden_hashes: FAIL (no golden checkpoint up to tick 100)"]
	)


func test_an_unfinished_run_compares_what_it_has_and_never_passes() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	Rig.ticks(hud, 320)  # Checkpoints 150 and 300.
	var s: Dictionary = hud.summary()
	assert_int(s["golden_checked"]).is_equal(2)
	assert_bool(s["golden_match"]).is_true()
	assert_bool(s["gate_pass"]).is_false()  # The run is not over.
	var wrong: PerfHud = auto_free(Rig.hud())
	wrong.record_snapshot(_snapshot_with_hash(150, 99))  # A mismatch shows before the run ends.
	assert_int(wrong.summary()["golden_mismatch_tick"]).is_equal(150)


func test_a_finished_run_that_lacks_a_golden_checkpoint_has_a_mismatch_there() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.pass_frames(hud)
	for tick: int in [150, 300, 450, 600, 900]:  # The snapshot of 750 never came.
		hud.record_snapshot(Rig.snapshot(tick))
	var s: Dictionary = hud.summary()
	assert_bool(s["finished"]).is_true()
	assert_int(s["golden_mismatch_tick"]).is_equal(750)
	var want: String = World.hash_hex(Rig.last_hash(750))
	assert_array(s["verdicts"]).contains(
		["golden_hashes: FAIL (MISMATCH at tick 750, got none, golden %s)" % want]
	)


func test_a_gate_without_golden_values_never_passes() -> void:
	var hud: PerfHud = auto_free(PerfHud.new())
	hud.gate = PerfGateDef.new()
	hud.refresh_source = func() -> float: return 60.0
	hud.restart()
	Rig.ticks(hud, 900)
	var s: Dictionary = hud.summary()
	assert_bool(s["golden_match"]).is_false()
	assert_int(s["golden_checked"]).is_equal(0)
	assert_array(s["verdicts"]).contains(
		["golden_hashes: FAIL (no golden checkpoint up to tick 900)"]
	)
	var uneven: PerfGateDef = PerfGateDef.new()  # A tick with no value does not count.
	uneven.golden_ticks = PackedInt32Array([150, 300])
	uneven.golden_hex = PackedStringArray([World.hash_hex(Rig.last_hash(150))])
	hud.gate = uneven
	assert_int(hud.summary()["golden_checked"]).is_equal(1)


func test_the_shipped_gate_holds_the_six_checkpoints_and_the_arena_matches_the_first() -> void:
	var gate: PerfGateDef = load(GATE)
	assert_array(Array(gate.golden_ticks)).is_equal([150, 300, 450, 600, 750, 900])
	assert_int(gate.golden_hex.size()).is_equal(6)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(Rig.ARENA)
	runner.match_seed = 42
	runner.start()
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.runner = runner
	hud.run_ticks = 150  # The first golden tick is the end of this short run.
	add_child(hud)
	hud.restart()
	runner.run_ticks(150)
	var s: Dictionary = hud.summary()
	assert_array(s["checkpoints"]).has_size(1)
	assert_int(s["golden_checked"]).is_equal(1)
	assert_str(s["checkpoints"][0]["hash_hex"]).is_equal(gate.golden_hex[0])
	assert_bool(s["golden_match"]).is_true()


func _snapshot_with_hash(tick: int, last_hash: int) -> MatchSnapshot:
	var snap: MatchSnapshot = Rig.snapshot(tick)
	snap.last_hash = last_hash
	return snap
