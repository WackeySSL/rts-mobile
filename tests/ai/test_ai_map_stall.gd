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
		var path: String = "%s%s.tres" % [STEM, suffix]
		# The control: the same walled passes with the answer off. It sends no ATTACK at all (in some
		# scenarios the wave's own fire still brings a wall down, which is why the outcome alone is not
		# the difference).
		_start(path, START.x, START.y, "normal", true, 0)
		for index: int in _crossings.size():
			_seal_crossing(index)
		var standing: int = _walls_alive()
		_run_until(_reached_base)
		assert_int(_ai.army.stall_attacks()).override_failure_message(suffix).is_equal(0)
		assert_int(_first_attack).override_failure_message(suffix).is_equal(0)
		# The answer on.
		_start(path, START.x, START.y)
		for index: int in _crossings.size():
			_seal_crossing(index)
		for index: int in _crossings.size():
			assert_bool(_blocked(index)).override_failure_message(suffix).is_true()
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_walls_alive()).override_failure_message(suffix).is_less(standing)
		assert_int(_ai.army.stall_attacks()).override_failure_message(suffix).is_greater(0)
		# The first ATTACK is on a wall, one of the nearest to the army (not the farthest).
		assert_bool(_walls.has(_first_attack)).override_failure_message(suffix).is_true()
		assert_int(_attack_gap).override_failure_message(suffix).is_less_equal(
			_nearest_gap + 3 * World.MILLI_PER_TILE
		)
		# Once the wall is down the wave goes back to its target.
		assert_int(_ai.army.stall_retries()).override_failure_message(suffix).is_greater(0)
