extends GdUnitTestSuite
## The edge pan of a ghost drag (plan P86b, ADR 0019 section 2), through the real TouchInput,
## GestureRecognizer and PlacementController of the main scene at the six screens
## (ScreenSizes.ALL) with a fake clock. A finger that grabbed the ghost and rests in the band
## `edge_band_dp` inside an edge of the safe area scrolls the map toward that edge at
## `edge_pan_dp_per_s` of screen, whatever the zoom and the frame rate, within the camera's clamp;
## the ghost stays on the tile under the finger as the map moves. It stops when the finger leaves
## the band, lifts or meets a second finger, and a pan that starts off the ghost or a tap near an
## edge scrolls nothing. The top band is measured on the ghost's point, `ghost_lift_dp` above the
## finger. A turn of the phone ends the scroll, queues no Command and leaves the sim as it was. The
## frames are driven by hand (`TouchInput._process` with a delta), so no real frame adds a step.

const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const HOME: Vector2i = Vector2i(11, 7)  ## The tile that holds the middle of the plant at FITS.
const FRAME: float = 1.0 / 60.0
const HOLD_FRAMES: int = 12  ## 0.2 s: 60 dp of scroll, well inside the map's clamp from HOME.
const TOLERANCE_PX: float = 0.1
const CUTOUT_PX: int = 100
## The four bands: the unit vector the map scrolls (the camera moves) along.
const LEFT: Vector2 = Vector2(-1.0, 0.0)
const RIGHT: Vector2 = Vector2(1.0, 0.0)
const UP: Vector2 = Vector2(0.0, -1.0)
const DOWN: Vector2 = Vector2(0.0, 1.0)

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _placement: PlacementController
var _now_ms: int = 0
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await _open_main(false)
	Rig.make_ready(_runner.snapshot)
	Rig.explore(_runner.snapshot)


func after_test() -> void:
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()


func test_a_drag_in_each_edge_band_scrolls_the_map_that_way_at_the_configured_speed() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		for edge: Vector2 in [LEFT, RIGHT, UP, DOWN]:
			var note: String = "%s toward %s" % [size, edge]
			_reset()
			var finger: Vector2 = _in_band(edge)
			assert_vector(_placement.edge_heading(finger)).override_failure_message(note).is_equal(
				edge
			)
			var start: Vector2i = _placement.tile
			_grab_and_drag_to(finger)
			var held: Vector2 = _camera.position
			_hold(HOLD_FRAMES, FRAME)
			var expected: Vector2 = edge * UiScale.dp(_speed_dp()) * (HOLD_FRAMES * FRAME)
			assert_vector(_camera.position - held).override_failure_message(note).is_equal_approx(
				expected / _camera.zoom.x, Vector2.ONE * TOLERANCE_PX
			)
			# The ghost followed the finger over the moving ground: the tile under its lifted point.
			var lifted: Vector2 = (
				finger - Vector2(0.0, UiScale.dp(_controller.settings.ghost_lift_dp))
			)
			var ground: Vector2i = IsoProjection.px_to_ground(_camera.screen_to_world(lifted))
			var under: Vector2i = Vector2i(floori(ground.x / 1000.0), floori(ground.y / 1000.0))
			assert_vector(_placement.tile).override_failure_message(note).is_equal(under)
			assert_vector(_placement.tile).override_failure_message(note).is_not_equal(start)
			assert_array(_sent).override_failure_message(note).is_empty()
			if edge == DOWN and HudLayout.is_portrait():
				var band_top: float = _build_band().position.y
				assert_float(_centre().y).override_failure_message(note).is_less(band_top)
			TouchEvents.release(get_viewport(), 0, finger)


## Two bands at once scroll along the diagonal at the same speed, not faster.
func test_a_corner_scrolls_along_the_diagonal_at_the_same_speed() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		_reset()
		var safe: Rect2 = UiScale.safe_rect_base()
		var band: float = UiScale.dp(_controller.settings.edge_band_dp)
		var floor_y: float = HudLayout.map_bottom_px(safe)
		var finger: Vector2 = Vector2(safe.end.x - band * 0.5, floor_y - band * 0.5)
		_grab_and_drag_to(finger)
		var held: Vector2 = _camera.position
		_hold(HOLD_FRAMES, FRAME)
		var moved: Vector2 = (_camera.position - held) * _camera.zoom.x
		var note: String = str(size)
		assert_float(moved.length()).override_failure_message(note).is_equal_approx(
			UiScale.dp(_speed_dp()) * (HOLD_FRAMES * FRAME), TOLERANCE_PX
		)
		assert_float(moved.x).override_failure_message(note).is_greater(0.0)
		assert_float(moved.y).override_failure_message(note).is_greater(0.0)
		assert_float(moved.x).override_failure_message(note).is_equal_approx(moved.y, TOLERANCE_PX)
		TouchEvents.release(get_viewport(), 0, finger)


func test_the_scroll_stops_when_the_finger_leaves_the_band_lifts_or_meets_a_second_finger() -> void:
	var finger: Vector2 = _in_band(RIGHT)
	var inside: Vector2 = _centre()
	# Leaves the band: a drag event back to the middle of the screen.
	_reset()
	_grab_and_drag_to(finger)
	_hold(HOLD_FRAMES, FRAME)
	var held: Vector2 = _camera.position
	TouchEvents.drag(get_viewport(), 0, inside, inside - finger)
	_hold(HOLD_FRAMES, FRAME)
	assert_vector(_camera.position).is_equal(held)
	# Back in the band, then the finger lifts.
	TouchEvents.drag(get_viewport(), 0, finger, finger - inside)
	_hold(HOLD_FRAMES, FRAME)
	assert_vector(_camera.position).is_not_equal(held)
	TouchEvents.release(get_viewport(), 0, finger)
	held = _camera.position
	_hold(HOLD_FRAMES, FRAME)
	assert_vector(_camera.position).is_equal(held)
	# A second finger turns the grab into a pinch: the band scrolls nothing.
	_reset()
	_grab_and_drag_to(finger)
	TouchEvents.press(get_viewport(), 1, inside)
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.MULTI)
	held = _camera.position
	_hold(HOLD_FRAMES, FRAME)
	assert_vector(_camera.position).is_equal(held)
	TouchEvents.release(get_viewport(), 1, inside)
	TouchEvents.release(get_viewport(), 0, finger)
	assert_array(_sent).is_empty()


## Only a finger that grabbed the ghost scrolls the map by resting: a pan that starts off the ghost
## and ends in a band is the finger's own pan, and a tap near an edge is a tap.
func test_a_pan_off_the_ghost_and_a_tap_in_a_band_scroll_nothing_by_themselves() -> void:
	var finger: Vector2 = _in_band(LEFT)
	var off: Vector2 = _centre() + Vector2(300.0, 0.0)  # Not on the ghost.
	assert_bool(_placement.grabs(off)).is_false()
	TouchEvents.press(get_viewport(), 0, off)
	TouchEvents.drag(get_viewport(), 0, finger, finger - off)
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.PAN)
	var held: Vector2 = _camera.position  # The pan moved the camera with the finger.
	_hold(HOLD_FRAMES, FRAME)
	assert_vector(_camera.position).is_equal(held)
	TouchEvents.release(get_viewport(), 0, finger)
	_reset()
	TouchEvents.press(get_viewport(), 0, finger)  # A press in the band, not yet moved.
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.PENDING)
	held = _camera.position
	_hold(HOLD_FRAMES, FRAME)
	assert_vector(_camera.position).is_equal(held)
	TouchEvents.release(get_viewport(), 0, finger)
	assert_array(_sent).is_empty()


## The scroll is distance per second of screen: the same for 60 and 30 frames a second and for
## uneven frames, and the same on screen at the three zoom levels (the world moves 1 / zoom as far).
func test_the_speed_is_the_same_at_any_frame_rate_and_any_zoom() -> void:
	var total: float = HOLD_FRAMES * FRAME
	var finger: Vector2 = _in_band(RIGHT)
	var plans: Array[Array] = [
		[HOLD_FRAMES, FRAME],
		[HOLD_FRAMES / 2, FRAME * 2.0],
		[HOLD_FRAMES * 2, FRAME * 0.5],
		[2, total * 0.5],
	]
	var shifts: Array[Vector2] = []
	for plan: Array in plans:
		_reset()
		_grab_and_drag_to(finger)
		var held: Vector2 = _camera.position
		_hold(plan[0], plan[1])
		shifts.append(_camera.position - held)
		TouchEvents.release(get_viewport(), 0, finger)
	for shift: Vector2 in shifts:
		assert_vector(shift).is_equal_approx(shifts[0], Vector2.ONE * TOLERANCE_PX)
	assert_float(shifts[0].x).is_greater(0.0)
	_reset()
	_grab_and_drag_to(finger)
	_hold(HOLD_FRAMES, 0.0)  # No time, no scroll.
	TouchEvents.release(get_viewport(), 0, finger)
	var levels: PackedFloat32Array = _controller.settings.zoom_levels
	for zoom: float in levels:
		_reset()
		_camera.zoom = Vector2(zoom, zoom)
		_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
		var edge: Vector2 = _in_band(RIGHT)
		_grab_and_drag_to(edge)
		var held: Vector2 = _camera.position
		_hold(HOLD_FRAMES, FRAME)
		var on_screen: float = (_camera.position.x - held.x) * zoom
		assert_float(on_screen).override_failure_message("zoom %s" % zoom).is_equal_approx(
			UiScale.dp(_speed_dp()) * total, TOLERANCE_PX
		)
		TouchEvents.release(get_viewport(), 0, edge)


## A frame that stalled (a hitch, an app coming back) scrolls for `edge_pan_max_step_ms` and no
## longer: half a second in one frame moves the map as far as a tenth of one, not 150 dp at once.
## The longest step is data too.
func test_a_stalled_frame_scrolls_no_further_than_the_longest_step() -> void:
	var tuned: InputSettings = _controller.settings.duplicate()
	_controller.settings = tuned
	var finger: Vector2 = _in_band(RIGHT)
	var step: float = tuned.edge_pan_max_step_ms / 1000.0
	var shifts: Array[float] = []
	for delta: float in [step, step * 5.0, step * 50.0]:
		_reset()
		_grab_and_drag_to(finger)
		var held: float = _camera.position.x
		_hold(1, delta)
		shifts.append(_camera.position.x - held)
		TouchEvents.release(get_viewport(), 0, finger)
	assert_float(shifts[0]).is_greater(0.0)
	assert_float(shifts[1]).is_equal_approx(shifts[0], TOLERANCE_PX)
	assert_float(shifts[2]).is_equal_approx(shifts[0], TOLERANCE_PX)
	var expected: float = UiScale.dp(_speed_dp()) * step / _camera.zoom.x
	assert_float(shifts[0]).is_equal_approx(expected, TOLERANCE_PX)
	# A frame shorter than the step is scrolled whole; a shorter step cuts the stall shorter.
	tuned.edge_pan_max_step_ms = 50
	_reset()
	_grab_and_drag_to(finger)
	var before: float = _camera.position.x
	_hold(1, step * 5.0)
	assert_float(_camera.position.x - before).is_equal_approx(shifts[0] * 0.5, TOLERANCE_PX)
	TouchEvents.release(get_viewport(), 0, finger)


## The dp and the safe area are read when the window changes, not by every frame of a scroll: a
## `UiScale` override put in without a resize is not seen until `read_metrics` (what the resize
## does), which then takes the new bands.
func test_the_metrics_are_read_when_the_window_changes_and_not_every_frame() -> void:
	var band: float = UiScale.dp(_controller.settings.edge_band_dp)
	var finger: Vector2 = Vector2(band + 8.0, UiScale.safe_rect_base().get_center().y)
	assert_vector(_placement.edge_heading(finger)).is_equal(Vector2.ZERO)
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(phone)
	assert_float(UiScale.dp(_controller.settings.edge_band_dp)).is_greater(finger.x)  # A wider band.
	assert_vector(_placement.edge_heading(finger)).is_equal(Vector2.ZERO)  # Not seen yet.
	_placement.read_metrics()
	assert_vector(_placement.edge_heading(finger)).is_equal(LEFT)
	UiScale.clear_override()
	_placement.read_metrics()
	assert_vector(_placement.edge_heading(finger)).is_equal(Vector2.ZERO)
	# A resize reads them by itself.
	get_window().size = ScreenSizes.PORTRAIT[0]
	await await_idle_frame()
	var safe: Rect2 = UiScale.safe_rect_base()
	var narrow: Vector2 = Vector2(safe.end.x - 1.0, safe.get_center().y)
	assert_vector(_placement.edge_heading(narrow)).is_equal(RIGHT)
	get_window().size = ScreenSizes.LANDSCAPE[0]
	await await_idle_frame()
	assert_vector(_placement.edge_heading(narrow)).is_equal(Vector2.ZERO)


## In portrait the build band covers the bottom of the map view, so the bottom band is the strip
## just above it, not the safe area's last 32 dp under it: a drag south scrolls while the ghost is
## still in view above the build band, and a finger at the safe area's bottom edge, deep in the
## band, still scrolls (it has not let go).
func test_in_portrait_the_bottom_band_is_above_the_build_band_and_the_ghost_stays_in_view() -> void:
	for size: Vector2i in ScreenSizes.PORTRAIT:
		get_window().size = size
		await await_idle_frame()
		await await_idle_frame()
		_reset()
		var note: String = str(size)
		var safe: Rect2 = UiScale.safe_rect_base()
		var band: float = UiScale.dp(_controller.settings.edge_band_dp)
		var covered: float = _build_band().position.y
		assert_float(HudLayout.bottom_zone_px()).override_failure_message(note).is_greater(0.0)
		assert_float(covered).override_failure_message(note).is_less(safe.end.y)
		# The old band, the safe area's last 32 dp, lies inside the build band.
		assert_float(safe.end.y - band * 0.5).override_failure_message(note).is_greater(covered)
		var finger: Vector2 = _in_band(DOWN)
		assert_vector(_placement.edge_heading(finger)).override_failure_message(note).is_equal(DOWN)
		var above: Vector2 = Vector2(finger.x, HudLayout.map_bottom_px(safe) - band * 1.5)
		assert_vector(_placement.edge_heading(above)).override_failure_message(note).is_equal(
			Vector2.ZERO
		)
		assert_vector(_placement.edge_heading(Vector2(finger.x, safe.end.y - 1.0))).is_equal(DOWN)
		var start: Vector2 = _camera.position
		_grab_and_drag_to(finger)
		_hold(HOLD_FRAMES, FRAME)
		assert_float(_camera.position.y).override_failure_message(note).is_greater(start.y)
		assert_float(_centre().y).override_failure_message(note).is_less(covered)  # In view.
		TouchEvents.release(get_viewport(), 0, finger)
		assert_float(_centre().y).override_failure_message(note).is_less(covered)  # And stays.
		assert_bool(_placement.active).override_failure_message(note).is_true()
		assert_array(_sent).override_failure_message(note).is_empty()


## With a top cutout the portrait band sits higher than the safe rect's bottom less its height (the
## safe area's margin gives both ends of an axis the larger inset), so P86b's rule put the bottom
## band up to a margin inside the build band. P86c ends it at the band's drawn top,
## `HudLayout.menu_top_px`: a finger half a band above that top scrolls, one a band and a half above
## does not, and the ghost stays in view above the drawn top.
func test_with_a_top_cutout_the_bottom_band_ends_at_the_drawn_top_of_the_build_band() -> void:
	var names: Array[StringName] = [
		&"android_6in_portrait", &"web_phone_portrait", &"desktop_portrait", &"web_tablet_portrait"
	]
	for profile_name: StringName in names:
		var m: UiMetrics = UiProfiles.by_name(profile_name)
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		UiScale.set_override(UiProfiles.with_safe_area(m, cut))
		get_window().size = m.window_size
		await await_idle_frame()
		await await_idle_frame()
		_reset()
		var note: String = str(profile_name)
		var safe: Rect2 = UiScale.safe_rect_base()
		var band: float = UiScale.dp(_controller.settings.edge_band_dp)
		var top: float = _build_band().position.y
		assert_float(HudLayout.menu_top_px).override_failure_message(note).is_equal_approx(top, 1.0)
		# The old rule's bottom lies in the band by the cutout's margin: more than half a band.
		var inside: float = safe.end.y - HudLayout.bottom_zone_px()
		assert_float(inside).override_failure_message(note).is_greater(top + band * 0.5)
		var x: float = safe.get_center().x
		var half: Vector2 = Vector2(x, top - band * 0.5)
		var far: Vector2 = Vector2(x, top - band * 1.5)
		assert_vector(_placement.edge_heading(half)).override_failure_message(note).is_equal(DOWN)
		assert_vector(_placement.edge_heading(far)).override_failure_message(note).is_equal(
			Vector2.ZERO
		)
		assert_vector(_placement.edge_heading(Vector2(x, top + 1.0))).is_equal(DOWN)
		var start: Vector2 = _camera.position
		_grab_and_drag_to(half)
		_hold(HOLD_FRAMES, FRAME)
		assert_float(_camera.position.y).override_failure_message(note).is_greater(start.y)
		assert_float(_centre().y).override_failure_message(note).is_less(top)  # In view.
		TouchEvents.release(get_viewport(), 0, half)


## The band and the speed are data: another `edge_pan_dp_per_s` scrolls at that speed, another
## `edge_band_dp` moves the band.
func test_the_band_and_the_speed_come_from_the_settings() -> void:
	var tuned: InputSettings = _controller.settings.duplicate()
	_controller.settings = tuned
	var finger: Vector2 = _in_band(RIGHT)
	_reset()
	_grab_and_drag_to(finger)
	var held: Vector2 = _camera.position
	_hold(HOLD_FRAMES, FRAME)
	var normal: float = _camera.position.x - held.x
	TouchEvents.release(get_viewport(), 0, finger)
	tuned.edge_pan_dp_per_s = _speed_dp() * 2.0
	_reset()
	_grab_and_drag_to(finger)
	held = _camera.position
	_hold(HOLD_FRAMES, FRAME)
	assert_float(_camera.position.x - held.x).is_equal_approx(normal * 2.0, TOLERANCE_PX)
	TouchEvents.release(get_viewport(), 0, finger)
	# A finger 1.5 bands from the edge is out; with a band twice as wide it is in.
	var safe: Rect2 = UiScale.safe_rect_base()
	var band: float = UiScale.dp(tuned.edge_band_dp)
	var near: Vector2 = Vector2(safe.end.x - band * 1.5, _centre().y)
	assert_vector(_placement.edge_heading(near)).is_equal(Vector2.ZERO)
	tuned.edge_band_dp *= 2.0
	assert_vector(_placement.edge_heading(near)).is_equal(RIGHT)
	tuned.edge_pan_dp_per_s = 0.0  # A speed of nothing is no scroll.
	_reset()
	_grab_and_drag_to(finger)
	held = _camera.position
	_hold(HOLD_FRAMES, FRAME)
	assert_vector(_camera.position).is_equal(held)
	TouchEvents.release(get_viewport(), 0, finger)


## The map ends at the camera's clamp: held there for seconds the camera comes to rest on the
## diamond's edge, and the ghost stays on the tile under the finger.
func test_the_scroll_stops_at_the_cameras_clamp() -> void:
	_reset()
	var finger: Vector2 = _in_band(UP)
	_grab_and_drag_to(finger)
	_hold(60 * 4, FRAME)  # 300 dp a second for four seconds is far past the map's top corner.
	var rest: Vector2 = _camera.position
	_hold(30, FRAME)
	assert_vector(_camera.position).is_equal(rest)
	# On the top-right edge of the diamond, the line y = x / 2 (IsoProjection's 2:1).
	assert_float(rest.y).is_equal_approx(absf(rest.x) * 0.5, 1.0)
	var unclamped: float = UiScale.dp(_speed_dp()) * 4.0
	assert_float(absf(rest.y - IsoProjection.cell_centre_px(HOME.x, HOME.y).y)).is_less(unclamped)
	assert_bool(_placement.active).is_true()
	TouchEvents.release(get_viewport(), 0, finger)
	assert_array(_sent).is_empty()


## The bands lie inside the safe area's edges: with a cutout a finger that is far from the screen's
## edge but in the safe area's band scrolls, and one a band further in does not; the top band is
## the ghost's point's, `ghost_lift_dp` above the finger; the bottom one the finger's.
func test_the_bands_follow_the_safe_area_and_the_top_one_the_ghost() -> void:
	for zone_dp: float in [0.0, HudLayout.BAND_MIN_DP]:
		_bands_follow_the_safe_area(zone_dp)
	HudLayout.menu_top_px = INF
	UiScale.clear_override()
	_placement.read_metrics()


## `zone_dp` is the height of a build band standing on the safe rect's bottom: its top is what the
## sidebar would publish (`HudLayout.menu_top_px`); 0 is no band.
func _bands_follow_the_safe_area(zone_dp: float) -> void:
	for profile_name: StringName in [&"android_6in", &"android_6in_portrait", &"web_tablet"]:
		var m: UiMetrics = UiProfiles.by_name(profile_name)
		if zone_dp > 0.0 and not UiScale.is_portrait_size(m.window_size):
			continue  # Only a portrait screen has a build band.
		var cut: Rect2i = Rect2i(
			CUTOUT_PX, CUTOUT_PX, m.window_size.x - CUTOUT_PX * 2, m.window_size.y - CUTOUT_PX * 2
		)
		UiScale.set_override(UiProfiles.with_safe_area(m, cut))
		_placement.read_metrics()
		var safe: Rect2 = UiScale.safe_rect_base()
		var band: float = UiScale.dp(_controller.settings.edge_band_dp)
		var lift: float = UiScale.dp(_controller.settings.ghost_lift_dp)
		var middle: Vector2 = safe.get_center()
		var note: String = str(profile_name)
		# The portrait build band covers the map view's bottom: its top is where the bottom band ends.
		HudLayout.menu_top_px = INF if zone_dp == 0.0 else safe.end.y - UiScale.dp(zone_dp)
		var floor_y: float = HudLayout.map_bottom_px(safe)
		# Each: the finger, the heading it earns. The cutout is wider than the band on every side.
		var cases: Array[Array] = [
			[Vector2(safe.position.x + band * 0.5, middle.y), LEFT],
			[Vector2(safe.position.x + band * 1.5, middle.y), Vector2.ZERO],
			[Vector2(safe.end.x - band * 0.5, middle.y), RIGHT],
			[Vector2(safe.end.x - band * 1.5, middle.y), Vector2.ZERO],
			[Vector2(middle.x, floor_y - band * 0.5), DOWN],
			[Vector2(middle.x, floor_y - band * 1.5), Vector2.ZERO],
			[Vector2(middle.x, safe.end.y - 1.0), DOWN],
			# The ghost is `lift` above the finger: the top band is that far lower.
			[Vector2(middle.x, safe.position.y + band + lift - 1.0), UP],
			[Vector2(middle.x, safe.position.y + band + lift + 1.0), Vector2.ZERO],
			[Vector2(middle.x, safe.position.y + 1.0), UP],
			# A finger out in the cutout is in the band too.
			[Vector2(1.0, middle.y), LEFT],
			[middle, Vector2.ZERO],
		]
		for entry: Array in cases:
			var at: String = "%s: finger %s" % [note, entry[0]]
			assert_vector(_placement.edge_heading(entry[0])).override_failure_message(at).is_equal(
				entry[1]
			)
		var corner: Vector2 = Vector2(safe.position.x + 1.0, safe.end.y - 1.0)
		(
			assert_vector(_placement.edge_heading(corner))
			. override_failure_message(note)
			. is_equal_approx(Vector2(-1.0, 1.0).normalized(), Vector2.ONE * 0.0001)
		)
		# Without the cutout the same fingers are in the middle of the screen: nowhere near an edge.
		UiScale.set_override(m)
		_placement.read_metrics()
		assert_vector(_placement.edge_heading(cases[1][0])).override_failure_message(note).is_equal(
			Vector2.ZERO
		)


func test_a_turn_during_the_scroll_ends_it_and_queues_no_command_or_hash_change() -> void:
	var idle: Dictionary = await _scroll_run(false)
	assert_int(idle["hash"]).is_not_equal(0)
	var turned: Dictionary = await _scroll_run(true)
	for key: String in ["hash", "commands", "queued", "tile", "active", "reason", "camera"]:
		assert_that(turned[key]).override_failure_message(key).is_equal(idle[key])
	assert_int(turned["commands"]).is_equal(0)
	assert_bool(turned["active"]).is_true()
	assert_vector(turned["camera"]).is_not_equal(IsoProjection.cell_centre_px(HOME.x, HOME.y))


## A new main scene on the phone, the plant built and the mode begun. A finger grabs the ghost and
## rests in the right band while the camera scrolls for 12 frames and the sim plays 30 ticks. Then
## the phone turns to portrait, or, in the run to compare with, the finger lifts there; 12 more
## frames (the finger of the turned run still down: the turn ended its grab, so they scroll
## nothing) and 30 more ticks follow.
func _scroll_run(turn: bool) -> Dictionary:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()
	await _open_main(true)
	CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
	_runner.run_ticks(160)  # The plant takes 150 ticks.
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	var finger: Vector2 = _in_band(RIGHT)
	_grab_and_drag_to(finger)
	_hold(HOLD_FRAMES, FRAME)
	_runner.run_ticks(30)
	if turn:
		var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
		UiScale.set_override(portrait)
		get_window().size = portrait.window_size
		await await_idle_frame()
		await await_idle_frame()
		assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
	else:
		TouchEvents.release(get_viewport(), 0, finger)
	_hold(HOLD_FRAMES, FRAME)
	_runner.run_ticks(30)
	if turn:
		TouchEvents.release(get_viewport(), 0, finger)
		_hold(HOLD_FRAMES, FRAME)
	return {
		"hash": _runner.last_hash,
		"commands": _sent.size(),
		"queued": CommandQueue.pending(),
		"tile": _placement.tile,
		"active": _placement.active,
		"reason": _placement.reason,
		"camera": _camera.position,
	}


## A new main scene in the rig's match, paused, the previous one freed. Its touch input runs only
## when the test says so; the Commands are caught, and passed on to the queue when `submit`.
func _open_main(submit: bool) -> void:
	if is_instance_valid(_main):
		_main.free()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario()
	_runner.paused = true  # Only run_ticks() moves time.
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_touch.set_process(false)  # The frames of the test are the only frames.
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		if submit:
			CommandQueue.submit(command)


## The camera at zoom 1 on HOME, the ghost there, the plant ready and the mode begun afresh.
func _reset() -> void:
	_placement.cancel()
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	_sent.clear()
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()


## A finger down on the ghost's middle and moved to `finger`, which stays down.
func _grab_and_drag_to(finger: Vector2) -> void:
	var from: Vector2 = _centre()
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, finger, finger - from)
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.GRAB)


## `frames` frames of `delta` seconds each.
func _hold(frames: int, delta: float) -> void:
	for _frame: int in frames:
		_touch._process(delta)


## A finger half a band inside the edge `edge` heads for, on the map view (the safe area, less the
## portrait build band at the bottom); the other axis in the middle, where it earns no heading (the
## top band counts from the ghost, `ghost_lift_dp` higher).
func _in_band(edge: Vector2) -> Vector2:
	var safe: Rect2 = UiScale.safe_rect_base()
	var band: float = UiScale.dp(_controller.settings.edge_band_dp)
	var lift: float = UiScale.dp(_controller.settings.ghost_lift_dp)
	var at: Vector2 = safe.get_center() + Vector2(0.0, lift)
	if edge == LEFT:
		at.x = safe.position.x + band * 0.5
	elif edge == RIGHT:
		at.x = safe.end.x - band * 0.5
	elif edge == UP:
		at.y = safe.position.y + band * 0.5 + lift
	else:
		at.y = HudLayout.map_bottom_px(safe) - band * 0.5
	return at


## The build menu's box, base px (the portrait band, or the landscape panel).
func _build_band() -> Rect2:
	return (
		(_main.get_node("Hud").find_child("BuildSidebar", true, false) as Control).get_global_rect()
	)


func _speed_dp() -> float:
	return _controller.settings.edge_pan_dp_per_s


## The screen point of the ghost's footprint centre.
func _centre() -> Vector2:
	var ground: Vector2i = _placement.centre_ground()
	return _camera.world_to_screen(IsoProjection.ground_to_px(ground.x, ground.y))
