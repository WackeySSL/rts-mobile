extends GdUnitTestSuite
## P402: AdLedger counters, the start bonus taken once, and the `ads` save section round trip.


func test_round_trip_keeps_every_field() -> void:
	var ledger: AdLedger = AdLedger.new()
	ledger.note_match_completed(120)
	ledger.note_match_completed(90)
	ledger.note_interstitial_shown()
	ledger.note_match_completed(33)
	ledger.set_remove_ads(true)
	ledger.grant_start_credits_bonus(500, 500)
	var back: AdLedger = AdLedger.from_dict(ledger.to_dict())
	assert_dict(back.to_dict()).is_equal(ledger.to_dict())
	assert_int(back.completed_matches).is_equal(3)
	assert_int(back.play_s_since_interstitial).is_equal(33)
	assert_int(back.last_interstitial_match).is_equal(2)
	assert_bool(back.remove_ads).is_true()
	assert_int(back.pending_start_credits).is_equal(500)


func test_to_dict_has_exactly_the_ads_section_keys() -> void:
	var keys: Array = AdLedger.new().to_dict().keys()
	keys.sort()
	(
		assert_array(keys)
		. is_equal(
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
		assert_int(ledger.completed_matches).is_equal(0)
		assert_int(ledger.play_s_since_interstitial).is_equal(0)
		assert_int(ledger.last_interstitial_match).is_equal(0)
		assert_bool(ledger.remove_ads).is_false()
		assert_int(ledger.pending_start_credits).is_equal(0)


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
	assert_int(ledger.take_start_credits_bonus()).is_equal(0)
	ledger.grant_start_credits_bonus(500, 500)
	assert_int(ledger.take_start_credits_bonus()).is_equal(500)
	assert_int(ledger.take_start_credits_bonus()).is_equal(0)
	assert_int(ledger.pending_start_credits).is_equal(0)


func test_the_bonus_does_not_stack_past_the_cap() -> void:
	var s: AdsSettingsDef = AdsSettingsDef.load_default()
	var ledger: AdLedger = AdLedger.new()
	ledger.grant_start_credits_bonus(s.reward_start_credits, s.start_credits_bonus_max)
	ledger.grant_start_credits_bonus(s.reward_start_credits, s.start_credits_bonus_max)
	assert_int(ledger.take_start_credits_bonus()).is_equal(s.start_credits_bonus_max)


func test_the_facade_stub_is_unchanged_by_the_ledger() -> void:
	assert_int(AdService.take_start_credits_bonus()).is_equal(0)
