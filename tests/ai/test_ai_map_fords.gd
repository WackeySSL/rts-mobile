extends "res://tests/ai/support/map_suite.gd"
## The opponent AI on Heron Fords (plan row P555): the river has two fords of buildable sand, so a
## player can wall one off or both. The army must still get through: by the other ford, or by
## shooting the wall. Every case first plays the open map to learn which ford the army takes, then
## walls that one (a wall on the unused ford would change nothing), and tells a reroute (the walls
## all stand and the army used the other ford) from a shoot-through (walls are gone). The army
## starts beside player 1's base on the west bank.

const STEM: String = "res://data/scenarios/skirmish_heron_fords"
const SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
const START: Vector2i = Vector2i(12, 20)


func before_test() -> void:
	_crossings = [Vector3i(14, 5, 28), Vector3i(41, 5, 28)]
	_band = Vector2i(28, 31)


func _path(suffix: String) -> String:
	return "%s%s.tres" % [STEM, suffix]


func test_an_open_river_is_crossed_to_the_enemy_base_in_every_scenario() -> void:
	for suffix: String in SUFFIXES:
		_open_run(_path(suffix), START.x, START.y)


func test_a_walled_ford_is_left_by_the_other_one_and_no_wall_is_shot() -> void:
	for suffix: String in SUFFIXES:
		var first: int = _open_run(_path(suffix), START.x, START.y)
		_start(_path(suffix), START.x, START.y)
		_seal_crossing(first)
		var standing: int = _walls_alive()
		assert_int(standing).is_greater(0)
		assert_bool(_blocked(first)).override_failure_message(suffix).is_true()
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_walls_alive()).override_failure_message(suffix).is_equal(standing)
		assert_int(_used).override_failure_message(suffix).is_not_equal(first)
		assert_int(_used).override_failure_message(suffix).is_greater_equal(0)


func test_a_wall_on_the_ford_the_army_does_not_use_changes_nothing() -> void:
	for suffix: String in SUFFIXES:
		var first: int = _open_run(_path(suffix), START.x, START.y)
		_start(_path(suffix), START.x, START.y)
		_seal_crossing(1 - first)
		var standing: int = _walls_alive()
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_used).override_failure_message(suffix).is_equal(first)
		assert_int(_walls_alive()).override_failure_message(suffix).is_equal(standing)


func test_two_walled_fords_get_the_wall_shot_and_the_attack_through() -> void:
	for suffix: String in SUFFIXES:
		_start(_path(suffix), START.x, START.y)
		_seal_crossing(0)
		_seal_crossing(1)
		var standing: int = _walls_alive()
		for index: int in _crossings.size():
			assert_bool(_blocked(index)).override_failure_message(suffix).is_true()
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_walls_alive()).override_failure_message(suffix).is_less(standing)
