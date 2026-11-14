extends "res://tests/sim/support/mine_suite.gd"
## The second half of plan row P288's tests (ADR 0037 section 16): the cost bound of the remember
## pass, the range edge, a record that outlives its detector, the in-sight drop of a mine that
## leaves, the exact sweep tick and what a sweep never removes, and the snapshot's one reader.
## The rig is `support/mine_suite.gd`.

const SCAN_DIRS: Array[String] = ["res://game/view", "res://game/ui", "res://game/input"]
const MINE_NAMES: Array[String] = ["mine_owner", "mine_cell", "mine_armed_tick", "mine_id"]


func test_the_remember_pass_counts_detectors_times_candidates_whatever_the_row_count() -> void:
	var world: World = _seeing_world(4)
	for column: int in 12:
		_add(world, 1, SQUAD, column, 1)  # Rows that do not detect.
	_add(world, 1, TANK, 0, 0)
	for col: int in [10, 12, 14]:
		_put(world, 2, col, 9)  # Visible, far from the detector.
	_turn(world, 1)
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_equal(3)  # 1 detector x 3 mines.
	_add(world, 1, TANK, 1, 0)
	_turn(world, 1)
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_equal(6)
	var plain: World = _seeing_world(4)
	for column: int in 12:
		_add(plain, 1, SQUAD, column, 1)
	_put(plain, 2, 10, 9)
	_turn(plain, 1)
	assert_int(plain.stats[World.Stat.MINE_CHECKS]).is_equal(0)  # No detector: no pass, no count.


func test_a_run_with_detectors_stays_within_rows_plus_detectors_times_mines() -> void:
	var world: World = _seeing_world(4)
	_add(world, 1, TANK, 5, 5)
	_add(world, 1, AWARE, 3, 3)
	_add(world, 2, SQUAD, 14, 10)
	_put(world, 2, 7, 5)
	_put(world, 2, 13, 10)
	for _tick: int in 12:
		_step(world)
		var bound: int = _eligible(world) + 2 * world.mine_count
		assert_int(world.stats[World.Stat.MINE_CHECKS]).is_less_equal(bound)
	assert_int(world.mine_seen_count[1]).is_equal(1)


func test_the_reach_is_inclusive_and_measured_from_the_cell_centre() -> void:
	var world: World = _seeing_world()
	var tank: int = _add(world, 1, TANK, 5, 5)
	_put(world, 2, 7, 5)  # Centre 7,500: exactly 2,000 from (5,500).
	world.pos_x[tank] = 5500
	_turn(world, 1)
	assert_int(world.mine_seen_count[1]).is_equal(1)
	world.mine_seen_count[1] = 0
	world.pos_x[tank] = 5499  # 2,001 from the centre (1,501 from the cell's corner).
	_turn(world, 1)
	assert_int(world.mine_seen_count[1]).is_equal(0)


func test_a_record_outlives_its_detector_while_its_mine_is_there() -> void:
	var world: World = _seeing_world()
	var tank: int = _add(world, 1, TANK, 5, 5)
	_put(world, 2, 6, 5)
	_turn(world, 1)
	assert_int(world.mine_seen_count[1]).is_equal(1)
	world.hp[tank] = 0
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([1])  # Seen, still there, no detector: kept.
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_equal(0)


func test_a_blast_makes_no_record_and_one_in_sight_drops_the_record_at_once() -> void:
	var world: World = _seeing_world()
	world.type_detect_milli[TANK] = 0
	_put(world, 2, 6, 5)
	_record(world, 1, 1, 2, 5 * COLS + 6)
	_add(world, 1, TANK, 6, 5)  # Steps on the mine of player 2.
	_step(world)
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.mine_seen_count[1]).is_equal(0)  # Dropped in the blast tick, not a turn later.
	var dark: World = _seeing_world()
	dark.type_detect_milli[TANK] = 0
	_put(dark, 2, 6, 5)
	_record(dark, 1, 1, 2, 5 * COLS + 6)
	dark.fog.visible[6 + 5 * COLS] = 0  # Player 1 does not see the cell.
	Mines.clear_radius(dark, 6500, 5500, 100)  # A rupture: no step, so the fog stays as set.
	assert_int(dark.mine_count).is_equal(0)
	assert_int(dark.mine_seen_count[1]).is_equal(1)  # Kept until the spot is seen again.


func test_a_building_over_a_known_mine_drops_the_record_where_it_is_seen() -> void:
	var world: World = _seeing_world()
	_put(world, 2, 6, 5)
	_record(world, 1, 1, 2, 5 * COLS + 6)
	Mines.clear_footprint(world, 5, 4, 2, 2)
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.mine_seen_count[1]).is_equal(0)


func test_a_sweep_ends_on_the_exact_tick_and_forgets_the_swept_mine() -> void:
	var world: World = _seeing_world()
	world.type_detect_milli[AWARE] = 0
	var row: int = _add(world, 1, AWARE, 6, 5)
	_put(world, 2, 6, 5)
	_put(world, 2, 9, 5)
	_record(world, 1, 1, 2, 5 * COLS + 6)
	_step(world)
	var due: int = world.ready_tick[row]
	assert_int(due).is_equal(world.tick + world.sweep_ticks)  # The stamp of the step is tick + 1.
	while world.tick + 1 < due - 1:
		_step(world)
	_step(world)  # Its stamp is due - 1.
	assert_int(world.mine_count).is_equal(2)
	_step(world)  # Its stamp is due.
	assert_int(world.mine_count).is_equal(1)
	assert_array(Array(_rebuilt(world))).is_equal(Array(world.mine_at))
	assert_int(world.mine_at[5 * COLS + 9]).is_equal(1)  # The moved entry's cell was rewritten.
	assert_int(world.mine_seen_count[1]).is_equal(0)
	assert_array(_blasts(world)).is_empty()


func test_a_pushed_sweeper_sweeps_no_mine_it_has_no_record_of() -> void:
	var world: World = _seeing_world()
	world.type_detect_milli[AWARE] = 0
	var row: int = _add(world, 1, AWARE, 6, 5)
	_put(world, 2, 6, 5)
	_put(world, 2, 7, 5)  # Never recorded.
	_record(world, 1, 1, 2, 5 * COLS + 6)
	_step(world)
	assert_int(world.carry_mode[row]).is_equal(Mines.SWEEPING)
	world.pos_x[row] = 7500  # A push by SEPARATION, order still IDLE.
	_steps(world, world.sweep_ticks + 2)
	assert_int(world.mine_count).is_equal(2)
	assert_int(world.carry_mode[row]).is_equal(0)


func test_a_mine_laid_on_the_cell_during_a_sweep_is_not_swept() -> void:
	var world: World = _seeing_world()
	world.type_detect_milli[AWARE] = 0
	var row: int = _add(world, 1, AWARE, 6, 5)
	_put(world, 2, 6, 5)
	_record(world, 1, 1, 2, 5 * COLS + 6)
	_step(world)
	assert_int(world.carry_mode[row]).is_equal(Mines.SWEEPING)
	Mines.clear_radius(world, 6500, 5500, 100)  # The known mine goes (and its record).
	_put(world, 2, 6, 5)  # Another one on the same cell.
	_steps(world, world.sweep_ticks + 2)
	assert_int(world.mine_count).is_equal(1)


func test_stop_during_a_sweep_does_not_end_the_mine_early() -> void:
	var world: World = _seeing_world()
	world.type_detect_milli[AWARE] = 0
	var row: int = _add(world, 1, AWARE, 6, 5)
	_put(world, 2, 6, 5)
	_record(world, 1, 1, 2, 5 * COLS + 6)
	_step(world)
	var due: int = world.ready_tick[row]
	_step(world, [Command.stop(1, PackedInt32Array([world.unit_id[row]]))])
	while world.tick + 1 < due:
		_step(world)
	assert_int(world.mine_count).is_equal(1)  # The idle row started over (ADR note).
	_steps(world, world.sweep_ticks + 2)
	assert_int(world.mine_count).is_equal(0)


func test_mines_for_gives_a_player_only_its_own_and_its_found_mines() -> void:
	var world: World = _seeing_world()
	_put(world, 1, 4, 4)
	_put(world, 2, 6, 5)
	_put(world, 2, 12, 9)  # Not found.
	_record(world, 1, 2, 2, 5 * COLS + 6)
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.capture(world, null)
	var mine: Dictionary = snap.mines_for(1)
	assert_array(Array(mine[&"own_cell"])).is_equal([4 * COLS + 4])
	assert_array(Array(mine[&"own_armed"])).is_equal([1])
	assert_array(Array(mine[&"known_cell"])).is_equal([5 * COLS + 6])
	assert_array(Array(mine[&"known_owner"])).is_equal([2])
	var other: Dictionary = snap.mines_for(2)
	assert_array(Array(other[&"own_cell"])).is_equal([5 * COLS + 6, 9 * COLS + 12])
	assert_int((other[&"known_cell"] as PackedInt32Array).size()).is_equal(0)
	assert_int((snap.mines_for(0)[&"own_cell"] as PackedInt32Array).size()).is_equal(0)


func test_no_view_ui_or_input_file_names_a_raw_mine_column() -> void:
	var found: Array[String] = []
	for dir: String in SCAN_DIRS:
		_scan(dir, found)
	assert_array(found).is_empty()


func _scan(dir: String, found: Array[String]) -> void:
	for name: String in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + name, found)
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string(dir + "/" + file)
		for token: String in MINE_NAMES:
			if text.contains(token):
				found.append(dir + "/" + file + ": " + token)
