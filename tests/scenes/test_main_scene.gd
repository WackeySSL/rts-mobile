extends GdUnitTestSuite
## The main scene (ROADMAP Phase 1 boxes 1 and 2, P117): a MatchRunner on the controls_test
## scenario, a 48x48 map drawn by MapView from the runner's World as a diamond of 64 x 32 px tiles
## (ADR 0023 section 1), 40 unit rigs, an RtsCamera driven by a TouchInput (both on
## data/input_settings.tres), and the Dev button. Composition only: the camera and gesture rules are
## tested in tests/view and tests/input. Fingers enter through the touch_events helper, which
## converts base px to the window px that push_input takes.
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
## The screens every screen is tested at: base, 20:9 phone and 4:3 tablet, each held both ways.
const TARGET_SIZES: Array[Vector2i] = ScreenSizes.ALL
## The UiOrientation autoload turns the base size with the window, so a portrait window shows the
## transposed rect: 1280x720, 1600x720 and 1280x960 in landscape; 720x1280, 720x1600 and 960x1280
## in portrait. The camera's centre stops at the map's tips whatever the size (ADR 0023 section 4).
## Bigger than the map, so the camera must stop at its edge.
const OVERSCROLL_PX: float = 5000.0
## The middle of the 48x48 map's diamond, where the pan and pinch tests begin, and the north and
## south tips that a pan down and right, and up and left, ends on.
const MAP_CENTRE: Vector2 = Vector2(0, 768)
const NORTH_TIP: Vector2 = Vector2(0, 0)
const SOUTH_TIP: Vector2 = Vector2(0, 1536)
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


func test_map_is_a_48_by_48_tile_diamond_from_the_scenario() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH)
	assert_that(scenario.map_size_tiles).is_equal(Vector2i(48, 48))
	assert_object(_main.get_node("MatchRunner").scenario).is_same(scenario)
	var runner: MatchRunner = _main.get_node("MatchRunner")
	assert_object(_map.runner).is_same(runner)  # The scene wires the map to the match.
	assert_int(runner.world.map_cols).is_equal(48)
	assert_int(runner.world.map_rows).is_equal(48)
	assert_that(_map.map_rect_px()).is_equal(Rect2i(-1536, 0, 3072, 1536))  # Its bounding rect.
	assert_array(_map.map_diamond_px()).contains_exactly(
		[Vector2(0, 0), Vector2(1536, 768), Vector2(0, 1536), Vector2(-1536, 768)]
	)
	# One bake of 8 texels per tile, drawn once over the whole map (no grid lines), with the two
	# grass tones of Phase 1 as a checkerboard (the scene sets no colour or tile override).
	assert_int(_map.bake_count()).is_equal(1)
	assert_that(_map.image().get_size()).is_equal(Vector2i(384, 384))
	assert_str(_map.image().get_pixel(3, 3).to_html(false)).is_equal("5e7d4a")
	assert_str(_map.image().get_pixel(8 + 3, 3).to_html(false)).is_equal("6f8f57")
	assert_int(_map.draw_count()).is_equal(1)
	assert_that(_map.drawn_rect()).is_equal(Rect2(0, 0, 48, 48))  # Cells, under the cell transform.
	assert_that(_map.drawn_transform()).is_equal(IsoProjection.cell_to_px())
	assert_that(_map.get_global_transform()).is_equal(Transform2D.IDENTITY)  # The node is at 0.


func test_the_camera_clamps_its_centre_into_the_maps_diamond_and_has_no_engine_limit() -> void:
	assert_bool(_camera.limit_enabled).is_false()
	_camera.centre_on(Vector2(-99999, -99999))
	assert_that(_camera.position).is_equal(NORTH_TIP)
	_camera.centre_on(Vector2(99999, 99999))
	assert_that(_camera.position).is_equal(SOUTH_TIP)
	_camera.centre_on(MAP_CENTRE)
	assert_that(_camera.position).is_equal(MAP_CENTRE)


func test_camera_starts_on_the_scenario_camera_tile_and_sees_all_30_tanks_at_every_size() -> void:
	var scenario: ScenarioDef = load(SCENARIO_PATH)
	assert_that(scenario.camera_start_tile).is_equal(Vector2i(12, 21))
	var layer: UnitLayer = _main.get_node("UnitLayer")
	for size: Vector2i in TARGET_SIZES:
		get_window().size = size
		await await_idle_frame()
		_camera.zoom = Vector2.ONE  # A turn rescales the zoom (ADR 0015 section 4); count at zoom 1.
		assert_that(_camera.position).is_equal(Vector2(-288, 544))  # The centre of tile (12, 21).
		assert_that(_camera.get_screen_center_position()).is_equal(Vector2(-288, 544))
		for row: int in 30:
			assert_bool(_camera.visible_world_rect().has_point(layer.rig(row).position)).is_true()


func test_30_blue_and_10_red_tanks_stand_on_the_map_under_the_unit_layer() -> void:
	var layer: UnitLayer = _main.get_node("UnitLayer")
	var atlas: IsoAtlas = (_main.get_node("WorldSort") as WorldSort).atlas
	var hulls: Array[Rect2] = []
	for row: int in layer.rig_count():
		var rig: Node2D = layer.rig(row)
		hulls.append((rig.get_node("Hull") as Sprite2D).region_rect)
		assert_bool(Rect2(_map.map_rect_px()).has_point(rig.position)).is_true()
		var ground: Vector2i = IsoProjection.px_to_ground(rig.position)
		(
			assert_bool(ground.x >= 0 and ground.x < 48000 and ground.y >= 0 and ground.y < 48000)
			. is_true()
		)
	assert_int(layer.rig_count()).is_equal(40)
	# The two owners wear their own triads, which are two frames of the one atlas.
	assert_int(hulls.count(Rect2(atlas.region(&"light_tank", &"hull", 6, 0)))).is_equal(30)
	assert_int(hulls.count(Rect2(atlas.region(&"light_tank", &"hull", 6, 1)))).is_equal(10)
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
		_camera.zoom = Vector2.ONE  # A turn rescales the zoom (ADR 0015 section 4); count at zoom 1.
		_camera.centre_on(MAP_CENTRE)
		await _pan(Vector2(100, 40))
		assert_vector(_camera.position).is_equal_approx(Vector2(-100, 728), TOLERANCE)
		# The finger goes down and right, so the camera goes up and left, out of the diamond past
		# its north edge: the centre stops on the north tip, and the engine draws what it holds.
		await _pan(Vector2(OVERSCROLL_PX, OVERSCROLL_PX))
		assert_vector(_camera.position).is_equal_approx(NORTH_TIP, TOLERANCE)
		_assert_position_matches_screen_centre()
		await _pan(Vector2(-OVERSCROLL_PX, -OVERSCROLL_PX))
		assert_vector(_camera.position).is_equal_approx(SOUTH_TIP, TOLERANCE)
		_assert_position_matches_screen_centre()
		# No dead zone after the overscroll: a pull back moves the centre at once.
		await _pan(Vector2(0, 100))
		assert_vector(_camera.position).is_equal_approx(SOUTH_TIP - Vector2(0, 100), TOLERANCE)


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


func _assert_position_matches_screen_centre() -> void:
	var gap: float = _camera.position.distance_to(_camera.get_screen_center_position())
	assert_float(gap).is_less(POSITION_MARGIN_PX)
