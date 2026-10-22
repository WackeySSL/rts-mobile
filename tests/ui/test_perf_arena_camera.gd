extends GdUnitTestSuite
## The perf arena's camera (plan P50c, ADR 0014 section 2), headless. Every run starts at the
## scenario's framing: the first one, and each one "Run again" or a layer-mode step starts, because
## the heavy window counts the rigs inside the camera and a pan carried into the next run shrinks
## it. The framing is put back after the runner's start and before the card's restart() (which
## reads the view the run is judged against), and the preflight's burst stays before both. A finger
## still pans and zooms the camera, but a move while a run records makes it INVALID
## (`camera_moved`). The rule itself is test_perf_hud_camera.gd's. The rig's seams log what the
## runner looks like when they run, as test_perf_arena.gd's do.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
## The framing of data/scenarios/perf_arena.tres: tile (32, 32) and its half, 64 px a tile, at the
## arena's start zoom.
const FRAMED_POSITION: Vector2 = Vector2(2080.0, 2080.0)
const FRAMED_ZOOM: Vector2 = Vector2(0.75, 0.75)

var _calls: Array[String] = []
var _max_fps_before: int = 0
var _arenas: Array[Node2D] = []


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


func test_the_first_run_starts_at_the_scenario_framing_and_the_card_watches_the_camera() -> void:
	var arena: Node2D = _open()
	var camera: RtsCamera = arena.camera
	var hud: PerfHud = arena.hud
	assert_vector(camera.position).is_equal(FRAMED_POSITION)
	assert_vector(camera.zoom).is_equal(FRAMED_ZOOM)
	assert_bool(hud.camera_source.is_valid()).is_true()
	assert_bool(hud.before_restart.is_valid()).is_true()
	assert_object(hud.camera_source.get_object()).is_same(camera)  # The view, not a copy of it.
	assert_that(hud.camera_source.call()).is_equal(camera.visible_world_rect())
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()  # A still camera.


func test_a_pan_or_a_zoom_during_the_first_run_makes_it_invalid() -> void:
	for move: String in ["pan", "zoom", "pinch"]:
		var arena: Node2D = _open()
		var hud: PerfHud = arena.hud
		_move(arena.camera, move)
		_frame(hud)
		assert_array(hud.summary()["invalid_reasons"]).override_failure_message(move).is_equal(
			[PerfHud.REASON_CAMERA_MOVED]
		)
		assert_bool(hud.summary()["gate_pass"]).override_failure_message(move).is_false()


func test_run_again_puts_a_moved_camera_back_between_the_runner_start_and_the_restart() -> void:
	var arena: Node2D = _open()
	var camera: RtsCamera = arena.camera
	var hud: PerfHud = arena.hud
	_log_the_hook(arena)
	var again: Button = hud.get_node("Column/Buttons/RunAgain")
	var serial: int = 1
	for move: String in ["pan", "zoom", "pinch", "corner", "pinch"]:  # Runs 2 to 6.
		_move(camera, move)
		assert_that(camera.visible_world_rect()).is_not_equal(_framed_view(arena))
		_calls.clear()
		again.pressed.emit()
		serial += 1
		(
			assert_array(_calls)
			. override_failure_message(move)
			. is_equal(
				[
					"burst job=false world=set serial=%d" % (serial - 1),
					"frame serial=%d" % serial,
					"restart serial=%d" % serial,
				]
			)
		)
		assert_vector(camera.position).override_failure_message(move).is_equal(FRAMED_POSITION)
		assert_vector(camera.zoom).override_failure_message(move).is_equal(FRAMED_ZOOM)
		_frame(hud)  # The run judges its camera against the framing, not against the move.
		assert_array(hud.summary()["invalid_reasons"]).override_failure_message(move).is_empty()
	assert_int(hud.summary()["runs"]).is_equal(6)


func test_a_pan_during_a_run_that_run_again_started_is_invalid_and_the_next_run_is_clean() -> void:
	var arena: Node2D = _open()
	var hud: PerfHud = arena.hud
	var again: Button = hud.get_node("Column/Buttons/RunAgain")
	again.pressed.emit()
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()
	_move(arena.camera, "pan")
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_equal([PerfHud.REASON_CAMERA_MOVED])
	arena.camera.centre_on(FRAMED_POSITION)  # Panned back: the latch holds until the next run.
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_equal([PerfHud.REASON_CAMERA_MOVED])
	again.pressed.emit()
	_frame(hud)
	assert_array(hud.summary()["invalid_reasons"]).is_empty()


func test_a_layer_mode_step_puts_a_moved_camera_back_before_the_next_run_records() -> void:
	var arena: Node2D = _open()
	var camera: RtsCamera = arena.camera
	var hud: PerfHud = arena.hud
	_log_the_hook(arena)
	for move: String in ["pan", "pinch"]:
		_move(camera, move)
		_calls.clear()
		var mode: String = arena.layer_mode
		(arena.layers_button as Button).pressed.emit()
		var serial: int = arena.runner.match_serial
		assert_str(arena.layer_mode).is_equal(Rig.ArenaScript.next_mode(mode))
		(
			assert_array(_calls)
			. override_failure_message(move)
			. is_equal(
				[
					"burst job=false world=set serial=%d" % (serial - 1),
					"frame serial=%d" % serial,
					"restart serial=%d" % serial,
				]
			)
		)
		assert_vector(camera.position).override_failure_message(move).is_equal(FRAMED_POSITION)
		assert_vector(camera.zoom).override_failure_message(move).is_equal(FRAMED_ZOOM)
		_frame(hud)
		assert_array(hud.summary()["invalid_reasons"]).override_failure_message(move).is_empty()


func test_the_framing_does_not_depend_on_where_the_camera_was() -> void:
	var arena: Node2D = _open()
	var camera: RtsCamera = arena.camera
	for corner: Vector2 in [Vector2.ZERO, Vector2(9000.0, 9000.0), Vector2(0.0, 9000.0)]:
		camera.zoom = Vector2.ONE * 1.5
		camera.centre_on(corner)
		arena.frame_camera()
		assert_vector(camera.position).is_equal(FRAMED_POSITION)
		assert_vector(camera.zoom).is_equal(FRAMED_ZOOM)
	arena.frame_camera()  # And again: framing a framed camera moves nothing.
	assert_that(camera.visible_world_rect()).is_equal(_framed_view(arena))


## Logs the framing step into `_calls` (the rig's seams log the burst and the restart), then runs
## it.
func _log_the_hook(arena: Node2D) -> void:
	var framing: Callable = arena.hud.before_restart
	var runner: MatchRunner = arena.runner
	arena.hud.before_restart = func() -> void:
		_calls.append("frame serial=%d" % runner.match_serial)
		framing.call()


## A finger on the camera: a pan, a zoom with the position kept, a pinch about a point (both move),
## or the camera thrown into the corner of the map.
func _move(camera: RtsCamera, how: String) -> void:
	match how:
		"pan":
			camera.pan_by_screen(Vector2(300.0, 200.0))
		"zoom":
			camera.zoom = Vector2.ONE * 1.5
		"pinch":
			camera.pinch(Vector2(900.0, 200.0), 1.6)
		"corner":
			camera.centre_on(Vector2.ZERO)
	assert_bool(camera.position != FRAMED_POSITION or camera.zoom != FRAMED_ZOOM).is_true()


## The visible world rect of a camera at the framing.
func _framed_view(arena: Node2D) -> Rect2:
	var view: Vector2 = arena.camera.get_viewport_rect().size / FRAMED_ZOOM
	return Rect2(FRAMED_POSITION - view * 0.5, view)


## One recorded frame of a run that would pass, so the HUD compares the camera with the run's start.
func _frame(hud: PerfHud) -> void:
	hud.record_frame(16667, 3000, 1000, 40, 140, false, 25, -1)


## An arena in the tree with its seams logging into `_calls`; freed with the case.
func _open() -> Node2D:
	var arena: Node2D = Rig.open(self, _calls)
	_arenas.append(arena)
	return arena
