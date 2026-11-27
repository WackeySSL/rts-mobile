extends GdUnitTestSuite
## P672a: the footer bar of the sub-screens (Michael's Figma, 2026-11-27): the back link at its
## left, outside the scroll so a page scrolled to its end still shows it, at least 48 dp, named
## for the screen below ("‹ MAIN MENU"), a press pops, and `on_back()` refusals hold.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const FakeRank: GDScript = preload("res://tests/ui/support/fake_rank_progression.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const KINDS: Array[StringName] = [&"settings", &"map", &"how_to_play", &"licences", &"tutorial"]
const TOLERANCE_PX: float = 0.5


## What the footer sits over: a root that names itself as the main menu does.
class FakeRoot:
	extends MenuScreen

	func screen_name() -> String:
		return "MAIN MENU"


var _window_size_before: Vector2i
var _menu: Control
var _stack: MenuStack
var _root: MenuScreen
var _screen: MenuScreen
var _progression: Node
var _flow: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	PrefsRig.begin()
	_progression = FakeRank.new()
	_flow = FakeFlow.new()


func after_test() -> void:
	UiScale.clear_override()
	_close()
	for node: Node in [_progression, _flow]:
		if is_instance_valid(node):
			node.free()
	PrefsRig.end()


func test_the_link_is_outside_the_scroll_visible_at_the_end_and_48_dp_at_the_six_sizes() -> void:
	for kind: StringName in KINDS:
		for size: Vector2i in ScreenSizes.ALL:
			await _open(kind, _profile_with_window(size))
			var label: String = "%s %s" % [kind, size]
			var link: Button = _screen.back_link
			(
				assert_bool(_screen.scroll.is_ancestor_of(link))
				. override_failure_message(label)
				. is_false()
			)
			assert_bool(_screen.footer.visible).override_failure_message(label).is_true()
			_screen.scroll.scroll_vertical = 1000000
			await await_idle_frame()
			var rect: Rect2 = link.get_global_rect()
			var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
			assert_bool(safe.encloses(rect)).override_failure_message(label).is_true()
			var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
			assert_float(rect.size.y).override_failure_message(label).is_greater_equal(floor_px)
			assert_float(rect.size.x).override_failure_message(label).is_greater_equal(floor_px)
			assert_float(rect.position.y).override_failure_message(label).is_greater_equal(
				_screen.scroll.get_global_rect().end.y - TOLERANCE_PX
			)
			assert_that(link.get_meta(&"ui_cue")).is_equal(&"ui_back")
			_close()
			UiScale.clear_override()


func test_the_label_names_the_screen_below_and_a_press_pops() -> void:
	for kind: StringName in KINDS:
		await _open(kind, _profile_with_window(ScreenSizes.PORTRAIT[0]))
		assert_str(_screen.back_link.text).override_failure_message(kind).is_equal("‹ MAIN MENU")
		assert_int(_stack.depth()).is_equal(2)
		_screen.back_link.pressed.emit()
		await await_idle_frame()
		assert_int(_stack.depth()).override_failure_message(kind).is_equal(1)
		assert_object(_stack.current()).is_same(_root)
		_close()
		UiScale.clear_override()


func test_the_main_menu_names_itself_and_a_screen_without_a_below_reads_back() -> void:
	var main: MainMenu = auto_free(MainMenu.new())
	assert_str(main.screen_name()).is_equal("MAIN MENU")
	await _open(&"settings", _profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_str(_screen.back_link.text).is_equal("‹ BACK")  # Over the pause menu: nothing below.


func test_a_section_and_a_licence_text_name_their_list_and_go_back_to_it() -> void:
	await _open(&"how_to_play", _profile_with_window(ScreenSizes.PORTRAIT[0]))
	var how: HowToPlayScreen = _screen as HowToPlayScreen
	for child: Node in how.column.get_children():
		if child is Button:
			(child as Button).pressed.emit()
			break
	await await_idle_frame()
	assert_object(how.open_section).is_not_null()
	assert_str(how.back_link.text).is_equal("‹ HOW TO PLAY")
	how.back_link.pressed.emit()
	await await_idle_frame()
	assert_object(how.open_section).is_null()
	assert_int(_stack.depth()).is_equal(2)
	assert_str(how.back_link.text).is_equal("‹ MAIN MENU")
	_close()
	await _open(&"licences", _profile_with_window(ScreenSizes.PORTRAIT[0]))
	var licences: LicencesScreen = _screen as LicencesScreen
	for child: Node in licences.column.get_children():
		if child is Button:
			(child as Button).pressed.emit()
			break
	await await_idle_frame()
	assert_object(licences.open_entry).is_not_null()
	assert_str(licences.back_link.text).is_equal("‹ LICENCES")
	licences.back_link.pressed.emit()
	await await_idle_frame()
	assert_object(licences.open_entry).is_null()
	assert_int(_stack.depth()).is_equal(2)


func test_the_link_does_nothing_while_the_match_starts() -> void:
	await _open(&"map", _profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var map: MapSelect = _screen as MapSelect
	map._start.pressed.emit()
	map.back_link.pressed.emit()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(2)
	_flow.release.emit()
	await await_idle_frame()


func _open(kind: StringName, profile: UiMetrics, with_root: bool = true) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	if with_root:
		_root = FakeRoot.new()
		_stack.push(_root)
		await await_idle_frame()
	_screen = _make(kind)
	_stack.push(_screen)
	for _frame: int in range(4):
		await await_idle_frame()


func _make(kind: StringName) -> MenuScreen:
	match kind:
		&"settings":
			var settings: SettingsScreen = SettingsScreen.new()
			settings.routes = MenuRoutes.new()
			settings.dev_enabled = func() -> bool: return false
			settings.in_match = func() -> bool: return false
			return settings
		&"map":
			var map: MapSelect = MapSelect.new()
			map.progression = _progression
			map.flow = _flow
			map.catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
			return map
		&"how_to_play":
			return HowToPlayScreen.new()
		&"licences":
			return LicencesScreen.new()
	return TutorialScreen.new()


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
