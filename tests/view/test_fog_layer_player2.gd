extends GdUnitTestSuite
## What FogLayer draws for local player 2 and on maps that are not square (plan P47, fix round 1).
## test_fog_layer.gd runs its patch, version and overflow cases as player 1, whose block of the
## fog grid starts at 0, and on the 48 x 48 map, where cols * cols is cells: a layer that stood on
## player 1's version, list or block, or on a square map, would pass them all. Here the layer
## follows player 2's version and dirty list on controls_test, and draws player 2's block on the
## 40 x 24 battle map of EffectsRig, which resizes by its rows alone and by its columns alone.
## Exact cases write one update into the published snapshot's fog, as ADR 0012 section 3 lets a
## SYNC test do, and emit `ticked`; the march plays the real sim. The runner is not in the tree.

const Rig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const EffectsRig: GDScript = preload("res://tests/view/support/effects_rig.gd")

var _runner: MatchRunner
var _fog: FogLayer


func before_test() -> void:
	_runner = null
	_fog = null


func after_test() -> void:
	CommandQueue.clear()


func test_player_2_patches_by_its_own_version_and_list_and_never_rebuilds_on_a_march() -> void:
	_build(Rig.scenario(2))
	assert_int(_fog.rebuild_count()).is_equal(1)
	# Both blocks drive, so both players' fog moves; the layer follows player 2's version only.
	CommandQueue.submit(Command.move(1, PackedInt32Array(range(1, 31)), 24000, 21500))
	CommandQueue.submit(Command.move(2, PackedInt32Array(range(31, 41)), 20000, 12000))
	var changed: int = 0
	for tick: int in 70:
		var version: int = _runner.snapshot.fog.version_of(2)
		var uploads: int = _fog.upload_count()
		_runner.run_ticks(1)
		var moved: bool = _runner.snapshot.fog.version_of(2) != version
		changed += int(moved)
		var text: String = "tick %d" % tick
		assert_int(_fog.upload_count()).override_failure_message(text).is_equal(
			uploads + (1 if moved else 0)
		)
		var wrong: Array[int] = Rig.mismatches(_fog.image(), _runner.snapshot.fog, 2)
		assert_array(wrong).override_failure_message(text).is_empty()
	assert_int(changed).is_greater(5)  # Player 2's updates, one tick in three.
	assert_int(_fog.upload_count()).is_equal(1 + changed)
	assert_int(_fog.rebuild_count()).is_equal(1)  # Only the match start drew from the grids.


func test_an_overflowed_dirty_list_of_player_2_rebuilds_from_its_own_block() -> void:
	_build(Rig.scenario(2))
	var snap: MatchSnapshot = _runner.snapshot
	var rebuilds: int = _fog.rebuild_count()
	Rig.flip(snap, 2, [Vector2i(30, 30)] as Array[Vector2i], true)
	snap.fog.dirty_full[1] = 1  # Player 2's list is only a prefix; player 1's flag stays clear.
	Rig.set_seen(snap, 2, Vector2i(5, 40), true)  # Not in the list.
	_runner.ticked.emit(snap.tick)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_int(_fog.image().get_pixel(5, 40).a8).is_equal(0)  # Not listed, still drawn.
	assert_array(Rig.mismatches(_fog.image(), snap.fog, 2)).is_empty()


func test_an_overflow_of_player_1_is_not_player_2s_to_rebuild_for() -> void:
	_build(Rig.scenario(2))
	var snap: MatchSnapshot = _runner.snapshot
	var rebuilds: int = _fog.rebuild_count()
	Rig.flip(snap, 2, [Vector2i(30, 30)] as Array[Vector2i], true)
	snap.fog.dirty_full[0] = 1  # The other player's list overflowed: no business of this layer.
	Rig.set_seen(snap, 2, Vector2i(5, 40), true)
	_runner.ticked.emit(snap.tick)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds)
	assert_int(_fog.image().get_pixel(30, 30).a8).is_equal(0)
	assert_int(_fog.image().get_pixel(5, 40).a8).is_equal(255)  # A patch writes the list only.


func test_player_2_on_a_map_that_is_not_square_draws_its_own_block_of_the_grid() -> void:
	var scenario: ScenarioDef = EffectsRig.battle()  # 40 x 24: cols * cols is not cells.
	scenario.local_player = 2
	_build(scenario)
	assert_that(_fog.image().get_size()).is_equal(Vector2i(40, 24))
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 2)).is_empty()
	var start: Vector3i = Rig.tally(_fog.image())
	assert_int(start.z).is_greater(0)  # Its own units see their tiles.
	assert_int(start.x).is_greater(0)
	for tick: int in 40:
		_runner.run_ticks(1)
		var wrong: Array[int] = Rig.mismatches(_fog.image(), _runner.snapshot.fog, 2)
		assert_array(wrong).override_failure_message("tick %d" % tick).is_empty()
	assert_that(Rig.tally(_fog.image())).is_not_equal(start)  # The armies moved, the fog with them.
	assert_int(_fog.rebuild_count()).is_equal(1)


func test_a_new_match_that_changes_only_the_rows_or_only_the_columns_resizes_the_image() -> void:
	var scenario: ScenarioDef = EffectsRig.battle()
	scenario.local_player = 2
	_build(scenario)
	for size: Vector2i in [Vector2i(40, 30), Vector2i(48, 30), Vector2i(48, 24)]:
		var rebuilds: int = _fog.rebuild_count()
		scenario.map_size_tiles = size  # One side changes at a time, the other keeps its value.
		_runner.start()
		_fog._process(0.0)
		assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
		assert_that(_fog.image().get_size()).is_equal(size)
		assert_that(_fog.texture.get_size()).is_equal(Vector2(size))
		var wrong: Array[int] = Rig.mismatches(_fog.image(), _runner.snapshot.fog, 2)
		assert_array(wrong).override_failure_message(str(size)).is_empty()
		_runner.run_ticks(5)  # Patches on the new size.
		assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 2)).is_empty()


func _build(scenario: ScenarioDef) -> void:
	if is_instance_valid(_fog):
		_fog.free()
	if is_instance_valid(_runner):
		_runner.free()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.start()
	_fog = auto_free(FogLayer.new())
	_fog.runner = _runner
	add_child(_fog)
	_fog.set_process(false)  # Frames come only from `_fog._process()`.
