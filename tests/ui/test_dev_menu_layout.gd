extends GdUnitTestSuite
## The dev menu in either orientation (plan P63, ADR 0015 section 5 "Other screens"): at the six
## test sizes its title and its eight buttons (the two Skirmishes of plan P90, test map, strike
## test, art gallery, touch probe, perf arena, perf bases) lie inside the safe rect, every button
## is at least
## dp(48) on each axis with text of 14 sp or more, and nothing overlaps. The same holds on the
## phone browsers (the buttons are 48 dp tall and stand in two columns sideways and one upright, so
## that they fit a phone browser held sideways without a scroll), with the cutouts of Michael's
## phone and of the ADR's portrait phone, and after a turn. A window that is too short for them
## scrolls, so no button is out of reach. Which scene a button opens is test_dev_routes.gd's.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const MIN_DP: float = 48.0
const TOLERANCE_PX: float = 0.5
const BUTTONS: Array[String] = [
	"SkirmishDerrickButton",
	"SkirmishLumenButton",
	"TestMapButton",
	"StrikeTestButton",
	"GalleryButton",
	"TouchProbeButton",
	"PerfArenaButton",
	"PerfBasesButton"
]
## Michael's phone in landscape (a cutout on the left) and the ADR's phone in portrait (a cutout at
## the top, the gesture bar at the bottom), as window px of the profile they are put on.
const LANDSCAPE_CUTOUT: Rect2i = Rect2i(152, 0, 2248, 1080)
const PORTRAIT_CUTOUT: Rect2i = Rect2i(0, 100, 1080, 2237)

var _window_size_before: Vector2i


func before() -> void:
	assert_bool(UiScale.has_override()).override_failure_message("override leaked").is_false()
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()


func test_every_control_is_inside_the_safe_area_and_the_buttons_are_big_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		var profile: UiMetrics = _profile_with_window(size)
		assert_object(profile).override_failure_message("no profile for %s" % size).is_not_null()
		await _check_layout(profile, str(size))


func test_the_phone_browsers_and_the_cutouts_keep_every_control_inside() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	var cases: Dictionary[String, UiMetrics] = {
		"web_phone": UiProfiles.by_name(&"web_phone"),
		"web_phone_portrait": UiProfiles.by_name(&"web_phone_portrait"),
		"landscape cutout": UiProfiles.with_safe_area(landscape, LANDSCAPE_CUTOUT),
		"portrait cutout": UiProfiles.with_safe_area(portrait, PORTRAIT_CUTOUT),
	}
	for label: String in cases:
		await _check_layout(cases[label], label)


## A phone browser held sideways with a cutout is too short for the column: the menu scrolls, and
## each button can be brought into the safe rect.
func test_a_window_too_short_for_the_column_scrolls_to_every_button() -> void:
	var small: UiMetrics = UiProfiles.by_name(&"web_phone_small")  # 304 dp tall.
	var short: Rect2i = Rect2i(0, 120, small.window_size.x, small.window_size.y - 240)
	var menu: Control = auto_free(await _open(UiProfiles.with_safe_area(small, short)))
	var scroll: ScrollContainer = menu.find_child("Scroll", true, false)
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	assert_float(bar.max_value).override_failure_message("fits: nothing to scroll").is_greater(
		bar.page
	)
	var safe: Rect2 = UiScale.safe_rect_base()
	var seen: Dictionary[String, bool] = {}
	for step: int in 20:
		scroll.scroll_vertical = roundi(bar.max_value) * step / 19  # Clamped to the end.
		await await_idle_frame()
		for button_name: String in BUTTONS:
			var rect: Rect2 = _control(menu, button_name).get_global_rect()
			seen[button_name] = seen.get(button_name, false) or safe.encloses(rect)
	assert_dict(seen).is_equal(
		{
			"SkirmishDerrickButton": true,
			"SkirmishLumenButton": true,
			"TestMapButton": true,
			"StrikeTestButton": true,
			"GalleryButton": true,
			"TouchProbeButton": true,
			"PerfArenaButton": true,
			"PerfBasesButton": true
		}
	)


## One menu turned: the engine's own metrics, no override, so the stretch turns with the window.
## The buttons stay dp(48) or more and inside the window, and the gap is the new dp(12).
func test_the_menu_follows_a_turn_of_the_window() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[1]
	await await_idle_frame()
	var menu: Control = await _instance()
	for size: Vector2i in [ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]]:
		get_window().size = size
		await await_idle_frame()
		await await_idle_frame()
		var visible_rect: Rect2 = get_window().get_visible_rect()
		var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
		var gap: int = roundi(UiScale.dp(12.0))
		assert_int(_control(menu, "Column").get_theme_constant("separation")).is_equal(gap)
		var grid: GridContainer = _control(menu, "Grid") as GridContainer
		assert_int(grid.get_theme_constant("h_separation")).is_equal(gap)
		assert_int(grid.get_theme_constant("v_separation")).is_equal(gap)
		assert_int(grid.columns).is_equal(1 if size.y > size.x else 2)  # The turn changes it.
		assert_float(grid.get_global_rect().get_center().x).is_equal_approx(
			visible_rect.get_center().x, 1.0
		)  # The block stays in the middle of the turn.
		for button_name: String in BUTTONS:
			var rect: Rect2 = _control(menu, button_name).get_global_rect()
			var label: String = "%s at %s: %s" % [button_name, size, rect]
			(
				assert_bool(rect.size.x >= floor_px and rect.size.y >= floor_px)
				. override_failure_message(label)
				. is_true()
			)
			assert_bool(visible_rect.encloses(rect)).override_failure_message(label).is_true()
	_close(menu)


## The hand-over of P112d: eight 48 dp buttons do not fit a phone browser held sideways in one
## column (the menu has 331 dp there), so they stand in two, and nothing scrolls at web_phone;
## upright there is one column, which has the height.
func test_the_eight_buttons_stand_in_two_columns_sideways_and_in_one_upright() -> void:
	for profile_name: StringName in [&"web_phone", &"android_6in", &"web_tablet", &"desktop"]:
		var menu: Control = await _open(UiProfiles.by_name(profile_name))
		var label: String = str(profile_name)
		assert_int((_control(menu, "Grid") as GridContainer).columns).is_equal(2)
		var left: float = _control(menu, "SkirmishDerrickButton").get_global_rect().position.x
		var right: float = _control(menu, "SkirmishLumenButton").get_global_rect().position.x
		var below: float = _control(menu, "TestMapButton").get_global_rect().position.x
		assert_float(right).override_failure_message(label).is_greater(left)
		assert_float(below).override_failure_message(label).is_equal_approx(left, 0.5)
		var bar: VScrollBar = (_control(menu, "Scroll") as ScrollContainer).get_v_scroll_bar()
		assert_float(bar.max_value).override_failure_message(label).is_less_equal(bar.page + 0.5)
		_close(menu)
		UiScale.clear_override()
	for profile_name: StringName in [&"web_phone_portrait", &"android_6in_portrait"]:
		var menu: Control = await _open(UiProfiles.by_name(profile_name))
		assert_int((_control(menu, "Grid") as GridContainer).columns).is_equal(1)
		_close(menu)
		UiScale.clear_override()


## `profile` shown: the title and the eight buttons, then the checks of the plan's acceptance.
func _check_layout(profile: UiMetrics, label: String) -> void:
	var menu: Control = await _open(profile)
	var safe: Rect2 = UiScale.safe_rect_base()
	var floor_px: float = UiScale.dp(MIN_DP) - TOLERANCE_PX
	var text_floor: int = roundi(UiScale.dp(14.0))  # 14 sp: the text of the HUD is dp.
	var rects: Array[Rect2] = [_control(menu, "Title").get_global_rect()]
	(
		assert_bool(safe.encloses(rects[0]))
		. override_failure_message("%s: title %s" % [label, rects[0]])
		. is_true()
	)
	for button_name: String in BUTTONS:
		var button: Button = _control(menu, button_name) as Button
		var rect: Rect2 = button.get_global_rect()
		var where: String = "%s: %s %s in %s" % [label, button_name, rect, safe]
		(
			assert_bool(rect.size.x >= floor_px and rect.size.y >= floor_px)
			. override_failure_message(where)
			. is_true()
		)
		assert_bool(safe.encloses(rect)).override_failure_message(where).is_true()
		(
			assert_bool(button.is_visible_in_tree() and not button.disabled)
			. override_failure_message(where)
			. is_true()
		)
		(
			assert_int(button.get_theme_font_size("font_size"))
			. override_failure_message(where)
			. is_greater_equal(text_floor)
		)
		rects.append(rect)
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			var why: String = "%s: %s overlaps %s" % [label, rects[first], rects[second]]
			(
				assert_bool(rects[first].intersects(rects[second]))
				. override_failure_message(why)
				. is_false()
			)
	_close(menu)
	UiScale.clear_override()


## The menu in the tree at `profile`'s window, after two frames of layout.
func _open(profile: UiMetrics) -> Control:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	return await _instance()


func _instance() -> Control:
	var menu: Control = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await await_idle_frame()
	await await_idle_frame()
	return menu


func _close(menu: Control) -> void:
	remove_child(menu)
	menu.free()


func _control(menu: Control, node_name: String) -> Control:
	return menu.find_child(node_name, true, false) as Control


## The profile whose window is `size`: the landscape ones, then the portrait ones.
func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
