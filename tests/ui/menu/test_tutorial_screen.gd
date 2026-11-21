extends GdUnitTestSuite
## The Tutorial screen (plan row P544, ADR 0044): at the six sizes of ADR 0015 section 6 the column
## is inside the safe rect and every button is 48 dp or more; the lessons are listed in order with
## the done mark and the NEXT mark; a tap starts the lesson through the flow, once; Back pops; the
## main menu and Settings reach it through the route.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = false
var _menu: Control
var _stack: MenuStack
var _screen: TutorialScreen
var _flow: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	PrefsRig.begin()
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	PrefsRig.end()


func test_the_screen_fits_the_safe_area_with_big_targets_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var label: String = str(size)
		var safe: Rect2 = UiScale.safe_rect_base()
		var scroll_rect: Rect2 = _screen.scroll.get_global_rect()
		var shown: Rect2 = _screen.column.get_global_rect().intersection(scroll_rect)
		(
			assert_bool(safe.grow(TOLERANCE_PX).encloses(shown))
			. override_failure_message(label)
			. is_true()
		)
		assert_int(_buttons().size()).is_equal(TutorialStart.ORDER.size() + 1)
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		for button: Button in _buttons():
			var rect: Rect2 = button.get_global_rect()
			assert_float(rect.size.y).override_failure_message(label).is_greater_equal(floor_px)
			assert_float(rect.size.x).override_failure_message(label).is_less_equal(
				safe.size.x + TOLERANCE_PX
			)
		_close()
		UiScale.clear_override()


func test_a_fresh_save_lists_the_lessons_in_order_and_marks_the_first_next() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_str(_buttons()[0].text).is_equal("BASICS   NEXT")
	assert_str(_buttons()[1].text).is_equal("STRIKES AND THE SATELLITE")
	assert_str(_buttons()[2].text).is_equal("AIRCRAFT AND CARRIERS")
	assert_str(_buttons()[3].text).is_equal("REPAIR, SALE AND MINES")
	assert_str(_buttons()[4].text).is_equal("BACK")


func test_a_finished_lesson_shows_done_in_words_and_the_next_one_moves_on() -> void:
	TutorialDirector.mark_done(&"basics")
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_str(_buttons()[0].text).is_equal("BASICS   DONE")
	assert_str(_buttons()[1].text).is_equal("STRIKES AND THE SATELLITE   NEXT")
	TutorialDirector.mark_done(&"strikes")
	_screen.refresh()  # What the screen does when it is back on top of the stack.
	assert_str(_buttons()[1].text).is_equal("STRIKES AND THE SATELLITE   DONE")
	assert_str(_buttons()[2].text).is_equal("AIRCRAFT AND CARRIERS   NEXT")


func test_a_tap_starts_that_lesson_once_even_when_it_is_done() -> void:
	TutorialDirector.mark_done(&"basics")
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	_buttons()[0].pressed.emit()  # A replay.
	_buttons()[0].pressed.emit()
	_buttons()[2].pressed.emit()
	assert_int(_flow.started.size()).is_equal(1)
	assert_str(String(_flow.started[0].lesson_id)).is_equal("basics")
	assert_bool(_screen.on_back()).is_true()  # Back waits while the lesson starts.
	assert_bool(_buttons()[1].disabled).is_true()
	_flow.release.emit()
	await await_idle_frame()


func test_a_refused_start_warns_and_the_screen_works_again() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	_flow.refuse = ERR_BUSY
	await (
		assert_error(func() -> void: _buttons()[1].pressed.emit())
		. is_push_warning("TutorialScreen: lesson strikes did not start (Busy)")
	)
	assert_bool(_screen.on_back()).is_false()
	assert_bool(_buttons()[1].disabled).is_false()


func test_back_pops_to_the_menu_below_and_the_android_back_is_not_taken() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_bool(_screen.on_back()).is_false()
	assert_int(_stack.depth()).is_equal(2)
	_buttons().back().pressed.emit()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)


func test_the_main_menu_and_settings_open_it_through_the_default_route() -> void:
	var routes: MenuRoutes = MenuRoutes.new()
	MenuRoutesDefaults.register(routes)
	assert_bool(routes.has(MenuRoutes.TUTORIAL)).is_true()
	var made: MenuScreen = routes.make(MenuRoutes.TUTORIAL)
	assert_object(made).is_instanceof(TutorialScreen)
	made.free()


func _open(profile: UiMetrics) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	add_child(_menu)
	await await_idle_frame()
	_stack.push(MenuScreen.new())  # A root to pop back to.
	await await_idle_frame()
	_flow = auto_free(FakeFlow.new())
	add_child(_flow)
	_screen = TutorialScreen.new()
	_screen.flow = _flow
	_stack.push(_screen)
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	remove_child(_menu)
	_menu.free()
	_menu = null


func _buttons() -> Array[Button]:
	var found: Array[Button] = []
	for child: Node in _screen.column.get_children():
		if child is Button:
			found.append(child as Button)
	return found


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
