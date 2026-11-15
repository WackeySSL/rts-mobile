extends GdUnitTestSuite
## P403: AdService's rewarded API and banner signals on the fake backend (reward only in the
## callback, never waited for before it shows, the banner height and `banner_changed`).

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


# --- rewarded ------------------------------------------------------------------------------


func test_rewarded_is_not_ready_without_consent_and_requests_no_load() -> void:
	var service: Node = _make(false)
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_false()
	assert_array(_fake(service).load_requests).is_empty()


func test_an_unfilled_rewarded_ad_is_not_ready_and_show_returns_false_at_once() -> void:
	var service: Node = _make()
	_fake(service).fill = false
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_events).is_empty()


func test_a_rewarded_load_that_never_answers_is_not_ready_and_never_waited_for() -> void:
	var service: Node = _make()
	_fake(service).load_never_answers = true
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)


func test_the_reward_is_granted_only_in_the_callback_before_the_close() -> void:
	var service: Node = _make()
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_true()
	var on_reward: Callable = func() -> void: _events.append("grant")
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT, on_reward)).is_true()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])


func test_a_close_without_the_reward_callback_grants_nothing() -> void:
	var service: Node = _make()
	_fake(service).grant_reward = false
	var on_reward: Callable = func() -> void: _events.append("grant")
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT, on_reward)).is_false()
	assert_array(_events).contains_exactly(["open:double_xp", "close:double_xp"])


func test_a_rewarded_ad_waits_for_its_close_and_grants_at_the_callback() -> void:
	var service: Node = _make()
	service.fake_auto_close = false
	var on_reward: Callable = func() -> void: _events.append("grant")
	var result: Array = _start(
		func() -> bool: return await service.show_rewarded(REWARD_PLACEMENT, on_reward)
	)
	_clock_ms = service._settings.fullscreen_timeout_ms * 5
	await _frames(3)
	assert_array(result).is_empty()
	assert_array(_events).contains_exactly(["open:double_xp"])
	_fake(service).finish_show()
	await _frames(1)
	assert_array(result).contains_exactly([true])
	assert_array(_events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])


func test_a_rewarded_show_that_never_opens_returns_false_at_the_timeout() -> void:
	var service: Node = _make()
	_fake(service).show_never_opens = true
	var result: Array = _start(func() -> bool: return await service.show_rewarded(REWARD_PLACEMENT))
	_clock_ms = service._settings.fullscreen_timeout_ms
	await _frames(2)
	assert_array(result).contains_exactly([false])
	assert_array(_events).is_empty()


func test_remove_ads_does_not_block_a_rewarded_ad() -> void:
	var service: Node = _make()
	service._ledger.remove_ads = true
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_true()


func test_a_rewarded_ad_preloads_the_next_one_after_it_closes() -> void:
	var service: Node = _make()
	await service.show_rewarded(REWARD_PLACEMENT)
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_true()


# --- the banner ----------------------------------------------------------------------------


func test_the_banner_signals_follow_show_hide_consent_and_remove_ads() -> void:
	var service: Node = _make(false)
	var heights: Array[int] = []
	service.banner_changed.connect(func(height_dp: int) -> void: heights.append(height_dp))
	service.show_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_array(heights).is_empty()
	service._can_request_ads = true
	service._refresh_banner()
	service._refresh_banner()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	service._ledger.remove_ads = true
	service._refresh_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	service._ledger.remove_ads = false
	service._refresh_banner()
	service.hide_banner()
	assert_array(heights).contains_exactly(
		[FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP, 0, FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP, 0]
	)
	assert_bool(_fake(service).banner_visible).is_false()


func test_a_banner_never_shows_in_the_backend_without_consent() -> void:
	var service: Node = _make(false)
	service.show_banner()
	assert_bool(_fake(service).banner_visible).is_false()
