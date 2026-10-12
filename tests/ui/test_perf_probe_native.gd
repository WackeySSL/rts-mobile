extends GdUnitTestSuite
## The perf probe's fifth mode (spike P26n, never merged): "sprite rings, C++ worker tick" is the
## worker mode with the job running ProbeTickNative, the GDExtension port of the mock tick. Proved
## here without a phone: the mode is reachable from the button, the C++ tick runs on a thread that
## is not the main thread, a quick run has no late ticks, the card and the report name the tick
## implementation and carry the 60-tick lockstep self-check line, the view follows the C++ object,
## and without the library the mode says so instead of crashing. The library is built by
## scripts/build-native.sh (verify.sh does it first); a missing one fails the tests that need it.

const SCENE: String = "res://scenes/dev/perf_probe.tscn"
const NATIVE_MODE: int = 4
const WORKER_MODE: int = 3
const NOT_LOADED: String = "ProbeTickNative not loaded: run scripts/build-native.sh"
const CHECK_LINE: String = "C++ matches GDScript: yes (60 ticks)"
const MISSING: String = "C++ tick not available on this build"


func test_the_next_mode_button_reaches_the_cpp_mode_from_the_worker_mode_and_leaves_it_joined(
) -> void:
	if not _loaded():
		return
	var probe: Node2D = _open()
	_press_next_mode(probe, WORKER_MODE)
	assert_bool(probe.worker_active()).is_true()
	assert_object(probe.native).is_null()
	_press_next_mode(probe, 1)  # The GDScript worker is joined, the C++ one starts.
	assert_int(probe.mode).is_equal(NATIVE_MODE)
	assert_bool(probe.worker_active()).is_true()
	assert_object(probe.native).is_not_null()
	assert_str(probe.report()).contains("PERF PROBE P26s | sprite rings, C++ worker tick | running")
	_press_next_mode(probe, 1)  # Back to mode 1: the worker is joined, the C++ tick is dropped.
	assert_int(probe.mode).is_equal(0)
	assert_bool(probe.worker_active()).is_false()
	assert_object(probe.native).is_null()
	assert_str(probe.report()).contains("tick impl: GDScript")
	_press_next_mode(probe, NATIVE_MODE)
	assert_bool(probe.worker_active()).is_true()
	remove_child(probe)  # _exit_tree joins the thread.
	assert_bool(probe.worker_active()).is_false()
	probe.free()


func test_the_cpp_tick_runs_on_a_worker_thread_with_no_late_ticks_and_the_card_says_so() -> void:
	if not _loaded():
		return
	var probe: Node2D = _open()
	_press_next_mode(probe, NATIVE_MODE)
	await await_millis(1500)  # About 22 ticks: the flow slice of tick 15 has run too.
	var report: String = probe.report()
	assert_str(report).contains("tick impl: C++ (")
	assert_str(report).contains(CHECK_LINE)
	assert_str(report).contains("job post to done (worker wake-up + tick + slice): p95 ")
	assert_str(report).contains("mock tick (15 Hz, usec timer): p95 ")
	assert_int(_late_ticks(report)).is_equal(0)
	assert_int(_ticks_published(report)).is_greater_equal(8)
	assert_str(probe._card.text).contains("tick impl: C++")  # The running card names it too.
	assert_str(probe._card.text).contains(CHECK_LINE)
	remove_child(probe)  # Joins the worker; a job in flight finishes first.
	var native: RefCounted = probe.native
	assert_int(native.tick).is_greater(15)
	var main_thread: int = OS.get_main_thread_id()
	assert_int(OS.get_thread_caller_id()).is_equal(main_thread)  # The test itself is the main thread.
	assert_int(native.get_last_step_thread()).is_not_equal(0)
	assert_int(native.get_last_step_thread()).is_not_equal(main_thread)
	assert_int(native.get_last_slice_thread()).is_not_equal(0)
	assert_int(native.get_last_slice_thread()).is_not_equal(main_thread)
	probe.free()


func test_the_view_follows_the_cpp_tick_and_it_plays_the_same_ticks() -> void:
	if not _loaded():
		return
	var probe: Node2D = _open()
	var start_x: PackedInt32Array = probe.sim.x.duplicate()
	_press_next_mode(probe, NATIVE_MODE)
	await await_millis(1500)
	remove_child(probe)
	var native: RefCounted = probe.native
	var shown: PerfProbeTick = probe._shown
	assert_object(probe._view).is_same(shown)  # The frame read the copies, not `sim`.
	assert_bool(shown.x == start_x).is_false()  # Published ticks moved the units.
	# The worker is joined: its last job ran one tick past the last one published. The reference
	# plays what the probe plays (a flow slice of 512 cells on every 15th tick).
	var reference: PerfProbeTick = PerfProbeTick.new()
	while reference.tick < native.tick - 1:
		reference.step()
		if reference.tick % 15 == 0:
			reference.flow_slice(512)
	assert_int(reference.tick).is_equal(native.tick - 1)
	assert_array(shown.x).is_equal(reference.x)
	assert_array(shown.y).is_equal(reference.y)
	assert_array(shown.target).is_equal(reference.target)
	reference.step()
	if reference.tick % 15 == 0:
		reference.flow_slice(512)
	# Not `dirty` and `dirty_count`: the fog patch consumed them on the C++ object during the run.
	var found: String = PerfProbeLockstep.difference(reference, native, false)
	assert_str(found).override_failure_message("C++ differs from GDScript: " + found).is_empty()
	assert_array(probe.sim.x).is_equal(start_x)  # `sim` was never touched by the C++ worker.
	probe.free()


func test_without_the_library_mode_five_says_so_and_measures_nothing() -> void:
	var probe: Node2D = _open()
	probe.native_class = "NoSuchProbeTickNative"  # What a build without the library looks like.
	_press_next_mode(probe, NATIVE_MODE)
	assert_int(probe.mode).is_equal(NATIVE_MODE)
	assert_bool(probe.native_available()).is_false()
	assert_bool(probe.worker_active()).is_false()
	assert_object(probe.native).is_null()
	assert_str(probe.report()).contains(MISSING)
	assert_str(probe.report()).contains("tick impl: C++")
	assert_str(probe._card.text).contains(MISSING)  # The card shows it at once and stays.
	await await_millis(300)  # The frames go on; nothing crashes, nothing ticks.
	assert_str(probe._card.text).contains(MISSING)
	assert_int(probe.sim.tick).is_equal(3)  # Only the constructor's warm-up ticks.
	_press_next_mode(probe, 1)  # Next mode wraps to the first.
	assert_int(probe.mode).is_equal(0)
	assert_str(probe.report()).contains("tick impl: GDScript")
	remove_child(probe)
	probe.free()


func test_every_mode_names_its_tick_implementation() -> void:
	var probe: Node2D = _open()
	await await_millis(100)  # A frame or two: the card is written by `_process`.
	assert_str(probe._card.text).contains("tick impl: GDScript")
	for mode: int in [0, 1, 2]:
		assert_int(probe.mode).is_equal(mode)
		assert_str(probe.report()).contains("tick impl: GDScript")
		_press_next_mode(probe, 1)
	assert_int(probe.mode).is_equal(WORKER_MODE)
	assert_str(probe.report()).contains("tick impl: GDScript")
	remove_child(probe)
	probe.free()


func _loaded() -> bool:
	var loaded: bool = ClassDB.class_exists(PerfProbeLockstep.NATIVE_CLASS)
	assert_bool(loaded).override_failure_message(NOT_LOADED).is_true()
	return loaded


func _open() -> Node2D:
	var packed: PackedScene = load(SCENE)
	var probe: Node2D = packed.instantiate()
	add_child(probe)
	return probe


func _press_next_mode(probe: Node2D, times: int) -> void:
	var button: Button = probe.get_node("Hud/Margin/Buttons/RingsButton")
	for _i: int in times:
		button.pressed.emit()


func _late_ticks(report: String) -> int:
	return _number(report, "late ticks \\(job post to done above [\\d.]+ ms\\): (\\d+) of")


func _ticks_published(report: String) -> int:
	return _number(report, "held ticks \\(boundary reached with the job running\\): \\d+ of (\\d+)")


func _number(text: String, pattern: String) -> int:
	var found: RegExMatch = RegEx.create_from_string(pattern).search(text)
	assert_object(found).override_failure_message("no match for " + pattern).is_not_null()
	return found.get_string(1).to_int() if found != null else -1
