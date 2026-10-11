extends GdUnitTestSuite
## The touch probe (ADR 0004 section 3): the numbers it shows, a square that is exactly dp(48) base
## px per side and stays so after a resize, live touch points and Back. The real 7.6 mm is for
## Michael's ruler. This proves the square is dp(48) and not some other size.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ANDROID: StringName = &"android_6in"
const ANDROID_TEXT: String = (
	"OS: Android\ndpi: 420\nscreen scale: 1.000\nstretch scale: 1.500\nwindow: 2400 x 1080 px\n"
	+ "base px per dp: 1.750\ndp(48): 84.0 base px"
)

var _window_size_before: Vector2i


func before() -> void:
	assert_bool(UiScale.has_override()).override_failure_message("override leaked").is_false()
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_it_shows_the_numbers_of_the_profile() -> void:
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))
	assert_str((_control(probe, "MetricsLabel") as Label).text).is_equal(ANDROID_TEXT)
	assert_str((_control(probe, "SquareLabel") as Label).text).is_equal("should measure 7.6 mm")


## Covers 1280x720 (desktop), 2400x1080 (android_6in) and 2048x1536 (web_tablet), and the phone
## browsers. The square is dp(48) on each side. The column and the Back button stay on screen.
func test_every_profile_has_an_exact_square_and_a_layout_that_fits() -> void:
	for profile_name: StringName in UiProfiles.all():
		var probe: Control = await _open(UiProfiles.by_name(profile_name))
		var column: Rect2 = _control(probe, "Column").get_global_rect()
		var back: Rect2 = _control(probe, "BackButton").get_global_rect()
		var label: String = str(profile_name)
		var fits: bool = Rect2(Vector2.ZERO, probe.size).encloses(column.merge(back))
		assert_bool(fits and not column.intersects(back)).override_failure_message(label).is_true()
		(
			assert_vector(_control(probe, "Square").size)
			. override_failure_message(label)
			. is_equal_approx(UiScale.dp_vec(48.0, 48.0), Vector2.ONE * 0.001)
		)


func test_the_square_and_the_numbers_follow_a_window_resize() -> void:
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))
	var square: Control = _control(probe, "Square")
	assert_that(square.size).is_equal_approx(Vector2(84.0, 84.0), Vector2(0.05, 0.05))
	var tablet: UiMetrics = UiProfiles.by_name(&"web_tablet")
	UiScale.set_override(tablet)
	get_window().size = tablet.window_size
	await await_idle_frame()
	assert_that(square.size).is_equal_approx(Vector2(60.0, 60.0), Vector2(0.05, 0.05))
	assert_str((_control(probe, "MetricsLabel") as Label).text).contains("dp(48): 60.0 base px")
	# Without an override it follows what the engine reports, as on a phone. The stretch scale
	# goes from 1.0 to 1.5 here, so the same dp is fewer base px.
	UiScale.clear_override()
	get_window().size = Vector2i(1280, 720)
	await await_idle_frame()
	var at_base_size: float = square.size.x
	assert_float(at_base_size).is_equal_approx(UiScale.dp(48.0), 0.001)
	get_window().size = Vector2i(2400, 1080)
	await await_idle_frame()
	assert_float(square.size.x).is_equal_approx(UiScale.dp(48.0), 0.001)
	assert_float(square.size.x * 1.5).is_equal_approx(at_base_size, 0.001)


func test_touch_points_follow_the_fingers_in_base_px() -> void:
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))  # Stretch 1.5.
	_touch(0, Vector2(1200, 540), true)
	_touch(1, Vector2(600, 300), true)
	assert_dict(probe.touches).is_equal({0: Vector2(800, 360), 1: Vector2(400, 200)})
	_drag(0, Vector2(1500, 600))
	assert_dict(probe.touches).is_equal({0: Vector2(1000, 400), 1: Vector2(400, 200)})
	_touch(1, Vector2(600, 300), false)
	assert_dict(probe.touches).is_equal({0: Vector2(1000, 400)})
	_touch(0, Vector2(1500, 600), false)
	assert_dict(probe.touches).is_empty()


func test_back_button_and_the_android_back_request_both_leave() -> void:
	var quit_before: bool = get_tree().quit_on_go_back
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))
	var calls: Array[int] = []
	probe.back_action = func() -> void: calls.append(1)
	(_control(probe, "BackButton") as Button).pressed.emit()
	assert_array(calls).has_size(1)
	assert_bool(get_tree().quit_on_go_back).is_false()
	probe.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_array(calls).has_size(1)  # Deferred: never inside the notification.
	await await_idle_frame()
	assert_array(calls).has_size(2)
	remove_child(probe)
	assert_bool(get_tree().quit_on_go_back).is_equal(quit_before)


func _open(profile: UiMetrics) -> Control:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	var probe: Control = auto_free((load(DevRoutes.TOUCH_PROBE_SCENE) as PackedScene).instantiate())
	add_child(probe)
	await await_idle_frame()
	return probe


func _control(probe: Control, node_name: String) -> Control:
	return probe.find_child(node_name, true, false) as Control


## Events enter at the window, in window px, as the engine delivers them.
func _touch(index: int, window_px: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = window_px
	event.pressed = pressed
	get_window().push_input(event)


func _drag(index: int, window_px: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = window_px
	get_window().push_input(event)
