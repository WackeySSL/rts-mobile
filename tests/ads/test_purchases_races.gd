extends GdUnitTestSuite
## P406: Purchases' timing and races over the FakeBilling: the deadline applies only before the
## store sheet shows, a stale or older answer never undoes a grant, and a lost result never locks
## purchases for good. The clock is fake: the timeouts
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


func test_a_connection_that_never_answers_times_out() -> void:
	_fake.connect_never_answers = true
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS - 1
	await _tick(2)
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await _tick(2)
	assert_array(out).contains_exactly([false])
	assert_array(_fake.launches).is_empty()


func test_a_restore_under_a_connection_that_never_answers_keeps_the_cache() -> void:
	_ledger.remove_ads = true
	_fake.connect_never_answers = true
	var out: Array = AdServiceHarness.start(_restore)
	await _tick()
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await _tick(2)
	assert_array(out).contains_exactly([false])
	assert_bool(_ledger.remove_ads).is_true()


func test_a_sheet_that_never_shows_times_out_and_a_late_purchase_is_still_applied() -> void:
	_fake.sheet_never_shows = true
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await _tick(2)
	assert_array(out).contains_exactly([false])
	# No second sheet while the first may still open.
	assert_bool(await _buy()).is_false()
	assert_array(_fake.launches).has_size(1)
	_fake.show_late_sheet()
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_fake.acknowledges).has_size(1)


func test_an_unanswered_launch_stops_blocking_after_a_restore_without_pending() -> void:
	_fake.sheet_never_shows = true
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	_clock_ms = TIMEOUT_MS
	await _tick(2)
	assert_array(out).contains_exactly([false])
	assert_bool(await _restore()).is_false()
	_fake.sheet_never_shows = false
	_fake.finish_sheet(BillingBackend.Outcome.CANCELED)
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await _buy()).is_true()
	assert_array(_fake.launches).has_size(2)


func test_an_unanswered_launch_stops_blocking_after_the_grace_period() -> void:
	_fake.sheet_never_shows = true
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	_clock_ms = TIMEOUT_MS
	await _tick(2)
	assert_array(out).contains_exactly([false])
	_fake.sheet_never_shows = false
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await _buy()).override_failure_message("still locked").is_false()
	_clock_ms = TIMEOUT_MS * (Purchases.RESULT_GRACE_FACTOR + 1)
	assert_bool(await _buy()).override_failure_message("recovered").is_true()


func test_once_the_sheet_shows_the_call_waits_past_the_timeout() -> void:
	_fake.sheet_never_closes = true
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	_clock_ms = TIMEOUT_MS * 10
	await _tick()
	assert_array(out).is_empty()
	_fake.finish_sheet(BillingBackend.Outcome.PURCHASED)
	await _tick(2)
	assert_array(out).contains_exactly([true])
	assert_array(_fake.acknowledges).has_size(1)


func test_a_stale_pending_completion_does_not_end_a_new_purchase_call() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PENDING
	await _buy()
	var token: String = _fake.purchases[0][BillingBackend.KEY_TOKEN]
	# A second attempt: its sheet stays open, then the old pending purchase is paid.
	_fake.sheet_never_closes = true
	_ledger.remove_ads = false
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	assert_array(out).is_empty()
	_fake.purchase_finished.emit(PRODUCT, BillingBackend.Outcome.PENDING, token)
	await _tick()
	assert_array(out).is_empty()
	_fake.finish_sheet(BillingBackend.Outcome.CANCELED)
	await _tick(2)
	assert_array(out).contains_exactly([false])


func test_a_stale_result_of_an_earlier_call_does_not_end_a_new_one() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PENDING
	await _buy()
	var old: String = _fake.purchases[0][BillingBackend.KEY_TOKEN]
	_fake.sheet_never_shows = true
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	_fake.purchase_finished.emit(PRODUCT, BillingBackend.Outcome.PENDING, old)
	await _tick()
	assert_array(out).is_empty()


func test_an_entitlement_that_arrives_while_the_product_loads_blocks_the_launch() -> void:
	_fake.product_never_answers = true
	var out: Array = AdServiceHarness.start(_buy)
	await _tick()
	_fake.purchase_finished.emit(PRODUCT, BillingBackend.Outcome.PURCHASED, "elsewhere")
	_fake.product_never_answers = false
	_fake.query_product(PRODUCT)
	await _tick()
	assert_array(out).contains_exactly([true])
	assert_array(_fake.launches).is_empty()


func test_a_query_that_never_answers_times_out_and_keeps_the_cache() -> void:
	_ledger.remove_ads = true
	_fake.query_never_answers = true
	var out: Array = AdServiceHarness.start(_restore)
	await _tick()
	assert_array(out).is_empty()
	_clock_ms = TIMEOUT_MS
	await _tick(2)
	assert_array(out).contains_exactly([false])
	assert_bool(_ledger.remove_ads).is_true()


func test_a_deferred_restore_after_a_purchase_never_clears_the_entitlement() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	await _buy()
	_fake.defer_queries = true
	var out: Array = AdServiceHarness.start(_restore)
	await _tick()
	assert_array(out).is_empty()
	assert_bool(_ledger.remove_ads).is_true()
	_fake.answer_queries()
	await _tick(2)
	assert_array(out).contains_exactly([true])
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_changes).contains_exactly([true])


func test_a_grant_during_a_restore_is_not_undone_by_its_older_answer() -> void:
	_fake.add_owned(PRODUCT, "p1", false, false)
	_fake.defer_queries = true
	var out: Array = AdServiceHarness.start(_restore)
	await _tick()
	_fake.complete_pending("p1")
	assert_bool(_ledger.remove_ads).is_true()
	# The snapshot the store answers with still lists p1 as pending.
	_fake.purchases.clear()
	_fake.answer_queries()
	await _tick(2)
	assert_array(out).contains_exactly([true])
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_changes).contains_exactly([true])


func test_a_late_answer_to_a_timed_out_restore_is_adopted_not_doubled() -> void:
	_fake.defer_queries = true
	var out: Array = AdServiceHarness.start(_restore)
	await _tick()
	_clock_ms = TIMEOUT_MS
	await _tick(2)
	assert_array(out).contains_exactly([false])
	_fake.add_owned(PRODUCT, "p2")
	var second: Array = AdServiceHarness.start(_restore)
	await _tick()
	_fake.answer_queries()
	await _tick(2)
	# The answer is the first request's snapshot, taken before p2 existed.
	assert_array(second).contains_exactly([false])


func test_the_backend_contract_hides_a_superseded_or_unanswered_query() -> void:
	_fake.add_owned(PRODUCT, "p1")
	_fake.defer_queries = true
	var first: int = _fake.query_purchases()
	assert_int(_fake.purchases_state(first)).is_equal(BillingBackend.QueryState.LOADING)
	assert_array(_fake.owned_purchases()).is_empty()
	var second: int = _fake.query_purchases()
	assert_int(_fake.purchases_state(first)).is_equal(BillingBackend.QueryState.FAILED)
	_fake.answer_queries()
	assert_int(_fake.purchases_state(second)).is_equal(BillingBackend.QueryState.DONE)
	assert_array(_fake.owned_purchases()).has_size(1)


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
	_fake.add_owned(PRODUCT, "old")
	assert_bool(await _restore()).is_true()
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_fake.acknowledges).is_empty()
	assert_array(_changes).contains_exactly([true])


func test_restore_acknowledges_a_purchase_the_store_lists_unacknowledged() -> void:
	_fake.add_owned(PRODUCT, "open", true, false)
	assert_bool(await _restore()).is_true()
	assert_array(_fake.acknowledges).contains_exactly(["open"])


func test_a_refund_clears_the_entitlement_on_the_next_answered_query() -> void:
	_fake.next_outcome = BillingBackend.Outcome.PURCHASED
	await _buy()
	_fake.refund()
	assert_bool(await _restore()).is_false()
	assert_bool(_ledger.remove_ads).is_false()
	assert_array(_changes).contains_exactly([true, false])


func test_offline_keeps_the_cached_entitlement() -> void:
	_ledger.remove_ads = true
	_fake.query_fails = true
	assert_bool(await _restore()).override_failure_message("offline").is_false()
	assert_bool(_ledger.remove_ads).is_true()
	_fake.query_fails = false
	_fake.store_available = false
	assert_bool(await _restore()).override_failure_message("unavailable").is_false()
	assert_bool(_ledger.remove_ads).is_true()
	assert_array(_changes).is_empty()
