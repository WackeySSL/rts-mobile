extends GdUnitTestSuite
## Where UnitLayer aims (plan P44a): a turret eases onto the bearing of the row in
## `snapshot.target_row` (computed on the worker, never searched here) and a rig without a turret,
## a squad, turns as a whole; a unit with no target keeps its turret on its hull; a target that is
## gone but not yet replaced (`target_row` -1 while `target` is not 0) leaves the turret where it
## was. Cases with exact numbers write positions and rows into the published snapshot (ADR 0012
## section 3 allows it in SYNC mode); the others run the real sim: two units 3 tiles apart on open
## grass, the second south of the first, so the bearing of the first to the second is PI / 2. The
## hull turns at 12 rad/s, so a frame of 0.05 s turns it 0.6 rad. The runner is not in the tree, so
## only the calls here move time. The rows, merges and heading of the layer are in
## test_unit_layer.gd and test_unit_layer_rows.gd (gdlint allows 20 public methods per file).

const FRAME_SECONDS: float = 0.05
const TURN_PER_FRAME: float = 0.6  ## 12 rad/s * FRAME_SECONDS.
const SOUTH: float = PI / 2.0

var _runner: MatchRunner
var _layer: UnitLayer


func before_test() -> void:
	_runner = auto_free(MatchRunner.new())
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	add_child(_layer)
	_layer.set_process(false)  # Frames come only from _frames().


func after_test() -> void:
	CommandQueue.clear()


func test_a_turret_eases_onto_its_target_while_the_hull_keeps_its_heading() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 10, 13)])
	_run_until_target(0)
	_run_until_target(1)
	assert_int(_runner.snapshot.target_row[0]).is_equal(1)
	assert_int(_runner.snapshot.target_row[1]).is_equal(0)
	_layer._process(FRAME_SECONDS)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(TURN_PER_FRAME, 0.001)
	assert_float(_part(1, "Turret").rotation).is_equal_approx(-TURN_PER_FRAME, 0.001)
	_layer._process(FRAME_SECONDS)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(2.0 * TURN_PER_FRAME, 0.001)
	_frames(10)
	assert_float(absf(angle_difference(_part(0, "Turret").rotation, SOUTH))).is_less(0.05)
	assert_float(absf(angle_difference(_part(1, "Turret").rotation, -SOUTH))).is_less(0.05)
	for row: int in 2:  # Neither tank moved: the hulls and the tint layers face east, as before.
		assert_float(_part(row, "Hull").rotation).is_equal(0.0)
		assert_float(_part(row, "Team").rotation).is_equal(0.0)


func test_the_bearing_is_taken_between_the_positions_of_the_tick_and_again_in_the_next() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 20, 20)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.prev_pos_x[0] = 9000  # The tank itself moves from (9000, 9000) to (11000, 11000),
	snap.prev_pos_y[0] = 9000
	snap.pos_x[0] = 11000
	snap.pos_y[0] = 11000
	snap.prev_pos_x[1] = 13000  # and the target from (13000, 10000) to (13000, 16000).
	snap.prev_pos_y[1] = 10000
	snap.pos_x[1] = 13000
	snap.pos_y[1] = 16000
	snap.target[0] = snap.unit_id[1]
	snap.target_row[0] = 1
	snap.tick += 1  # Written as the next tick, so that the layer takes its bearings from it.
	_runner._process(1.0 / 30.0)  # Half a tick on: alpha 0.5, which the bearing does not follow.
	assert_float(_runner.alpha()).is_equal(0.5)
	_frames(10)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(atan2(5000.0, 2000.0), 0.001)
	snap.pos_x[1] = 8000  # The next tick: the target stands at (8000, 16000), north-west of
	snap.tick += 1  # the tank's (11000, 11000), 3000 to the west and 5000 to the south.
	_frames(10)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(atan2(5000.0, -3000.0), 0.001)


func test_a_new_match_takes_the_bearings_again_even_at_the_same_tick() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 10, 13)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.target[0] = snap.unit_id[1]  # Tick 7 of a match, the target 3000 to the south.
	snap.target_row[0] = 1
	snap.tick = 7
	_frames(10)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(SOUTH, 0.001)
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 13, 10)], false)
	snap = _runner.snapshot  # Tick 7 of the next, the target 3000 to the east.
	snap.target[0] = snap.unit_id[1]
	snap.target_row[0] = 1
	snap.tick = 7
	_frames(10)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(0.0, 0.001)


func test_the_hull_turns_on_the_move_while_the_turret_holds_its_target() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 10, 20)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.target[0] = snap.unit_id[1]  # The red tank, 10 tiles south: the turret bearing is south.
	snap.target_row[0] = 1
	snap.tick += 1  # Written as the next tick, so that the layer takes its bearings from it.
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(SOUTH, 0.001)
	assert_float(_part(0, "Hull").rotation).is_equal(0.0)
	snap.prev_pos_y[0] = snap.pos_y[0] + 120  # Now a full step north (data/units/light_tank.tres).
	_frames(12)
	assert_float(_part(0, "Hull").rotation).is_equal_approx(-SOUTH, 0.001)
	assert_float(_part(0, "Team").rotation).is_equal(_part(0, "Hull").rotation)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(SOUTH, 0.001)  # Still on its target.


func test_a_squad_rig_turns_as_a_whole_toward_its_target() -> void:
	# The red tank is row 0 and the blue squad row 1, so the squad's target is row 0.
	_start([_spawn(2, "light_tank", 10, 13), _spawn(1, "rifle_squad", 10, 10)])
	assert_int(_part_count(1)).is_equal(2)  # Hull and Team: a squad has no turret to swing.
	_run_until_target(0)
	_run_until_target(1)
	assert_int(_runner.snapshot.target_row[1]).is_equal(0)
	_layer._process(FRAME_SECONDS)
	assert_float(_part(1, "Hull").rotation).is_equal_approx(TURN_PER_FRAME, 0.001)
	assert_float(_part(1, "Team").rotation).is_equal(_part(1, "Hull").rotation)
	_frames(10)
	assert_float(_part(1, "Hull").rotation).is_equal_approx(SOUTH, 0.001)
	assert_float(_part(1, "Team").rotation).is_equal(_part(1, "Hull").rotation)
	# The tank beside it turns its turret and not its hull.
	assert_float(_part(0, "Hull").rotation).is_equal(0.0)
	assert_float(absf(angle_difference(_part(0, "Turret").rotation, -SOUTH))).is_less(0.05)
	# A squad whose target is gone keeps facing where it was: nothing sends it back to east.
	_runner.world.hp[0] = 0
	_runner.run_ticks(1)
	assert_int(_runner.snapshot.target_row[0]).is_equal(-1)  # The squad is row 0 now.
	_frames(10)
	assert_float(_part(0, "Hull").rotation).is_equal_approx(SOUTH, 0.001)


func test_a_target_that_died_in_the_tick_leaves_the_turret_where_it_was() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 10, 13)])
	_run_until_target(0)
	_frames(12)
	var aimed: float = _part(0, "Turret").rotation
	assert_float(aimed).is_equal_approx(SOUTH, 0.001)
	_runner.world.hp[1] = 0  # The red tank dies in the next tick.
	_runner.run_ticks(1)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(1)
	assert_int(snap.target[0]).is_not_equal(0)  # The sim leaves the dead target for its next scan,
	assert_int(snap.target_row[0]).is_equal(-1)  # but its row is gone.
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal(aimed)
	# A turret that was mid-swing stops where it is, and does not go on to the bearing it had.
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 10, 13)])
	_run_until_target(0)
	_layer._process(FRAME_SECONDS)
	_runner.world.hp[1] = 0
	_runner.run_ticks(1)
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(TURN_PER_FRAME, 0.001)


func test_with_no_target_left_the_turret_swings_back_onto_its_hull() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 10, 13)])
	_run_until_target(0)
	_frames(12)
	_runner.world.hp[1] = 0
	_runner.run_ticks(1)
	for _tick: int in 10:  # The next scan drops the target that is gone.
		if _runner.snapshot.target[0] == 0:
			break
		_runner.run_ticks(1)
	assert_int(_runner.snapshot.target[0]).is_equal(0)
	_layer._process(FRAME_SECONDS)  # It eases back, as it eased out.
	assert_float(_part(0, "Turret").rotation).is_equal_approx(SOUTH - TURN_PER_FRAME, 0.001)
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal(_part(0, "Hull").rotation)
	# And a hull that turns takes the turret with it, to the last bit, as before the target.
	CommandQueue.submit(Command.move(1, PackedInt32Array([1]), 10500, 4500))  # Due north.
	_runner.run_ticks(1)
	_frames(12)
	assert_float(_part(0, "Hull").rotation).is_equal_approx(-SOUTH, 0.001)
	assert_float(_part(0, "Turret").rotation).is_equal(_part(0, "Hull").rotation)


func test_a_turret_keeps_its_angle_when_a_unit_before_it_dies() -> void:
	var far: SpawnDef = _spawn(1, "light_tank", 3, 3)
	_start([far, _spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 10, 13)])
	_run_until_target(1)
	_run_until_target(2)
	_frames(12)
	assert_float(_part(1, "Turret").rotation).is_equal_approx(SOUTH, 0.001)
	assert_float(_part(2, "Turret").rotation).is_equal_approx(-SOUTH, 0.001)
	_runner.world.hp[0] = 0  # The tank at row 0 dies: the aimed tank becomes row 0.
	_runner.run_ticks(1)
	assert_int(_runner.snapshot.unit_count()).is_equal(2)
	_layer._process(0.0)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(SOUTH, 0.001)
	assert_float(_part(1, "Turret").rotation).is_equal_approx(-SOUTH, 0.001)


func test_an_armed_neutral_tank_aims_at_a_player_tank_that_does_not_aim_back() -> void:
	# Plan design note: an armed unit of owner 0 acquires every player's units, and nothing else
	# turns on whose unit it is. A player's unit does not take a neutral one for an enemy.
	_start([_spawn(0, "light_tank", 10, 10), _spawn(1, "light_tank", 10, 13)])
	_run_until_target(0)
	assert_int(_runner.snapshot.target_row[0]).is_equal(1)
	assert_int(_runner.snapshot.target_row[1]).is_equal(-1)
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(SOUTH, 0.001)
	assert_float(_part(1, "Turret").rotation).is_equal(_part(1, "Hull").rotation)


func test_frames_that_aim_leave_no_new_objects_alive() -> void:
	_start([_spawn(1, "rifle_squad", 10, 10), _spawn(2, "light_tank", 10, 13)])
	_run_until_target(0)
	_run_until_target(1)
	_layer._process(0.0)
	await await_idle_frame()
	await await_idle_frame()  # The first idle frame leaves an object of the test runner behind.
	# Counts are read between the steps and asserted at the end: an assertion is an object too.
	var before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame: int in 20:  # The squad and the turret both swing for the first 8 of them.
		_layer._process(0.016)
	var after_frames: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_float(_part(0, "Hull").rotation).is_not_equal(0.0)
	assert_float(after_frames).is_equal(before)


## Frames of FRAME_SECONDS, the first of zero length.
func _frames(count: int) -> void:
	_layer._process(0.0)
	for _frame: int in count:
		_layer._process(FRAME_SECONDS)


func _rig(row: int) -> Node2D:
	return _layer.get_child(row)


func _part(row: int, part: String) -> Sprite2D:
	return _rig(row).get_node(part)


func _part_count(row: int) -> int:
	return _rig(row).get_child_count()


## Plays ticks until row `row` holds a target (50 at most: the sim scans every 5 ticks).
func _run_until_target(row: int) -> void:
	for _tick: int in 50:
		if _runner.snapshot.target[row] != 0:
			return
		_runner.run_ticks(1)
	assert_int(_runner.snapshot.target[row]).is_not_equal(0)


## One unit of `unit` (a file of data/units) for `owner_id` on tile (x, y).
func _spawn(owner_id: int, unit: String, x: int, y: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = owner_id
	spawn.unit = load("res://data/units/%s.tres" % unit)
	spawn.count = 1
	spawn.origin_tile = Vector2i(x, y)
	return spawn


## A new match of `spawns` (SpawnDefs) on open grass, drawn by the layer at once unless `draw` is
## false, so that a case can write the snapshot before the layer's first frame of it.
func _start(spawns: Array, draw: bool = true) -> void:
	_runner.scenario = ScenarioDef.new()
	_runner.scenario.spawns.assign(spawns)
	_runner.start()
	if draw:
		_layer._process(0.0)
