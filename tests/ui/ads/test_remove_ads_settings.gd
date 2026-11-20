extends GdUnitTestSuite
## Settings and the Remove ads rows (plan P434): opened in a match there is no slot, no rows and no
## Privacy row (Michael, 2026-11-17); the rows are 48 dp and nothing below the slot moves at the six
## sizes of ADR 0015 section 6; a screen pushed during a call leaves normal rows on Back; and the
## price is never the part that is cut.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const TOLERANCE_PX: float = 0.5
const ARM_MS: int = 10000
const PRICE: String = "kr 19,00"

var _window_size_before: Vector2i
var _menu: Control
var _screen: SettingsScreen
var _harness: AdServiceHarness
var _service: Node
var _in_match: bool = false
var _stack: MenuStack


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	PrefsRig.begin()
	_in_match = false
	_harness = AdServiceHarness.new()
	_service = auto_free(_harness.make())


func after_test() -> void:
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	_harness.dispose()
	PrefsRig.end()


func test_settings_opened_in_a_match_has_no_slot_no_rows_and_no_privacy_row() -> void:
	_in_match = true
	await _open(_profile_for(ScreenSizes.PORTRAIT[0]))
	assert_object(_screen.purchase_slot).is_null()
	assert_object(_screen.privacy_button).is_null()
	assert_object(_screen.find_child("PurchaseSlot", true, false)).is_null()
	assert_object(_screen.find_child("RemoveAdsRows", true, false)).is_null()
	assert_array(_all_of_type(_screen, "RemoveAdsRows")).is_empty()
	for button: Button in _buttons(_screen):
		assert_bool(button.text.contains("PRIVACY")).is_false()
		assert_bool(button.text.contains("REMOVE ADS")).is_false()
		assert_bool(button.text.contains("RESTORE")).is_false()


func test_the_rows_are_48_dp_and_nothing_below_the_slot_moves_at_the_six_sizes() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	_service = fake
	for size: Vector2i in ScreenSizes.ALL:
		fake.answer(PRICE)
		fake.owned = false
		await _open(_profile_for(size))
		var label: String = str(size)
		var slot: VBoxContainer = _screen.purchase_slot
		var rows: RemoveAdsRows = slot.get_child(0) as RemoveAdsRows
		assert_bool(slot.visible).override_failure_message(label).is_true()
		var floor_px: float = UiScale.dp(48.0) - TOLERANCE_PX
		var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
		for button: Button in [rows.remove_button, rows.restore_button]:
			var rect: Rect2 = button.get_global_rect()
			assert_float(rect.size.y).override_failure_message(label).is_greater_equal(floor_px)
			assert_bool(safe.encloses(rect)).override_failure_message(label).is_true()
		var shown: Array[Rect2] = _below(slot)
		var slot_shown: float = slot.size.y
		# Busy: the label changes, no rect does.
		rows.now_ms = func() -> int: return Time.get_ticks_msec() + ARM_MS
		rows.remove_button.pressed.emit()
		await AdServiceHarness.frames(2)
		_assert_same(shown, _below(slot), label + " busy")
		fake.release.emit()
		await AdServiceHarness.frames(2)
		_assert_same(shown, _below(slot), label + " after")
		# Owned: Remove ads leaves, Restore stays; only the slot's own height changes.
		fake.owned = true
		fake.entitlement_changed.emit(true)
		await AdServiceHarness.frames(2)
		assert_bool(slot.visible).override_failure_message(label).is_true()
		var owned: Array[Rect2] = _below(slot)
		_assert_moved(shown, owned, slot_shown - slot.size.y, label + " owned")
		# The store goes quiet after the rows took their place: the space stays, empty.
		fake.answer("")
		rows.refresh()
		await AdServiceHarness.frames(2)
		assert_bool(slot.visible).override_failure_message(label).is_true()
		_assert_same(owned, _below(slot), label + " late unavailable")
		_close()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	UiScale.clear_override()


func _open(profile: UiMetrics) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	var stack: MenuStack = _menu.get_node("MenuStack") as MenuStack
	_stack = stack
	stack.slide_ms = 0
	_screen = SettingsScreen.new()
	_screen.routes = MenuRoutes.new()
	_screen.ad_service = _service
	_screen.dev_enabled = func() -> bool: return false
	_screen.in_match = func() -> bool: return _in_match
	stack.push(_screen)
	for _frame: int in range(3):
		await await_idle_frame()


func _profile_for(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null


## The rects of the column's children after the slot.
func _below(slot: Control) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var after_slot: bool = false
	for child: Node in slot.get_parent().get_children():
		if child == slot:
			after_slot = true
		elif after_slot and child is Control and (child as Control).visible:
			out.append((child as Control).get_global_rect())
	return out


## `after` is `before` moved up by `rise` px: the same sizes and columns.
func _assert_moved(before: Array[Rect2], after: Array[Rect2], rise: float, label: String) -> void:
	assert_int(after.size()).override_failure_message(label).is_equal(before.size())
	for index: int in before.size():
		assert_vector(after[index].size).override_failure_message(label).is_equal(
			before[index].size
		)
		assert_float(after[index].position.x).is_equal_approx(before[index].position.x, 0.01)
		(
			assert_float(before[index].position.y - after[index].position.y)
			. override_failure_message(label)
			. is_equal_approx(rise, TOLERANCE_PX)
		)


func _assert_same(expected: Array[Rect2], actual: Array[Rect2], label: String) -> void:
	assert_int(actual.size()).override_failure_message(label).is_equal(expected.size())
	for index: int in expected.size():
		(
			assert_bool(actual[index].is_equal_approx(expected[index]))
			. override_failure_message(
				"%s %d: %s vs %s" % [label, index, expected[index], actual[index]]
			)
			. is_true()
		)


## The column's gap between rows: what is left of the slot's height when it hides.
func _gap_px() -> int:
	return roundi(UiScale.dp(MenuScreen.GAP_DP))


func _buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	for node: Node in root.find_children("*", "Button", true, false):
		out.append(node as Button)
	return out


func _all_of_type(root: Node, script_name: String) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script() as Script
		if script != null and script.get_global_name() == script_name:
			out.append(node)
	return out


func test_settings_pushing_a_screen_during_a_call_comes_back_with_normal_rows() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	_service = fake
	await _open(_profile_for(ScreenSizes.PORTRAIT[0]))
	var rows: RemoveAdsRows = _screen.remove_rows
	rows.now_ms = func() -> int: return Time.get_ticks_msec() + ARM_MS
	rows.restore_button.pressed.emit()
	assert_bool(_screen.on_back()).is_true()  # Back keeps Settings open while the call runs.
	_stack.push(auto_free(MenuScreen.new()))
	await await_idle_frame()
	fake.release.emit()
	await await_idle_frame()
	assert_bool(_screen.on_back()).is_false()
	_stack.pop()
	await await_idle_frame()
	assert_bool(rows.remove_button.disabled).is_false()
	assert_bool(rows.restore_button.disabled).is_false()
	assert_str(rows.restore_button.text).is_equal("RESTORE PURCHASES")
	assert_str(rows.remove_button.text).contains(PRICE)


func test_the_price_is_never_the_part_that_is_cut() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	_service = fake
	for price: String in ["US$ 2.99", "29,00 kr", "29,00 kr  /  US$ 2.99"]:
		fake.price = price
		await _open(_profile_for(ScreenSizes.PORTRAIT[0]))
		var button: Button = _screen.remove_rows.remove_button
		assert_str(button.text).ends_with(price)
		var font: Font = button.get_theme_font("font")
		var room: float = button.size.x - button.get_theme_stylebox("normal").get_minimum_size().x
		var width: float = (
			font
			. get_string_size(
				button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")
			)
			. x
		)
		assert_float(width).override_failure_message(price).is_less_equal(room)
		_close()
