extends GdUnitTestSuite
## The radar scope (plan P121, ADR 0025 sections 2 and 7), in the main scene at the six sizes of
## ScreenSizes.ALL and at every profile of both orientations, also with a cutout: a 56 dp round
## window at the top right of the safe rect in both orientations, taking the rect of
## `HudCorners.place` and keeping it through a turn; its crop is centred on the camera's ground
## centre and drawn under the iso skew (a cell north-east of the centre draws up and right, a ground
## circle of `scope_radius_tiles` meets the rim), one textured polygon of 32 points cut to the map
## where the camera is near an edge; the camera's frame is the visible world rect scaled about the
## middle; it redraws only when the camera or the picture moved; a tap opens the full map and
## nothing else happens (no Command, no pan, no map gesture); at 360 dp upright the pill, its menu
## button included, stands clear of the scope's corner (P124 took the Surrender button away, whose
## room had pushed the pill into the scope). The full map under it is test_radar_map's.
## Player 1 has a Headquarters, two light tanks, a Heavy Yard and a Bunkhouse.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const RadarRig: GDScript = preload("res://tests/ui/support/radar_rig.gd")
const ROSTER: Array = ["power_plant", "barracks", "vehicle_factory", "defence_turret", "light_tank"]
const MORE: Array = [
	["light_tank", 12, 10], ["light_tank", 13, 10], ["vehicle_factory", 14, 3], ["barracks", 10, 14]
]
const TANK_A: int = 3
const HOME: Vector2i = Vector2i(11, 7)
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _feed: HudStateFeed
var _state: HudState
var _scope: RadarScope
var _minimap: Minimap
var _now_ms: int = 0
var _sent: Array[Command] = []
var _told: int = 0  ## `map_gesture`s: a touch on the scope is none.


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_the_scope_is_56_dp_at_the_top_right_of_the_safe_rect_at_every_screen() -> void:
	for screen: Dictionary in RadarRig.screens():
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var expected: Rect2 = RadarRig.rects(get_viewport(), false)[HudCorners.SCOPE]
		var rect: Rect2 = _scope.get_global_rect()
		var safe: Rect2 = UiScale.safe_rect_base()
		var edge: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		var at: String = "%s: scope %s, expected %s, safe %s" % [why, rect, expected, edge]
		assert_bool(_scope.is_visible_in_tree()).override_failure_message(at).is_true()
		assert_vector(rect.position).override_failure_message(at).is_equal_approx(
			expected.position, Vector2.ONE * TOLERANCE_PX
		)
		assert_vector(rect.size).override_failure_message(at).is_equal_approx(
			expected.size, Vector2.ONE * TOLERANCE_PX
		)
		var side: float = UiScale.dp(HudCorners.SCOPE_DP)
		assert_vector(rect.size).override_failure_message(at).is_equal_approx(
			Vector2(side, side), Vector2.ONE * 1.0
		)
		assert_float(rect.size.x).is_greater_equal(UiScale.dp(48.0) - TOLERANCE_PX)
		# The safe rect's top right corner, inside the platform's safe area.
		assert_float(rect.end.x).override_failure_message(at).is_equal_approx(edge.end.x, 1.0)
		assert_float(rect.position.y).override_failure_message(at).is_equal_approx(
			edge.position.y, 1.0
		)
		assert_bool(safe.encloses(rect)).override_failure_message(at).is_true()
		# Clear of the pill, and the scope takes its touches itself.
		for other: String in ["EconomyPill"]:
			var clash: String = "%s: %s %s" % [at, other, _rect(other)]
			assert_bool(rect.intersects(_rect(other))).override_failure_message(clash).is_false()
		assert_int(_scope.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


## A turn keeps the node and the state and puts the scope in the other orientation's corner.
func test_a_turn_moves_the_scope_to_the_corner_of_the_other_layout_and_keeps_the_state() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	_state.open(HudState.Unfold.RADAR)
	_state.pinned = true
	for turn: UiMetrics in [portrait, landscape, portrait, landscape]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		var why: String = str(turn.window_size)
		var expected: Rect2 = RadarRig.rects(get_viewport(), false)[HudCorners.SCOPE]
		assert_object(_hud("RadarScope")).override_failure_message(why).is_same(_scope)
		(
			assert_vector(_scope.get_global_rect().position)
			. override_failure_message(why)
			. is_equal_approx(expected.position, Vector2.ONE * TOLERANCE_PX)
		)
		assert_vector(_scope.get_global_rect().size).override_failure_message(why).is_equal_approx(
			expected.size, Vector2.ONE * TOLERANCE_PX
		)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_bool(_state.pinned).override_failure_message(why).is_true()
		assert_bool(_scope.is_visible_in_tree()).override_failure_message(why).is_true()
	_state.pinned = false


## The crop is centred on the camera's ground centre, and a cell north-east of it (the grid's -y)
## draws up and right, one to the south-east (+x) down and right, as on the screen.
func test_the_crop_follows_the_cameras_ground_centre_in_the_iso_projection() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var cols: int = _minimap.picture().cols()
		var rows: int = _minimap.picture().rows()
		var middle: Vector2 = _scope.size * 0.5
		var s: float = _scope.world_scale()
		var wide: Vector2i = Vector2i(cols, rows) * World.MILLI_PER_TILE
		var fifth: Vector2i = Vector2i(Vector2(wide) * Vector2(0.8, 0.2))
		for ground: Vector2i in [wide / 2, wide * 3 / 10, fifth]:
			_camera.centre_on(IsoProjection.ground_to_px(ground.x, ground.y))
			var centre: Vector2 = Vector2(IsoProjection.px_to_ground(_camera.position)) / 1000.0
			var why: String = "%s: camera on %s" % [size, centre]
			(
				assert_vector(_scope.world_to_local(_camera.position))
				. override_failure_message(why)
				. is_equal_approx(middle, Vector2.ONE * 0.001)
			)
			(
				assert_vector(_scope.cell_to_local(centre.x, centre.y))
				. override_failure_message(why)
				. is_equal_approx(middle, Vector2.ONE * 0.01)
			)
			(
				assert_vector(RadarScope.uv_of(_camera.position, cols, rows))
				. override_failure_message(why)
				. is_equal_approx(centre / Vector2(cols, rows), Vector2.ONE * 0.0001)
			)
			var steps: Dictionary[String, Vector2] = {
				"north-east (-y)": Vector2(0.0, -3.0),
				"south-east (+x)": Vector2(3.0, 0.0),
				"south-west (+y)": Vector2(0.0, 3.0),
				"north-west (-x)": Vector2(-3.0, 0.0),
			}
			for label: String in steps:
				var cell: Vector2 = centre + steps[label]
				var drawn: Vector2 = _scope.cell_to_local(cell.x, cell.y) - middle
				var skew: Vector2 = Vector2(
					(steps[label].x - steps[label].y) * IsoProjection.HALF_W,
					(steps[label].x + steps[label].y) * IsoProjection.HALF_H
				)
				(
					assert_vector(drawn)
					. override_failure_message("%s, %s" % [why, label])
					. is_equal_approx(skew * s, Vector2.ONE * 0.01)
				)
			var north_east: Vector2 = _scope.cell_to_local(centre.x, centre.y - 3.0) - middle
			(
				assert_bool(north_east.x > 0.0 and north_east.y < 0.0)
				. override_failure_message(why + ": a cell north-east draws up and right")
				. is_true()
			)


## The rim is `scope_radius_tiles` away: a ground circle of that radius meets the scope's rim on
## the screen's horizontal, and the number is the settings' own.
func test_the_rim_is_scope_radius_tiles_from_the_centre_and_the_setting_is_the_states() -> void:
	await _open(ScreenSizes.LANDSCAPE[1])
	assert_int(_state.settings.scope_radius_tiles).is_equal(16)
	_camera.centre_on(IsoProjection.ground_to_px(24000, 24000))
	var middle: Vector2 = _scope.size * 0.5
	var radius: float = _scope.size.x * 0.5
	var out: Vector2 = IsoProjection.ground_to_px(24000 + 11314, 24000 - 11314)  # 16 tiles, east.
	assert_vector(_scope.world_to_local(out)).is_equal_approx(
		middle + Vector2(radius, 0.0), Vector2.ONE * 0.1
	)
	var near: InputSettings = _state.settings.duplicate() as InputSettings
	near.scope_radius_tiles = 8
	_state.settings = near
	assert_vector(_scope.world_to_local(out)).is_equal_approx(
		middle + Vector2(2.0 * radius, 0.0), Vector2.ONE * 0.2
	)  # Twice as far: 16 tiles are two radii now.
	assert_float(_scope.world_scale()).is_equal_approx(
		radius / RadarScope.rim_world_px(8), 0.000001
	)


## The crop is one polygon of 32 points while the disc lies inside the map, a cut one near an
## edge, and none before there is a picture; every point's texture coordinate is on the picture.
func test_the_crop_is_one_polygon_of_32_points_cut_to_the_map_near_an_edge() -> void:
	await _open(ScreenSizes.LANDSCAPE[1])
	var near: InputSettings = _state.settings.duplicate() as InputSettings
	near.scope_radius_tiles = 8  # The disc fits the 48 x 48 map's diamond with room to spare.
	_state.settings = near
	var cols: int = _minimap.picture().cols()
	var rows: int = _minimap.picture().rows()
	var wide: Vector2i = Vector2i(cols, rows) * World.MILLI_PER_TILE  # The map's far corner.
	var middle: Vector2i = wide / 2
	_camera.centre_on(IsoProjection.ground_to_px(middle.x, middle.y))
	var inside: Array[PackedVector2Array] = _scope.crop_pieces()
	assert_int(inside.size()).is_equal(1)
	assert_int(inside[0].size()).is_equal(RadarScope.POINTS)
	var disc_area: float = _area(RadarScope.disc_points(_scope.size * 0.5, _scope.size.x * 0.5))
	assert_float(_area(inside[0])).is_equal_approx(disc_area, disc_area * 0.001)
	_state.settings = _state.settings.duplicate() as InputSettings
	_state.settings.scope_radius_tiles = 16
	for ground: Vector2i in [Vector2i(0, 0), Vector2i(wide.x, 0), wide, Vector2i(0, wide.y)]:
		_camera.centre_on(IsoProjection.ground_to_px(ground.x, ground.y))
		var pieces: Array[PackedVector2Array] = _scope.crop_pieces()
		var why: String = "camera on the corner %s" % ground
		assert_int(pieces.size()).override_failure_message(why).is_equal(1)
		assert_float(_area(pieces[0])).override_failure_message(why).is_less(disc_area * 4.0 * 0.6)
		assert_float(_area(pieces[0])).override_failure_message(why).is_greater(0.0)
		for point: Vector2 in pieces[0]:
			var uv: Vector2 = RadarScope.uv_of(_scope.local_to_world(point), cols, rows)
			(
				assert_bool(Rect2(Vector2.ZERO, Vector2.ONE).grow(0.002).has_point(uv))
				. override_failure_message("%s: %s is at %s on the picture" % [why, point, uv])
				. is_true()
			)


## The frame is the camera's visible world rect scaled about the scope's middle, which is the
## camera's centre: its size follows the zoom, and it is the same shape as the screen.
func test_the_frame_is_the_visible_world_rect_scaled_about_the_middle() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var s: float = _scope.world_scale()
		for zoom: float in [0.5, 1.0, 1.5, 2.0]:
			_camera.zoom = Vector2.ONE * zoom
			_camera.centre_on(IsoProjection.ground_to_px(24000, 24000))
			var view: Rect2 = _camera.visible_world_rect()
			var frame: Rect2 = _scope.frame_rect()
			var why: String = "%s, zoom %s: view %s, frame %s" % [size, zoom, view, frame]
			assert_vector(frame.size).override_failure_message(why).is_equal_approx(
				view.size * s, Vector2.ONE * 0.001
			)
			assert_vector(frame.get_center()).override_failure_message(why).is_equal_approx(
				_scope.size * 0.5, Vector2.ONE * 0.001
			)
			assert_float(frame.size.x / frame.size.y).override_failure_message(why).is_equal_approx(
				view.size.x / view.size.y, 0.0001
			)
			# A corner of the view is where the world point of that corner is on the scope.
			assert_vector(frame.position).override_failure_message(why).is_equal_approx(
				_scope.world_to_local(view.position), Vector2.ONE * 0.001
			)


## The scope draws on a move of the camera (its centre or its zoom) and on a new picture, and never
## at rest.
func test_the_scope_redraws_only_when_the_camera_or_the_picture_moved() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		await _settle()
		var why: String = str(size)
		var draws: int = _scope.draw_count()
		assert_int(draws).override_failure_message(why).is_greater(0)
		for frame: int in 20:  # At rest: nothing is drawn.
			await await_idle_frame()
		assert_int(_scope.draw_count()).override_failure_message(why).is_equal(draws)
		for frame: int in 10:  # A pan: a draw a frame.
			_camera.pan_by_screen(Vector2(30.0, 12.0))
			await await_idle_frame()
		var panned: int = _scope.draw_count() - draws
		assert_int(panned).override_failure_message(why).is_between(8, 10)
		draws = _scope.draw_count()
		_camera.zoom = Vector2.ONE * 1.5  # A zoom: one.
		await _settle()
		assert_int(_scope.draw_count() - draws).override_failure_message(why).is_equal(1)
		draws = _scope.draw_count()
		for frame: int in 5:
			await await_idle_frame()
		assert_int(_scope.draw_count()).override_failure_message(why).is_equal(draws)
		# A match of 60 ticks paints the picture often and the scope sees it once, in its frame.
		var paints: int = _minimap.redraw_count()
		CommandQueue.submit(Command.move(1, PackedInt32Array([TANK_A]), 24000, 21500))
		_runner.run_ticks(60)
		await _settle()
		assert_int(_minimap.redraw_count() - paints).override_failure_message(why).is_greater(1)
		assert_int(_scope.draw_count() - draws).override_failure_message(why).is_equal(1)
		draws = _scope.draw_count()
		for frame: int in 5:
			await await_idle_frame()
		assert_int(_scope.draw_count()).override_failure_message(why).is_equal(draws)


## A press and a release on the scope is a tap and opens the full map, however long the finger
## rested; a finger that leaves it opens nothing. None of it pans, selects, orders or is a gesture
## on the map.
func test_a_tap_opens_the_full_map_and_nothing_else_happens() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var at: Vector2 = _scope.get_global_rect().get_center()
		var away: Vector2 = _scope.get_global_rect().position - Vector2.ONE * UiScale.dp(60.0)
		var home: Vector2 = _camera.position
		for kind: StringName in [&"tap", &"hold", &"drag_inside", &"drag_off", &"cancelled"]:
			var why: String = "%s: a %s" % [size, kind]
			_state.close(HudState.Unfold.RADAR)
			_controller.selection.set_ids(PackedInt32Array([TANK_A]))
			_sent.clear()
			_told = 0
			var opens: bool = true
			TouchEvents.press(get_viewport(), 0, at)
			match kind:
				&"hold":
					_now_ms += 5000
					_touch._process(0.0)
					_scope._process(0.0)
				&"drag_inside":
					var by: Vector2 = Vector2(UiScale.dp(6.0), 0.0)
					TouchEvents.drag(get_viewport(), 0, at + by, by)
				&"drag_off":
					TouchEvents.drag(get_viewport(), 0, away, away - at)
					opens = false
				&"cancelled":
					opens = false
			var end: Vector2 = away if kind == &"drag_off" else at
			TouchEvents.release(get_viewport(), 0, end, kind == &"cancelled")
			(
				assert_bool(_state.is_open(HudState.Unfold.RADAR))
				. override_failure_message(why)
				. is_equal(opens)
			)
			assert_array(_sent).override_failure_message(why).is_empty()
			assert_int(_told).override_failure_message(why).is_equal(0)
			assert_vector(_camera.position).override_failure_message(why).is_equal(home)
			assert_array(_controller.selection.selected).override_failure_message(why).is_equal(
				[TANK_A]
			)
		_state.close(HudState.Unfold.RADAR)


## A tap on the scope while the full map is open is another touch on it, not a toggle: the map
## stays open and its count starts over (HudState.open on an open map restarts it).
func test_a_tap_on_the_scope_while_the_map_is_open_keeps_it_open_and_restarts_the_count() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		_feed.set_process(false)
		var why: String = str(size)
		_state.open(HudState.Unfold.RADAR)
		_step(3750.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_tap(_scope.get_global_rect().get_center())
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_step(3750.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_step(250.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_int(_told).override_failure_message(why).is_equal(0)


## A modal that opens between the press and the lift spends the finger (TouchInput.CANCEL_GROUP):
## the lift opens nothing, and the next tap opens the map as usual.
func test_a_modal_between_the_press_and_the_lift_spends_the_tap() -> void:
	await _open(ScreenSizes.LANDSCAPE[1])
	var at: Vector2 = _scope.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	get_tree().call_group(TouchInput.CANCEL_GROUP, "cancel_gestures")
	TouchEvents.release(get_viewport(), 0, at)
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	_tap(at)
	assert_int(_state.current).is_equal(HudState.Unfold.RADAR)


## 360 dp upright: the pill (menu button, credits and power bar) starts at the corner and ends a
## gap short of the scope, so a tap meant for the scope never lands on the pill.
func test_at_360_dp_the_pill_stands_clear_of_the_scope() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(phone.window_size, phone)
	var pill: EconomyPill = _hud("EconomyPill") as EconomyPill
	pill.place()
	await _settle()
	var pill_rect: Rect2 = pill.get_global_rect()
	var scope: Rect2 = _scope.get_global_rect()
	assert_bool(pill_rect.intersects(scope)).is_false()
	assert_float(scope.position.x - pill_rect.end.x).is_greater_equal(UiScale.dp(8.0) - 1.0)


## Twice the polygon's signed area, halved and made positive: its area.
func _area(points: PackedVector2Array) -> float:
	var twice: float = 0.0
	for index: int in points.size():
		var next: Vector2 = points[(index + 1) % points.size()]
		twice += points[index].x * next.y - next.x * points[index].y
	return absf(twice) * 0.5


## Frames of `ms` in 250 ms steps through the feed, as the engine would run them.
func _step(ms: float) -> void:
	var left: float = ms
	while left > 0.0:
		var step: float = minf(left, 250.0)
		_feed._process(step / 1000.0)
		left -= step


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), the match
## paused, the Commands caught and the touch input's clock the test's.
func _open(size: Vector2i, metrics: UiMetrics = null) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	if metrics != null:
		UiScale.set_override(metrics)
	else:
		UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario_for(1, "headquarters", MORE, ROSTER)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_feed = _hud("HudStateFeed") as HudStateFeed
	_state = _feed.state
	_scope = _hud("RadarScope") as RadarScope
	_minimap = _hud("Minimap") as Minimap
	_now_ms = 0
	_told = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_touch.map_gesture.connect(func() -> void: _told += 1)
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	Rig.explore(_runner.snapshot)
	await _settle()
