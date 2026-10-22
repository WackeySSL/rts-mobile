extends GdUnitTestSuite
## RtsCamera on the 48x48 tile map (3072 px): clamp cases at the three target screens, pan, pinch,
## the zoom levels, screen/world maths. Snaps are immediate unless a test sets `zoom_snap_ms`.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAP: Rect2 = Rect2(0, 0, 3072, 3072)
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
const PHONE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[1]
## A window as high as the base size and 320 px wider: it shows 1600x720 base px at stretch 1.
const WIDE_SIZE: Vector2i = Vector2i(1600, 720)
## Window size -> [lowest, highest] camera position at zoom 1: the map inset by half the visible
## size. Visible: 1280x720, 1600x720 (20:9 at stretch 1.5), 1280x960 (4:3 at 1.6).
const BOUNDS: Dictionary[Vector2i, Array] = {
	ScreenSizes.LANDSCAPE[0]: [Vector2(640, 360), Vector2(2432, 2712)],
	ScreenSizes.LANDSCAPE[1]: [Vector2(800, 360), Vector2(2272, 2712)],
	ScreenSizes.LANDSCAPE[2]: [Vector2(640, 480), Vector2(2432, 2592)],
}
const OVERSCROLL: float = 5000.0
const LEVELS: Array[float] = [0.75, 1.0, 1.5]
const POINT: Vector2 = Vector2(900, 200)  ## A screen point off the centre.

var _window_size_before: Vector2i
var _settings: InputSettings
var _camera: RtsCamera


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = BASE_SIZE
	await await_idle_frame()
	_settings = (load("res://data/input_settings.tres") as InputSettings).duplicate()
	_settings.zoom_snap_ms = 0
	_camera = _add_camera()


func test_starts_at_the_settings_start_level_and_falls_back_to_the_defaults() -> void:
	_zoom_is(1.0)
	_settings.zoom_start_index = 2
	assert_that(_add_camera().zoom).is_equal(Vector2(1.5, 1.5))
	var bare: RtsCamera = auto_free(RtsCamera.new())  # No settings: the InputSettings defaults.
	add_child(bare)
	assert_that(bare.zoom).is_equal(Vector2(1, 1))


func test_set_map_rect_sets_the_limits_reclamps_and_centres_a_narrow_map() -> void:
	_camera.centre_on(Vector2(OVERSCROLL, OVERSCROLL))
	assert_that(_camera.position).is_equal(Vector2(2432, 2712))
	_camera.set_map_rect(Rect2(100, 200, 3072, 2048))
	var limits: Array[int] = [
		_camera.limit_left, _camera.limit_top, _camera.limit_right, _camera.limit_bottom
	]
	assert_array(limits).contains_exactly([100, 200, 3172, 2248])
	_near(_camera.position, Vector2(2432, 1888))
	# 640 px is narrower than the 1280 px view: centred on x. y is clamped to 360..1640.
	_camera.set_map_rect(Rect2(0, 0, 640, 2000))
	_near(_camera.position, Vector2(320, 1640))
	_camera.set_map_rect(Rect2(0, 0, 2000, 500))  # 500 px is shorter than the 720 px view.
	_near(_camera.position, Vector2(640, 250))
	var detached: RtsCamera = auto_free(RtsCamera.new())
	detached.set_map_rect(MAP)  # Outside a tree there is no viewport to clamp to: no error.
	assert_int(detached.limit_right).is_equal(3072)


func test_position_stops_exactly_at_the_corners_with_no_dead_zone_at_every_target_size() -> void:
	for size: Vector2i in ScreenSizes.LANDSCAPE:
		var low: Vector2 = BOUNDS[size][0]
		var high: Vector2 = BOUNDS[size][1]
		get_window().size = size
		await await_idle_frame()
		_camera.pan_by_screen(Vector2(OVERSCROLL, OVERSCROLL))
		_near(_camera.position, low, str(size))
		# Back by 1000 px: an overscrolled position would leave the view where it was.
		_camera.pan_by_screen(Vector2(-1000, -1000))
		_near(_camera.position, low + Vector2(1000, 1000), str(size))
		_camera.pan_by_screen(Vector2(-OVERSCROLL, -OVERSCROLL))
		_near(_camera.position, high, str(size))
		_camera.pan_by_screen(Vector2(1000, 1000))
		_near(_camera.position, high - Vector2(1000, 1000), str(size))
		await await_idle_frame()
		_near(_camera.get_screen_center_position(), _camera.position)


func test_reclamps_when_the_viewport_resizes() -> void:
	_camera.pan_by_screen(Vector2(OVERSCROLL, OVERSCROLL))
	get_window().size = WIDE_SIZE
	await await_idle_frame()
	_near(_camera.position, Vector2(800, 360))


func test_zoomed_out_on_a_20_9_phone_the_map_is_wider_than_the_view_and_still_clamps() -> void:
	get_window().size = PHONE_SIZE
	await await_idle_frame()
	_camera.zoom = Vector2(0.75, 0.75)
	_near(_camera.visible_world_rect().size, Vector2(2133.3333, 960))
	_camera.pan_by_screen(Vector2(OVERSCROLL, OVERSCROLL))
	_near(_camera.position, Vector2(1066.6667, 480))
	_camera.pan_by_screen(Vector2(-OVERSCROLL, -OVERSCROLL))
	_near(_camera.position, Vector2(2005.3333, 2592))
	_near(_camera.visible_world_rect().end, MAP.end)
	await await_idle_frame()
	_near(_camera.get_screen_center_position(), _camera.position)  # The engine limits agree.


func test_pan_moves_by_minus_delta_over_zoom() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.pan_by_screen(Vector2(60, -30))
	_near(_camera.position, Vector2(1496, 1556))


func test_zooming_out_at_a_corner_reclamps_the_position() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.pan_by_screen(Vector2(OVERSCROLL, OVERSCROLL))  # The corner, (426.67, 240).
	_camera.pinch(Vector2(640, 360), 0.5)  # Zoom 0.75 about the view centre.
	_near(_camera.position, Vector2(853.3333, 480))  # The view grew, so the inset grew.


func test_pinch_keeps_the_world_point_under_the_centre_fixed_through_the_snap() -> void:
	var world: Vector2 = _camera.screen_to_world(POINT)
	for factor: float in [1.3, 0.8]:
		_camera.pinch(POINT, factor)
		_near(_camera.screen_to_world(POINT), world, str(factor), 0.5)
	_zoom_is(1.04)
	# The engine's own transform agrees, so the maths above is not just self-consistent.
	await await_idle_frame()
	_near(_camera.get_canvas_transform().affine_inverse() * POINT, world, "engine", 0.5)
	_camera.end_gesture()
	_zoom_is(1.0)
	_near(_camera.screen_to_world(POINT), world, "snap", 0.5)


func test_pinch_is_bounded_by_the_outer_levels_plus_minus_15_percent() -> void:
	_camera.pinch(POINT, 100.0)
	_zoom_is(1.725)
	_camera.pinch(POINT, 0.001)
	_zoom_is(0.6375)
	_settings.pinch_overshoot = 0.5
	_camera.pinch(POINT, 100.0)
	_zoom_is(2.25)
	_camera.pinch(POINT, NAN)  # Two fingers on one point give a NaN or 0 ratio: ignored.
	_camera.pinch(POINT, 0.0)
	_zoom_is(2.25)
	_camera.pinch(POINT, 0.001)
	_zoom_is(0.375)


func test_end_gesture_snaps_to_the_nearest_level_by_ratio() -> void:
	# The ratio midpoints are 0.866 and 1.2247; the arithmetic ones, 0.875 and 1.25, differ.
	var index_for: Dictionary[float, int] = {0.65: 0, 0.85: 0, 0.87: 1, 1.22: 1, 1.24: 2, 1.7: 2}
	for z: float in index_for:
		_camera.zoom = Vector2(z, z)
		assert_int(_camera.zoom_level_index()).is_equal(index_for[z])
		_camera.end_gesture()
		_zoom_is(LEVELS[index_for[z]], str(z))


func test_step_zoom_walks_the_levels_and_stops_at_the_ends() -> void:
	var world: Vector2 = _camera.screen_to_world(POINT)
	var directions: Array[int] = [1, 1, -1, -1, -1]
	var zooms: Array[float] = [1.5, 1.5, 1.0, 0.75, 0.75]
	for i: int in directions.size():
		_camera.step_zoom(directions[i], POINT)
		_zoom_is(zooms[i], str(i))
		_near(_camera.screen_to_world(POINT), world, str(i), 0.5)


func test_snap_is_zoom_snap_ms_long_about_the_pinch_point_and_a_new_pinch_cancels_it() -> void:
	_settings.zoom_snap_ms = 150
	_camera.pinch(POINT, 1.3)
	var world: Vector2 = _camera.screen_to_world(POINT)
	_camera.end_gesture()
	_camera._snap.pause()  # The tween is stepped by hand: exact, no wall-clock waits.
	_camera._snap.custom_step(0.075)  # Half of 150 ms, linear in zoom.
	_zoom_is(1.4)
	_near(_camera.screen_to_world(POINT), world, "half way", 0.5)
	_camera._snap.custom_step(0.075)
	_zoom_is(1.5)
	_camera.pinch(POINT, 0.8)
	_camera.end_gesture()
	_camera.pinch(POINT, 1.0)  # A pinch during the snap cancels it.
	_camera._snap.custom_step(1.0)  # A live tween would finish and move the zoom to 1.0.
	_zoom_is(1.2)


func test_screen_and_world_round_trip_and_match_the_engine_canvas_transform() -> void:
	get_window().size = PHONE_SIZE
	await await_idle_frame()
	for level: float in LEVELS:
		_camera.zoom = Vector2(level, level)
		_camera.centre_on(Vector2(1400, 1700))
		await await_idle_frame()
		for p: Vector2 in [Vector2.ZERO, Vector2(1600, 720), Vector2(333, 555)]:
			var world: Vector2 = _camera.screen_to_world(p)
			_near(_camera.world_to_screen(world), p, str(level))
			_near(_camera.get_canvas_transform().affine_inverse() * p, world, "engine")


func _add_camera() -> RtsCamera:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	camera.settings = _settings
	add_child(camera)
	camera.set_map_rect(MAP)
	camera.centre_on(MAP.get_center())
	return camera


func _near(actual: Vector2, expected: Vector2, note: String = "", tol: float = 0.01) -> void:
	var approx: Vector2 = Vector2(tol, tol)
	assert_vector(actual).append_failure_message(note).is_equal_approx(expected, approx)


## The zoom is `expected` on both axes.
func _zoom_is(expected: float, note: String = "") -> void:
	_near(_camera.zoom, Vector2(expected, expected), note, 0.0001)
