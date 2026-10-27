extends GdUnitTestSuite
## UnitLayer turns a hull toward a move only when the move was at least half a full step (plan P40,
## P56d): `4 * moved >= speed * speed` with `moved` the squared length of the move in milli-tiles.
## A shorter move is the step onto a goal, an integer remainder that can point anywhere, so the
## unit keeps its heading. The boundary is pinned from both sides: a move of exactly half a step
## turns the hull (the survivor of P40's mutation run was `>`), and one milli-tile less does not.
## The moves are written into the published snapshot, as test_unit_layer_rows.gd does for the speed
## of a type, so the cases do not depend on how the sim moves a unit: only on what the layer reads.
## On data/scenarios/controls_test.tres tank 30 is row 29. The runner is not in the tree: only the
## calls here move time, and one frame of 0.3 s turns a hull by 12 rad/s * 0.3 s = 3.6 rad, more
## than any turn below, so the heading reaches the aim in that frame. Headings are grid angles
## (P114): east on the grid is 0 and the frame `d06`, grid south (+y) is a quarter turn, `d10`.
## A cross-owner edit (tests/view is touch-ux-dev's), named in the P56d pull request.

const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const ROW: int = 29
## A full step of the type, in milli-tiles per tick (data/units/light_tank.tres is 120), written
## into the snapshot so that the numbers below stay right if that file is rebalanced.
const FULL_STEP: int = 120
const FRAME_SECONDS: float = 0.3
const SOUTH: float = PI / 2.0  ## A move due south on the grid (0, +y).
const WEST: float = PI  ## One due west (-x, 0).

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
	_frame(0, 60)
	assert_float(_layer.heading(ROW)).is_equal_approx(SOUTH, 0.0001)
	assert_int(Frames.dir(_layer, ROW, &"hull")).is_equal(10)  # d10 faces grid +y.


## The same half step on a diagonal, 36 and 48 milli-tiles (3, 4, 5 times 12): both axes count.
func test_a_diagonal_half_step_turns_the_hull_toward_it() -> void:
	_frame(36, 48)
	assert_float(_layer.heading(ROW)).is_equal_approx(atan2(48.0, 36.0), 0.0001)
	assert_int(Frames.dir(_layer, ROW, &"hull")).is_equal(8)  # 53 degrees: two steps from east.


## One milli-tile short of half a step (4 * 59 * 59 < 120 * 120): the heading stays east.
func test_a_move_just_under_half_a_full_step_keeps_the_heading() -> void:
	_frame(0, 59)
	assert_float(_layer.heading(ROW)).is_equal(0.0)
	assert_int(Frames.dir(_layer, ROW, &"hull")).is_equal(6)


## The turn follows the move that was made last, so the rule is applied afresh in each tick: a
## half step south turns the hull, and a short move west after it leaves it facing south.
func test_a_short_move_after_a_turn_keeps_the_new_heading() -> void:
	_frame(0, 60)
	assert_float(_layer.heading(ROW)).is_equal_approx(SOUTH, 0.0001)
	_frame(-59, 0)
	assert_float(_layer.heading(ROW)).is_equal_approx(SOUTH, 0.0001)
	assert_int(Frames.dir(_layer, ROW, &"hull")).is_equal(10)
	_frame(-60, 0)
	assert_float(_layer.heading(ROW)).is_equal_approx(WEST, 0.0001)
	assert_int(Frames.dir(_layer, ROW, &"hull")).is_equal(14)  # d14 faces grid -x.


## Frame `d06` faces grid +x and every step is 22.5 degrees towards grid +y (a squad's 8 frames are
## the even ones): the table of the plain cases, then every angle on a 64th of a turn.
func test_the_frame_of_an_angle_is_the_nearest_of_16_or_8_steps_from_d06() -> void:
	var sixteen: Dictionary[float, int] = {
		0.0: 6,
		PI / 2.0: 10,
		PI: 14,
		-PI: 14,
		-PI / 2.0: 2,
		PI / 4.0: 8,
		-PI / 4.0: 4,
		3.0: 14,
		-3.0: 14
	}
	for angle: float in sixteen:
		assert_int(UnitLayer.frame_of(angle, 16)).override_failure_message(str(angle)).is_equal(
			sixteen[angle]
		)
	var eight: Dictionary[float, int] = {
		0.0: 6, PI / 4.0: 8, PI / 2.0: 10, 3.0 * PI / 4.0: 12, PI: 14, -PI / 4.0: 4, -PI / 2.0: 2
	}
	for angle: float in eight:
		assert_int(UnitLayer.frame_of(angle, 8)).override_failure_message(str(angle)).is_equal(
			eight[angle]
		)
	for step: int in range(-64, 65):
		var angle: float = step * TAU / 64.0
		assert_int(UnitLayer.frame_of(angle, 16)).is_equal(Frames.of_angle(angle, 16))
		var squad: int = UnitLayer.frame_of(angle, 8)
		assert_int(squad).is_equal(Frames.of_angle(angle, 8))
		assert_int(squad % 2).is_equal(0)  # Only the frames a squad has.


## The layer reads a sheet's counts by part position: the hull is its first part and a turret its
## second, for every unit of both factions.
func test_every_unit_sheet_has_the_hull_first_and_a_turret_second_and_shadow_last() -> void:
	var units: int = 0
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if sheet.footprint > 0:
			continue
		units += 1
		assert_str(sheet.parts[0]).override_failure_message(str(sheet.art_id)).is_equal("hull")
		assert_str(sheet.parts[sheet.parts.size() - 1]).is_equal("shadow")
		if sheet.has_part(&"turret"):
			assert_str(sheet.parts[1]).override_failure_message(str(sheet.art_id)).is_equal(
				"turret"
			)
		for dir: int in sheet.directions(&"hull"):  # The frames the layer picks from.
			assert_int(dir * sheet.counts[0] % 16).is_equal(0)  # A multiple of 16 / counts.
	assert_int(units).is_greater(10)


## Makes tank 30's last move `(move_x, move_y)` (its position stays, its previous position is
## moved back) with a full step of FULL_STEP and draws one frame of FRAME_SECONDS.
func _frame(move_x: int, move_y: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.type_speed[snap.type_index[ROW]] = FULL_STEP  # Test-only: written into the snapshot.
	snap.prev_pos_x[ROW] = snap.pos_x[ROW] - move_x
	snap.prev_pos_y[ROW] = snap.pos_y[ROW] - move_y
	_layer._process(FRAME_SECONDS)
