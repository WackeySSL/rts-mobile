extends GdUnitTestSuite
## The Phase 0 main scene (ROADMAP Phase 0 box 3): a 32x32 test map of 64 px tiles, a camera that
## pans on one-finger drag and never leaves the map, and the Dev button.
##
## The scene runs at 1280x720. The headless window is 64x64 by default, and GUI hit-tests
## silently miss until the window has the base size.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const BASE_SIZE: Vector2i = Vector2i(1280, 720)
## Bigger than the map, so the camera must stop at its limit.
const OVERSCROLL_PX: float = 5000.0
const BACK_PX: float = 1000.0
const POSITION_MARGIN_PX: float = 0.5

var _window_size_before: Vector2i
var _pressed_count: int = 0
var _main: Node2D
var _map: TestMapView
var _camera: Camera2D


func before() -> void:
	_window_size_before = get_window().size
	get_window().size = BASE_SIZE


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_pressed_count = 0
	var packed: PackedScene = load(MAIN_SCENE)
	_main = auto_free(packed.instantiate())
	add_child(_main)
	await await_idle_frame()
	_map = _main.get_node("TestMapView")
	_camera = _main.get_node("Camera")


func test_map_is_32_by_32_tiles_of_64_px() -> void:
	assert_that(_map.size_tiles).is_equal(Vector2i(32, 32))
	assert_int(_map.tile_px).is_equal(64)
	assert_that(_map.map_rect_px()).is_equal(Rect2i(0, 0, 2048, 2048))


func test_camera_limits_equal_the_map_rect_and_start_at_its_centre() -> void:
	var rect: Rect2i = _map.map_rect_px()
	assert_int(_camera.limit_left).is_equal(rect.position.x)
	assert_int(_camera.limit_top).is_equal(rect.position.y)
	assert_int(_camera.limit_right).is_equal(rect.end.x)
	assert_int(_camera.limit_bottom).is_equal(rect.end.y)
	assert_that(_camera.position).is_equal(Vector2(1024, 1024))
	assert_that(_camera.get_screen_center_position()).is_equal(Vector2(1024, 1024))


func test_drag_moves_the_camera_by_minus_relative_over_zoom() -> void:
	var start: Vector2 = _camera.position
	await _drag(Vector2(100, 40))
	assert_that(_camera.position).is_equal(start - Vector2(100, 40) / _camera.zoom)
	_camera.zoom = Vector2(2, 2)
	var zoomed_start: Vector2 = _camera.position
	await _drag(Vector2(-60, 20))
	assert_that(_camera.position).is_equal(zoomed_start - Vector2(-60, 20) / _camera.zoom)


func test_camera_has_no_dead_zone_after_overscrolling() -> void:
	# Toward the top-left limit: relative > 0 moves the camera up and left.
	await _drag(Vector2(OVERSCROLL_PX, OVERSCROLL_PX))
	var at_limit: Vector2 = _camera.get_screen_center_position()
	_assert_position_matches_screen_centre()
	# Back by 1000 px. A camera that kept the overscrolled position would not move the view.
	await _drag(Vector2(-BACK_PX, -BACK_PX))
	var moved_back: Vector2 = _camera.get_screen_center_position()
	assert_float(moved_back.x).is_greater(at_limit.x)
	assert_float(moved_back.y).is_greater(at_limit.y)
	_assert_position_matches_screen_centre()
	# And the same toward the bottom-right limit.
	await _drag(Vector2(-OVERSCROLL_PX, -OVERSCROLL_PX))
	var at_far_limit: Vector2 = _camera.get_screen_center_position()
	_assert_position_matches_screen_centre()
	await _drag(Vector2(BACK_PX, BACK_PX))
	var moved_back_far: Vector2 = _camera.get_screen_center_position()
	assert_float(moved_back_far.x).is_less(at_far_limit.x)
	assert_float(moved_back_far.y).is_less(at_far_limit.y)
	_assert_position_matches_screen_centre()


func test_dev_button_is_pressed_exactly_once_by_a_touch() -> void:
	var button: Button = _main.get_node("Hud/Margin/DevButton")
	assert_bool(button.visible).is_true()
	# Replace the scene change with a counter, so no scene is changed inside the test.
	for connection: Dictionary in button.pressed.get_connections():
		var callable: Callable = connection["callable"]
		button.pressed.disconnect(callable)
	button.pressed.connect(_on_dev_button_pressed)
	var centre: Vector2 = button.get_global_rect().get_center()
	await _touch(centre, true)
	await _touch(centre, false)
	assert_int(_pressed_count).is_equal(1)


func _on_dev_button_pressed() -> void:
	_pressed_count += 1


func _drag(relative: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = 0
	event.position = Vector2(BASE_SIZE) * 0.5
	event.relative = relative
	get_viewport().push_input(event)
	await await_idle_frame()


func _touch(at: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 0
	event.position = at
	event.pressed = pressed
	get_viewport().push_input(event)
	await await_idle_frame()


func _assert_position_matches_screen_centre() -> void:
	var gap: float = _camera.position.distance_to(_camera.get_screen_center_position())
	assert_float(gap).is_less(POSITION_MARGIN_PX)
