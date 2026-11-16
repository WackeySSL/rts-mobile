extends GdUnitTestSuite
## P405: AdIds. Google's test units, the cfg reader and its fallbacks (ADR 0039 section 9). The
## fake IDs here are built at run time, so no ID literal enters the repository.

const PATH: String = "user://test_ad_ids.cfg"
const TEST_PUBLISHER: String = "ca-app-pub-3940256099942544/"


func after_test() -> void:
	DirAccess.remove_absolute(PATH)


func _fake(digit: String) -> String:
	return "ca-app-pub-%s/%s" % [digit.repeat(16), digit.repeat(10)]


func _write(values: Dictionary) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	for key: String in values:
		cfg.set_value("units", key, values[key])
	assert_int(cfg.save(PATH)).is_equal(OK)


func test_the_constants_are_googles_test_units() -> void:
	for unit: String in [AdIds.TEST_BANNER, AdIds.TEST_INTERSTITIAL, AdIds.TEST_REWARDED]:
		assert_bool(unit.begins_with(TEST_PUBLISHER)).is_true()
	var ids: AdIds = AdIds.new()
	assert_str(ids.unit(AdIds.KIND_BANNER)).is_equal(AdIds.TEST_BANNER)
	assert_str(ids.unit(AdBackend.KIND_INTERSTITIAL)).is_equal(AdIds.TEST_INTERSTITIAL)
	assert_str(ids.unit(AdBackend.KIND_REWARDED)).is_equal(AdIds.TEST_REWARDED)
	assert_str(ids.unit(&"other")).is_empty()


func test_a_debug_build_uses_test_units_even_with_a_file() -> void:
	_write({"banner": _fake("1"), "interstitial": _fake("2"), "rewarded": _fake("3")})
	var ids: AdIds = AdIds.load_units(true, PATH)
	assert_str(ids.banner).is_equal(AdIds.TEST_BANNER)
	assert_str(ids.interstitial).is_equal(AdIds.TEST_INTERSTITIAL)
	assert_str(ids.rewarded).is_equal(AdIds.TEST_REWARDED)
	assert_bool(ids.uses_test_units).is_true()


func test_a_release_build_reads_the_file() -> void:
	_write({"banner": _fake("1"), "interstitial": _fake("2"), "rewarded": _fake("3")})
	var ids: AdIds = AdIds.load_units(false, PATH)
	assert_str(ids.banner).is_equal(_fake("1"))
	assert_str(ids.interstitial).is_equal(_fake("2"))
	assert_str(ids.rewarded).is_equal(_fake("3"))
	assert_bool(ids.uses_test_units).is_false()


func test_a_missing_file_falls_back_to_test_units() -> void:
	var ids: AdIds = AdIds.load_units(false, "user://no_such_ad_ids.cfg")
	assert_str(ids.banner).is_equal(AdIds.TEST_BANNER)
	assert_bool(ids.uses_test_units).is_true()


func test_a_missing_or_malformed_key_falls_back_for_that_key_only() -> void:
	_write({"banner": _fake("1"), "interstitial": "not an id", "rewarded": ""})
	var ids: AdIds = AdIds.load_units(false, PATH)
	assert_str(ids.banner).is_equal(_fake("1"))
	assert_str(ids.interstitial).is_equal(AdIds.TEST_INTERSTITIAL)
	assert_str(ids.rewarded).is_equal(AdIds.TEST_REWARDED)
	assert_bool(ids.uses_test_units).is_false()
