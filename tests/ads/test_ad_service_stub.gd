extends GdUnitTestSuite
## P401's stub: every awaitable returns at once with the fake-mode values, and the autoload
## holds no child (so no banner).


func test_every_awaitable_returns_the_stub_value() -> void:
	var service: Node = get_tree().root.get_node("AdService")
	assert_bool(await service.ensure_consent()).is_false()
	await service.show_privacy_options()
	assert_bool(await service.purchase_remove_ads()).is_false()
	assert_bool(await service.restore_purchases()).is_false()
	assert_bool(await service.maybe_show_interstitial(&"post_match")).is_false()


func test_the_synchronous_calls_return_the_stub_values() -> void:
	var service: Node = get_tree().root.get_node("AdService")
	assert_bool(service.is_privacy_options_required()).is_false()
	assert_bool(service.has_remove_ads()).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)
	service.note_match_completed(300)
	assert_int(service.take_start_credits_bonus()).is_equal(0)
	assert_int(service.take_start_credits_bonus()).is_equal(0)


func test_the_autoload_holds_no_child() -> void:
	var service: Node = get_tree().root.get_node("AdService")
	assert_int(service.get_child_count()).is_equal(0)
