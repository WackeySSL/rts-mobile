extends GdUnitTestSuite
## P402: AdCaps rules (ADR 0039 section 4) against a copy of the shipped settings.

var _settings: AdsSettingsDef


func before_test() -> void:
	_settings = AdsSettingsDef.load_default().duplicate() as AdsSettingsDef


func _ledger(matches: int, play_s: int) -> AdLedger:
	var ledger: AdLedger = AdLedger.new()
	ledger.completed_matches = matches
	ledger.play_s_since_interstitial = play_s
	return ledger


func _may(ledger: AdLedger, consent: bool = true) -> bool:
	return AdCaps.may_show_interstitial(_settings, ledger, AdCaps.PLACEMENT_POST_MATCH, consent)


func _why(ledger: AdLedger, consent: bool = true) -> StringName:
	return AdCaps.denial_reason(_settings, ledger, AdCaps.PLACEMENT_POST_MATCH, consent)


func test_no_interstitial_in_the_free_matches_even_with_long_play() -> void:
	for matches: int in range(0, _settings.interstitial_free_matches + 1):
		var ledger: AdLedger = _ledger(matches, 9999)
		assert_bool(_may(ledger)).override_failure_message("matches=%d" % matches).is_false()
		assert_str(String(_why(ledger))).is_equal("free_matches")


func test_the_first_match_after_the_free_ones_needs_the_min_play_time() -> void:
	var first: int = _settings.interstitial_free_matches + 1
	var need: int = _settings.interstitial_min_play_s
	assert_bool(_may(_ledger(first, need - 1))).is_false()
	assert_str(String(_why(_ledger(first, need - 1)))).is_equal("play_time")
	assert_bool(_may(_ledger(first, need))).is_true()
	assert_bool(_may(_ledger(first, need + 1))).is_true()


func test_one_per_completed_match() -> void:
	var ledger: AdLedger = _ledger(3, _settings.interstitial_min_play_s + 60)
	assert_bool(_may(ledger)).is_true()
	ledger.note_interstitial_shown()
	ledger.play_s_since_interstitial = 9999
	assert_bool(_may(ledger)).is_false()
	assert_str(String(_why(ledger))).is_equal("per_match")
	ledger.note_match_completed(_settings.interstitial_min_play_s)
	assert_bool(_may(ledger)).is_true()


func test_a_shown_interstitial_resets_the_play_counter() -> void:
	var ledger: AdLedger = _ledger(3, _settings.interstitial_min_play_s + 60)
	ledger.note_interstitial_shown()
	assert_int(ledger.play_s_since_interstitial).is_equal(0)
	assert_int(ledger.last_interstitial_match).is_equal(3)
	ledger.note_match_completed(_settings.interstitial_min_play_s - 1)
	assert_bool(_may(ledger)).is_false()
	assert_str(String(_why(ledger))).is_equal("play_time")
	ledger.note_match_completed(1)
	assert_bool(_may(ledger)).is_true()


func test_the_match_after_a_shown_one_can_show_once_play_time_accumulates_there() -> void:
	var ledger: AdLedger = _ledger(3, _settings.interstitial_min_play_s)
	ledger.note_interstitial_shown()
	ledger.note_match_completed(_settings.interstitial_min_play_s - 1)
	assert_bool(_may(ledger)).is_false()
	ledger.play_s_since_interstitial += 1
	assert_bool(_may(ledger)).is_true()


func test_play_seconds_add_up_across_matches() -> void:
	var need: int = _settings.interstitial_min_play_s
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(100)
	ledger.note_match_completed(100)
	ledger.note_match_completed(need - 201)
	assert_int(ledger.play_s_since_interstitial).is_equal(need - 1)
	assert_bool(_may(ledger)).is_false()
	ledger.note_match_completed(1)
	assert_bool(_may(ledger)).is_true()


func test_a_saved_shown_match_still_blocks_a_second_one_after_loading() -> void:
	var ledger: AdLedger = _ledger(3, _settings.interstitial_min_play_s + 60)
	ledger.note_interstitial_shown()
	var back: AdLedger = AdLedger.from_dict(ledger.to_dict())
	back.play_s_since_interstitial = 9999
	assert_str(String(_why(back))).is_equal("per_match")


func test_remove_ads_blocks_even_with_consent() -> void:
	var ledger: AdLedger = _ledger(9, 9999)
	ledger.remove_ads = true
	assert_bool(_may(ledger, true)).is_false()
	assert_str(String(_why(ledger, true))).is_equal("remove_ads")


func test_no_consent_blocks_without_remove_ads() -> void:
	var ledger: AdLedger = _ledger(9, 9999)
	ledger.remove_ads = false
	assert_bool(_may(ledger, false)).is_false()
	assert_str(String(_why(ledger, false))).is_equal("consent")


func test_other_placements_never_show() -> void:
	var ledger: AdLedger = _ledger(9, 9999)
	for placement: StringName in [&"pause", &"", &"battle"]:
		assert_bool(AdCaps.may_show_interstitial(_settings, ledger, placement, true)).is_false()
		assert_str(String(AdCaps.denial_reason(_settings, ledger, placement, true))).is_equal(
			"placement"
		)


func test_negative_play_seconds_do_not_subtract() -> void:
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(-50)
	assert_int(ledger.play_s_since_interstitial).is_equal(0)
