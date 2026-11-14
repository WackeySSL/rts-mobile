extends "res://tests/sim/support/mine_suite.gd"
## What a player knows of other players' mines (plan row P288, ADR 0037 sections 8 and 16):
## `MineMemory` remembers by detectors x mines on the player's fog turn and forgets a mine it sees
## gone, `MINE_CHECKS` counts the distance tests, a mine-aware row sweeps a mine it has a record of,
## and `PlayerView` and `MatchSnapshot` carry the player's own and known lists. The rig is
## `support/mine_suite.gd`.


func test_a_detector_within_range_of_a_seen_enemy_mine_remembers_it_and_counts_the_test() -> void:
	var world: World = _seeing_world()
	_add(world, 1, TANK, 5, 5)
	_put(world, 2, 6, 5)  # 1,000 away.
	_put(world, 2, 9, 5)  # 4,000 away: out of range.
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([1])
	var at: int = world.mine_known_cap
	assert_array([world.mine_seen_owner[at], world.mine_seen_cell[at]]).is_equal([2, 5 * COLS + 6])
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_equal(2)  # One detector x two mines.
	assert_int(world.mine_seen_count[2]).is_equal(0)


func test_nothing_is_remembered_off_the_fog_turn_unseen_own_or_without_a_detector() -> void:
	var world: World = _seeing_world()
	var tank: int = _add(world, 1, TANK, 5, 5)
	_put(world, 2, 6, 5)
	_put(world, 1, 5, 6)  # Its own.
	world.tick = 1  # Player 1's turn is the multiples of 3.
	MineMemory.run(world)
	assert_int(world.mine_seen_count[1]).is_equal(0)
	world.fog.visible[6 + 5 * COLS] = 0  # Not seen now, though in range.
	_turn(world, 1)
	assert_int(world.mine_seen_count[1]).is_equal(0)
	world.fog.visible[6 + 5 * COLS] = 1
	world.hp[tank] = 0  # A dead detector, then a unit that does not detect.
	_turn(world, 1)
	assert_int(world.mine_seen_count[1]).is_equal(0)
	_add(world, 1, SQUAD, 5, 5)
	_turn(world, 1)
	assert_int(world.mine_seen_count[1]).is_equal(0)
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_equal(0)


func test_a_full_block_keeps_the_lowest_ids_in_every_run() -> void:
	var world: World = _seeing_world(3)
	world.mine_known_cap = 2
	_add(world, 1, AWARE, 5, 5)
	for col: int in [4, 5, 6]:
		_put(world, 2, col, 6)
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([1, 2])
	assert_int(world.stats[World.Stat.MINE_CHECKS]).is_equal(2)  # The third is never tested.
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([1, 2])


func test_a_record_is_forgotten_when_its_cell_is_seen_without_the_mine_and_kept_in_the_dark(
) -> void:
	var world: World = _seeing_world()
	_add(world, 1, TANK, 5, 5)
	_put(world, 2, 6, 5)
	_put(world, 2, 4, 5)
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([1, 2])
	world.fog.visible[6 + 5 * COLS] = 0
	Mines.clear_radius(world, 6500, 5500, 100)  # The mine of id 1 goes while out of sight.
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([1, 2])  # Still remembered.
	world.fog.visible[6 + 5 * COLS] = 1
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([2])
	var at: int = world.mine_known_cap + 1
	assert_array([world.mine_seen_id[at], world.mine_seen_cell[at]]).is_equal([0, 0])  # Freed.


func test_a_new_mine_on_a_remembered_cell_is_another_mine() -> void:
	var world: World = _seeing_world()
	_add(world, 1, TANK, 5, 5)
	_put(world, 2, 6, 5)
	_turn(world, 1)
	Mines.clear_radius(world, 6500, 5500, 100)
	_put(world, 2, 6, 5)  # Id 2 on the same cell.
	_turn(world, 1)
	assert_array(_seen(world, 1)).is_equal([2])  # Forgot id 1, found id 2.


func test_the_other_players_turn_is_its_own() -> void:
	var world: World = _seeing_world()
	_add(world, 2, TANK, 6, 6)
	_put(world, 1, 6, 5)
	_turn(world, 1)
	assert_int(world.mine_seen_count[2]).is_equal(0)  # Player 2's turn is not this tick.
	_turn(world, 2)
	assert_array(_seen(world, 2)).is_equal([1])
	assert_int(world.mine_seen_count[1]).is_equal(0)


func test_an_aware_row_idle_on_a_known_enemy_mine_sweeps_it_without_a_blast() -> void:
	var world: World = _seeing_world()
	var row: int = _add(world, 1, AWARE, 6, 5)
	_put(world, 2, 6, 5)
	_turn(world, 1)
	assert_int(world.mine_seen_count[1]).is_equal(1)
	_step(world)
	assert_int(world.carry_mode[row]).is_equal(Mines.SWEEPING)
	assert_int(world.ready_tick[row]).is_equal(world.tick - 1 + 1 + world.sweep_ticks)
	for _tick: int in world.sweep_ticks - 2:
		_step(world)
	assert_int(world.mine_count).is_equal(1)
	assert_int(world.hp[row]).is_equal(200)
	_steps(world, 3)
	assert_int(world.mine_count).is_equal(0)
	assert_int(world.mine_at[5 * COLS + 6]).is_equal(0)
	assert_int(world.carry_mode[row]).is_equal(0)
	assert_array(_blasts(world)).is_empty()
	assert_int(world.hp[row]).is_equal(200)


func test_a_mine_without_a_record_own_or_a_non_aware_row_is_not_swept() -> void:
	var world: World = _seeing_world()
	var aware: int = _add(world, 1, AWARE, 6, 5)
	_put(world, 2, 6, 5)  # No record: the row's own sight does not make one.
	_put(world, 1, 8, 5)
	var other: int = _add(world, 1, AWARE, 8, 5)  # Its own mine.
	world.type_detect_milli[AWARE] = 0
	_steps(world, 3)
	assert_array([world.carry_mode[aware], world.carry_mode[other]]).is_equal([0, 0])
	var tank: int = _add(world, 1, TANK, 6, 5)
	world.type_detect_milli[TANK] = 2000
	_turn(world, 1)
	_steps(world, 2)
	assert_int(world.carry_mode[tank]).is_equal(0)  # A tank triggers it instead.
	assert_int(world.mine_count).is_less(2)


func test_a_new_order_cancels_a_sweep_and_the_mine_stays() -> void:
	var world: World = _seeing_world()
	var row: int = _add(world, 1, AWARE, 6, 5)
	_put(world, 2, 6, 5)
	_turn(world, 1)
	_step(world)
	assert_int(world.carry_mode[row]).is_equal(Mines.SWEEPING)
	_step(world, [Command.move(1, PackedInt32Array([world.unit_id[row]]), 9500, 5500)])
	assert_int(world.carry_mode[row]).is_equal(0)
	_steps(world, world.sweep_ticks + 3)
	assert_int(world.mine_count).is_equal(1)


func test_player_view_holds_the_own_and_the_found_mines_as_copies() -> void:
	var world: World = _seeing_world()
	_add(world, 1, TANK, 5, 5)
	_put(world, 1, 4, 4)
	_put(world, 2, 6, 5)
	_put(world, 2, 12, 9)  # Never found.
	_turn(world, 1)
	var view: PlayerView = PlayerView.of(world, 1)
	assert_array(Array(view.own_mines)).is_equal([4 * COLS + 4])
	assert_array(Array(view.own_mine_id)).is_equal([1])
	assert_array(Array(view.own_mine_armed)).is_equal([1])
	assert_array(Array(view.known_mines)).is_equal([5 * COLS + 6])
	assert_array(Array(view.known_mine_id)).is_equal([2])
	assert_array(Array(view.known_mine_owner)).is_equal([2])
	var enemy: PlayerView = PlayerView.of(world, 2)
	assert_array(Array(enemy.own_mines)).is_equal([5 * COLS + 6, 9 * COLS + 12])
	assert_int(enemy.known_mines.size()).is_equal(0)
	view.own_mines[0] = 99
	view.known_mines[0] = 99
	assert_int(world.mine_cell[0]).is_equal(4 * COLS + 4)
	assert_int(world.mine_seen_cell[world.mine_known_cap]).is_equal(5 * COLS + 6)
	assert_int(PlayerView.of(world, 0).own_mines.size()).is_equal(0)


func test_the_snapshot_carries_the_table_and_the_records() -> void:
	var world: World = _seeing_world()
	_add(world, 1, TANK, 5, 5)
	_put(world, 2, 6, 5)
	_turn(world, 1)
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.capture(world, null)
	assert_int(snap.mine_count).is_equal(1)
	assert_int(snap.mine_known_cap).is_equal(world.mine_known_cap)
	assert_array(Array(snap.mine_id)).is_equal(Array(world.mine_id))
	assert_array(Array(snap.mine_seen_id)).is_equal(Array(world.mine_seen_id))
	assert_array(Array(snap.mine_seen_count)).is_equal([0, 1, 0])
	world.mine_seen_count[1] = 0
	assert_int(snap.mine_seen_count[1]).is_equal(1)  # A copy.
