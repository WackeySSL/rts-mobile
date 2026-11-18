extends GdUnitTestSuite
## The Mine order in the main scene at the six sizes of ScreenSizes.ALL (plan P294, ADR 0037
## section 8, `touch-ui-rules`): it shows for minelayers only, at least 48 dp, with its word the
## laid mines over the cap ("n/cap") and dim at the cap; a tap on it, a tap on the ground and the
## check mark send one LAY_MINE; the X, a second tap, a turn of the phone and a selection with no
## minelayer end the aim with nothing sent; the ring's bounding box holds the check mark and the X
## (at least 64 dp, inside the screen, clear of the bar). The last tests are the data check of
## ADR 0036's Board and Unload on the two ground carriers. Rows (player 1 the local one): a Shot
## Truck 1, a second one 2, a rifle squad 3, a Bunk Wagon 4, a Linecar 5, the enemy Headquarters 6.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const LAYER_A: int = 1
const LAYER_B: int = 2
const SQUAD: int = 3
const WAGON: int = 4
const LINECAR: int = 5
const ENEMY_HQ: int = 6
const SPAWNS: Array[Array] = [
	[1, "fossil_shot_truck", 14, 14],
	[1, "fossil_shot_truck", 15, 14],
	[1, "rifle_squad", 14, 18],
	[1, "fossil_bunk_wagon", 10, 20],
	[1, "renew_linecar", 12, 20],
	[2, "renew_hq", 24, 24],
]
const GROUND: Vector2i = Vector2i(20000, 10000)  ## Milli-tiles, a tile no row stands near.

var _window_size_before: Vector2i
var _main: Node2D
var _controller: PlayerController
var _aim: CarryAim
var _bar: CommandBar
var _controls: CarryControls
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func test_mine_shows_for_minelayers_only_and_is_at_least_48_dp() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, SPAWNS)
		var why: String = str(size)
		await _select([LAYER_A])
		var button: Button = _order("mine")
		assert_bool(button.is_visible_in_tree()).override_failure_message(why).is_true()
		var least: Vector2 = button.get_combined_minimum_size()
		(
			assert_float(minf(button.size.x, button.size.y))
			. override_failure_message(why)
			. is_greater_equal(UiScale.dp(48.0) - 0.5)
		)
		assert_float(minf(least.x, least.y)).override_failure_message(why).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		for others: Array in [[SQUAD], [WAGON], [LAYER_A, SQUAD]]:
			await _select(others)
			(
				assert_bool(_order("mine").visible)
				. override_failure_message(why + str(others))
				. is_equal(others.has(LAYER_A))
			)


func test_the_word_is_the_laid_mines_over_the_cap_and_the_button_dims_at_the_cap() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], SPAWNS)
	var snap: MatchSnapshot = _snap()
	assert_int(snap.mine_cap).is_equal(12)
	await _select([LAYER_A])
	var word: Label = _order("mine").get_node("Face/Word")
	assert_str(word.text).is_equal("0/12")
	assert_bool(_order("mine").disabled).is_false()
	_lay(7)
	await _select([])
	await _select([LAYER_A])
	assert_str(word.text).is_equal("7/12")
	assert_bool(_order("mine").disabled).is_false()
	_lay(12)
	await _select([])
	await _select([LAYER_A])
	assert_str(word.text).is_equal("12/12")
	assert_bool(_order("mine").visible).is_true()  # Dim, not hidden.
	assert_bool(_order("mine").disabled).is_true()
	_tap(_order("mine"))
	assert_bool(_aim.is_active()).is_false()
	_lay(11)  # Another player's mines do not count.
	snap.mine_owner[0] = 2
	await _select([])
	await _select([LAYER_A])
	assert_str(word.text).is_equal("10/12")
	assert_bool(_order("mine").disabled).is_false()


func test_mine_then_the_ground_then_the_check_mark_sends_one_lay_mine() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, SPAWNS)
		var why: String = str(size)
		await _select([LAYER_A, LAYER_B, SQUAD])
		_tap(_order("mine"))
		assert_int(_aim.mode).override_failure_message(why).is_equal(CarryAim.Mode.MINE)
		assert_bool(_order("mine").button_pressed).override_failure_message(why).is_true()
		assert_bool(_controls.visible).override_failure_message(why).is_false()  # No point yet.
		var held: bool = _bar.has_slot()
		_tap_ground(GROUND)
		await await_idle_frame()
		assert_bool(_aim.has_point).override_failure_message(why).is_true()
		assert_bool(_bar.has_slot()).override_failure_message(why).is_equal(held)
		assert_int(_aim.blast_milli()).override_failure_message(why).is_greater(0)
		assert_int((_main.get_node("CarryMarkLayer") as CarryMarkLayer).marks()).is_equal(1)
		_check_buttons(why)
		var ring: Rect2 = _controls.anchor()  # The check mark stands beside the ring's box.
		(
			assert_bool(ring.has_point(_ground_on_screen(GROUND)))
			. override_failure_message(why)
			. is_true()
		)
		var confirm: Rect2 = (_controls.get_node("CarryConfirm") as Control).get_global_rect()
		assert_bool(confirm.intersects(ring.grow(-1.0))).override_failure_message(why).is_false()
		_tap(_controls.get_node("CarryConfirm"))
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.LAY_MINE)
		assert_array(Array(_sent[0].unit_ids)).is_equal([LAYER_A, LAYER_B])
		assert_array([_sent[0].target_x, _sent[0].target_y]).is_equal([GROUND.x, GROUND.y])
		assert_bool(_aim.is_active()).override_failure_message(why).is_false()


func test_another_tap_moves_the_point_even_on_an_own_unit() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], SPAWNS)
	await _select([LAYER_A])
	_tap(_order("mine"))
	_tap_ground(GROUND)
	var first: Vector2i = _aim.point
	var own: Vector2 = _screen_of(SQUAD)
	_tap_at(own)
	assert_bool(_aim.point != first).is_true()
	assert_int(_bar.shakes).is_equal(0)
	assert_array(_sent).is_empty()


func test_the_x_the_second_tap_and_a_selection_without_a_minelayer_send_nothing() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], SPAWNS)
	await _select([LAYER_A])
	_tap(_order("mine"))
	_tap_ground(GROUND)
	await await_idle_frame()
	_tap(_controls.get_node("CarryCancel"))
	assert_bool(_aim.is_active()).is_false()
	_tap(_order("mine"))
	_tap(_order("mine"))
	assert_bool(_aim.is_active()).is_false()
	_tap(_order("mine"))
	await _select([SQUAD])
	assert_bool(_aim.is_active()).is_false()
	assert_array(_sent).is_empty()


func test_a_turn_of_the_phone_and_a_placement_that_begins_end_the_aim() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], SPAWNS)
	await _select([LAYER_A])
	_tap(_order("mine"))
	_tap_ground(GROUND)
	get_window().size = ScreenSizes.PORTRAIT[0]
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_aim.is_active()).is_false()
	assert_bool(_aim.has_point).is_false()
	_tap(_order("mine"))
	assert_bool(_aim.is_active()).is_true()
	var placement: PlacementController = _main.get_node("PlacementController")
	assert_bool(placement.begin(_snap().type_index[_snap().index_of(ENEMY_HQ)])).is_true()
	assert_bool(_aim.is_active()).is_false()
	assert_array(_sent).is_empty()


func test_board_and_unload_take_a_ground_carrier() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, SPAWNS)
		var why: String = str(size)
		var snap: MatchSnapshot = _snap()
		for carrier: int in [WAGON, LINECAR]:
			var type: int = snap.type_index[snap.index_of(carrier)]
			var named: String = "%s %s" % [why, snap.type_ids[type]]
			(
				assert_bool(CarryRules.is_carrier_type(snap, type))
				. override_failure_message(named)
				. is_true()
			)
			assert_int(snap.type_move_class[type]).override_failure_message(named).is_not_equal(
				World.MoveClass.AIR
			)
			(
				assert_bool(CarryRules.can_take_squads(snap, snap.index_of(carrier), 1))
				. override_failure_message(named)
				. is_true()
			)
		await _select([SQUAD])
		assert_bool(_order("board").is_visible_in_tree()).override_failure_message(why).is_true()
		_tap(_order("board"))
		_tap_at(_screen_of(WAGON))
		assert_int(_aim.carrier_id).override_failure_message(why).is_equal(WAGON)
		_tap(_controls.get_node("CarryConfirm"))
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.LOAD)
		assert_int(_sent[0].target_id).is_equal(WAGON)
		snap.pass_carrier = PackedInt32Array([WAGON])
		snap.pass_count = 1
		await _select([WAGON])
		assert_bool(_order("unload").is_visible_in_tree()).override_failure_message(why).is_true()
		_sent.clear()
		_tap(_order("unload"))
		_tap_ground(GROUND)
		await await_idle_frame()
		_tap(_controls.get_node("CarryConfirm"))
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.UNLOAD)
		assert_array(Array(_sent[0].unit_ids)).is_equal([WAGON])


## The check mark and the X: at least 64 dp, inside the screen, clear of the bar and of each other.
func _check_buttons(why: String) -> void:
	assert_bool(_controls.visible).override_failure_message(why).is_true()
	var screen: Rect2 = get_viewport().get_visible_rect()
	var parts: Array[Rect2] = []
	for node: String in ["CarryConfirm", "CarryCancel"]:
		var rect: Rect2 = (_controls.get_node(node) as Control).get_global_rect()
		var named: String = "%s %s %s" % [why, node, rect]
		(
			assert_float(minf(rect.size.x, rect.size.y))
			. override_failure_message(named)
			. is_greater_equal(UiScale.dp(64.0) - 0.5)
		)
		assert_bool(screen.encloses(rect)).override_failure_message(named).is_true()
		(
			assert_bool(rect.intersects(_bar.get_global_rect()))
			. override_failure_message(named)
			. is_false()
		)
		parts.append(rect)
	assert_bool(parts[0].intersects(parts[1])).override_failure_message(why).is_false()


func _snap() -> MatchSnapshot:
	return (_main.get_node("MatchRunner") as MatchRunner).snapshot


func _camera() -> RtsCamera:
	return _main.get_node("Camera")


func _order(id: String) -> Button:
	return _bar.order_button(StringName(id))


## Puts `count` mines of player 1 in the published snapshot (the world is not stepped).
func _lay(count: int) -> void:
	var snap: MatchSnapshot = _snap()
	snap.mine_count = count
	snap.mine_owner = PackedInt32Array()
	snap.mine_cell = PackedInt32Array()
	snap.mine_armed_tick = PackedInt32Array()
	for mine: int in count:
		snap.mine_owner.append(1)
		snap.mine_cell.append(mine)
		snap.mine_armed_tick.append(0)


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()
	await await_idle_frame()


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


func _ground_on_screen(ground: Vector2i) -> Vector2:
	_camera().centre_on(IsoProjection.ground_to_px(ground.x, ground.y))
	return _camera().world_to_screen(IsoProjection.ground_to_px(ground.x, ground.y))


func _tap_ground(ground: Vector2i) -> void:
	_tap_at(_ground_on_screen(ground))


func _screen_of(id: int) -> Vector2:
	var snap: MatchSnapshot = _snap()
	var row: int = snap.index_of(id)
	_camera().centre_on(IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row]))
	var pick: PickSnapshot = PickSnapshot.new()
	_controller.fill_pick(pick)
	return pick.screen_pos[pick.ids.find(id)]


func _tap_at(at: Vector2) -> void:
	var gesture: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	gesture.position = at
	_controller.handle_gesture(gesture)


func _open(size: Vector2i, spawns_in: Array) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in spawns_in:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	(_main.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario(spawns)
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	_controller = _main.get_node("PlayerController")
	_aim = _main.get_node("CarryAim")
	_bar = _main.get_node("Hud").find_child("CommandBar", true, false)
	_controls = _main.get_node("Hud").find_child("CarryControls", true, false)
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	await await_idle_frame()
