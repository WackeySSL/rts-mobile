extends GdUnitTestSuite
## P403: AdService's interstitial path on the fake backend. Caps through the facade, the timeouts
## (counted in frames against a fake clock, never wall time), a never-closing ad, a late open,
## paired ad_opened and ad_closed and `fake_auto_close` both ways.

const POST_MATCH: StringName = &"post_match"

var _h: AdServiceHarness = AdServiceHarness.new()


func before_test() -> void:
	_h = AdServiceHarness.new()


func _make(consent: bool = true) -> Node:
	return auto_free(_h.make(consent))


# --- caps through the facade ---------------------------------------------------------------


func test_the_third_match_after_240_seconds_shows_one() -> void:
	var service: Node = _make()
	AdServiceHarness.play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_array(AdServiceHarness.fake(service).shows).contains_exactly([&"interstitial"])


func test_matches_one_and_two_show_none() -> void:
	var service: Node = _make()
	service.note_match_completed(1000)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	service.note_match_completed(1000)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_array(AdServiceHarness.fake(service).shows).is_empty()


func test_239_seconds_show_none_and_240_show_one() -> void:
	var service: Node = _make()
	service.note_match_completed(100)
	service.note_match_completed(100)
	service.note_match_completed(39)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	var other: Node = _make()
	AdServiceHarness.play_three_matches(other)
	assert_bool(await other.maybe_show_interstitial(POST_MATCH)).is_true()


func test_twice_for_one_match_shows_once() -> void:
	var service: Node = _make()
	AdServiceHarness.play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_array(AdServiceHarness.fake(service).shows).has_size(1)


func test_a_shown_interstitial_resets_the_play_counter() -> void:
	var service: Node = _make()
	AdServiceHarness.play_three_matches(service)
	await service.maybe_show_interstitial(POST_MATCH)
	service.note_match_completed(100)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	service.note_match_completed(140)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()


func test_remove_ads_consent_and_other_placements_show_none() -> void:
	var removed: Node = _make()
	removed._ledger.remove_ads = true
	AdServiceHarness.play_three_matches(removed)
	assert_bool(await removed.maybe_show_interstitial(POST_MATCH)).is_false()
	var no_consent: Node = _make(false)
	AdServiceHarness.play_three_matches(no_consent)
	assert_bool(await no_consent.maybe_show_interstitial(POST_MATCH)).is_false()
	# No load is requested before consent, nor with Remove ads.
	for service: Node in [removed, no_consent]:
		assert_array(AdServiceHarness.fake(service).load_requests).is_empty()
		assert_array(AdServiceHarness.fake(service).shows).is_empty()
	var elsewhere: Node = _make()
	AdServiceHarness.play_three_matches(elsewhere)
	assert_bool(await elsewhere.maybe_show_interstitial(&"battle")).is_false()
	assert_array(AdServiceHarness.fake(elsewhere).shows).is_empty()


func test_the_stub_default_shows_nothing_without_consent() -> void:
	var service: Node = auto_free(load(AdServiceHarness.SCRIPT_PATH).new())
	AdServiceHarness.play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()


func test_the_start_credits_bonus_comes_once_capped_by_data() -> void:
	var service: Node = _make()
	assert_int(service.take_start_credits_bonus()).is_equal(0)
	var cap: int = service._settings.start_credits_bonus_max
	service._ledger.grant_start_credits_bonus(cap + 1000, cap)
	assert_int(service.take_start_credits_bonus()).is_equal(cap)
	assert_int(service.take_start_credits_bonus()).is_equal(0)


# --- same frame, no fill, pairing ----------------------------------------------------------


func test_with_auto_close_the_interstitial_returns_in_the_same_frame_with_paired_signals() -> void:
	var service: Node = _make()
	service.fake_auto_close = true
	AdServiceHarness.play_three_matches(service)
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])


func test_with_no_fill_it_returns_false_at_once_and_shows_nothing() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).fill = false
	AdServiceHarness.play_three_matches(service)
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_h.events).is_empty()
	assert_int(service._ledger.last_interstitial_match).is_equal(0)


func test_without_auto_close_the_ad_waits_for_its_close() -> void:
	var service: Node = _make()
	service.fake_auto_close = false
	AdServiceHarness.play_three_matches(service)
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	await AdServiceHarness.frames(3)
	assert_array(result).is_empty()
	assert_array(_h.events).contains_exactly(["open:post_match"])
	AdServiceHarness.fake(service).finish_show()
	await AdServiceHarness.frames(1)
	assert_array(result).contains_exactly([true])
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])


# --- never waits for what has not shown ----------------------------------------------------


func test_a_load_that_never_answers_returns_false_at_the_data_timeout() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).load_never_answers = true
	AdServiceHarness.play_three_matches(service)
	var timeout: int = service._settings.fullscreen_timeout_ms
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_h.clock_ms = timeout - 1
	await AdServiceHarness.frames(3)
	assert_array(result).is_empty()
	_h.clock_ms = timeout
	await AdServiceHarness.frames(1)
	assert_array(result).contains_exactly([false])
	assert_array(_h.events).is_empty()
	assert_array(AdServiceHarness.fake(service).shows).is_empty()
	assert_int(service._ledger.last_interstitial_match).is_equal(0)


func test_a_show_that_never_opens_returns_false_at_the_timeout_and_is_withdrawn() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.show_never_opens = true
	AdServiceHarness.play_three_matches(service)
	var timeout: int = service._settings.fullscreen_timeout_ms
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_h.clock_ms = timeout - 1
	await AdServiceHarness.frames(2)
	assert_array(result).is_empty()
	_h.clock_ms = timeout
	await AdServiceHarness.frames(1)
	assert_array(result).contains_exactly([false])
	assert_array(fake.cancels).contains_exactly([&"interstitial"])
	# The cancelled show cannot open late: no signal, no ledger change.
	fake.open_late()
	assert_array(_h.events).is_empty()
	assert_int(service._ledger.last_interstitial_match).is_equal(0)
	# A later call is not blocked by the abandoned one.
	fake.show_never_opens = false
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()


func test_a_backend_that_ignores_the_cancel_and_opens_late_is_still_paired_and_noted() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.show_never_opens = true
	fake.ignore_cancel = true
	AdServiceHarness.play_three_matches(service)
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_h.clock_ms = service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(1)
	assert_array(result).contains_exactly([false])
	fake.open_late()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_int(service._ledger.last_interstitial_match).is_equal(3)


func test_a_late_ad_that_has_not_closed_keeps_the_service_busy() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.show_never_opens = true
	fake.ignore_cancel = true
	fake.show_never_closes = true
	AdServiceHarness.play_three_matches(service)
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_h.clock_ms = service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(1)
	fake.open_late()
	assert_array(_h.events).contains_exactly(["open:post_match"])
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	fake.finish_show()
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
	assert_array(result).contains_exactly([false])


func test_a_show_that_fails_returns_false_in_the_same_frame() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).show_fails = true
	AdServiceHarness.play_three_matches(service)
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_h.events).is_empty()
	assert_int(service._ledger.last_interstitial_match).is_equal(0)


func test_the_interstitial_is_preloaded_after_a_match_and_after_each_show() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	service.note_match_completed(100)
	assert_array(fake.load_requests).contains_exactly([&"interstitial"])
	service.note_match_completed(100)
	service.note_match_completed(40)
	# Already loaded: no second request.
	assert_array(fake.load_requests).has_size(1)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	# The show used it up and the next one is requested at once.
	assert_array(fake.load_requests).has_size(2)


# --- never closing -------------------------------------------------------------------------


func test_once_shown_the_call_waits_for_the_close_past_the_timeout() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).show_never_closes = true
	AdServiceHarness.play_three_matches(service)
	var timeout: int = service._settings.fullscreen_timeout_ms
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_h.clock_ms = timeout * 10
	await AdServiceHarness.frames(5)
	assert_array(result).is_empty()
	assert_array(_h.events).contains_exactly(["open:post_match"])
	# Nothing else may start under the ad.
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	AdServiceHarness.fake(service).finish_show()
	await AdServiceHarness.frames(1)
	assert_array(result).contains_exactly([true])
	assert_array(_h.events).contains_exactly(["open:post_match", "close:post_match"])
