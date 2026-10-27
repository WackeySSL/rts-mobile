extends GdUnitTestSuite
## Where UnitLayer aims (plan P44a): a turret eases onto the bearing of the row in
## `snapshot.target_row` (computed on the worker, never searched here), taken between the rigs as
## they are drawn (ADR 0011 section 2), and a rig without a turret, a squad, turns as a whole; a
## unit with no target keeps its turret on its hull; a target that is gone but not yet replaced
## (`target_row` -1 while `target` is not 0) leaves the turret where it was. Cases with exact
## numbers write positions and rows into the published snapshot (ADR 0012 section 3 allows it in
## SYNC mode); the others run the real sim: two units 2 tiles apart along the grid diagonal on open
## grass, the second at +x +y of the first. The diagonal is straight down the screen under the 2:1
## projection (P117), so the bearing of the first to the second is PI / 2 and the way back is
## -PI / 2. The hull turns at 12 rad/s, so a frame of 0.05 s turns it 0.6 rad. The runner is not in
## the tree, so only the calls here move time. The rows, merges and heading of the layer are in
## test_unit_layer.gd and test_unit_layer_rows.gd (gdlint allows 20 public methods per file).

const FRAME_SECONDS: float = 0.05
const TURN_PER_FRAME: float = 0.6  ## 12 rad/s * FRAME_SECONDS.
const DOWN: float = PI / 2.0  ## Down the screen: the grid diagonal (+x, +y).
## Grid north (-y) on the screen, atan2(-16, 32): a hull that drives straight north faces it.
const NORTH: float = -0.4636476

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
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 12, 12)])
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
	assert_float(absf(angle_difference(_part(0, "Turret").rotation, DOWN))).is_less(0.05)
	assert_float(absf(angle_difference(_part(1, "Turret").rotation, -DOWN))).is_less(0.05)
	for row: int in 2:  # Neither tank moved: the hulls and the tint layers face east, as before.
		assert_float(_part(row, "Hull").rotation).is_equal(0.0)
		assert_float(_part(row, "Team").rotation).is_equal(0.0)


func test_the_bearing_follows_both_rigs_as_they_are_drawn_within_a_tick() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 20, 20)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.prev_pos_x[0] = 9000  # The tank itself moves from (9000, 9000) to (11000, 11000),
	snap.prev_pos_y[0] = 9000
	snap.pos_x[0] = 11000
	snap.pos_y[0] = 11000
	snap.prev_pos_x[1] = 13000  # and the target from (13000, 10000) to (15000, 16000).
	snap.prev_pos_y[1] = 10000
	snap.pos_x[1] = 15000
	snap.pos_y[1] = 16000
	snap.target[0] = snap.unit_id[1]
	snap.target_row[0] = 1
	# No tick passes below: the snapshot stays the same one, and only alpha moves.
	_frames(10)  # Alpha 0: the rigs stand on their previous positions, 4000 east and 1000 south.
	var at_zero: float = IsoProjection.screen_angle(4000.0, 1000.0)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(at_zero, 0.001)
	_runner._process(1.0 / 30.0)  # Alpha 0.5: (10000, 10000) and (14000, 13000).
	assert_float(_runner.alpha()).is_equal(0.5)
	_frames(10)
	var halfway: float = _part(0, "Turret").rotation
	assert_float(halfway).is_equal_approx(IsoProjection.screen_angle(4000.0, 3000.0), 0.001)
	# The bearing between the positions of the tick, which the turret once took, is another one.
	var of_the_tick: float = IsoProjection.screen_angle(4000.0, 5000.0)
	assert_float(absf(angle_difference(halfway, of_the_tick))).is_greater(0.2)
	_runner._process(1.0 / 60.0)  # Alpha 0.75: (10500, 10500) and (14500, 14500).
	assert_float(_runner.alpha()).is_equal(0.75)
	_frames(10)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN, 0.001)  # 4000 east and south.
	# That is the bearing between the two rigs on the screen, which is what the player compares.
	var between: Vector2 = _rig(1).position - _rig(0).position
	assert_float(_part(0, "Turret").rotation).is_equal_approx(between.angle(), 0.001)


func test_the_turret_reads_target_row_and_never_looks_the_target_up_by_id() -> void:
	# Columns the sim would not write, so that only the row of the worker can explain the result:
	# row 0 has a row to aim at and no target id, row 1 has a target id and no row.
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 12, 12)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.target[0] = 0
	snap.target_row[0] = 1
	snap.target[1] = snap.unit_id[0]  # An id that is in the snapshot, with its row gone.
	snap.target_row[1] = -1
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN, 0.001)
	assert_float(_part(1, "Turret").rotation).is_equal(0.0)  # Held where it was, east.
	assert_float(_part(1, "Hull").rotation).is_equal(0.0)


func test_the_hull_turns_on_the_move_while_the_turret_holds_its_target() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 20, 20)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.target[0] = snap.unit_id[1]  # The red tank, 10 tiles south: the turret bearing is south.
	snap.target_row[0] = 1
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN, 0.001)
	assert_float(_part(0, "Hull").rotation).is_equal(0.0)
	snap.prev_pos_x[0] = snap.pos_x[0] + 85  # A full step (data/units/light_tank.tres: 120, and
	snap.prev_pos_y[0] = snap.pos_y[0] + 85  # 85 x 1.414) up the screen, along the diagonal.
	_frames(12)
	assert_float(_part(0, "Hull").rotation).is_equal_approx(-DOWN, 0.001)
	assert_float(_part(0, "Team").rotation).is_equal(_part(0, "Hull").rotation)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN, 0.001)  # Still on its target.


func test_a_squad_rig_turns_as_a_whole_toward_its_target() -> void:
	# The red tank is row 0 and the blue squad row 1, so the squad's target is row 0.
	_start([_spawn(2, "light_tank", 12, 12), _spawn(1, "rifle_squad", 10, 10)])
	assert_int(_part_count(1)).is_equal(2)  # Hull and Team: a squad has no turret to swing.
	_run_until_target(0)
	_run_until_target(1)
	assert_int(_runner.snapshot.target_row[1]).is_equal(0)
	_layer._process(FRAME_SECONDS)
	assert_float(_part(1, "Hull").rotation).is_equal_approx(TURN_PER_FRAME, 0.001)
	assert_float(_part(1, "Team").rotation).is_equal(_part(1, "Hull").rotation)
	_frames(10)
	assert_float(_part(1, "Hull").rotation).is_equal_approx(DOWN, 0.001)
	assert_float(_part(1, "Team").rotation).is_equal(_part(1, "Hull").rotation)
	# The tank beside it turns its turret and not its hull.
	assert_float(_part(0, "Hull").rotation).is_equal(0.0)
	assert_float(absf(angle_difference(_part(0, "Turret").rotation, -DOWN))).is_less(0.05)
	# A squad whose target is gone keeps facing where it was: nothing sends it back to east.
	_runner.world.hp[0] = 0
	_runner.run_ticks(1)
	assert_int(_runner.snapshot.target_row[0]).is_equal(-1)  # The squad is row 0 now.
	_frames(10)
	assert_float(_part(0, "Hull").rotation).is_equal_approx(DOWN, 0.001)


func test_a_squad_that_moves_faces_its_target_and_not_where_it_goes() -> void:
	# The red tank is row 0 and the blue squad row 1. The squad's last move was a full step due
	# east, its target is 3 tiles to the south: with no turret to swing, the rig faces the target.
	_start([_spawn(2, "light_tank", 12, 12), _spawn(1, "rifle_squad", 10, 10)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.target[1] = snap.unit_id[0]
	snap.target_row[1] = 0
	snap.prev_pos_x[1] = snap.pos_x[1] - snap.type_speed[snap.type_index[1]]
	_frames(10)
	var between: Vector2 = _rig(0).position - _rig(1).position  # The rigs on the screen.
	assert_float(between.angle()).is_greater(1.4)  # South, so not the 0.0 of the move.
	assert_float(_part(1, "Hull").rotation).is_equal_approx(between.angle(), 0.001)
	assert_float(_part(1, "Team").rotation).is_equal(_part(1, "Hull").rotation)


func test_a_turret_takes_the_short_way_round_when_the_bearing_crosses_due_west() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 12, 12)])
	var snap: MatchSnapshot = _runner.snapshot
	# Due west on the screen is the grid direction (-1, +1). The target is (-2000, +1000) from the
	# tank, a little north of it on the screen: bearing -2.976.
	_place_next_to(snap, 1, 0, Vector2i(-2000, 1000))
	snap.target[0] = snap.unit_id[1]
	snap.target_row[0] = 1
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(-2.976, 0.001)
	# The target is (-1000, +2000) now, a little south of due west: bearing +2.976, 0.33 rad from
	# the turret across the west, not 5.95 rad the other way. One frame (0.6 rad) is enough.
	_place_next_to(snap, 1, 0, Vector2i(-1000, 2000))
	_layer._process(FRAME_SECONDS)
	var want: float = IsoProjection.screen_angle(-1000.0, 2000.0)
	assert_float(absf(angle_difference(_part(0, "Turret").rotation, want))).is_less(0.001)


func test_a_squad_takes_the_short_way_round_when_the_bearing_crosses_due_west() -> void:
	# The red tank is row 0 and the blue squad row 1; the squad's target is row 0, west of it.
	_start([_spawn(2, "light_tank", 12, 12), _spawn(1, "rifle_squad", 10, 10)])
	var snap: MatchSnapshot = _runner.snapshot
	_place_next_to(snap, 0, 1, Vector2i(-2000, 1000))  # A little north of due west on the screen.
	snap.target[1] = snap.unit_id[0]
	snap.target_row[1] = 0
	_frames(12)
	assert_float(_part(1, "Hull").rotation).is_equal_approx(-2.976, 0.001)
	_place_next_to(snap, 0, 1, Vector2i(-1000, 2000))  # A little south of it.
	_layer._process(FRAME_SECONDS)
	var want: float = IsoProjection.screen_angle(-1000.0, 2000.0)
	assert_float(absf(angle_difference(_part(1, "Hull").rotation, want))).is_less(0.001)
	assert_float(_part(1, "Team").rotation).is_equal(_part(1, "Hull").rotation)


func test_a_target_that_died_in_the_tick_leaves_the_turret_where_it_was() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 12, 12)])
	_run_until_target(0)
	_frames(12)
	var aimed: float = _part(0, "Turret").rotation
	assert_float(aimed).is_equal_approx(DOWN, 0.001)
	_runner.world.hp[1] = 0  # The red tank dies in the next tick.
	_runner.run_ticks(1)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(1)
	assert_int(snap.target[0]).is_not_equal(0)  # The sim leaves the dead target for its next scan,
	assert_int(snap.target_row[0]).is_equal(-1)  # but its row is gone.
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal(aimed)
	# A turret that was mid-swing stops where it is, and does not go on to the bearing it had.
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 12, 12)])
	_run_until_target(0)
	_layer._process(FRAME_SECONDS)
	_runner.world.hp[1] = 0
	_runner.run_ticks(1)
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(TURN_PER_FRAME, 0.001)


func test_with_no_target_left_the_turret_swings_back_onto_its_hull() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 12, 12)])
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
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN - TURN_PER_FRAME, 0.001)
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal(_part(0, "Hull").rotation)
	# And a hull that turns takes the turret with it, to the last bit, as before the target.
	CommandQueue.submit(Command.move(1, PackedInt32Array([1]), 10500, 4500))  # Due north (-y).
	_runner.run_ticks(1)
	_frames(12)
	assert_float(_part(0, "Hull").rotation).is_equal_approx(NORTH, 0.001)
	assert_float(_part(0, "Turret").rotation).is_equal(_part(0, "Hull").rotation)


func test_with_no_target_the_turret_follows_the_hull_as_drawn_and_not_where_it_will_face() -> void:
	_start([_spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 20, 20)])
	var snap: MatchSnapshot = _runner.snapshot
	snap.target[0] = snap.unit_id[1]  # Aimed at the red tank, 10 tiles south.
	snap.target_row[0] = 1
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN, 0.001)
	snap.target[0] = 0  # No target left, and the hull's last move was a full step down the screen:
	snap.target_row[0] = -1  # the hull is to turn from east to down, the turret is already there.
	snap.prev_pos_x[0] = snap.pos_x[0] - 85  # A full step (data/units/light_tank.tres: 120, and
	snap.prev_pos_y[0] = snap.pos_y[0] - 85  # 85 x 1.414) down the screen, along the diagonal.
	_layer._process(FRAME_SECONDS)
	# The hull has turned 0.6 rad and the turret follows that hull, not its end point, so it swings
	# back by 0.6 rad too, and the two meet only when the hull is there.
	assert_float(_part(0, "Hull").rotation).is_equal_approx(TURN_PER_FRAME, 0.001)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN - TURN_PER_FRAME, 0.001)
	_frames(12)
	assert_float(_part(0, "Hull").rotation).is_equal_approx(DOWN, 0.001)
	assert_float(_part(0, "Turret").rotation).is_equal(_part(0, "Hull").rotation)


func test_a_turret_keeps_its_angle_when_a_unit_before_it_dies() -> void:
	var far: SpawnDef = _spawn(1, "light_tank", 3, 3)
	_start([far, _spawn(1, "light_tank", 10, 10), _spawn(2, "light_tank", 12, 12)])
	_run_until_target(1)
	_run_until_target(2)
	_frames(12)
	assert_float(_part(1, "Turret").rotation).is_equal_approx(DOWN, 0.001)
	assert_float(_part(2, "Turret").rotation).is_equal_approx(-DOWN, 0.001)
	_runner.world.hp[0] = 0  # The tank at row 0 dies: the aimed tank becomes row 0.
	_runner.run_ticks(1)
	assert_int(_runner.snapshot.unit_count()).is_equal(2)
	_layer._process(0.0)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN, 0.001)
	assert_float(_part(1, "Turret").rotation).is_equal_approx(-DOWN, 0.001)


func test_an_armed_neutral_tank_aims_at_a_player_tank_that_does_not_aim_back() -> void:
	# Plan design note: an armed unit of owner 0 acquires every player's units, and nothing else
	# turns on whose unit it is. A player's unit does not take a neutral one for an enemy.
	_start([_spawn(0, "light_tank", 10, 10), _spawn(1, "light_tank", 12, 12)])
	_run_until_target(0)
	assert_int(_runner.snapshot.target_row[0]).is_equal(1)
	assert_int(_runner.snapshot.target_row[1]).is_equal(-1)
	_frames(12)
	assert_float(_part(0, "Turret").rotation).is_equal_approx(DOWN, 0.001)
	assert_float(_part(1, "Turret").rotation).is_equal(_part(1, "Hull").rotation)


func test_frames_that_aim_leave_no_new_objects_alive() -> void:
	_start([_spawn(1, "rifle_squad", 10, 10), _spawn(2, "light_tank", 12, 12)])
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


## Stands row `row` at `offset` milli from row `from`, in this tick and the one before.
func _place_next_to(snap: MatchSnapshot, row: int, from: int, offset: Vector2i) -> void:
	for column: PackedInt32Array in [snap.prev_pos_x, snap.pos_x]:
		column[row] = snap.pos_x[from] + offset.x
	for column: PackedInt32Array in [snap.prev_pos_y, snap.pos_y]:
		column[row] = snap.pos_y[from] + offset.y


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
