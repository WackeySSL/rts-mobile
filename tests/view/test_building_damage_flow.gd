extends "res://tests/view/support/damage_suite.gd"
## Damage stages and the fog (plan P159, ADR 0028 sections 2 and 5): a site shows none, a hidden
## enemy building writes nothing, the remembered stage for the ghosts. Fixtures:
## support/damage_suite.gd.

# --- Sites, fog, the remembered stage ---


func test_a_site_shows_no_stage_whatever_its_hp_and_shows_it_when_complete() -> void:
	_open(_pair() + [[1, 22, 4]])  # A spare, so the match does not end while building 1 is a site.
	_runner.world.build_left[0] = 100000  # Far from complete (building 1 is row 0).
	Dmg.hit(_runner, 1, 10)
	_layer._process(0.0)
	assert_int(_runner.snapshot.build_left[_runner.snapshot.index_of(1)]).is_not_equal(0)
	assert_bool(_patch(1).visible).is_false()
	assert_that(_body(1).region_rect).is_equal(Rect2(_region(&"hull")))
	_runner.world.build_left[0] = Production.CANCELLED  # A cancelled site is a site.
	Dmg.hit(_runner, 1, 10)
	_layer._process(0.0)
	assert_bool(_patch(1).visible).is_false()
	_runner.world.build_left[0] = 0  # Complete, and it took hits meanwhile.
	_runner.run_ticks(1)
	_layer._process(0.0)
	_check_stage(1, 2)


func test_a_hidden_enemy_building_writes_nothing_and_shows_its_stage_when_seen() -> void:
	_open(_pair(), {}, 1.0, false)
	var snap: MatchSnapshot = _runner.snapshot
	Dmg.Rig.see(snap, 1, [])  # Nothing seen.
	_layer._process(0.0)
	assert_bool(_layer.is_shown(snap.index_of(2))).is_false()
	var writes: int = _layer.life_writes()
	var region: Rect2 = _body(2).region_rect
	_hit(2, 20)
	Dmg.Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_int(_layer.life_writes()).is_equal(writes)
	assert_that(_body(2).region_rect).is_equal(region)
	assert_bool(_patch(2).visible).is_false()
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])  # A cell of its footprint.
	_layer._process(0.0)
	_check_stage(2, 2)  # The stage of now.


func test_the_stage_is_remembered_only_while_the_enemy_building_is_shown() -> void:
	_open(_pair(), {}, 1.0, false)
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_layer._process(0.0)
	assert_int(_layer.remembered_stage(2)).is_equal(0)
	Dmg.set_hp(_runner, 2, 66)
	_runner.run_ticks(1)  # Seen: noted. (The sim's fog is not what the fixture wrote.)
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.remembered_stage(2)).is_equal(1)
	Dmg.Rig.see(_runner.snapshot, 1, [])  # Out of sight.
	Dmg.set_hp(_runner, 2, 10)
	_runner.run_ticks(1)
	Dmg.Rig.see(_runner.snapshot, 1, [])
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.remembered_stage(2)).is_equal(1)  # Hit unseen: the last look stands.
	assert_int(_layer.remembered_stage(99)).is_equal(0)  # An unknown id is intact.
	assert_int(_layer.remembered_stage(1)).is_equal(0)  # An own building is not remembered.


func test_a_frame_that_plays_two_ticks_notes_both() -> void:
	_open(_pair())
	var seen: Array[int] = []
	_runner.ticked.connect(func(_t: int) -> void: seen.append(_layer.remembered_stage(2)))
	Dmg.set_hp(_runner, 2, 66)
	_runner.run_ticks(1)
	Dmg.set_hp(_runner, 2, 10)
	_runner.run_ticks(1)
	assert_array(seen).is_equal([1, 2])  # Both ticks were noted before any frame was drawn.


func test_the_note_is_written_after_the_rows_have_compacted() -> void:
	# Building 1 dies in the tick that building 3 drops under a line: row 2 of the snapshot is
	# row 2 - 1 of the entries' old table; a stale row would note building 2 and drop building 3.
	_open([[1, 4, 4], [2, 14, 14], [2, 20, 20]])
	Dmg.set_hp(_runner, 3, 20)
	_runner.world.hp[_runner.world.index_of(1)] = 0
	_runner.run_ticks(1)
	assert_int(_layer.remembered_stage(3)).is_equal(2)
	assert_int(_layer.remembered_stage(2)).is_equal(0)
	_layer._process(0.0)
	_check_stage(3, 2)
	assert_bool(_patch(2).visible).is_false()


func test_the_memory_is_cleared_with_a_new_match_and_with_a_change_of_the_local_player() -> void:
	_open(_pair())
	_hit(2, 20)
	assert_int(_layer.remembered_stage(2)).is_equal(2)
	_runner.scenario.local_player = 2  # Building 2 is now the local player's own.
	assert_int(_layer.remembered_stage(2)).is_equal(0)
	_runner.scenario.local_player = 1
	_layer._process(0.0)
	_hit(2, 20)
	assert_int(_layer.remembered_stage(2)).is_equal(2)
	_runner.start()  # Another match serial.
	_layer._process(0.0)
	assert_int(_layer.remembered_stage(2)).is_equal(0)


func test_a_building_hidden_after_it_was_queued_writes_nothing_until_seen_again() -> void:
	_open(_pair(), {}, 1.0, false)
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_layer._process(0.0)
	Dmg.set_hp(_runner, 2, 10)
	_runner.run_ticks(1)
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_runner.ticked.emit(_runner.snapshot.tick)  # Shown, so queued.
	assert_int(_layer._stage_queue.size()).is_equal(1)
	var writes: int = _layer.life_writes()
	Dmg.Rig.see(_runner.snapshot, 1, [])  # Out of sight before the frame writes it.
	_layer._process(0.0)
	assert_int(_layer.life_writes()).is_equal(writes)
	assert_that(_body(2).region_rect).is_equal(Rect2(_region(&"hull")))
	assert_bool(_patch(2).visible).is_false()
	assert_int(_layer._stage_queue.size()).is_equal(0)
	Dmg.Rig.see(_runner.snapshot, 1, [Vector2i(14, 14)])
	_layer._process(0.0)
	_check_stage(2, 2)
