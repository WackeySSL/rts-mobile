extends GdUnitTestSuite
## P406: the fake store's "Test purchase" sheet: Buy, Pending and Cancel end the purchase, the
## buttons are at least 48 dp, the box sits inside the safe rect and follows a viewport change, and
## nothing is drawn with auto close on.

const WINDOW: Vector2i = Vector2i(1280, 720)
const SAFE: Rect2i = Rect2i(60, 30, 1160, 660)

var _fake: FakeBilling


func after_test() -> void:
	UiScale.clear_override()


func _metrics(dpi: int) -> UiMetrics:
	return UiMetrics.create("Android", dpi, 1.0, 1.0, WINDOW, SAFE)


func _shown(outcomes: Array[int]) -> Node:
	var host: Node = auto_free(Node.new())
	add_child(host)
	_fake = FakeBilling.new()
	_fake.host = host
	_fake.auto_close = false
	_fake.draw_placeholders = true
	_fake.purchase_finished.connect(
		func(_id: String, outcome: BillingBackend.Outcome, _token: String) -> void:
			outcomes.append(outcome)
	)
	_fake.launch_purchase("remove_ads")
	return host


func test_each_button_ends_the_purchase_with_its_outcome() -> void:
	var cases: Dictionary = {
		"Buy": BillingBackend.Outcome.PURCHASED,
		"Pending": BillingBackend.Outcome.PENDING,
		"Cancel": BillingBackend.Outcome.CANCELED,
	}
	for label: String in cases:
		var outcomes: Array[int] = []
		var host: Node = _shown(outcomes)
		var layer: Node = host.get_node("FakeTestPurchase")
		assert_array(outcomes).override_failure_message(label).is_empty()
		(layer.find_child(label, true, false) as Button).pressed.emit()
		assert_array(outcomes).override_failure_message(label).contains_exactly([cases[label]])


func test_auto_close_draws_no_sheet() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var fake: FakeBilling = FakeBilling.new()
	fake.host = host
	fake.launch_purchase("remove_ads")
	assert_int(host.get_child_count()).is_equal(0)


func test_buttons_are_48_dp_inside_the_safe_rect_and_follow_a_viewport_change() -> void:
	UiScale.set_override(_metrics(480))
	var outcomes: Array[int] = []
	var host: Node = _shown(outcomes)
	var layer: Node = host.get_node("FakeTestPurchase")
	var area: Control = layer.get_node("SafeArea") as Control
	assert_object(Rect2(area.position, area.size)).is_equal(UiScale.safe_rect_base())
	var buy: Button = layer.find_child("Buy", true, false) as Button
	assert_float(buy.custom_minimum_size.x).is_greater_equal(UiScale.dp(48))
	assert_float(buy.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))
	UiScale.set_override(_metrics(240))
	host.get_viewport().size_changed.emit()
	assert_float(buy.custom_minimum_size.y).is_equal(UiScale.dp(FakeBillingSheet.BUTTON_MIN_DP.y))
	assert_float(buy.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))
