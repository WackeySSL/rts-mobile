extends GdUnitTestSuite
## The Remove ads and Restore rows (plan P434), widget level: visibility for owned, not owned and
## no store, the store's price, the poll timer, one call per tap, the arm delay, the busy state and
## its restore (also after the widget left the tree), `entitlement_changed`, a refund and the widget
## outside a slot. The Settings-level checks are in `test_remove_ads_settings.gd`.

const ARM_MS: int = 10000
const PRICE: String = "kr 19,00"

var _harness: AdServiceHarness
var _service: Node
var _clock_ms: int = 0


func before_test() -> void:
	_clock_ms = 0
	_harness = AdServiceHarness.new()
	_service = auto_free(_harness.make())


func after_test() -> void:
	_harness.dispose()


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
	_harness.seed_section({"remove_ads": true})
	_service = auto_free(_harness.make())
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
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	fake.price = ""
	var rows: RemoveAdsRows = _rows(fake)
	assert_bool(rows.visible).is_false()
	assert_bool(rows._timer.is_stopped()).is_false()  # Polling while the price is empty.
	rows._timer.timeout.emit()
	assert_bool(rows.visible).is_false()
	assert_bool(rows._timer.is_stopped()).is_false()
	fake.price = PRICE
	rows._timer.timeout.emit()  # What the poll timer does.
	assert_bool(rows.remove_button.visible).is_true()
	assert_bool(rows._timer.is_stopped()).is_true()  # Stops once there is a price.
	var bare: RemoveAdsRows = _rows(auto_free(Node.new()))
	assert_bool(bare.visible).is_false()


func test_a_tap_calls_the_service_once_and_a_second_tap_does_nothing() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
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
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	var rows: RemoveAdsRows = _rows(fake)
	var before_text: String = rows.remove_button.text
	rows.restore_button.pressed.emit()
	assert_bool(rows.remove_button.disabled).is_true()
	assert_bool(rows.restore_button.disabled).is_true()
	assert_str(rows.restore_button.text).is_equal("RESTORING…")
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


## The widget in a `PurchaseSlot` of its own, in the tree.
func _rows(service: Node) -> RemoveAdsRows:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var slot: VBoxContainer = VBoxContainer.new()
	slot.name = &"PurchaseSlot"
	host.add_child(slot)
	var rows: RemoveAdsRows = RemoveAdsRows.new()
	rows.service = service
	rows.now_ms = func() -> int: return _clock_ms
	slot.add_child(rows)
	_clock_ms = ARM_MS  # The arm delay is over; `test_new_rows_ignore_...` keeps its own.
	return rows


func test_new_rows_ignore_touches_for_the_arm_delay() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	var rows: RemoveAdsRows = _rows(fake)
	fake.price = ""
	rows.refresh()  # The store goes away, then answers: the rows appear again.
	_clock_ms = 100000
	fake.price = PRICE
	rows.refresh()
	rows.remove_button.pressed.emit()
	assert_int(fake.purchases).is_equal(0)  # Just appeared: a stray tap does nothing.
	_clock_ms += AdsSettingsDef.load_default().reward_arm_ms
	rows.remove_button.pressed.emit()
	assert_int(fake.purchases).is_equal(1)
	fake.release.emit()


func test_busy_clears_when_the_widget_left_the_tree_during_the_call() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	var rows: RemoveAdsRows = _rows(fake)
	var host: Node = rows.get_parent().get_parent()
	rows.restore_button.pressed.emit()
	assert_bool(rows.is_busy()).is_true()
	remove_child(host)  # Settings under a pushed screen.
	fake.release.emit()
	await await_idle_frame()
	assert_bool(rows.is_busy()).is_false()
	assert_bool(rows.remove_button.disabled).is_false()
	assert_bool(rows.restore_button.disabled).is_false()
	assert_str(rows.restore_button.text).is_equal("RESTORE PURCHASES")
	add_child(host)
	assert_str(rows.remove_button.text).contains(PRICE)


func test_an_entitlement_change_off_the_tree_is_safe_and_shows_on_return() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	var rows: RemoveAdsRows = _rows(fake)
	var host: Node = rows.get_parent().get_parent()
	remove_child(host)
	fake.owned = true
	fake.price = ""
	fake.entitlement_changed.emit(true)  # No timer may start outside the tree.
	assert_bool(rows._timer.is_stopped()).is_true()
	fake.price = PRICE
	add_child(host)  # The enter-tree refresh catches up.
	assert_bool(rows.remove_button.visible).is_false()
	assert_bool(rows.restore_button.visible).is_true()


func test_a_refund_shows_remove_ads_again() -> void:
	var store: FakeBilling = AdServiceHarness.billing(_service)
	store.next_outcome = BillingBackend.Outcome.PURCHASED
	var rows: RemoveAdsRows = _rows(_service)
	rows.remove_button.pressed.emit()
	await AdServiceHarness.frames(3)
	assert_bool(rows.remove_button.visible).is_false()
	store.refund()  # The store no longer lists it; the restore's answer is the truth.
	await _service.restore_purchases()
	await AdServiceHarness.frames(2)
	assert_bool(_service.has_remove_ads()).is_false()
	assert_bool(rows.remove_button.visible).is_true()
	assert_str(rows.remove_button.text).contains(store.price)
