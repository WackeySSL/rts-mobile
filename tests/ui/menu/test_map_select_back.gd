extends GdUnitTestSuite
## P672a: the on-screen BACK of the map select (the web has no back event, ADR 0043 s.4): the
## last control of the column, 48 dp, with the ui_back cue; a press pops to the menu below it.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const FakeRank: GDScript = preload("res://tests/ui/support/fake_rank_progression.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _menu: Control
var _stack: MenuStack
var _root: MenuScreen  ## Stands in for the main menu under the screen.
var _screen: MapSelect
var _progression: Node
var _flow: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_progression = FakeRank.new()
	_flow = FakeFlow.new()


func after_test() -> void:
	UiScale.clear_override()
	_close()
	for node: Node in [_progression, _flow]:
		if is_instance_valid(node):
			node.free()


func test_back_button_ends_the_column_and_pops_to_the_menu_below_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var label: String = str(size)
		var last: Control = _screen.column.get_child(_screen.column.get_child_count() - 1)
		assert_bool(last is Button).override_failure_message(label).is_true()
		var back: Button = last as Button
		assert_str(back.text).override_failure_message(label).is_equal("BACK")
		assert_that(back.get_meta(&"ui_cue")).is_equal(&"ui_back")
		(
			assert_float(back.get_global_rect().size.y)
			. override_failure_message(label)
			. is_greater_equal(UiScale.dp(48.0) - TOLERANCE_PX)
		)
		assert_int(_stack.depth()).is_equal(2)
		back.pressed.emit()
		await await_idle_frame()
		assert_int(_stack.depth()).override_failure_message(label).is_equal(1)
		assert_object(_stack.current()).is_same(_root)
		_close()
		UiScale.clear_override()


func test_the_back_button_does_nothing_while_the_match_starts() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var back: Button = _screen.column.get_child(_screen.column.get_child_count() - 1) as Button
	_screen._start.pressed.emit()
	back.pressed.emit()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(2)
	_flow.release.emit()
	await await_idle_frame()


func _open(profile: UiMetrics) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_root = MenuScreen.new()
	_stack.push(_root)
	await await_idle_frame()
	_screen = MapSelect.new()
	_screen.progression = _progression
	_screen.flow = _flow
	_screen.catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	_stack.push(_screen)
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	assert_bool(false).override_failure_message("no profile for %s" % size).is_true()
	return null
