extends GdUnitTestSuite
## The perf probe's worker mode (P26s, ADR 0012 section 1): the fourth "Next mode" runs each mock
## tick on one dedicated Thread. Proved here without a phone: the mode is reachable from the
## button, the worker plays the same ticks as the frame would (the view's copies do not change the
## sim), a job that outlasts the period is counted as a late tick without stopping the frames, and
## the thread is joined when the scene leaves the tree with Engine.max_fps restored. Timing is never
## asserted, except that the frames keep coming while a 600 ms job runs.

const SCENE: String = "res://scenes/dev/perf_probe.tscn"
const WORKER_MODE: int = 3
const LATE_ROW: String = "late ticks (job still running at a 15 Hz boundary): "


## A tick that outlasts several periods (66.7 ms each) once `delay_msec` is set.
class SlowTick:
	extends PerfProbeTick

	var delay_msec: int = 0

	func step() -> int:
		OS.delay_msec(delay_msec)
		return super.step()


func test_the_next_mode_button_reaches_the_worker_mode_and_leaves_it_joined() -> void:
	var fps_before: int = Engine.max_fps
	var probe: Node2D = _open(null)
	assert_int(probe.mode).is_equal(0)
	assert_bool(probe.worker_active()).is_false()
	_press_next_mode(probe, WORKER_MODE)
	assert_int(probe.mode).is_equal(WORKER_MODE)
	assert_bool(probe.worker_active()).is_true()
	assert_int(Engine.max_fps).is_equal(60)
	_press_next_mode(probe, 1)  # Back to the in-frame mode: the worker is joined, `sim` is ours.
	assert_int(probe.mode).is_equal(0)
	assert_bool(probe.worker_active()).is_false()
	assert_int(probe.sim.tick).is_greater_equal(3)
	_press_next_mode(probe, WORKER_MODE)
	assert_bool(probe.worker_active()).is_true()
	remove_child(probe)  # _exit_tree joins the thread and restores Engine.max_fps.
	assert_bool(probe.worker_active()).is_false()
	assert_int(Engine.max_fps).is_equal(fps_before)
	probe.free()


func test_the_worker_plays_the_same_ticks_and_the_card_has_the_new_rows() -> void:
	var probe: Node2D = _open(null)
	_press_next_mode(probe, WORKER_MODE)
	await await_millis(1300)  # About 19 ticks at 15 Hz.
	var report: String = probe.report()
	assert_str(report).contains("PERF PROBE P26s | sprite rings, worker tick | running")
	assert_str(report).contains(LATE_ROW)
	assert_str(report).contains("job post to done (worker wake-up + tick + slice): p95 ")
	assert_str(report).contains("mock tick (15 Hz, usec timer): p95 ")  # The row keeps its label.
	assert_int(_ticks_published(report)).is_greater_equal(8)
	remove_child(probe)  # Joins the worker; a job in flight finishes first.
	var reference: PerfProbeTick = PerfProbeTick.new()  # Plays what the in-frame modes play.
	while reference.tick < probe.sim.tick:
		reference.step()
		if reference.tick % 15 == 0:
			reference.flow_slice(512)  # The probe's FLOW_CELLS.
	assert_int(reference.tick).is_equal(probe.sim.tick)
	assert_int(reference.tick).is_greater(15)  # At least one flow slice ran.
	assert_array(probe.sim.flow_cost).is_equal(reference.flow_cost)
	assert_array(probe.sim.x).is_equal(reference.x)
	assert_array(probe.sim.y).is_equal(reference.y)
	assert_array(probe.sim.target).is_equal(reference.target)
	assert_array(probe.sim.seen).is_equal(reference.seen)
	probe.free()


func test_a_job_that_outlasts_the_period_is_a_late_tick_and_does_not_block_the_frame() -> void:
	var slow: SlowTick = SlowTick.new()
	slow.delay_msec = 600
	var probe: Node2D = _open(slow)
	_press_next_mode(probe, WORKER_MODE)
	await await_millis(2000)
	var report: String = probe.report()
	assert_int(_late_ticks(report)).is_greater_equal(2)  # One per job, three jobs in 2 s.
	assert_int(_ticks_published(report)).is_greater_equal(2)  # Late jobs are still published.
	# A main thread that waited for a job would stand still for about 530 ms, and manage about 40
	# frames in the 2 s where 60 fps gives 120.
	assert_int(_max_frame_ms(report)).is_less(300)
	assert_int(_frames(report)).is_greater(60)
	remove_child(probe)
	assert_bool(probe.worker_active()).is_false()
	probe.free()


func test_a_quick_job_is_never_late() -> void:
	var probe: Node2D = _open(null)
	_press_next_mode(probe, WORKER_MODE)
	await await_millis(900)
	assert_int(_late_ticks(probe.report())).is_equal(0)
	remove_child(probe)
	probe.free()


## The scene in the tree, in its first mode; `sim` is swapped before `_ready` when one is given.
func _open(sim: PerfProbeTick) -> Node2D:
	var packed: PackedScene = load(SCENE)
	var probe: Node2D = packed.instantiate()
	if sim != null:
		probe.sim = sim
	add_child(probe)
	return probe


func _press_next_mode(probe: Node2D, times: int) -> void:
	var button: Button = probe.get_node("Hud/Margin/Buttons/RingsButton")
	for _i: int in times:
		button.pressed.emit()


func _late_ticks(report: String) -> int:
	return _number(report, "late ticks \\(job still running at a 15 Hz boundary\\): (\\d+) of")


func _ticks_published(report: String) -> int:
	return _number(report, "boundary\\): \\d+ of (\\d+) ticks")


## Whole milliseconds of the slowest frame.
func _max_frame_ms(report: String) -> int:
	var row: String = "frame interval \\(wall clock\\): p95 [\\d.]+, mean [\\d.]+, max (\\d+)"
	return _number(report, row)


func _frames(report: String) -> int:
	return _number(report, "frames (\\d+) in")


func _number(text: String, pattern: String) -> int:
	var found: RegExMatch = RegEx.create_from_string(pattern).search(text)
	assert_object(found).override_failure_message("no match for " + pattern).is_not_null()
	return found.get_string(1).to_int() if found != null else -1
