extends GdUnitTestSuite
## P407: the ledger is the `ads` section of SaveService (a temp file, see AdServiceHarness), saved
## on every change; the entitlement is saved before `entitlement_changed` is emitted.

var _h: AdServiceHarness


func before_test() -> void:
	_h = AdServiceHarness.new()


func _section() -> Dictionary:
	return AdServiceHarness._save().get_section(&"ads")


func test_a_missing_section_gives_the_defaults() -> void:
	var service: Node = auto_free(_h.make())
	assert_bool(service.has_remove_ads()).is_false()
	assert_int(service.take_start_credits_bonus()).is_equal(0)


func test_a_corrupt_section_gives_the_defaults() -> void:
	AdServiceHarness.seed_section(
		{"completed_matches": "x", "remove_ads": 7, "play_s_since_interstitial": -3}
	)
	var service: Node = auto_free(_h.make())
	assert_bool(service.has_remove_ads()).is_false()
	assert_dict(service._ledger.to_dict()).is_equal(AdLedger.new().to_dict())


func test_the_counters_round_trip_through_the_file() -> void:
	var service: Node = auto_free(_h.make())
	AdServiceHarness.play_three_matches(service)
	service._ledger.grant_start_credits_bonus(300, 500)
	service._save_ledger()
	var save: Node = AdServiceHarness._save()
	assert_int(save.flush()).is_equal(OK)
	save.set_path_override(AdServiceHarness.SAVE_PATH)  # Reloads from the file.
	var again: Node = auto_free(_h.make())
	assert_int(again._ledger.completed_matches).is_equal(3)
	assert_int(again._ledger.play_s_since_interstitial).is_equal(240)
	assert_int(again.take_start_credits_bonus()).is_equal(300)


func test_each_change_is_saved() -> void:
	var service: Node = auto_free(_h.make())
	service.note_match_completed(60)
	assert_int(_section()["completed_matches"]).is_equal(1)
	service._ledger.grant_start_credits_bonus(200, 500)
	service._save_ledger()
	assert_int(_section()["pending_start_credits"]).is_equal(200)
	service.take_start_credits_bonus()
	assert_int(_section()["pending_start_credits"]).is_equal(0)
	AdServiceHarness.play_three_matches(service)
	var shown: Array = AdServiceHarness.start(
		func() -> bool: return await service.maybe_show_interstitial(&"post_match")
	)
	await AdServiceHarness.frames(3)
	assert_array(shown).contains_exactly([true])
	assert_int(_section()["last_interstitial_match"]).is_equal(4)
	assert_int(_section()["play_s_since_interstitial"]).is_equal(0)


func test_the_entitlement_is_saved_before_it_is_announced() -> void:
	var service: Node = auto_free(_h.make())
	var seen: Array[bool] = []
	service.entitlement_changed.connect(
		func(_on: bool) -> void: seen.append(bool(_section().get("remove_ads", false)))
	)
	service._on_entitlement_changed(true)
	assert_array(seen).contains_exactly([true])
	service._on_entitlement_changed(false)
	assert_array(seen).contains_exactly([true, false])
