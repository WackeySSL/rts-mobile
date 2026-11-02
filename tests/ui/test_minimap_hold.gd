extends GdUnitTestSuite
## The minimap's hold (plan P88b, ADR 0019 section 4, ADR 0024 section 5), in the main scene through
## the real GUI at the six sizes of ScreenSizes.ALL with a fake clock. A finger that rests on the
## minimap for `long_press_ms` within `tap_slop_dp` of where it went down, with own units selected,
## sends exactly one MOVE to the ground point under it (the inverse projection, kept inside the
## map as the camera's jump is: a hold beside the diamond orders the nearest point of the map and
## its chevrons are on the screen), with the marker and the buzz of a long-press; the press jumped
## the camera there already, and a resize during the hold does not move the point. A tap, a
## release before the time, a finger that moves beyond the slop first (a drag), a hold with nothing
## or a building selected, one while a strike is aimed or a building placed, one that a focus loss,
## a turn (also when nothing moves the minimap) or the minimap being hidden cut short, and a
## minimap without a controller send nothing, and the camera still jumps. A second finger never
## holds and its tap leaves the first finger's hold alone, a finger that holds again after a
## release orders again, and the hold never collapses the build menu or reaches the map's
## recognizer. The jump itself is test_minimap's, the controller's entry point
## test_player_controller_hold_move's.
## Player 1 has a Headquarters (id 1) and two light tanks (ids 3 and 4) on a 32 x 32 map.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ROSTER: Array = ["power_plant", "barracks", "light_tank"]
const MORE: Array = [["light_tank", 12, 10], ["light_tank", 13, 10]]
const HQ: int = 1
const TANK_A: int = 3
const TANK_B: int = 4
## Ground points (milli-tiles) inside the 32 x 32 map, a good way apart.
const FIRST: Vector2i = Vector2i(21500, 9500)
const SECOND: Vector2i = Vector2i(9500, 22500)
const TOLERANCE: Vector2 = Vector2(0.1, 0.1)

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _minimap: Minimap
var _sidebar: BuildSidebar
var _markers: MoveMarkerLayer
var _now_ms: int = 0
var _sent: Array[Command] = []
var _buzzes: Array[int] = []
var _told: int = 0  ## `map_gesture`s since the scene opened.


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_a_hold_with_units_selected_sends_one_move_to_the_ground_under_the_finger() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var hold_ms: int = _controller.settings.long_press_ms
		_controller.selection.set_ids(PackedInt32Array([TANK_B, TANK_A]))
		var at: Vector2 = _local(FIRST)
		TouchEvents.press(get_viewport(), 0, _global(at))
		# The press jumps the camera and orders nothing.
		assert_vector(_camera.position).override_failure_message(why).is_equal_approx(
			IsoProjection.ground_to_px(FIRST.x, FIRST.y), TOLERANCE
		)
		assert_array(_sent).override_failure_message(why).is_empty()
		_wait(hold_ms - 1)
		assert_array(_sent).override_failure_message(why).is_empty()  # A ms short of the hold.
		_wait(1)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		var move: Command = _sent[0]
		assert_int(move.type).override_failure_message(why).is_equal(Command.Type.MOVE)
		assert_int(move.player_id).override_failure_message(why).is_equal(1)
		assert_array(move.unit_ids).override_failure_message(why).is_equal([TANK_A, TANK_B])
		(
			assert_vector(Vector2i(move.target_x, move.target_y))
			. override_failure_message(why)
			. is_equal(FIRST)
		)
		# Feedback as for a ground tap: the marker, and the buzz of a long-press.
		assert_int(_markers.active_count()).override_failure_message(why).is_equal(1)
		assert_array(_buzzes).override_failure_message(why).is_equal(
			[_controller.settings.haptic_ms]
		)
		# The finger rests on, then lifts: still the one MOVE, and the selection is kept.
		for rest: int in 4:
			_wait(hold_ms)
		TouchEvents.release(get_viewport(), 0, _global(at))
		_wait(hold_ms)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_array(_controller.selection.selected).is_equal([TANK_A, TANK_B])
		# Another finger, another hold: another MOVE, to its own point.
		var elsewhere: Vector2 = _local(SECOND)
		TouchEvents.press(get_viewport(), 0, _global(elsewhere))
		_wait(hold_ms)
		assert_int(_sent.size()).override_failure_message(why).is_equal(2)
		assert_vector(Vector2i(_sent[1].target_x, _sent[1].target_y)).is_equal(SECOND)
		TouchEvents.release(get_viewport(), 0, _global(elsewhere))


## A hold in a corner of the box, beside the diamond, orders the nearest point of the map and not
## the point the inverse projection gives past it: the units go where the camera went, and the
## chevrons are on the map and on the screen.
func test_a_hold_beside_the_diamond_orders_the_nearest_point_of_the_map_where_the_camera_went(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var box: Rect2 = _minimap.box_rect()
		var side: int = 32 * World.MILLI_PER_TILE
		var corners: Array[Vector2] = [
			box.position + Vector2(2.0, 2.0),
			Vector2(box.end.x - 2.0, box.position.y + 2.0),
			box.end - Vector2(2.0, 2.0),
			Vector2(box.position.x + 2.0, box.end.y - 2.0),
		]
		for corner: Vector2 in corners:
			var why: String = "%s, corner %s" % [size, corner]
			_controller.selection.set_ids(PackedInt32Array([TANK_A]))
			_sent.clear()
			_wait(_controller.settings.marker_ms * 2)  # The last corner's chevrons are gone.
			_markers._process(0.0)
			var beyond: Vector2i = _minimap.ground_at(corner)
			var past: bool = beyond.x < 0 or beyond.y < 0 or beyond.x > side or beyond.y > side
			assert_bool(past).override_failure_message("%s: %s" % [why, beyond]).is_true()
			TouchEvents.press(get_viewport(), 0, _global(corner))
			_wait(_controller.settings.long_press_ms)
			assert_int(_sent.size()).override_failure_message(why).is_equal(1)
			var sent: Vector2i = Vector2i(_sent[0].target_x, _sent[0].target_y)
			assert_bool(sent.x >= 0 and sent.y >= 0 and sent.x <= side and sent.y <= side).is_true()
			# It is where the camera went (a milli-tile or two of rounding through the window's px).
			var centre: Vector2i = IsoProjection.px_to_ground(_camera.position)
			assert_int(absi(sent.x - centre.x)).override_failure_message(why).is_less_equal(1)
			assert_int(absi(sent.y - centre.y)).override_failure_message(why).is_less_equal(1)
			var clamped: Vector2i = _minimap.clamped_ground_at(corner)
			assert_int(absi(sent.x - clamped.x)).override_failure_message(why).is_less_equal(2)
			assert_int(absi(sent.y - clamped.y)).override_failure_message(why).is_less_equal(2)
			# The chevrons are at the ordered point, inside what the camera shows.
			var marks: Array[MoveMarkerLayer.Mark] = _shown_marks()
			assert_int(marks.size()).override_failure_message(why).is_equal(1)
			assert_vector(marks[0].position).override_failure_message(why).is_equal_approx(
				IsoProjection.ground_to_px(sent.x, sent.y), Vector2(0.05, 0.05)
			)
			var shown: Rect2 = _camera.visible_world_rect()
			assert_bool(shown.has_point(marks[0].position)).override_failure_message(why).is_true()
			TouchEvents.release(get_viewport(), 0, _global(corner))


## The point is taken at the finger's last event: a resize during the hold changes the minimap's
## layout, and the ordered point stays the one the camera jumped to.
func test_a_resize_during_the_hold_does_not_move_the_ordered_point() -> void:
	var moved: int = 0  # The sizes at which the resize changed what the press point means.
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var hold_ms: int = _controller.settings.long_press_ms
		var same: Array[Vector2i] = (
			ScreenSizes.PORTRAIT if UiScale.is_portrait_size(size) else ScreenSizes.LANDSCAPE
		)
		var other: Vector2i = same[(same.find(size) + 1) % same.size()]  # Not a turn.
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		var at: Vector2 = _local(FIRST)
		TouchEvents.press(get_viewport(), 0, _global(at))
		_wait(hold_ms / 2)
		get_window().size = other
		await _settle()
		_wait(hold_ms)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		var sent: Vector2i = Vector2i(_sent[0].target_x, _sent[0].target_y)
		assert_int(absi(sent.x - FIRST.x)).override_failure_message(why).is_less_equal(2)
		assert_int(absi(sent.y - FIRST.y)).override_failure_message(why).is_less_equal(2)
		var now: Vector2i = _minimap.clamped_ground_at(at)
		if absi(now.x - FIRST.x) > 50 or absi(now.y - FIRST.y) > 50:
			moved += 1
		TouchEvents.release(get_viewport(), 0, _global(at))
	assert_int(moved).is_greater(0)  # The test would pass vacuously if no resize moved it.


func test_a_tap_and_a_drag_send_nothing_and_a_wobble_inside_the_slop_still_holds() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var hold_ms: int = _controller.settings.long_press_ms
		var slop: float = UiScale.dp(_controller.settings.tap_slop_dp)
		_controller.selection.set_ids(PackedInt32Array([TANK_A, TANK_B]))
		var at: Vector2 = _local(FIRST)
		# A tap, and a release a ms before the time, and a release that comes long after the time
		# with no frame between (a release never turns into a hold).
		for ms: int in [0, 50, hold_ms - 1, hold_ms * 4]:
			TouchEvents.press(get_viewport(), 0, _global(at))
			_now_ms += ms
			TouchEvents.release(get_viewport(), 0, _global(at))
			_wait(hold_ms * 2)
			assert_array(_sent).override_failure_message("%s: tap of %d ms" % [why, ms]).is_empty()
		# A drag beyond the slop before the time: the camera follows it, nothing is ordered, however
		# long the finger rests after, and a drag back to the press point does not undo it.
		TouchEvents.press(get_viewport(), 0, _global(at))
		var gone: Vector2 = at + Vector2(slop + 2.0, 0.0)
		TouchEvents.drag(get_viewport(), 0, _global(gone), gone - at)
		assert_vector(_camera.position).override_failure_message(why).is_equal_approx(
			_minimap.centre_for(gone), TOLERANCE
		)
		TouchEvents.drag(get_viewport(), 0, _global(at), at - gone)
		_wait(hold_ms * 3)
		TouchEvents.release(get_viewport(), 0, _global(at))
		assert_array(_sent).override_failure_message(why).is_empty()
		# A wobble inside the slop is still a hold, at the ground point under the finger now.
		TouchEvents.press(get_viewport(), 0, _global(at))
		var wobble: Vector2 = at + Vector2(slop * 0.5, 0.0)
		TouchEvents.drag(get_viewport(), 0, _global(wobble), wobble - at)
		_wait(hold_ms)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		# The finger's position arrives through the window's px, so the point may be a milli-tile off.
		var sent: Vector2i = Vector2i(_sent[0].target_x, _sent[0].target_y)
		var wanted: Vector2i = _minimap.clamped_ground_at(wobble)
		assert_int(absi(sent.x - wanted.x)).override_failure_message(why).is_less_equal(2)
		assert_int(absi(sent.y - wanted.y)).override_failure_message(why).is_less_equal(2)
		# And it is not the press point: the hold goes where the finger is now.
		assert_int(sent.distance_squared_to(_minimap.ground_at(at))).is_greater(1000)
		TouchEvents.release(get_viewport(), 0, _global(wobble))


func test_a_hold_with_nothing_or_a_building_selected_orders_nothing_and_the_camera_jumps() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		for selected: Array in [[], [HQ]]:
			var ids: PackedInt32Array = PackedInt32Array(selected)
			_controller.selection.set_ids(ids)
			_camera.centre_on(Vector2.ZERO)
			var at: Vector2 = _local(FIRST)
			TouchEvents.press(get_viewport(), 0, _global(at))
			_wait(_controller.settings.long_press_ms * 3)
			TouchEvents.release(get_viewport(), 0, _global(at))
			var note: String = "%s, selected %s" % [why, ids]
			assert_array(_sent).override_failure_message(note).is_empty()
			assert_array(_buzzes).override_failure_message(note).is_empty()
			assert_int(_markers.active_count()).override_failure_message(note).is_equal(0)
			assert_array(_controller.selection.selected).override_failure_message(note).is_equal(
				ids
			)
			assert_vector(_camera.position).override_failure_message(note).is_equal_approx(
				IsoProjection.ground_to_px(FIRST.x, FIRST.y), TOLERANCE
			)


## While a strike is aimed or a building placed nothing is ordered (the controller's rule for every
## gesture), so the hold orders nothing either; the view still jumps.
func test_a_hold_while_placing_a_building_or_aiming_a_strike_orders_nothing() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var modes: Dictionary[String, Object] = {
			"placement": _controller.placement, "strike aim": _controller.strike_aim
		}
		for mode: String in modes:
			_controller.selection.set_ids(PackedInt32Array([TANK_A]))
			modes[mode].set("active", true)
			var at: Vector2 = _local(FIRST)
			TouchEvents.press(get_viewport(), 0, _global(at))
			_wait(_controller.settings.long_press_ms * 2)
			TouchEvents.release(get_viewport(), 0, _global(at))
			modes[mode].set("active", false)
			assert_array(_sent).override_failure_message("%s, %s" % [why, mode]).is_empty()
			assert_array(_buzzes).override_failure_message("%s, %s" % [why, mode]).is_empty()
		# Back to normal: the same hold orders.
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(_controller.settings.long_press_ms)
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)


## Only the first finger counts: a second one on the minimap neither jumps nor holds, and its tap
## or its release leaves the first finger's hold alone.
func test_a_second_finger_never_holds_and_its_tap_leaves_the_first_ones_hold_alone() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var hold_ms: int = _controller.settings.long_press_ms
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		# A tap of a second finger before the first one's time is up: the hold still lands.
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(hold_ms / 4)
		TouchEvents.press(get_viewport(), 1, _global(_local(SECOND)))
		TouchEvents.release(get_viewport(), 1, _global(_local(SECOND)))
		_wait(hold_ms - hold_ms / 4)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_vector(Vector2i(_sent[0].target_x, _sent[0].target_y)).is_equal(FIRST)
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
		_sent.clear()
		# A second finger that goes down late and stays: its own time is not up, and it never holds.
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(hold_ms / 2)
		TouchEvents.press(get_viewport(), 1, _global(_local(SECOND)))
		_wait(hold_ms / 2)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_vector(Vector2i(_sent[0].target_x, _sent[0].target_y)).is_equal(FIRST)
		TouchEvents.release(get_viewport(), 1, _global(_local(SECOND)))
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
		# The second finger alone, down while the first is still, holds nothing.
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		TouchEvents.press(get_viewport(), 1, _global(_local(SECOND)))
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
		_wait(hold_ms * 2)
		TouchEvents.release(get_viewport(), 1, _global(_local(SECOND)))
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)


## A finger whose release never comes (the app loses focus) or whose place the turn takes (the
## minimap changes home) holds no more; the next touch holds as usual.
func test_a_focus_loss_and_a_turn_end_a_hold_in_flight() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var hold_ms: int = _controller.settings.long_press_ms
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(hold_ms / 2)
		_minimap.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		_wait(hold_ms * 2)
		assert_array(_sent).override_failure_message(why).is_empty()
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))  # The next touch holds.
		_wait(hold_ms)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
		# The turn: the same phone held the other way.
		var turned: Vector2i = Vector2i(size.y, size.x)
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(hold_ms / 2)
		get_window().size = turned
		await await_idle_frame()
		await await_idle_frame()
		_wait(hold_ms * 2)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		TouchEvents.press(get_viewport(), 0, _global(_local(SECOND)))
		_wait(hold_ms)
		assert_int(_sent.size()).override_failure_message(why).is_equal(2)
		TouchEvents.release(get_viewport(), 0, _global(_local(SECOND)))


## The minimap ends the finger on a turn by itself, not through being moved: with the sidebar not
## holding the node or its slot, nothing reparents or hides it, and the hold still sends no MOVE
## (a turn never issues a Command). Sideways the node stays shown, which isolates the turn.
func test_a_turn_ends_a_hold_when_nothing_moves_the_minimap() -> void:
	var isolated: int = 0  # The turns after which the minimap was still where it was and shown.
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var hold_ms: int = _controller.settings.long_press_ms
		_sidebar.minimap = null
		_sidebar.minimap_slot = null
		var home: Node = _minimap.get_parent()
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(hold_ms / 2)
		get_window().size = Vector2i(size.y, size.x)
		await _settle()
		assert_object(_minimap.get_parent()).override_failure_message(why).is_same(home)
		if _minimap.is_visible_in_tree():
			isolated += 1
		_wait(hold_ms * 2)
		assert_array(_sent).override_failure_message(why).is_empty()
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
	assert_int(isolated).is_greater_equal(ScreenSizes.LANDSCAPE.size())


## A minimap that is hidden, or folded away with its parent, holds no more; shown again, the next
## touch holds as usual.
func test_a_hidden_minimap_holds_no_more() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var hold_ms: int = _controller.settings.long_press_ms
		for hide_parent: bool in [false, true]:
			var why: String = "%s, %s" % [size, "its parent" if hide_parent else "itself"]
			var folded: CanvasItem = _minimap.get_parent() if hide_parent else _minimap
			_sent.clear()
			_controller.selection.set_ids(PackedInt32Array([TANK_A]))
			TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
			_wait(hold_ms / 2)
			folded.visible = false
			assert_bool(_minimap.is_visible_in_tree()).override_failure_message(why).is_false()
			_wait(hold_ms * 2)
			assert_array(_sent).override_failure_message(why).is_empty()
			folded.visible = true
			TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
			TouchEvents.press(get_viewport(), 0, _global(_local(SECOND)))
			_wait(hold_ms)
			assert_int(_sent.size()).override_failure_message(why).is_equal(1)
			TouchEvents.release(get_viewport(), 0, _global(_local(SECOND)))


## A minimap taken out of the tree during the hold (its place is gone) holds no more either.
func test_a_minimap_that_leaves_the_tree_holds_no_more() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var hold_ms: int = _controller.settings.long_press_ms
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(hold_ms / 2)
		var home: Node = _minimap.get_parent()
		home.remove_child(_minimap)
		home.add_child(_minimap)
		_wait(hold_ms * 2)
		assert_array(_sent).override_failure_message(why).is_empty()
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))


func test_without_a_controller_a_hold_orders_nothing_and_the_minimap_still_jumps() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_minimap.controller = null
	_controller.selection.set_ids(PackedInt32Array([TANK_A]))
	TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
	_wait(1000)
	TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
	assert_array(_sent).is_empty()
	assert_vector(_camera.position).is_equal_approx(
		IsoProjection.ground_to_px(FIRST.x, FIRST.y), TOLERANCE
	)


## The minimap is a HUD control: the GUI takes the touch, so the map's recognizer never hears of it
## (no long-press anchor, no box, no `map_gesture`) and the build menu stays open.
func test_the_hold_never_collapses_the_build_menu_or_reaches_the_maps_recognizer() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var overlay: BoxOverlay = _main.find_child("BoxOverlay", true, false) as BoxOverlay
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		TouchEvents.press(get_viewport(), 0, _global(_local(FIRST)))
		_wait(_controller.settings.long_press_ms * 2)
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_int(_told).override_failure_message(why).is_equal(0)
		assert_bool(overlay.is_showing()).override_failure_message(why).is_false()
		TouchEvents.release(get_viewport(), 0, _global(_local(FIRST)))
		_wait(_controller.settings.long_press_ms)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_int(_told).override_failure_message(why).is_equal(0)


## Advances the fake clock and runs the frame of the minimap and of the map's recognizer, as the
## engine does while a finger rests: a touch the GUI did not take would show in `_told`.
func _wait(ms: int) -> void:
	_now_ms += ms
	_touch._process(0.0)
	_minimap._process(0.0)


func _shown_marks() -> Array[MoveMarkerLayer.Mark]:
	var shown: Array[MoveMarkerLayer.Mark] = []
	for mark: MoveMarkerLayer.Mark in _markers.get_children():
		if mark.visible:
			shown.append(mark)
	return shown


func _global(local: Vector2) -> Vector2:
	return _minimap.get_global_rect().position + local


## The minimap's local point of the ground point `ground` (milli-tiles).
func _local(ground: Vector2i) -> Vector2:
	return _minimap.world_to_local(IsoProjection.ground_to_px(ground.x, ground.y))


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size` with the engine's own metrics, paused, with the Commands, the buzzes
## and the map's gestures caught, and every clock the fake one.
func _open(size: Vector2i) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario_for(1, "headquarters", MORE, ROSTER)
	_runner.paused = true
	add_child(_main)
	await _settle()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_markers = _main.get_node("MarkerLayer")
	_minimap = _main.get_node("Hud").find_child("Minimap", true, false)
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_now_ms = 0
	_sent.clear()
	_buzzes.clear()
	_told = 0
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_touch.map_gesture.connect(func() -> void: _told += 1)
	_markers.clock = _touch.clock
	_minimap.clock = _touch.clock
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_camera.zoom = Vector2.ONE
	_camera.centre_on(Vector2.ZERO)
