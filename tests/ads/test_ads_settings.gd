extends GdUnitTestSuite
## P402: data/ads_settings.tres loads, pins every ADR 0039 section 4 value, and every value is in
## range. A change of a number here is a decision of Michael's.


func _file() -> AdsSettingsDef:
	return load("res://data/ads_settings.tres") as AdsSettingsDef


func test_the_file_loads_as_the_def() -> void:
	assert_object(_file()).is_not_null()
	assert_bool(AdsSettingsDef.load_default() == _file()).is_true()


func test_every_field_is_pinned() -> void:
	var s: AdsSettingsDef = _file()
	assert_int(s.interstitial_free_matches).is_equal(2)
	assert_int(s.interstitial_min_play_s).is_equal(240)
	assert_int(s.interstitial_per_match).is_equal(1)
	assert_int(s.fullscreen_timeout_ms).is_equal(8000)
	assert_int(s.consent_timeout_ms).is_equal(10000)
	assert_int(s.reward_xp_multiplier).is_equal(2)
	assert_int(s.reward_start_credits).is_equal(500)
	assert_int(s.start_credits_bonus_max).is_equal(500)
	assert_int(s.rewarded_offers_per_screen).is_equal(1)
	assert_int(s.banner_gap_dp).is_equal(16)
	assert_int(s.start_banner_gap_dp).is_equal(48)
	assert_int(s.banner_reload_min_ms).is_equal(30000)
	assert_str(s.remove_ads_product_id).is_equal("remove_ads")


func test_the_file_is_in_range() -> void:
	assert_array(Array(_file().problems())).is_empty()


func test_out_of_range_values_are_reported() -> void:
	var bad: AdsSettingsDef = _file().duplicate() as AdsSettingsDef
	bad.interstitial_per_match = 0
	bad.banner_gap_dp = 15
	bad.start_credits_bonus_max = 499
	bad.remove_ads_product_id = " "
	assert_int(bad.problems().size()).is_equal(4)
