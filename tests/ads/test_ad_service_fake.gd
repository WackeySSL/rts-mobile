extends GdUnitTestSuite
## P403: AdService on the fake backend. Caps through the facade, the timeouts (counted in frames
## against a fake clock, never wall time), reward only in the callback, paired ad_opened and
## ad_closed, the banner signals and `fake_auto_close` both ways.

const SCRIPT_PATH: String = "res://game/ads/AdService.gd"
const POST_MATCH: StringName = &"post_match"
const REWARD_PLACEMENT: StringName = &"double_xp"

var _script: GDScript = load(SCRIPT_PATH) as GDScript
var _clock_ms: int = 0
var _events: Array[String] = []


func before_test() -> void:
	_clock_ms = 0
	_events.clear()


## A service on a fake backend with consent granted, a fake clock and event logging.
func _make(consent: bool = true) -> Node:
	var service: Node = auto_free(_script.new())
	service._can_request_ads = consent
	service._now_ms = func() -> int: return _clock_ms
	service.ad_opened.connect(
		func(placement: StringName) -> void: _events.append("open:" + placement)
	)
	service.ad_closed.connect(
		func(placement: StringName) -> void: _events.append("close:" + placement)
	)
	return service


func _fake(service: Node) -> FakeAdBackend:
	return service._backend as FakeAdBackend


## Three finished matches, 240 s in all: the first interstitial may show.
func _play_three_matches(service: Node) -> void:
	service.note_match_completed(100)
	service.note_match_completed(100)
	service.note_match_completed(40)


## Starts a coroutine without awaiting it; the result lands in the returned array.
func _start(call: Callable) -> Array:
	var out: Array = []
	var run: Callable = func() -> void: out.append(await call.call())
	run.call()
	return out


func _frames(count: int) -> void:
	for i: int in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


# --- caps through the facade ---------------------------------------------------------------


func test_the_third_match_after_240_seconds_shows_one() -> void:
	var service: Node = _make()
	_play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_array(_fake(service).shows).contains_exactly([&"interstitial"])


func test_matches_one_and_two_show_none() -> void:
	var service: Node = _make()
	service.note_match_completed(1000)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	service.note_match_completed(1000)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_array(_fake(service).shows).is_empty()


func test_239_seconds_show_none_and_240_show_one() -> void:
	var service: Node = _make()
	service.note_match_completed(100)
	service.note_match_completed(100)
	service.note_match_completed(39)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	var other: Node = _make()
	_play_three_matches(other)
	assert_bool(await other.maybe_show_interstitial(POST_MATCH)).is_true()


func test_twice_for_one_match_shows_once() -> void:
	var service: Node = _make()
	_play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_array(_fake(service).shows).has_size(1)


func test_a_shown_interstitial_resets_the_play_counter() -> void:
	var service: Node = _make()
	_play_three_matches(service)
	await service.maybe_show_interstitial(POST_MATCH)
	service.note_match_completed(100)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	service.note_match_completed(140)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()


func test_remove_ads_consent_and_other_placements_show_none() -> void:
	var removed: Node = _make()
	_play_three_matches(removed)
	removed._ledger.remove_ads = true
	assert_bool(await removed.maybe_show_interstitial(POST_MATCH)).is_false()
	var no_consent: Node = _make(false)
	_play_three_matches(no_consent)
	assert_bool(await no_consent.maybe_show_interstitial(POST_MATCH)).is_false()
	var elsewhere: Node = _make()
	_play_three_matches(elsewhere)
	assert_bool(await elsewhere.maybe_show_interstitial(&"battle")).is_false()
	for service: Node in [removed, no_consent, elsewhere]:
		assert_array(_fake(service).load_requests).is_empty()
		assert_array(_fake(service).shows).is_empty()


func test_the_stub_default_shows_nothing_without_consent() -> void:
	var service: Node = auto_free(_script.new())
	_play_three_matches(service)
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
	_play_three_matches(service)
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_events).contains_exactly(["open:post_match", "close:post_match"])


func test_with_no_fill_it_returns_false_at_once_and_shows_nothing() -> void:
	var service: Node = _make()
	_fake(service).fill = false
	_play_three_matches(service)
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_events).is_empty()
	assert_int(service._ledger.last_interstitial_match).is_equal(0)


func test_without_auto_close_the_ad_waits_for_its_close() -> void:
	var service: Node = _make()
	service.fake_auto_close = false
	_play_three_matches(service)
	var result: Array = _start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	await _frames(3)
	assert_array(result).is_empty()
	assert_array(_events).contains_exactly(["open:post_match"])
	_fake(service).finish_show()
	await _frames(1)
	assert_array(result).contains_exactly([true])
	assert_array(_events).contains_exactly(["open:post_match", "close:post_match"])


# --- never waits for what has not shown ----------------------------------------------------


func test_a_load_that_never_answers_returns_false_at_the_data_timeout() -> void:
	var service: Node = _make()
	_fake(service).load_never_answers = true
	_play_three_matches(service)
	var timeout: int = service._settings.fullscreen_timeout_ms
	var result: Array = _start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_clock_ms = timeout - 1
	await _frames(3)
	assert_array(result).is_empty()
	_clock_ms = timeout
	await _frames(1)
	assert_array(result).contains_exactly([false])
	assert_array(_events).is_empty()
	assert_array(_fake(service).shows).is_empty()
	assert_int(service._ledger.last_interstitial_match).is_equal(0)


func test_a_show_that_never_opens_returns_false_at_the_timeout_and_is_withdrawn() -> void:
	var service: Node = _make()
	_fake(service).show_never_opens = true
	_play_three_matches(service)
	var timeout: int = service._settings.fullscreen_timeout_ms
	var result: Array = _start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_clock_ms = timeout - 1
	await _frames(2)
	assert_array(result).is_empty()
	_clock_ms = timeout
	await _frames(1)
	assert_array(result).contains_exactly([false])
	assert_array(_events).is_empty()
	# A later call is not blocked by the abandoned one.
	_fake(service).show_never_opens = false
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()


# --- never closing -------------------------------------------------------------------------


func test_once_shown_the_call_waits_for_the_close_past_the_timeout() -> void:
	var service: Node = _make()
	_fake(service).show_never_closes = true
	_play_three_matches(service)
	var timeout: int = service._settings.fullscreen_timeout_ms
	var result: Array = _start(
		func() -> bool: return await service.maybe_show_interstitial(POST_MATCH)
	)
	_clock_ms = timeout * 10
	await _frames(5)
	assert_array(result).is_empty()
	assert_array(_events).contains_exactly(["open:post_match"])
	# Nothing else may start under the ad.
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_false()
	_fake(service).finish_show()
	await _frames(1)
	assert_array(result).contains_exactly([true])
	assert_array(_events).contains_exactly(["open:post_match", "close:post_match"])
