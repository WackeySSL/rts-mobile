extends GdUnitTestSuite
## UiScale: the dp formula per platform, its fallbacks and clamp, the safe area in base px, the
## test override, and DpMinSize (ADR 0004 section 3).

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ANDROID: StringName = &"android_6in"
const TABLET: StringName = &"web_tablet"
const BASE_SIZE: Vector2i = Vector2i(1280, 720)
## dp(48) in base px for each profile (plan Phase 1, "Test profiles").
const EXPECTED_DP48: Dictionary = {
	&"android_6in": 84.0,
	&"web_phone": 97.3,
	&"web_phone_small": 113.7,
	&"web_tablet": 60.0,
	&"desktop": 48.0,
}
const TOLERANCE_PX: float = 0.5
## The android_6in window (2400x1080) at stretch 1.5 shows 1600x720 base px.
const ANDROID_VISIBLE: Rect2 = Rect2(0, 0, 1600, 720)

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = BASE_SIZE
	await await_idle_frame()


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


## Each profile holds the stretch scale the engine computes at its window size, and gives its
## dp(48) in base px.
func test_each_profile_matches_the_engine_and_gives_its_dp_48() -> void:
	var profiles: Dictionary = UiProfiles.all()
	assert_array(profiles.keys()).contains_exactly_in_any_order(EXPECTED_DP48.keys())
	for profile_name: StringName in profiles:
		var profile: UiMetrics = profiles[profile_name]
		get_window().size = profile.window_size
		await await_idle_frame()
		var engine_scale: float = get_window().get_stretch_transform().get_scale().x
		_assert_near(engine_scale, profile.stretch_scale, 0.001, str(profile_name))
		UiScale.set_override(profile)
		_assert_near(UiScale.dp(48.0), EXPECTED_DP48[profile_name], TOLERANCE_PX, str(profile_name))
		assert_that(UiScale.dp_vec(48.0, 24.0)).is_equal(
			Vector2(UiScale.dp(48.0), UiScale.dp(24.0))
		)


## Cases are [os_name, dpi, screen_scale, window px per dp].
func test_window_px_per_dp_per_platform_with_fallbacks_and_clamp() -> void:
	var cases: Array[Array] = [
		# Android is dpi / 160 and ignores screen_scale. Everything else is the reverse.
		["Android", 320, 5.0, 2.0],
		["Web", 480, 2.5, 2.5],
		["iOS", 480, 3.0, 3.0],
		["Linux", 96, 1.0, 1.0],
		# Values that are not finite or not above 0 count as 1.0.
		["Android", 0, 3.0, 1.0],
		["Web", 96, 0.0, 1.0],
		["Web", 96, NAN, 1.0],
		["Web", 96, INF, 1.0],
		# The clamp is [0.75, 4.0].
		["Android", 40, 1.0, 0.75],
		["Android", 1600, 1.0, 4.0],
		["Web", 96, 0.1, 0.75],
		["Web", 96, 9.0, 4.0],
	]
	for case: Array in cases:
		var metrics: UiMetrics = UiMetrics.create(
			case[0], case[1], case[2], 1.0, BASE_SIZE, Rect2i()
		)
		_assert_near(UiScale.window_px_per_dp(metrics), case[3], 0.0001, str(case))


## Cases are [stretch_scale, base px per dp] at 3.0 window px per dp.
func test_base_px_per_dp_divides_by_the_stretch_scale_or_one() -> void:
	var cases: Array[Vector2] = [Vector2(1.5, 2.0), Vector2(0.0, 3.0), Vector2(NAN, 3.0)]
	for case: Vector2 in cases:
		var metrics: UiMetrics = UiMetrics.create("Web", 96, 3.0, case.x, BASE_SIZE, Rect2i())
		_assert_near(UiScale.base_px_per_dp_for(metrics), case.y, 0.0001, str(case.x))


func test_safe_rect_in_base_px() -> void:
	var android: UiMetrics = UiProfiles.by_name(ANDROID)
	# Nothing reported: the visible rect.
	UiScale.set_override(android)
	assert_that(UiScale.safe_rect_base()).is_equal(ANDROID_VISIBLE)
	# A 100 px cutout on the left and a 54 px status bar, at stretch 1.5.
	var inset: Rect2i = Rect2i(100, 54, 2200, 1026)
	UiScale.set_override(UiProfiles.with_safe_area(android, inset))
	var safe: Rect2 = UiScale.safe_rect_base()
	assert_vector(safe.position).is_equal_approx(Vector2(66.667, 36.0), Vector2(0.01, 0.01))
	assert_vector(safe.size).is_equal_approx(Vector2(1466.667, 684.0), Vector2(0.01, 0.01))
	# A desktop screen's usable area is larger than the window, or lies elsewhere on the screen.
	for area: Rect2i in [Rect2i(-50, -50, 5000, 5000), Rect2i(5000, 5000, 100, 100)]:
		var metrics: UiMetrics = UiProfiles.with_safe_area(android, area)
		assert_that(UiScale.safe_rect_base_for(metrics)).is_equal(ANDROID_VISIBLE)


func test_override_wins_until_cleared_and_then_the_engine_is_read() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(TABLET)
	UiScale.set_override(metrics)
	assert_object(UiScale.current()).is_same(metrics)
	UiScale.clear_override()
	get_window().size = Vector2i(2400, 1080)
	await await_idle_frame()
	var current: UiMetrics = UiScale.current()
	assert_object(current).is_not_same(metrics)
	assert_str(current.os_name).is_equal(OS.get_name())
	assert_int(current.dpi).is_equal(DisplayServer.screen_get_dpi())
	assert_float(current.screen_scale).is_equal(DisplayServer.screen_get_scale())
	assert_that(current.window_size).is_equal(Vector2i(2400, 1080))
	assert_float(current.stretch_scale).is_equal(1.5)


func test_dp_min_size_sets_the_parent_minimum_when_ready() -> void:
	UiScale.set_override(UiProfiles.by_name(ANDROID))
	var square: Button = _button_with_dp_min_size(Vector2(48, 48))
	var wide: Button = _button_with_dp_min_size(Vector2(96, 56))
	await await_idle_frame()
	assert_that(square.custom_minimum_size).is_equal(Vector2(84, 84))
	assert_that(wide.custom_minimum_size).is_equal(Vector2(168, 98))
	assert_vector(square.size).is_greater_equal(Vector2(83.5, 83.5))


func test_dp_min_size_resizes_its_parent_when_the_window_changes() -> void:
	var tablet: UiMetrics = UiProfiles.by_name(TABLET)
	UiScale.set_override(UiProfiles.by_name(ANDROID))
	var button: Button = _button_with_dp_min_size(Vector2(48, 48))
	await await_idle_frame()
	assert_that(button.custom_minimum_size).is_equal(Vector2(84, 84))
	UiScale.set_override(tablet)
	get_window().size = tablet.window_size
	await await_idle_frame()
	assert_that(button.custom_minimum_size).is_equal(Vector2(60, 60))


func _button_with_dp_min_size(min_dp: Vector2) -> Button:
	var button: Button = auto_free(Button.new())
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = min_dp
	button.add_child(min_size)
	add_child(button)
	return button


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	assert_float(actual).override_failure_message(label).is_equal_approx(expected, tolerance)
