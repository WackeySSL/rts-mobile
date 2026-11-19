extends GdUnitTestSuite
## Plan P445: the Remove ads rows keep their space while the store answers. Reserved rows are
## invisible and untouchable at full height; unavailable at the moment they take their place
## collapses them for the visit; a late answer (a price or "unavailable") never resizes. The
## store is the fake one (FakeBilling knobs) or a CountingPurchaseService; the clock is injected.
## The six-size rects of what lies below are in `test_menu_six_sizes.gd`.

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


func test_unavailable_when_the_rows_take_their_place_collapses_them_for_the_visit() -> void:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	fake.answer("")
	var rows: RemoveAdsRows = _rows(fake)
	assert_bool(rows.visible).is_false()
	assert_bool(rows.remove_button.visible).is_false()
	assert_bool(rows.restore_button.visible).is_false()
	assert_bool(rows._timer.is_stopped()).is_true()
	fake.answer(PRICE)  # Decided once per visit: a late price never resizes either.
	rows.refresh()
	assert_bool(rows.visible).is_false()
	var slot: Node = rows.get_parent()
	slot.remove_child(rows)
	slot.add_child(rows)  # Back from a screen: a new visit.
	await await_idle_frame()
	_assert_live(rows)


func test_a_late_unavailable_keeps_the_reserved_space_empty_and_never_resizes() -> void:
	var fake: CountingPurchaseService = _answering()
	var rows: RemoveAdsRows = _rows(fake)
	var size_before: Vector2 = rows.get_combined_minimum_size()
	rows.refresh()
	fake.answer("")  # The store turns out unavailable.
	rows._timer.timeout.emit()
	_assert_reserved(rows)
	assert_vector(rows.get_combined_minimum_size()).is_equal(size_before)
	assert_bool(rows._timer.is_stopped()).is_true()
	rows.remove_button.pressed.emit()  # Nothing to tap: no call.
	rows.restore_button.pressed.emit()
	assert_int(fake.purchases + fake.restores).is_equal(0)


func test_reserved_rows_have_the_height_of_live_ones_and_take_no_touch() -> void:
	var fake: CountingPurchaseService = _answering()
	var rows: RemoveAdsRows = _rows(fake)
	await await_idle_frame()
	var reserved: float = rows.get_combined_minimum_size().y
	var remove_h: float = rows.remove_button.get_combined_minimum_size().y
	assert_float(reserved).is_greater_equal(remove_h * 2.0)
	assert_int(rows.remove_button.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(rows.restore_button.focus_mode).is_equal(Control.FOCUS_NONE)
	fake.answer(PRICE)
	rows.refresh()
	await await_idle_frame()
	assert_float(rows.get_combined_minimum_size().y).is_equal(reserved)


func test_the_fake_billing_knobs_drive_the_store_state_and_the_rows() -> void:
	var store: FakeBilling = AdServiceHarness.billing(_service)
	store.connect_never_answers = true  # Still connecting: reserved, polling.
	var rows: RemoveAdsRows = _rows(_service)
	assert_int(_service.store_state()).is_equal(Purchases.StoreState.UNKNOWN)
	_assert_reserved(rows)
	store.connect_never_answers = false
	store.connect_store()
	rows.refresh()
	_assert_live(rows)
	assert_int(_service.store_state()).is_equal(Purchases.StoreState.AVAILABLE)


## A store that has not answered yet (no price).
func _answering() -> CountingPurchaseService:
	var fake: CountingPurchaseService = auto_free(CountingPurchaseService.new())
	fake.price = ""
	fake.state = Purchases.StoreState.UNKNOWN
	return fake


func _assert_live(rows: RemoveAdsRows) -> void:
	assert_bool(rows.remove_button.visible).is_true()
	assert_bool(rows.restore_button.visible).is_true()
	assert_float(rows.modulate.a).is_equal(1.0)
	assert_int(rows.remove_button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(rows.remove_button.disabled).is_false()


## The space is kept (visible to layout) but nothing shows and nothing can be tapped.
func _assert_reserved(rows: RemoveAdsRows) -> void:
	assert_bool(rows.visible).is_true()
	assert_bool(rows.remove_button.visible).is_true()
	assert_bool(rows.restore_button.visible).is_true()
	assert_float(rows.modulate.a).is_equal(0.0)
	assert_int(rows.remove_button.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(rows.remove_button.disabled).is_true()


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
	_clock_ms = ARM_MS
	return rows
