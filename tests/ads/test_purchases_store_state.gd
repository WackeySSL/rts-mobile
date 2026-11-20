extends GdUnitTestSuite
## P445: `Purchases.store_state` and the price query over the FakeBilling knobs. UNKNOWN until the
## connection and the product query answer; UNAVAILABLE without a store, a product or a price, and
## when the latest attempt got no answer within `billing_timeout_ms`; else AVAILABLE. A known price
## is latched for the session (also across a reset on reconnect) and cleared when the product is
## delisted. A failed or stuck attempt is issued again once per interval, and a fresh attempt gets a
## fresh deadline (also with an answer one step late). The injected clock drives all of it.

const PRODUCT: String = "remove_ads"
const TIMEOUT_MS: int = 8000

var _fake: FakeBilling
var _purchases: Purchases
var _clock_ms: int = 0


func before_test() -> void:
	_clock_ms = 0
	_fake = FakeBilling.new()
	_purchases = _make(_fake)


func _make(backend: BillingBackend) -> Purchases:
	return Purchases.new(backend, PRODUCT, func() -> bool: return false)


func test_store_state_follows_the_connection_and_the_product_query() -> void:
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.UNKNOWN)  # Never asked.
	_purchases.price_text()  # Starts the connection and the query; the fake answers at once.
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.AVAILABLE)
	var slow: FakeBilling = FakeBilling.new()
	slow.connect_never_answers = true
	var connecting: Purchases = _make(slow)
	connecting.price_text()
	assert_int(connecting.store_state()).is_equal(Purchases.StoreState.UNKNOWN)
	var loading: FakeBilling = FakeBilling.new()
	loading.product_never_answers = true
	var product: Purchases = _make(loading)
	product.price_text()
	assert_int(product.store_state()).is_equal(Purchases.StoreState.UNKNOWN)


func test_store_state_is_unavailable_without_a_store_or_a_product() -> void:
	_fake.store_available = false
	_purchases.price_text()
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	var missing: FakeBilling = FakeBilling.new()
	missing.product_found = false
	var lacking: Purchases = _make(missing)
	lacking.price_text()
	assert_int(lacking.store_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	assert_int(_make(BillingBackend.new()).store_state()).is_equal(Purchases.StoreState.UNAVAILABLE)


func test_a_known_price_stays_available_when_the_connection_drops_later() -> void:
	_purchases.price_text()
	_fake.connect_never_answers = true
	_fake.connect_store()  # Connecting again, and it never ends.
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.AVAILABLE)


func _now() -> int:
	return _clock_ms


func _ask() -> String:
	return _purchases.price_text(_now, TIMEOUT_MS)


func _state() -> int:
	return _purchases.store_state(_now, TIMEOUT_MS)


func test_unknown_turns_unavailable_at_the_timeout_since_the_first_query() -> void:
	_fake.connect_never_answers = true
	_ask()
	_clock_ms = TIMEOUT_MS - 1
	assert_int(_state()).is_equal(Purchases.StoreState.UNKNOWN)
	_clock_ms = TIMEOUT_MS
	assert_int(_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.UNKNOWN)  # No clock, no limit.


func test_a_known_price_is_latched_when_the_backend_resets_on_a_reconnect() -> void:
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)
	_fake.reset_product_on_connect = true
	_fake.connect_never_answers = true
	_fake.connect_store()  # Reconnecting: the fake forgets the product and its price.
	assert_str(_fake.price_text(PRODUCT)).is_empty()
	assert_int(_fake.product_state(PRODUCT)).is_equal(BillingBackend.QueryState.IDLE)
	assert_int(_state()).is_equal(Purchases.StoreState.AVAILABLE)
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)


func test_a_failed_connection_is_retried_at_most_once_per_interval() -> void:
	_fake.store_available = false
	assert_str(_ask()).is_empty()  # Connecting ends UNAVAILABLE.
	assert_str(_ask()).is_empty()  # The failure is seen: the wait starts now.
	_fake.store_available = true
	_clock_ms = TIMEOUT_MS - 1
	assert_str(_ask()).is_empty()  # Too early: no retry.
	assert_int(_fake.connection_state()).is_equal(BillingBackend.ConnState.UNAVAILABLE)
	_clock_ms = TIMEOUT_MS
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)  # The retry ran.
	assert_int(_state()).is_equal(Purchases.StoreState.AVAILABLE)


func test_a_failed_product_is_retried_at_most_once_per_interval() -> void:
	_fake.product_found = false
	assert_str(_ask()).is_empty()
	assert_int(_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	assert_str(_ask()).is_empty()  # The failure is seen: the wait starts now.
	_fake.product_found = true
	_clock_ms = TIMEOUT_MS - 1
	assert_str(_ask()).is_empty()
	assert_int(_fake.product_state(PRODUCT)).is_equal(BillingBackend.QueryState.FAILED)
	_clock_ms = TIMEOUT_MS
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)
	assert_int(_state()).is_equal(Purchases.StoreState.AVAILABLE)
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.AVAILABLE)


func test_without_a_clock_a_failure_is_never_retried() -> void:
	_fake.store_available = false
	_purchases.price_text()
	_fake.store_available = true
	_purchases.price_text()
	assert_int(_fake.connection_state()).is_equal(BillingBackend.ConnState.UNAVAILABLE)


func test_a_stuck_connection_is_retried_after_the_interval() -> void:
	_fake.connect_never_answers = true
	_ask()
	_clock_ms = TIMEOUT_MS - 1
	_ask()
	assert_int(_fake.connection_state()).is_equal(BillingBackend.ConnState.CONNECTING)
	_fake.connect_never_answers = false  # The next visit finds the store reachable.
	_clock_ms = TIMEOUT_MS
	assert_str(_ask()).is_empty()  # The deadline shows as final first,
	assert_int(_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)  # and the next visit retries.
	assert_int(_state()).is_equal(Purchases.StoreState.AVAILABLE)


func test_a_stuck_product_query_is_retried_after_the_interval() -> void:
	_fake.product_never_answers = true
	_ask()
	assert_int(_fake.product_state(PRODUCT)).is_equal(BillingBackend.QueryState.LOADING)
	_fake.product_never_answers = false
	_clock_ms = TIMEOUT_MS - 1
	assert_str(_ask()).is_empty()
	_clock_ms = TIMEOUT_MS
	assert_str(_ask()).is_empty()  # The deadline shows as final first,
	assert_int(_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)  # and the next visit retries.


func test_a_retry_restarts_the_deadline_so_a_late_answer_never_collapses() -> void:
	_fake.store_available = false
	_ask()  # Visit 1: offline.
	assert_int(_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	_fake.store_available = true
	_fake.late_answers = true
	_clock_ms = TIMEOUT_MS * 3  # Visit 2, long after the first attempt.
	_ask()  # The retry connects; the answer is a step away.
	assert_int(_state()).is_equal(Purchases.StoreState.UNKNOWN)
	_fake.answer_late()
	_ask()  # Connected: the product is asked.
	assert_int(_state()).is_equal(Purchases.StoreState.UNKNOWN)
	_fake.answer_late()
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)
	assert_int(_state()).is_equal(Purchases.StoreState.AVAILABLE)
	# A fresh attempt that never answers is final only after its own interval.
	var stuck: FakeBilling = FakeBilling.new()
	stuck.connect_never_answers = true
	var other: Purchases = _make(stuck)
	other.price_text(_now, TIMEOUT_MS)
	_clock_ms += TIMEOUT_MS - 1
	assert_int(other.store_state(_now, TIMEOUT_MS)).is_equal(Purchases.StoreState.UNKNOWN)
	_clock_ms += 1
	assert_int(other.store_state(_now, TIMEOUT_MS)).is_equal(Purchases.StoreState.UNAVAILABLE)


func test_a_delisted_product_clears_the_latched_price() -> void:
	assert_str(_ask()).is_equal(FakeBilling.DEFAULT_PRICE)
	_fake.product_found = false
	_fake.query_product(PRODUCT)  # The store now ends the query FAILED while connected.
	assert_str(_ask()).is_empty()
	assert_int(_state()).is_equal(Purchases.StoreState.UNAVAILABLE)


func test_a_latched_price_with_a_stuck_connection_never_launches_a_purchase() -> void:
	_ask()
	_fake.connect_never_answers = true
	_fake.connect_store()  # CONNECTING, and it never ends.
	var grants: Array[bool] = []
	_purchases.entitlement_changed.connect(func(has: bool) -> void: grants.append(has))
	var out: Array = AdServiceHarness.start(
		func() -> bool: return await _purchases.purchase(_now, TIMEOUT_MS)
	)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await AdServiceHarness.frames(3)
	assert_array(out).contains_exactly([false])
	assert_array(_fake.launches).is_empty()
	assert_array(grants).is_empty()
