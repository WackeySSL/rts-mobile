extends GdUnitTestSuite
## Feedback in the main scene (STYLE.md "Feedback markers"): rings, chevrons, target diamond, anchor
## and box, with one fake clock for TouchInput, MarkerLayer and BoxOverlay. Tank 1 stands at world
## px (544, 1184) and red tank 31 at (2208, 672). The expected numbers are STYLE.md's, as literals.

const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]
const GROUND: Vector2 = Vector2(1281, 1377)  ## No unit near it: milli (20016, 21516).
const DARK: Color = Color("1C2127")
const AMBER: Color = Color("F5A524")
const RED: Color = Color("E5484D")
const TOL: Vector2 = Vector2(0.01, 0.01)

var _now_ms: int = 0
var _buzzes: Array[int] = []
var _runner: MatchRunner
var _layer: UnitLayer
var _markers: MoveMarkerLayer
var _box: BoxOverlay
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController


func before_test() -> void:
	get_window().size = Vector2i(1280, 720)
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


func test_rings_show_for_exactly_the_selected_ids_and_are_31_5_35_2_and_52_8_px() -> void:
	assert_bool(_controller.selection_changed.is_connected(_layer.set_selected)).is_true()
	_controller.selection.set_ids(PackedInt32Array([3, 7]))  # No frame has run.
	assert_array(_ringed_ids()).is_equal([3, 7])
	var rig_children: Array = _layer.get_child(2).get_children()
	var names: Array = rig_children.map(func(n: Node) -> StringName: return n.name)
	assert_array(names).is_equal([&"Ring", &"Hull", &"Team", &"Turret"])  # Under the layers.
	_controller.selection.set_ids(PackedInt32Array([7, 40]))
	assert_array(_ringed_ids()).is_equal([7, 40])
	_layer.set_selected(PackedInt32Array([999, 1]))  # An unknown id is skipped.
	assert_array(_ringed_ids()).is_equal([1])
	await _use(&"android_6in")  # 1 dp is 1.75 px: 18 dp is 31.5 px, the art 35.2 world px.
	_layer.set_selected(PackedInt32Array([1]))
	var ring: Node2D = _layer.get_child(0).get_node("Ring")
	for z: Array in [[0.75, 31.5], [1.0, 35.2], [1.5, 52.8]]:
		_camera.zoom = Vector2(z[0], z[0])
		_layer._process(0.0)
		assert_float(ring.radius * z[0]).is_equal_approx(z[1], 0.001)
		assert_float(ring.unit * z[0]).is_equal_approx(1.75, 0.0001)  # Strokes are 3 and 5 dp.
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame: int in 20:  # Frames allocate nothing.
		_layer._process(0.016)
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)
	await _use(&"desktop")  # A resize under a ring: 1 dp is now 1 px, and the art is larger.
	assert_float(ring.unit * 1.5).is_equal_approx(1.0, 0.0001)
	assert_float(ring.radius * 1.5).is_equal_approx(52.8, 0.001)
	_controller.selection.clear()
	assert_array(_ringed_ids()).is_empty()


func test_chevrons_close_in_and_the_diamond_settles_at_the_spec_sizes() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1.75 px per dp.
	_markers.show_attack_move(Vector2(1000, 2000))
	_markers.show_target(Vector2(2208, 672))
	var chevrons: CanvasGroup = _markers.get_child(0)
	var flash: CanvasGroup = _markers.get_child(1)
	assert_that(chevrons.position).is_equal(Vector2(1000, 2000))
	assert_that(flash.position).is_equal(Vector2(2208, 672))
	assert_vector(chevrons.scale).is_equal_approx(Vector2(1.75, 1.75), TOL)  # Children are dp.
	assert_array(_strokes(chevrons, 0)).is_equal([[5.0, DARK, true], [3.0, AMBER, true]])
	assert_array(_strokes(flash, 4)).is_equal([[5.0, DARK, true], [3.0, RED, true]])
	for k: int in 4:  # The east chevron's tip faces west, the others are turned by 90 degrees.
		var arm: Line2D = chevrons.get_child(5 + k)
		assert_array(arm.points).is_equal([Vector2(7, -7), Vector2.ZERO, Vector2(7, 7)])
		assert_float(arm.rotation).is_equal_approx(k * PI / 2.0, 0.0001)
	# Age in ms, chevron tip distance in dp (ease out: not 27 at 75 ms), diamond size.
	for step: Array in [[0, 36.0, 1.5], [75, 21.375, 1.125], [150, 13.5, 1.0], [200, 12.0, 1.0]]:
		_now_ms = step[0]
		_markers._process(0.0)
		for k: int in 4:
			var tip: Vector2 = Vector2(step[1], 0).rotated(k * PI / 2.0)
			assert_vector(chevrons.get_child(5 + k).position).is_equal_approx(tip, TOL)
		var west: Vector2 = flash.get_child(9).points[2] * flash.scale.x  # World px.
		assert_vector(west).is_equal_approx(Vector2(-45.8, 0) * step[2], TOL)
		assert_bool(chevrons.get_child(0).visible and not flash.get_child(0).visible).is_true()
		assert_bool(flash.get_child(4).visible and not chevrons.get_child(4).visible).is_true()
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame: int in 20:  # Frames allocate nothing.
		_now_ms += 5
		_markers._process(0.0)
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)
	_camera.zoom = Vector2(1.5, 1.5)  # A dp size divides by the zoom: 1.75 / 1.5.
	await await_idle_frame()
	_markers.show_attack_move(Vector2.ZERO)
	assert_vector(_markers.get_child(2).scale).is_equal_approx(Vector2.ONE * 1.75 / 1.5, TOL)


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


func test_orders_rings_anchor_and_box_follow_the_fingers_at_every_profile() -> void:
	for profile: StringName in PROFILES:
		await _use(profile)
		_runner.start()
		await await_idle_frame()
		_camera.zoom = Vector2.ONE
		_camera.centre_on(Vector2(800, 1376))
		_controller.selection.clear()
		_now_ms += 5000
		_markers._process(0.0)  # Earlier marks have expired.
		_tap(_camera.world_to_screen(GROUND))  # Nothing selected: nothing happens.
		assert_int(_markers.active_count()).is_equal(0)
		_tap(_layer.unit_screen_position(0))  # The first tap selects, and the ring is there at once.
		assert_array(_ringed_ids()).is_equal([1])
		_tap(_camera.world_to_screen(GROUND))
		assert_bool(_mark_at(GROUND).get_child(0).visible).is_true()  # Chevrons.
		_camera.centre_on(Vector2(2208, 672))
		_tap(_layer.unit_screen_position(30) - Vector2(UiScale.dp(20), 0))  # An enemy.
		assert_bool(_mark_at(Vector2(2208, 672)).get_child(4).visible).is_true()  # The diamond.
		assert_int(_markers.active_count()).is_equal(2)
		_long_press_drag_release(false)
		_long_press_drag_release(true)
		assert_array(_buzzes).is_equal([15, 15])  # One buzz per long-press.
		_buzzes.clear()


func _long_press_drag_release(canceled: bool) -> void:
	var from: Vector2 = Vector2(400, 300)
	var to: Vector2 = Vector2(250, 420)
	TouchEvents.press(get_viewport(), 0, from)
	assert_bool(_box.is_showing()).is_false()
	_now_ms += 300
	_touch._process(0.0)  # The frame that sees the hold.
	assert_vector(_box.anchor).is_equal_approx(from, TOL)
	var shown_at: int = _now_ms
	for step: Array in [[0, 48.0], [75, 36.0], [150, 32.0], [500, 32.0]]:  # Ease out.
		_now_ms = shown_at + step[0]
		assert_float(_box.anchor_radius()).is_equal_approx(UiScale.dp(step[1]), 0.001)
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	assert_vector(_box.rect.position).is_equal_approx(Vector2(250, 300), TOL)  # Normalised.
	assert_vector(_box.rect.size).is_equal_approx(Vector2(150, 120), TOL)
	TouchEvents.release(get_viewport(), 0, to, canceled)
	assert_bool(_box.is_showing()).is_false()
	_now_ms += 1000


## Unit ids whose ring shows.
func _ringed_ids() -> Array[int]:
	var ids: Array[int] = []
	for rig: Node2D in _layer.get_children():
		if rig.has_node("Ring") and rig.get_node("Ring").visible:
			ids.append(rig.name.trim_prefix("Unit").to_int())
	return ids


## The mark showing at `world`.
func _mark_at(world: Vector2) -> CanvasGroup:
	for mark: CanvasGroup in _markers.get_children():
		if mark.visible and mark.position.distance_to(world) < 0.05:
			return mark
	return null


## [width, colour, round and smooth] of the outline pass and the colour pass of `shape`.
func _strokes(mark: Node, shape: int) -> Array:
	var out: Array = []
	for line: Line2D in [mark.get_child(shape), mark.get_child(5 + shape)]:
		var round: bool = line.joint_mode == Line2D.LINE_JOINT_ROUND and line.antialiased
		for cap: int in [line.begin_cap_mode, line.end_cap_mode]:
			round = round and cap == Line2D.LINE_CAP_ROUND
		out.append([line.width, line.default_color, round])
	return out


func _use(profile: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()


func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
