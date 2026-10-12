extends GdUnitTestSuite
## The perf probe's worker mode (P26s, ADR 0012 section 1): the fourth "Next mode" runs each mock
## tick on one dedicated Thread. Proved here without a phone: the mode is reachable from the
## button, the worker plays the same ticks as the frame would (the view's copies do not change the
## sim), a job that outlasts the period is counted as a late tick without stopping the frames, a
## main-thread hitch is a held tick and never a late one (ADR 0012 section 1), a swapped `sim`
## drives the view in the in-frame modes, and the thread is joined when the scene leaves the tree
## with Engine.max_fps restored. Timing is never asserted, except that the frames keep coming while
## a 600 ms job runs. Since P26n2 every later mode starts from a fresh tick made by `new_sim`, so a
## test that swaps `sim` for a slow tick swaps the maker too, and the burst before every run is
## shortened here (tests/ui/test_perf_probe_calib.gd covers it).

const SCENE: String = "res://scenes/dev/perf_probe.tscn"
const WORKER_MODE: int = 3
const LATE_ROW: String = "late ticks (job post to done above 66.7 ms): "
const HELD_ROW: String = "held ticks (boundary reached with the job running): "
const SHORT_BURST_USEC: int = 20000


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
	# P26n: the cycle has a fifth mode now (the C++ worker, tests/ui/test_perf_probe_native.gd), so
	# two presses lead back to the in-frame mode: the worker is joined, `sim` is ours.
	_press_next_mode(probe, 2)
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
	assert_str(report).contains(HELD_ROW)
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
	assert_int(_held_ticks(report)).is_greater_equal(2)  # Each of those jobs held a boundary.
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


func test_a_main_thread_hitch_holds_a_quick_job_but_does_not_make_it_late() -> void:
	var slow: SlowTick = SlowTick.new()
	slow.delay_msec = 40  # Under the 66.7 ms period, and still running one frame after its post.
	var probe: Node2D = _open(slow)
	probe.set_process(false)  # The test plays the frames itself, at the lengths it picks.
	_press_next_mode(probe, WORKER_MODE)
	_frame(probe, 16)  # Posts the first job.
	OS.delay_msec(100)  # The job is done long before the next frame.
	# A 128 ms frame publishes it and keeps 61 ms of the next period owed, so the next frame reaches
	# a boundary one frame after the second job's post, with that job still running: a held tick.
	_frame(probe, 128)
	_frame(probe, 8)
	OS.delay_msec(100)
	_frame(probe, 16)  # The second job is published after its hold.
	var report: String = probe.report()
	assert_int(_ticks_published(report)).is_equal(2)
	assert_int(_held_ticks(report)).is_equal(1)
	assert_int(_late_ticks(report)).is_equal(0)  # No job came near the period.
	remove_child(probe)
	probe.free()


func test_a_swapped_sim_drives_the_view_in_the_in_frame_modes() -> void:
	var swapped: PerfProbeTick = PerfProbeTick.new()
	var probe: Node2D = _open(swapped)
	probe.set_process(false)
	var from_x: PackedInt32Array = swapped.x.duplicate()
	var from_y: PackedInt32Array = swapped.y.duplicate()
	_frame(probe, 100)  # One tick of `swapped`, and half a tick over: the rigs sit half way.
	assert_int(swapped.tick).is_equal(4)  # Three warm-up ticks and the one played.
	var moved: int = 0
	for i: int in PerfProbeTick.UNITS:
		var from: Vector2 = ViewScale.milli_to_px_vec(from_x[i], from_y[i])
		var to: Vector2 = ViewScale.milli_to_px_vec(swapped.x[i], swapped.y[i])
		if from.distance_to(to) > 4.0:  # A stale view would leave this rig on `from`.
			moved += 1
			assert_float(probe._rigs[i].position.distance_to(from.lerp(to, 0.5))).is_less(0.5)
	assert_int(moved).is_greater(20)
	remove_child(probe)
	probe.free()


## The scene in the tree, in its first mode; `sim` is swapped before `_ready` when one is given,
## and a slow one is what every later mode starts from too.
func _open(sim: PerfProbeTick) -> Node2D:
	var packed: PackedScene = load(SCENE)
	var probe: Node2D = packed.instantiate()
	probe.burst_usec = SHORT_BURST_USEC
	if sim != null:
		probe.sim = sim
	if sim is SlowTick:
		var delay: int = (sim as SlowTick).delay_msec
		probe.new_sim = func() -> PerfProbeTick: return _slow_tick(delay)
	add_child(probe)
	return probe


## A fresh slow tick: the constructor's three warm-up ticks run before the delay is set. Built here
## and not by a static function of SlowTick: a class that names itself in its own body leaves the
## scripts alive at exit when a suite that names PerfProbeTick ran first
## (tests/project/test_inner_class_self_reference.gd).
func _slow_tick(delay: int) -> SlowTick:
	var tick: SlowTick = SlowTick.new()
	tick.delay_msec = delay
	return tick


func _press_next_mode(probe: Node2D, times: int) -> void:
	var button: Button = probe.get_node("Hud/Margin/Buttons/RingsButton")
	for _i: int in times:
		button.pressed.emit()


## One frame of `ms` milliseconds, played by hand: the probe measures a frame from the last one.
func _frame(probe: Node2D, ms: int) -> void:
	probe._last_us = Time.get_ticks_usec() - ms * 1000
	probe._process(0.0)


func _late_ticks(report: String) -> int:
	return _number(report, "late ticks \\(job post to done above [\\d.]+ ms\\): (\\d+) of")


func _held_ticks(report: String) -> int:
	return _number(report, "held ticks \\(boundary reached with the job running\\): (\\d+) of")


func _ticks_published(report: String) -> int:
	return _number(report, "held ticks \\(boundary reached with the job running\\): \\d+ of (\\d+)")


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
