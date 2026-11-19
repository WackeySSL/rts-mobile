extends GdUnitTestSuite
## The Remove ads and Restore rows (plan P434): visibility for owned, not owned and no store, the
## store's price, one call per tap, the busy state, `entitlement_changed`, the widget outside a
## slot, Settings opened in a match (no slot, no rows, no Privacy row, Michael 2026-11-17), 48 dp,
## and nothing below the slot moving at the six sizes of ADR 0015 section 6.

const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const TOLERANCE_PX: float = 0.5
const PRICE: String = "kr 19,00"


## A service that counts calls and keeps each one open until `release`.
class CountingService:
	extends Node
	signal entitlement_changed(has_remove_ads: bool)
	signal release
	var price: String = PRICE
	var owned: bool = false
	var purchases: int = 0
	var restores: int = 0

	func has_remove_ads() -> bool:
		return owned

	func is_privacy_options_required() -> bool:
		return false

	func remove_ads_price_text() -> String:
		return price

	func purchase_remove_ads() -> bool:
		purchases += 1
		await release
		return owned

	func restore_purchases() -> bool:
		restores += 1
		await release
		return owned


var _window_size_before: Vector2i
var _menu: Control
var _screen: SettingsScreen
var _harness: AdServiceHarness
var _service: Node
var _in_match: bool = false


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


func test_not_owned_with_a_store_shows_both_rows_and_the_price() -> void:
	var rows: RemoveAdsRows = _rows(_service)
	assert_bool(rows.visible).is_true()
	assert_bool(rows.remove_button.visible).is_true()
	assert_bool(rows.restore_button.visible).is_true()
	(
		assert_bool(rows.remove_button.text.contains(AdServiceHarness.billing(_service).price))
		. is_true()
	)
	assert_str(rows.restore_button.text).is_equal("RESTORE PURCHASES")


func test_owned_hides_remove_ads_and_keeps_restore() -> void:
	_service._ledger.remove_ads = true
	var rows: RemoveAdsRows = _rows(_service)
	assert_bool(rows.remove_button.visible).is_false()
	assert_bool(rows.restore_button.visible).is_true()


func test_no_store_hides_both_rows_and_the_slot() -> void:
	AdServiceHarness.billing(_service).store_available = false
	var rows: RemoveAdsRows = _rows(_service)
	assert_bool(rows.remove_button.visible).is_false()
	assert_bool(rows.restore_button.visible).is_false()
	assert_bool(rows.visible).is_false()


func test_a_late_price_shows_the_rows_and_no_service_hides_them() -> void:
	var fake: CountingService = auto_free(CountingService.new())
	fake.price = ""
	var rows: RemoveAdsRows = _rows(fake)
	assert_bool(rows.visible).is_false()
	fake.price = PRICE
	rows.refresh()  # What the poll timer does.
	assert_bool(rows.remove_button.visible).is_true()
	var bare: RemoveAdsRows = _rows(auto_free(Node.new()))
	assert_bool(bare.visible).is_false()


func test_a_tap_calls_the_service_once_and_a_second_tap_does_nothing() -> void:
	var fake: CountingService = auto_free(CountingService.new())
	var rows: RemoveAdsRows = _rows(fake)
	rows.remove_button.pressed.emit()
	rows.remove_button.pressed.emit()
	rows.restore_button.pressed.emit()  # Also ignored while one call runs.
	assert_int(fake.purchases).is_equal(1)
	assert_int(fake.restores).is_equal(0)
	fake.release.emit()
	await await_idle_frame()
	rows.restore_button.pressed.emit()
	assert_int(fake.restores).is_equal(1)
	fake.release.emit()


func test_busy_disables_both_rows_labels_the_tapped_one_and_restores_after() -> void:
	var fake: CountingService = auto_free(CountingService.new())
	var rows: RemoveAdsRows = _rows(fake)
	var before_text: String = rows.remove_button.text
	rows.restore_button.pressed.emit()
	assert_bool(rows.remove_button.disabled).is_true()
	assert_bool(rows.restore_button.disabled).is_true()
	assert_str(rows.restore_button.text).is_equal("WORKING…")
	assert_str(rows.remove_button.text).is_equal(before_text)
	fake.release.emit()
	await await_idle_frame()
	assert_bool(rows.remove_button.disabled).is_false()
	assert_bool(rows.restore_button.disabled).is_false()
	assert_str(rows.restore_button.text).is_equal("RESTORE PURCHASES")
	rows.remove_button.pressed.emit()
	assert_str(rows.remove_button.text).is_equal("WORKING…")
	fake.release.emit()


func test_a_real_purchase_hides_remove_ads_through_the_entitlement_signal() -> void:
	var store: FakeBilling = AdServiceHarness.billing(_service)
	store.next_outcome = BillingBackend.Outcome.PURCHASED
	var rows: RemoveAdsRows = _rows(_service)
	rows.remove_button.pressed.emit()
	await AdServiceHarness.frames(3)
	assert_bool(_service.has_remove_ads()).is_true()
	assert_bool(rows.remove_button.visible).is_false()
	assert_bool(rows.restore_button.visible).is_true()
	assert_bool(rows.restore_button.disabled).is_false()
	assert_int(store.launches.size()).is_equal(1)


func test_a_cancelled_purchase_leaves_the_rows_as_they_were() -> void:
	var rows: RemoveAdsRows = _rows(_service)
	rows.remove_button.pressed.emit()
	await AdServiceHarness.frames(3)
	assert_bool(rows.remove_button.visible).is_true()
	assert_bool(rows.remove_button.disabled).is_false()
	(
		assert_bool(rows.remove_button.text.contains(AdServiceHarness.billing(_service).price))
		. is_true()
	)


func test_outside_a_slot_the_widget_never_shows() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var rows: RemoveAdsRows = RemoveAdsRows.new()
	rows.service = _service
	host.add_child(rows)
	assert_bool(rows.visible).is_false()
	assert_bool(rows.remove_button.visible).is_false()
	assert_bool(rows.restore_button.visible).is_false()


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
	var fake: CountingService = auto_free(CountingService.new())
	_service = fake
	for size: Vector2i in ScreenSizes.ALL:
		fake.price = PRICE
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
		# No store: the slot is 0 tall and the controls below only moved up by its height.
		fake.price = ""
		rows.refresh()
		await AdServiceHarness.frames(2)
		assert_bool(slot.visible).override_failure_message(label).is_false()
		_assert_moved(shown, _below(slot), slot_shown + float(_gap_px()), label + " hidden")
		_close()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	UiScale.clear_override()


## The widget in a `PurchaseSlot` of its own, in the tree.
func _rows(service: Node) -> RemoveAdsRows:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var slot: VBoxContainer = VBoxContainer.new()
	slot.name = &"PurchaseSlot"
	host.add_child(slot)
	var rows: RemoveAdsRows = RemoveAdsRows.new()
	rows.service = service
	slot.add_child(rows)
	return rows


func _open(profile: UiMetrics) -> void:
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	var stack: MenuStack = _menu.get_node("MenuStack") as MenuStack
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
