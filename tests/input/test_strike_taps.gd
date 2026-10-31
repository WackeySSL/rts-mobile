extends GdUnitTestSuite
## The map's gestures while the strike is aimed (plan P112), through the real TouchInput,
## GestureRecognizer and PlayerController of the main scene at the six screens (ScreenSizes.ALL),
## with a fake clock. A tap, and the second tap of a double-tap, place the point on the ground under
## the finger (the inverse projection, held inside the map) and move it when the player taps again;
## nothing is selected, ordered or boxed meanwhile: a long-press and drag draws no box and clears no
## selection, a pan and a pinch still move the camera and leave the point on its ground. A confirm
## sends one SUPERWEAPON and the very next ground tap is a MOVE again (the mode is over); a cancel
## sends nothing and the next tap is a MOVE at once.
## Player 1 (local) has a Deep Bore, id 1 (3x3 at tiles 6-8 by 6-8), and a light tank, id 2, at tile
## (14, 14), which is selected; player 2 has a Headquarters, id 3 (tiles 20-22 by 20-22). The bore
## is made ready in the snapshot (its `ready_tick` is 0); the charge itself is test_strike_aim's.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const BORE: int = 1
const TANK: int = 2
const SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6],
	[1, "light_tank", 14, 14],
	[2, "renew_hq", 20, 20],
]
const ONE: Vector2i = Vector2i(16500, 16500)  ## Ground points clear of every row and of the HUD.
const TWO: Vector2i = Vector2i(11500, 20500)

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _aim: StrikeAim
var _now_ms: int = 0
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	(_main.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario(spawns)
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_aim = _main.get_node("StrikeAim")
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_a_tap_places_the_point_under_the_finger_and_a_second_tap_moves_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _aiming(size)
		var note: String = str(size)
		_tap_ground(ONE)
		assert_bool(_aim.has_point).override_failure_message(note).is_true()
		assert_vector(Vector2(_aim.point)).override_failure_message(note).is_equal_approx(
			Vector2(ONE), Vector2.ONE * 2.0
		)
		_tap_ground(TWO)
		assert_vector(Vector2(_aim.point)).override_failure_message(note).is_equal_approx(
			Vector2(TWO), Vector2.ONE * 2.0
		)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([TANK])
		assert_array(_sent).override_failure_message(note).is_empty()  # Placing orders nothing.


func test_a_double_tap_places_the_point_where_the_second_tap_lands() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _aiming(size)
		_tap_ground(ONE, true)
		var note: String = str(size)
		assert_bool(_aim.has_point).override_failure_message(note).is_true()
		assert_vector(Vector2(_aim.point)).override_failure_message(note).is_equal_approx(
			Vector2(ONE), Vector2.ONE * 2.0
		)
		assert_array(_sent).override_failure_message(note).is_empty()


func test_a_tap_beyond_a_corner_of_the_map_is_held_inside_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _aiming(size)
		var far: Vector2i = Vector2i(Rig.MAP) * ViewScale.MILLI_PER_TILE - Vector2i.ONE
		# Each corner, with where a tap 150 px past it lands.
		var beyond: Dictionary[Vector2i, Vector2] = {
			Vector2i.ZERO: Vector2(0.0, -150.0), far: Vector2(0.0, 150.0)
		}
		for corner: Vector2i in beyond:
			var corner_px: Vector2 = IsoProjection.ground_to_px(corner.x, corner.y)
			_camera.centre_on(corner_px)
			_tap(_camera.world_to_screen(corner_px + beyond[corner]))
			var note: String = "%s %s" % [size, corner]
			assert_vector(Vector2(_aim.point)).override_failure_message(note).is_equal_approx(
				Vector2(corner), Vector2.ONE * 2.0
			)


func test_a_long_press_and_drag_draws_no_box_and_clears_nothing_while_aiming() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _aiming(size)
		_tap_ground(ONE)
		var centre: Vector2 = _camera.world_to_screen(IsoProjection.ground_to_px(ONE.x, ONE.y))
		_box(centre, centre + Vector2(120.0, 90.0))  # A box with the tank nowhere in it.
		var note: String = str(size)
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([TANK])
		assert_bool((_main.get_node("Hud/BoxOverlay") as Control).visible).is_false()
		assert_vector(Vector2(_aim.point)).override_failure_message(note).is_equal_approx(
			Vector2(ONE), Vector2.ONE * 2.0
		)
		assert_array(_sent).override_failure_message(note).is_empty()


func test_a_pan_and_a_pinch_still_move_the_camera_and_leave_the_point_on_its_ground() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _aiming(size)
		_tap_ground(ONE)
		var note: String = str(size)
		var from: Vector2 = _camera.world_to_screen(IsoProjection.ground_to_px(ONE.x, ONE.y))
		var before_pan: Vector2 = _camera.position
		TouchEvents.press(get_viewport(), 0, from)
		TouchEvents.drag(get_viewport(), 0, from + Vector2(80.0, 0.0), Vector2(80.0, 0.0))
		TouchEvents.release(get_viewport(), 0, from + Vector2(80.0, 0.0))
		assert_vector(_camera.position).override_failure_message(note).is_not_equal(before_pan)
		TouchEvents.press(get_viewport(), 0, from - Vector2(50.0, 0.0))
		TouchEvents.press(get_viewport(), 1, from + Vector2(50.0, 0.0))
		TouchEvents.drag(get_viewport(), 0, from - Vector2(80.0, 0.0), Vector2(-30.0, 0.0))
		TouchEvents.drag(get_viewport(), 1, from + Vector2(80.0, 0.0), Vector2(30.0, 0.0))
		assert_float(_camera.zoom.x).override_failure_message(note).is_greater(1.0)
		TouchEvents.release(get_viewport(), 1, from + Vector2(80.0, 0.0))
		TouchEvents.release(get_viewport(), 0, from - Vector2(80.0, 0.0))
		assert_vector(Vector2(_aim.point)).override_failure_message(note).is_equal_approx(
			Vector2(ONE), Vector2.ONE * 2.0
		)
		assert_bool(_aim.active).override_failure_message(note).is_true()
		assert_array(_sent).override_failure_message(note).is_empty()


## A confirm sends the one Command and ends the mode, so the very next ground tap is an ordinary
## move of the selected tank; after a cancel the next tap is that move at once.
func test_after_a_confirm_or_a_cancel_the_next_ground_tap_is_a_move_again() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _aiming(size)
		var note: String = str(size)
		_tap_ground(ONE)
		var placed: Vector2i = _aim.point
		assert_bool(_aim.confirm()).override_failure_message(note).is_true()
		assert_array(_sent).override_failure_message(note).has_size(1)
		var fired: Command = _sent[0]
		assert_array([fired.type, fired.target_id, fired.target_x, fired.target_y]).is_equal(
			[Command.Type.SUPERWEAPON, BORE, placed.x, placed.y]
		)
		_tap_ground(TWO)
		assert_array(_sent).override_failure_message(note).has_size(2)
		assert_int((_sent[1] as Command).type).is_equal(Command.Type.MOVE)
		await _aiming(size)
		_tap_ground(ONE)
		_aim.cancel()
		_sent.clear()
		_tap_ground(TWO)
		assert_array(_sent).override_failure_message(note).has_size(1)
		assert_int((_sent[0] as Command).type).is_equal(Command.Type.MOVE)


## A size, the camera back at zoom 1, the tank selected and the bore ready: the aim has begun.
func _aiming(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	_camera.zoom = Vector2.ONE
	_aim.cancel()
	_controller.selection.set_ids(PackedInt32Array([TANK]))
	var snap: MatchSnapshot = _runner.snapshot
	snap.ready_tick[snap.index_of(BORE)] = 0
	_aim.refresh()
	_sent.clear()
	assert_bool(_aim.begin()).override_failure_message(str(size)).is_true()


## Centres the camera on `ground` (milli-tiles) and taps the middle of the screen, which is clear of
## the HUD; `twice` taps again inside the double-tap time first.
func _tap_ground(ground: Vector2i, twice: bool = false) -> void:
	var world: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
	_camera.centre_on(world)
	_tap(_camera.world_to_screen(world), twice)


## A finger down and up at `at` (base px), then a pause past the double-tap time; `twice` taps again
## inside the double-tap time first.
func _tap(at: Vector2, twice: bool = false) -> void:
	for tap_count: int in 2 if twice else 1:
		TouchEvents.press(get_viewport(), 0, at)
		_now_ms += 50
		_touch._process(0.0)
		TouchEvents.release(get_viewport(), 0, at)
		_now_ms += 100 if twice and tap_count == 0 else 1000


## Holds the long-press time at `from`, drags to `to` and lets go.
func _box(from: Vector2, to: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	_now_ms += _touch.settings.long_press_ms
	_touch._process(0.0)  # The frame that sees the hold.
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000
