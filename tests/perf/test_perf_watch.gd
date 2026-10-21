extends GdUnitTestSuite
## The pure parts of the STEP sub-line and the two WATCH lines (plan P49a, ADR 0013 section 15),
## on made-up logs and samples: which tick ordered the most units, the job time outside Sim.step on
## checkpoint ticks and on the others, the 95th percentile, and the text of a sub-line.
## test_sim_perf.gd prints the lines from the real arena.

const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")


## The tick with the most ordered units wins, summed over all the commands of the tick and not
## counted per command; the lowest tick takes a tie; a log without a unit has none; and a log that
## stops inside a command is read as far as it goes.
func test_the_largest_order_tick_sums_the_units_of_a_tick_and_ties_go_to_the_lowest() -> void:
	assert_array(_largest(PackedInt32Array())).is_equal([-1, 0])
	assert_array(_largest(_log([[5, 3]]))).is_equal([5, 3])
	# Tick 3 orders 25 + 20 units in two commands; tick 7 orders 40 in one.
	assert_array(_largest(_log([[3, 25], [7, 40], [3, 20]]))).is_equal([3, 45])
	assert_array(_largest(_log([[3, 25], [7, 40]]))).is_equal([7, 40])
	# Equal sums: the lower tick, whichever comes first in the log.
	assert_array(_largest(_log([[9, 10], [4, 10]]))).is_equal([4, 10])
	assert_array(_largest(_log([[4, 10], [9, 10]]))).is_equal([4, 10])
	# Commands with no unit do not make a tick.
	assert_array(_largest(_log([[2, 0], [6, 0]]))).is_equal([-1, 0])
	assert_array(_largest(_log([[2, 0], [6, 1]]))).is_equal([6, 1])
	# A log cut inside its last command keeps the commands before it.
	var cut: PackedInt32Array = _log([[3, 25], [7, 40]])
	cut.resize(cut.size() - 5)
	assert_array(_largest(cut)).is_equal([3, 25])


## The job minus Sim.step, tick by tick, for the checkpoint ticks (the step that ends on a multiple
## of 15: index 14, 29, ...) or for all the others, in tick order, from the two series; the shorter
## series sets the length.
func test_the_job_minus_step_series_splits_the_ticks_at_the_checkpoints() -> void:
	var job: PackedFloat64Array = PackedFloat64Array()
	var step: PackedFloat64Array = PackedFloat64Array()
	for index: int in 31:
		step.append(1.0 + index)
		job.append(1.0 + index + 0.5 + index * 0.01)
	var at_checkpoint: PackedFloat64Array = PerfReport.job_minus_step_ms(job, step, true)
	assert_int(at_checkpoint.size()).is_equal(2)
	assert_float(at_checkpoint[0]).is_equal_approx(0.5 + 14 * 0.01, 0.00001)
	assert_float(at_checkpoint[1]).is_equal_approx(0.5 + 29 * 0.01, 0.00001)
	var elsewhere: PackedFloat64Array = PerfReport.job_minus_step_ms(job, step, false)
	assert_int(elsewhere.size()).is_equal(29)
	assert_float(elsewhere[0]).is_equal_approx(0.5, 0.00001)
	assert_float(elsewhere[14]).is_equal_approx(0.5 + 15 * 0.01, 0.00001)
	assert_float(elsewhere[28]).is_equal_approx(0.5 + 30 * 0.01, 0.00001)
	# Sixteen ticks of the job against 31 of the step: 16 pairs, one checkpoint among them.
	var short: PackedFloat64Array = job.slice(0, 16)
	assert_int(PerfReport.job_minus_step_ms(short, step, true).size()).is_equal(1)
	assert_int(PerfReport.job_minus_step_ms(short, step, false).size()).is_equal(15)
	assert_int(PerfReport.job_minus_step_ms(PackedFloat64Array(), step, true).size()).is_equal(0)


## The nearest-rank 95th percentile of 20 values in any order is the 19th smallest; one value is
## itself; none is 0; the caller's array keeps its order.
func test_p95_is_the_nearest_rank_of_the_sorted_values_and_leaves_the_input_alone() -> void:
	var values: PackedFloat64Array = PackedFloat64Array()
	for index: int in 20:
		values.append(float((index * 7) % 20 + 1))
	var before: PackedFloat64Array = values.duplicate()
	assert_float(PerfReport.p95(values)).is_equal(19.0)
	assert_array(values).is_equal(before)
	assert_float(PerfReport.p95(PackedFloat64Array([4.5]))).is_equal(4.5)
	assert_float(PerfReport.p95(PackedFloat64Array())).is_equal(0.0)


## A sub-line is the head, `impl=native` after it for the native run only, and `key=value` for the
## entries in their order: floats with three decimals, ints plain. None starts with `PERF `, which
## is what P51 copies. The heads are the ones the suite prints.
func test_a_sub_line_is_the_head_the_native_marker_and_the_values_in_order() -> void:
	var values: Dictionary = {"order_tick": 0, "commands_ms": 1.23456, "crafted_units": 150}
	assert_str(PerfReport.sub_line("WATCH sim x", values, false)).is_equal(
		"WATCH sim x order_tick=0 commands_ms=1.235 crafted_units=150"
	)
	assert_str(PerfReport.sub_line("WATCH sim x", values, true)).is_equal(
		"WATCH sim x impl=native order_tick=0 commands_ms=1.235 crafted_units=150"
	)
	assert_str(PerfReport.sub_line("STEP sim", {}, true)).is_equal("STEP sim impl=native")
	assert_str(PerfReport.STEP_HEAD).is_equal("STEP sim")
	assert_str(PerfReport.COMMANDS_HEAD).is_equal("WATCH sim commands")
	assert_str(PerfReport.OVERHEAD_HEAD).is_equal("WATCH sim job_minus_step")
	assert_array(PerfReport.STEP_KEYS).is_equal(["mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms"])
	for head: String in [PerfReport.STEP_HEAD, PerfReport.COMMANDS_HEAD, PerfReport.OVERHEAD_HEAD]:
		assert_bool(head.begins_with("PERF ")).is_false()


## (tick, units) of the largest order tick of `log`, as an array to compare.
func _largest(log: PackedInt32Array) -> Array[int]:
	var best: Vector2i = PerfReport.largest_order_tick(log)
	return [best.x, best.y]


## A command log (the layout of Command.encode) of one command for each [tick, unit count] pair.
func _log(orders: Array[Array]) -> PackedInt32Array:
	var log: PackedInt32Array = PackedInt32Array()
	for order: Array in orders:
		var ids: PackedInt32Array = PackedInt32Array()
		ids.resize(order[1])
		var command: Command = Command.attack_move(1, ids, 0, 0)
		command.tick = order[0]
		command.encode(log)
	return log
