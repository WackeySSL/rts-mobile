extends "res://tests/ai/support/map_suite.gd"
## The opponent AI on Curlew Crags (plan row P555): the ridge across the map has three passes of
## buildable sand (5, 6 and 5 tiles wide), so a wave must not jam in one of them or stop at a
## walled one. Every case first plays the open map to learn which pass the army takes, then walls
## that one (and the next), and tells a reroute (the walls all stand and the army used another
## pass) from a shoot-through (walls are gone). The army starts beside player 1's base.

const STEM: String = "res://data/scenarios/skirmish_curlew_crags"
const SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
const START: Vector2i = Vector2i(12, 19)
const CENTRE: int = 1


func before_test() -> void:
	_crossings = [Vector3i(8, 5, 26), Vector3i(25, 6, 26), Vector3i(43, 5, 26)]
	_band = Vector2i(26, 29)


func _path(suffix: String) -> String:
	return "%s%s.tres" % [STEM, suffix]


## Plays `path` with the crossings `sealed` walled and asserts a reroute: the base is reached, every
## wall stands, the sealed crossings block a tracked unit, and the army used a crossing not in
## `sealed`. Returns that crossing.
func _rerouted(path: String, sealed: Array[int]) -> int:
	_start(path, START.x, START.y)
	for index: int in sealed:
		_seal_crossing(index)
	var standing: int = _walls_alive()
	assert_int(standing).is_greater(0)
	for index: int in sealed:
		assert_bool(_blocked(index)).override_failure_message(path).is_true()
	_run_until(_reached_base)
	assert_bool(_reached_base()).override_failure_message(path).is_true()
	assert_int(_walls_alive()).override_failure_message(path).is_equal(standing)
	assert_int(_used).override_failure_message(path).is_greater_equal(0)
	assert_bool(sealed.has(_used)).override_failure_message(path).is_false()
	return _used


func test_open_passes_are_crossed_to_the_enemy_base_in_every_scenario() -> void:
	for suffix: String in SUFFIXES:
		_open_run(_path(suffix), START.x, START.y)


func test_a_walled_pass_is_left_by_another_and_no_wall_is_shot() -> void:
	for suffix: String in SUFFIXES:
		var first: int = _open_run(_path(suffix), START.x, START.y)
		_rerouted(_path(suffix), [first] as Array[int])


func test_two_walled_passes_are_left_by_the_third() -> void:
	for suffix: String in SUFFIXES:
		var first: int = _open_run(_path(suffix), START.x, START.y)
		var second: int = _rerouted(_path(suffix), [first] as Array[int])
		var third: int = _rerouted(_path(suffix), [first, second] as Array[int])
		assert_bool([first, second].has(third)).override_failure_message(suffix).is_false()


func test_the_six_wide_centre_pass_alone_carries_the_wave_to_the_enemy_base() -> void:
	for suffix: String in SUFFIXES:
		var used: int = _rerouted(_path(suffix), [0, 2] as Array[int])
		assert_int(used).override_failure_message(suffix).is_equal(CENTRE)
