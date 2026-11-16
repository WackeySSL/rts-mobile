extends GdUnitTestSuite
## P408: purchases against the silent restore, the order of the backend calls and of the banner
## announcements, and the two fake overlays on top of each other. (Late ads: test_ad_service_late.)

var _h: AdServiceHarness


func before_test() -> void:
	_h = AdServiceHarness.new()


# --- a purchase during the silent restore -------------------------------------------------------


func test_a_purchase_tapped_during_the_silent_restore_waits_for_it_then_proceeds() -> void:
	var service: Node = auto_free(_h.make())
	var billing: FakeBilling = AdServiceHarness.billing(service)
	billing.defer_queries = true
	billing.next_outcome = BillingBackend.Outcome.PURCHASED
	add_child(service)
	await AdServiceHarness.frames(1)
	var out: Array = AdServiceHarness.start(service.purchase_remove_ads)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	assert_array(billing.launches).is_empty()
	billing.answer_queries()
	await AdServiceHarness.frames(3)
	assert_array(billing.launches).has_size(1)
	assert_array(out).contains_exactly([true])
	assert_bool(service.has_remove_ads()).is_true()


func test_a_purchase_during_a_restore_that_finds_it_owned_never_opens_the_sheet() -> void:
	var service: Node = auto_free(_h.make())
	var billing: FakeBilling = AdServiceHarness.billing(service)
	billing.add_owned(service._settings.remove_ads_product_id, "t1")
	billing.defer_queries = true
	add_child(service)
	await AdServiceHarness.frames(1)
	var out: Array = AdServiceHarness.start(service.purchase_remove_ads)
	await AdServiceHarness.frames(2)
	billing.answer_queries()
	await AdServiceHarness.frames(3)
	assert_array(out).contains_exactly([true])
	assert_array(billing.launches).is_empty()


func test_a_purchase_during_a_restore_that_never_answers_gives_up_at_the_billing_timeout() -> void:
	var service: Node = auto_free(_h.make())
	var billing: FakeBilling = AdServiceHarness.billing(service)
	billing.query_never_answers = true
	add_child(service)
	await AdServiceHarness.frames(1)
	var out: Array = AdServiceHarness.start(service.purchase_remove_ads)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_h.clock_ms = service._settings.billing_timeout_ms
	await AdServiceHarness.frames(3)
	assert_array(out).contains_exactly([false])
	assert_array(billing.launches).is_empty()


# --- production order ---------------------------------------------------------------------------


func test_without_consent_an_owned_purchase_makes_no_ad_call_and_no_banner_signal() -> void:
	var service: Node = auto_free(_h.make(false))
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	AdServiceHarness.billing(service).add_owned(service._settings.remove_ads_product_id, "t1")
	service.show_banner()
	add_child(service)
	await AdServiceHarness.frames(2)
	assert_bool(service.has_remove_ads()).is_true()
	# A banner call before initialize would also push the strict-order error, which fails the test.
	assert_int(fake.initializations).is_equal(0)
	assert_bool(fake.banner_visible).is_false()
	assert_array(fake.shows).is_empty()
	assert_array(fake.load_requests).is_empty()
	assert_array(heights).is_empty()


func test_a_refund_then_a_decline_back_to_back_announces_each_real_change_once() -> void:
	var service: Node = auto_free(_h.make())
	service._ledger.remove_ads = true
	service.show_banner()
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	var frame: int = Engine.get_process_frames()
	AdServiceHarness.billing(service).refund()
	await service.restore_purchases()
	service._set_can_request(false)
	assert_int(Engine.get_process_frames()).override_failure_message("one frame").is_equal(frame)
	assert_bool(service.has_remove_ads()).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_array(heights).contains_exactly([FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP, 0])


func test_a_decline_then_a_refund_back_to_back_announces_nothing() -> void:
	var service: Node = auto_free(_h.make())
	service._ledger.remove_ads = true
	service.show_banner()
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	var frame: int = Engine.get_process_frames()
	AdServiceHarness.billing(service).refund()
	service._set_can_request(false)
	await service.restore_purchases()
	assert_int(Engine.get_process_frames()).override_failure_message("one frame").is_equal(frame)
	assert_bool(service.has_remove_ads()).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_array(heights).is_empty()


func test_an_entitlement_handler_reads_the_fresh_banner_height() -> void:
	var service: Node = auto_free(_h.make())
	service.show_banner()
	var seen: Array[int] = []
	service.entitlement_changed.connect(
		func(_has: bool) -> void: seen.append(service.banner_height_dp())
	)
	AdServiceHarness.billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	await service.purchase_remove_ads()
	assert_array(seen).contains_exactly([0])


func test_a_re_settled_banner_is_shown_on_the_backend_only_once() -> void:
	var service: Node = auto_free(_h.make())
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	service.show_banner()
	service._refresh_banner()
	service.show_banner()
	service._set_can_request(true)
	assert_int(fake.calls.count("banner")).is_equal(1)
	service.hide_banner()
	service.hide_banner()
	service.hide_banner()
	# A later row may defer the last hide to idle; one frame covers both.
	await AdServiceHarness.frames(1)
	assert_int(fake.calls.count("hide_banner")).is_equal(1)


func test_a_hide_and_a_show_in_one_frame_make_no_backend_banner_call() -> void:
	var service: Node = auto_free(_h.make())
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	service.show_banner()
	await AdServiceHarness.frames(1)
	var before: int = fake.calls.size()
	service.hide_banner()
	service.show_banner()
	await AdServiceHarness.frames(2)
	assert_array(fake.calls.slice(before)).is_empty()
	assert_bool(fake.banner_visible).is_true()


func test_the_consent_form_is_drawn_above_the_purchase_sheet() -> void:
	var service: Node = auto_free(_h.make())
	service.fake_auto_close = false
	AdServiceHarness.ump(service).consent_required = true
	add_child(service)
	await AdServiceHarness.frames(1)
	var purchase: Array = AdServiceHarness.start(service.purchase_remove_ads)
	var consent: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(3)
	var form: FakeConsentForm = null
	var sheet: FakeBillingSheet = null
	for child: Node in service.get_children():
		if child is FakeConsentForm:
			form = child as FakeConsentForm
		elif child is FakeBillingSheet:
			sheet = child as FakeBillingSheet
	assert_object(form).is_not_null()
	assert_object(sheet).is_not_null()
	if form != null and sheet != null:
		assert_int(form.layer).is_greater(sheet.layer)
	# End the open flows so no coroutine outlives the test.
	AdServiceHarness.ump(service).dismiss(true)
	AdServiceHarness.billing(service).finish_sheet(BillingBackend.Outcome.CANCELED)
	await AdServiceHarness.frames(3)
	assert_array(consent).contains_exactly([true])
	assert_array(purchase).contains_exactly([false])


# --- P407 ---------------------------------------------------------------------------------------


func test_a_buyer_sees_no_banner_before_the_first_restore_answers() -> void:
	AdServiceHarness.seed_section({"remove_ads": true})
	var service: Node = auto_free(_h.make())
	var billing: FakeBilling = AdServiceHarness.billing(service)
	billing.add_owned(service._settings.remove_ads_product_id, "t1")
	billing.defer_queries = true
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	service.show_banner()
	add_child(service)
	await AdServiceHarness.frames(2)
	assert_array(heights).override_failure_message("a buyer saw a banner").is_empty()
