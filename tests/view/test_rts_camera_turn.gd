extends GdUnitTestSuite
## RtsCamera when the phone turns (ADR 0015 section 4, plan P62): the world point at the centre
## stays, the zoom keeps the world size per dp, the snap stops, and a resize inside one orientation
## only clamps and refreshes what the next turn compares with. The 6-inch phone (2400x1080 and
## 1080x2400, stretch 1.5 both ways) is the plain turn, the engine's own metrics are used where
## they decide (the rounding at 2556x1179), and a profile override stands in for a phone browser
## whose toolbar takes a different share of the screen in each orientation.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MAP: Rect2 = Rect2(0, 0, 3072, 3072)
const LEVELS: Array[float] = [0.75, 1.0, 1.5]
const PHONE: Vector2i = ScreenSizes.LANDSCAPE[1]
const PHONE_TURNED: Vector2i = ScreenSizes.PORTRAIT[1]
## A phone the engine rounds: 2556x1179 shows 1560 whole base px across, its transpose 720, and the
## stretch differs by 0.06 % (ADR 0015 section 2).
const ROUNDED: Vector2i = Vector2i(2556, 1179)
const ROUNDED_TURNED: Vector2i = Vector2i(1179, 2556)
const POINT: Vector2 = Vector2(1700, 100)  ## Off the landscape centre, outside the portrait view.
const SAME_WORLD_SIZE: float = 0.001  ## ADR 0015 section 4: within 0.1 %.

var _window_size_before: Vector2i
var _settings: InputSettings
var _camera: RtsCamera


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_settings = (load("res://data/input_settings.tres") as InputSettings).duplicate()
	_settings.zoom_snap_ms = 0
	await _show_size(PHONE)


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_a_turn_keeps_every_zoom_level_exactly_and_the_centre_where_the_clamp_allows() -> void:
	_camera = _add_camera()
	for level: float in LEVELS:
		await _show_size(PHONE)
		_camera.zoom = Vector2(level, level)
		_camera.centre_on(MAP.get_center())
		await _show_size(PHONE_TURNED)
		assert_that(_camera.zoom).is_equal(Vector2(level, level))
		assert_that(_camera.position).is_equal(MAP.get_center())
		await _show_size(PHONE)
		assert_that(_camera.zoom).is_equal(Vector2(level, level))
		assert_that(_camera.position).is_equal(MAP.get_center())


## At zoom 1 the landscape view shows 1600x720 world px and the portrait one 720x1600, so a centre
## on the landscape limits (800..2272, 360..2712) moves on y only, to the portrait ones
## (360..2712, 800..2272).
func test_a_centre_near_a_map_edge_moves_only_as_far_as_the_new_clamp_needs() -> void:
	_camera = _add_camera()
	var limits: Array[int] = _limits()
	_camera.centre_on(Vector2(800, 360))
	await _show_size(PHONE_TURNED)
	assert_that(_camera.position).is_equal(Vector2(800, 800))
	await _show_size(PHONE)  # Back: no memory of (800, 360), the landscape limits take (800, 800).
	assert_that(_camera.position).is_equal(Vector2(800, 800))
	_camera.centre_on(Vector2(2272, 2712))
	await _show_size(PHONE_TURNED)
	assert_that(_camera.position).is_equal(Vector2(2272, 2272))
	await _show_size(PHONE)
	assert_that(_camera.position).is_equal(Vector2(2272, 2272))
	assert_array(_limits()).is_equal(limits)


## The engine floors the expanded axis to whole base px, so a window and its transpose differ in
## stretch by up to 0.1 %. That is rounding, not a different screen: the zoom stays on its level.
func test_a_turn_the_engine_rounds_keeps_a_zoom_on_its_level() -> void:
	await _show_size(ROUNDED)
	_camera = _add_camera()
	var landscape: float = UiScale.base_px_per_dp()
	await _show_size(ROUNDED_TURNED)
	var ratio: float = UiScale.base_px_per_dp() / landscape
	assert_float(absf(ratio - 1.0)).is_greater(0.0003).is_less(SAME_WORLD_SIZE)  # Not vacuous.
	for level: float in LEVELS:
		_camera.zoom = Vector2(level, level)
		await _show_size(ROUNDED)
		assert_that(_camera.zoom).is_equal(Vector2(level, level))
		await _show_size(ROUNDED_TURNED)
		assert_that(_camera.zoom).is_equal(Vector2(level, level))


## The web phone: a toolbar takes height in landscape (2400x932, stretch 1.2945, 2.03 base px per
## dp) and less in portrait (1.5, 1.75), so a turn rescales the zoom by 1.75 / 2.03 = 0.863 and the
## world px per dp stay.
func test_a_turn_between_other_stretches_keeps_the_world_px_per_dp() -> void:
	for level: float in LEVELS:
		await _use_phone(&"web_phone")
		_camera = _add_camera()
		_camera.zoom = Vector2(level, level)
		var before: float = _world_px_per_dp()
		await _use_phone(&"web_phone_portrait")
		assert_float(_camera.zoom.x).is_equal_approx(level * 0.863, 0.0005)
		assert_float(_world_px_per_dp()).is_equal_approx(before, before * SAME_WORLD_SIZE)
		await _use_phone(&"web_phone")
		assert_float(_camera.zoom.x).is_equal_approx(level, 0.0001)
		assert_float(_world_px_per_dp()).is_equal_approx(before, before * SAME_WORLD_SIZE)
		_camera.free()


func test_the_rescaled_zoom_stays_within_the_pinch_bounds() -> void:
	await _use_phone(&"web_phone_portrait")
	_camera = _add_camera()
	_camera.zoom = Vector2(1.5, 1.5)
	await _use_phone(&"web_phone")  # 1.5 / 0.863 is 1.738, over the highest bound.
	_near(_camera.zoom, Vector2(1.725, 1.725), 0.0001)
	_camera.zoom = Vector2(0.6375, 0.6375)  # The lowest bound.
	await _use_phone(&"web_phone_portrait")  # 0.55 is under it.
	_near(_camera.zoom, Vector2(0.6375, 0.6375), 0.0001)


## 2400x932 to 2400x1080 is a resize in one orientation: the zoom stays, so the world px per dp
## change (2.03 to 1.75). The turn after it must keep the new value, which means comparing with the
## base px per dp of the resize and not with the ones from before it.
func test_a_resize_inside_landscape_then_a_turn_keeps_the_world_px_per_dp_of_the_resize() -> void:
	await _use_phone(&"web_phone")
	_camera = _add_camera()
	var toolbar_hidden: UiMetrics = _web_phone_like(&"android_6in")  # 2400x1080, stretch 1.5.
	await _show(toolbar_hidden)
	assert_that(_camera.zoom).is_equal(Vector2.ONE)
	var resized: float = _world_px_per_dp()
	assert_float(resized).is_equal_approx(1.75, 0.0001)  # It was 2.028 before the resize.
	await _show(_web_phone_like(&"android_6in_portrait"))
	assert_that(_camera.zoom).is_equal(Vector2.ONE)
	assert_float(_world_px_per_dp()).is_equal_approx(resized, resized * SAME_WORLD_SIZE)


## The tween is stepped by hand (no wall-clock waits): paused half way, it is dead after the turn.
func test_a_snap_in_flight_at_the_turn_is_stopped_and_not_resumed() -> void:
	_settings.zoom_snap_ms = 150
	_camera = _add_camera()
	_camera.pinch(Vector2(800, 400), 1.3)
	_camera.end_gesture()
	_camera._snap.pause()
	_camera._snap.custom_step(0.05)  # A third of the way from 1.3 to 1.5.
	var half_way: float = _camera.zoom.x
	assert_float(half_way).is_between(1.3, 1.5)
	await _show_size(PHONE_TURNED)
	assert_bool(_camera._snap.is_valid()).is_false()  # Killed, not paused.
	assert_int(_camera._snap_level).is_equal(-1)
	assert_that(_camera.zoom).is_equal(Vector2(half_way, half_way))


## The zoom is between levels, the pinch point (1700, 100) is outside the 720 px wide portrait
## view, and the web phone's turn rescales the zoom by 0.863. The centre point stays, no snap
## starts, and the lift after the turn (the end of the next gesture) snaps about the new view
## centre, so the centre point stays then too. A stale anchor would move it by about 46 world px.
func test_a_turn_during_a_pinch_keeps_the_centre_and_snaps_later_about_the_new_centre() -> void:
	await _use_phone(&"web_phone")
	_camera = _add_camera()
	_settings.zoom_snap_ms = 150
	_camera.pinch(POINT, 1.2)
	var centre: Vector2 = _camera.position
	await _use_phone(&"web_phone_portrait")
	assert_float(_camera.zoom.x).is_equal_approx(1.2 * 0.863, 0.0005)
	assert_that(_camera.position).is_equal(centre)
	assert_bool(_camera._snap == null or not _camera._snap.is_valid()).is_true()  # None started.
	_settings.zoom_snap_ms = 0
	_camera.end_gesture()
	_near(_camera.zoom, Vector2.ONE)
	_near(_camera.position, centre)


func test_a_turn_during_a_pan_keeps_the_centre_and_the_next_pan_end_snaps_about_the_new_one(
) -> void:
	await _use_phone(&"web_phone")
	_camera = _add_camera()
	_settings.zoom_snap_ms = 0
	_camera.step_zoom(1, POINT)  # Zoom 1.5 about POINT: the anchor is off the centre.
	_settings.zoom_snap_ms = 150
	_camera.pan_by_screen(Vector2(40, -30))  # A pan, then the turn in the middle of it.
	var centre: Vector2 = _camera.position
	await _use_phone(&"web_phone_portrait")
	assert_float(_camera.zoom.x).is_equal_approx(1.5 * 0.863, 0.0005)
	assert_that(_camera.position).is_equal(centre)
	assert_bool(_camera._snap == null or not _camera._snap.is_valid()).is_true()
	_settings.zoom_snap_ms = 0
	_camera.end_gesture()  # 1.295 is nearest the level 1.5 by ratio.
	_near(_camera.zoom, Vector2(1.5, 1.5))
	_near(_camera.position, centre)


## The turn is limited to `UiScale`'s function: a window that stays taller than wide is no turn.
func test_a_resize_inside_portrait_does_not_rescale_the_zoom() -> void:
	await _show_size(PHONE_TURNED)
	_camera = _add_camera()
	_camera.zoom = Vector2(1.2, 1.2)
	await _show_size(ScreenSizes.PORTRAIT[2])  # Stretch 1.5 to 1.6: the world px per dp change.
	assert_that(_camera.zoom).is_equal(Vector2(1.2, 1.2))


func _add_camera() -> RtsCamera:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	camera.settings = _settings
	add_child(camera)
	camera.set_map_rect(MAP)
	camera.centre_on(MAP.get_center())
	return camera


## The engine's metrics at `size`: no override.
func _show_size(size: Vector2i) -> void:
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()


## The web phone in the window of `profile` (`web_phone` or `web_phone_portrait`).
func _use_phone(profile: StringName) -> void:
	await _show(_web_phone_like(profile))


## The web phone's screen (2.625 window px per dp) in the window and stretch of `profile`: the same
## phone, whatever the toolbar takes.
func _web_phone_like(profile: StringName) -> UiMetrics:
	var window: UiMetrics = UiProfiles.by_name(profile)
	var phone: UiMetrics = UiProfiles.by_name(&"web_phone")
	return UiMetrics.create(
		phone.os_name,
		phone.dpi,
		phone.screen_scale,
		window.stretch_scale,
		window.window_size,
		Rect2i()
	)


func _show(metrics: UiMetrics) -> void:
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()


## World px one dp covers: base px per dp over the zoom.
func _world_px_per_dp() -> float:
	return UiScale.base_px_per_dp() / _camera.zoom.x


func _limits() -> Array[int]:
	return [_camera.limit_left, _camera.limit_top, _camera.limit_right, _camera.limit_bottom]


func _near(actual: Vector2, expected: Vector2, tol: float = 0.01) -> void:
	assert_vector(actual).is_equal_approx(expected, Vector2(tol, tol))
