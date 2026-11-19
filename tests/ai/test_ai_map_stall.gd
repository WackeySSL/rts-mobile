extends "res://tests/ai/support/map_suite.gd"
## The stalled wave on Curlew Crags (plan row P555b): all three passes of the ridge are walled, so
## the target has no route and the sim leaves the wave's units idle where they stop. The AI sees
## that from the view alone (no progress over the window, the units idle), orders an attack on the
## nearest enemy building it sees, and goes back to the target once that building is gone, so the
## walls get shot and the wave reaches the enemy base. Both factions, in the base and the mirrored
## scenarios.

const STEM: String = "res://data/scenarios/skirmish_curlew_crags"
const SUFFIXES: Array[String] = ["", "_mirrored", "_fossil_mirror", "_renew_mirror"]
const WEST: Vector3i = Vector3i(8, 5, 26)
const CENTRE: Vector3i = Vector3i(25, 6, 26)
const EAST: Vector3i = Vector3i(43, 5, 26)


func _walled(suffix: String, army_x: int, army_y: int) -> int:
	_start("%s%s.tres" % [STEM, suffix], army_x, army_y)
	_seal(WEST.x, WEST.y, WEST.z)
	_seal(CENTRE.x, CENTRE.y, CENTRE.z)
	_seal(EAST.x, EAST.y, EAST.z)
	return _walls_alive()


func test_a_wave_stalled_before_three_walled_passes_shoots_a_wall_and_reaches_the_base() -> void:
	for suffix: String in SUFFIXES:
		var standing: int = _walled(suffix, 24, 24)
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_walls_alive()).override_failure_message(suffix).is_less(standing)
		assert_int(_ai.army.stall_attacks()).override_failure_message(suffix).is_greater(0)
