extends GdUnitTestSuite
## P404: AdService's consent gate on FakeUmp. The flow, the timeout over the info update and the
## form load only (counted against a fake clock, never wall time), a form that never closes, the
## spy proof that no initialise, load or banner happens before "can request ads". Privacy options,
## the debug geography and the placeholder are test_ad_service_privacy.gd.

var _h: AdServiceHarness = AdServiceHarness.new()
var _seen: Array[bool] = []


func before_test() -> void:
	_h = AdServiceHarness.new()
	_seen = []


func _make() -> Node:
	var service: Node = auto_free(_h.make(false))
	service.consent_finished.connect(func(allowed: bool) -> void: _seen.append(allowed))
	return service


static func _ump(service: Node) -> FakeUmp:
	return service._consent as FakeUmp


func _timeout(service: Node) -> int:
	return service._settings.consent_timeout_ms


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
	_ump(service).consent_required = true
	assert_bool(await service.ensure_consent()).is_true()
	assert_int(_ump(service).forms_shown).is_equal(1)
	assert_array(_seen).contains_exactly([true])


func test_a_required_form_that_is_declined_returns_false_and_requests_nothing() -> void:
	var service: Node = _make()
	_ump(service).consent_required = true
	_ump(service).obtained = false
	assert_bool(await service.ensure_consent()).is_false()
	assert_array(_seen).contains_exactly([false])
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)
	assert_bool(service.rewarded_ready(&"x")).is_false()
	assert_array(AdServiceHarness.fake(service).load_requests).is_empty()


func test_offline_returns_false_at_once() -> void:
	var service: Node = _make()
	_ump(service).offline = true
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.ensure_consent()).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_seen).contains_exactly([false])
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)


func test_an_info_update_that_never_answers_ends_at_the_timeout() -> void:
	var service: Node = _make()
	_ump(service).info_never_answers = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	_h.clock_ms = _timeout(service) - 1
	await AdServiceHarness.frames(2)
	assert_array(out).is_empty()
	_h.clock_ms = _timeout(service)
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_array(_seen).contains_exactly([false])
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)


func test_a_form_that_never_loads_ends_at_the_same_deadline() -> void:
	var service: Node = _make()
	_ump(service).consent_required = true
	_ump(service).form_never_loads = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	_h.clock_ms = _timeout(service) - 1
	await AdServiceHarness.frames(2)
	assert_array(out).is_empty()
	_h.clock_ms = _timeout(service)
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_int(_ump(service).forms_shown).is_equal(0)


func test_a_form_that_never_closes_is_never_timed_out_and_nothing_proceeds_under_it() -> void:
	var service: Node = _make()
	_ump(service).consent_required = true
	_ump(service).form_never_closes = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(2)
	_h.clock_ms = _timeout(service) * 10
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	assert_array(_seen).is_empty()
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)
	_ump(service).dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([true])
	assert_array(_seen).contains_exactly([true])


func test_a_second_call_waits_for_the_first() -> void:
	var service: Node = _make()
	_ump(service).consent_required = true
	_ump(service).form_never_closes = true
	var first: Array = AdServiceHarness.start(service.ensure_consent)
	var second: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(1)
	assert_int(_ump(service).info_updates).is_equal(1)
	_ump(service).dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(first).contains_exactly([true])
	assert_array(second).contains_exactly([true])
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
	assert_int(fake.initializations).is_equal(0)
	assert_array(fake.load_requests).is_empty()
	assert_array(fake.shows).is_empty()
	assert_bool(fake.banner_visible).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)


func test_after_consent_the_sdk_is_initialised_once_and_loads_are_allowed() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	await service.ensure_consent()
	await service.ensure_consent()
	assert_int(fake.initializations).is_equal(1)
	service.rewarded_ready(&"x")
	assert_array(fake.load_requests).contains_exactly([&"rewarded"])


func test_the_banner_follows_consent_and_announces_its_height() -> void:
	var service: Node = _make()
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	service.show_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	await service.ensure_consent()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	assert_array(heights).contains_exactly([FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP])
