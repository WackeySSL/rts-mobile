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


## The REAL case (P555c): the wave leaves the base into the dark, stalls at the first ridge it meets
## with no enemy building in view, and sends scouts to unexplored ground on the target's side until
## the walls come into view; then the stall answer shoots a wall and the base falls or is reached.
func test_a_blind_wave_from_the_base_scouts_finds_the_walls_and_reaches_the_base() -> void:
	for suffix: String in SUFFIXES:
		_start("%s%s.tres" % [STEM, suffix], 12, 19, "normal", false)
		for index: int in _crossings.size():
			_seal_crossing(index)
		var standing: int = _walls_alive()
		_run_until(_reached_base)
		assert_bool(_reached_base()).override_failure_message(suffix).is_true()
		assert_int(_walls_alive()).override_failure_message(suffix).is_less(standing)
		assert_int(_ai.army.stall_scouts()).override_failure_message(suffix).is_greater(0)


## The scout cell is picked from the view alone: the nearest cell the player has not explored on
## the target's side. Explored cells and unexplored ones behind the wave are never picked, and the
## pick follows what the view says is explored.
func test_the_scout_cell_is_the_nearest_unexplored_cell_the_view_shows_on_the_targets_side(
) -> void:
	_start("%s.tres" % STEM, 12, 19, "normal", false)
	var cols: int = _world.map_cols
	var stall: AiStall = AiStall.create(Opp.def_of("fossil"))
	var at: Vector2i = Vector2i(20500, 20500)
	var aim: Vector2i = Vector2i(40500, 40500)
	var first: int = stall.scout_cell(PlayerView.of(_world, 1), at, aim)
	_assert_nearest_unexplored(first, cols, at)
	# What the player explores changes the pick: everything within 8 tiles of it is explored now.
	for cell: int in cols * _world.map_rows:
		var dx: int = cell % cols - first % cols
		var dy: int = cell / cols - first / cols
		if dx * dx + dy * dy <= 64:
			_world.fog.explored[cell] = 1
	var second: int = stall.scout_cell(PlayerView.of(_world, 1), at, aim)
	assert_int(second).is_not_equal(first)
	_assert_nearest_unexplored(second, cols, at)


## `picked` is unexplored in the view, on the side of the target (the dot product with the way
## (20, 20) is above 0) and no unexplored cell on that side is nearer.
func _assert_nearest_unexplored(picked: int, cols: int, at: Vector2i) -> void:
	var view: PlayerView = PlayerView.of(_world, 1)
	assert_bool(picked >= 0).is_true()
	assert_bool(view.is_explored(picked)).is_false()
	var gap: Vector2i = Vector2i(picked % cols * 1000 + 500, picked / cols * 1000 + 500) - at
	assert_int(gap.x + gap.y).is_greater(0)
	for cell: int in cols * _world.map_rows:
		if view.is_explored(cell):
			continue
		var other: Vector2i = Vector2i(cell % cols * 1000 + 500, cell / cols * 1000 + 500) - at
		if other.x + other.y > 0:
			assert_bool(other.length_squared() < gap.length_squared()).is_false()


func test_the_stall_answer_names_no_map_or_world() -> void:
	var text: String = FileAccess.get_file_as_string("res://game/ai/AiStall.gd")
	for word: String in ["MapDef", "World", "terrain", ".rows", "move_cost", "fog."]:
		assert_bool(text.contains(word)).override_failure_message(word).is_false()
