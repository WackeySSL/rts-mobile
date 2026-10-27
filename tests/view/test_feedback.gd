extends GdUnitTestSuite
## Feedback in the main scene (STYLE.md "Feedback markers"): rings, chevrons, target diamond, anchor
## and box, with one fake clock for TouchInput, MarkerLayer and BoxOverlay. Under the 2:1 projection
## (P117) tank 1 stands at world px (-320, 432) and red tank 31 at (768, 720); the camera starts on
## tile (12, 21), px (-288, 544). The expected numbers are STYLE.md's, as literals; a ring is a
## ground ellipse (a 2:1 oval, ADR 0023 section 2) whose horizontal radius is what they measure.
## A mark lies on the ground too (P117b): its points are flattened to half their height, its strokes
## are as wide as before, and the target diamond's corners are 1.3 x the ring's 24.9 px horizontal
## radius, 32.4 px (STYLE.md's 45.8 was 1.3 x the top-down ring).

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
## The six screens of the shared list (ScreenSizes.ALL, entry by entry), each with its profile.
const PROFILES: Array[StringName] = [
	&"desktop",
	&"android_6in",
	&"web_tablet",
	&"desktop_portrait",
	&"android_6in_portrait",
	&"web_tablet_portrait",
]
## No unit near it, past the tank block's upper right edge: milli (10000, 15000), 102 px or more
## from every tank. On screen it is 128 px right of and 144 px above the middle of the view, clear
## of the build sidebar, the selection panel and the army bar at every profile.
const GROUND: Vector2 = Vector2(-160, 400)
const CAMERA_START: Vector2 = Vector2(-288, 544)  ## The centre of tile (12, 21).
const RED_TANK: Vector2 = Vector2(768, 720)  ## Tank 31, on tile (34, 10).
const RING_TEXTURE: String = "res://assets/art/svg/ui/selection_ring.svg"
## The texture's centre-line radius in px, typed again from STYLE.md (not read from UnitLayer, so
## that a wrong UnitLayer.RING_TEX_RADIUS_PX fails; tests/art pins the texture to the same number).
const RING_CENTRE_PX: float = 72.0
const DARK: Color = Color("1C2127")
const AMBER: Color = Color("F5A524")
const RED: Color = Color("E5484D")
const TOL: Vector2 = Vector2(0.01, 0.01)
const CORNERS: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
const FLAT: Vector2 = Vector2(1.0, 0.5)  ## A shape on the ground keeps its width, half its height.
const DIAMOND_PX: float = 32.4

var _window_size_before: Vector2i
var _now_ms: int = 0
var _buzzes: Array[int] = []
var _runner: MatchRunner
var _layer: UnitLayer
var _markers: MoveMarkerLayer
var _box: BoxOverlay
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	var main: Node2D = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(main)
	await await_idle_frame()
	_runner = main.get_node("MatchRunner")
	_runner.paused = true
	_layer = main.get_node("UnitLayer")
	_markers = main.get_node("MarkerLayer")
	_box = main.get_node("Hud/BoxOverlay")
	_camera = main.get_node("Camera")
	_touch = main.get_node("TouchInput")
	_controller = main.get_node("PlayerController")
	_now_ms = 0
	_buzzes.clear()
	var clock: Callable = func() -> int: return _now_ms
	_touch.clock = clock
	_markers.clock = clock
	_box.clock = clock
	_touch.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	_controller.command_sink = func(_command: Command) -> void: pass


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_rings_show_for_exactly_the_selected_ids_and_are_31_5_31_5_and_37_3_px() -> void:
	assert_bool(_controller.selection_changed.is_connected(_layer.set_selected)).is_true()
	UiScale.set_override(UiProfiles.by_name(&"desktop"))  # 1 dp is 1 px.
	_controller.selection.set_ids(PackedInt32Array([3, 7]))  # No frame has run.
	assert_array(_ringed_ids()).is_equal([3, 7])
	var first_ring: Sprite2D = _layer.rig(2).get_node("Ring")  # Sized in the frame of the tap.
	assert_float(first_ring.radius).is_equal_approx(24.8901, 0.001)  # (500 + 50) * 32 * sqrt(2) / 1000
	assert_float(first_ring.unit).is_equal_approx(1.0, 0.0001)
	assert_str(first_ring.texture.resource_path).is_equal(RING_TEXTURE)
	assert_float(UnitLayer.RING_TEX_RADIUS_PX).is_equal(RING_CENTRE_PX)
	assert_float(first_ring.scale.x * RING_CENTRE_PX).is_equal_approx(24.8901, 0.001)
	assert_float(first_ring.scale.y * 2.0).is_equal_approx(first_ring.scale.x, 0.000001)  # 2:1
	var rig_children: Array = _layer.rig(2).get_children()
	var names: Array = rig_children.map(func(n: Node) -> StringName: return n.name)
	assert_array(names).is_equal([&"Shadow", &"Ring", &"Hull", &"Turret"])  # Under the sprites.
	_controller.selection.set_ids(PackedInt32Array([7, 40]))
	assert_array(_ringed_ids()).is_equal([7, 40])
	_layer.set_selected(PackedInt32Array([999, 1]))  # An unknown id is skipped.
	assert_array(_ringed_ids()).is_equal([1])
	await _use(&"android_6in")  # 1 dp is 1.75 px: 18 dp is 31.5 px, the ellipse 24.89 world px.
	_layer.set_selected(PackedInt32Array([1]))
	var ring: Sprite2D = _layer.rig(0).get_node("Ring")
	for z: Array in [[0.75, 31.5], [1.0, 31.5], [1.5, 37.335]]:
		_camera.zoom = Vector2(z[0], z[0])
		_layer._process(0.0)
		assert_float(ring.radius * z[0]).is_equal_approx(z[1], 0.001)
		# The stroke is baked into the texture and scales with the ring (STYLE.md, P34): white R/6
		# with R/18 of dark on each side, which is 3 dp + 1 dp + 1 dp at the 18 dp minimum radius.
		# So the checks are the dp (unit) and the scale that sizes the texture to the radius.
		assert_float(ring.unit * z[0]).is_equal_approx(1.75, 0.0001)
		assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(ring.radius, 0.001)
		assert_float(ring.scale.y * 2.0).is_equal_approx(ring.scale.x, 0.000001)
	await _use(&"desktop")  # A resize under a ring: 1 dp is now 1 px, and the ellipse is larger.
	assert_float(ring.unit * 1.5).is_equal_approx(1.0, 0.0001)
	assert_float(ring.radius * 1.5).is_equal_approx(37.335, 0.001)
	assert_float(ring.scale.x * RING_CENTRE_PX).is_equal_approx(ring.radius, 0.001)
	_assert_no_allocation(func() -> void: _layer._process(0.016))
	_controller.selection.clear()
	assert_array(_ringed_ids()).is_empty()


func test_the_markers_draw_at_z_70_above_every_layer_of_the_world() -> void:
	# The table of ADR 0023 section 2: the sorted world at 10, the bars, shells and effects at 30,
	# 40 and 50, the marks at 70, and the mark layer's own z does not depend on its parent.
	assert_int(_markers.z_index).is_equal(70)
	assert_bool(_markers.z_as_relative).is_false()
	for z: int in [WorldSort.Z_SORT, 30, 40, 50]:
		assert_int(_markers.z_index).is_greater(z)
	_layer.set_selected(PackedInt32Array([3]))
	var highest: int = 0
	for rig: Node2D in _layer.world_sort.get_children():
		for layer: Sprite2D in rig.get_children():
			var z: int = (
				layer.z_index if not layer.z_as_relative else layer.z_index + WorldSort.Z_SORT
			)
			highest = maxi(highest, z)
	assert_int(highest).is_equal(WorldSort.Z_SORT)  # The hulls and turrets; the ring is at 3.
	assert_int(_markers.z_index).is_greater(highest)


func test_chevrons_close_in_and_the_diamond_settles_at_the_spec_sizes() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1.75 px per dp.
	_markers.show_attack_move(Vector2(1000, 2000))
	_markers.show_target(RED_TANK)
	var chevrons: CanvasGroup = _markers.get_child(0)
	var flash: CanvasGroup = _markers.get_child(1)
	assert_that(chevrons.position).is_equal(Vector2(1000, 2000))
	assert_that(flash.position).is_equal(RED_TANK)
	assert_vector(chevrons.scale).is_equal_approx(Vector2(1.75, 1.75), TOL)  # Children are dp.
	# Open chevrons, a closed diamond: the second cue.
	assert_array(_strokes(chevrons, 0)).is_equal(
		[[5.0, DARK, true, false], [3.0, AMBER, true, false]]
	)
	assert_array(_strokes(flash, 4)).is_equal([[5.0, DARK, true, true], [3.0, RED, true, true]])
	for first: int in [0, 5]:  # The outline pass and the colour pass.
		for k: int in 4:  # The east chevron's tip faces west, the others are turned by 90 degrees.
			var arm: Line2D = chevrons.get_child(first + k)
			assert_int(arm.points.size()).is_equal(3)
			for at: int in 3:  # Turned by k quarter turns, then flattened: the node is not turned.
				var corner: Vector2 = [Vector2(7, -7), Vector2.ZERO, Vector2(7, 7)][at]
				var turned: Vector2 = corner.rotated(k * PI / 2.0) * FLAT
				assert_vector(arm.points[at]).is_equal_approx(turned, TOL)
			assert_float(arm.rotation).is_equal(0.0)
			assert_vector(arm.scale).is_equal(Vector2.ONE)  # Strokes keep their width.
	# Age in ms, chevron tip distance in dp (ease out: not 27 at 75 ms), diamond size.
	for step: Array in [[0, 36.0, 1.5], [75, 21.375, 1.125], [150, 13.5, 1.0], [200, 12.0, 1.0]]:
		_now_ms = step[0]
		_markers._process(0.0)
		for first: int in [0, 5]:  # Both passes move and show together.
			for k: int in 4:
				var tip: Vector2 = Vector2(step[1], 0).rotated(k * PI / 2.0) * FLAT
				assert_vector(chevrons.get_child(first + k).position).is_equal_approx(tip, TOL)
				var corner: Vector2 = flash.get_child(first + 4).points[k] * flash.scale.x  # World px.
				assert_vector(corner).is_equal_approx(CORNERS[k] * FLAT * DIAMOND_PX * step[2], TOL)
			assert_bool(chevrons.get_child(first).visible).is_true()
			assert_bool(flash.get_child(first).visible).is_false()
			assert_bool(flash.get_child(first + 4).visible).is_true()
			assert_bool(chevrons.get_child(first + 4).visible).is_false()
	_camera.zoom = Vector2(1.5, 1.5)  # A dp size divides by the zoom: 1.75 / 1.5.
	await await_idle_frame()
	_markers.show_attack_move(Vector2.ZERO)
	assert_vector(_markers.get_child(2).scale).is_equal_approx(Vector2.ONE * 1.75 / 1.5, TOL)
	_camera.zoom = Vector2(0.75, 0.75)  # A pinch under a mark: it keeps its dp size on screen.
	await await_idle_frame()
	_markers._process(0.0)
	assert_vector(_markers.get_child(2).scale).is_equal_approx(Vector2.ONE * 1.75 / 0.75, TOL)
	_assert_no_allocation(
		func() -> void:
			_now_ms += 5
			_markers._process(0.0)
	)


func test_a_mark_fades_as_one_group_and_expires_at_marker_ms() -> void:
	var settings: InputSettings = _markers.settings.duplicate()
	_markers.settings = settings
	var fades: Dictionary[int, Array] = {  # Full alpha until min(200, marker_ms / 3), then linear.
		600: [[0, 1.0], [200, 1.0], [300, 0.75], [400, 0.5], [500, 0.25]],
		300: [[0, 1.0], [100, 1.0], [150, 0.75], [200, 0.5], [250, 0.25]],
	}
	for marker_ms: int in fades:
		settings.marker_ms = marker_ms
		_now_ms = 10000
		_markers.show_attack_move(Vector2.ZERO)
		var mark: CanvasGroup = _markers.get_child(_markers.get_child_count() - 1)
		for step: Array in fades[marker_ms]:
			_now_ms = 10000 + step[0]
			_markers._process(0.0)
			assert_float(mark.self_modulate.a).is_equal_approx(step[1], 0.0001)
			assert_that(mark.modulate).is_equal(Color.WHITE)  # Not modulate: that blends twice.
		_now_ms = 10000 + marker_ms - 1
		_markers._process(0.0)
		assert_bool(mark.visible).is_true()
		_now_ms += 1
		_markers._process(0.0)
		assert_bool(mark.visible).is_false()
		assert_int(_markers.active_count()).is_equal(0)


func test_the_pool_never_grows_past_pool_size_and_reuses_the_oldest_mark() -> void:
	assert_int(_markers.pool_size).is_equal(4)
	for i: int in 6:  # Shows 5 and 6 take the oldest marks, the first and second.
		if i == 4:
			_markers.show_target(Vector2(100 * i, 0))
		else:
			_markers.show_attack_move(Vector2(100 * i, 0))
	assert_int(_markers.get_child_count()).is_equal(4)
	assert_int(_markers.active_count()).is_equal(4)
	var xs: Array = _markers.get_children().map(func(m: Node2D) -> float: return m.position.x)
	assert_array(xs).is_equal([400.0, 500.0, 200.0, 300.0])
	assert_bool(_markers.get_child(0).get_child(4).visible).is_true()  # Reused as a flash.


## The table pairs each profile with a size by position: it stays in step with the shared list.
func test_the_profiles_are_the_six_sizes_of_the_shared_list() -> void:
	var sizes: Array[Vector2i] = []
	for profile: StringName in PROFILES:
		sizes.append(UiProfiles.by_name(profile).window_size)
	assert_array(sizes).is_equal(ScreenSizes.ALL)


func test_orders_rings_anchor_and_box_follow_the_fingers_at_every_profile() -> void:
	assert_int(_markers.get_index()).is_greater(_layer.get_index())
	assert_int(_box.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)  # A second finger reaches us.
	for profile: StringName in PROFILES:
		await _use(profile)
		_runner.start()
		await await_idle_frame()
		_camera.zoom = Vector2.ONE
		_camera.centre_on(CAMERA_START)
		_controller.selection.clear()
		_now_ms += 5000
		_markers._process(0.0)  # Earlier marks have expired.
		var ground: Vector2 = GROUND
		_tap(_camera.world_to_screen(ground))  # Nothing selected: nothing happens.
		assert_int(_markers.active_count()).is_equal(0)
		_tap(_layer.unit_screen_position(0))  # The first tap selects, and the ring is there at once.
		assert_array(_ringed_ids()).is_equal([1])
		_tap(_camera.world_to_screen(ground))
		assert_bool(_mark_at(ground).get_child(0).visible).is_true()  # Chevrons.
		_camera.centre_on(RED_TANK)
		# The diamond is the subject, not the fog: red tank 31 is hidden at the start and a tap on a
		# hidden enemy is a ground tap. Picking under fog is proven in test_player_controller.gd
		# (the hidden-enemy cases) and test_picker.gd.
		_layer.reveal_enemies = true
		_tap(_layer.unit_screen_position(30) - Vector2(0, UiScale.dp(20)))  # An enemy, from above.
		assert_bool(_mark_at(RED_TANK).get_child(4).visible).is_true()  # The diamond.
		assert_int(_markers.active_count()).is_equal(2)
		await _long_press_drag_release(false)
		await _long_press_drag_release(true)
		assert_array(_buzzes).is_equal([15, 15])  # One buzz per long-press.
		_buzzes.clear()


## The overlay is drawn in the frames between the steps, so a script error in _draw shows up here.
func _long_press_drag_release(canceled: bool) -> void:
	var from: Vector2 = Vector2(400, 300)
	var to: Vector2 = Vector2(250, 420)
	TouchEvents.press(get_viewport(), 0, from)
	assert_bool(_box.is_showing()).is_false()
	_now_ms += 300
	_touch._process(0.0)  # The frame that sees the hold.
	assert_bool(_box.is_showing()).is_true()
	assert_vector(_box.anchor).is_equal_approx(from, TOL)
	assert_bool(_box.rect.has_area()).is_false()  # No box yet, and none left from the last gesture.
	var shown_at: int = _now_ms
	for step: Array in [[0, 48.0], [75, 36.0], [150, 32.0], [500, 32.0]]:  # Ease out.
		_now_ms = shown_at + step[0]
		assert_float(_box.anchor_radius()).is_equal_approx(UiScale.dp(step[1]), 0.001)
	await await_idle_frame()
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	assert_bool(_box.is_showing()).is_true()
	assert_vector(_box.rect.position).is_equal_approx(Vector2(250, 300), TOL)  # Normalised.
	assert_vector(_box.rect.size).is_equal_approx(Vector2(150, 120), TOL)
	await await_idle_frame()
	TouchEvents.release(get_viewport(), 0, to, canceled)
	assert_bool(_box.is_showing()).is_false()
	_now_ms += 1000


## `step` runs 20 times and allocates no object: the validator in an instance id counts up with
## every allocation, and the second probe is one itself. The override goes first, because without
## one every UiScale call builds a UiMetrics, and a stray call in a frame then shows up.
func _assert_no_allocation(step: Callable) -> void:
	UiScale.clear_override()
	var first: int = RefCounted.new().get_instance_id() >> 24
	for _frame: int in 20:
		step.call()
	assert_int((RefCounted.new().get_instance_id() >> 24) - first).is_equal(1)


## Unit ids whose ring shows.
func _ringed_ids() -> Array[int]:
	var ids: Array[int] = []
	for rig: Node2D in _layer.world_sort.get_children():
		if rig.has_node("Ring") and rig.get_node("Ring").visible:
			ids.append(rig.name.trim_prefix("Unit").to_int())
	return ids


## The mark showing at `world`.
func _mark_at(world: Vector2) -> CanvasGroup:
	for mark: CanvasGroup in _markers.get_children():
		if mark.visible and mark.position.distance_to(world) < 0.05:
			return mark
	return null


## [width, colour, round and smooth, closed] of the outline pass and the colour pass of `shape`.
func _strokes(mark: Node, shape: int) -> Array:
	var out: Array = []
	for line: Line2D in [mark.get_child(shape), mark.get_child(5 + shape)]:
		var round: bool = line.joint_mode == Line2D.LINE_JOINT_ROUND and line.antialiased
		for cap: int in [line.begin_cap_mode, line.end_cap_mode]:
			round = round and cap == Line2D.LINE_CAP_ROUND
		out.append([line.width, line.default_color, round, line.closed])
	return out


func _use(profile: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()


func _tap(at: Vector2) -> void:
	var view: Rect2 = get_viewport().get_visible_rect()
	assert_bool(view.has_point(at)).override_failure_message("tap off screen: %s" % at).is_true()
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
