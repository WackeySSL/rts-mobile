extends GdUnitTestSuite
## P401's stub values that still hold: every awaitable is a real coroutine that returns in the same
## frame (consent is the fake UMP with nothing required since P404), nothing shows, and no
## placeholder node is drawn. The awaitable calls
## go through the typed autoload global, so the suite fails to compile if a method stops being a
## coroutine. Anything that writes state (the ledger) uses a fresh instance, never the autoload.

const SCRIPT_PATH: String = "res://game/ads/AdService.gd"


func test_every_awaitable_returns_the_stub_value_in_the_same_frame() -> void:
	var frame: int = Engine.get_process_frames()
	var service: Node = auto_free(load(SCRIPT_PATH).new())
	assert_bool(await service.ensure_consent()).is_true()
	await AdService.show_privacy_options()
	assert_bool(await AdService.purchase_remove_ads()).is_false()
	assert_bool(await AdService.restore_purchases()).is_false()
	assert_bool(await AdService.maybe_show_interstitial(&"post_match")).is_false()
	assert_int(Engine.get_process_frames()).is_equal(frame)


func test_the_synchronous_calls_return_the_stub_values() -> void:
	assert_bool(AdService.is_privacy_options_required()).is_false()
	assert_bool(AdService.has_remove_ads()).is_false()
	assert_int(AdService.banner_height_dp()).is_equal(0)
	assert_int(AdService.take_start_credits_bonus()).is_equal(0)
	assert_int(AdService.take_start_credits_bonus()).is_equal(0)


func test_a_match_completed_changes_nothing_visible_without_consent() -> void:
	var service: Node = auto_free(load(SCRIPT_PATH).new())
	service.note_match_completed(300)
	assert_int(service.take_start_credits_bonus()).is_equal(0)
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_int(service._backend.load_requests.size()).is_equal(0)


func test_the_autoload_draws_no_placeholder_child() -> void:
	assert_int(AdService.get_child_count()).is_equal(0)
