extends GdUnitTestSuite
## The rally point by gestures (plan P87, ADR 0019 section 3) through the real TouchInput,
## GestureRecognizer and PlayerController in the main scene at the six screens (ScreenSizes.ALL),
## with a fake clock. With one own barracks or vehicle factory selected a tap on the ground sends
## RALLY for that building and no other Command, the building stays selected and its flag and line
## show; with any other building selected (a Headquarters, a power plant, a refinery, a turret, an
## enemy building seen for its info) the same tap sends nothing and lets go of the selection.
## The scene is `OrdersRig`'s: 32 x 32 tiles, player 1 the local one.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/orders_rig.gd")
const BuildingRig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")

var _window_size_before: Vector2i
var _rig: Rig = Rig.new()
var _flags: RallyLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	_rig = Rig.new()
	var scene: Node2D = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	(scene.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario()
	add_child(scene)
	await await_idle_frame()
	_rig.bind(scene)
	_flags = scene.get_node("RallyLayer")


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_a_ground_tap_with_a_barracks_selected_sends_one_rally_for_it_and_keeps_it_selected(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.tap_building(Rig.BARRACKS)
		assert_array(_rig.sent).override_failure_message(note).is_empty()  # Selecting orders nothing.
		var ground: Vector2 = Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y)
		_rig.tap_world(ground)
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		var command: Command = _rig.sent[0]
		assert_int(command.type).override_failure_message(note).is_equal(Command.Type.RALLY)
		assert_int(command.player_id).is_equal(1)
		assert_int(command.target_id).override_failure_message(note).is_equal(Rig.BARRACKS)
		assert_array(command.unit_ids).is_empty()
		_assert_near(Vector2i(command.target_x, command.target_y), ground, note)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.BARRACKS]
		)
		assert_int(_rig.main.get_node("MarkerLayer").active_count()).is_equal(0)  # Not a move.
		# The feedback: the flag stands at once, and the phone gives its light buzz.
		await _frames()
		assert_array(_flags.last_flags.keys()).override_failure_message(note).is_equal(
			[World.Tab.INFANTRY]
		)
		assert_array(_rig.buzzes).override_failure_message(note).is_equal(
			[_rig.controller.settings.haptic_ms]
		)


func test_a_ground_tap_with_a_vehicle_factory_selected_sends_one_rally_for_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.tap_building(Rig.FACTORY)
		_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		assert_int(_rig.sent[0].type).override_failure_message(note).is_equal(Command.Type.RALLY)
		assert_int(_rig.sent[0].target_id).override_failure_message(note).is_equal(Rig.FACTORY)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.FACTORY]
		)


func test_each_tap_sends_a_new_rally_and_the_selection_stays_on_the_building() -> void:
	await _show(ScreenSizes.LANDSCAPE[1])
	_rig.tap_building(Rig.BARRACKS)
	_rig.tap_world(Rig.tile_px(22, 10))
	_rig.tap_world(Rig.tile_px(20, 14))
	assert_array(_rig.sent).has_size(2)
	assert_int(_rig.sent[0].type).is_equal(Command.Type.RALLY)
	assert_int(_rig.sent[1].type).is_equal(Command.Type.RALLY)
	assert_bool(_rig.sent[0].target_x == _rig.sent[1].target_x).is_false()
	assert_array(_rig.controller.selection.selected).is_equal([Rig.BARRACKS])


func test_the_flag_and_its_line_show_at_once_at_the_tapped_point_before_any_tick() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		var ticked: int = _rig.runner.snapshot.tick
		_rig.tap_building(Rig.BARRACKS)
		_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
		await _frames()
		var snap: MatchSnapshot = _rig.runner.snapshot
		assert_int(snap.tick).override_failure_message(note).is_equal(ticked)  # No tick ran.
		assert_int(snap.rally_x[World.TABS + World.Tab.INFANTRY]).is_equal(-1)  # Nothing published.
		assert_bool(_flags.has_pending(World.Tab.INFANTRY)).override_failure_message(note).is_true()
		var flag: Vector2 = IsoProjection.ground_to_px(_rig.sent[0].target_x, _rig.sent[0].target_y)
		assert_array(_flags.last_flags.keys()).override_failure_message(note).is_equal(
			[World.Tab.INFANTRY]
		)
		assert_vector(_flags.last_flags[World.Tab.INFANTRY]).is_equal_approx(
			flag, Vector2.ONE * 0.01
		)
		assert_array(_flags.last_lines).override_failure_message(note).is_equal(
			[World.Tab.INFANTRY]
		)
		assert_vector(_flags.last_line_to).is_equal_approx(flag, Vector2.ONE * 0.01)


func test_a_tap_beyond_the_map_shows_the_flag_where_the_sim_clamps_the_point() -> void:
	await _show(ScreenSizes.LANDSCAPE[1])
	_rig.send_to_the_sim()
	_rig.tap_building(Rig.BARRACKS)
	_rig.camera.centre_on(Vector2.ZERO)  # The north tip: the view overhangs the map above it.
	_rig.tap(get_viewport().get_visible_rect().size * 0.5 - Vector2(0.0, 150.0))
	assert_bool(_rig.sent[0].target_x < 0 and _rig.sent[0].target_y < 0).is_true()  # Off the map.
	await _frames()
	assert_vector(_flags.last_flags[World.Tab.INFANTRY]).is_equal_approx(Vector2.ZERO, Vector2.ONE)
	_rig.runner.run_ticks(2)  # The sim clamps it to the corner: the same place.
	await _frames()
	var infantry: int = World.TABS + World.Tab.INFANTRY
	assert_int(_rig.runner.snapshot.rally_x[infantry]).is_equal(0)
	assert_int(_rig.runner.snapshot.rally_y[infantry]).is_equal(0)
	assert_bool(_flags.has_pending(World.Tab.INFANTRY)).is_false()
	assert_vector(_flags.last_flags[World.Tab.INFANTRY]).is_equal_approx(Vector2.ZERO, Vector2.ONE)


func test_the_pending_flag_gives_way_to_the_snapshots_point_without_moving() -> void:
	await _show(ScreenSizes.PORTRAIT[1])
	_rig.send_to_the_sim()
	_rig.tap_building(Rig.BARRACKS)
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
	await _frames()
	assert_bool(_flags.has_pending(World.Tab.INFANTRY)).is_true()
	var shown: Vector2 = _flags.last_flags[World.Tab.INFANTRY]
	_rig.runner.run_ticks(2)
	await _frames()
	assert_bool(_flags.has_pending(World.Tab.INFANTRY)).is_false()
	assert_vector(_flags.last_flags[World.Tab.INFANTRY]).is_equal_approx(shown, Vector2.ONE * 0.01)


## A RALLY the sim never gets (here the sink only records it, as if it was refused: the building
## died first) leaves the flag for `PENDING_TICKS` published ticks and then takes it away.
func test_a_rally_the_sim_does_not_take_drops_its_flag_after_a_few_ticks() -> void:
	await _show(ScreenSizes.LANDSCAPE[0])
	_rig.tap_building(Rig.BARRACKS)
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
	_rig.runner.run_ticks(RallyLayer.PENDING_TICKS)
	await _frames()
	assert_bool(_flags.has_pending(World.Tab.INFANTRY)).is_true()
	assert_array(_flags.last_flags.keys()).is_equal([World.Tab.INFANTRY])
	_rig.runner.run_ticks(1)
	await _frames()
	assert_bool(_flags.has_pending(World.Tab.INFANTRY)).is_false()
	assert_dict(_flags.last_flags).is_empty()
	assert_array(_flags.last_lines).is_empty()


func test_a_rally_tap_buzzes_once_and_a_let_go_tap_does_not_and_the_setting_is_kept() -> void:
	await _show(ScreenSizes.PORTRAIT[0])
	var ms: int = _rig.controller.settings.haptic_ms
	_rig.tap_building(Rig.BARRACKS)
	assert_array(_rig.buzzes).is_empty()  # Selecting is no order.
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
	assert_array(_rig.buzzes).is_equal([ms])
	_rig.tap_world(Rig.tile_px(20, 14))
	assert_array(_rig.buzzes).is_equal([ms, ms])
	_rig.tap_building(Rig.HQ)
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))  # A let-go: no order, no buzz.
	assert_array(_rig.controller.selection.selected).is_empty()
	assert_array(_rig.buzzes).is_equal([ms, ms])
	var quiet: InputSettings = _rig.controller.settings.duplicate()
	quiet.haptics_enabled = false
	_rig.controller.settings = quiet
	_rig.sent.clear()
	_rig.tap_building(Rig.FACTORY)
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
	assert_int(_rig.sent[0].type).is_equal(Command.Type.RALLY)  # The order goes, silently.
	assert_array(_rig.buzzes).is_equal([ms, ms])


## Enemy units do not count with a building selected (`Picker.pick`), so a tap on one is a tap on
## the ground: a barracks sets its rally point there, any other building lets go (ADR 0019 s. 3).
func test_with_a_building_selected_a_tap_on_an_enemy_unit_is_a_tap_on_the_ground() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		var snap: MatchSnapshot = _rig.runner.snapshot
		var row: int = snap.index_of(Rig.ENEMY_RIFLE)
		var place: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		_rig.tap_building(Rig.BARRACKS)
		_rig.tap_unit(Rig.ENEMY_RIFLE)
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		assert_int(_rig.sent[0].type).override_failure_message(note).is_equal(Command.Type.RALLY)
		assert_int(_rig.sent[0].target_id).is_equal(Rig.BARRACKS)
		_assert_near(Vector2i(_rig.sent[0].target_x, _rig.sent[0].target_y), place, note)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.BARRACKS]
		)
		_rig.sent.clear()
		_rig.tap_building(Rig.HQ)
		_rig.tap_unit(Rig.ENEMY_RIFLE)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_empty()
		assert_array(_rig.sent).override_failure_message(note).is_empty()  # No ATTACK either.


func test_the_team_layer_and_the_line_wear_the_players_colour() -> void:
	await _show(ScreenSizes.LANDSCAPE[0])
	var sort: WorldSort = _rig.main.get_node("WorldSort")
	_rig.tap_building(Rig.BARRACKS)
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
	await _frames()
	assert_that(_flags.last_tint).is_equal(sort.mid_colour(1))
	assert_bool(_flags.last_tint == Color.WHITE).is_false()  # The art's own white is not the colour.
	assert_bool(sort.mid_colour(1) == sort.mid_colour(2)).is_false()  # The players differ.


func test_a_ground_tap_with_any_other_building_selected_lets_go_and_sends_nothing() -> void:
	# The Headquarters produces structures, which are placed: the sim refuses its RALLY, so the tap
	# is a plain let-go, like the power plant's, the refinery's and the turret's.
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		for id: int in [Rig.HQ, Rig.PLANT, Rig.REFINERY, Rig.TURRET]:
			var note: String = "%s building %d" % [size, id]
			_rig.tap_building(id)
			(
				assert_array(_rig.controller.selection.selected)
				. override_failure_message(note)
				. is_equal([id])
			)
			_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
			(
				assert_array(_rig.controller.selection.selected)
				. override_failure_message(note)
				. is_empty()
			)
			assert_array(_rig.sent).override_failure_message(note).is_empty()
			assert_int(_rig.main.get_node("MarkerLayer").active_count()).is_equal(0)


func test_a_ground_tap_with_an_enemy_building_selected_lets_go_and_sends_nothing() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.tap_building(Rig.ENEMY_HQ)
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_equal(
			[Rig.ENEMY_HQ]
		)
		_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
		assert_array(_rig.controller.selection.selected).override_failure_message(note).is_empty()
		assert_array(_rig.sent).override_failure_message(note).is_empty()


func test_a_ground_tap_with_nothing_selected_does_nothing() -> void:
	await _show(ScreenSizes.LANDSCAPE[0])
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
	assert_array(_rig.sent).is_empty()
	assert_array(_rig.controller.selection.selected).is_empty()


func test_units_selected_still_move_on_a_ground_tap_and_a_rally_never_goes_with_them() -> void:
	await _show(ScreenSizes.PORTRAIT[1])
	_rig.controller.selection.set_ids(PackedInt32Array([Rig.TANK, Rig.RIFLE]))
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))
	assert_array(_rig.sent).has_size(1)
	assert_int(_rig.sent[0].type).is_equal(Command.Type.MOVE)
	assert_array(_rig.sent[0].unit_ids).is_equal([Rig.TANK, Rig.RIFLE])


## The whole way through the sim: the tap's RALLY is applied by the next tick, the snapshot then
## holds the point for the barracks' tab only, and the flag stands on it; the line shows while the
## barracks is selected and goes when it is let go, the flag stays. A vehicle factory sets the other
## tab's flag.
func test_the_sim_takes_the_rally_and_the_flag_and_its_line_follow_the_selection() -> void:
	await _show(ScreenSizes.LANDSCAPE[0])
	_rig.send_to_the_sim()
	var infantry: int = World.TABS + World.Tab.INFANTRY  # Player 1's queue of the infantry tab.
	var vehicles: int = World.TABS + World.Tab.VEHICLES
	var ground: Vector2 = Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y)
	assert_int(_rig.runner.snapshot.rally_x[infantry]).is_equal(-1)
	_rig.tap_building(Rig.BARRACKS)
	_rig.tap_world(ground)
	_rig.runner.run_ticks(2)
	var snap: MatchSnapshot = _rig.runner.snapshot
	_assert_near(Vector2i(snap.rally_x[infantry], snap.rally_y[infantry]), ground, "sim")
	assert_int(snap.rally_x[vehicles]).is_equal(-1)  # The other tab has none.
	await _frames()
	assert_array(_flags.last_flags.keys()).is_equal([World.Tab.INFANTRY])
	assert_vector(_flags.last_flags[World.Tab.INFANTRY]).is_equal_approx(
		IsoProjection.ground_to_px(snap.rally_x[infantry], snap.rally_y[infantry]),
		Vector2.ONE * 0.01
	)
	assert_array(_flags.last_lines).is_equal([World.Tab.INFANTRY])
	# Another producer: its line is its own tab's, which has no flag yet.
	_rig.tap_building(Rig.FACTORY)
	await _frames()
	assert_array(_flags.last_lines).is_empty()
	_rig.tap_world(Rig.tile_px(20, 14))
	_rig.runner.run_ticks(2)
	await _frames()
	var first: int = _rig.runner.snapshot.rally_x[vehicles]
	assert_bool(first >= 0).is_true()
	assert_array(_flags.last_flags.keys()).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES])
	assert_array(_flags.last_lines).is_equal([World.Tab.VEHICLES])
	_rig.tap_world(Rig.tile_px(14, 18))  # The factory is still selected: the flag moves.
	_rig.runner.run_ticks(2)
	assert_bool(_rig.runner.snapshot.rally_x[vehicles] != first).is_true()
	assert_int(_rig.runner.snapshot.rally_x[infantry]).is_equal(snap.rally_x[infantry])
	_rig.controller.selection.clear()
	await _frames()
	assert_array(_flags.last_flags.keys()).is_equal([World.Tab.INFANTRY, World.Tab.VEHICLES])
	assert_array(_flags.last_lines).is_empty()


func test_the_flag_layer_sits_between_the_ghost_and_the_strike_marks() -> void:
	var ghost: Node2D = _rig.main.get_node("GhostLayer")
	var strike: Node2D = _rig.main.get_node("StrikeMarkerLayer")
	assert_int(_flags.z_index).is_equal(61)
	assert_bool(_flags.z_as_relative).is_false()
	assert_bool(ghost.z_index < _flags.z_index and _flags.z_index < strike.z_index).is_true()


## A size, with the camera back at zoom 1, nothing selected and nothing recorded.
func _show(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	_rig.reset()


## The frames a layer needs to take a change and draw it.
func _frames() -> void:
	await await_idle_frame()
	await await_idle_frame()


## `got` (milli-tiles) is the tapped world point `world` put back on the ground, within 2 milli.
func _assert_near(got: Vector2i, world: Vector2, note: String) -> void:
	var want: Vector2i = IsoProjection.px_to_ground(world)
	assert_int(absi(got.x - want.x)).override_failure_message(note).is_less_equal(2)
	assert_int(absi(got.y - want.y)).override_failure_message(note).is_less_equal(2)
