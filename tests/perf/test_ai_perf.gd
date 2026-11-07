extends GdUnitTestSuite
## The AI's time and bounds (plan row P189, ADR 0030 section 4, ADR 0031 section 8). Two Normal
## `OpponentAi` play `data/scenarios/perf_ai.tres` (the base arena's layout on the frozen sim defs,
## the shipped AI defs) for 900 ticks of seed 42, twice, through `AiDriver.think_all`.
##
## What is judged is deterministic and read from the controllers, never from the clock: every think
## stays inside the counted bounds of ADR 0030 section 4 (the passes, the Commands, the placement
## tries, the candidate tests, the goal keys, the sectors, the squads and the id lists), the two
## runs end on the same state hash at every checkpoint and drop no Command, and the counters that
## judge a bound are live (a bound that nothing moves is not a bound). `flow_full_ticks` is printed
## for the lead's choice between `goal_keys_max` 3 and plan row P194; it is not asserted.
##
## What is only printed: `WATCH ai think` (report only, no ratchet: that is P189b's), the time of a
## think (the call of `think_all` that made it, the PlayerView included, as the snapshot's
## `think_usec`) at the p95 and the max over the better run, with the phone estimate at the gate's
## `ci_ratio_p95`. The watch value of the card is 1.0 ms on the phone (ADR 0030 section 4).

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const AiRun: GDScript = preload("res://tests/perf/support/ai_perf_run.gd")
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const WATCH_HEAD: String = "WATCH ai think"
const RUNS: int = 2

var _runs: Array = []


func before() -> void:
	for _run: int in RUNS:
		_runs.append(AiRun.play())
	var gate: PerfGateDef = load(GATE_PATH) as PerfGateDef
	var best: Variant = _best()
	print(watch_line(best.think_usec, best.impl, best.thinks, gate.ci_ratio_p95))
	print("WATCH ai flow_full_ticks=%d hash=%s" % [best.flow_full_ticks, _hex(best.final_hash)])


## Both runs play the whole 900 ticks (no match end), every Command passes the sim's validation, and
## both end on the same state hash at every checkpoint: the AI is a pure function of its views and
## its stream, so the counted bounds below are the same in both.
func test_both_runs_play_900_ticks_drop_nothing_and_agree_at_every_checkpoint() -> void:
	var first: Variant = _runs[0]
	assert_int(first.checkpoint_hashes.size()).is_equal(AiRun.TICKS / Replay.CHECKPOINT_PERIOD)
	for run: Variant in _runs:
		assert_int(run.match_end_tick).is_equal(0)
		assert_int(run.dropped_commands).is_equal(0)
		assert_array(run.checkpoint_ticks).is_equal(first.checkpoint_ticks)
		assert_array(run.checkpoint_hashes).is_equal(first.checkpoint_hashes)
		assert_int(run.final_hash).is_equal(first.final_hash)
		assert_int(run.flow_full_ticks).is_equal(first.flow_full_ticks)
		assert_int(run.thinks).is_equal(first.thinks)


## Every think of both AIs, 900 ticks long, stays inside the bounds of ADR 0030 section 4; the run
## itself is the planned one (two AIs, one think a tick at most, each AI thinks every fifth tick).
func test_every_think_stays_inside_the_counted_bounds_of_the_adr() -> void:
	for run: Variant in _runs:
		assert_array(run.violations).is_empty()
		assert_int(run.controllers.size()).is_equal(2)
		assert_int(run.most_in_a_tick).is_equal(1)
		assert_int(run.thinks).is_equal(run.think_usec.size())
		var expected: int = 0
		for ai: AiController in run.controllers:
			expected += AiRun.TICKS / ai.think_period
		assert_int(run.thinks).is_equal(expected)


## The counters that the bounds read moved: an AI that never sent a Command, never reached the pass
## budget or never sent its slots' work would pass the bounds on silence. Each AI thought in every
## slot, sent Commands, and its `work_max` reached the view's pass and the two of a slot (3).
func test_the_counters_the_bounds_judge_are_live() -> void:
	for run: Variant in _runs:
		for controller: AiController in run.controllers:
			var ai: OpponentAi = controller as OpponentAi
			for slot: int in OpponentAi.SLOTS:
				assert_int(ai.slot_thinks[slot]).is_greater(0)
			assert_int(ai.commands).is_greater(0)
			assert_int(ai.work_max).is_equal(3)


## The WATCH line is the head, `impl=`, the slots, the think count, the p95 and the max in
## microseconds and the phone estimate (the p95 in ms times the ratio), in that order; none starts
## with `PERF `, the lines that P51 copies. Made-up samples: the p95 is the nearest rank.
func test_the_watch_line_has_the_keys_in_order_and_the_phone_estimate() -> void:
	var samples: PackedFloat64Array = PackedFloat64Array()
	for index: int in 20:
		samples.append(float((index * 7) % 20 + 1) * 100.0)
	var line: String = watch_line(samples, "gdscript", 20, 5.9)
	assert_str(line).is_equal(
		(
			"WATCH ai think impl=gdscript slots=3 thinks=20 p95_us=1900.000 max_us=2000.000 "
			+ "est_phone_p95_ms=11.210"
		)
	)
	assert_bool(line.begins_with("PERF ")).is_false()
	var keys: Array[String] = []
	for field: String in line.split(" "):
		keys.append(field.get_slice("=", 0))
	assert_array(keys).is_equal(
		["WATCH", "ai", "think", "impl", "slots", "thinks", "p95_us", "max_us", "est_phone_p95_ms"]
	)
	assert_str(watch_line(PackedFloat64Array(), "native", 0, 5.9)).contains(
		"impl=native slots=3 thinks=0 p95_us=0.000 max_us=0.000 est_phone_p95_ms=0.000"
	)


## The line of `WATCH ai think` for the think times `usec` (floats, microseconds).
static func watch_line(usec: PackedFloat64Array, impl: String, thinks: int, ratio: float) -> String:
	var p95_us: float = PerfReport.p95(usec)
	var max_us: float = 0.0
	for sample: float in usec:
		max_us = maxf(max_us, sample)
	var values: Dictionary = {
		"impl": impl,
		"slots": OpponentAi.SLOTS,
		"thinks": thinks,
		"p95_us": p95_us,
		"max_us": max_us,
		"est_phone_p95_ms": p95_us / 1000.0 * ratio,
	}
	return PerfReport.sub_line(WATCH_HEAD, values, false)


## The run with the lower p95, the better of the two, as the perf lines take the best run.
func _best() -> Variant:
	var best: Variant = _runs[0]
	for run: Variant in _runs:
		if PerfReport.p95(run.think_usec) < PerfReport.p95(best.think_usec):
			best = run
	return best


func _hex(hash_value: int) -> String:
	return World.hash_hex(hash_value)
