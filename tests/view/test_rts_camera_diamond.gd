extends GdUnitTestSuite
## The camera's clamp into the map's diamond (P117, ADR 0023 section 4), as acceptance cases: the
## ground point of the view centre stays inside the map at every zoom level, at the six target
## sizes in both orientations, on a square and on a wide map, and a turn keeps it. The basic
## clamp, pan and pinch cases are in test_rts_camera.gd.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAPS: Array[Vector2i] = [Vector2i(48, 48), Vector2i(64, 20)]  ## Columns and rows.
const LEVELS: Array[float] = [0.75, 1.0, 1.5]
const OVERSCROLL: float = 20000.0
## Eight pushes of a pan, in screen directions: the camera moves by minus the delta.
const PUSHES: Array[Vector2] = [
	Vector2(1, 0),
	Vector2(1, 1),
	Vector2(0, 1),
	Vector2(-1, 1),
	Vector2(-1, 0),
	Vector2(-1, -1),
	Vector2(0, -1),
	Vector2(1, -1),
]

var _window_size_before: Vector2i
var _settings: InputSettings
var _camera: RtsCamera


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_settings = (load("res://data/input_settings.tres") as InputSettings).duplicate()
	_settings.zoom_snap_ms = 0


func test_the_centre_stays_inside_the_map_at_every_size_zoom_level_and_push() -> void:
	for map: Vector2i in MAPS:
		_camera = _add_camera(map)
		for size: Vector2i in ScreenSizes.ALL:
			get_window().size = size
			await await_idle_frame()
			for level: float in LEVELS:
				for push: Vector2 in PUSHES:
					_camera.zoom = Vector2(level, level)
					_camera.centre_on(_middle(map))
					_camera.pan_by_screen(push * OVERSCROLL)
					_assert_inside(map, "%s %s %s %s" % [map, size, level, push])
					_camera.pan_by_screen(push * OVERSCROLL * 0.3)  # More of the same: stays.
					_assert_inside(map, "again %s %s %s %s" % [map, size, level, push])
		_camera.free()


func test_every_zoom_step_and_pinch_about_any_point_keeps_the_centre_inside() -> void:
	for map: Vector2i in MAPS:
		_camera = _add_camera(map)
		for size: Vector2i in [ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1]]:
			get_window().size = size
			await await_idle_frame()
			var view: Vector2 = get_viewport().get_visible_rect().size
			for point: Vector2 in [Vector2.ZERO, view, Vector2(view.x, 0), view * 0.5]:
				for push: Vector2 in PUSHES:
					_camera.centre_on(_middle(map))
					_camera.pan_by_screen(push * OVERSCROLL)  # At or past a tip.
					for direction: int in [1, 1, -1, -1, -1]:
						_camera.step_zoom(direction, point)
						_assert_inside(map, "step %s %s %s" % [map, size, point])
					_camera.pinch(point, 0.5)
					_assert_inside(map, "pinch in %s %s %s" % [map, size, point])
					_camera.pinch(point, 3.0)
					_assert_inside(map, "pinch out %s %s %s" % [map, size, point])
					_camera.end_gesture()
					_assert_inside(map, "snap %s %s %s" % [map, size, point])
		_camera.free()


func test_a_turn_keeps_the_ground_point_of_the_centre_at_every_zoom_level() -> void:
	for map: Vector2i in MAPS:
		_camera = _add_camera(map)
		var diamond: PackedVector2Array = IsoProjection.map_diamond(map.x, map.y)
		var places: Array[Vector2] = [
			_middle(map),
			diamond[0],
			diamond[1],
			diamond[2],
			diamond[3],
			diamond[0].lerp(diamond[1], 0.5),
		]
		for index: int in 3:  # The phone and the other two screens, each turned and back.
			var landscape: Vector2i = ScreenSizes.LANDSCAPE[index]
			var portrait: Vector2i = ScreenSizes.PORTRAIT[index]
			for level: float in LEVELS:
				for place: Vector2 in places:
					get_window().size = landscape
					await await_idle_frame()
					_camera.zoom = Vector2(level, level)
					_camera.centre_on(place)
					var before: Vector2i = _ground()
					get_window().size = portrait
					await await_idle_frame()
					assert_that(_ground()).override_failure_message("turned %s" % place).is_equal(
						before
					)
					_assert_inside(map, "portrait %s" % place)
					get_window().size = landscape
					await await_idle_frame()
					assert_that(_ground()).override_failure_message("back %s" % place).is_equal(
						before
					)
		_camera.free()


## The reason the engine's limits are off: at a tip the view overhangs the map by half its size, and
## the world point under the centre of the screen is still the camera's `position`.
func test_at_every_tip_the_engines_view_centre_is_the_camera_position() -> void:
	_camera = _add_camera(MAPS[0])
	var diamond: PackedVector2Array = IsoProjection.map_diamond(MAPS[0].x, MAPS[0].y)
	for size: Vector2i in [ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1]]:
		get_window().size = size
		await await_idle_frame()
		for level: float in LEVELS:
			_camera.zoom = Vector2(level, level)
			for corner: Vector2 in diamond:
				_camera.centre_on(corner)
				await await_idle_frame()
				var middle: Vector2 = get_viewport().get_visible_rect().size * 0.5
				assert_that(_camera.screen_to_world(middle)).is_equal_approx(
					_camera.position, Vector2(0.01, 0.01)
				)
				assert_that(_camera.get_screen_center_position()).is_equal_approx(
					_camera.position, Vector2(0.01, 0.01)
				)
				(
					assert_that(_camera.get_canvas_transform().affine_inverse() * middle)
					. is_equal_approx(_camera.position, Vector2(0.01, 0.01))
				)


func test_a_screen_point_taps_the_same_ground_the_engine_draws_there() -> void:
	_camera = _add_camera(MAPS[0])
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	_camera.centre_on(IsoProjection.map_diamond(MAPS[0].x, MAPS[0].y)[3])  # Pushed to the west tip.
	await await_idle_frame()
	for point: Vector2 in [Vector2(200, 300), Vector2(1000, 540), Vector2(1500, 900)]:
		var world: Vector2 = _camera.screen_to_world(point)
		var drawn: Vector2 = _camera.get_canvas_transform().affine_inverse() * point
		assert_that(world).is_equal_approx(drawn, Vector2(0.01, 0.01))
		# The ground tap's milli point is the inverse of what stands at that world point.
		var ground: Vector2i = IsoProjection.px_to_ground(world)
		assert_that(IsoProjection.ground_to_px(ground.x, ground.y)).is_equal_approx(
			world, Vector2(0.05, 0.05)
		)


func _add_camera(map: Vector2i) -> RtsCamera:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	camera.settings = _settings
	add_child(camera)
	camera.set_map_rect(IsoProjection.map_diamond(map.x, map.y))
	camera.centre_on(_middle(map))
	return camera


## The middle of the map's diamond, world px.
func _middle(map: Vector2i) -> Vector2:
	return IsoProjection.ground_to_px(map.x * 500, map.y * 500)


func _ground() -> Vector2i:
	return IsoProjection.px_to_ground(_camera.position)


func _assert_inside(map: Vector2i, note: String) -> void:
	var ground: Vector2i = _ground()
	assert_int(ground.x).override_failure_message("x " + note).is_between(0, map.x * 1000)
	assert_int(ground.y).override_failure_message("y " + note).is_between(0, map.y * 1000)
