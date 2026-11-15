extends GdUnitTestSuite
## P406: Purchases over the FakeBilling. PENDING is never granted, a purchase is acknowledged once,
## a refund clears the entitlement, offline keeps the cache, a stale answer never undoes a grant,
## and the deadline applies only before the store sheet shows. The clock is fake: the timeouts
## never read wall time. The ledger plays AdService's part: it is the cache and it is written
## from `entitlement_changed`.

const PRODUCT: String = "remove_ads"
const TIMEOUT_MS: int = 8000

var _clock_ms: int = 0
var _fake: FakeBilling
var _ledger: AdLedger
var _purchases: Purchases
var _changes: Array[bool] = []


func before_test() -> void:
	_clock_ms = 0
	_changes = []
	_fake = FakeBilling.new()
	_ledger = AdLedger.new()
	_purchases = _make(_fake)


func _make(backend: BillingBackend) -> Purchases:
	var made: Purchases = Purchases.new(backend, PRODUCT, func() -> bool: return _ledger.remove_ads)
	made.entitlement_changed.connect(
		func(has: bool) -> void:
			_ledger.remove_ads = has
			_changes.append(has)
	)
	return made


func _now() -> int:
	return _clock_ms


func _buy() -> bool:
	return await _purchases.purchase(_now, TIMEOUT_MS)


func _restore() -> bool:
	return await _purchases.restore(_now, TIMEOUT_MS)


func _tick(frames: int = 3) -> void:
	await AdServiceHarness.frames(frames)


func test_price_text_comes_from_the_backend() -> void:
	assert_str(_make(FakeBilling.new()).price_text()).is_equal(FakeBilling.DEFAULT_PRICE)
	_fake.price = "29,00 kr."
	assert_str(_purchases.price_text()).is_equal("29,00 kr.")


func test_price_text_is_empty_for_an_unknown_product() -> void:
	_fake.product_found = false
	assert_str(_purchases.price_text()).is_empty()


func test_price_text_is_empty_for_an_unavailable_store() -> void:
	_fake.store_available = false
	assert_str(_purchases.price_text()).is_empty()
	assert_str(_make(BillingBackend.new()).price_text()).is_empty()


func test_a_purchase_grants_acknowledges_once_and_emits_once() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await _buy()).is_true()
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_fake.acknowledges).has_size(1)
	assert_array(_fake.launches).contains_exactly([PRODUCT])
	assert_array(_changes).contains_exactly([true])


func test_owned_means_no_second_launch_and_no_second_acknowledge() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	await _buy()
	assert_bool(await _buy()).is_true()
	assert_bool(await _restore()).is_true()
	assert_array(_fake.launches).has_size(1)
	assert_array(_fake.acknowledges).has_size(1)
	assert_array(_changes).has_size(1)


func test_the_same_token_purchased_twice_acknowledges_and_emits_once() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	await _buy()
	var token: String = _fake.purchases[0][BillingBackend.KEY_TOKEN]
	_fake.purchase_finished.emit(PRODUCT, BillingBackend.Outcome.PURCHASED, token)
	assert_array(_fake.acknowledges).has_size(1)
	assert_array(_changes).has_size(1)


func test_a_ledger_loaded_as_owned_gets_no_second_emit_from_a_late_purchase() -> void:
	_ledger.remove_ads = true
	_fake.purchase_finished.emit(PRODUCT, BillingBackend.Outcome.PURCHASED, "late")
	assert_array(_changes).is_empty()
	assert_array(_fake.acknowledges).contains_exactly(["late"])


func test_pending_is_never_granted_and_not_acknowledged() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PENDING
	assert_bool(await _buy()).is_false()
	assert_bool(_ledger.remove_ads).is_false()
	assert_array(_fake.acknowledges).is_empty()
	assert_array(_changes).is_empty()


func test_a_restore_that_lists_the_purchase_as_pending_does_not_grant_it() -> void:
	_fake.add_owned(PRODUCT, "p1", false, false)
	assert_bool(await _restore()).is_false()
	assert_bool(_ledger.remove_ads).is_false()
	assert_array(_fake.acknowledges).is_empty()


func test_a_pending_purchase_paid_later_is_granted_and_acknowledged_once() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PENDING
	await _buy()
	var token: String = _fake.purchases[0][BillingBackend.KEY_TOKEN]
	_fake.complete_pending(token)
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_fake.acknowledges).contains_exactly([token])
	assert_array(_changes).contains_exactly([true])


func test_complete_pending_reports_nothing_for_an_unknown_token() -> void:
	var seen: Array[String] = []
	_fake.purchase_finished.connect(
		func(_id: String, _outcome: BillingBackend.Outcome, token: String) -> void:
			seen.append(token)
	)
	_fake.complete_pending("nobody")
	assert_array(seen).is_empty()


func test_cancel_grants_nothing() -> void:
	assert_bool(await _buy()).override_failure_message("cancel").is_false()
	assert_bool(_ledger.remove_ads).is_false()
	assert_array(_fake.acknowledges).is_empty()


func test_failure_after_the_sheet_and_before_it_grant_nothing() -> void:
	_fake.next_outcome = BillingBackend.Outcome.FAILED
	assert_bool(await _buy()).override_failure_message("failed sheet").is_false()
	_fake.launch_fails = true
	assert_bool(await _buy()).override_failure_message("failed launch").is_false()
	assert_bool(_ledger.remove_ads).is_false()


func test_another_products_result_is_ignored() -> void:
	_fake.purchase_finished.emit("other", BillingBackend.Outcome.PURCHASED, "x")
	assert_bool(_ledger.remove_ads).is_false()
	assert_array(_fake.acknowledges).is_empty()


func test_an_empty_token_is_never_acknowledged() -> void:
	_fake.purchase_finished.emit(PRODUCT, BillingBackend.Outcome.PURCHASED, "")
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_fake.acknowledges).is_empty()


func test_an_unavailable_store_returns_at_once_without_a_launch() -> void:
	_fake.store_available = false
	var out: Array = AdServiceHarness.start(_buy)
	assert_array(out).contains_exactly([false])
	assert_array(_fake.launches).is_empty()


func test_an_unknown_product_returns_at_once_without_a_launch() -> void:
	_fake.product_found = false
	var out: Array = AdServiceHarness.start(_buy)
	assert_array(out).contains_exactly([false])
	assert_array(_fake.launches).is_empty()


func test_the_inert_backend_never_grants_and_keeps_the_cache() -> void:
	var inert: Purchases = _make(BillingBackend.new())
	assert_bool(await inert.purchase(_now, TIMEOUT_MS)).is_false()
	_ledger.remove_ads = true
	assert_bool(await inert.restore(_now, TIMEOUT_MS)).is_false()
	assert_bool(_ledger.remove_ads).is_true()


func test_restore_ignores_another_product() -> void:
	_fake.add_owned("other", "x")
	assert_bool(await _restore()).is_false()
	assert_bool(_ledger.remove_ads).is_false()
