extends GdUnitTestSuite
## RtsCamera on the 48x48 tile map, a diamond 3072 px wide (P117, ADR 0023 section 4): the centre
## clamp into the diamond at the target screens, pan, pinch, the zoom levels, screen/world maths.
## Snaps are immediate unless a test sets `zoom_snap_ms`. The acceptance cases of the clamp (the
## ground point of the centre at every size, zoom and turn) are in test_rts_camera_diamond.gd.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAP_TILES: int = 48
const MAP_CENTRE: Vector2 = Vector2(0, 768)  ## The middle of the diamond.
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
const PHONE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[1]
## The diamond's tips: north, east, south and west, in world px.
const TIPS: Array[Vector2] = [
	Vector2(0, 0), Vector2(1536, 768), Vector2(0, 1536), Vector2(-1536, 768)
]
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


func test_set_map_rect_clamps_the_centre_into_the_diamond_and_leaves_the_engine_limits_off(
) -> void:
	assert_bool(_camera.limit_enabled).is_false()
	_camera.centre_on(Vector2(OVERSCROLL, OVERSCROLL))
	assert_that(_camera.position).is_equal(TIPS[2])  # Far down and right: the south tip.
	# A smaller map re-clamps the centre at once: 6 x 2 tiles have their south tip at (128, 128).
	_camera.set_map_rect(IsoProjection.map_diamond(6, 2))
	var ground: Vector2i = IsoProjection.px_to_ground(_camera.position)
	assert_int(ground.x).is_between(0, 6000)
	assert_int(ground.y).is_between(0, 2000)
	assert_that(_camera.position).is_equal_approx(Vector2(128, 128), Vector2(0.01, 0.01))
	# No map (an empty diamond) means no clamp, and a camera outside a tree is no error.
	_camera.set_map_rect(PackedVector2Array())
	_camera.centre_on(Vector2(OVERSCROLL, OVERSCROLL))
	assert_that(_camera.position).is_equal(Vector2(OVERSCROLL, OVERSCROLL))
	var detached: RtsCamera = auto_free(RtsCamera.new())
	detached.set_map_rect(IsoProjection.map_diamond(MAP_TILES, MAP_TILES))
	detached.centre_on(Vector2(OVERSCROLL, 0))
	assert_that(detached.position).is_equal(TIPS[1])


func test_a_pan_stops_exactly_at_each_tip_with_no_dead_zone_at_every_target_size() -> void:
	# Pan deltas that push the centre past a tip: the world follows the fingers, so the camera moves
	# by minus the delta. The east and west tips lie on the centre line, the north and south ones on
	# the centre column. `inward` is the way the camera moves back into the map from each tip.
	var pushes: Array[Vector2] = [
		Vector2(0, OVERSCROLL),
		Vector2(-OVERSCROLL, 0),
		Vector2(0, -OVERSCROLL),
		Vector2(OVERSCROLL, 0),
	]
	var inward: Array[Vector2] = [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		for tip: int in 4:
			_camera.zoom = Vector2.ONE  # A turn rescales the zoom (ADR 0015 section 4).
			_camera.centre_on(MAP_CENTRE)
			_camera.pan_by_screen(pushes[tip])
			_near(_camera.position, TIPS[tip], str(size))
			# Back by 100 px: an overscrolled position would leave the view where it was.
			_camera.pan_by_screen(-inward[tip] * 100.0)
			_near(_camera.position, TIPS[tip] + inward[tip] * 100.0, str(size))
		await await_idle_frame()
		_near(_camera.get_screen_center_position(), _camera.position)  # No engine limit shifts it.


func test_zoomed_out_on_a_20_9_phone_the_view_overhangs_the_tip_and_the_engine_agrees() -> void:
	get_window().size = PHONE_SIZE
	await await_idle_frame()
	_camera.zoom = Vector2(0.75, 0.75)
	_near(_camera.visible_world_rect().size, Vector2(2133.3333, 960))
	_camera.pan_by_screen(Vector2(OVERSCROLL, 0))
	_near(_camera.position, TIPS[3])
	# Half the view lies past the west tip (the clear colour), and the engine draws exactly that.
	assert_float(_camera.visible_world_rect().position.x).is_less(TIPS[3].x - 1000.0)
	await await_idle_frame()
	_near(_camera.get_screen_center_position(), _camera.position)
	var middle: Vector2 = get_viewport().get_visible_rect().size * 0.5
	_near(_camera.get_canvas_transform().affine_inverse() * middle, _camera.position)


func test_pan_moves_by_minus_delta_over_zoom() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.pan_by_screen(Vector2(60, -30))
	_near(_camera.position, MAP_CENTRE + Vector2(-40, 20))


func test_zooming_out_about_a_point_at_a_tip_keeps_the_centre_on_the_map() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.pan_by_screen(Vector2(OVERSCROLL, 0))  # The west tip.
	_near(_camera.position, TIPS[3])
	_camera.pinch(Vector2(640, 360), 0.5)  # Zoom 0.75 about the view centre: the centre stays.
	_near(_camera.position, TIPS[3])
	_camera.pinch(Vector2(1000, 360), 0.9)  # About a point east of it: the zoom would move it west.
	_near(_camera.position, TIPS[3])
	assert_float(_camera.zoom.x).is_less(0.75)


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
		_camera.centre_on(Vector2(300, 900))
		await await_idle_frame()
		for p: Vector2 in [Vector2.ZERO, Vector2(1600, 720), Vector2(333, 555)]:
			var world: Vector2 = _camera.screen_to_world(p)
			_near(_camera.world_to_screen(world), p, str(level))
			_near(_camera.get_canvas_transform().affine_inverse() * p, world, "engine")


func _add_camera() -> RtsCamera:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	camera.settings = _settings
	add_child(camera)
	camera.set_map_rect(IsoProjection.map_diamond(MAP_TILES, MAP_TILES))
	camera.centre_on(MAP_CENTRE)
	return camera


func _near(actual: Vector2, expected: Vector2, note: String = "", tol: float = 0.01) -> void:
	var approx: Vector2 = Vector2(tol, tol)
	assert_vector(actual).append_failure_message(note).is_equal_approx(expected, approx)


## The zoom is `expected` on both axes.
func _zoom_is(expected: float, note: String = "") -> void:
	_near(_camera.zoom, Vector2(expected, expected), note, 0.0001)
