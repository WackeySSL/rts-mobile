extends GdUnitTestSuite
## The collapse sequence numbers of `data/life_settings.tres` (plan P165, ADR 0029 section 13):
## their values, the order of the times, and the crater's scale of the refineries.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const PATH: String = "res://data/life_settings.tres"


func _file() -> LifeSettings:
	return load(PATH) as LifeSettings


func test_the_data_file_holds_the_documented_values() -> void:
	var file: LifeSettings = _file()
	assert_int(file.collapse_max).is_equal(16)
	assert_array(file.collapse_sink_ms).is_equal([250, 700])
	assert_int(file.collapse_sink_steps).is_equal(6)
	assert_int(file.collapse_sink_percent).is_equal(60)
	assert_int(file.collapse_hide_ms).is_equal(700)
	assert_int(file.collapse_end_ms).is_equal(900)
	var defaults: LifeSettings = LifeSettings.new()  # The script says the same.
	for field: String in ["collapse_max", "collapse_hide_ms", "collapse_end_ms"]:
		assert_that(defaults.get(field)).is_equal(file.get(field))
	assert_array(defaults.collapse_sink_ms).is_equal(file.collapse_sink_ms)
	assert_dict(defaults.crater_scale_milli).is_equal(file.crater_scale_milli)


func test_the_times_are_in_order() -> void:
	var file: LifeSettings = _file()
	assert_int(file.collapse_sink_ms[0]).is_less_equal(file.collapse_sink_ms[1])
	assert_int(file.collapse_sink_ms[1]).is_equal(file.collapse_hide_ms)  # Sink end = hide.
	assert_int(file.collapse_hide_ms).is_less(file.collapse_end_ms)  # Hide < collapse end.
	assert_int(file.collapse_sink_percent).is_between(1, 100)
	assert_int(file.collapse_sink_steps).is_greater(0)


func test_every_refinery_leaves_a_crater_one_and_a_half_times_the_default() -> void:
	var file: LifeSettings = _file()
	assert_int(file.crater_scale_milli.get(&"refinery", 1000)).is_equal(1500)
	for path: String in FileScan.list_files("res://data/units", ".tres"):
		var unit: UnitDef = load(path) as UnitDef
		var scale: int = file.crater_scale_milli.get(unit.type_id, 1000)
		var refinery: bool = String(unit.type_id).ends_with("refinery")
		assert_int(scale).override_failure_message(String(unit.type_id)).is_equal(
			1500 if refinery else 1000
		)
