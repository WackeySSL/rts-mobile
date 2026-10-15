extends GdUnitTestSuite
## UnitLayer turns a hull toward a move only when the move was at least half a full step (plan P40,
## P56d): `4 * moved >= speed * speed` with `moved` the squared length of the move in milli-tiles.
## A shorter move is the step onto a goal, an integer remainder that can point anywhere, so the
## unit keeps its heading. The boundary is pinned from both sides: a move of exactly half a step
## turns the hull (the survivor of P40's mutation run was `>`), and one milli-tile less does not.
## The moves are written into the published snapshot, as test_unit_layer_rows.gd does for the speed
## of a type, so the cases do not depend on how the sim moves a unit: only on what the layer reads.
## On data/scenarios/controls_test.tres tank 30 is row 29. The runner is not in the tree: only the
## calls here move time, and one frame of 0.2 s turns a hull by 12 rad/s * 0.2 s = 2.4 rad, more
## than any turn below, so the heading reaches the aim in that frame.
## A cross-owner edit (tests/view is touch-ux-dev's), named in the P56d pull request.

const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const ROW: int = 29
## A full step of the type, in milli-tiles per tick (data/units/light_tank.tres is 120), written
## into the snapshot so that the numbers below stay right if that file is rebalanced.
const FULL_STEP: int = 120
const FRAME_SECONDS: float = 0.2

var _runner: MatchRunner
var _layer: UnitLayer


func before_test() -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO)
	_runner.start()
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	add_child(_layer)
	_layer.set_process(false)  # Frames come only from _frame().


## 4 * 60 * 60 = 120 * 120: the boundary itself turns the hull, due south.
func test_a_move_of_exactly_half_a_full_step_turns_the_hull() -> void:
	assert_float(_frame(0, 60).rotation).is_equal_approx(PI / 2.0, 0.0001)


## The same half step on a diagonal, 36 and 48 milli-tiles (3, 4, 5 times 12): both axes count.
func test_a_diagonal_half_step_turns_the_hull_toward_it() -> void:
	assert_float(_frame(36, 48).rotation).is_equal_approx(atan2(4.0, 3.0), 0.0001)


## One milli-tile short of half a step (4 * 59 * 59 < 120 * 120): the heading stays east.
func test_a_move_just_under_half_a_full_step_keeps_the_heading() -> void:
	assert_float(_frame(0, 59).rotation).is_equal(0.0)


## The turn follows the move that was made last, so the rule is applied afresh in each tick: a
## half step south turns the hull, and a short move west after it leaves it facing south.
func test_a_short_move_after_a_turn_keeps_the_new_heading() -> void:
	assert_float(_frame(0, 60).rotation).is_equal_approx(PI / 2.0, 0.0001)
	assert_float(_frame(-59, 0).rotation).is_equal_approx(PI / 2.0, 0.0001)
	assert_float(_frame(-60, 0).rotation).is_equal_approx(PI, 0.0001)


## Makes tank 30's last move `(move_x, move_y)` (its position stays, its previous position is
## moved back) with a full step of FULL_STEP, draws one frame of FRAME_SECONDS and returns its Hull.
func _frame(move_x: int, move_y: int) -> Sprite2D:
	var snap: MatchSnapshot = _runner.snapshot
	snap.type_speed[snap.type_index[ROW]] = FULL_STEP  # Test-only: written into the snapshot.
	snap.prev_pos_x[ROW] = snap.pos_x[ROW] - move_x
	snap.prev_pos_y[ROW] = snap.pos_y[ROW] - move_y
	_layer._process(FRAME_SECONDS)
	return _layer.get_child(ROW).get_node("Hull")
