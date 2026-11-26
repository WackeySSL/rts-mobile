extends GdUnitTestSuite
## `AirLayer.tap_point` and `UnitLayer.tap_point` for a flyer (plan P593b-1, ADR 0048 section 13.3):
## the hull's point a tap picks, without the bob, and INF where the layer shows no rig. Own fighter:
## unit 3, enemy drone: unit 4, own tank: unit 1 (as in test_air_layer.gd).

const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const FIGHTER_ID: int = Air.FIGHTER_ID
const DRONE_ID: int = Air.DRONE_ID
const NEAR: Vector2 = Vector2(0.01, 0.01)

var _runner: MatchRunner
var _air: AirLayer
var _units: UnitLayer
var _camera: RtsCamera


func before_test() -> void:
	_runner = auto_free(Air.runner())
	_air = auto_free(Air.layer(self, _runner))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	add_child(_units)
	_see([Vector2i(8, 8), Vector2i(16, 20)])


func after_test() -> void:
	CommandQueue.clear()


func test_the_point_is_the_pick_fill_point_of_every_flyer_row() -> void:
	var pick: PickSnapshot = PickSnapshot.new()
	_units.fill_pick_snapshot(pick, 24.0)
	_air.fill_pick_snapshot(pick, _camera, 24.0)
	for id: int in [FIGHTER_ID, DRONE_ID]:
		var row: int = _runner.snapshot.index_of(id)
		assert_int(pick.pickable[row]).is_equal(1)
		assert_that(_camera.world_to_screen(_air.tap_point(id))).is_equal_approx(
			pick.screen_pos[row], NEAR
		)


func test_it_is_the_hull_without_the_bob() -> void:
	_air._process(0.3)
	var rig: AirLayer.Rig = _air.rig_of(FIGHTER_ID)
	assert_that(_air.tap_point(FIGHTER_ID)).is_equal_approx(
		rig.global_position - Vector2(0.0, rig.lift), NEAR
	)


func test_the_other_layers_unit_a_fogged_enemy_and_an_unknown_id_are_inf() -> void:
	assert_that(_units.tap_point(FIGHTER_ID)).is_equal(Vector2.INF)
	assert_that(_air.tap_point(1)).is_equal(Vector2.INF)  # A tank is the unit layer's.
	assert_that(_units.tap_point(1)).is_not_equal(Vector2.INF)
	assert_that(_air.tap_point(9999)).is_equal(Vector2.INF)
	_see([Vector2i(8, 8)])  # Not the drone's tile.
	assert_that(_air.tap_point(DRONE_ID)).is_equal(Vector2.INF)
	assert_that(_air.tap_point(FIGHTER_ID)).is_not_equal(Vector2.INF)


func _see(tiles: Array) -> void:
	Buildings.see(_runner.snapshot, 1, tiles)
	_air._process(0.0)
