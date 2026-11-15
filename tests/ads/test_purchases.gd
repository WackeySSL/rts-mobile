extends GdUnitTestSuite
## P406: Purchases over the FakeBilling. PENDING is never granted, a purchase is acknowledged once,
## a refund clears the entitlement, offline keeps the cache, and the deadline applies only before
## the store sheet shows. The clock is fake: the timeouts never read wall time.

const PRODUCT: String = "remove_ads"
const TIMEOUT_MS: int = 8000

var _clock_ms: int = 0
var _fake: FakeBilling
var _purchases: Purchases
var _changes: Array[bool] = []


func before_test() -> void:
	_clock_ms = 0
	_changes = []
	_fake = FakeBilling.new()
	_purchases = Purchases.new(_fake, PRODUCT)
	_purchases.entitlement_changed.connect(func(has: bool) -> void: _changes.append(has))


func _now() -> int:
	return _clock_ms


func _buy() -> bool:
	return await _purchases.purchase(_now, TIMEOUT_MS)


func _restore() -> bool:
	return await _purchases.restore(_now, TIMEOUT_MS)


func test_price_text_comes_from_the_backend_and_is_empty_until_known() -> void:
	_fake.price = "29,00 kr."
	assert_str(_purchases.price_text()).is_equal("29,00 kr.")
	var unknown: FakeBilling = FakeBilling.new()
	unknown.product_found = false
	assert_str(Purchases.new(unknown, PRODUCT).price_text()).is_empty()
	var unavailable: FakeBilling = FakeBilling.new()
	unavailable.store_available = false
	assert_str(Purchases.new(unavailable, PRODUCT).price_text()).is_empty()
	assert_str(Purchases.new(BillingBackend.new(), PRODUCT).price_text()).is_empty()


func test_the_fake_shows_a_placeholder_price() -> void:
	assert_str(_purchases.price_text()).is_equal(FakeBilling.DEFAULT_PRICE)


func test_a_purchase_grants_acknowledges_once_and_emits_once() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await _buy()).is_true()
	assert_bool(_purchases.owned).is_true()
	assert_array(_fake.acknowledges).has_size(1)
	assert_array(_fake.launches).contains_exactly([PRODUCT])
	assert_array(_changes).contains_exactly([true])
	# Owned: a second purchase launches nothing, and a restore does not acknowledge again.
	assert_bool(await _buy()).is_true()
	assert_bool(await _restore()).is_true()
	assert_array(_fake.launches).has_size(1)
	assert_array(_fake.acknowledges).has_size(1)
	assert_array(_changes).has_size(1)


func test_pending_is_never_granted_and_not_acknowledged() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PENDING
	assert_bool(await _buy()).is_false()
	assert_bool(_purchases.owned).is_false()
	assert_array(_fake.acknowledges).is_empty()
	assert_array(_changes).is_empty()
	# A restore that lists it as pending does not grant it either.
	assert_bool(await _restore()).is_false()
	assert_bool(_purchases.owned).is_false()
	assert_array(_fake.acknowledges).is_empty()


func test_a_pending_purchase_paid_later_is_granted_and_acknowledged_once() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PENDING
	await _buy()
	var token: String = _fake.purchases[0][BillingBackend.KEY_TOKEN]
	_fake.complete_pending(token)
	assert_bool(_purchases.owned).is_true()
	assert_array(_fake.acknowledges).contains_exactly([token])
	assert_array(_changes).contains_exactly([true])


func test_cancel_and_failure_grant_nothing() -> void:
	assert_bool(await _buy()).is_false()
	_fake.next_outcome = BillingBackend.Outcome.FAILED
	assert_bool(await _buy()).is_false()
	_fake.launch_fails = true
	assert_bool(await _buy()).is_false()
	assert_bool(_purchases.owned).is_false()
	assert_array(_fake.acknowledges).is_empty()


func test_an_unavailable_store_or_unknown_product_returns_false_at_once() -> void:
	_fake.store_available = false
	assert_bool(await _buy()).is_false()
	_fake.store_available = true
	_fake.product_found = false
	assert_bool(await _buy()).is_false()
	assert_array(_fake.launches).is_empty()


func test_a_connection_that_never_answers_times_out() -> void:
	_fake.connect_never_answers = true
	var out: Array = AdServiceHarness.start(_buy)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS - 1
	await AdServiceHarness.frames(2)
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_array(_fake.launches).is_empty()


func test_a_sheet_that_never_shows_times_out_and_a_late_purchase_is_still_applied() -> void:
	_fake.sheet_never_shows = true
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	var out: Array = AdServiceHarness.start(_buy)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	# No second sheet while the first may still open.
	assert_bool(await _buy()).is_false()
	assert_array(_fake.launches).has_size(1)
	_fake.show_late_sheet()
	assert_bool(_purchases.owned).is_true()
	assert_array(_fake.acknowledges).has_size(1)


func test_once_the_sheet_shows_the_call_waits_past_the_timeout() -> void:
	_fake.sheet_never_closes = true
	var out: Array = AdServiceHarness.start(_buy)
	await AdServiceHarness.frames(3)
	_clock_ms = TIMEOUT_MS * 10
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_fake.finish_sheet(BillingBackend.Outcome.PURCHASED)
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([true])
	assert_array(_fake.acknowledges).has_size(1)


func test_a_failed_acknowledge_is_retried_by_restore_not_repeated_before() -> void:
	_fake.ack_fails = true
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await _buy()).is_true()
	assert_array(_fake.acknowledges).has_size(1)
	_fake.ack_fails = false
	assert_bool(await _restore()).is_true()
	assert_array(_fake.acknowledges).has_size(2)
	assert_bool(await _restore()).is_true()
	assert_array(_fake.acknowledges).has_size(2)


func test_restore_grants_a_purchase_the_store_lists() -> void:
	(
		_fake
		. purchases
		. append(
			{
				BillingBackend.KEY_PRODUCT: PRODUCT,
				BillingBackend.KEY_TOKEN: "old",
				BillingBackend.KEY_PURCHASED: true,
				BillingBackend.KEY_ACKNOWLEDGED: true,
			}
		)
	)
	assert_bool(await _restore()).is_true()
	assert_bool(_purchases.owned).is_true()
	assert_array(_fake.acknowledges).is_empty()
	assert_array(_changes).contains_exactly([true])


func test_restore_ignores_another_product() -> void:
	(
		_fake
		. purchases
		. append(
			{
				BillingBackend.KEY_PRODUCT: "other",
				BillingBackend.KEY_TOKEN: "x",
				BillingBackend.KEY_PURCHASED: true,
				BillingBackend.KEY_ACKNOWLEDGED: true,
			}
		)
	)
	assert_bool(await _restore()).is_false()
	assert_bool(_purchases.owned).is_false()


func test_a_refund_clears_the_entitlement_on_the_next_answered_query() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	await _buy()
	_fake.refund()
	assert_bool(await _restore()).is_false()
	assert_bool(_purchases.owned).is_false()
	assert_array(_changes).contains_exactly([true, false])


func test_offline_keeps_the_cached_entitlement() -> void:
	_purchases.owned = true
	_fake.query_fails = true
	assert_bool(await _restore()).is_false()
	assert_bool(_purchases.owned).is_true()
	_fake.query_fails = false
	_fake.store_available = false
	assert_bool(await _restore()).is_false()
	assert_bool(_purchases.owned).is_true()
	assert_array(_changes).is_empty()


func test_a_query_that_never_answers_times_out_and_keeps_the_cache() -> void:
	_purchases.owned = true
	_fake.query_never_answers = true
	var out: Array = AdServiceHarness.start(_restore)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_bool(_purchases.owned).is_true()


func test_the_inert_backend_never_grants() -> void:
	var inert: Purchases = Purchases.new(BillingBackend.new(), PRODUCT)
	assert_bool(await inert.purchase(_now, TIMEOUT_MS)).is_false()
	inert.owned = true
	assert_bool(await inert.restore(_now, TIMEOUT_MS)).is_false()
	assert_bool(inert.owned).is_true()
