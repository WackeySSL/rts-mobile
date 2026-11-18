extends GdUnitTestSuite
## P402: data/ads_settings.tres loads, pins every ADR 0039 section 4 value, and every value is in
## range. A change of a number here is a decision of Michael's.


func _file() -> AdsSettingsDef:
	return load("res://data/ads_settings.tres") as AdsSettingsDef


func test_the_file_loads_as_the_def() -> void:
	assert_object(_file()).is_not_null()
	assert_object(AdsSettingsDef.load_default()).is_same(_file())


func test_every_field_is_pinned() -> void:
	var s: AdsSettingsDef = _file()
	assert_int(s.interstitial_free_matches).is_equal(2)
	assert_int(s.interstitial_min_play_s).is_equal(240)
	assert_int(s.interstitial_per_match).is_equal(1)
	assert_int(s.fullscreen_timeout_ms).is_equal(8000)
	assert_int(s.billing_timeout_ms).is_equal(8000)
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
	assert_array(Array(_file().validate())).is_empty()


func test_out_of_range_values_are_reported() -> void:
	var bad: AdsSettingsDef = _file().duplicate() as AdsSettingsDef
	bad.interstitial_per_match = 0
	bad.banner_gap_dp = 15
	bad.start_credits_bonus_max = 499
	bad.remove_ads_product_id = " "
	bad.billing_timeout_ms = 999
	var messages: PackedStringArray = bad.validate()
	assert_int(messages.size()).is_equal(5)
	var joined: String = "\n".join(messages)
	for field: String in [
		"interstitial_per_match",
		"banner_gap_dp",
		"start_credits_bonus_max",
		"remove_ads_product_id",
		"billing_timeout_ms"
	]:
		assert_str(joined).override_failure_message("missing %s" % field).contains(field)


func test_the_arm_delay_is_pinned_and_checked() -> void:
	assert_int(_file().reward_arm_ms).is_equal(500)
	var bad: AdsSettingsDef = _file().duplicate() as AdsSettingsDef
	bad.reward_arm_ms = 0
	assert_str("\n".join(bad.validate())).contains("reward_arm_ms")


func test_the_reward_text_formats_with_exactly_one_multiplier() -> void:
	for text: String in ["Watch an ad", "%d and %d", "%d%%", "%s %d", "%d 100%"]:
		var bad: AdsSettingsDef = _file().duplicate() as AdsSettingsDef
		bad.reward_xp_text = text
		assert_str("\n".join(bad.validate())).override_failure_message(text).contains(
			"reward_xp_text"
		)
	assert_str(_file().reward_xp_text % 2).is_not_empty()


func test_the_xp_multiplier_is_one_that_apply_bonus_accepts() -> void:
	var progression: ProgressionDef = load("res://data/meta/progression.tres") as ProgressionDef
	assert_int(_file().reward_xp_multiplier).is_greater_equal(progression.min_bonus_multiplier)
