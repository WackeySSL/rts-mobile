extends "res://tests/ai/support/map_suite.gd"
## The stalled wave on Curlew Crags (plan row P555b): all three passes of the ridge are walled, so
## the target has no route and the sim leaves the wave's units idle where they stop. The AI sees
## that from the view alone (no progress over the window, the units idle), orders an attack on the
## nearest enemy building it sees, and goes back to the target once that building is gone, so the
## walls get shot and the wave reaches the enemy base. Both factions, in the base and the mirrored
## scenarios.

const STEM: String = "res://data/scenarios/skirmish_curlew_crags"
const SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
const START: Vector2i = Vector2i(24, 24)


func before_test() -> void:
	_crossings = [Vector3i(8, 5, 26), Vector3i(25, 6, 26), Vector3i(43, 5, 26)]
	_band = Vector2i(26, 29)


func test_a_wave_stalled_before_three_walled_passes_shoots_a_wall_and_reaches_the_base() -> void:
	for suffix: String in SUFFIXES:
		_start("%s%s.tres" % [STEM, suffix], START.x, START.y)
		for index: int in _crossings.size():
			_seal_crossing(index)
		var standing: int = _walls_alive()
		for index: int in _crossings.size():
			assert_bool(_blocked(index)).override_failure_message(suffix).is_true()
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_walls_alive()).override_failure_message(suffix).is_less(standing)
		assert_int(_ai.army.stall_attacks()).override_failure_message(suffix).is_greater(0)
