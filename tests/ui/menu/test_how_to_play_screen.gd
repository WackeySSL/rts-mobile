extends GdUnitTestSuite
## The How to play screen (plan P527, ADR 0044 section 3): at the six sizes of ADR 0015 section 6
## the column is inside the safe rect and every button is 48 dp or more; a long section scrolls;
## back goes from a section to the list and from the list pops the stack; the foot slot is empty.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = true
var _menu: Control
var _stack: MenuStack
var _screen: HowToPlayScreen


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func test_the_list_and_a_section_stay_in_the_safe_area_with_big_targets_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size), _long_help(1))
		_assert_fits(str(size) + " list")
		assert_int(_buttons().size()).is_equal(2)  # One section and Back.
		_buttons()[0].pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		assert_object(_screen.open_section).is_not_null()
		_assert_fits(str(size) + " section")
		_close()
		UiScale.clear_override()


func test_a_long_section_scrolls_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size), _long_help(60))
		_buttons()[0].pressed.emit()
		await await_idle_frame()
		await await_idle_frame()
		var bar: VScrollBar = _screen.scroll.get_v_scroll_bar()
		var label: String = str(size)
		assert_float(bar.max_value).override_failure_message(label).is_greater(bar.page)
		_screen.scroll.scroll_vertical = int(bar.max_value)
		await await_idle_frame()
		assert_int(_screen.scroll.scroll_vertical).override_failure_message(label).is_greater(0)
		_close()
		UiScale.clear_override()


func test_the_real_data_lists_every_section_as_a_button() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]), null)
	var help: HelpDef = load(HowToPlayScreen.DEF_PATH) as HelpDef
	assert_int(_buttons().size()).is_equal(help.sections.size() + 1)
	assert_bool(_screen.slot.has_band()).is_false()
	assert_float(_screen.slot.size.y).is_equal_approx(0.0, 0.01)


func test_back_leaves_a_section_for_the_list_and_the_list_for_the_menu_below() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), _long_help(1))
	assert_int(_stack.depth()).is_equal(2)
	_buttons()[0].pressed.emit()
	await await_idle_frame()
	assert_object(_screen.open_section).is_not_null()
	_stack.back()  # Android back: the section closes, the screen stays.
	await await_idle_frame()
	assert_object(_screen.open_section).is_null()
	assert_int(_stack.depth()).is_equal(2)
	_stack.back()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)
	assert_bool(is_instance_valid(_screen)).is_false()  # Replaced by pop: the stack freed it.


func test_the_back_button_of_the_list_pops() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), _long_help(1))
	_buttons().back().pressed.emit()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(1)


func _assert_fits(label: String) -> void:
	var safe: Rect2 = UiScale.safe_rect_base()
	var column: Control = _screen.column
	(
		assert_bool(safe.grow(TOLERANCE_PX).encloses(column.get_global_rect()))
		. override_failure_message(label)
		. is_true()
	)
	var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
	for button: Button in _buttons():
		(
			assert_float(button.get_global_rect().size.y)
			. override_failure_message(label)
			. is_greater_equal(floor_px)
		)
	for child: Node in column.get_children():
		var control: Control = child as Control
		(
			assert_float(control.get_global_rect().size.x)
			. override_failure_message(label)
			. is_less_equal(safe.size.x + TOLERANCE_PX)
		)


func _buttons() -> Array[Button]:
	var found: Array[Button] = []
	for child: Node in _screen.column.get_children():
		if child is Button and not child.is_queued_for_deletion():
			found.append(child as Button)
	return found


## One section with `count` entries of a long body.
func _long_help(count: int) -> HelpDef:
	var section: HelpSectionDef = HelpSectionDef.new()
	section.id = &"long"
	section.title = "Long"
	for i: int in count:
		var entry: HelpEntryDef = HelpEntryDef.new()
		entry.id = StringName("long-%d" % i)
		entry.title = "Entry %d" % i
		entry.body = "A line of help text that has to wrap on a narrow screen. ".repeat(8)
		section.entries.append(entry)
	var help: HelpDef = HelpDef.new()
	help.sections.append(section)
	return help


## A menu with a root screen and the How to play screen on top of it (`help` null: the real data).
func _open(profile: UiMetrics, help: HelpDef) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_stack.push(MenuScreen.new())
	await await_idle_frame()
	_screen = HowToPlayScreen.new()
	_screen.help = help  # Null: the screen loads the real data.
	_stack.push(_screen)
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	remove_child(_menu)
	_menu.free()
	_menu = null


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
