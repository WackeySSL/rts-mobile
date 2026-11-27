extends GdUnitTestSuite
## P672b: a finger drag scrolls a menu page. The project does not turn touch into mouse events
## (`emulate_mouse_from_touch` is off, P26az), and a ScrollContainer scrolls only from the mouse,
## so a page too long for the window must scroll from `InputEventScreenDrag` itself. A short tap
## still presses the button under the finger; a drag that starts on a button scrolls and does not
## press it; a page that fits stays where it is. Run at the portrait and landscape phone sizes.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const LONG_ROWS: int = 40
const SHORT_ROWS: int = 2
const SWIPE_DP: float = 120.0
const SWIPE_STEPS: int = 8

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = false
var _menu: Control
var _stack: MenuStack
var _screen: MenuScreen
var _pressed: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	_pressed.clear()


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	_close()


func test_a_drag_scrolls_a_long_page_in_both_orientations() -> void:
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		await _open(size, LONG_ROWS)
		var scroll: ScrollContainer = _screen.scroll
		assert_int(scroll.scroll_vertical).override_failure_message(str(size)).is_equal(0)
		var from: Vector2 = scroll.get_global_rect().get_center()
		# The finger moves up: the page follows it, so the offset grows.
		await _swipe(from, from + Vector2(0.0, -UiScale.dp(SWIPE_DP)))
		(
			assert_int(scroll.scroll_vertical)
			. override_failure_message("%s scrolled" % size)
			. is_greater(0)
		)
		_close()
		UiScale.clear_override()


func test_a_tap_still_presses_the_button() -> void:
	await _open(ScreenSizes.PORTRAIT[0], LONG_ROWS)
	var button: Button = _screen.column.get_child(3) as Button
	var at: Vector2 = button.get_global_rect().get_center()
	await _swipe(at, at)
	assert_array(_pressed).is_equal([3])
	assert_int(_screen.scroll.scroll_vertical).is_equal(0)


func test_a_drag_that_starts_on_a_button_scrolls_and_does_not_press_it() -> void:
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		await _open(size, LONG_ROWS)
		var button: Button = _screen.column.get_child(2) as Button
		var at: Vector2 = button.get_global_rect().get_center()
		await _swipe(at, at + Vector2(0.0, -UiScale.dp(SWIPE_DP)))
		assert_array(_pressed).override_failure_message(str(size)).is_empty()
		(
			assert_int(_screen.scroll.scroll_vertical)
			. override_failure_message("%s scrolled" % size)
			. is_greater(0)
		)
		_close()
		UiScale.clear_override()


func test_a_drag_on_a_page_that_fits_does_nothing() -> void:
	await _open(ScreenSizes.PORTRAIT[0], SHORT_ROWS)
	var scroll: ScrollContainer = _screen.scroll
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	assert_float(bar.max_value - bar.page).is_less_equal(0.5)
	var from: Vector2 = scroll.get_global_rect().get_center()
	await _swipe(from, from + Vector2(0.0, -UiScale.dp(SWIPE_DP)))
	assert_int(scroll.scroll_vertical).is_equal(0)
	assert_array(_pressed).is_empty()


func test_a_sideways_drag_does_not_scroll() -> void:
	await _open(ScreenSizes.PORTRAIT[0], LONG_ROWS)
	var from: Vector2 = _screen.scroll.get_global_rect().get_center()
	await _swipe(from, from + Vector2(UiScale.dp(SWIPE_DP), 0.0))
	assert_int(_screen.scroll.scroll_vertical).is_equal(0)


func test_a_modal_frame_scrolls_under_a_finger() -> void:
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		await _open(size, 0)
		var modal: ModalFrame = ModalFrame.new()
		_menu.add_child(modal)
		modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await await_idle_frame()
		for row: int in LONG_ROWS:
			modal.add_button(modal.column, "ROW %d" % row, func() -> void: _pressed.append(row))
		modal.visible = true
		await await_idle_frame()
		await await_idle_frame()
		var scroll: ScrollContainer = modal.find_children("*", "ScrollContainer", true, false)[0]
		var from: Vector2 = scroll.get_global_rect().get_center()
		await _swipe(from, from + Vector2(0.0, -UiScale.dp(SWIPE_DP)))
		assert_int(scroll.scroll_vertical).override_failure_message(str(size)).is_greater(0)
		assert_array(_pressed).override_failure_message(str(size)).is_empty()
		_close()
		UiScale.clear_override()


func _open(size: Vector2i, rows: int) -> void:
	var profile: UiMetrics = null
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				profile = profiles[profile_name]
	UiScale.set_override(profile)
	get_window().size = size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_screen = MenuScreen.new()
	_stack.push(_screen)
	await await_idle_frame()
	for row: int in rows:
		_screen.add_button("ROW %d" % row, func() -> void: _pressed.append(row))
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


## One finger: press at `from`, move to `to` in steps, release there. Events enter at the window
## as the engine delivers them.
func _swipe(from: Vector2, to: Vector2) -> void:
	_touch(from, true)
	await await_idle_frame()
	if from != to:
		for i: int in range(1, SWIPE_STEPS + 1):
			_drag(from.lerp(to, float(i) / SWIPE_STEPS), (to - from) / SWIPE_STEPS)
			await await_idle_frame()
	_touch(to, false)
	await await_idle_frame()


func _touch(position: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	get_window().push_input(event)


func _drag(position: Vector2, relative: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	event.relative = relative
	get_window().push_input(event)
