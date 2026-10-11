extends GdUnitTestSuite
## InputSettings: the ADR 0004 section 2 table as literals, for the script defaults and for
## data/input_settings.tres. When the file is tuned after the phone test, this table changes too.

const SETTINGS_PATH: String = "res://data/input_settings.tres"


func _table() -> Dictionary[String, Variant]:
	return {
		"tap_slop_dp": 12.0,
		"long_press_ms": 300,
		"double_tap_ms": 300,
		"double_tap_slop_dp": 32.0,
		"hit_radius_dp": 24.0,
		"group_assign_ms": 500,
		"zoom_levels": PackedFloat32Array([0.75, 1.0, 1.5]),
		"zoom_start_index": 1,
		"pinch_overshoot": 0.15,
		"zoom_snap_ms": 150,
		"marker_ms": 600,
		"haptic_ms": 15,
		"haptics_enabled": true,
	}


func test_script_defaults_are_the_adr_table() -> void:
	_assert_table(InputSettings.new())


func test_data_file_holds_the_adr_table() -> void:
	var loaded: InputSettings = load(SETTINGS_PATH) as InputSettings
	assert_object(loaded).is_not_null()
	_assert_table(loaded)


func test_zoom_levels_are_strictly_ascending_with_1_0_among_them_and_the_start_is_one() -> void:
	var settings: InputSettings = load(SETTINGS_PATH)
	var levels: PackedFloat32Array = settings.zoom_levels
	for i: int in range(1, levels.size()):
		assert_float(levels[i]).is_greater(levels[i - 1])
	assert_int(levels.find(1.0)).is_greater_equal(0)
	assert_float(levels[settings.zoom_start_index]).is_equal(1.0)


func _assert_table(settings: InputSettings) -> void:
	var table: Dictionary[String, Variant] = _table()
	for field: String in table:
		assert_that(settings.get(field)).override_failure_message(field).is_equal(table[field])
