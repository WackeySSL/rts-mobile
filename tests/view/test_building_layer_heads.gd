extends GdUnitTestSuite
## The head of a defence (plan P115, ADR 0023 section 2): a child sprite that turns in 16 steps
## toward the building's target as a tank's turret does (`UnitLayer`: the grid angle, `d06` east,
## eased at `turn_rate`), keeps its angle while the target is gone, is written only when its frame
## index changes, and does not turn while the building is hidden. Only the heads change in a
## frame; the buildings themselves are in test_building_layer.gd.
## On a 32 x 32 map: player 1's Redoubt (1x1) at tile (10, 10), so its centre is (10.5, 10.5),
## and its light tank at (14.5, 10.5) east of it, an enemy Lumen Accord tank at (10.5, 14.5) south
## of it and a Lumen Accord defence at (3, 3). The runner is not in the tree: the target is written
## into the published snapshot, which the layer reads (ADR 0012 section 3), and alpha is 0.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const REDOUBT: int = 1
const TANK: int = 2  ## The Derrick League's, east of the Redoubt.
const ENEMY_TANK: int = 3  ## The Lumen Accord's, south of it.
const ENEMY_DEFENCE: int = 4
const STEP: float = 0.05  ## A frame of 50 ms turns a head by 0.6 rad at 12 rad/s.

var _runner: MatchRunner
var _layer: BuildingLayer


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "defence_turret", 10, 10),
		Rig.spawn(1, "light_tank", 14, 10),
		Rig.spawn(2, "renew_tank", 10, 14),
		Rig.spawn(2, "renew_defence", 3, 3),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_a_head_with_no_target_stays_on_d06() -> void:
	for _frame: int in 20:
		_layer._process(STEP)
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(6)


func test_a_head_turns_toward_its_target_in_steps_of_the_turn_rate() -> void:
	_aim(REDOUBT, ENEMY_TANK)  # Grid south: a quarter turn from east, 1.571 rad.
	_layer._process(STEP)
	# 12 rad/s x 0.05 s = 0.6 rad: 1.5 steps of 22.5 degrees, which rounds to 2 (d08).
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(8)
	_layer._process(STEP)  # 1.2 rad: 3.06 steps, d09.
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(9)
	_layer._process(STEP)  # Past the aim: it stops on it, 4 steps, d10 (grid +y faces south-west).
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(10)
	var done: int = Rig.head_frame(_layer, REDOUBT)
	for _frame: int in 10:
		_layer._process(STEP)
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(done)


func test_the_head_frame_is_the_nearest_of_16_to_the_bearing_of_the_target() -> void:
	# Targets round the Redoubt at (10.5, 10.5), each far enough for the head to arrive: the frame
	# is the rig_frames rule for the bearing of the grid vector to the target.
	var cases: Array[Vector2i] = [
		Vector2i(16500, 10500),  # East, d06.
		Vector2i(16500, 12500),
		Vector2i(10500, 16500),  # South on the grid, d10.
		Vector2i(5500, 12500),
		Vector2i(4500, 10500),  # West, d14.
		Vector2i(8500, 4500),
		Vector2i(10500, 4500),  # North on the grid, d02.
		Vector2i(14500, 6500),
	]
	for target_at: Vector2i in cases:
		_move(ENEMY_TANK, target_at)
		_aim(REDOUBT, ENEMY_TANK)
		for _frame: int in 12:  # More than the half turn of 3.14 rad at 0.6 rad a frame.
			_layer._process(STEP)
		var bearing: float = atan2(target_at.y - 10500.0, target_at.x - 10500.0)
		(
			assert_int(Rig.head_frame(_layer, REDOUBT))
			. override_failure_message("target at %s" % target_at)
			. is_equal(Frames.of_angle(bearing))
		)


func test_the_head_follows_a_target_that_moves_and_keeps_its_angle_when_the_target_is_gone(
) -> void:
	_aim(REDOUBT, TANK)
	for _frame: int in 3:
		_layer._process(STEP)
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(6)
	_move(TANK, Vector2i(10500, 4500))  # Now due north on the grid.
	for _frame: int in 12:
		_layer._process(STEP)
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(2)
	_runner.snapshot.target[0] = 0  # The target is gone: no row, no id.
	_runner.snapshot.target_row[0] = -1
	for _frame: int in 12:
		_layer._process(STEP)
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(2)  # It stays where it looked.


func test_a_region_is_written_only_when_the_frame_index_changes() -> void:
	_aim(REDOUBT, ENEMY_TANK)
	var head: Sprite2D = Rig.head(_layer, REDOUBT)
	var bogus: Rect2 = Rect2(1, 1, 2, 2)  # A region no frame has, written by the test.
	head.region_rect = bogus
	_layer._process(STEP / 4.0)  # 0.15 rad: 0.38 of a step, still d06, so nothing is written.
	assert_that(head.region_rect).is_equal(bogus)
	_layer._process(STEP / 4.0)  # 0.3 rad: 0.76 of a step, d07: the region is written.
	assert_int(Rig.head_frame(_layer, REDOUBT)).is_equal(7)
	head.region_rect = bogus
	_layer._process(STEP / 4.0)  # 0.45 rad: 1.15 steps, still d07.
	assert_that(head.region_rect).is_equal(bogus)
	assert_int(Rig.head_frame(_layer, ENEMY_DEFENCE)).is_equal(6)  # A building with no target.


func test_a_hidden_enemy_defence_does_not_turn() -> void:
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_bool(_layer.building(ENEMY_DEFENCE).visible).is_false()
	_aim(ENEMY_DEFENCE, TANK)
	for _frame: int in 12:
		_layer._process(STEP)
	assert_int(Rig.head_frame(_layer, ENEMY_DEFENCE)).is_equal(6)  # Not seen, so not turned.
	Rig.see(_runner.snapshot, 1, [Vector2i(3, 3)])
	_layer._process(STEP)
	assert_bool(_layer.building(ENEMY_DEFENCE).visible).is_true()
	for _frame: int in 12:
		_layer._process(STEP)
	var bearing: float = atan2(10500.0 - 3500.0, 14500.0 - 3500.0)
	assert_int(Rig.head_frame(_layer, ENEMY_DEFENCE)).is_equal(Frames.of_angle(bearing))


## Building `id` aims at unit `target_id`: the published snapshot's target and its row.
func _aim(id: int, target_id: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	snap.target[row] = target_id
	snap.target_row[row] = snap.index_of(target_id)


## Unit `id` stands at `at`, milli-tiles, in both ticks of the published snapshot.
func _move(id: int, at: Vector2i) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	snap.pos_x[row] = at.x
	snap.pos_y[row] = at.y
	snap.prev_pos_x[row] = at.x
	snap.prev_pos_y[row] = at.y
