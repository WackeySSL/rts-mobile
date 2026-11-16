extends GdUnitTestSuite
## P407: the ledger is the `ads` section of SaveService (the harness's own, on a temp file), saved
## on every change; the entitlement is saved, flushed, before `entitlement_changed` is emitted.

var _h: AdServiceHarness


func before_test() -> void:
	_h = AdServiceHarness.new()


func after_test() -> void:
	_h.dispose()


func _service(load_ledger: bool = true) -> Node:
	return auto_free(_h.make(true, load_ledger))


func _section() -> Dictionary:
	return _h.save_service().get_section(&"ads")


## What the file holds, read by a second SaveService on the same path.
func _section_in_file() -> Dictionary:
	var other: Node = AdServiceHarness.SaveServiceScript.new()
	other.set_path_override(_h.save_path())
	var values: Dictionary = other.get_section(&"ads")
	other.free()
	return values


func _own_the_product(service: Node) -> void:
	var billing: FakeBilling = AdServiceHarness.billing(service)
	billing.add_owned(service._settings.remove_ads_product_id, "t1")


func test_a_missing_section_gives_the_defaults() -> void:
	var service: Node = _service()
	assert_dict(service._ledger.to_dict()).is_equal(AdLedger.new().to_dict())


func test_a_corrupt_section_gives_the_defaults() -> void:
	_h.seed_section({"completed_matches": "x", "remove_ads": 7, "play_s_since_interstitial": -3})
	var service: Node = _service()
	assert_dict(service._ledger.to_dict()).is_equal(AdLedger.new().to_dict())


func test_nothing_is_saved_before_the_section_was_read() -> void:
	_h.seed_section({"completed_matches": 9})
	var service: Node = _service(false)
	service.note_match_completed(60)
	assert_dict(_section()).override_failure_message("a fresh ledger overwrote the save").is_equal(
		{"completed_matches": 9}
	)


func test_ready_reads_the_section() -> void:
	_h.seed_section({"completed_matches": 5, "pending_start_credits": 120})
	var service: Node = _service(false)
	add_child(service)
	assert_int(service._ledger.completed_matches).is_equal(5)
	assert_int(service.take_start_credits_bonus()).is_equal(120)


func test_all_five_fields_round_trip_through_the_file() -> void:
	var service: Node = _service()
	AdServiceHarness.play_three_matches(service)
	var shown: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(&"post_match")
	)
	await AdServiceHarness.frames(3)
	assert_array(shown).contains_exactly([true])
	service.note_match_completed(50)
	assert_bool(service.grant_start_credits_bonus(300)).is_true()
	_own_the_product(service)
	assert_bool(await service.restore_purchases()).is_true()
	var expected: Dictionary = {
		"completed_matches": 4,
		"play_s_since_interstitial": 50,
		"last_interstitial_match": 3,
		"remove_ads": true,
		"pending_start_credits": 300,
	}
	(
		assert_dict(_section_in_file())
		. override_failure_message("the file does not hold the values")
		. is_equal(expected)
	)
	var again: Node = _service()
	assert_dict(again._ledger.to_dict()).is_equal(expected)


func test_a_finished_match_is_saved() -> void:
	var service: Node = _service()
	service.note_match_completed(60)
	assert_int(_section().get("completed_matches", -1)).is_equal(1)
	assert_int(_section().get("play_s_since_interstitial", -1)).is_equal(60)


func test_a_grant_is_saved_at_once() -> void:
	var service: Node = _service()
	assert_bool(service.grant_start_credits_bonus(200)).is_true()
	assert_int(_section_in_file().get("pending_start_credits", -1)).is_equal(200)


func test_a_grant_is_capped_and_does_not_stack() -> void:
	var service: Node = _service()
	var cap: int = service._settings.start_credits_bonus_max
	assert_bool(service.grant_start_credits_bonus(cap + 1000)).is_true()
	assert_bool(service.grant_start_credits_bonus(10)).is_false()
	assert_int(_section_in_file().get("pending_start_credits", -1)).is_equal(cap)


func test_taking_the_bonus_is_saved() -> void:
	var service: Node = _service()
	service.grant_start_credits_bonus(200)
	assert_int(service.take_start_credits_bonus()).is_equal(200)
	assert_int(_section().get("pending_start_credits", -1)).is_equal(0)


func test_taking_nothing_writes_nothing() -> void:
	var service: Node = _service()
	assert_int(service.take_start_credits_bonus()).is_equal(0)
	assert_dict(_section()).override_failure_message("a take with nothing pending saved").is_empty()


func test_a_shown_interstitial_is_saved_at_once() -> void:
	var service: Node = _service()
	AdServiceHarness.play_three_matches(service)
	var shown: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(&"post_match")
	)
	await AdServiceHarness.frames(3)
	assert_array(shown).contains_exactly([true])
	var in_file: Dictionary = _section_in_file()
	assert_int(in_file.get("last_interstitial_match", -1)).is_equal(3)
	assert_int(in_file.get("play_s_since_interstitial", -1)).is_equal(0)


func test_a_rewarded_ad_does_not_save_the_ledger() -> void:
	var service: Node = _service()
	assert_bool(await service.show_rewarded(&"offer")).is_true()
	assert_dict(_section()).override_failure_message("a rewarded ad saved").is_empty()


func test_a_purchase_is_in_the_file_before_the_signal() -> void:
	var service: Node = _service()
	var seen: Array[bool] = []
	service.entitlement_changed.connect(
		func(_on: bool) -> void: seen.append(_section_in_file().get("remove_ads", false) as bool)
	)
	_own_the_product(service)
	assert_bool(await service.restore_purchases()).is_true()
	assert_array(seen).override_failure_message("saved after the signal").contains_exactly([true])


func test_a_refund_is_in_the_file_before_the_signal() -> void:
	var service: Node = _service()
	_own_the_product(service)
	assert_bool(await service.restore_purchases()).is_true()
	var seen: Array[bool] = []
	service.entitlement_changed.connect(
		func(_on: bool) -> void: seen.append(_section_in_file().get("remove_ads", true) as bool)
	)
	AdServiceHarness.billing(service).refund()
	assert_bool(await service.restore_purchases()).is_false()
	assert_array(seen).override_failure_message("saved after the signal").contains_exactly([false])
