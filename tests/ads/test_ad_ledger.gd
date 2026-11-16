extends GdUnitTestSuite
## P402: AdLedger counters, the start bonus taken once, and the `ads` save section round trip.


func test_round_trip_keeps_every_field() -> void:
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(120)
	ledger.note_match_completed(90)
	ledger.note_interstitial_shown()
	ledger.note_match_completed(33)
	ledger.remove_ads = true
	assert_bool(ledger.grant_start_credits_bonus(500, 500)).is_true()
	var back: AdLedger = AdLedger.from_dict(ledger.to_dict())
	assert_dict(back.to_dict()).is_equal(ledger.to_dict())
	assert_int(back.completed_matches).is_equal(3)
	assert_int(back.play_s_since_interstitial).is_equal(33)
	assert_int(back.last_interstitial_match).is_equal(2)
	assert_bool(back.remove_ads).is_true()
	assert_int(back.pending_start_credits).is_equal(500)


func test_to_dict_has_exactly_the_ads_section_keys() -> void:
	(
		assert_array(AdLedger.new().to_dict().keys())
		. contains_exactly_in_any_order(
			[
				"completed_matches",
				"last_interstitial_match",
				"pending_start_credits",
				"play_s_since_interstitial",
				"remove_ads",
			]
		)
	)


func test_a_missing_section_gives_the_defaults() -> void:
	for missing: Variant in [null, {}, "x", 5]:
		var ledger: AdLedger = AdLedger.from_dict(missing)
		var msg: String = "input=%s" % str(missing)
		assert_int(ledger.completed_matches).override_failure_message(msg).is_equal(0)
		assert_int(ledger.play_s_since_interstitial).override_failure_message(msg).is_equal(0)
		assert_int(ledger.last_interstitial_match).override_failure_message(msg).is_equal(0)
		assert_bool(ledger.remove_ads).override_failure_message(msg).is_false()
		assert_int(ledger.pending_start_credits).override_failure_message(msg).is_equal(0)


func test_bad_values_fall_back_and_clamp() -> void:
	var ledger: AdLedger = (
		AdLedger
		. from_dict(
			{
				"completed_matches": 2,
				"play_s_since_interstitial": -5,
				"last_interstitial_match": 9,
				"remove_ads": "yes",
				"pending_start_credits": "lots",
			}
		)
	)
	assert_int(ledger.completed_matches).is_equal(2)
	assert_int(ledger.play_s_since_interstitial).is_equal(0)
	assert_int(ledger.last_interstitial_match).is_equal(2)
	assert_bool(ledger.remove_ads).is_false()
	assert_int(ledger.pending_start_credits).is_equal(0)


func test_the_start_bonus_is_taken_once() -> void:
	var ledger: AdLedger = AdLedger.new()
	assert_int(ledger.take_start_credits_bonus(500)).is_equal(0)
	assert_bool(ledger.grant_start_credits_bonus(500, 500)).is_true()
	assert_int(ledger.take_start_credits_bonus(500)).is_equal(500)
	assert_int(ledger.take_start_credits_bonus(500)).is_equal(0)
	assert_int(ledger.pending_start_credits).is_equal(0)


func test_a_second_grant_does_not_stack() -> void:
	var ledger: AdLedger = AdLedger.new()
	assert_bool(ledger.grant_start_credits_bonus(300, 500)).is_true()
	assert_bool(ledger.grant_start_credits_bonus(300, 500)).is_false()
	assert_int(ledger.pending_start_credits).is_equal(300)


func test_a_grant_is_capped() -> void:
	var ledger: AdLedger = AdLedger.new()
	assert_bool(ledger.grant_start_credits_bonus(900, 500)).is_true()
	assert_int(ledger.pending_start_credits).is_equal(500)


func test_the_bonus_is_capped_on_take_too() -> void:
	var ledger: AdLedger = AdLedger.from_dict({"pending_start_credits": 999999})
	assert_int(ledger.take_start_credits_bonus(500)).is_equal(500)
	assert_int(ledger.pending_start_credits).is_equal(0)


func test_whole_floats_load_as_ints() -> void:
	var ledger: AdLedger = AdLedger.from_dict(
		{"completed_matches": 3.0, "play_s_since_interstitial": 240.0}
	)
	assert_int(ledger.completed_matches).is_equal(3)
	assert_int(ledger.play_s_since_interstitial).is_equal(240)
	var settings: AdsSettingsDef = AdsSettingsDef.load_default()
	(
		assert_bool(
			AdCaps.may_show_interstitial(settings, ledger, AdCaps.PLACEMENT_POST_MATCH, true)
		)
		. is_true()
	)


func test_huge_and_non_finite_numbers_load_as_zero() -> void:
	for bad: float in [1e30, INF, NAN]:
		var ledger: AdLedger = AdLedger.from_dict(
			{"completed_matches": bad, "play_s_since_interstitial": bad}
		)
		assert_int(ledger.completed_matches).override_failure_message("bad=%s" % bad).is_equal(0)
		(
			assert_int(ledger.play_s_since_interstitial)
			. override_failure_message("bad=%s" % bad)
			. is_equal(0)
		)
	var big_int: AdLedger = AdLedger.from_dict({"completed_matches": AdLedger.LIMIT + 1})
	assert_int(big_int.completed_matches).is_equal(0)


func test_play_seconds_saturate() -> void:
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(9223372036854775807)
	ledger.note_match_completed(9223372036854775807)
	assert_int(ledger.play_s_since_interstitial).is_equal(AdLedger.LIMIT)
	assert_int(ledger.completed_matches).is_equal(2)


func test_a_saved_shown_match_survives_the_round_trip() -> void:
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(300)
	ledger.note_interstitial_shown()
	var back: AdLedger = AdLedger.from_dict(ledger.to_dict())
	assert_int(back.last_interstitial_match).is_equal(back.completed_matches)
	assert_bool(back.shown_for_current_match()).is_true()
