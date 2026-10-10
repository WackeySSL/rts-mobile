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
## Mid-screen at 1280x720, well clear of the Dev button (24..144 px).
const MAP_POINT: Vector2 = Vector2(640, 360)

var _window_size_before: Vector2i
var _pressed_count: int = 0
var _main: Node2D
var _map: TestMapView
var _camera: Camera2D


## Counts the drags that reached `_unhandled_input`, i.e. that nothing consumed.
class UnhandledDragSpy:
	extends Node
	var drags: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventScreenDrag:
			drags += 1


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
	await _pan(Vector2(100, 40))
	assert_that(_camera.position).is_equal(start - Vector2(100, 40) / _camera.zoom)
	_camera.zoom = Vector2(2, 2)
	var zoomed_start: Vector2 = _camera.position
	await _pan(Vector2(-60, 20))
	assert_that(_camera.position).is_equal(zoomed_start - Vector2(-60, 20) / _camera.zoom)


func test_camera_has_no_dead_zone_after_overscrolling() -> void:
	# Toward the top-left limit: relative > 0 moves the camera up and left.
	await _pan(Vector2(OVERSCROLL_PX, OVERSCROLL_PX))
	var at_limit: Vector2 = _camera.get_screen_center_position()
	_assert_position_matches_screen_centre()
	# Back by 1000 px. A camera that kept the overscrolled position would not move the view.
	await _pan(Vector2(-BACK_PX, -BACK_PX))
	var moved_back: Vector2 = _camera.get_screen_center_position()
	assert_float(moved_back.x).is_greater(at_limit.x)
	assert_float(moved_back.y).is_greater(at_limit.y)
	_assert_position_matches_screen_centre()
	# And the same toward the bottom-right limit.
	await _pan(Vector2(-OVERSCROLL_PX, -OVERSCROLL_PX))
	var at_far_limit: Vector2 = _camera.get_screen_center_position()
	_assert_position_matches_screen_centre()
	await _pan(Vector2(BACK_PX, BACK_PX))
	var moved_back_far: Vector2 = _camera.get_screen_center_position()
	assert_float(moved_back_far.x).is_less(at_far_limit.x)
	assert_float(moved_back_far.y).is_less(at_far_limit.y)
	_assert_position_matches_screen_centre()


func test_pan_that_crosses_the_dev_button_keeps_panning_and_does_not_press_it() -> void:
	var button: Button = _count_dev_button_presses()
	var over_button: Vector2 = button.get_global_rect().get_center()
	var start: Vector2 = _camera.position
	_press(0, Vector2(400, 300))
	# Over the button. The GUI used to take this drag, so the camera froze while the finger
	# was on the button.
	_drag(0, over_button, Vector2(-100, -100))
	await await_idle_frame()
	assert_that(_camera.position).is_equal(start + Vector2(100, 100))
	# Past the button, on the margin.
	_drag(0, Vector2(10, 10), Vector2(-50, -50))
	_release(0, over_button)
	await await_idle_frame()
	assert_that(_camera.position).is_equal(start + Vector2(150, 150))
	assert_int(_pressed_count).is_equal(0)


func test_drag_that_starts_on_the_dev_button_does_not_pan() -> void:
	var button: Button = _count_dev_button_presses()
	var over_button: Vector2 = button.get_global_rect().get_center()
	var start: Vector2 = _camera.position
	_press(0, over_button)
	_drag(0, MAP_POINT, Vector2(200, 100))
	_release(0, MAP_POINT)
	await await_idle_frame()
	assert_that(_camera.position).is_equal(start)


func test_a_pan_drag_is_consumed_and_a_stray_drag_is_not() -> void:
	# The spy sees only events that nobody handled.
	var spy: UnhandledDragSpy = auto_free(UnhandledDragSpy.new())
	add_child(spy)
	_press(0, MAP_POINT)
	_drag(0, MAP_POINT, Vector2(5, 5))
	assert_int(spy.drags).is_equal(0)
	_release(0, MAP_POINT)
	# A drag whose press the camera never saw is none of its business.
	_drag(3, MAP_POINT, Vector2(5, 5))
	assert_int(spy.drags).is_equal(1)


func test_two_finger_drag_does_not_pan() -> void:
	var start: Vector2 = _camera.position
	_press(0, Vector2(400, 300))
	_press(1, Vector2(800, 400))
	_drag(0, Vector2(410, 310), Vector2(10, 10))
	_drag(1, Vector2(810, 410), Vector2(-10, 20))
	await await_idle_frame()
	assert_that(_camera.position).is_equal(start)
	# Lifting one finger hands the pan back to the other.
	_release(1, Vector2(810, 410))
	_drag(0, Vector2(430, 320), Vector2(20, 10))
	_release(0, Vector2(430, 320))
	await await_idle_frame()
	assert_that(_camera.position).is_equal(start - Vector2(20, 10))


func test_a_finger_lost_with_the_app_focus_does_not_block_the_pan() -> void:
	var start: Vector2 = _camera.position
	# This finger's release never arrives.
	_press(1, Vector2(800, 400))
	_camera.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _pan(Vector2(40, 20))
	assert_that(_camera.position).is_equal(start - Vector2(40, 20))


func test_dev_button_is_pressed_exactly_once_by_a_touch() -> void:
	var button: Button = _count_dev_button_presses()
	assert_bool(button.visible).is_true()
	var centre: Vector2 = button.get_global_rect().get_center()
	_press(0, centre)
	await await_idle_frame()
	_release(0, centre)
	await await_idle_frame()
	assert_int(_pressed_count).is_equal(1)


func _on_dev_button_pressed() -> void:
	_pressed_count += 1


## Replaces the Dev button's scene change with a counter, so no scene is changed inside a test.
func _count_dev_button_presses() -> Button:
	var button: Button = _main.get_node("Hud/Margin/DevButton")
	for connection: Dictionary in button.pressed.get_connections():
		var callable: Callable = connection["callable"]
		button.pressed.disconnect(callable)
	button.pressed.connect(_on_dev_button_pressed)
	return button


## One finger pans the map: press, one drag of `relative`, release.
func _pan(relative: Vector2) -> void:
	_press(0, MAP_POINT)
	_drag(0, MAP_POINT, relative)
	_release(0, MAP_POINT)
	await await_idle_frame()


func _press(index: int, at: Vector2) -> void:
	_push_touch(index, at, true)


func _release(index: int, at: Vector2) -> void:
	_push_touch(index, at, false)


func _push_touch(index: int, at: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	get_viewport().push_input(event)


func _drag(index: int, at: Vector2, relative: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = relative
	get_viewport().push_input(event)


func _assert_position_matches_screen_centre() -> void:
	var gap: float = _camera.position.distance_to(_camera.get_screen_center_position())
	assert_float(gap).is_less(POSITION_MARGIN_PX)
