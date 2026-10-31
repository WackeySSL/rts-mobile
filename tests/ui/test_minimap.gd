extends GdUnitTestSuite
## The minimap as a control (plan P88, ADR 0019 section 4, ADR 0023 section 4): the map's diamond is
## inscribed in its 2:1 box with the corners at the middles of the box's edges (a square map) or
## at the fractions `rows / (cols + rows)` along the top and bottom edges (any map); a touch on it,
## delivered by the viewport as the engine does, centres the camera on the ground point under the
## finger through the inverse projection, kept inside the map's diamond, and a drag goes on
## jumping; a finger that started on the map never jumps the camera, whatever it crosses; the
## camera's frame is the screen's rectangle through the same scale, and the texture is drawn only
## when the picture or the layout changes, never because the camera moved. Where the minimap sits at
## the six sizes is test_minimap_layout's. The picture's content is test_minimap_image's.
## Cases run the real main scene (controls_test: a 48 x 48 map, 30 blue tanks, the red ones out of
## sight) on the 6-inch phone, paused, with the Commands caught.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const TOLERANCE_PX: float = 0.5
const MAP_TILES: int = 48
const BASES: String = "res://data/scenarios/perf_bases.tres"  ## 54 columns by 24 rows.

var _window_size_before: Vector2i
var _main: Node2D
var _minimap: Minimap
var _camera: RtsCamera
var _runner: MatchRunner
var _controller: PlayerController
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	await _open(null)


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func test_the_diamond_is_inscribed_in_a_2_to_1_box_whatever_the_maps_shape() -> void:
	for scenario: ScenarioDef in [null, load(BASES) as ScenarioDef]:
		await _open(scenario)
		var cols: int = _minimap.picture().cols()
		var rows: int = _minimap.picture().rows()
		var box: Rect2 = _minimap.box_rect()
		var why: String = "%d x %d, box %s" % [cols, rows, box]
		assert_float(box.size.x).override_failure_message(why).is_equal_approx(
			box.size.y * 2.0, 0.001
		)
		assert_bool(Rect2(Vector2.ZERO, _minimap.size).encloses(box)).is_true()
		# The corners of the map, ground (0,0), (cols,0), (cols,rows) and (0,rows): the top corner is
		# `rows / (cols + rows)` of the way along the top edge, the right one `cols / (cols + rows)`
		# down the right edge, the bottom one as far along the bottom, the left one `rows / (cols +
		# rows)` down the left edge.
		var along: float = float(rows) / float(cols + rows)
		var corners: Array[Vector2] = [
			box.position + Vector2(box.size.x * along, 0.0),
			box.position + Vector2(box.size.x, box.size.y * (1.0 - along)),
			box.position + Vector2(box.size.x * (1.0 - along), box.size.y),
			box.position + Vector2(0.0, box.size.y * along),
		]
		var ground: Array[Vector2i] = [
			Vector2i(0, 0), Vector2i(cols, 0), Vector2i(cols, rows), Vector2i(0, rows)
		]
		for at: int in 4:
			var shown: Vector2 = _minimap.world_to_local(
				IsoProjection.ground_to_px(ground[at].x * 1000, ground[at].y * 1000)
			)
			assert_vector(shown).override_failure_message(why).is_equal_approx(
				corners[at], Vector2(0.01, 0.01)
			)


func test_a_tap_centres_the_camera_on_the_ground_point_under_it_through_the_inverse_projection(
) -> void:
	for ground: Vector2i in [
		Vector2i(24000, 24000),
		Vector2i(10500, 30500),
		Vector2i(40000, 5000),
		Vector2i(1000, 1000),
		Vector2i(47000, 47000),
	]:
		var target: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
		_tap(_minimap.world_to_local(target))
		var why: String = "ground %s, wanted %s, camera %s" % [ground, target, _camera.position]
		assert_vector(_camera.position).override_failure_message(why).is_equal_approx(
			target, Vector2(0.1, 0.1)
		)
		assert_vector(_minimap.ground_at(_minimap.world_to_local(target))).is_equal(ground)
	assert_array(_sent).is_empty()


## A touch in a corner of the box, off the diamond, lands on the nearest point of the map: the
## ground point is clamped into the map before the camera centres on it.
func test_a_tap_beside_the_diamond_lands_inside_the_map() -> void:
	var box: Rect2 = _minimap.box_rect()
	var diamond: PackedVector2Array = IsoProjection.map_diamond(MAP_TILES, MAP_TILES)
	for corner: Vector2 in [
		box.position,
		Vector2(box.end.x, box.position.y),
		box.end,
		Vector2(box.position.x, box.end.y)
	]:
		_tap(corner)
		var why: String = "tap at %s, camera %s" % [corner, _camera.position]
		var inside: Vector2 = IsoProjection.clamp_to_diamond(_camera.position, diamond)
		assert_vector(_camera.position).override_failure_message(why).is_equal_approx(
			inside, Vector2(0.01, 0.01)
		)
	# The top left corner of the box is level with the diamond's left corner and lands on the
	# map's west edge at its middle, ground (0, 24000).
	_tap(box.position)
	assert_vector(_camera.position).is_equal_approx(
		IsoProjection.ground_to_px(0, 24000), Vector2(0.1, 0.1)
	)


func test_a_drag_goes_on_jumping_until_the_finger_lifts_and_a_second_finger_does_nothing() -> void:
	var from: Vector2 = _minimap.world_to_local(IsoProjection.ground_to_px(12000, 12000))
	var middle: Vector2 = _minimap.world_to_local(IsoProjection.ground_to_px(30000, 20000))
	var to: Vector2 = _minimap.world_to_local(IsoProjection.ground_to_px(36000, 40000))
	TouchEvents.press(get_viewport(), 0, _global(from))
	assert_vector(_camera.position).is_equal_approx(
		IsoProjection.ground_to_px(12000, 12000), Vector2(0.1, 0.1)
	)
	TouchEvents.drag(get_viewport(), 0, _global(middle), middle - from)
	assert_vector(_camera.position).is_equal_approx(
		IsoProjection.ground_to_px(30000, 20000), Vector2(0.1, 0.1)
	)
	TouchEvents.press(get_viewport(), 1, _global(from))  # A second finger: ignored.
	TouchEvents.release(get_viewport(), 1, _global(from))
	assert_vector(_camera.position).is_equal_approx(
		IsoProjection.ground_to_px(30000, 20000), Vector2(0.1, 0.1)
	)
	TouchEvents.drag(get_viewport(), 0, _global(to), to - middle)
	assert_vector(_camera.position).is_equal_approx(
		IsoProjection.ground_to_px(36000, 40000), Vector2(0.1, 0.1)
	)
	TouchEvents.release(get_viewport(), 0, _global(to))
	var rest: Vector2 = _camera.position
	_tap(from)  # A new finger starts a new jump.
	assert_vector(_camera.position).is_not_equal(rest)
	assert_array(_sent).is_empty()


## A finger that started on the map pans the camera, however far it goes, and a finger that started
## on the minimap is the minimap's: neither is the other's.
func test_a_finger_that_started_on_the_map_never_jumps_the_camera_over_the_minimap() -> void:
	var map_point: Vector2 = Vector2(300.0, 360.0)  # Clear of the panels, the units and the HUD.
	var over: Vector2 = _global(_minimap.box_rect().get_center())
	var before: Vector2 = _camera.position
	var zoom: float = _camera.zoom.x
	TouchEvents.press(get_viewport(), 0, map_point)
	var at: Vector2 = map_point
	for step: int in 8:
		var next: Vector2 = map_point.lerp(over, float(step + 1) / 8.0)
		TouchEvents.drag(get_viewport(), 0, next, next - at)
		at = next
	TouchEvents.release(get_viewport(), 0, over)
	var jump: Vector2 = IsoProjection.ground_to_px(24000, 24000)  # Under the centre of the box.
	var why: String = "camera %s from %s, a jump would be %s" % [_camera.position, before, jump]
	assert_float(_camera.position.distance_to(jump)).override_failure_message(why).is_greater(10.0)
	assert_vector(_camera.position).override_failure_message(why).is_equal_approx(
		before - (over - map_point) / zoom, Vector2(1.5, 1.5)
	)


func test_a_touch_on_the_minimap_orders_and_selects_nothing_with_units_selected() -> void:
	_controller.selection.set_ids(PackedInt32Array([1, 2]))
	_tap(_minimap.box_rect().get_center())
	_tap(_minimap.box_rect().position + Vector2(3.0, 3.0))
	assert_array(_sent).is_empty()
	assert_array(_controller.selection.selected).is_equal([1, 2])


func test_the_frame_is_the_screens_rectangle_through_the_minimaps_scale_at_every_zoom() -> void:
	var settings: InputSettings = _camera.settings
	var view: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = view.x / view.y
	var sizes: Array[float] = []
	for level: float in settings.zoom_levels:
		_camera.zoom = Vector2(level, level)
		_camera.centre_on(Vector2(0.0, 768.0))
		await await_idle_frame()
		var corners: Array[Vector2] = []
		for screen: Vector2 in [Vector2.ZERO, Vector2(view.x, 0.0), view, Vector2(0.0, view.y)]:
			corners.append(_minimap.world_to_local(_camera.screen_to_world(screen)))
		var frame: Rect2 = _minimap.frame_rect()
		var why: String = "zoom %s: frame %s, corners %s" % [level, frame, corners]
		assert_vector(frame.position).override_failure_message(why).is_equal_approx(
			corners[0], Vector2(0.01, 0.01)
		)
		assert_vector(frame.end).override_failure_message(why).is_equal_approx(
			corners[2], Vector2(0.01, 0.01)
		)
		assert_vector(corners[1]).override_failure_message(why).is_equal_approx(
			Vector2(frame.end.x, frame.position.y), Vector2(0.01, 0.01)
		)
		assert_vector(corners[3]).override_failure_message(why).is_equal_approx(
			Vector2(frame.position.x, frame.end.y), Vector2(0.01, 0.01)
		)
		assert_float(frame.size.x / frame.size.y).override_failure_message(why).is_equal_approx(
			ratio, 0.001
		)
		assert_that((_minimap.get_node("Frame") as Control).get("rect")).is_equal(frame)
		sizes.append(frame.size.x)
	# A wider zoom shows more of the map: a larger frame, in the ratio of the zoom levels.
	assert_float(sizes[0] / sizes[2]).is_equal_approx(
		settings.zoom_levels[2] / settings.zoom_levels[0], 0.001
	)


## The frame follows the camera into every corner of the map and never leaves the box, even where
## the view reaches past the map's edge.
func test_the_frame_stays_in_the_box_and_follows_the_camera_to_the_maps_corners() -> void:
	var box: Rect2 = _minimap.box_rect()
	for ground: Vector2i in [
		Vector2i(0, 0), Vector2i(47000, 0), Vector2i(47000, 47000), Vector2i(0, 47000)
	]:
		_camera.centre_on(IsoProjection.ground_to_px(ground.x, ground.y))
		await await_idle_frame()
		var frame: Rect2 = _minimap.frame_rect()
		var why: String = "camera at %s: frame %s, box %s" % [ground, frame, box]
		assert_bool(box.grow(TOLERANCE_PX).encloses(frame)).override_failure_message(why).is_true()
		assert_bool(frame.has_area()).override_failure_message(why).is_true()
		var centre: Vector2 = _minimap.world_to_local(_camera.position)
		(
			assert_bool(frame.grow(TOLERANCE_PX).has_point(centre))
			. override_failure_message(why)
			. is_true()
		)


func test_the_texture_is_drawn_for_a_new_picture_and_never_because_the_camera_moved() -> void:
	await _settle()
	var texture: ImageTexture = _minimap.picture().texture()
	assert_object(texture).is_not_null()
	var paints: int = _minimap.redraw_count()
	var draws: int = _minimap.draw_count()
	var frames: int = _minimap.frame_count()
	assert_int(draws).is_greater(0)
	for frame: int in 20:  # Idle: nothing is drawn again and the frame stays.
		await await_idle_frame()
	assert_int(_minimap.redraw_count()).is_equal(paints)
	assert_int(_minimap.draw_count()).is_equal(draws)
	assert_int(_minimap.frame_count()).is_equal(frames)
	for frame: int in 10:  # A pan: the frame moves every frame, the texture is not drawn again.
		_camera.pan_by_screen(Vector2(30.0, 12.0))
		await await_idle_frame()
	assert_int(_minimap.frame_count()).is_greater_equal(frames + 8)
	assert_int(_minimap.redraw_count()).is_equal(paints)
	assert_int(_minimap.draw_count()).is_equal(draws)
	# A match of 60 ticks: the picture is painted at the fog's cadence, one in three ticks at
	# most, and each paint draws the one texture (the same object throughout) once.
	CommandQueue.submit(Command.move(1, PackedInt32Array(range(1, 31)), 24000, 21500))
	_runner.run_ticks(60)
	await _settle()
	var made: int = _minimap.redraw_count() - paints
	assert_int(made).is_between(10, 20)
	assert_int(_minimap.draw_count() - draws).is_less_equal(made)
	assert_object(_minimap.picture().texture()).is_same(texture)


## A hidden enemy is never in the picture the control draws: at the start the red tanks are out of
## the blue ones' sight, and no texel is player 2's.
func test_no_texel_of_a_hidden_enemy_is_in_the_picture_the_control_draws() -> void:
	await _settle()
	var image: Image = _minimap.picture().image()
	var red: Color = Color(WorldSort.TRIADS[1][0])
	var blue: Color = Color(WorldSort.TRIADS[0][0])
	var reds: int = 0
	var blues: int = 0
	for line: int in image.get_height():
		for col: int in image.get_width():
			var pixel: Color = image.get_pixel(col, line)
			reds += 1 if pixel.r8 == red.r8 and pixel.g8 == red.g8 and pixel.b8 == red.b8 else 0
			blues += 1 if pixel.r8 == blue.r8 and pixel.g8 == blue.g8 and pixel.b8 == blue.b8 else 0
	assert_int(reds).is_equal(0)
	assert_int(blues).is_greater(0)  # The player's own tanks are there.


func _global(local: Vector2) -> Vector2:
	return _minimap.get_global_rect().position + local


## A finger down and up at the minimap's `local` point, through the viewport.
func _tap(local: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, _global(local))
	TouchEvents.release(get_viewport(), 0, _global(local))


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene on the 6-inch phone (the scenario's own when null), paused, with the Commands
## caught.
func _open(scenario: ScenarioDef) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	if scenario != null:
		_runner.scenario = scenario
	_runner.paused = true
	add_child(_main)
	await _settle()
	_minimap = _main.get_node("Hud").find_child("Minimap", true, false)
	_camera = _main.get_node("Camera")
	_controller = _main.get_node("PlayerController")
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
