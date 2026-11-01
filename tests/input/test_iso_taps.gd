extends GdUnitTestSuite
## Taps, a ground tap, a tap in the void and a box through the 2:1 projection (P117, ADR 0023
## sections 1 and 3) in the main scene at the six screens (ScreenSizes.ALL: 1280x720, 2400x1080 and
## 2048x1536, each held both ways). Fingers are window-px touches pushed into the viewport through
## the real TouchInput, GestureRecognizer and PlayerController, with a fake clock. The camera starts
## on tile (12, 21), world px (-288, 544), at zoom 1; the 30 blue tanks stand in a diamond whose top
## corner is tank 1 (px (-320, 432)), right corner tank 6, left corner tank 25 and bottom corner
## tank 30. What the unit tests of IsoProjection pin (the formulas, the inverse, the clamp) is here
## proved through a finger.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const CAMERA_START: Vector2 = Vector2(-288, 544)
const Lifts: GDScript = preload("res://tests/view/support/lifts.gd")
## The corner tanks: rows 0, 5, 24 and 29 are the ids 1, 6, 25 and 30.
const CORNER_ROWS: Array[int] = [0, 5, 24, 29]
## A ground point past the block's upper right edge, milli (10000, 15000): 128 px right of and
## 144 px above the middle of the view, clear of the units and of the HUD at every size.
const GROUND_FROM_MIDDLE: Vector2 = Vector2(128, -144)
const GROUND_MILLI: Vector2i = Vector2i(10000, 15000)
## The top of the diamond: the world rect that holds exactly the tanks 1, 2, 3, 7, 8 and 13 once it
## is raised by the light tank's pick lift (a box takes the units whose lifted centres it covers).
const TOP_BOX: Rect2 = Rect2(-440, 410, 240, 80)
const TOP_TANKS: Array[int] = [1, 2, 3, 7, 8, 13]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
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
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	_layer = _main.get_node("UnitLayer")
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


## A tap on a tank's rig position selects that tank on the first tap, whichever corner of the
## diamond it stands in and at every size: the nearest centre wins, and the 53 px between two
## neighbours on the screen is more than a tap's slop.
func test_the_first_tap_on_a_corner_tank_selects_it_at_every_size() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		for row: int in CORNER_ROWS:
			_controller.selection.clear()
			_tap(_layer.unit_screen_position(row))
			(
				assert_array(_controller.selection.selected)
				. override_failure_message("%s row %d" % [size, row])
				. is_equal([row + 1])
			)
		assert_array(_sent).is_empty()  # Selecting orders nothing.


## A ground tap sends the inverse projection of the tapped screen point, rounded to milli-tiles: at
## the start framing the point 128 px right of and 144 px above the middle is milli (10000, 15000).
func test_a_ground_tap_sends_the_inverse_projection_of_the_point_at_every_size() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		_controller.selection.set_ids(PackedInt32Array([1]))
		_sent.clear()
		var point: Vector2 = get_viewport().get_visible_rect().size * 0.5 + GROUND_FROM_MIDDLE
		_tap(point)
		assert_array(_sent).override_failure_message(str(size)).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
		assert_int(_sent[0].target_x).override_failure_message(str(size)).is_equal(GROUND_MILLI.x)
		assert_int(_sent[0].target_y).override_failure_message(str(size)).is_equal(GROUND_MILLI.y)
		var again: Vector2i = IsoProjection.px_to_ground(_camera.screen_to_world(point))
		assert_that(again).is_equal(GROUND_MILLI)


## A tap in the empty ground beyond the map's edge (the camera may stand on a tip, with half the
## screen past it) is a MOVE like any other: the Command carries the point under the finger, which
## is off the map, and the sim clamps the target, so the tank drives to the edge and stops.
func test_a_tap_beyond_the_edge_is_a_move_and_the_sim_keeps_the_goal_on_the_map() -> void:
	var seen: Array[Command] = []
	_controller.command_sink = func(command: Command) -> void:
		seen.append(command)
		CommandQueue.submit(command)
	for size: Vector2i in [ScreenSizes.LANDSCAPE[1], ScreenSizes.PORTRAIT[1]]:
		await _show(size)
		_runner.start()
		await await_idle_frame()
		await _show(size)
		_camera.centre_on(Vector2.ZERO)  # The north tip: the view overhangs the map above it.
		_controller.selection.set_ids(PackedInt32Array([1]))
		seen.clear()
		_tap(get_viewport().get_visible_rect().size * 0.5 - Vector2(0, 150))
		assert_array(seen).override_failure_message(str(size)).has_size(1)
		assert_int(seen[0].target_x).is_less(0)  # Off the map, as tapped.
		assert_int(seen[0].target_y).is_less(0)
		_runner.run_ticks(2)
		var world: World = _runner.world
		var row: int = world.index_of(1)
		assert_int(world.goal_x[row]).is_between(0, world.map_w)
		assert_int(world.goal_y[row]).is_between(0, world.map_h)
		assert_int(world.dropped_commands).is_equal(0)
		CommandQueue.clear()


## A long press and a drag draw a box on the screen and select the own units whose projected
## positions are inside it: the top of the diamond holds six tanks, and a box of the same size
## beside the block holds none and clears the selection.
func test_a_long_press_box_selects_the_tanks_it_covers_at_every_size() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		_controller.selection.set_ids(PackedInt32Array([20]))
		var raise: Vector2 = Vector2(0.0, Lifts.pick(&"light_tank"))
		var top_left: Vector2 = _camera.world_to_screen(TOP_BOX.position - raise)
		_box(top_left, _camera.world_to_screen(TOP_BOX.end - raise))
		assert_array(_controller.selection.selected).override_failure_message(str(size)).is_equal(
			TOP_TANKS
		)
		# The same box 560 px to the left of the block holds no tank.
		var shift: Vector2 = Vector2(-560, 0)
		_box(top_left + shift, _camera.world_to_screen(TOP_BOX.end - raise) + shift)
		assert_array(_controller.selection.selected).override_failure_message(str(size)).is_empty()


func test_a_tap_on_the_body_of_the_top_tank_selects_it_on_the_first_tap_at_every_size() -> void:
	# A unit is hit round the middle of its picture (P114b): the first tap on the tank at the top
	# corner, which no unit stands above, selects it on its ground point, on the middle of its
	# picture and on the upper half of its body. Nothing is ordered by selecting.
	var lift: float = Lifts.pick(&"light_tank")
	for size: Vector2i in ScreenSizes.ALL:
		await _show(size)
		var foot: Vector2 = _layer.unit_screen_position(0)
		for offset: float in [0.0, lift, 1.5 * lift]:
			_tap(foot - Vector2(0.0, offset * _camera.zoom.x))
			(
				assert_array(_controller.selection.selected)
				. override_failure_message("%s, %s px above its foot" % [size, offset])
				. is_equal([1])
			)
			_controller.selection.clear()
		assert_array(_sent).is_empty()


## A size, with the camera back on its start at zoom 1 (a turn rescales the zoom, ADR 0015 §4).
func _show(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	_camera.zoom = Vector2.ONE
	_camera.centre_on(CAMERA_START)
	_controller.selection.clear()


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	_touch._process(0.0)
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## Holds the long-press time at `from`, drags to `to` and lets go.
func _box(from: Vector2, to: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	_now_ms += _touch.settings.long_press_ms
	_touch._process(0.0)  # The frame that sees the hold.
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000
