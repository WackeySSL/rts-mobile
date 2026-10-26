extends GdUnitTestSuite
## The defence turret's head and the order of the quads (plan P84, ADR 0022 sections 1 and 2): the
## head turns about the roof's centre (the footprint's centre lifted by the rise) toward its
## target on the frame clock like a unit's turret, redraws the roof list while it turns and not
## otherwise, keeps its angle through a change of rows, and is drawn right after its own roof part,
## the roof parts in ascending south row. On the base match (Rig): player 1's turret is the 1x1
## building at tile (9, 5), row 5; player 2's mirror is at (30, 5), row 16 (id 17).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TURRET_ROW: int = 5
const TARGET_ROW: int = 10  ## An own rifle squad, which a test moves to where it wants a target.
## Radians a head turns in a 0.05 s frame at the layer's default rate of 12 rad/s.
const STEP: float = 0.6

var _runner: MatchRunner
var _buildings: BuildingLayer
var _roofs: BuildingRoofLayer
var _list: Array[Dictionary] = []
var _turret: int = 0  ## The turret's index in the building list.


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_list = Rig.buildings()
	_turret = Rig.find(_list, &"defence_turret", 1)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	add_child(_buildings)
	_buildings.set_process(false)
	_roofs = auto_free(BuildingRoofLayer.new())
	_roofs.buildings = _buildings
	add_child(_roofs)
	_roofs.set_process(false)


func after_test() -> void:
	CommandQueue.clear()


func test_the_head_turns_about_the_roofs_centre_toward_its_target_by_the_shortest_way() -> void:
	_buildings.sync()
	assert_int(_buildings.building_row(_turret)).is_equal(TURRET_ROW)
	# Tile (9, 5) has its centre at (608, 352); the roof's centre is the rise (48 px) above.
	assert_that(_buildings.head_pivot(_turret)).is_equal(Vector2(608.0, 304.0))
	assert_float(_buildings.head_angle(_turret)).is_equal(0.0)
	_target(Vector2i(0, 3000))  # Three tiles south: the bearing is a quarter turn.
	assert_bool(_buildings.turn_heads(0.05)).is_true()
	assert_float(_buildings.head_angle(_turret)).is_equal_approx(STEP, 0.000001)
	assert_bool(_buildings.turn_heads(0.05)).is_true()
	assert_float(_buildings.head_angle(_turret)).is_equal_approx(2.0 * STEP, 0.000001)
	assert_bool(_buildings.turn_heads(0.05)).is_true()  # What is left is under a step: it arrives.
	assert_float(_buildings.head_angle(_turret)).is_equal(PI / 2.0)
	assert_bool(_buildings.turn_heads(0.05)).is_false()  # Arrived: nothing turns.
	_target(Vector2i(3000, 0))  # Back east, which is a quarter turn the other way.
	assert_bool(_buildings.turn_heads(0.05)).is_true()
	assert_float(_buildings.head_angle(_turret)).is_equal_approx(PI / 2.0 - STEP, 0.000001)


func test_a_head_with_no_target_keeps_its_angle_and_so_does_one_that_is_hidden() -> void:
	_buildings.sync()
	_target(Vector2i(0, 3000))
	_buildings.turn_heads(1.0)
	assert_float(_buildings.head_angle(_turret)).is_equal(PI / 2.0)
	_runner.snapshot.target_row[TURRET_ROW] = -1  # The target is gone: the head stays as it is.
	assert_bool(_buildings.turn_heads(1.0)).is_false()
	assert_float(_buildings.head_angle(_turret)).is_equal(PI / 2.0)
	# The enemy turret is in the fog: it has a target and does not turn, so it costs no redraw.
	var enemy: int = Rig.find(_list, &"defence_turret", 2)
	_runner.snapshot.target_row[_buildings.building_row(enemy)] = TARGET_ROW
	assert_bool(_buildings.turn_heads(1.0)).is_false()
	assert_float(_buildings.head_angle(enemy)).is_equal(0.0)


func test_the_roofs_redraw_while_a_head_turns_and_in_no_other_frame() -> void:
	await _frame(0.0)
	await _frame(0.0)
	var draws: int = _roofs.draw_count()
	var base_draws: int = _buildings.draw_count()
	_target(Vector2i(0, 3000))
	for step: int in 3:  # Two steps and the arrival.
		await _frame(0.05)
		assert_int(_roofs.draw_count()).is_equal(draws + step + 1)
	for _step: int in 4:
		await _frame(0.05)
	assert_int(_roofs.draw_count()).is_equal(draws + 3)
	assert_int(_buildings.draw_count()).is_equal(base_draws)  # The base parts never redraw for it.


func test_a_head_keeps_its_angle_when_the_rows_change_and_starts_again_with_a_new_match() -> void:
	_buildings.sync()
	_target(Vector2i(0, 3000))
	_buildings.turn_heads(1.0)
	_runner.world.hp[Rig.OWN_BUILDINGS] = 0  # A harvester dies: the rows change.
	_runner.run_ticks(1)
	var version: int = _buildings.plan_version()
	_buildings.sync()
	assert_int(_buildings.plan_version()).is_greater(version)
	assert_int(_buildings.building_row(_turret)).is_equal(TURRET_ROW)  # Buildings come first.
	assert_float(_buildings.head_angle(_turret)).is_equal(PI / 2.0)
	_runner.start()
	_buildings.sync()
	assert_float(_buildings.head_angle(_turret)).is_equal(0.0)


func test_each_roof_part_is_followed_by_its_own_head_in_ascending_south_row() -> void:
	_buildings.reveal_enemies = true  # Both turrets, so a head is between two roofs twice.
	await _frame(0.0)
	var base: Array[int] = []
	var roofs: Array[int] = []
	for b: int in _buildings.building_count():
		base.append(b * 4 + BuildingLayer.HULL)
		base.append(b * 4 + BuildingLayer.TEAM)
	for b: int in _buildings.roof_order():
		roofs.append(b * 4 + BuildingLayer.HULL)
		roofs.append(b * 4 + BuildingLayer.TEAM)
		if _list[b][&"id"] == &"defence_turret":
			roofs.append(b * 4 + BuildingLayer.TURRET)  # Right after its own roof part.
	assert_array(Array(_buildings.painted(false))).is_equal(base)
	assert_array(Array(_buildings.painted(true))).is_equal(roofs)
	assert_int(_buildings.drawn_quads()).is_equal(base.size())
	assert_int(_roofs.drawn_quads()).is_equal(roofs.size())
	assert_int(roofs.size()).is_equal(base.size() + 2)


## Gives the own turret the target row `TARGET_ROW`, standing `offset` (milli-tiles) from the
## turret's centre, in the published snapshot (allowed in SYNC, ADR 0012 section 3).
func _target(offset: Vector2i) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.target_row[TURRET_ROW] = TARGET_ROW
	snap.pos_x[TARGET_ROW] = snap.pos_x[TURRET_ROW] + offset.x
	snap.pos_y[TARGET_ROW] = snap.pos_y[TURRET_ROW] + offset.y
	snap.prev_pos_x[TARGET_ROW] = snap.pos_x[TARGET_ROW]
	snap.prev_pos_y[TARGET_ROW] = snap.pos_y[TARGET_ROW]


## One frame of the two layers, in the scene's order, then the engine's own, which draws.
func _frame(delta: float) -> void:
	_buildings._process(delta)
	_roofs._process(delta)
	await await_idle_frame()
