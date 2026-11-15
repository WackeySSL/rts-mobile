extends GdUnitTestSuite
## P403: AdService's rewarded API and banner signals on the fake backend (reward only in the
## callback, never waited for before it shows, the banner height and `banner_changed`).

const REWARD_PLACEMENT: StringName = &"double_xp"

var _h: AdServiceHarness = AdServiceHarness.new()


func before_test() -> void:
	_h = AdServiceHarness.new()


func _make(consent: bool = true) -> Node:
	return auto_free(_h.make(consent))


# --- rewarded ------------------------------------------------------------------------------


func test_rewarded_is_not_ready_without_consent_and_requests_no_load() -> void:
	var service: Node = _make(false)
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_false()
	assert_array(AdServiceHarness.fake(service).load_requests).is_empty()


func test_an_unfilled_rewarded_ad_is_not_ready_and_show_returns_false_at_once() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).fill = false
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_h.events).is_empty()


func test_a_rewarded_load_that_never_answers_is_not_ready_and_never_waited_for() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).load_never_answers = true
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)


func test_the_reward_is_granted_only_in_the_callback_before_the_close() -> void:
	var service: Node = _make()
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_true()
	var on_reward: Callable = func() -> void: _h.events.append("grant")
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT, on_reward)).is_true()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_array(_h.events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])


func test_a_close_without_the_reward_callback_grants_nothing() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).grant_reward = false
	var on_reward: Callable = func() -> void: _h.events.append("grant")
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT, on_reward)).is_false()
	assert_array(_h.events).contains_exactly(["open:double_xp", "close:double_xp"])


func test_a_rewarded_ad_waits_for_its_close_and_grants_at_the_callback() -> void:
	var service: Node = _make()
	service.fake_auto_close = false
	var on_reward: Callable = func() -> void: _h.events.append("grant")
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.show_rewarded(REWARD_PLACEMENT, on_reward)
	)
	_h.clock_ms = service._settings.fullscreen_timeout_ms * 5
	await AdServiceHarness.frames(3)
	assert_array(result).is_empty()
	assert_array(_h.events).contains_exactly(["open:double_xp"])
	AdServiceHarness.fake(service).finish_show()
	await AdServiceHarness.frames(1)
	assert_array(result).contains_exactly([true])
	assert_array(_h.events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])


func test_a_rewarded_show_that_never_opens_returns_false_at_the_timeout() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).show_never_opens = true
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.show_rewarded(REWARD_PLACEMENT)
	)
	_h.clock_ms = service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(2)
	assert_array(result).contains_exactly([false])
	assert_array(_h.events).is_empty()


func test_remove_ads_does_not_block_a_rewarded_ad() -> void:
	var service: Node = _make()
	service._ledger.remove_ads = true
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_true()


func test_a_failed_rewarded_load_is_retried_after_the_data_interval() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.fill = false
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	fake.fill = true
	var interval: int = service._settings.banner_reload_min_ms
	_h.clock_ms = interval - 1
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_false()
	assert_array(fake.load_requests).has_size(1)
	_h.clock_ms = interval
	assert_bool(service.rewarded_ready(REWARD_PLACEMENT)).is_true()


func test_a_reward_that_arrives_after_the_close_grants_nothing() -> void:
	# The ordering the real SDK uses is to confirm in P405; AdService grants only before the close.
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.reward_after_close = true
	var on_reward: Callable = func() -> void: _h.events.append("grant")
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT, on_reward)).is_false()
	assert_array(_h.events).contains_exactly(["open:double_xp", "close:double_xp"])


func test_a_rewarded_show_that_fails_returns_false_in_the_same_frame() -> void:
	var service: Node = _make()
	AdServiceHarness.fake(service).show_fails = true
	var frame: int = Engine.get_process_frames()
	assert_bool(await service.show_rewarded(REWARD_PLACEMENT)).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)


func test_a_late_rewarded_ad_grants_only_if_the_reward_comes_before_the_close() -> void:
	var service: Node = _make()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.show_never_opens = true
	fake.ignore_cancel = true
	var on_reward: Callable = func() -> void: _h.events.append("grant")
	var result: Array = AdServiceHarness.start(
		func() -> bool: return await service.show_rewarded(REWARD_PLACEMENT, on_reward)
	)
	_h.clock_ms = service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(1)
	assert_array(result).contains_exactly([false])
	fake.open_late()
	assert_array(_h.events).contains_exactly(["open:double_xp", "grant", "close:double_xp"])


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
	service._set_can_request(true)
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
	assert_bool(AdServiceHarness.fake(service).banner_visible).is_false()


func test_banner_requests_are_counted_with_a_floor_of_zero() -> void:
	var service: Node = _make()
	service.show_banner()
	service.show_banner()
	service.hide_banner()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	service.hide_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	service.hide_banner()
	service.show_banner()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)


func test_a_banner_never_shows_in_the_backend_without_consent() -> void:
	var service: Node = _make(false)
	service.show_banner()
	assert_bool(AdServiceHarness.fake(service).banner_visible).is_false()


func test_consent_without_a_band_shows_no_banner_and_height_zero() -> void:
	var service: Node = _make()
	service.fake_auto_close = false
	var host: Node = auto_free(Node.new())
	add_child(host)
	AdServiceHarness.fake(service).host = host
	service._refresh_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_bool(host.has_node("FakeTestBanner")).is_false()


func test_the_reward_callback_runs_once_even_if_the_backend_rewards_twice() -> void:
	var service: Node = auto_free(_h.make(true))
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	fake.show_never_closes = true
	fake.grant_reward = false
	var grants: Array[int] = []
	var out: Array = AdServiceHarness.start(
		func() -> bool:
			service.rewarded_ready(&"x")
			return await service.show_rewarded(&"x", func() -> void: grants.append(1))
	)
	await AdServiceHarness.frames(2)
	fake.reward_earned.emit(AdBackend.KIND_REWARDED)
	fake.reward_earned.emit(AdBackend.KIND_REWARDED)
	fake.finish_show()
	await AdServiceHarness.frames(2)
	assert_array(grants).has_size(1)
	assert_array(out).contains_exactly([true])
