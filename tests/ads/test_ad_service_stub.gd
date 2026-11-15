extends GdUnitTestSuite
## P401's stub: every awaitable is a real coroutine that returns in the same frame with the
## fake-mode values, and the autoload holds no child (so no banner). The calls go through the
## typed autoload global, so the suite fails to compile if a method stops being a coroutine.


func test_every_awaitable_returns_the_stub_value_in_the_same_frame() -> void:
	var frame: int = Engine.get_process_frames()
	assert_bool(await AdService.ensure_consent()).is_false()
	await AdService.show_privacy_options()
	assert_bool(await AdService.purchase_remove_ads()).is_false()
	assert_bool(await AdService.restore_purchases()).is_false()
	assert_bool(await AdService.maybe_show_interstitial(&"post_match")).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)


func test_ensure_consent_emits_consent_finished_false_before_it_returns() -> void:
	var seen: Array[bool] = []
	var record: Callable = func(can_request_ads: bool) -> void: seen.append(can_request_ads)
	AdService.consent_finished.connect(record)
	var result: bool = await AdService.ensure_consent()
	AdService.consent_finished.disconnect(record)
	assert_bool(result).is_false()
	assert_array(seen).contains_exactly([false])


func test_the_synchronous_calls_return_the_stub_values() -> void:
	assert_bool(AdService.is_privacy_options_required()).is_false()
	assert_bool(AdService.has_remove_ads()).is_false()
	assert_int(AdService.banner_height_dp()).is_equal(0)
	AdService.note_match_completed(300)
	assert_int(AdService.take_start_credits_bonus()).is_equal(0)
	assert_int(AdService.take_start_credits_bonus()).is_equal(0)


func test_the_autoload_holds_no_child() -> void:
	assert_int(AdService.get_child_count()).is_equal(0)
