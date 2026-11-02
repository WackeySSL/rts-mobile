extends GdUnitTestSuite
## The rally flags (plan P87, ADR 0019 section 3, ADR 0023 section 2) from a published snapshot of a
## hand-built World: a flag on the projected point of each tab whose rally point is set, the local
## player's only; a line from the one selected own barracks or vehicle factory to its tab's flag and
## from no other building; a frame drawn when the tick, the selection or the zoom changes and none
## otherwise. The drawing is the engine's, so the suite reads what the layer recorded
## (`last_flags`, `last_lines`) and how often it drew (`draws`). The World is 24 x 16 open tiles,
## player 1 the local one: its Headquarters id 1 (3x3 at (2, 2)), barracks id 2 (2x2 at (7, 2)),
## vehicle factory id 3 (3x3 at (11, 2)); player 2's barracks id 4 (2x2 at (18, 10)).

const Rig: GDScript = preload("res://tests/input/support/strike_rig.gd")
const IDS: Array[String] = ["headquarters", "barracks", "vehicle_factory"]
const HQ: int = 1
const BARRACKS: int = 2
const FACTORY: int = 3
const ENEMY_BARRACKS: int = 4

var _world: World
var _runner: MatchRunner
var _layer: RallyLayer


func before_test() -> void:
	_world = Rig.Worlds.open(Rig.COLS, Rig.ROWS, IDS)
	_world.add_building(1, Rig.type_of(_world, "headquarters"), 2, 2)
	_world.add_building(1, Rig.type_of(_world, "barracks"), 7, 2)
	_world.add_building(1, Rig.type_of(_world, "vehicle_factory"), 11, 2)
	_world.add_building(2, Rig.type_of(_world, "barracks"), 18, 10)
	_runner = auto_free(Rig.runner(Rig.snapshot(_world)))
	_layer = auto_free(RallyLayer.new())
	_layer.runner = _runner
	add_child(_layer)


func test_the_layer_draws_at_z_61_in_the_scene_order_of_the_ground_marks() -> void:
	assert_int(_layer.z_index).is_equal(RallyLayer.Z_RALLY)
	assert_int(RallyLayer.Z_RALLY).is_equal(61)
	assert_bool(_layer.z_as_relative).is_false()


func test_a_flag_stands_on_the_projected_point_of_each_tab_that_has_one() -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	_rally(1, World.Tab.VEHICLES, 6500, 11500)
	await _draw()
	assert_array(_layer.last_flags.keys()).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES])
	assert_vector(_layer.last_flags[World.Tab.INFANTRY]).is_equal_approx(
		IsoProjection.ground_to_px(12500, 8500), Vector2.ONE * 0.01
	)
	assert_vector(_layer.last_flags[World.Tab.VEHICLES]).is_equal_approx(
		IsoProjection.ground_to_px(6500, 11500), Vector2.ONE * 0.01
	)


func test_no_rally_point_no_flag_and_the_structures_tab_never_has_one() -> void:
	await _draw()
	assert_int(_layer.draws).is_greater(0)
	assert_dict(_layer.last_flags).is_empty()
	_rally(1, World.Tab.STRUCTURES, 4000, 4000)  # Nothing in the sim can set it.
	await _draw()
	assert_dict(_layer.last_flags).is_empty()


func test_only_the_local_players_flags_are_drawn() -> void:
	_rally(2, World.Tab.INFANTRY, 9000, 9000)
	await _draw()
	assert_dict(_layer.last_flags).is_empty()
	_rally(1, World.Tab.VEHICLES, 5000, 9000)
	await _draw()
	assert_array(_layer.last_flags.keys()).is_equal([World.Tab.VEHICLES])


func test_the_line_runs_from_the_selected_producer_to_the_flag_of_its_own_tab() -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	_rally(1, World.Tab.VEHICLES, 6500, 11500)
	_layer.set_selected(PackedInt32Array([BARRACKS]))
	await _draw()
	assert_array(_layer.last_lines).is_equal([World.Tab.INFANTRY])
	_layer.set_selected(PackedInt32Array([FACTORY]))
	await _draw()
	assert_array(_layer.last_lines).is_equal([World.Tab.VEHICLES])
	assert_array(_layer.last_flags.keys()).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES])


func test_no_line_for_another_building_an_enemy_one_a_producer_with_no_flag_or_a_mixed_selection(
) -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	for ids: Array in [[HQ], [ENEMY_BARRACKS], [FACTORY], [BARRACKS, FACTORY], []]:
		_layer.set_selected(PackedInt32Array(ids))
		await _draw()
		assert_array(_layer.last_lines).override_failure_message(str(ids)).is_empty()
		assert_array(_layer.last_flags.keys()).is_equal([World.Tab.INFANTRY])  # The flag stays.


func test_a_frame_is_drawn_when_the_tick_the_selection_or_the_zoom_changes_and_not_otherwise(
) -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	await _draw()
	var idle: int = _layer.draws
	await _draw()
	assert_int(_layer.draws).is_equal(idle)
	_world.tick += 1
	_runner.snapshot = Rig.snapshot(_world)
	await _draw()
	assert_int(_layer.draws).is_equal(idle + 1)
	_layer.set_selected(PackedInt32Array([BARRACKS]))
	await _draw()
	assert_int(_layer.draws).is_equal(idle + 2)
	_layer.get_viewport().canvas_transform = Transform2D().scaled(Vector2.ONE * 1.5)
	await _draw()
	assert_int(_layer.draws).is_equal(idle + 3)
	_layer.get_viewport().canvas_transform = Transform2D()


func test_the_point_of_infinity_marks_a_tab_with_no_flag() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	assert_bool(RallyLayer.flag_px(snap, 1, World.Tab.INFANTRY).is_finite()).is_false()
	_rally(1, World.Tab.INFANTRY, 0, 0)  # The map's top corner is a point like any other.
	assert_vector(RallyLayer.flag_px(_runner.snapshot, 1, World.Tab.INFANTRY)).is_equal(
		Vector2.ZERO
	)
	assert_bool(RallyLayer.flag_px(_runner.snapshot, 9, World.Tab.INFANTRY).is_finite()).is_false()


## Sets a rally point of `player`'s `tab` in the World and publishes a new snapshot of it.
func _rally(player: int, tab: int, x: int, y: int) -> void:
	_world.rally_x[player * World.TABS + tab] = x
	_world.rally_y[player * World.TABS + tab] = y
	_world.tick += 1
	_runner.snapshot = Rig.snapshot(_world)


## The frames the layer needs to take a change and draw it.
func _draw() -> void:
	await await_idle_frame()
	await await_idle_frame()
