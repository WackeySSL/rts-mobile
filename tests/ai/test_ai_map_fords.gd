extends "res://tests/ai/support/map_suite.gd"
## The opponent AI on Heron Fords (plan row P555): the river has two fords of buildable sand, so a
## player can wall one off or both. The army must still get through: by the other ford, or by
## shooting the wall. The army starts beside player 1's base on the west bank.

const STEM: String = "res://data/scenarios/skirmish_heron_fords"
const SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
## The fords: first column, width and the row of the first of their four rows.
const WEST: Vector3i = Vector3i(14, 5, 28)
const EAST: Vector3i = Vector3i(41, 5, 28)


func _begin(suffix: String) -> void:
	_start("%s%s.tres" % [STEM, suffix], 12, 20)


func test_an_open_river_is_crossed_to_the_enemy_base_in_every_scenario() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()


func test_a_walled_west_ford_is_left_by_the_east_one() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_seal(WEST.x, WEST.y, WEST.z)
		var standing: int = _walls_alive()
		assert_int(standing).is_greater(0)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()


func test_a_walled_east_ford_is_left_by_the_west_one() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_seal(EAST.x, EAST.y, EAST.z)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()


func test_two_walled_fords_get_the_wall_shot_and_the_attack_through() -> void:
	for suffix: String in SUFFIXES:
		_begin(suffix)
		_seal(WEST.x, WEST.y, WEST.z)
		_seal(EAST.x, EAST.y, EAST.z)
		var standing: int = _walls_alive()
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_walls_alive()).is_less(standing)
