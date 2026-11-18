extends GdUnitTestSuite
## P409: AdService.settle_fullscreen, the wait that keeps a match from being built while a late
## full-screen ad (a show that timed out and cannot be recalled) may still open.

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


func _late_rig(kind: StringName) -> LateRig:
	var rig: LateRig = LateRig.new()
	rig.service = auto_free(_h.make())
	rig.fake = AdServiceHarness.fake(rig.service)
	rig.fake.show_never_opens = true
	rig.fake.ignore_cancel = true
	AdServiceHarness.play_three_matches(rig.service)
	var grant: Callable = func() -> void: _h.events.append("grant")
	var out: Array = AdServiceHarness.start(
		func() -> bool:
			if kind == AdBackend.KIND_REWARDED:
				return await rig.service.show_rewarded(REWARD, grant)
			return await rig.service.maybe_show_interstitial(POST_MATCH)
	)
	await AdServiceHarness.frames(2)
	_h.clock_ms = rig.service._settings.fullscreen_timeout_ms
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("setup: the show did not time out").is_equal([false])
	return rig if out == [false] else null


func _settle(service: Node) -> Array:
	return AdServiceHarness.start(
		func() -> bool:
			await service.settle_fullscreen()
			return true
	)


func test_settle_returns_at_once_with_no_run() -> void:
	var service: Node = auto_free(_h.make())
	assert_array(_settle(service)).is_equal([true])  # No frame was awaited.


func test_settle_returns_at_once_after_a_normal_open_and_close() -> void:
	var service: Node = auto_free(_h.make())
	AdServiceHarness.play_three_matches(service)
	assert_bool(await service.maybe_show_interstitial(POST_MATCH)).is_true()
	assert_array(_settle(service)).is_equal([true])


func test_settle_waits_for_a_late_interstitial_to_open_and_close() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	rig.fake.show_never_closes = true
	var out: Array = _settle(rig.service)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	rig.fake.open_late()
	await AdServiceHarness.frames(2)
	assert_array(out).override_failure_message("open, not closed").is_empty()
	rig.fake.finish_show()
	await AdServiceHarness.frames(2)
	assert_array(out).is_equal([true])


func test_settle_waits_for_a_late_show_failure() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	var out: Array = _settle(rig.service)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	rig.fake.show_failed.emit(AdBackend.KIND_INTERSTITIAL)
	await AdServiceHarness.frames(2)
	assert_array(out).is_equal([true])


func test_settle_gives_up_at_the_cap_and_later_calls_do_not_wait_again() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	var cap: int = rig.service._settings.fullscreen_late_cap_ms
	var start: int = _h.clock_ms  # The moment the run went late.
	var out: Array = _settle(rig.service)
	_h.clock_ms = start + cap - 1
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_h.clock_ms = start + cap
	await AdServiceHarness.frames(2)
	assert_array(out).is_equal([true])
	assert_int(rig.service._runs.late_count()).override_failure_message("still listening").is_equal(
		1
	)
	assert_array(_settle(rig.service)).override_failure_message("second call").is_equal([true])


func test_settle_waits_for_the_close_of_an_ad_that_opened_after_the_cap_window() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_INTERSTITIAL)
	if rig == null:
		return
	rig.fake.show_never_closes = true
	var cap: int = rig.service._settings.fullscreen_late_cap_ms
	var start: int = _h.clock_ms
	var out: Array = _settle(rig.service)
	_h.clock_ms = start + cap - 1
	await AdServiceHarness.frames(2)
	rig.fake.open_late()
	_h.clock_ms = start + cap * 3  # An ad on screen is waited for without a cap.
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	rig.fake.finish_show()
	await AdServiceHarness.frames(2)
	assert_array(out).is_equal([true])


func test_settle_waits_for_a_late_rewarded_ad_too() -> void:
	var rig: LateRig = await _late_rig(AdBackend.KIND_REWARDED)
	if rig == null:
		return
	var out: Array = _settle(rig.service)
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	rig.fake.open_late()
	await AdServiceHarness.frames(2)
	assert_array(out).is_equal([true])
