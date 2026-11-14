extends GdUnitTestSuite
## The Board and Unload orders in the main scene at the six sizes of ScreenSizes.ALL (plan P265,
## ADR 0036 section 12, `touch-ui-rules`): Board shows for squads while the player has a carrier,
## Unload for a loaded one, each at least 48 dp; a carrier's chip shows its seats as pips; a tap on
## Board, a tap on an own carrier and the check mark send one LOAD; a tap on Unload, a tap on the
## ground and the check mark one UNLOAD; the check mark and the X stand beside the aimed point, at
## least 64 dp, inside the screen and clear of the bar. Rows (player 1 the local one): rifle squads
## 1 and 2, a Skyhauler transport 3, a light tank 4, the enemy Headquarters 5.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const SQUAD_A: int = 1
const SQUAD_B: int = 2
const CARRIER: int = 3
const TANK: int = 4
const SPAWNS: Array[Array] = [
	[1, "rifle_squad", 14, 14],
	[1, "rifle_squad", 15, 14],
	[1, "fossil_transport", 10, 20],
	[1, "light_tank", 14, 18],
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


func test_board_shows_for_squads_while_a_carrier_stands_and_unload_for_a_loaded_one() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, SPAWNS)
		var why: String = str(size)
		await _select([SQUAD_A, SQUAD_B])
		assert_bool(_order("board").is_visible_in_tree()).override_failure_message(why).is_true()
		assert_bool(_order("unload").visible).override_failure_message(why).is_false()
		await _select([TANK])
		assert_bool(_order("board").visible).override_failure_message(why).is_false()
		await _select([CARRIER])
		assert_bool(_order("board").visible).override_failure_message(why).is_false()
		assert_bool(_order("unload").visible).override_failure_message(why).is_false()  # Empty.
		_load(CARRIER, 1)
		await _select([])
		await _select([CARRIER])
		assert_bool(_order("unload").is_visible_in_tree()).override_failure_message(why).is_true()
		for id: String in ["board", "unload"]:
			var button: Button = _order(id)
			(
				assert_float(button.get_combined_minimum_size().x)
				. override_failure_message(why)
				. is_greater_equal(UiScale.dp(48.0) - 0.5)
			)
			(
				assert_float(button.get_combined_minimum_size().y)
				. override_failure_message(why)
				. is_greater_equal(UiScale.dp(48.0) - 0.5)
			)


func test_board_stays_hidden_while_the_player_has_no_carrier() -> void:
	await _open(
		ScreenSizes.LANDSCAPE[0],
		SPAWNS.filter(func(e: Array) -> bool: return e[1] != "fossil_transport")
	)
	await _select([SQUAD_A, SQUAD_B])
	assert_bool(_order("board").visible).is_false()


func test_a_loaded_carriers_chip_shows_its_seats_as_pips() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, SPAWNS)
		var why: String = str(size)
		await _select([CARRIER])
		var pips: Control = _bar.find_child("Pips", true, false)
		var seats: int = _snap().type_carry_slots[_snap().type_index[_snap().index_of(CARRIER)]]
		assert_int(seats).override_failure_message(why).is_greater(0)
		assert_bool(pips.visible).override_failure_message(why).is_true()
		assert_array([pips.seats, pips.aboard]).override_failure_message(why).is_equal([seats, 0])
		_load(CARRIER, 2)
		await _select([])
		await _select([CARRIER])
		assert_array([pips.seats, pips.aboard]).override_failure_message(why).is_equal([seats, 2])
		await _select([TANK])
		assert_bool(pips.visible).override_failure_message(why).is_false()


func test_board_then_a_carrier_then_the_check_mark_sends_one_load_and_the_x_none() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, SPAWNS)
		var why: String = str(size)
		await _select([SQUAD_A, SQUAD_B])
		_tap(_order("board"))
		assert_int(_aim.mode).override_failure_message(why).is_equal(CarryAim.Mode.BOARD)
		assert_bool(_order("board").button_pressed).override_failure_message(why).is_true()
		assert_bool(_controls.visible).override_failure_message(why).is_false()  # No ring yet.
		_tap_world(_snap().index_of(TANK))  # A tank: refused, no Command.
		assert_int(_bar.shakes).override_failure_message(why).is_equal(1)
		assert_int(_aim.carrier_id).override_failure_message(why).is_equal(0)
		_tap_world(_snap().index_of(CARRIER))
		await await_idle_frame()
		assert_int(_aim.carrier_id).override_failure_message(why).is_equal(CARRIER)
		_check_buttons(why)
		_tap(_controls.get_node("CarryConfirm"))
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.LOAD)
		assert_int(_sent[0].target_id).is_equal(CARRIER)
		assert_bool(_aim.is_active()).is_false()
		# The X sends nothing.
		_sent.clear()
		_tap(_order("board"))
		_tap_world(_snap().index_of(CARRIER))
		await await_idle_frame()
		_tap(_controls.get_node("CarryCancel"))
		assert_bool(_aim.is_active()).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).is_empty()


func test_unload_then_the_ground_then_the_check_mark_sends_one_unload() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, SPAWNS)
		var why: String = str(size)
		_load(CARRIER, 1)
		await _select([CARRIER])
		_tap(_order("unload"))
		assert_int(_aim.mode).override_failure_message(why).is_equal(CarryAim.Mode.UNLOAD)
		var held: bool = _bar.has_slot()  # The slot is frozen while the aim runs.
		var gesture: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
		_camera().centre_on(IsoProjection.ground_to_px(GROUND.x, GROUND.y))
		gesture.position = _camera().world_to_screen(IsoProjection.ground_to_px(GROUND.x, GROUND.y))
		_controller.handle_gesture(gesture)
		await await_idle_frame()
		assert_bool(_aim.has_point).override_failure_message(why).is_true()
		assert_bool(_bar.has_slot()).override_failure_message(why).is_equal(held)
		_check_buttons(why)
		_tap(_controls.get_node("CarryConfirm"))
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.UNLOAD)
		assert_array(Array(_sent[0].unit_ids)).is_equal([CARRIER])
		assert_bool(_aim.is_active()).is_false()


## The check mark and the X: at least 64 dp, inside the screen, clear of the bar and of each other.
func _check_buttons(why: String) -> void:
	assert_bool(_controls.visible).override_failure_message(why).is_true()
	var screen: Rect2 = get_viewport().get_visible_rect()
	var parts: Array[Rect2] = []
	for node: String in ["CarryConfirm", "CarryCancel"]:
		var rect: Rect2 = (_controls.get_node(node) as Control).get_global_rect()
		var named: String = "%s %s %s" % [why, node, rect]
		assert_float(rect.size.x).override_failure_message(named).is_greater_equal(
			UiScale.dp(64.0) - 0.5
		)
		assert_float(rect.size.y).override_failure_message(named).is_greater_equal(
			UiScale.dp(64.0) - 0.5
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


## Puts `count` squads aboard carrier `id` in the published snapshot (the world is not stepped).
func _load(id: int, count: int) -> void:
	var snap: MatchSnapshot = _snap()
	var carriers: PackedInt32Array = PackedInt32Array()
	for _squad: int in count:
		carriers.append(id)
	snap.pass_carrier = carriers
	snap.pass_count = count


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()
	await await_idle_frame()


func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## A map tap through the controller on the picture of row `row` (its lifted centre).
func _tap_world(row: int) -> void:
	var units: UnitLayer = _main.get_node("UnitLayer")
	var pick: PickSnapshot = PickSnapshot.new()
	var snap: MatchSnapshot = _snap()
	_camera().centre_on(IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row]))
	units.fill_pick_snapshot(pick, UiScale.dp(_controller.settings.hit_radius_dp))
	var gesture: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	gesture.position = pick.screen_pos[row]
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
