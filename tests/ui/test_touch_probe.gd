extends GdUnitTestSuite
## The touch probe (ADR 0004 section 3): the numbers it shows, with the window's orientation and the
## base size it is stretched from (ADR 0015, plan P63), a square that is exactly dp(48) base px per
## side and stays so after a resize or a turn, live touch points and Back, in both orientations.
## The real 7.6 mm is for Michael's ruler. This proves the square is dp(48) and not some other size.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const ANDROID: StringName = &"android_6in"
const SAFE_AREA: Rect2i = Rect2i(60, 0, 2280, 1080)  ## A landscape cutout on the left.
const ANDROID_TEXT: String = (
	"OS: Android\ndpi: 420\nscreen scale: 1.000\nstretch scale: 1.500\nwindow: 2400 x 1080 px\n"
	+ "base 1280 x 720 (landscape)\nsafe area: 60,0 2280x1080 px\n"
	+ "base px per dp: 1.750\ndp(48): 84.0 base px"
)
## The ADR's phone held upright, with a cutout at the top and the gesture bar at the bottom.
const PORTRAIT_CUTOUT: Rect2i = Rect2i(0, 100, 1080, 2237)

var _window_size_before: Vector2i
var _now_ms: int = 0


func before() -> void:
	assert_bool(UiScale.has_override()).override_failure_message("override leaked").is_false()
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The engine default is true. A probe that is gone restores it, or a false leaks into later suites.
func before_test() -> void:
	var restored: bool = get_tree().quit_on_go_back
	assert_bool(restored).override_failure_message("quit_on_go_back leaked").is_true()


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_it_shows_the_numbers_of_the_profile() -> void:
	var metrics: UiMetrics = UiProfiles.with_safe_area(UiProfiles.by_name(ANDROID), SAFE_AREA)
	var probe: Control = await _open(metrics)
	assert_str((_control(probe, "MetricsLabel") as Label).text).is_equal(ANDROID_TEXT)
	assert_str((_control(probe, "SquareLabel") as Label).text).is_equal("should measure 7.6 mm")
	# The 60 px cutout is 40 base px, plus dp(12) = 21: the text no longer sits under it.
	assert_float(_control(probe, "Column").get_global_rect().position.x).is_equal(61.0)


## Covers the six sizes of ADR 0015 section 6 through the profiles that have them (desktop 1280x720
## and 720x1280, android_6in 2400x1080 and 1080x2400, web_tablet 2048x1536 and 1536x2048) and the
## phone browsers in both orientations, then the 6-inch phone with a cutout in each orientation.
## The square is dp(48) on each side. The column, the square, the gesture log and the Back button
## (at least dp(48) each way) lie inside the safe area and apart.
func test_every_profile_has_an_exact_square_and_a_layout_that_fits() -> void:
	var cases: Dictionary[String, UiMetrics] = {}
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			cases[str(profile_name)] = profiles[profile_name]
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	cases["cutout left"] = UiProfiles.with_safe_area(phone, SAFE_AREA)
	cases["cutout top"] = UiProfiles.with_safe_area(
		UiProfiles.by_name(&"android_6in_portrait"), PORTRAIT_CUTOUT
	)
	for label: String in cases:
		var probe: Control = await _open(cases[label])
		var square: Control = _control(probe, "Square")
		var column: Rect2 = _control(probe, "Column").get_global_rect()
		var back: Rect2 = _control(probe, "BackButton").get_global_rect()
		_touch(0, Vector2(100, 100), true)  # A pinch line is about the widest the log gets.
		_touch(1, Vector2(300, 100), true)
		_drag(1, Vector2(500, 100))
		await await_idle_frame()
		var log_rect: Rect2 = _control(probe, "GestureLog").get_global_rect()
		var safe: Rect2 = UiScale.safe_rect_base()
		var fits: bool = safe.encloses(column.merge(back).merge(log_rect))
		fits = fits and column.encloses(square.get_global_rect()) and square.is_visible_in_tree()
		var apart: bool = not (column.intersects(back) or log_rect.intersects(back))
		apart = apart and not column.intersects(log_rect)
		var where: String = (
			"%s: column %s back %s log %s safe %s" % [label, column, back, log_rect, safe]
		)
		assert_bool(fits and apart).override_failure_message(where).is_true()
		var touch_px: float = UiScale.dp(48.0) - 0.5
		(
			assert_bool(back.size.x >= touch_px and back.size.y >= touch_px)
			. override_failure_message(label + " Back is " + str(back.size))
			. is_true()
		)
		assert_vector(square.size).override_failure_message(label).is_equal_approx(
			UiScale.dp_vec(48.0, 48.0), Vector2.ONE * 0.001
		)
		probe.free()  # One at a time: probes alive together restore quit_on_go_back in a bad order.
		UiScale.clear_override()


## The readout names the window and, next to it, the base size and the orientation, one pair per
## size of the list: the first three are landscape on the project's base size, the last three
## portrait on its transpose.
func test_the_readout_names_the_orientation_and_the_base_size_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		var portrait: bool = ScreenSizes.PORTRAIT.has(size)
		var probe: Control = await _open(_profile_with_window(size))
		var text: String = (_control(probe, "MetricsLabel") as Label).text
		var base: String = (
			"base 720 x 1280 (portrait)" if portrait else "base 1280 x 720 (landscape)"
		)
		var window: String = "window: %d x %d px\n%s\n" % [size.x, size.y, base]
		assert_str(text).override_failure_message(str(size)).contains(window)
		probe.free()
		UiScale.clear_override()


## The readout follows the window through a turn, on the engine's own metrics (no override): the
## autoload turns the base size, and the probe shows what the engine uses now.
func test_the_readout_follows_a_turn_of_the_window() -> void:
	var probe: Control = await _open(UiProfiles.by_name(&"android_6in"))
	UiScale.clear_override()
	var metrics: Label = _control(probe, "MetricsLabel") as Label
	for step: Array in [
		[ScreenSizes.PORTRAIT[1], "base 720 x 1280 (portrait)"],
		[ScreenSizes.LANDSCAPE[1], "base 1280 x 720 (landscape)"],
	]:
		var size: Vector2i = step[0]
		get_window().size = size
		await await_idle_frame()
		var expected: String = "window: %d x %d px\n%s\n" % [size.x, size.y, step[1]]
		assert_str(metrics.text).override_failure_message(str(size)).contains(expected)
	probe.free()


func test_the_square_and_the_numbers_follow_a_window_resize() -> void:
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))
	var square: Control = _control(probe, "Square")
	assert_that(square.size).is_equal_approx(Vector2(84.0, 84.0), Vector2(0.05, 0.05))
	var tablet: UiMetrics = UiProfiles.by_name(&"web_tablet")
	UiScale.set_override(tablet)
	get_window().size = tablet.window_size
	await await_idle_frame()
	assert_that(square.size).is_equal_approx(Vector2(60.0, 60.0), Vector2(0.05, 0.05))
	var metrics: Label = _control(probe, "MetricsLabel") as Label
	assert_str(metrics.text).contains("dp(48): 60.0 base px")
	assert_int(metrics.get_theme_font_size("font_size")).is_equal(20)  # dp(16)
	var log_label: Control = _control(probe, "GestureLog")
	assert_int(log_label.get_theme_font_size("font_size")).is_equal(20)
	assert_int(_control(probe, "Margin").get_theme_constant("margin_bottom")).is_equal(15)
	assert_int(_control(probe, "Margin").get_theme_constant("margin_left")).is_equal(15)  # dp(12)
	assert_int(_control(probe, "Column").get_theme_constant("separation")).is_equal(15)
	# Without an override it follows what the engine reports, as on a phone. The stretch scale
	# goes from 1.0 to 1.5 here, so the same dp is fewer base px.
	UiScale.clear_override()
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	var at_base_size: float = square.size.x
	assert_float(at_base_size).is_equal_approx(UiScale.dp(48.0), 0.001)
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	assert_float(square.size.x).is_equal_approx(UiScale.dp(48.0), 0.001)
	assert_float(square.size.x * 1.5).is_equal_approx(at_base_size, 0.001)


func test_touch_points_follow_the_fingers_in_base_px() -> void:
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))  # Stretch 1.5.
	_touch(0, Vector2(1200, 540), true)
	_touch(1, Vector2(600, 300), true)
	assert_dict(probe.touches).is_equal({0: Vector2(800, 360), 1: Vector2(400, 200)})
	_drag(1, Vector2(1500, 600))
	assert_dict(probe.touches).is_equal({0: Vector2(800, 360), 1: Vector2(1000, 400)})
	_touch(1, Vector2(1500, 600), false)
	assert_dict(probe.touches).is_equal({0: Vector2(800, 360)})
	_touch(0, Vector2(1200, 540), false)
	assert_dict(probe.touches).is_empty()


## The same fingers in portrait: the window px are divided by the stretch (1.5 here, as in
## landscape), the thresholds are the same dp, and the log names the same gestures.
func test_touch_points_and_gestures_are_in_base_px_in_portrait_too() -> void:
	var probe: Control = await _open(UiProfiles.by_name(&"android_6in_portrait"))
	probe.clock = func() -> int: return _now_ms
	_touch(0, Vector2(900, 1800), true)  # Base 600,1200.
	assert_dict(probe.touches).is_equal({0: Vector2(600, 1200)})
	_drag(0, Vector2(930, 1800))  # 20 base px: inside the 21 base px slop, a tap
	_touch(0, Vector2(930, 1800), false)
	assert_dict(probe.touches).is_empty()
	_touch(0, Vector2(900, 1800), true)
	_drag(0, Vector2(900, 2100))  # 200 base px down: a pan
	_touch(0, Vector2(900, 2100), false)
	assert_array(probe.log_lines).is_equal(["TAP 600,1200", "PAN move 0,200", "CAMERA_END"])


## At 1.75 base px per dp (stretch 1.5), so 12 dp is 21 base px and the thresholds are in dp.
func test_the_log_names_each_gesture_with_its_numbers_and_keeps_the_last_8() -> void:
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))
	probe.clock = func() -> int: return _now_ms
	_touch(0, Vector2(150, 300), true)  # Base 100,200.
	_drag(0, Vector2(180, 300))  # 20 base px: a tap, not a pan
	_touch(0, Vector2(180, 300), false)
	_touch(0, Vector2(150, 300), true)
	_touch(1, Vector2(450, 300), true)
	_drag(1, Vector2(750, 300))  # The distance doubles from 200 to 400 base px.
	_touch(1, Vector2(750, 300), false)
	_touch(0, Vector2(150, 300), false)
	var first: Array[String] = ["TAP 100,200", "PINCH x2.00 move 100,0 at 300,200"]
	assert_array(probe.log_lines).is_equal(first + ["CAMERA_END", "CAMERA_END"])
	_now_ms = 5000
	_touch(0, Vector2(150, 300), true)
	_now_ms = 5300  # The long-press comes with the frame, no finger event.
	await await_idle_frame()
	_touch(0, Vector2(150, 300), false, true)  # The system cancels the touch: a box cancel, no tap.
	var text: String = (_control(probe, "GestureLog") as Label).text
	assert_str(text).is_equal("\n\n" + "\n".join(probe.log_lines))
	assert_array(probe.log_lines).has_size(6)
	assert_str(probe.log_lines[4]).is_equal("LONG_PRESS 100,200")
	assert_str(probe.log_lines[5]).is_equal("BOX_CANCEL")
	for i: int in 4:  # Taps 1 s and 100 base px apart push the oldest lines out.
		_now_ms = 6000 + i * 1000
		_touch(0, Vector2(150 * (i + 3), 300), true)
		_touch(0, Vector2(150 * (i + 3), 300), false)
	assert_array(probe.log_lines).has_size(8)
	assert_str(probe.log_lines[0]).is_equal("CAMERA_END")
	assert_str(probe.log_lines[7]).is_equal("TAP 600,200")
	assert_int((_control(probe, "GestureLog") as Label).text.count("\n")).is_equal(7)


## The phone check reads these lines. Each finger event hands the clock's time to the recognizer.
func test_a_double_tap_a_pan_and_a_box_are_logged_with_their_numbers() -> void:
	var probe: Control = await _open(UiProfiles.by_name(ANDROID))
	probe.clock = func() -> int: return _now_ms
	for step: Array in [[1000, true], [1050, false], [1300, true], [1350, false]]:
		_now_ms = step[0]  # Two taps 250 ms apart.
		_touch(0, Vector2(150, 300), step[1])
	_now_ms = 5000
	_touch(0, Vector2(150, 300), true)
	_drag(0, Vector2(300, 300))
	_drag(0, Vector2(300, 450))
	_touch(0, Vector2(300, 450), false)
	_now_ms = 6000
	_touch(0, Vector2(150, 300), true)
	_now_ms = 6300  # No frame ran: the first move applies the time, so this is a box.
	_drag(0, Vector2(300, 450))
	_touch(0, Vector2(300, 450), false)
	var expected: Array[String] = [
		"TAP 100,200",
		"DOUBLE_TAP 100,200",
		"PAN move 100,0",
		"PAN move 0,100",
		"CAMERA_END",
		"LONG_PRESS 100,200",
		"BOX_UPDATE 100,200 100x100",
		"BOX_END 100,200 100x100",
	]
	assert_array(probe.log_lines).is_equal(expected)


func test_back_button_and_the_android_back_request_both_leave() -> void:
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
	assert_bool(get_tree().quit_on_go_back).is_true()


func _open(profile: UiMetrics) -> Control:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	var probe: Control = auto_free((load(DevRoutes.TOUCH_PROBE_SCENE) as PackedScene).instantiate())
	add_child(probe)
	await await_idle_frame()
	return probe


## The profile whose window is `size`, among the landscape and the portrait ones.
func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null


func _control(probe: Control, node_name: String) -> Control:
	return probe.find_child(node_name, true, false) as Control


## Events enter at the window, in window px, as the engine delivers them.
func _touch(index: int, window_px: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = window_px
	event.pressed = pressed
	event.canceled = canceled
	get_window().push_input(event)


func _drag(index: int, window_px: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = window_px
	get_window().push_input(event)
