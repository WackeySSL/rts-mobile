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
	_assert_line_between(BARRACKS, IsoProjection.ground_to_px(12500, 8500))
	_layer.set_selected(PackedInt32Array([FACTORY]))
	await _draw()
	assert_array(_layer.last_lines).is_equal([World.Tab.VEHICLES])
	_assert_line_between(FACTORY, IsoProjection.ground_to_px(6500, 11500))
	assert_array(_layer.last_flags.keys()).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES])


func test_no_line_for_another_building_an_enemy_one_a_producer_with_no_flag_or_a_mixed_selection(
) -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	for ids: Array in [[HQ], [ENEMY_BARRACKS], [FACTORY], [BARRACKS, FACTORY], []]:
		_layer.set_selected(PackedInt32Array(ids))
		await _draw()
		assert_array(_layer.last_lines).override_failure_message(str(ids)).is_empty()
		assert_array(_layer.last_flags.keys()).is_equal([World.Tab.INFANTRY])  # The flag stays.


func test_a_frame_is_drawn_when_the_local_flags_a_pending_one_the_selection_or_the_zoom_change(
) -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	await _draw()
	var drawn: int = _layer.draws
	await _draw()
	assert_int(_layer.draws).is_equal(drawn)
	# A tick alone, another player's flag and a new snapshot of the same flags redraw nothing.
	_world.tick += 1
	_runner.snapshot = Rig.snapshot(_world)
	await _draw()
	_rally(2, World.Tab.VEHICLES, 3000, 3000)
	await _draw()
	assert_int(_layer.draws).is_equal(drawn)
	_rally(1, World.Tab.VEHICLES, 6500, 11500)  # The local player's own flag.
	await _draw()
	drawn += 1
	assert_int(_layer.draws).is_equal(drawn)
	_layer.set_selected(PackedInt32Array([BARRACKS]))
	await _draw()
	drawn += 1
	assert_int(_layer.draws).is_equal(drawn)
	_layer.set_selected(PackedInt32Array([BARRACKS]))  # The same selection again.
	await _draw()
	assert_int(_layer.draws).is_equal(drawn)
	_layer.show_pending(World.Tab.INFANTRY, 4500, 4500)
	await _draw()
	drawn += 1
	assert_int(_layer.draws).is_equal(drawn)
	_scale_canvas(1.5)
	await _draw()
	drawn += 1
	assert_int(_layer.draws).is_equal(drawn)
	_scale_canvas(1.0)


func test_the_point_of_infinity_marks_a_tab_with_no_flag() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	assert_bool(RallyLayer.flag_px(snap, 1, World.Tab.INFANTRY).is_finite()).is_false()
	_rally(1, World.Tab.INFANTRY, 0, 0)  # The map's top corner is a point like any other.
	assert_vector(RallyLayer.flag_px(_runner.snapshot, 1, World.Tab.INFANTRY)).is_equal(
		Vector2.ZERO
	)
	assert_bool(RallyLayer.flag_px(_runner.snapshot, 9, World.Tab.INFANTRY).is_finite()).is_false()


## The stroke keeps its size in dp through any zoom: the world width times the zoom is the same on
## the screen: 3 dp for the colour pass and 2 dp more for the dark one (STYLE.md).
func test_the_line_keeps_its_width_in_dp_through_the_zoom() -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	_layer.set_selected(PackedInt32Array([BARRACKS]))
	var dp: float = UiScale.base_px_per_dp()
	for zoom: float in [0.75, 1.0, 1.5]:
		_scale_canvas(zoom)
		await _draw()
		var note: String = "zoom %s" % zoom
		assert_float(_layer.last_stroke_px * zoom).override_failure_message(note).is_equal_approx(
			FeedbackStyle.STROKE_DP * dp, 0.001
		)
		assert_float(_layer.last_outline_px * zoom).override_failure_message(note).is_equal_approx(
			(FeedbackStyle.STROKE_DP + FeedbackStyle.OUTLINE_DP) * dp, 0.001
		)
	_scale_canvas(1.0)


func test_a_pending_flag_stands_at_once_at_the_point_clamped_to_the_map() -> void:
	await _draw()
	var snap: MatchSnapshot = _runner.snapshot
	var last_x: int = snap.map_cols * World.MILLI_PER_TILE - 1
	var last_y: int = snap.map_rows * World.MILLI_PER_TILE - 1
	assert_bool(_layer.has_pending(World.Tab.INFANTRY)).is_false()
	_layer.show_pending(World.Tab.INFANTRY, 7500, 6500)
	_layer.show_pending(World.Tab.VEHICLES, -4000, 999999)  # Past the map: where the sim clamps it.
	await _draw()
	assert_bool(_layer.has_pending(World.Tab.INFANTRY)).is_true()
	assert_vector(_layer.last_flags[World.Tab.INFANTRY]).is_equal_approx(
		IsoProjection.ground_to_px(7500, 6500), Vector2.ONE * 0.01
	)
	assert_vector(_layer.last_flags[World.Tab.VEHICLES]).is_equal_approx(
		IsoProjection.ground_to_px(0, last_y), Vector2.ONE * 0.01
	)
	_layer.show_pending(World.Tab.INFANTRY, 999999, -1)
	await _draw()
	assert_vector(_layer.last_flags[World.Tab.INFANTRY]).is_equal_approx(
		IsoProjection.ground_to_px(last_x, 0), Vector2.ONE * 0.01
	)
	assert_int(_world.rally_x[World.TABS + World.Tab.INFANTRY]).is_equal(-1)  # The sim has none.


func test_a_tab_that_has_no_flag_takes_no_pending_one() -> void:
	_layer.show_pending(World.Tab.STRUCTURES, 4000, 4000)
	_layer.show_pending(7, 4000, 4000)
	await _draw()
	assert_dict(_layer.last_flags).is_empty()
	assert_bool(_layer.has_pending(World.Tab.STRUCTURES)).is_false()


func test_the_line_runs_to_a_pending_flag_and_the_snapshot_then_takes_over_without_a_jump() -> void:
	_layer.set_selected(PackedInt32Array([FACTORY]))
	_layer.show_pending(World.Tab.VEHICLES, 6500, 11500)
	await _draw()
	assert_array(_layer.last_lines).is_equal([World.Tab.VEHICLES])
	_assert_line_between(FACTORY, IsoProjection.ground_to_px(6500, 11500))
	_rally(1, World.Tab.VEHICLES, 6500, 11500)  # The sim took the same point.
	await _draw()
	assert_bool(_layer.has_pending(World.Tab.VEHICLES)).is_false()
	_assert_line_between(FACTORY, IsoProjection.ground_to_px(6500, 11500))
	assert_vector(_layer.last_flags[World.Tab.VEHICLES]).is_equal_approx(
		IsoProjection.ground_to_px(6500, 11500), Vector2.ONE * 0.01
	)


## Another point in the snapshot is not the pending one: it waits, up to `PENDING_TICKS` published
## ticks after the tap, and then the snapshot's flag stands again.
func test_a_pending_flag_waits_for_its_point_and_is_dropped_after_a_few_ticks() -> void:
	_rally(1, World.Tab.INFANTRY, 12500, 8500)
	await _draw()
	_layer.show_pending(World.Tab.INFANTRY, 4500, 4500)
	for step: int in RallyLayer.PENDING_TICKS:
		_world.tick += 1
		_runner.snapshot = Rig.snapshot(_world)
		await _draw()
		(
			assert_bool(_layer.has_pending(World.Tab.INFANTRY))
			. override_failure_message(str(step))
			. is_true()
		)
		assert_vector(_layer.last_flags[World.Tab.INFANTRY]).is_equal_approx(
			IsoProjection.ground_to_px(4500, 4500), Vector2.ONE * 0.01
		)
	_world.tick += 1
	_runner.snapshot = Rig.snapshot(_world)
	await _draw()
	assert_bool(_layer.has_pending(World.Tab.INFANTRY)).is_false()
	assert_vector(_layer.last_flags[World.Tab.INFANTRY]).is_equal_approx(
		IsoProjection.ground_to_px(12500, 8500), Vector2.ONE * 0.01
	)


func test_a_pending_flag_stays_while_no_tick_is_published_as_in_a_paused_match() -> void:
	_layer.show_pending(World.Tab.INFANTRY, 4500, 4500)
	for frame: int in 5:
		await _draw()
	assert_bool(_layer.has_pending(World.Tab.INFANTRY)).is_true()
	assert_array(_layer.last_flags.keys()).is_equal([World.Tab.INFANTRY])


func test_a_pending_flag_goes_with_a_new_match_and_with_the_end_of_the_match() -> void:
	_world.tick = 100
	_runner.snapshot = Rig.snapshot(_world)
	_layer.show_pending(World.Tab.INFANTRY, 4500, 4500)
	await _draw()
	assert_bool(_layer.has_pending(World.Tab.INFANTRY)).is_true()
	_world.tick = 2  # A match that began after the tap: its ticks start over.
	_runner.snapshot = Rig.snapshot(_world, 1)
	await _draw()
	assert_bool(_layer.has_pending(World.Tab.INFANTRY)).is_false()
	_layer.show_pending(World.Tab.VEHICLES, 4500, 4500)
	_world.match_end_tick = _world.tick + 1  # The match ended: no order is applied any more.
	_runner.snapshot = Rig.snapshot(_world, 1)
	await _draw()
	assert_bool(_layer.has_pending(World.Tab.VEHICLES)).is_false()
	assert_dict(_layer.last_flags).is_empty()


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


## The line the last frame drew starts at building `id`'s footprint centre and ends at `flag`.
func _assert_line_between(id: int, flag: Vector2) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	assert_vector(_layer.last_line_from).is_equal_approx(
		IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row]), Vector2.ONE * 0.01
	)
	assert_vector(_layer.last_line_to).is_equal_approx(flag, Vector2.ONE * 0.01)


## The camera's zoom, as the layer reads it: the scale of the viewport's canvas transform.
func _scale_canvas(zoom: float) -> void:
	_layer.get_viewport().canvas_transform = Transform2D().scaled(Vector2.ONE * zoom)
