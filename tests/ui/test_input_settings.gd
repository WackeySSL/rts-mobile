extends GdUnitTestSuite
## InputSettings: the ADR 0004 section 2 table as literals, for the script defaults and for
## data/input_settings.tres, with the corner HUD's keys (ADR 0025, plan P119c: every key of HUD v2
## is here, so that no two rows edit this table). When the file is tuned after the phone test, this
## table changes too.

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
		"ghost_grab_dp": 24.0,
		"ghost_lift_dp": 64.0,
		"edge_band_dp": 32.0,
		"edge_pan_dp_per_s": 300.0,
		"edge_pan_max_step_ms": 100,
		"menu_slide_ms": 160,
		# The corner HUD (ADR 0025, plan HUD v2). The two attack_cue keys are placeholders (P123 tunes).
		"economy_flash_ms": 1000,
		"radar_close_ms": 4000,
		"scope_radius_tiles": 16,
		"attack_toast_ms": 4000,
		"attack_cue_ms": 4000,
		"attack_cue_area_tiles": 12,
		"drawer_swipe_dp": 48.0,
		"sell_arm_min_ms": 400,
		"sell_confirm_ms": 3000,
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


## The two-tap Sell's timing hangs together (ADR 0037 section 3): the gap from the first release to
## the second press is at least a double-tap's (`double_tap_ms`), so a double-tap never sells, and
## under the window; a contact of `long_press_ms` is a hold, so a tap (shorter than it) fits inside
## the window, which is longer than a hold.
func test_the_sell_timing_keeps_a_double_tap_from_selling_and_a_tap_inside_the_window() -> void:
	for settings: InputSettings in [InputSettings.new(), load("res://data/input_settings.tres")]:
		assert_int(settings.double_tap_ms).is_less_equal(settings.sell_arm_min_ms)
		assert_int(settings.sell_arm_min_ms).is_less(settings.sell_confirm_ms)
		assert_int(settings.long_press_ms).is_greater(0)
		assert_int(settings.long_press_ms).is_less(settings.sell_confirm_ms)


func _assert_table(settings: InputSettings) -> void:
	var table: Dictionary[String, Variant] = _table()
	for field: String in table:
		assert_that(settings.get(field)).override_failure_message(field).is_equal(table[field])
		# gdUnit equality also accepts an Array[float] for a PackedFloat32Array: pin the type.
		assert_int(typeof(settings.get(field))).is_equal(typeof(table[field]))
