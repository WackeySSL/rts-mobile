extends GdUnitTestSuite
## P406: the Remove ads purchase through the AdService facade. Banners and interstitials stop,
## rewarded ads stay, entitlement_changed fires once per change, and the facade's timeouts follow
## the data and the fake clock.

var _h: AdServiceHarness
var _signals: Array[bool] = []


func before_test() -> void:
	_h = AdServiceHarness.new()
	_signals = []


func _service() -> Node:
	var service: Node = auto_free(_h.make())
	service.entitlement_changed.connect(func(has: bool) -> void: _signals.append(has))
	return service


func _billing(service: Node) -> FakeBilling:
	return service._billing as FakeBilling


func test_a_purchase_sets_the_ledger_emits_and_hides_the_banner() -> void:
	var service: Node = _service()
	service.show_banner()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	_billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await service.purchase_remove_ads()).is_true()
	assert_bool(service.has_remove_ads()).is_true()
	assert_bool(service._ledger.remove_ads).is_true()
	assert_array(_signals).contains_exactly([true])
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_array(heights).contains_exactly([0])
	assert_array(_billing(service).acknowledges).has_size(1)


func test_pending_changes_nothing() -> void:
	var service: Node = _service()
	service.show_banner()
	_billing(service).next_outcome = BillingBackend.Outcome.PENDING
	assert_bool(await service.purchase_remove_ads()).is_false()
	assert_bool(service.has_remove_ads()).is_false()
	assert_array(_signals).is_empty()
	assert_int(service.banner_height_dp()).is_greater(0)


func test_remove_ads_stops_interstitials_and_their_preload_but_rewarded_stays() -> void:
	var service: Node = _service()
	AdServiceHarness.play_three_matches(service)
	_billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	await service.purchase_remove_ads()
	var ad: FakeAdBackend = AdServiceHarness.fake(service)
	ad.load_requests.clear()
	service.note_match_completed(300)
	assert_bool(await service.maybe_show_interstitial(&"post_match")).is_false()
	assert_array(ad.shows).is_empty()
	assert_array(ad.load_requests).is_empty()
	var rewards: Array[int] = []
	assert_bool(service.rewarded_ready(&"result")).is_true()
	assert_bool(await service.show_rewarded(&"result", func() -> void: rewards.append(1))).is_true()
	assert_array(rewards).has_size(1)


func test_a_banner_requested_after_the_purchase_never_shows() -> void:
	var service: Node = _service()
	_billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	await service.purchase_remove_ads()
	service.show_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_bool(AdServiceHarness.fake(service).banner_visible).is_false()


func test_a_refund_brings_the_banner_and_interstitials_back() -> void:
	var service: Node = _service()
	service.show_banner()
	_billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	await service.purchase_remove_ads()
	_billing(service).refund()
	assert_bool(await service.restore_purchases()).is_false()
	assert_bool(service.has_remove_ads()).is_false()
	assert_array(_signals).contains_exactly([true, false])
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	AdServiceHarness.play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(&"post_match")).is_true()


func test_restore_grants_and_offline_keeps_the_cache() -> void:
	var service: Node = _service()
	(
		_billing(service)
		. purchases
		. append(
			{
				BillingBackend.KEY_PRODUCT: service._settings.remove_ads_product_id,
				BillingBackend.KEY_TOKEN: "t1",
				BillingBackend.KEY_PURCHASED: true,
				BillingBackend.KEY_ACKNOWLEDGED: true,
			}
		)
	)
	assert_bool(await service.restore_purchases()).is_true()
	assert_bool(service.has_remove_ads()).is_true()
	_billing(service).query_fails = true
	assert_bool(await service.restore_purchases()).is_false()
	assert_bool(service.has_remove_ads()).is_true()
	assert_array(_signals).contains_exactly([true])


func test_a_loaded_cache_survives_an_unavailable_store() -> void:
	var service: Node = _service()
	service._ledger.remove_ads = true
	_billing(service).store_available = false
	assert_bool(await service.restore_purchases()).is_false()
	assert_bool(await service.purchase_remove_ads()).is_true()
	assert_bool(service.has_remove_ads()).is_true()


func test_the_facade_timeout_comes_from_the_data() -> void:
	var service: Node = _service()
	_billing(service).connect_never_answers = true
	var timeout: int = service._settings.fullscreen_timeout_ms
	var out: Array = AdServiceHarness.start(service.purchase_remove_ads)
	await AdServiceHarness.frames(2)
	_h.clock_ms = timeout - 1
	await AdServiceHarness.frames(2)
	assert_array(out).is_empty()
	_h.clock_ms = timeout
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])


func test_the_price_text_is_the_fakes_placeholder_and_empty_when_unavailable() -> void:
	var service: Node = _service()
	assert_str(service.remove_ads_price_text()).is_equal(FakeBilling.DEFAULT_PRICE)
	var other: Node = _service()
	_billing(other).store_available = false
	assert_str(other.remove_ads_price_text()).is_empty()
