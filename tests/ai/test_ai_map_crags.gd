extends "res://tests/ai/support/map_suite.gd"
## The opponent AI on Curlew Crags (plan row P555): the ridge across the map has three passes of
## buildable sand (5, 6 and 5 tiles wide), so a wave must not jam in one of them or stop at a
## walled one. The army starts beside player 1's base.

const STEM: String = "res://data/scenarios/skirmish_curlew_crags"
const SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
## The passes: first column, width and the row of the first of their four rows.
const WEST: Vector3i = Vector3i(8, 5, 26)
const CENTRE: Vector3i = Vector3i(25, 6, 26)
const EAST: Vector3i = Vector3i(43, 5, 26)


func _begin(suffix: String, army_x: int = 12, army_y: int = 19) -> void:
	_start("%s%s.tres" % [STEM, suffix], army_x, army_y)


func test_open_passes_are_crossed_to_the_enemy_base_in_every_scenario() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()


func test_a_walled_centre_pass_is_left_by_a_flank_pass() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_seal(CENTRE.x, CENTRE.y, CENTRE.z)
		assert_int(_walls_alive()).is_greater(0)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()


func test_two_walled_passes_are_left_by_the_third() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_seal(WEST.x, WEST.y, WEST.z)
		_seal(CENTRE.x, CENTRE.y, CENTRE.z)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()


func test_the_six_wide_centre_pass_alone_carries_the_wave_to_the_enemy_base() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_seal(WEST.x, WEST.y, WEST.z)
		_seal(EAST.x, EAST.y, EAST.z)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
