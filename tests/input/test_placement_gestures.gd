extends GdUnitTestSuite
## The map's gestures while a building is being placed (plan P86, ADR 0019 section 2, ADR 0023
## section 3), through the real TouchInput, GestureRecognizer, PlayerController and
## PlacementController of the main scene at the six screens (ScreenSizes.ALL), with a fake clock.
## The ghost is the power plant (2x2) of player 1, whose Headquarters stands at tiles 6-8 by 6-8.
## A tap on the ground moves the ghost to the tapped tile (not a tap on the ghost itself), a drag
## that starts within `ghost_grab_dp` of its silhouette moves it, the ghost sitting `ghost_lift_dp`
## above the finger and snapping to tiles, and a drag that starts elsewhere pans the map and leaves
## the ghost. A release alone never places; a hold starts no box; a pinch zooms as ever.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const HOME: Vector2i = Vector2i(11, 7)  ## The tile that holds the middle of the plant at FITS.

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _placement: PlacementController
var _layer: GhostLayer
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
	(_main.get_node("MatchRunner") as MatchRunner).scenario = Rig.scenario()
	add_child(_main)
	await await_idle_frame()
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	Rig.make_ready(_runner.snapshot)
	Rig.explore(_runner.snapshot)
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_layer = _main.get_node("GhostLayer")
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_the_ghost_starts_on_the_tile_under_the_view_centre_and_is_judged_there() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		var note: String = str(size)
		assert_vector(_placement.tile).override_failure_message(note).is_equal(HOME)
		assert_vector(_placement.origin()).override_failure_message(note).is_equal(Rig.FITS)
		assert_vector(_placement.foot).override_failure_message(note).is_equal(Rig.FOOT)
		assert_int(_placement.reason).override_failure_message(note).is_equal(Placement.Reason.OK)
		assert_bool(_placement.active).override_failure_message(note).is_true()
		var cells: Array[Vector2i] = [
			Vector2i(10, 6), Vector2i(11, 6), Vector2i(10, 7), Vector2i(11, 7)
		]
		assert_array(_layer.cells()).override_failure_message(note).contains_exactly(cells)
		assert_that(_layer.tint()).override_failure_message(note).is_equal(GhostLayer.FITS)
		# The picture is on the atlas and rises above the diamond, so the grab area has walls.
		assert_bool(_layer.body_region().has_area()).override_failure_message(note).is_true()
		assert_float(_layer.rise_px()).override_failure_message(note).is_greater(
			float(IsoProjection.HALF_H * 2)
		)


func test_a_tap_on_the_ground_moves_the_ghost_to_that_tile_with_its_verdict() -> void:
	var cases: Array[Array] = [
		[Rig.TOO_FAR, Placement.Reason.TOO_FAR],
		[Rig.ON_THE_HQ, Placement.Reason.GROUND],
		[Rig.FITS + Vector2i(0, 3), Placement.Reason.OK],
	]
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		for entry: Array in cases:
			var origin: Vector2i = entry[0]
			var note: String = "%s %s" % [size, origin]
			_tap(_screen_of(origin + Vector2i.ONE))
			assert_vector(_placement.tile).override_failure_message(note).is_equal(
				origin + Vector2i.ONE
			)
			assert_vector(_placement.origin()).override_failure_message(note).is_equal(origin)
			assert_int(_placement.reason).override_failure_message(note).is_equal(entry[1])
			var red: bool = entry[1] != Placement.Reason.OK
			var tint: Color = GhostLayer.DANGER if red else GhostLayer.FITS
			assert_that(_layer.tint()).override_failure_message(note).is_equal(tint)
			assert_array(_sent).override_failure_message(note).is_empty()  # A tap places nothing.
		_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))


func test_a_tap_on_the_ghost_itself_leaves_it_and_one_just_outside_the_grab_area_moves_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		var note: String = str(size)
		var body: Rect2 = _silhouette()
		_tap(Vector2(body.get_center().x, body.position.y + 4.0))  # On the roof.
		assert_vector(_placement.tile).override_failure_message(note).is_equal(HOME)
		_tap(Vector2(body.end.x - 4.0, body.end.y - 4.0 - body.size.y * 0.3))  # Near a side corner.
		assert_vector(_placement.tile).override_failure_message(note).is_equal(HOME)
		var away: Vector2 = Vector2(
			body.end.x + UiScale.dp(_controller.settings.ghost_grab_dp), 0.0
		)
		# Past the margin, in the strip before the check mark and the X (P86c): the ground to the east.
		_tap(Vector2(away.x + UiScale.dp(GhostControls.RING_GAP_DP) * 0.5, _centre().y))
		assert_vector(_placement.tile).override_failure_message(note).is_not_equal(HOME)


func test_a_drag_that_starts_on_the_silhouette_moves_the_ghost_above_the_finger() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		# Three starts: the middle of the footprint, the roof near its top and the side corner.
		for start_at: int in 3:
			await _placing(size)
			var lift: float = UiScale.dp(_controller.settings.ghost_lift_dp)
			var starts: Array[Vector2] = [
				_centre(), Vector2(_centre().x, _silhouette().position.y + 5.0), _side()
			]
			var target: Vector2i = HOME + Vector2i(3, -2)
			_drag(starts[start_at], _screen_of(target) + Vector2(0.0, lift))
			var note: String = "%s from %s" % [size, starts[start_at]]
			assert_vector(_placement.tile).override_failure_message(note).is_equal(target)
			var origin: Vector2i = target - Vector2i.ONE
			assert_vector(_placement.origin()).override_failure_message(note).is_equal(origin)
			assert_array(_sent).override_failure_message(note).is_empty()


func test_a_drag_that_starts_elsewhere_pans_the_map_and_leaves_the_ghost() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		var note: String = str(size)
		var body: Rect2 = _silhouette()
		var margin: float = UiScale.dp(_controller.settings.ghost_grab_dp)
		var start: Vector2 = Vector2(body.position.x - margin - 12.0, _centre().y)  # West of it.
		var before: Vector2 = _camera.position
		_drag(start, start + Vector2(60.0, 20.0))
		assert_vector(_placement.tile).override_failure_message(note).is_equal(HOME)
		assert_vector(_camera.position).override_failure_message(note).is_equal_approx(
			before - Vector2(60.0, 20.0) / _camera.zoom.x, Vector2.ONE * 0.01
		)
		assert_array(_sent).override_failure_message(note).is_empty()


## The grab area is the silhouette grown by `ghost_grab_dp` on every side: the picture's top, the
## walls, the diamond's lower half, whose two lower edges are measured across (perpendicular), not
## along an axis. A point inside it grabs and one a few px outside does not.
func test_the_grab_area_is_the_silhouette_plus_the_margin_all_round() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		var margin: float = UiScale.dp(_controller.settings.ghost_grab_dp)
		var body: Rect2 = _silhouette()
		var middle: float = _centre().x
		var inside: Array[Vector2] = [
			_centre(),
			Vector2(middle, body.position.y - margin + 3.0),  # Above the roof.
			Vector2(body.position.x - margin + 3.0, _centre().y - 5.0),  # West of the wall.
			Vector2(body.end.x + margin - 3.0, _centre().y - 5.0),
			Vector2(middle, body.end.y + margin - 3.0),  # Below the diamond's bottom corner.
		]
		var outside: Array[Vector2] = [
			Vector2(middle, body.position.y - margin - 6.0),
			Vector2(body.position.x - margin - 6.0, _centre().y - 5.0),
			Vector2(body.end.x + margin + 6.0, _centre().y - 5.0),
			Vector2(middle, body.end.y + margin + 6.0),
			Vector2(body.end.x + margin - 3.0, body.end.y + margin - 3.0),  # The box's corner.
		]
		# Across each lower edge of the diamond, from its middle: 3 px short of the margin, 3 past it.
		var half: Vector2 = (
			Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * (2.0 * _camera.zoom.x)
		)
		for side: float in [-1.0, 1.0]:
			var across: Vector2 = Vector2(side / half.x, 1.0 / half.y).normalized()
			var edge_middle: Vector2 = _centre() + Vector2(side * half.x, half.y) * 0.5
			inside.append(edge_middle + across * (margin - 3.0))
			outside.append(edge_middle + across * (margin + 3.0))
		for point: Vector2 in inside:
			(
				assert_bool(_placement.grabs(point))
				. override_failure_message("%s inside %s" % [size, point])
				. is_true()
			)
		for point: Vector2 in outside:
			(
				assert_bool(_placement.grabs(point))
				. override_failure_message("%s outside %s" % [size, point])
				. is_false()
			)


## What the layer draws for the verdict a tap on the ground gives: the wash and the frame of each
## cell where the plant fits, and the hatch of each cell and the reason's glyph where it does not.
func test_the_ghost_draws_the_hatch_and_the_reasons_glyph_only_where_it_does_not_fit() -> void:
	var cases: Array[Array] = [
		[Rig.FITS + Vector2i(0, 3), Placement.Reason.OK],
		[Rig.TOO_FAR, Placement.Reason.TOO_FAR],
		[Rig.ON_THE_HQ, Placement.Reason.GROUND],
		[Rig.OFF_THE_MAP, Placement.Reason.OUTSIDE],
	]
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		for entry: Array in cases:
			var origin: Vector2i = entry[0]
			var note: String = "%s %s" % [size, origin]
			_camera.centre_on(IsoProjection.cell_centre_px(origin.x + 1, origin.y + 1))
			_tap(_screen_of(origin + Vector2i.ONE))
			await await_idle_frame()
			await await_idle_frame()
			assert_int(_placement.reason).override_failure_message(note).is_equal(entry[1])
			var cells: int = _layer.cells().size()
			assert_int(cells).override_failure_message(note).is_equal(4)
			if entry[1] == Placement.Reason.OK:
				assert_int(_layer.last_marks).override_failure_message(note).is_equal(cells * 2)
				assert_object(_layer.last_glyph).override_failure_message(note).is_null()
			else:
				assert_int(_layer.last_marks).override_failure_message(note).is_equal(cells * 3)
				var key: String = String(Placement.Reason.find_key(entry[1])).to_lower()
				var drawn: Texture2D = _layer.last_glyph
				var path: String = "" if drawn == null else drawn.resource_path
				assert_str(path).override_failure_message(note).is_equal(GhostLayer.GLYPH_ART % key)
		_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))


func test_a_release_alone_never_places_and_a_hold_starts_no_box() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		var note: String = str(size)
		_controller.selection.set_ids(PackedInt32Array([1]))
		_tap(_centre())  # A press and a release on the ghost.
		_drag(_centre(), _centre() + Vector2(40.0, 40.0))  # A drag, lifted where it ended.
		assert_array(_sent).override_failure_message(note).is_empty()
		assert_bool(_placement.active).override_failure_message(note).is_true()
		# A hold on the ground and a drag after it pans: no box, nothing selected, no buzz.
		var from: Vector2 = _centre() + Vector2(-_silhouette().size.x - 100.0, 0.0)
		var before: Vector2 = _camera.position
		TouchEvents.press(get_viewport(), 0, from)
		_now_ms += _touch.settings.long_press_ms + 100
		_touch._process(0.0)  # The frame that sees the hold.
		TouchEvents.drag(get_viewport(), 0, from + Vector2(70.0, 0.0), Vector2(70.0, 0.0))
		TouchEvents.release(get_viewport(), 0, from + Vector2(70.0, 0.0))
		_now_ms += 1000
		assert_vector(_camera.position).override_failure_message(note).is_not_equal(before)
		assert_bool((_main.get_node("Hud/BoxOverlay") as Control).visible).is_false()
		assert_array(_controller.selection.selected).override_failure_message(note).is_equal([1])
		# A hold that does not move is a slow tap: the ghost goes to the tile held.
		var held: Vector2i = HOME + Vector2i(4, 2)
		var at: Vector2 = _screen_of(held)
		TouchEvents.press(get_viewport(), 0, at)
		_now_ms += _touch.settings.long_press_ms + 100
		_touch._process(0.0)
		TouchEvents.release(get_viewport(), 0, at)
		_now_ms += 1000
		assert_vector(_placement.tile).override_failure_message(note).is_equal(held)
		assert_array(_sent).override_failure_message(note).is_empty()


func test_a_pinch_still_zooms_and_a_second_finger_lifts_the_ghost_drag() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _placing(size)
		var note: String = str(size)
		var from: Vector2 = _centre()
		TouchEvents.press(get_viewport(), 0, from)
		TouchEvents.drag(get_viewport(), 0, from + Vector2(30.0, 0.0), Vector2(30.0, 0.0))
		var held: Vector2i = _placement.tile
		TouchEvents.press(get_viewport(), 1, from + Vector2(200.0, 0.0))
		TouchEvents.drag(get_viewport(), 1, from + Vector2(260.0, 0.0), Vector2(60.0, 0.0))
		assert_float(_camera.zoom.x).override_failure_message(note).is_greater(1.0)
		TouchEvents.drag(get_viewport(), 0, from + Vector2(90.0, 40.0), Vector2(60.0, 40.0))
		assert_vector(_placement.tile).override_failure_message(note).is_equal(held)
		TouchEvents.release(get_viewport(), 1, from + Vector2(260.0, 0.0))
		TouchEvents.release(get_viewport(), 0, from + Vector2(90.0, 40.0))
		assert_bool(_placement.active).override_failure_message(note).is_true()
		assert_array(_sent).override_failure_message(note).is_empty()


## The size, the camera at zoom 1 on the middle of the plant's ground at FITS, the plant ready and
## the mode begun.
func _placing(size: Vector2i) -> void:
	get_window().size = size
	await await_idle_frame()
	_placement.cancel()
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	await await_idle_frame()
	_sent.clear()
	var type: int = Rig.plant(_runner.snapshot)
	assert_bool(_placement.begin(type)).override_failure_message(str(size)).is_true()


## The screen point (base px) of the middle of tile `tile`'s diamond.
func _screen_of(tile: Vector2i) -> Vector2:
	return _camera.world_to_screen(IsoProjection.cell_centre_px(tile.x, tile.y))


## The screen point of the ghost's footprint centre.
func _centre() -> Vector2:
	var ground: Vector2i = _placement.centre_ground()
	return _camera.world_to_screen(IsoProjection.ground_to_px(ground.x, ground.y))


## The ghost's silhouette box on the screen: the footprint's width, from the picture's top down to
## the diamond's bottom corner.
func _silhouette() -> Rect2:
	var half: Vector2 = Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * (2.0 * _camera.zoom.x)
	var rise: float = maxf(_layer.rise_px() * _camera.zoom.x, half.y)
	return Rect2(_centre() - Vector2(half.x, rise), Vector2(2.0 * half.x, rise + half.y))


## The diamond's east corner, where a finger is on the silhouette's edge.
func _side() -> Vector2:
	return _centre() + Vector2(IsoProjection.HALF_W * 2.0 * _camera.zoom.x - 3.0, 0.0)


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	_touch._process(0.0)
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## A finger down at `from`, moved to `to` and lifted there.
func _drag(from: Vector2, to: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000
