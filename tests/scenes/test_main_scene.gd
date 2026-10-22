extends GdUnitTestSuite
## The main scene (ROADMAP Phase 1 boxes 1 and 2): a MatchRunner on the controls_test scenario, a
## 48x48 map of 64 px tiles drawn by MapView from the runner's World, 40 unit rigs, an RtsCamera
## driven by a TouchInput (both on data/input_settings.tres), and the Dev button. Composition
## only: the camera and gesture rules are tested in tests/view and tests/input. Fingers enter
## through the touch_events helper, which converts base px to the window px that push_input takes.
##
## Every test starts at a 1280x720 window. The headless window is 64x64 by default, and GUI
## hit-tests silently miss until the window has the base size. Tests that resize the window reset
## it in before_test.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const SETTINGS_PATH: String = "res://data/input_settings.tres"
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
## The landscape screens every screen is tested at: base, 20:9 phone and 4:3 tablet. The portrait
## ones join in P61 (ScreenSizes.ALL).
const TARGET_SIZES: Array[Vector2i] = ScreenSizes.LANDSCAPE
## The lowest camera position at each of them: half the visible size (1280x720, 1600x720, 1280x960).
const LOWEST: Dictionary[Vector2i, Vector2] = {
	ScreenSizes.LANDSCAPE[0]: Vector2(640, 360),
	ScreenSizes.LANDSCAPE[1]: Vector2(800, 360),
	ScreenSizes.LANDSCAPE[2]: Vector2(640, 480),
}
## Bigger than the map, so the camera must stop at its limit.
const OVERSCROLL_PX: float = 5000.0
## The middle of the 48x48 map (3072 px), where the pan and pinch tests begin.
const MAP_CENTRE: Vector2 = Vector2(1536, 1536)
const POSITION_MARGIN_PX: float = 0.5
const TOLERANCE: Vector2 = Vector2(0.01, 0.01)
## Mid-screen at 1280x720, well clear of the Dev button (24..144 px).
const MAP_POINT: Vector2 = Vector2(640, 360)

var _window_size_before: Vector2i
var _pressed_count: int = 0
var _main: Node2D
var _map: MapView
var _camera: RtsCamera
var _touch: TouchInput


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_pressed_count = 0
	get_window().size = BASE_SIZE
	await await_idle_frame()
	var packed: PackedScene = load(MAIN_SCENE)
	_main = auto_free(packed.instantiate())
	add_child(_main)
	await await_idle_frame()
	_map = _main.get_node("MapView")
	_camera = _main.get_node("Camera") as RtsCamera
	_touch = _main.get_node("TouchInput") as TouchInput
	_touch.clock = func() -> int: return 0  # No long-press, however long the test stalls.


func test_map_is_48_by_48_tiles_of_64_px_from_the_scenario() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH)
	assert_that(scenario.map_size_tiles).is_equal(Vector2i(48, 48))
	assert_object(_main.get_node("MatchRunner").scenario).is_same(scenario)
	var runner: MatchRunner = _main.get_node("MatchRunner")
	assert_object(_map.runner).is_same(runner)  # The scene wires the map to the match.
	assert_int(runner.world.map_cols).is_equal(48)
	assert_int(runner.world.map_rows).is_equal(48)
	assert_that(_map.map_rect_px()).is_equal(Rect2i(0, 0, 3072, 3072))
	# One bake of 8 texels per tile, drawn once over the whole map (no grid lines), with the two
	# grass tones of Phase 1 as a checkerboard (the scene sets no colour or tile override).
	assert_int(_map.bake_count()).is_equal(1)
	assert_that(_map.image().get_size()).is_equal(Vector2i(384, 384))
	assert_str(_map.image().get_pixel(3, 3).to_html(false)).is_equal("5e7d4a")
	assert_str(_map.image().get_pixel(8 + 3, 3).to_html(false)).is_equal("6f8f57")
	assert_int(_map.draw_count()).is_equal(1)
	assert_that(_map.drawn_rect()).is_equal(Rect2(0, 0, 3072, 3072))
	assert_that(_map.get_global_transform()).is_equal(Transform2D.IDENTITY)  # Sim px are world px.


func test_camera_limits_equal_the_map_rect() -> void:
	var rect: Rect2i = _map.map_rect_px()
	assert_int(_camera.limit_left).is_equal(rect.position.x)
	assert_int(_camera.limit_top).is_equal(rect.position.y)
	assert_int(_camera.limit_right).is_equal(rect.end.x)
	assert_int(_camera.limit_bottom).is_equal(rect.end.y)


func test_camera_starts_on_the_scenario_camera_tile_and_sees_all_30_tanks_at_every_size() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH)
	assert_that(scenario.camera_start_tile).is_equal(Vector2i(12, 21))
	var layer: UnitLayer = _main.get_node("UnitLayer")
	for size: Vector2i in TARGET_SIZES:
		get_window().size = size
		await await_idle_frame()
		assert_that(_camera.position).is_equal(Vector2(800, 1376))  # The centre of tile (12, 21).
		assert_that(_camera.get_screen_center_position()).is_equal(Vector2(800, 1376))
		for row: int in 30:
			(
				assert_bool(_camera.visible_world_rect().has_point(layer.get_child(row).position))
				. is_true()
			)


func test_30_blue_and_10_red_tanks_stand_on_the_map_under_the_unit_layer() -> void:
	var layer: UnitLayer = _main.get_node("UnitLayer")
	var tints: Array[Color] = []
	for rig: Node2D in layer.get_children():
		tints.append(rig.get_node("Team").modulate)
		assert_bool(Rect2(_map.map_rect_px()).has_point(rig.position)).is_true()
	assert_int(layer.rig_count()).is_equal(40)
	assert_int(tints.count(Color("2F80ED"))).is_equal(30)
	assert_int(tints.count(Color("E5484D"))).is_equal(10)
	assert_object(layer.runner).is_same(_main.get_node("MatchRunner"))
	assert_object(layer.camera).is_same(_camera)
	# The runner ticks before the layer reads it, the map is drawn under the units, the HUD above.
	assert_int(_main.get_node("MatchRunner").get_index()).is_less(layer.get_index())
	assert_int(_map.get_index()).is_less(layer.get_index())
	assert_int(layer.get_index()).is_less(_main.get_node("Hud").get_index())


func test_camera_and_touch_input_are_wired_to_each_other_and_the_shared_settings() -> void:
	var settings: InputSettings = load(SETTINGS_PATH)
	assert_object(_camera).is_not_null()
	assert_object(_touch).is_not_null()
	assert_object(_touch.camera).is_same(_camera)
	assert_object(_camera.settings).is_same(settings)
	assert_object(_touch.settings).is_same(settings)
	assert_object(_main.get_node("Hud")).is_instanceof(CanvasLayer)  # The camera cannot move it.


func test_one_finger_pan_stops_exactly_at_the_map_edge_at_every_target_resolution() -> void:
	for size: Vector2i in TARGET_SIZES:
		get_window().size = size
		await await_idle_frame()
		assert_that(_expected_low()).is_equal(LOWEST[size])
		_camera.centre_on(MAP_CENTRE)
		await _pan(Vector2(100, 40))
		assert_vector(_camera.position).is_equal_approx(Vector2(1436, 1496), TOLERANCE)
		await _pan(Vector2(OVERSCROLL_PX, OVERSCROLL_PX))
		assert_that(_camera.position).is_equal(_expected_low())
		_assert_position_matches_screen_centre()
		await _pan(Vector2(-OVERSCROLL_PX, -OVERSCROLL_PX))
		assert_that(_camera.position).is_equal(_expected_high())
		_assert_position_matches_screen_centre()


func test_a_pinch_zooms_about_the_fingers_and_snaps_to_a_level_at_every_target_resolution() -> void:
	# The snap is a tween on the clock (tests/view covers its timing): make it instant here.
	var instant: InputSettings = _camera.settings.duplicate() as InputSettings
	instant.zoom_snap_ms = 0
	_camera.settings = instant
	_touch.settings = instant
	var vp: Viewport = get_viewport()
	for size: Vector2i in TARGET_SIZES:
		get_window().size = size
		await await_idle_frame()
		_camera.zoom = Vector2.ONE
		_camera.centre_on(MAP_CENTRE)
		var world: Vector2 = _camera.screen_to_world(Vector2(640, 400))
		TouchEvents.press(vp, 0, Vector2(540, 400))
		TouchEvents.press(vp, 1, Vector2(740, 400))  # 200 apart.
		TouchEvents.drag(vp, 0, Vector2(510, 400), Vector2(-30, 0))  # x1.15
		TouchEvents.drag(vp, 1, Vector2(780, 400), Vector2(40, 0))  # x1.174
		assert_float(_camera.zoom.x).is_equal_approx(1.35, 0.001)
		# The world point between the fingers follows their centre, which is now at x 645.
		var under: Vector2 = _camera.screen_to_world(Vector2(645, 400))
		assert_vector(under).is_equal_approx(world, Vector2(0.5, 0.5))
		TouchEvents.release(vp, 1, Vector2(780, 400))
		TouchEvents.release(vp, 0, Vector2(510, 400))
		assert_float(_camera.zoom.x).is_equal_approx(1.5, 0.001)


func test_dev_button_is_pressed_exactly_once_by_a_touch_at_every_target_resolution() -> void:
	var button: Button = _count_dev_button_presses()
	assert_bool(button.visible).is_true()
	var start: Vector2 = _camera.position
	for size: Vector2i in TARGET_SIZES:
		get_window().size = size
		await await_idle_frame()
		_pressed_count = 0
		var centre: Vector2 = button.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, centre)
		TouchEvents.drag(get_viewport(), 0, centre + Vector2(30, 30), Vector2(30, 30))
		await await_idle_frame()
		TouchEvents.release(get_viewport(), 0, centre + Vector2(30, 30))
		await await_idle_frame()
		assert_int(_pressed_count).is_equal(1)
		# A touch that starts on the button stays with it: no pan.
		assert_that(_camera.position).is_equal(start)


func _on_dev_button_pressed() -> void:
	_pressed_count += 1


## Replaces the Dev button's scene change with a counter, so no scene is changed inside a test.
func _count_dev_button_presses() -> Button:
	var button: Button = _main.get_node("Hud/SafeArea/DevButton")
	for connection: Dictionary in button.pressed.get_connections():
		var callable: Callable = connection["callable"]
		button.pressed.disconnect(callable)
	button.pressed.connect(_on_dev_button_pressed)
	return button


## One finger pans the map: press, one drag of `relative` base px, release.
func _pan(relative: Vector2) -> void:
	var vp: Viewport = get_viewport()
	TouchEvents.press(vp, 0, MAP_POINT)
	TouchEvents.drag(vp, 0, MAP_POINT + relative, relative)
	TouchEvents.release(vp, 0, MAP_POINT + relative)
	await await_idle_frame()


func _half_view() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5 / _camera.zoom


## Lowest camera position: the map's top-left corner plus half the view.
func _expected_low() -> Vector2:
	return Vector2(_map.map_rect_px().position) + _half_view()


## Highest camera position: the map's bottom-right corner minus half the view.
func _expected_high() -> Vector2:
	return Vector2(_map.map_rect_px().end) - _half_view()


func _assert_position_matches_screen_centre() -> void:
	var gap: float = _camera.position.distance_to(_camera.get_screen_center_position())
	assert_float(gap).is_less(POSITION_MARGIN_PX)
