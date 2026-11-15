extends GdUnitTestSuite
## P408: interaction fixes between consent (P404) and purchases (P406): a late ad that opens after
## consent is withdrawn, the silent restore against a purchase, the order of the backend calls and
## of the banner announcements, and the two fake overlays on top of each other.

const POST_MATCH: StringName = &"post_match"
const REWARD: StringName = &"double_xp"

var _h: AdServiceHarness


func before_test() -> void:
	_h = AdServiceHarness.new()


## A service whose show never opened within the timeout and cannot be recalled: [service, fake].
func _late_service(kind: StringName) -> Array:
	var service: Node = auto_free(_h.make())
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.show_never_opens = true
	fake.ignore_cancel = true
	AdServiceHarness.play_three_matches(service)
	var grant: Callable = func() -> void: _h.events.append("grant")
	var out: Array = AdServiceHarness.start(
		func() -> bool:
			if kind == AdBackend.KIND_REWARDED:
				return await service.show_rewarded(REWARD, grant)
			return await service.maybe_show_interstitial(POST_MATCH)
	)
	await AdServiceHarness.frames(2)
	_h.clock_ms = service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	return [service, fake]


# --- S1, S2: a late ad against consent and Remove ads ------------------------------------------


func test_a_consent_decline_after_a_late_ad_opened_keeps_the_pair_and_frees_the_service() -> void:
	var late: Array = await _late_service(AdBackend.KIND_REWARDED)
	var service: Node = late[0]
	var fake: FakeAdBackend = late[1]
	fake.show_never_closes = true
	fake.open_late()
	assert_bool(service._busy).is_true()
	service._set_can_request(false)
	assert_bool(service._busy).override_failure_message("still open, still busy").is_true()
	fake.show_never_closes = false
	fake.finish_show()
	assert_bool(service._busy).is_false()
	assert_array(_h.events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])


func test_a_late_ad_that_opens_after_a_consent_decline_is_paired_and_not_noted() -> void:
	var late: Array = await _late_service(AdBackend.KIND_INTERSTITIAL)
	var service: Node = late[0]
	service._set_can_request(false)
	late[1].open_late()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_bool(service._busy).is_false()
	assert_bool(service._ledger.shown_for_current_match()).is_false()


func test_a_late_rewarded_ad_dropped_by_a_decline_keeps_its_reward() -> void:
	var late: Array = await _late_service(AdBackend.KIND_REWARDED)
	late[0]._set_can_request(false)
	late[1].open_late()
	assert_array(_h.events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])
	assert_bool(late[0]._busy).is_false()


func test_a_late_ad_that_opens_after_remove_ads_is_paired_and_the_service_is_free() -> void:
	var late: Array = await _late_service(AdBackend.KIND_INTERSTITIAL)
	var service: Node = late[0]
	AdServiceHarness.billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await service.purchase_remove_ads()).is_true()
	late[1].open_late()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_bool(service._busy).is_false()
	assert_bool(service._ledger.shown_for_current_match()).is_false()


func test_a_new_call_of_the_same_kind_takes_over_a_late_one_without_a_double_announce() -> void:
	var late: Array = await _late_service(AdBackend.KIND_INTERSTITIAL)
	var service: Node = late[0]
	var fake: FakeAdBackend = late[1]
	fake.show_never_opens = false
	fake.ignore_cancel = false
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_int(service._lates.size()).is_equal(0)


# --- S4: a purchase during the silent restore --------------------------------------------------


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


# --- S5: production order ----------------------------------------------------------------------


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
	assert_int(fake.initializations).is_equal(0)
	assert_array(fake.calls).is_empty()
	assert_array(heights).is_empty()


func test_a_refund_then_a_decline_in_one_frame_announces_each_real_change_once() -> void:
	var service: Node = auto_free(_h.make())
	service._ledger.remove_ads = true
	service.show_banner()
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	AdServiceHarness.billing(service).refund()
	await service.restore_purchases()
	service._set_can_request(false)
	assert_bool(service.has_remove_ads()).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_array(heights).contains_exactly([FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP, 0])


func test_a_decline_then_a_refund_in_one_frame_announces_nothing() -> void:
	var service: Node = auto_free(_h.make())
	service._ledger.remove_ads = true
	service.show_banner()
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	AdServiceHarness.billing(service).refund()
	service._set_can_request(false)
	await service.restore_purchases()
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
	assert_int(fake.calls.count("hide_banner")).is_equal(1)


func test_the_consent_form_is_drawn_above_the_purchase_sheet() -> void:
	var service: Node = auto_free(_h.make())
	service.fake_auto_close = false
	AdServiceHarness.ump(service).consent_required = true
	add_child(service)
	await AdServiceHarness.frames(1)
	var purchase: Array = AdServiceHarness.start(service.purchase_remove_ads)
	var consent: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(3)
	var form: FakeConsentForm = (
		service.find_child("FakeConsentForm", true, false) as FakeConsentForm
	)
	var sheet: FakeBillingSheet = (
		service.find_child("FakeTestPurchase", true, false) as FakeBillingSheet
	)
	assert_object(form).is_not_null()
	assert_object(sheet).is_not_null()
	assert_int(form.layer).is_greater(sheet.layer)
	# End the open flows so no coroutine outlives the test.
	AdServiceHarness.ump(service).dismiss(true)
	AdServiceHarness.billing(service).finish_sheet(BillingBackend.Outcome.CANCELED)
	await AdServiceHarness.frames(3)
	assert_array(consent).contains_exactly([true])
	assert_array(purchase).contains_exactly([false])


# --- S3: P407 pending ---------------------------------------------------------------------------


func test_a_buyer_sees_no_banner_before_the_first_restore_answers(
	_do_skip := true, _skip_reason := "Pending P407: the ads save section is not loaded yet"
) -> void:
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
