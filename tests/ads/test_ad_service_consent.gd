extends GdUnitTestSuite
## P404: AdService's consent gate on FakeUmp. The flow, the timeout over the info update and the
## form load only (counted against a fake clock, never wall time), a form that never closes, the
## spy proof that no initialise, load or banner happens before "can request ads", and the flows
## excluding each other. Privacy options, the debug geography and the placeholder are
## test_ad_service_privacy.gd; the fake's model is test_consent_flow.gd.

var _h: AdServiceHarness
var _seen: Array[bool] = []


func before_test() -> void:
	_h = AdServiceHarness.new()
	_seen = []


func after_test() -> void:
	_h.dispose()


func _make() -> Node:
	var service: Node = auto_free(_h.make(false))
	service.consent_finished.connect(func(allowed: bool) -> void: _seen.append(allowed))
	return service


# --- the flow -------------------------------------------------------------------------------


func test_no_consent_needed_returns_true_in_the_same_frame_and_emits_once() -> void:
	var service: Node = _make()
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.ensure_consent()).is_true()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_seen).contains_exactly([true])
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(1)


func test_a_required_form_that_is_accepted_returns_true() -> void:
	var service: Node = _make()
	AdServiceHarness.ump(service).consent_required = true
	assert_bool(await service.ensure_consent()).is_true()
	assert_int(AdServiceHarness.ump(service).forms_shown).is_equal(1)
	assert_array(_seen).contains_exactly([true])


func test_a_declined_form_still_allows_limited_ads_as_umps_status_does() -> void:
	var service: Node = _make()
	AdServiceHarness.ump(service).consent_required = true
	AdServiceHarness.ump(service).obtained = false
	assert_bool(await service.ensure_consent()).is_true()
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(1)


func test_a_decline_that_blocks_returns_false_and_requests_nothing() -> void:
	var service: Node = _make()
	AdServiceHarness.ump(service).consent_required = true
	AdServiceHarness.ump(service).obtained = false
	AdServiceHarness.ump(service).decline_limits_ads = false
	assert_bool(await service.ensure_consent()).is_false()
	assert_array(_seen).contains_exactly([false])
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)
	assert_bool(service.rewarded_ready(&"x")).is_false()
	assert_array(AdServiceHarness.fake(service).load_requests).is_empty()


func test_offline_returns_false_at_once() -> void:
	var service: Node = _make()
	AdServiceHarness.ump(service).offline = true
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.ensure_consent()).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_seen).contains_exactly([false])
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)


func test_a_form_that_fails_to_load_returns_false() -> void:
	var service: Node = _make()
	AdServiceHarness.ump(service).consent_required = true
	AdServiceHarness.ump(service).form_load_fails = true
	assert_bool(await service.ensure_consent()).override_failure_message("form load").is_false()
	assert_int(AdServiceHarness.ump(service).forms_shown).is_equal(0)
	assert_array(_seen).contains_exactly([false])


func test_an_info_update_that_never_answers_ends_at_the_timeout() -> void:
	var service: Node = _make()
	var limit: int = AdServiceHarness.consent_timeout_ms(service)
	AdServiceHarness.ump(service).info_never_answers = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	_h.clock_ms = limit - 1
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("info update, before the limit").is_empty()
	_h.clock_ms = limit
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("info update, at the limit").contains_exactly(
		[false]
	)
	assert_array(_seen).contains_exactly([false])
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)


func test_a_form_that_never_loads_ends_at_the_same_deadline() -> void:
	var service: Node = _make()
	var limit: int = AdServiceHarness.consent_timeout_ms(service)
	AdServiceHarness.ump(service).consent_required = true
	AdServiceHarness.ump(service).form_never_loads = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	_h.clock_ms = limit - 1
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("form load, before the limit").is_empty()
	_h.clock_ms = limit
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("form load, at the limit").contains_exactly([false])
	assert_int(AdServiceHarness.ump(service).forms_shown).is_equal(0)


func test_the_deadline_is_shared_by_the_info_update_and_the_form_load() -> void:
	var service: Node = _make()
	var limit: int = AdServiceHarness.consent_timeout_ms(service)
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	ump.info_never_answers = true
	ump.form_never_loads = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	_h.clock_ms = limit - 100
	await AdServiceHarness.frames(2)
	ump.answer_info()
	await AdServiceHarness.frames(2)
	_h.clock_ms = limit - 1
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("form load, before the shared limit").is_empty()
	_h.clock_ms = limit
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("a fresh deadline for the load").contains_exactly(
		[false]
	)
	assert_int(ump.forms_shown).is_equal(0)


func test_a_form_that_never_closes_is_never_timed_out_and_nothing_proceeds_under_it() -> void:
	var service: Node = _make()
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	ump.form_never_closes = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(2)
	_h.clock_ms = AdServiceHarness.consent_timeout_ms(service) * 10
	await AdServiceHarness.frames(3)
	assert_array(out).override_failure_message("form open, past the limit").is_empty()
	assert_array(_seen).is_empty()
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)
	ump.dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("after the close").contains_exactly([true])
	assert_array(_seen).contains_exactly([true])


# --- the gate before every initialise and load ---------------------------------------------


func test_a_spy_sees_no_initialise_load_or_banner_before_consent() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	AdServiceHarness.play_three_matches(service)
	service.show_banner()
	assert_bool(service.rewarded_ready(&"x")).is_false()
	assert_bool(await service.show_rewarded(&"x")).is_false()
	assert_bool(await service.maybe_show_interstitial(&"post_match")).is_false()
	assert_array(fake.calls).override_failure_message("calls before consent").is_empty()
	assert_bool(fake.banner_visible).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)


func test_after_consent_initialise_comes_first_and_only_once() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	await service.ensure_consent()
	await service.ensure_consent()
	service.rewarded_ready(&"x")
	service.show_banner()
	assert_int(fake.initializations).is_equal(1)
	assert_array(fake.calls).contains_exactly(["initialize", "load:rewarded", "banner"])


func test_the_banner_follows_consent_and_announces_its_height() -> void:
	var service: Node = _make()
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	service.show_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	await service.ensure_consent()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	assert_array(heights).contains_exactly([FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP])


# --- the two flows exclude each other -------------------------------------------------------


func test_a_second_ensure_consent_waits_for_the_first() -> void:
	var service: Node = _make()
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	ump.form_never_closes = true
	var first: Array = AdServiceHarness.start(service.ensure_consent)
	var second: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(1)
	assert_int(ump.info_updates).is_equal(1)
	ump.dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(first).contains_exactly([true])
	assert_array(second).contains_exactly([true])
	assert_array(_seen).contains_exactly([true])


func test_privacy_options_during_ensure_consent_wait_and_show_no_second_form() -> void:
	var service: Node = _make()
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	ump.form_never_closes = true
	var consent: Array = AdServiceHarness.start(service.ensure_consent)
	var privacy: Array = AdServiceHarness.start(service.show_privacy_options)
	await AdServiceHarness.frames(2)
	assert_int(ump.forms_shown).override_failure_message("forms during consent").is_equal(1)
	assert_array(privacy).is_empty()
	ump.dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(consent).contains_exactly([true])
	assert_array(privacy).has_size(1)
	assert_int(ump.forms_shown).is_equal(1)
	assert_array(_seen).override_failure_message("one finish per flow").contains_exactly([true])


func test_ensure_consent_during_privacy_options_waits_and_starts_no_update() -> void:
	var service: Node = _make()
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	await service.ensure_consent()
	ump.form_never_closes = true
	var privacy: Array = AdServiceHarness.start(service.show_privacy_options)
	var consent: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(2)
	assert_int(ump.info_updates).override_failure_message("updates during privacy").is_equal(1)
	assert_array(consent).is_empty()
	ump.dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(privacy).has_size(1)
	assert_array(consent).contains_exactly([true])
	assert_array(_seen).override_failure_message("one finish per flow").contains_exactly(
		[true, true]
	)
