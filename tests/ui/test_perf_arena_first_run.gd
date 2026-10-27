extends GdUnitTestSuite
## The perf arena's first run waits for landscape (plan P63c, ADR 0015, ADR 0011 section 5). After
## the flip a phone held upright opens the arena in a portrait window: entry asks for sensor
## landscape, but Android turns the window a few frames later, while `_ready` has already framed
## the camera and started the run, which would be INVALID for `camera_moved` and `portrait`. So
## where entry asked for the lock (the orientation feature, injected here as in
## test_perf_arena_orientation.gd) and the viewport is portrait, the runner's start, the framing and
## the card's first run wait for the viewport's `size_changed` that makes it landscape, at most
## `LANDSCAPE_WAIT_FRAMES` frames, and the run that starts anyway is marked `portrait`. Without the
## lock (the web preview, headless) or in a landscape view the first run starts at once, as before.
## The viewport is the test window, turned by its size (the UiOrientation autoload answers the
## change as it does on the phone); the frames of the bound are `_process` calls, so the bound is
## exact. The card's portrait rule on its own: test_perf_hud_portrait.gd and
## test_perf_arena_portrait.gd.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
## The log of an arena that waits: the preflight ran (no World, no job), and no run restarted.
const PREFLIGHT: Array[String] = [
	"self_check job=false world=null serial=0",
	"burst job=false world=null serial=0",
]
const RESTART: String = "restart serial=1"
## The framing of data/scenarios/perf_arena.tres at the arena's start zoom (test_perf_arena_camera).
const FRAMED_POSITION: Vector2 = Vector2(0.0, 1040.0)
const FRAMED_ZOOM: Vector2 = Vector2(0.75, 0.75)

var _calls: Array[String] = []
var _arenas: Array[Node2D] = []
var _window_size_before: Vector2i
var _max_fps_before: int = 0


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_max_fps_before = Engine.max_fps
	CommandQueue.clear()


## Every arena is freed (which restores the frame cap), the last one in first.
func after_test() -> void:
	_arenas.reverse()
	for arena: Node2D in _arenas:
		if is_instance_valid(arena):
			Rig.close(self, arena)
	_arenas.clear()
	_calls.clear()
	assert_int(Engine.max_fps).is_equal(_max_fps_before)
	CommandQueue.clear()


func test_no_run_starts_in_a_portrait_view_until_the_viewport_turns_landscape() -> void:
	for at: int in ScreenSizes.PORTRAIT.size():
		var label: String = str(ScreenSizes.PORTRAIT[at])
		var arena: Node2D = await _open(ScreenSizes.PORTRAIT[at], true)
		await _frames(2)  # Frames with no match: the layers have no snapshot to show.
		_assert_waiting(arena, label)
		# Another portrait size is no turn.
		get_window().size = ScreenSizes.PORTRAIT[(at + 1) % ScreenSizes.PORTRAIT.size()]
		await _frames(2)
		_assert_waiting(arena, label + " resized")
		get_window().size = ScreenSizes.LANDSCAPE[at]  # The phone is upright no longer.
		await _frames(2)
		var hud: PerfHud = arena.hud
		var camera: RtsCamera = arena.camera
		assert_array(_calls).override_failure_message(label).is_equal(PREFLIGHT + [RESTART])
		assert_int(arena.runner.match_serial).override_failure_message(label).is_equal(1)
		assert_int(hud.summary()["runs"]).override_failure_message(label).is_equal(1)
		assert_vector(camera.position).override_failure_message(label).is_equal(FRAMED_POSITION)
		assert_vector(camera.zoom).override_failure_message(label).is_equal(FRAMED_ZOOM)
		_frame(hud)  # The first recorded frame judges the camera and the view.
		assert_array(hud.summary()["invalid_reasons"]).override_failure_message(label).is_empty()
		# The run is started once: more frames, and a resize within landscape, start none.
		for _frame_count: int in Rig.ArenaScript.LANDSCAPE_WAIT_FRAMES + 10:
			arena._process(0.0)
		get_window().size = ScreenSizes.LANDSCAPE[(at + 1) % ScreenSizes.LANDSCAPE.size()]
		await _frames(2)
		assert_int(arena.runner.match_serial).override_failure_message(label).is_equal(1)
		assert_int(hud.summary()["runs"]).override_failure_message(label).is_equal(1)
		Rig.close(self, arena)
		_calls.clear()


func test_the_wait_is_bounded_and_the_run_that_starts_anyway_is_marked_portrait() -> void:
	var bound: int = Rig.ArenaScript.LANDSCAPE_WAIT_FRAMES
	assert_int(bound).is_greater(0)
	var arena: Node2D = await _open(ScreenSizes.PORTRAIT[1], true)  # The window never turns.
	for _frame_count: int in bound - 1:
		arena._process(0.0)
	_assert_waiting(arena, "after %d frames" % (bound - 1))
	arena._process(0.0)
	var hud: PerfHud = arena.hud
	assert_array(_calls).is_equal(PREFLIGHT + [RESTART])  # The bound'th frame starts it.
	assert_int(arena.runner.match_serial).is_equal(1)
	assert_int(hud.summary()["runs"]).is_equal(1)
	assert_vector(arena.camera.zoom).is_equal(FRAMED_ZOOM)
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_equal([PerfHud.REASON_PORTRAIT])
	assert_bool(hud.summary()["gate_pass"]).is_false()
	for _frame_count: int in bound:  # Started once: the count does not run on.
		arena._process(0.0)
	assert_int(arena.runner.match_serial).is_equal(1)
	assert_int(hud.summary()["runs"]).is_equal(1)


func test_without_the_lock_or_in_a_landscape_view_the_first_run_starts_at_once() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		for lock: bool in [false, true]:
			var label: String = "%s, lock %s" % [size, lock]
			var arena: Node2D = await _open(size, lock)
			var waits: bool = lock and ScreenSizes.PORTRAIT.has(size)
			var want: Array = PREFLIGHT if waits else PREFLIGHT + [RESTART]
			assert_array(_calls).override_failure_message(label).is_equal(want)
			assert_int(arena.runner.match_serial).override_failure_message(label).is_equal(
				0 if waits else 1
			)
			assert_int(arena.hud.summary()["runs"]).override_failure_message(label).is_equal(
				0 if waits else 1
			)
			Rig.close(self, arena)
			_calls.clear()


## A removed arena stays connected to the root viewport until it is freed, and outside the tree it
## reads no view (a size that is not portrait), so only the wait's end keeps a turn or the bound
## from starting a match in it. The turn is the handler called by hand: a real size change would
## run the other scenes' handlers too, and they need their tree.
func test_an_arena_that_left_the_tree_during_the_wait_starts_no_run() -> void:
	var arena: Node2D = await _open(ScreenSizes.PORTRAIT[1], true)
	remove_child(arena)
	arena._on_view_resized()
	for _frame_count: int in Rig.ArenaScript.LANDSCAPE_WAIT_FRAMES + 1:
		arena._process(0.0)
	assert_array(_calls).is_equal(PREFLIGHT)
	assert_int(arena.runner.match_serial).is_equal(0)
	assert_int(arena.hud.summary()["runs"]).is_equal(0)


## The arena in the tree (its `_ready` has run) in a window of `size`, its preflight seams logging
## into `_calls`; `lock` is whether the display server has the orientation feature. It awaits only
## before the arena exists, so the caller counts every frame the arena sees.
func _open(size: Vector2i, lock: bool) -> Node2D:
	get_window().size = size
	await _frames(1)
	var arena: Node2D = Rig.make(_calls)
	arena.orientation_feature = func() -> bool: return lock
	arena.orientation_source = func() -> int: return DisplayServer.SCREEN_PORTRAIT
	arena.orientation_sink = func(_orientation: int) -> void: pass
	_arenas.append(arena)
	add_child(arena)
	return arena


## The arena has not started: the preflight ran, and no match, no snapshot, no run, no Command.
func _assert_waiting(arena: Node2D, label: String) -> void:
	assert_array(_calls).override_failure_message(label).is_equal(PREFLIGHT)
	assert_int(arena.runner.match_serial).override_failure_message(label).is_equal(0)
	assert_object(arena.runner.snapshot).override_failure_message(label).is_null()
	assert_int(arena.hud.summary()["runs"]).override_failure_message(label).is_equal(0)
	assert_int(CommandQueue.pending()).override_failure_message(label).is_equal(0)


func _frames(count: int) -> void:
	for _frame_count: int in count:
		await await_idle_frame()


## One recorded frame of a run that would pass, so the HUD judges the camera and the view.
func _frame(hud: PerfHud) -> void:
	hud.record_frame(16667, 3000, 1000, 40, 140, false, 25, -1)
