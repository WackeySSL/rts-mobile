extends GdUnitTestSuite
## P408: late full-screen ads (a show that timed out and cannot be recalled) against consent and
## Remove ads, the handover between runs of a kind and across kinds, and a show withdrawn before it
## opened.

const POST_MATCH: StringName = &"post_match"
const REWARD: StringName = &"double_xp"

var _h: AdServiceHarness


## A service with one full-screen run that timed out and cannot be recalled (a late run).
class LateRig:
	extends RefCounted
	var service: Node
	var fake: FakeAdBackend


func before_test() -> void:
	_h = AdServiceHarness.new()


func after_test() -> void:
	_h.dispose()


## The rig, or null when the setup failed (the failure is reported; callers return at once).
func _late_rig(kind: StringName) -> LateRig:
	var rig: LateRig = LateRig.new()
	rig.service = auto_free(_h.make())
	rig.fake = AdServiceHarness.fake(rig.service)
	rig.fake.show_never_opens = true
	rig.fake.ignore_cancel = true
	AdServiceHarness.play_three_matches(rig.service)
	var out: Array = _start_show(rig.service, kind)
	await AdServiceHarness.frames(2)
	_h.clock_ms = rig.service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("setup: the show did not time out").is_equal([false])
	return rig if out == [false] else null


func _start_show(service: Node, kind: StringName) -> Array:
	var grant: Callable = func() -> void: _h.events.append("grant")
	return AdServiceHarness.start(
		func() -> bool:
			if kind == AdBackend.KIND_REWARDED:
				return await service.show_rewarded(REWARD, grant)
			return await service.maybe_show_interstitial(POST_MATCH)
	)


# --- a late ad against consent and Remove ads ---------------------------------------------------


func test_a_consent_decline_after_a_late_ad_opened_keeps_the_pair_and_busy_until_the_close(
) -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_REWARDED)
	if rig == null:
		return
	rig.fake.show_never_closes = true
	rig.fake.open_late()
	assert_bool(rig.service._runs.is_busy()).is_true()
	rig.service._set_can_request(false)
	assert_bool(rig.service._runs.is_busy()).override_failure_message("open, so busy").is_true()
	rig.fake.finish_show()
	assert_bool(rig.service._runs.is_busy()).is_false()
	assert_array(_h.events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])


func test_a_late_ad_that_opens_after_a_consent_decline_is_paired_and_counted() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	rig.service._set_can_request(false)
	rig.fake.open_late()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_bool(rig.service._runs.is_busy()).is_false()
	assert_int(rig.service._runs.late_count()).is_equal(0)
	# The caps describe what the player saw.
	assert_bool(rig.service._ledger.shown_for_current_match()).is_true()


func test_a_late_rewarded_ad_that_opens_after_a_decline_keeps_its_reward() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_REWARDED)
	if rig == null:
		return
	rig.service._set_can_request(false)
	rig.fake.open_late()
	assert_array(_h.events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])
	assert_bool(rig.service._runs.is_busy()).is_false()


func test_a_late_ad_that_opens_after_remove_ads_is_paired_and_the_service_is_idle_at_the_close(
) -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	AdServiceHarness.billing(rig.service).next_outcome = BillingBackend.Outcome.PURCHASED
	assert_bool(await rig.service.purchase_remove_ads()).is_true()
	rig.fake.open_late()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_bool(rig.service._runs.is_busy()).is_false()
	assert_bool(rig.service._ledger.shown_for_current_match()).is_true()


# --- the handover between runs --------------------------------------------------------------------


func test_a_new_run_of_the_same_kind_takes_over_a_late_one_without_a_double_announce() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	rig.fake.show_never_opens = false
	rig.fake.ignore_cancel = false
	assert_bool(await rig.service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_int(rig.service._runs.late_count()).is_equal(0)


func test_a_new_run_that_has_not_connected_leaves_the_late_one_listening() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	rig.fake.load_never_answers = true
	rig.fake.show_never_closes = true
	var out: Array = _start_show(rig.service, AdBackend.KIND_INTERSTITIAL)
	await AdServiceHarness.frames(1)
	rig.fake.open_late()
	assert_array(_h.events).contains_exactly(["open:post_match"])
	assert_bool(rig.service._runs.is_busy()).is_true()
	rig.fake.finish_show()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	# The new run still waits for its load, then ends at its own deadline.
	_h.clock_ms = rig.service._settings.fullscreen_timeout_ms * 3
	await AdServiceHarness.frames(3)
	assert_array(out).contains_exactly([false])
	assert_bool(rig.service._runs.is_busy()).is_false()


func test_a_late_rewarded_ad_and_a_new_interstitial_pair_and_hold_busy_until_both_close() -> void:
	await _cross_kind(AdBackend.KIND_REWARDED, AdBackend.KIND_INTERSTITIAL)


func test_a_late_interstitial_and_a_new_rewarded_ad_pair_and_hold_busy_until_both_close() -> void:
	await _cross_kind(AdBackend.KIND_INTERSTITIAL, AdBackend.KIND_REWARDED)


func _cross_kind(first: StringName, second: StringName) -> void:
	var rig: LateRig = await _late_rig(first)
	if rig == null:
		return
	rig.fake.show_never_opens = false
	rig.fake.show_never_closes = true
	var out: Array = _start_show(rig.service, second)
	await AdServiceHarness.frames(2)
	assert_array(_h.events).contains_exactly(["open:" + _placement(second)])
	rig.fake.open_late(first)
	assert_array(_h.events).has_size(2)
	assert_bool(rig.service._runs.is_busy()).is_true()
	rig.fake.finish_show(second)
	assert_bool(rig.service._runs.is_busy()).override_failure_message("late ad open").is_true()
	rig.fake.finish_show(first)
	await AdServiceHarness.frames(2)
	assert_bool(rig.service._runs.is_busy()).is_false()
	assert_array(out).has_size(1)
	assert_int(_h.events.count("grant")).is_equal(1)
	assert_int(_h.events.count("close:" + _placement(first))).is_equal(1)
	assert_int(_h.events.count("close:" + _placement(second))).is_equal(1)


func _placement(kind: StringName) -> String:
	return REWARD if kind == AdBackend.KIND_REWARDED else POST_MATCH


func test_a_run_that_is_freed_leaves_no_reference_behind() -> void:
	var service: Node = auto_free(_h.make())
	AdServiceHarness.play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	await AdServiceHarness.frames(1)
	assert_object(service._runs.last_run).is_not_null()
	assert_object(service._runs.last_run.get_ref()).is_null()


# --- an interstitial still waiting to open ------------------------------------------------------


func _waiting_interstitial() -> LateRig:
	var rig: LateRig = LateRig.new()
	rig.service = auto_free(_h.make())
	rig.fake = AdServiceHarness.fake(rig.service)
	rig.fake.show_never_opens = true
	AdServiceHarness.play_three_matches(rig.service)
	return rig


func test_remove_ads_withdraws_an_interstitial_that_has_not_opened() -> void:
	var rig: LateRig = _waiting_interstitial()
	var out: Array = _start_show(rig.service, AdBackend.KIND_INTERSTITIAL)
	await AdServiceHarness.frames(2)
	AdServiceHarness.billing(rig.service).next_outcome = BillingBackend.Outcome.PURCHASED
	await rig.service.purchase_remove_ads()
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_array(rig.fake.cancels).contains_exactly([AdBackend.KIND_INTERSTITIAL])
	rig.fake.open_late()
	assert_array(_h.events).is_empty()


func test_a_withdrawn_interstitial_that_the_backend_cannot_recall_keeps_its_pair() -> void:
	var rig: LateRig = _waiting_interstitial()
	rig.fake.ignore_cancel = true
	var out: Array = _start_show(rig.service, AdBackend.KIND_INTERSTITIAL)
	await AdServiceHarness.frames(2)
	AdServiceHarness.billing(rig.service).next_outcome = BillingBackend.Outcome.PURCHASED
	await rig.service.purchase_remove_ads()
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	rig.fake.open_late()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_bool(rig.service._runs.is_busy()).is_false()


func test_a_consent_withdrawal_withdraws_an_interstitial_that_has_not_opened() -> void:
	var rig: LateRig = _waiting_interstitial()
	var out: Array = _start_show(rig.service, AdBackend.KIND_INTERSTITIAL)
	await AdServiceHarness.frames(2)
	rig.service._set_can_request(false)
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_array(rig.fake.cancels).contains_exactly([AdBackend.KIND_INTERSTITIAL])
	rig.fake.open_late()
	assert_array(_h.events).is_empty()
