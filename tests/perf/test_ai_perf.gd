extends GdUnitTestSuite
## The AI's time and bounds (plan row P189, ADR 0030 section 4, ADR 0031 section 8). Two Normal
## `OpponentAi` play `data/scenarios/perf_ai.tres` (the base arena's layout on the frozen sim defs,
## the frozen AI defs, below) for 900 ticks of seed 42, three times, through `AiDriver.think_all`.
##
## What is judged is deterministic and read from the controllers, never from the clock: every think
## stays inside the counted bounds of ADR 0030 section 4 (the passes, the Commands cut, the
## placement tries, the candidate tests, the goal keys, the sectors and every id list of the
## memory), the runs end on the same state hash at every checkpoint and drop no Command.
##
## The workload plays the frozen AI defs of `data/dev/arena/ai/` (plan row P189b): copies of the
## eleven shipped AI defs but for Normal's early scout (tick 30) and first wave (tick 300, no
## jitter). The scouts leave at ticks 40 and 36, player 1 sees an enemy combat unit at tick 50 and
## player 2 at tick 61, both launch a wave by tick 305, and player 1 sees an enemy building only at
## tick 740 (player 2 none), its strike tests start at tick 115.
## What it exercises, by `WATCH ai peaks`: the passes (3), the placement tries, the STAGING, ARMY
## and SCOUT keys, the own id lists, `seen_unit_id` and `seen_site_id`, the army's target tests, the
## strike tests (player 1's Deep Bore only: `perf_ai.tres` spawns each strike building charged,
## where one built in the match needs 600 build and 4 500 charge ticks; player 2's Dusk Array is
## never tested, as it fires on a seen producer and player 2 sees no enemy building), the Commands
## and every slot. What stays 0: `hit_tests` (no calm home unit is hit), `withdrawn_id` (Normal's
## `unit_retreat_hp_percent` is 0), `seen_mobile_id` (no enemy tanker seen) and `commands_cut`
## (capped at 0); their bounds hold on silence, and the manager suites and
## P188's matches pin them on crafted Worlds. Only the counters this workload moves are asserted
## live (`LIVE`, and `CONTACT` for the ones that need the enemy seen).
##
## What is only printed (report only; the `[ai]` budget value is row P189c's, after 11 CI runs on
## main):
## - `WATCH ai think`: the time of a think (the call of `think_all` that made it, the PlayerView
##   included, as the snapshot's `think_usec`), the p95 and the max, each the smallest of the runs
##   (as `PerfReport.best_of`), with the phone estimate at the gate's `ci_ratio_p95`. `impl=` is the
##   sim's implementation; the AI is GDScript in both. `thinks=` is added to ADR 0030 section 4's
##   keys. The watch value of the card is 1.0 ms on the phone.
## - `WATCH ai flow seed=<s> ticks=<t> full_ticks=<n> hash=<hex>`: input for goal_keys_max or P194.
## - `WATCH ai peaks name=count ...`: the largest value of every judged counter (counts only).

const AiRun: GDScript = preload("res://tests/perf/support/ai_perf_run.gd")
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const RUNS: int = 3
## The counters this workload moves (see the header); asserted greater than 0 in every run.
const LIVE: Array[String] = [
	"work", "placement_tries", "keys_staging", "unit_id", "own_mobile_id", "hp_id", "commands"
]
## The counters that move only once the enemy is seen: the early scout and first wave of the frozen
## defs make contact inside the 900 ticks, so each is above 0 (P189 had them at 0). `seen_site_id`
## first moves at tick 740 (a 160-tick margin, player 1 only) and `strike_tests` for player 1 only.
const CONTACT: Array[String] = [
	"seen_unit_id", "seen_site_id", "army_tests", "strike_tests", "keys_army", "keys_scout"
]

var _runs: Array[AiRun] = []


func before() -> void:
	for _run: int in RUNS:
		var run: AiRun = AiRun.new()
		run.play()
		_runs.append(run)
	var gate: PerfGateDef = load(GATE_PATH) as PerfGateDef
	var first: AiRun = _runs[0]
	var p95_us: float = _smallest(AiRun.p95_of)
	var max_us: float = _smallest(AiRun.max_of)
	print(AiRun.think_line(p95_us, max_us, first.impl, first.thinks, gate.ci_ratio_p95))
	print(AiRun.flow_line(first.flow_full_ticks, World.hash_hex(first.final_hash)))
	print(AiRun.peaks_line(first.peaks))
	_print_prof(first)


## The runs play the whole 900 ticks (no match end), every Command passes the sim's validation, and
## all end on the same state hash at every checkpoint: the AI is a pure function of its views and
## its stream, so the counted bounds below are the same in all of them.
func test_the_runs_play_900_ticks_drop_nothing_and_agree_at_every_checkpoint() -> void:
	var first: AiRun = _runs[0]
	@warning_ignore("integer_division")
	var checkpoints: int = AiRun.TICKS / Replay.CHECKPOINT_PERIOD
	assert_int(first.checkpoint_hashes.size()).is_equal(checkpoints)
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		var tag: String = "run %d" % index
		assert_int(run.match_end_tick).append_failure_message(tag).is_equal(0)
		assert_int(run.dropped_commands).append_failure_message(tag).is_equal(0)
		assert_array(run.checkpoint_ticks).append_failure_message(tag).is_equal(
			first.checkpoint_ticks
		)
		assert_array(run.checkpoint_hashes).append_failure_message(tag).is_equal(
			first.checkpoint_hashes
		)
		assert_int(run.final_hash).append_failure_message(tag).is_equal(first.final_hash)
		assert_int(run.flow_full_ticks).append_failure_message(tag).is_equal(first.flow_full_ticks)
		assert_int(run.thinks).append_failure_message(tag).is_equal(first.thinks)
		assert_array(_peak_values(run)).append_failure_message(tag).is_equal(_peak_values(first))


## Every think of both AIs, 900 ticks long, stays inside the bounds of ADR 0030 sections 3 and 4;
## the run itself is the planned one: two AIs, at most one think a tick, and as many thinks as the
## driver's rule `(tick + think_offset) % think_period == 0` owes.
func test_every_think_stays_inside_the_counted_bounds_of_the_adr() -> void:
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		var tag: String = "run %d" % index
		assert_array(run.violations).append_failure_message(tag).is_empty()
		assert_int(run.controllers.size()).append_failure_message(tag).is_equal(2)
		assert_int(run.most_in_a_tick).append_failure_message(tag).is_equal(1)
		assert_int(run.thinks).append_failure_message(tag).is_equal(run.thinks_owed)
		assert_int(run.thinks).append_failure_message(tag).is_equal(run.think_usec.size())


## The counters that this workload moves did move, so their bounds were judged on something: the
## passes reached the budget of 3, and each AI thought in every slot. The counters that stay 0 here
## are named in the header and printed by `WATCH ai peaks`.
func test_the_counters_this_workload_moves_are_live() -> void:
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		for name: String in LIVE + CONTACT:
			(
				assert_int(run.peaks.get(name, 0))
				. override_failure_message("run %d: %s never moved" % [index, name])
				. is_greater(0)
			)
		assert_int(run.peaks["work"]).override_failure_message("run %d" % index).is_equal(
			AiRun.PASSES_MAX
		)
		for controller: AiController in run.controllers:
			var ai: OpponentAi = controller as OpponentAi
			for slot: int in OpponentAi.SLOTS:
				(
					assert_int(ai.slot_thinks[slot])
					. override_failure_message(
						"run %d player %d slot %d" % [index, ai.player_id, slot]
					)
					. is_greater(0)
				)


## The early scout and first wave make contact: each AI's memory held a seen enemy unit, each scout
## went, and a wave was launched, in every run.
func test_the_frozen_defs_make_contact_within_the_900_ticks() -> void:
	for index: int in _runs.size():
		var run: AiRun = _runs[index]
		var waves: int = 0
		for at: int in run.controllers.size():
			var ai: OpponentAi = run.controllers[at] as OpponentAi
			var tag: String = "run %d player %d" % [index, ai.player_id]
			assert_int(ai.memory.scout_trip_tick).append_failure_message(tag).is_not_equal(
				AiMemory.NONE
			)
			waves += ai.army.waves
			assert_int(run.seen_peaks[at]).append_failure_message(tag).is_greater(0)
		assert_int(waves).append_failure_message("run %d" % index).is_greater(0)


## The three report-only lines are `WATCH ai <name> key=value ...` with their keys in order, none
## starts with `PERF `, the lines that P51 copies. Made-up samples: the p95 is the nearest rank.
func test_the_watch_lines_have_the_heads_the_keys_in_order_and_the_phone_estimate() -> void:
	assert_str(AiRun.THINK_HEAD).is_equal("WATCH ai think")
	assert_str(AiRun.FLOW_HEAD).is_equal("WATCH ai flow")
	assert_str(AiRun.PEAKS_HEAD).is_equal("WATCH ai peaks")
	var samples: PackedFloat64Array = PackedFloat64Array()
	for index: int in 20:
		samples.append(float((index * 7) % 20 + 1) * 100.0)
	assert_float(AiRun.p95_of(samples)).is_equal(1900.0)
	assert_float(AiRun.max_of(samples)).is_equal(2000.0)
	assert_float(AiRun.max_of(PackedFloat64Array())).is_equal(0.0)
	var think: String = AiRun.think_line(1900.0, 2000.0, "gdscript", 20, 5.9)
	assert_str(think).is_equal(
		(
			"WATCH ai think impl=gdscript slots=3 thinks=20 p95_us=1900.000 max_us=2000.000 "
			+ "est_phone_p95_ms=11.210"
		)
	)
	assert_str(AiRun.think_line(0.0, 0.0, "native", 0, 5.9)).is_equal(
		(
			"WATCH ai think impl=native slots=3 thinks=0 p95_us=0.000 max_us=0.000 "
			+ "est_phone_p95_ms=0.000"
		)
	)
	assert_str(AiRun.flow_line(191, "00ab")).is_equal(
		"WATCH ai flow seed=42 ticks=900 full_ticks=191 hash=00ab"
	)
	var counts: Dictionary[String, int] = {"work": 3, "keys_scout": 0}
	assert_str(AiRun.peaks_line(counts)).is_equal("WATCH ai peaks work=3 keys_scout=0")
	for line: String in [think, AiRun.flow_line(0, ""), AiRun.peaks_line(counts)]:
		assert_bool(line.begins_with("PERF ")).is_false()
		assert_bool(line.begins_with("WATCH ai ")).is_true()


## The p95 and the max, each the smallest over the runs (like `PerfReport.best_of`).
func _smallest(statistic: Callable) -> float:
	var smallest: float = INF
	for run: AiRun in _runs:
		smallest = minf(smallest, statistic.call(run.think_usec))
	return smallest


## The peaks of `run` as a list in the order they were first seen, to compare two runs.
func _peak_values(run: AiRun) -> Array[int]:
	var values: Array[int] = []
	for name: String in run.peaks:
		values.append(run.peaks[name])
	return values


func _print_prof(run: AiRun) -> void:
	var names: Array[String] = ["economy", "production", "refresh", "army", "intel", "striker"]
	var parts: String = "WATCH ai prof view p95=%.0f mean=%.0f" % [AiRun.p95_of(AiDriver.view_usec), _mean(AiDriver.view_usec)]
	print(parts)
	var ai: OpponentAi = run.controllers[0] as OpponentAi
	for i: int in names.size():
		var all: PackedFloat64Array = PackedFloat64Array()
		for c: AiController in run.controllers:
			all.append_array((c as OpponentAi).prof[i])
		print("WATCH ai prof %s n=%d p95=%.0f mean=%.0f max=%.0f" % [names[i], all.size(), AiRun.p95_of(all), _mean(all), AiRun.max_of(all)])
	var _unused: OpponentAi = ai


func _mean(a: PackedFloat64Array) -> float:
	var t: float = 0.0
	for v: float in a:
		t += v
	return t / maxf(1.0, float(a.size()))
