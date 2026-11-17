extends GdUnitTestSuite
## A menu screen and its foot slot at the six sizes of ADR 0015 section 6 (plan P522): one column
## on the short side inside the safe rect, buttons of 48 dp or more, the slot at the very bottom of
## the safe area with nothing below it, 0 tall while empty, and as tall as its band once one is
## hosted (the band owns its height, also when it changes).

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const AdBandAsserts: GDScript = preload("res://tests/ui/support/ad_band_asserts.gd")
const TOLERANCE_PX: float = 0.5
## A phone with a cutout at the top and a gesture bar below, as window px of the portrait profile.
const PORTRAIT_CUTOUT: Rect2i = Rect2i(0, 100, 1080, 2137)

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = false
var _menu: Control
var _stack: MenuStack
var _screen: MenuScreen
var _service: Node
var _harness: RefCounted


func before() -> void:
	assert_bool(UiScale.has_override()).override_failure_message("override leaked").is_false()
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back


func after_test() -> void:
	# The menu leaves it off for good (ADR 0043 section 4); this suite puts it back for the others.
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	if is_instance_valid(_service):
		remove_child(_service)
		_service.free()
	_service = null
	if _harness != null:
		_harness.dispose()  # Frees the harness's own SaveService and its temp files (P407).
		_harness = null


func test_the_column_and_the_slot_hold_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var label: String = str(size)
		var safe: Rect2 = UiScale.safe_rect_base()
		var column: Control = _screen.column
		var rect: Rect2 = column.get_global_rect()
		(
			assert_bool(safe.grow(TOLERANCE_PX).encloses(rect))
			. override_failure_message(label)
			. is_true()
		)
		var short_side: float = minf(safe.size.x, safe.size.y)
		assert_float(rect.size.x).override_failure_message(label).is_less_equal(short_side)
		assert_float(rect.get_center().x).override_failure_message(label).is_equal_approx(
			safe.get_center().x, 1.0
		)
		for child: Node in column.get_children():
			var button: Button = child as Button
			var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
			var button_rect: Rect2 = button.get_global_rect()
			assert_bool(button_rect.size.y >= floor_px).override_failure_message(label).is_true()
		_close()
		UiScale.clear_override()


func test_a_long_column_scrolls_inside_the_safe_rect_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		for index: int in range(40):
			_screen.add_button("MORE %d" % index, func() -> void: pass)
		await await_idle_frame()
		await await_idle_frame()
		var label: String = str(size)
		var bar: VScrollBar = _screen.scroll.get_v_scroll_bar()
		assert_float(bar.max_value).override_failure_message(label).is_greater(bar.page)
		var safe: Rect2 = UiScale.safe_rect_base()
		(
			assert_bool(safe.grow(TOLERANCE_PX).encloses(_screen.scroll.get_global_rect()))
			. override_failure_message(label + " scroll")
			. is_true()
		)
		var column: Rect2 = _screen.column.get_global_rect()
		assert_float(column.position.x).override_failure_message(label).is_greater_equal(
			_screen.scroll.get_global_rect().position.x - TOLERANCE_PX
		)
		assert_float(column.end.x).override_failure_message(label).is_less_equal(
			_screen.scroll.get_global_rect().end.x - bar.size.x + TOLERANCE_PX
		)
		_close()
		UiScale.clear_override()


func test_the_empty_slot_is_0_tall_and_at_the_safe_bottom_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var slot: AdBannerSlot = _screen.slot
		var label: String = str(size)
		assert_bool(slot.has_band()).is_false()
		assert_float(slot.size.y).override_failure_message(label).is_equal_approx(0.0, 0.01)
		_assert_on_safe_bottom(slot, label)
		_close()
		UiScale.clear_override()


func test_a_filled_slot_is_as_tall_as_its_band_and_follows_the_bands_size() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var slot: AdBannerSlot = _screen.slot
		var band: AdBannerBand = _real_band()
		assert_bool(slot.host(band)).is_true()
		await await_idle_frame()
		await await_idle_frame()
		var label: String = str(size)
		assert_float(band.reserved_px()).is_greater(0.0)
		assert_float(slot.size.y).override_failure_message(label).is_equal_approx(
			band.reserved_px(), 1.0
		)
		_assert_on_safe_bottom(slot, label)
		AdBandAsserts.assert_lines_up(self, band, _service, _screen.scroll, band.gap_dp(), label)
		var scroll_end: float = _screen.scroll.get_global_rect().end.y
		assert_float(scroll_end).override_failure_message(label).is_less_equal(
			slot.get_global_rect().position.y + 0.5
		)
		var before_px: float = slot.size.y
		band.start_page = true  # The band owns its height: the slot follows its new minimum.
		await await_idle_frame()
		await await_idle_frame()
		assert_float(slot.size.y).override_failure_message(label).is_greater(before_px)
		assert_float(slot.size.y).override_failure_message(label).is_equal_approx(
			band.reserved_px(), 1.0
		)
		AdBandAsserts.assert_lines_up(self, band, _service, _screen.scroll, band.gap_dp(), label)
		_close()
		UiScale.clear_override()


func test_the_slot_follows_the_minimum_size_of_any_hosted_control() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var slot: AdBannerSlot = _screen.slot
	var band: Control = Control.new()
	band.custom_minimum_size = Vector2(0.0, UiScale.dp(66.0))
	assert_bool(slot.host(band)).is_true()
	await await_idle_frame()
	await await_idle_frame()
	assert_float(slot.size.y).is_equal_approx(UiScale.dp(66.0), 1.0)
	_assert_on_safe_bottom(slot, "66 dp")
	band.custom_minimum_size = Vector2(0.0, UiScale.dp(114.0))
	await await_idle_frame()
	await await_idle_frame()
	assert_float(slot.size.y).is_equal_approx(UiScale.dp(114.0), 1.0)
	_assert_on_safe_bottom(band, "114 dp")
	band.custom_minimum_size = Vector2.ZERO
	await await_idle_frame()
	await await_idle_frame()
	assert_float(slot.size.y).is_equal_approx(0.0, 0.01)


func test_re_hosting_the_same_band_connects_it_once() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var slot: AdBannerSlot = _screen.slot
	var band: AdBannerBand = _real_band()
	assert_bool(slot.host(band)).is_true()
	assert_bool(slot.host(band)).is_false()
	slot.remove_child(band)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(slot.has_band()).is_false()
	assert_bool(slot.host(band)).is_true()  # Re-hosted: the old connection is still there.
	var ours: int = 0
	for connection: Dictionary in band.minimum_size_changed.get_connections():
		if (connection["callable"] as Callable) == Callable(slot, "_relayout"):
			ours += 1
	assert_int(ours).is_equal(1)


func test_the_slot_hosts_one_band_only_and_lets_go_of_a_removed_one() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	var slot: AdBannerSlot = _screen.slot
	var first: Control = Control.new()
	first.custom_minimum_size = Vector2(0.0, UiScale.dp(50.0))
	assert_bool(slot.host(first)).is_true()
	var second: Control = auto_free(Control.new())
	assert_bool(slot.host(second)).is_false()
	assert_bool(slot.host(null)).is_false()
	assert_int(slot.get_child_count()).is_equal(1)
	slot.remove_child(first)
	first.free()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(slot.has_band()).is_false()
	assert_float(slot.size.y).is_equal_approx(0.0, 0.01)


func test_the_slot_stays_at_the_safe_bottom_under_a_cutout_and_a_gesture_bar() -> void:
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(UiProfiles.with_safe_area(portrait, PORTRAIT_CUTOUT))
	var slot: AdBannerSlot = _screen.slot
	var band: Control = Control.new()
	band.custom_minimum_size = Vector2(0.0, UiScale.dp(50.0))
	slot.host(band)
	await await_idle_frame()
	await await_idle_frame()
	var safe: Rect2 = UiScale.safe_rect_base()
	_assert_on_safe_bottom(slot, "cutout")
	assert_float(safe.end.y).is_less(get_window().get_visible_rect().end.y)
	assert_float(safe.position.y).is_greater(0.0)
	assert_bool(safe.grow(TOLERANCE_PX).encloses(_screen.column.get_global_rect())).is_true()


func _open(profile: UiMetrics) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_screen = MenuScreen.new()
	_stack.push(_screen)
	await await_idle_frame()
	for text: String in ["PLAY", "SETTINGS", "HOW TO PLAY"]:
		_screen.add_button(text, func() -> void: pass)
	await await_idle_frame()
	await await_idle_frame()


func _close() -> void:
	remove_child(_menu)
	_menu.free()
	_menu = null


## A real band (P430) with the fake service injected; the service draws the "Test ad" strip.
func _real_band() -> AdBannerBand:
	if not is_instance_valid(_service):
		_harness = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
		_service = _harness.make(true)
		_service.fake_auto_close = false  # The strip stays, so the band can be lined up with it.
		add_child(_service)
	var band: AdBannerBand = AdBannerBand.new()
	band.service = _service
	return band


## The control's bottom edge is the safe rect's bottom, within half a base px: nothing is below it.
func _assert_on_safe_bottom(control: Control, label: String) -> void:
	assert_float(control.get_global_rect().end.y).override_failure_message(label).is_equal_approx(
		UiScale.safe_rect_base().end.y, TOLERANCE_PX
	)


## The profile whose window is `size`: the landscape ones, then the portrait ones.
func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null
