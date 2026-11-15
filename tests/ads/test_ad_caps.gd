extends GdUnitTestSuite
## P402: AdCaps boundaries (ADR 0039 section 4) against the shipped settings.

const POST: StringName = &"post_match"

var _settings: AdsSettingsDef


func before_test() -> void:
	_settings = AdsSettingsDef.load_default()


func _ledger(matches: int, play_s: int) -> AdLedger:
	var ledger: AdLedger = AdLedger.new()
	ledger.completed_matches = matches
	ledger.play_s_since_interstitial = play_s
	return ledger


func _may(ledger: AdLedger, consent: bool = true) -> bool:
	return AdCaps.may_show_interstitial(_settings, ledger, POST, consent)


func test_none_in_the_first_two_matches_even_with_long_play() -> void:
	assert_bool(_may(_ledger(0, 9999))).is_false()
	assert_bool(_may(_ledger(1, 9999))).is_false()
	assert_bool(_may(_ledger(2, 9999))).is_false()
	var why: StringName = AdCaps.denial(_settings, _ledger(2, 9999), POST, true)
	assert_str(String(why)).is_equal("free_matches")


func test_the_third_match_shows_from_exactly_240_seconds() -> void:
	assert_bool(_may(_ledger(3, 239))).is_false()
	assert_bool(_may(_ledger(3, 240))).is_true()
	assert_bool(_may(_ledger(3, 241))).is_true()


func test_one_per_completed_match() -> void:
	var ledger: AdLedger = _ledger(3, 300)
	assert_bool(_may(ledger)).is_true()
	ledger.note_interstitial_shown()
	ledger.play_s_since_interstitial = 9999
	assert_bool(_may(ledger)).is_false()
	assert_str(String(AdCaps.denial(_settings, ledger, POST, true))).is_equal("per_match")
	ledger.note_match_completed(300)
	assert_bool(_may(ledger)).is_true()


func test_a_shown_interstitial_resets_the_play_counter() -> void:
	var ledger: AdLedger = _ledger(3, 300)
	ledger.note_interstitial_shown()
	assert_int(ledger.play_s_since_interstitial).is_equal(0)
	assert_int(ledger.last_interstitial_match).is_equal(3)
	ledger.note_match_completed(239)
	assert_bool(_may(ledger)).is_false()
	ledger.note_match_completed(1)
	assert_bool(_may(ledger)).is_true()


func test_play_seconds_add_up_across_matches() -> void:
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(100)
	ledger.note_match_completed(100)
	ledger.note_match_completed(39)
	assert_int(ledger.play_s_since_interstitial).is_equal(239)
	assert_bool(_may(ledger)).is_false()
	ledger.note_match_completed(1)
	assert_bool(_may(ledger)).is_true()


func test_remove_ads_no_consent_and_other_placements_never_show() -> void:
	var ledger: AdLedger = _ledger(9, 9999)
	assert_bool(_may(ledger, false)).is_false()
	assert_bool(AdCaps.may_show_interstitial(_settings, ledger, &"pause", true)).is_false()
	assert_bool(AdCaps.may_show_interstitial(_settings, ledger, &"", true)).is_false()
	ledger.set_remove_ads(true)
	assert_bool(_may(ledger)).is_false()


func test_negative_play_seconds_do_not_subtract() -> void:
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(-50)
	assert_int(ledger.play_s_since_interstitial).is_equal(0)
