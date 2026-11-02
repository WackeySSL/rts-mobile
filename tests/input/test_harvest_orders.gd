extends GdUnitTestSuite
## Orders to tankers by gestures (plan P87, ADR 0019 section 3, rev 5: tankers, oil and gas) through
## the real TouchInput, GestureRecognizer and PlayerController in the main scene at the six screens
## (ScreenSizes.ALL), with a fake clock. With tankers alone selected a tap on an oil or gas field,
## or within a fingertip's reach of one (`hit_radius_dp`), sends HARVEST with the selected ids and
## the tapped point, and no MOVE; a tap anywhere else, or with any other unit among the selection,
## moves as before. The field is `OrdersRig`'s: a 2 x 2 block of ore at tiles (16, 16) to (17, 17),
## whose lowest corner is the ground point (18000, 18000) at world px (0, 576).

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/orders_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const FIELD_CELL: Vector2 = Vector2(0.0, 528.0)  ## The middle of tile (16, 16).
const FIELD_BOTTOM: Vector2 = Vector2(0.0, 576.0)  ## The block's lowest corner.
const TANKERS: Array[int] = [Rig.TANKER_A, Rig.TANKER_B]

var _window_size_before: Vector2i
var _rig: Rig = Rig.new()


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


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_a_tap_on_a_field_with_tankers_selected_sends_one_harvest_and_no_move() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_select_tankers()
		for world: Vector2 in [FIELD_CELL, Rig.tile_px(17, 17), Rig.tile_px(16, 17)]:
			_rig.sent.clear()
			_rig.tap_world(world)
			assert_array(_rig.sent).override_failure_message(note).has_size(1)
			var command: Command = _rig.sent[0]
			assert_int(command.type).override_failure_message(note).is_equal(Command.Type.HARVEST)
			assert_int(command.player_id).is_equal(1)
			assert_array(command.unit_ids).override_failure_message(note).is_equal(TANKERS)
			_assert_near(Vector2i(command.target_x, command.target_y), world, note)
			assert_array(_rig.controller.selection.selected).is_equal(TANKERS)  # Ordering keeps them.
		assert_int(_rig.main.get_node("MarkerLayer").active_count()).is_greater(0)  # The chevrons.


func test_a_tap_on_a_field_with_one_tanker_selected_sends_harvest_for_it() -> void:
	await _show(ScreenSizes.PORTRAIT[0])
	_rig.tap_unit(Rig.TANKER_B)
	assert_array(_rig.controller.selection.selected).is_equal([Rig.TANKER_B])
	assert_array(_rig.sent).is_empty()
	_rig.tap_world(FIELD_CELL)
	assert_array(_rig.sent).has_size(1)
	assert_int(_rig.sent[0].type).is_equal(Command.Type.HARVEST)
	assert_array(_rig.sent[0].unit_ids).is_equal([Rig.TANKER_B])


func test_a_tap_on_the_ground_with_tankers_selected_moves_them() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_select_tankers()
		var world: Vector2 = Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y)
		_rig.tap_world(world)
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		assert_int(_rig.sent[0].type).override_failure_message(note).is_equal(Command.Type.MOVE)
		assert_array(_rig.sent[0].unit_ids).override_failure_message(note).is_equal(TANKERS)
		_assert_near(Vector2i(_rig.sent[0].target_x, _rig.sent[0].target_y), world, note)


## The field's reach is a fingertip, 48 dp across like a unit's hit (`hit_radius_dp`, dp so the same
## on every phone): a tap half a radius below the block's lowest corner is on the field, one a
## little past the radius is not.
func test_a_tap_within_a_fingertip_of_the_field_harvests_and_one_past_it_moves() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		var reach: float = UiScale.dp(_rig.controller.settings.hit_radius_dp)  # Zoom 1.
		_select_tankers()
		_rig.tap_world(FIELD_BOTTOM + Vector2(0.0, reach * 0.5))
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		assert_int(_rig.sent[0].type).override_failure_message(note).is_equal(Command.Type.HARVEST)
		_rig.sent.clear()
		_rig.tap_world(FIELD_BOTTOM + Vector2(0.0, reach + 6.0))
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		assert_int(_rig.sent[0].type).override_failure_message(note).is_equal(Command.Type.MOVE)


## The reach is in dp on the screen, so it shrinks in world px as the camera zooms in: a tap 0.85
## of it below the corner is on the field at zoom 1 and past it at zoom 1.5.
func test_the_reach_follows_the_zoom() -> void:
	await _show(ScreenSizes.LANDSCAPE[0])
	var reach: float = UiScale.dp(_rig.controller.settings.hit_radius_dp)
	_rig.camera.zoom = Vector2.ONE * 1.5
	_select_tankers()
	_rig.tap_world(FIELD_BOTTOM + Vector2(0.0, reach / 1.5 * 0.5))
	assert_int(_rig.sent[0].type).is_equal(Command.Type.HARVEST)
	_rig.sent.clear()
	_rig.tap_world(FIELD_BOTTOM + Vector2(0.0, reach * 0.85))
	assert_int(_rig.sent[0].type).is_equal(Command.Type.MOVE)
	_rig.sent.clear()
	_rig.camera.zoom = Vector2.ONE
	_rig.tap_world(FIELD_BOTTOM + Vector2(0.0, reach * 0.85))
	assert_int(_rig.sent[0].type).is_equal(Command.Type.HARVEST)


func test_with_other_units_among_the_selection_a_tap_on_a_field_moves_them_all() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.controller.selection.set_ids(PackedInt32Array([Rig.TANKER_A, Rig.TANK]))
		_rig.tap_world(FIELD_CELL)
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		assert_int(_rig.sent[0].type).override_failure_message(note).is_equal(Command.Type.MOVE)
		assert_array(_rig.sent[0].unit_ids).is_equal([Rig.TANKER_A, Rig.TANK])


func test_combat_units_selected_move_to_a_field_and_do_not_harvest() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var note: String = str(size)
		_rig.controller.selection.set_ids(PackedInt32Array([Rig.TANK, Rig.RIFLE]))
		_rig.tap_world(FIELD_CELL)
		assert_array(_rig.sent).override_failure_message(note).has_size(1)
		assert_int(_rig.sent[0].type).override_failure_message(note).is_equal(Command.Type.MOVE)


## The whole way through the sim: a tanker the player moved away stands idle; the tap on the field
## sends HARVEST, and the next tick has it seeking an ore cell of the field.
@warning_ignore("integer_division")
func test_the_sim_takes_the_harvest_and_the_tanker_seeks_the_field() -> void:
	await _show(ScreenSizes.LANDSCAPE[0])
	_rig.send_to_the_sim()
	_rig.controller.selection.set_ids(PackedInt32Array([Rig.TANKER_A]))
	_rig.tap_world(Rig.tile_px(Rig.GROUND.x, Rig.GROUND.y))  # A MOVE hands it to the player.
	_rig.runner.run_ticks(2)
	var snap: MatchSnapshot = _rig.runner.snapshot
	var row: int = snap.index_of(Rig.TANKER_A)
	assert_int(snap.harvest_mode[row]).is_equal(World.HarvestMode.IDLE)
	_rig.tap_world(FIELD_CELL)
	_rig.runner.run_ticks(2)
	snap = _rig.runner.snapshot
	assert_int(snap.harvest_mode[row]).is_equal(World.HarvestMode.SEEK)
	assert_bool(snap.harvest_slot[row] >= 0).is_true()
	var cell: int = snap.ore_cell[snap.harvest_slot[row]]
	var tile: Vector2i = Vector2i(cell % snap.map_cols, cell / snap.map_cols)
	assert_bool(Rig.FIELD_TILES.has(tile)).override_failure_message(str(tile)).is_true()


## A size, with the camera back at zoom 1, nothing selected and nothing recorded.
func _show(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	_rig.reset()


func _select_tankers() -> void:
	_rig.controller.selection.set_ids(PackedInt32Array(TANKERS))


## `got` (milli-tiles) is the tapped world point `world` put back on the ground, within 2 milli.
func _assert_near(got: Vector2i, world: Vector2, note: String) -> void:
	var want: Vector2i = IsoProjection.px_to_ground(world)
	assert_int(absi(got.x - want.x)).override_failure_message(note).is_less_equal(2)
	assert_int(absi(got.y - want.y)).override_failure_message(note).is_less_equal(2)
