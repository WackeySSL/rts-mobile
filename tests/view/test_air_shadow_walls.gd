extends GdUnitTestSuite
## Aircraft shadows on wall tops (ADR 0053 section 7, amendment A9, plan P656d5): a shadow whose
## ground point lies in a raised cell is drawn 32 px up at z 19, every other one on the ground at
## z 2. `raised_walls.gd` stands in for `WallLayer` with a crafted raised set.
## Own fighter: unit 3 (row 2), raised cell: tile (10, 8).

const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const RaisedWalls: GDScript = preload("res://tests/view/support/raised_walls.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const FIGHTER_ID: int = Air.FIGHTER_ID
const ROW: int = 2
const WALL_TILE: int = 10

var _runner: MatchRunner
var _layer: AirLayer
var _walls: Object


func before_test() -> void:
	_runner = auto_free(Air.runner())
	_layer = auto_free(Air.layer(self, _runner))
	_layer.life = load("res://data/life_settings.tres").duplicate()
	_layer.life.reduced = true
	_walls = auto_free(RaisedWalls.new())
	_walls.raised[_cell(WALL_TILE, 8)] = true
	_layer.walls = _walls
	_see_all()


func test_over_flat_ground_the_shadow_stays_at_z_2_unmoved() -> void:
	_fly_to(8500, 8500)
	var shadow: Sprite2D = _layer.rig_of(FIGHTER_ID).shadow
	assert_int(shadow.z_index + _layer.z_index).is_equal(WorldSort.Z_SHADOW)
	assert_float(shadow.position.y).is_equal(0.0)


func test_over_a_raised_cell_the_shadow_is_32_px_up_at_z_19() -> void:
	_fly_to(WALL_TILE * 1000 + 500, 8500)
	var rig: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	assert_int(rig.shadow.z_index + _layer.z_index).is_equal(19)
	assert_float(rig.shadow.position.y).is_equal(-32.0)
	assert_float(rig.hull.position.y).is_less(0.0)  # The hull is not the shadow's business.


func test_crossing_the_cells_edge_switches_cleanly_both_ways() -> void:
	var edge: int = WALL_TILE * 1000
	for step: Array in [[edge - 1, false], [edge, true], [edge + 999, true], [edge + 1000, false]]:
		_fly_to(step[0], 8500)
		var shadow: Sprite2D = _layer.rig_of(FIGHTER_ID).shadow
		var up: bool = step[1]
		assert_int(shadow.z_index + _layer.z_index).is_equal(19 if up else 2)
		assert_float(shadow.position.y).is_equal(-32.0 if up else 0.0)


func test_with_no_wall_layer_nothing_changes() -> void:
	_layer.walls = null
	_fly_to(WALL_TILE * 1000 + 500, 8500)
	var shadow: Sprite2D = _layer.rig_of(FIGHTER_ID).shadow
	assert_int(shadow.z_index + _layer.z_index).is_equal(WorldSort.Z_SHADOW)
	assert_float(shadow.position.y).is_equal(0.0)


func test_with_the_flag_off_the_real_layer_lifts_nothing() -> void:
	var real: WallLayer = auto_free(WallLayer.new())
	_layer.walls = real
	_fly_to(WALL_TILE * 1000 + 500, 8500)
	assert_int(_layer.rig_of(FIGHTER_ID).shadow.z_index + _layer.z_index).is_equal(2)


func test_a_pooled_rig_comes_back_on_the_ground() -> void:
	_fly_to(WALL_TILE * 1000 + 500, 8500)
	var rig: AirLayer.Rig = _layer.rig_of(FIGHTER_ID)
	assert_bool(rig.shadow_up).is_true()
	_layer._pool_rig(rig)
	_layer._shadow_to(rig, false)
	assert_int(rig.shadow.z_index + _layer.z_index).is_equal(2)
	assert_float(rig.shadow.position.y).is_equal(0.0)


func _cell(col: int, row: int) -> int:
	return _runner.snapshot.cell_of(col * 1000 + 500, row * 1000 + 500)


func _fly_to(x: int, y: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.pos_x[ROW] = x
	snap.prev_pos_x[ROW] = x
	snap.pos_y[ROW] = y
	snap.prev_pos_y[ROW] = y
	_layer._process(0.0)


func _see_all() -> void:
	var tiles: Array = []
	for y: int in 32:
		for x: int in 32:
			tiles.append(Vector2i(x, y))
	Buildings.see(_runner.snapshot, 1, tiles)
