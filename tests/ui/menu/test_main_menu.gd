extends GdUnitTestSuite
## The main menu (plan P524) at the six sizes of ADR 0015 section 6: inside the safe area, touch
## targets of 48 dp or more, the start-page banner band lined up with the banner, the slot 0 tall
## without a banner, the XP bar following `xp_changed`, Continue only with a resume file, the
## buttons through the route table, and the quit question at the root.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const SAVE_SCRIPT: String = "res://game/meta/save_service.gd"
const SERVICE_SCRIPT: String = "res://game/meta/progression_service.gd"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const AdBandAsserts: GDScript = preload("res://tests/ui/support/ad_band_asserts.gd")
const TOLERANCE_PX: float = 0.5
const VERSION_KEY: String = "application/config/version"

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = true
var _dir: String = ""
var _menu: Control
var _stack: MenuStack
var _main: MainMenu
var _ads: Node
var _harness: RefCounted
var _save: Node
var _progression: Node
var _routes: MenuRoutes
var _resume: Array[bool] = [false]
var _quits: Array[int] = [0]
var _version_before: Variant


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	_dir = "user://test_main_menu_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_save = (load(SAVE_SCRIPT) as GDScript).new()
	_save.call("set_path_override", _dir.path_join("save.cfg"))
	_progression = (load(SERVICE_SCRIPT) as GDScript).new()
	_progression.call("bind", _save, null)
	_routes = MenuRoutes.new()
	_resume[0] = false
	_quits[0] = 0
	_version_before = (
		ProjectSettings.get_setting(VERSION_KEY)
		if ProjectSettings.has_setting(VERSION_KEY)
		else null
	)


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	_close()
	MenuRoutes.shared.clear()
	ProjectSettings.set_setting(VERSION_KEY, _version_before)
	for node: Node in [_ads, _save, _progression]:
		if is_instance_valid(node):
			node.free()
	if _harness != null:
		_harness.dispose()
		_harness = null
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func test_everything_is_inside_the_safe_area_with_48_dp_targets_at_the_six_sizes() -> void:
	_resume[0] = true
	_routes.register(MenuRoutes.SKIRMISH, MenuScreen.new)
	var fitting: int = 0
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size), true)
		var label: String = str(size)
		var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
		var column_rect: Rect2 = _main.column.get_global_rect()
		assert_float(column_rect.position.x).override_failure_message(label).is_greater_equal(
			safe.position.x
		)
		assert_float(column_rect.end.x).override_failure_message(label).is_less_equal(safe.end.x)
		(
			assert_bool(safe.encloses(_main.scroll.get_global_rect()))
			. override_failure_message(label)
			. is_true()
		)
		var first: Button = _buttons()[0]
		if _main.column.get_combined_minimum_size().y <= _main.scroll.size.y:
			fitting += 1
			assert_bool(safe.encloses(column_rect)).override_failure_message(label).is_true()
		else:
			_main.scroll.ensure_control_visible(first)
			await await_idle_frame()
			var scroll_rect: Rect2 = _main.scroll.get_global_rect().grow(TOLERANCE_PX)
			(
				assert_bool(scroll_rect.encloses(first.get_global_rect()))
				. override_failure_message(label)
				. is_true()
			)
		var shown: int = 0
		for child: Node in _main.column.get_children():
			var button: Button = child as Button
			if button == null or not button.visible:
				continue
			shown += 1
			(
				assert_float(button.get_global_rect().size.y)
				. override_failure_message(label)
				. is_greater_equal(UiScale.dp(48.0) - TOLERANCE_PX)
			)
		assert_int(shown).override_failure_message(label).is_equal(5)
		_close()
		UiScale.clear_override()
	# Every upright size fits; at least one sideways size scrolls and is checked by scrolling.
	assert_int(fitting).is_greater_equal(ScreenSizes.PORTRAIT.size())
	assert_int(fitting).is_less(ScreenSizes.ALL.size())


func test_the_band_lines_up_on_the_start_page_and_the_slot_is_tall_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size), true)
		var label: String = str(size)
		var band: AdBannerBand = _main.slot.get_child(0) as AdBannerBand
		assert_bool(band.start_page).is_true()
		assert_float(band.gap_dp()).is_equal(48.0)
		assert_float(_main.slot.size.y).override_failure_message(label).is_equal_approx(
			band.reserved_px(), 1.0
		)
		assert_float(_main.slot.size.y).override_failure_message(label).is_greater(0.0)
		AdBandAsserts.assert_lines_up(self, band, _ads, _main.scroll, band.gap_dp(), label)
		_close()
		UiScale.clear_override()


func test_the_slot_is_0_tall_without_a_banner() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]), false)
	assert_bool(_main.slot.has_band()).is_true()
	assert_float(_main.slot.size.y).is_equal_approx(0.0, 0.01)
	assert_float(_main.slot.get_global_rect().end.y).is_equal_approx(
		UiScale.safe_rect_base().end.y, TOLERANCE_PX
	)


func test_the_xp_bar_and_rank_follow_xp_changed() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_float(_main._xp_bar.value).is_equal(0.0)
	assert_str(_main._rank_label.text).contains("RANK 1")
	var summary: MatchSummary = MatchSummary.new()
	summary.outcome = &"win"
	summary.level = &"normal"
	summary.ticks = 5 * 900
	var award: XpAward = _progression.call("award_match", summary) as XpAward
	assert_int(award.base_xp).is_greater(0)
	assert_float(_main._xp_bar.value).is_equal(float(_progression.call("xp")))
	assert_str(_main._xp_label.text).contains(str(_progression.call("xp")))
	assert_float(_main._xp_bar.max_value).is_equal(float(_progression.call("next_rank_xp")))


func test_continue_shows_only_with_a_resume_file() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	var shown: Callable = func() -> bool: return _main._continue.visible
	assert_bool(shown.call()).is_false()
	_resume[0] = true
	_stack.push(MenuScreen.new())  # Covered, then back: the menu looks again.
	await await_idle_frame()
	_stack.pop()
	await await_idle_frame()
	assert_bool(shown.call()).is_true()


func test_a_route_nobody_registered_is_disabled_and_a_registered_one_opens() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	var buttons: Array[Button] = _buttons()
	for button: Button in buttons:
		assert_bool(button.disabled).is_true()
	_routes.register(MenuRoutes.SETTINGS, MenuScreen.new)
	_stack.push(MenuScreen.new())
	_stack.pop()
	await await_idle_frame()
	var settings: Button = _main._routed.find_key(MenuRoutes.SETTINGS) as Button
	assert_bool(settings.disabled).is_false()
	settings.pressed.emit()
	await await_idle_frame()
	assert_int(_stack.depth()).is_equal(2)
	assert_object(_stack.current()).is_not_same(_main)


func test_back_at_the_root_asks_the_quit_question() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]), false)
	_stack.back()
	assert_bool(_stack.is_asking_to_quit()).is_true()
	assert_int(_quits[0]).is_equal(0)


func test_the_title_the_sides_and_the_tagline_show() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	var texts: Array[String] = []
	_collect(_main.column, texts)
	assert_array(texts).contains(
		["TREADLINE", "Oil and gas against wind and sun. Choose your side."]
	)
	assert_array(texts).contains(["DERRICK LEAGUE", "LUMEN ACCORD"])


## `consent`: the fake ad service has consent, so the banner shows (false: no banner).
func test_a_route_registered_while_shown_enables_its_button() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	var tutorial: Button = _main._routed.find_key(MenuRoutes.TUTORIAL) as Button
	assert_bool(tutorial.disabled).is_true()
	_routes.register(MenuRoutes.TUTORIAL, MenuScreen.new)
	assert_bool(tutorial.disabled).is_false()
	_routes.clear()
	assert_bool(tutorial.disabled).is_true()


func test_the_version_line_shows_the_version_or_only_the_copyright() -> void:
	ProjectSettings.set_setting(VERSION_KEY, "1.2.3")
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	var texts: Array[String] = []
	_collect(_main.column, texts)
	assert_array(texts).contains(["v1.2.3 · © AppCode ApS"])
	_close()
	ProjectSettings.set_setting(VERSION_KEY, "")
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	texts.clear()
	_collect(_main.column, texts)
	assert_array(texts).contains(["© AppCode ApS"])
	assert_bool(texts.any(func(text: String) -> bool: return text.contains(" · "))).is_false()


func test_the_xp_bar_at_the_top_rank_is_full() -> void:
	_save.call("set_section", &"progress", {"xp": 5000})
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	var top: int = int(_progression.call("max_rank"))
	assert_str(_main._rank_label.text).contains("RANK %d" % top)
	assert_float(_main._xp_bar.value).is_equal(_main._xp_bar.max_value)
	assert_str(_main._xp_label.text).is_equal("5000 XP")


func test_the_xp_bar_exactly_at_a_rank_floor_is_empty() -> void:
	_save.call("set_section", &"progress", {"xp": 250})
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_str(_main._rank_label.text).contains("RANK 3")
	assert_float(_main._xp_bar.value).is_equal(_main._xp_bar.min_value)
	assert_float(_main._xp_bar.min_value).is_equal(250.0)


func _open(profile: UiMetrics, consent: bool) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	if _harness == null:
		_harness = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
		_ads = _harness.make(consent)
		_ads.fake_auto_close = false  # The strip stays, so the band can be lined up with it.
		add_child(_ads)
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_stack.quit_handler = func() -> void: _quits[0] += 1
	_main = MainMenu.new()
	_main.routes = _routes
	_main.progression = _progression
	_main.ad_service = _ads
	_main.resume_check = func() -> bool: return _resume[0]
	_stack.push(_main)
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _buttons() -> Array[Button]:
	var found: Array[Button] = []
	for child: Node in _main.column.get_children():
		if child is Button and (child as Button).visible:
			found.append(child as Button)
	return found


func _collect(node: Node, into: Array[String]) -> void:
	if node is Label:
		into.append((node as Label).text)
	for child: Node in node.get_children():
		_collect(child, into)


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	assert_bool(false).override_failure_message("no profile for %s" % size).is_true()
	return null
