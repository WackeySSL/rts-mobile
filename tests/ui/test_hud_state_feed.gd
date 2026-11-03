extends GdUnitTestSuite
## The unfold rules of ADR 0025 section 1 against the real gestures (plan P119c), in the main scene
## through the real GUI at the six sizes of ScreenSizes.ALL: a tap, a double-tap, a long-press with
## its box, a pan, a pinch and a wheel step on the map close the drawer, the economy card and the
## unpinned full map and still do their work (a MOVE queued, a selection made, the camera moved); a
## pinned full map stays; a touch on a HUD control closes nothing but the economy card, and the
## touch that closes the card cannot open it again; PAUSE takes every touch; the start of placement
## and of a strike aim fold what a gesture folds; the full map folds after `radar_close_ms` of
## frame time; a turn keeps the state; a new match starts with nothing unfolded. The state's own
## rules on crafted calls are test_hud_state.gd's. Nothing shows the unfolds yet (their rows come
## later), so the tests read `HudStateFeed.state`.
## Player 1 has a Headquarters, two light tanks, a Heavy Yard and a Bunkhouse, and a finished
## structure in its queue.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const ROSTER: Array = ["power_plant", "barracks", "vehicle_factory", "defence_turret", "light_tank"]
const MORE: Array = [
	["light_tank", 12, 10], ["light_tank", 13, 10], ["vehicle_factory", 14, 3], ["barracks", 10, 14]
]
const TANK_A: int = 3
const TANK_B: int = 4
const HOME: Vector2i = Vector2i(11, 7)
const GESTURES: Array[StringName] = [&"tap", &"double_tap", &"box", &"pan", &"pinch", &"wheel"]
## The unfolds a gesture on the map folds.
const FOLDING: Array[HudState.Unfold] = [
	HudState.Unfold.DRAWER, HudState.Unfold.ECONOMY, HudState.Unfold.RADAR
]
## HUD controls of the scene as it stands (the band, the army bar), found by name. The pill's
## numbers are not among them: a tap on them asks for the economy card, and opening an unfold
## closes the open one (test_economy_card.gd has the pill's touches). The scope is left out too:
## a tap on it opens the full map, and the full map's own touches are test_radar_map's.
const CONTROLS: Array[String] = [
	"AllArmy", "Group1", "SelectionPanel", "TabVehicles", "TabStructures"
]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _placement: PlacementController
var _units: UnitLayer
var _feed: HudStateFeed
var _state: HudState
var _pill: EconomyPill
var _now_ms: int = 0
var _sent: Array[Command] = []
var _taps_on_pill: int = 0  ## `economy_pressed`s: each one asks for the card (the pill does that).


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


func test_the_feed_is_in_the_scene_and_a_match_starts_with_nothing_unfolded() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		assert_object(_feed).override_failure_message(why).is_not_null()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_bool(_state.pinned).override_failure_message(why).is_false()
		assert_object(_feed.settings).is_same(_touch.settings)  # The file's table, shared.
		assert_object(_state.settings).is_same(_touch.settings)  # And the state reads that table.
		assert_int(_state.settings.radar_close_ms).is_equal(4000)


func test_each_gesture_on_the_map_closes_the_unfold_and_still_does_its_work() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		for unfold: HudState.Unfold in FOLDING:
			for kind: StringName in GESTURES:
				var why: String = "%s: %d then a %s" % [size, unfold, kind]
				_prepare()
				assert_bool(_state.open(unfold)).override_failure_message(why).is_true()
				var worked: String = _gesture(kind)
				assert_int(_state.current).override_failure_message(why).is_equal(
					HudState.Unfold.NONE
				)
				assert_str(worked).override_failure_message(why).is_empty()


func test_a_pinned_full_map_stays_through_every_gesture_and_the_gesture_works() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		for kind: StringName in GESTURES:
			var why: String = "%s: a %s" % [size, kind]
			_prepare()
			_state.open(HudState.Unfold.RADAR)
			_state.pinned = true
			var worked: String = _gesture(kind)
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
			assert_str(worked).override_failure_message(why).is_empty()
			_state.pinned = false


func test_a_touch_on_a_hud_control_closes_nothing_but_the_economy_card() -> void:
	var panel: BuildSidebar = null
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		panel = _hud("BuildSidebar") as BuildSidebar
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		await _settle()
		for label: String in CONTROLS:
			# Sideways the open full map folds the build panel (P121, one unfold at a time) and the
			# open panel closes the map: the panel is open again for each control, and a control the
			# map has folded away is not there to touch.
			panel.open()
			await _settle()  # The drawer lays itself out when it opens.
			var control: Control = _hud(label) as Control
			var at: Vector2 = control.get_global_rect().get_center()
			for unfold: HudState.Unfold in [HudState.Unfold.DRAWER, HudState.Unfold.RADAR]:
				var why: String = "%s: a tap on %s with %d open" % [size, label, unfold]
				_state.open(unfold)
				# The tabs are the drawer's: with the map open they are hidden, and say so.
				var there: bool = unfold == HudState.Unfold.DRAWER or not label.begins_with("Tab")
				assert_bool(control.is_visible_in_tree()).override_failure_message(why).is_equal(
					there
				)
				if there:
					_tap(at)
					assert_int(_state.current).override_failure_message(why).is_equal(unfold)
			panel.open()
			_state.pinned = true
			_state.open(HudState.Unfold.RADAR)
			var shown: bool = not label.begins_with("Tab")  # The drawer's tabs are folded away.
			assert_bool(control.is_visible_in_tree()).override_failure_message(label).is_equal(
				shown
			)
			if shown:
				_tap(at)
				assert_int(_state.current).is_equal(HudState.Unfold.RADAR)
			_state.pinned = false
			panel.open()
			_state.open(HudState.Unfold.ECONOMY)  # One unfold at a time: the drawer folds.
			if not shown:
				continue  # The drawer's tabs are not there to touch; the next label is.
			_tap(at)
			(
				assert_int(_state.current)
				. override_failure_message("%s: a tap on %s with the card open" % [size, label])
				. is_equal(HudState.Unfold.NONE)
			)
			_state.close(HudState.Unfold.RADAR)
		assert_int(_sent.size()).override_failure_message(str(size)).is_equal(0)  # No order.


## A tap on the pill's numbers while the card shows is the touch that closes it; its release asks
## for the card (the pill's own `economy_pressed` handler, P119b) and the card stays shut. The next
## tap opens it.
func test_a_tap_on_the_pill_while_the_card_shows_only_closes_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_pill.economy_pressed.connect(_on_economy_pressed)
		var at: Vector2 = (_hud("CreditsTap") as Control).get_global_rect().get_center()
		_tap(at)
		assert_int(_taps_on_pill).override_failure_message(why).is_equal(1)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.ECONOMY)
		_tap(at)
		assert_int(_taps_on_pill).override_failure_message(why).is_equal(2)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		_tap(at)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.ECONOMY)
		_tap(_ground())  # And a tap on the map closes it, the pill not involved.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)


## The card is open; a finger goes down on the pill's numbers (the card closes), a second one goes
## down on a HUD control or pans the map, and the first one lifts: the tap asks for the card, and
## the card stays shut. The next first finger opens it.
func test_a_second_finger_cannot_let_the_first_ones_release_reopen_the_card() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		_pill.economy_pressed.connect(_on_economy_pressed)
		var pill: Vector2 = (_hud("CreditsTap") as Control).get_global_rect().get_center()
		var control: Vector2 = (_hud("AllArmy") as Control).get_global_rect().get_center()
		var ground: Vector2 = _ground()
		for second: StringName in [&"a HUD control", &"the map"]:
			var why: String = "%s: the second finger on %s" % [size, second]
			_tap(pill)
			assert_int(_state.current).override_failure_message(why).is_equal(
				HudState.Unfold.ECONOMY
			)
			var taps: int = _taps_on_pill
			TouchEvents.press(get_viewport(), 0, pill)  # The card closes.
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
			if second == &"the map":
				TouchEvents.press(get_viewport(), 1, ground)
				TouchEvents.drag(
					get_viewport(), 1, ground + Vector2(80.0, 30.0), Vector2(80.0, 30.0)
				)
			else:
				TouchEvents.press(get_viewport(), 1, control)
			_now_ms += 50
			TouchEvents.release(get_viewport(), 0, pill)  # The pill's tap: it asks for the card.
			assert_int(_taps_on_pill).override_failure_message(why).is_equal(taps + 1)
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
			TouchEvents.release(get_viewport(), 1, ground if second == &"the map" else control)
			_now_ms += 1000
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
			_tap(pill)  # A new touch opens it again.
			assert_int(_state.current).override_failure_message(why).is_equal(
				HudState.Unfold.ECONOMY
			)
			_tap(ground)
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)


## A focus loss ends every finger: the release of the one that was down may never come, and the
## next finger must still count as the first.
func test_a_focus_loss_forgets_the_fingers_down() -> void:
	await _open(ScreenSizes.LANDSCAPE[1])
	var pill: Vector2 = (_hud("CreditsTap") as Control).get_global_rect().get_center()
	_state.touch_down()
	_state.open(HudState.Unfold.ECONOMY)
	TouchEvents.press(get_viewport(), 0, pill)  # Closes the card; its release is lost.
	assert_int(_state.current).is_equal(HudState.Unfold.NONE)
	_feed.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	TouchEvents.press(get_viewport(), 1, _ground())  # The first finger of a new touch.
	assert_bool(_state.open(HudState.Unfold.ECONOMY)).is_true()
	TouchEvents.release(get_viewport(), 1, _ground())
	TouchEvents.release(get_viewport(), 0, pill)


func test_pause_takes_every_touch() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		_state.open(HudState.Unfold.PAUSE)
		for kind: StringName in GESTURES:
			_prepare()
			_gesture(kind)
			assert_int(_state.current).override_failure_message("%s: a %s" % [size, kind]).is_equal(
				HudState.Unfold.PAUSE
			)
		for label: String in CONTROLS:
			_tap((_hud(label) as Control).get_global_rect().get_center())
			(
				assert_int(_state.current)
				. override_failure_message("%s: a tap on %s" % [size, label])
				. is_equal(HudState.Unfold.PAUSE)
			)
		assert_bool(_state.open(HudState.Unfold.DRAWER)).is_false()
		_state.close(HudState.Unfold.PAUSE)
		assert_int(_state.current).is_equal(HudState.Unfold.NONE)


func test_placement_and_a_strike_aim_that_begin_fold_what_a_gesture_folds() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var aim: StrikeAim = _main.get_node("StrikeAim")
		for unfold: HudState.Unfold in FOLDING:
			_state.open(unfold)
			assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
			(
				assert_int(_state.current)
				. override_failure_message("%s: placement, %d" % [why, unfold])
				. is_equal(HudState.Unfold.NONE)
			)
			_placement.cancel()
			_state.open(unfold)
			aim.owned = true
			aim.building_id = 1
			assert_bool(aim.begin()).is_true()
			(
				assert_int(_state.current)
				. override_failure_message("%s: aim, %d" % [why, unfold])
				. is_equal(HudState.Unfold.NONE)
			)
			aim.cancel()
		_state.open(HudState.Unfold.RADAR)
		_state.pinned = true
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_placement.cancel()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)


## Only the start of a mode folds: `PlacementController.changed` also fires when the ghost is
## judged again and `StrikeAim.changed` when its status moves, and a mode's end opens or folds
## nothing (the drawer's return after placement is P120's, ADR 0024 R1).
func test_only_the_start_of_a_mode_folds_not_its_later_changes_or_its_end() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var aim: StrikeAim = _main.get_node("StrikeAim")
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		_state.open(HudState.Unfold.RADAR)  # Opened during placement.
		_placement.changed.emit()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_state.open(HudState.Unfold.DRAWER)
		_placement.cancel()  # The end of the mode.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.DRAWER)
		_state.close(HudState.Unfold.DRAWER)
		aim.owned = true
		aim.building_id = 1
		assert_bool(aim.begin()).is_true()
		_state.open(HudState.Unfold.RADAR)
		aim.changed.emit()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_state.open(HudState.Unfold.DRAWER)
		aim.cancel()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.DRAWER)


func test_the_full_map_folds_after_radar_close_ms_of_frame_time() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_state.open(HudState.Unfold.RADAR)
		for frame: int in 15:
			_feed._process(0.25)  # 3 750 ms.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_state.touch_radar()  # A touch on the map: the count starts over.
		for frame: int in 15:
			_feed._process(0.25)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_feed._process(0.25)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		_state.open(HudState.Unfold.RADAR)  # Pinned, it does not.
		_state.pinned = true
		for frame: int in 40:
			_feed._process(0.25)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_state.pinned = false


## A turn keeps the state: a finger of the old layout is cancelled, nothing is folded.
func test_a_turn_keeps_the_state_and_the_pin() -> void:
	await _open(ScreenSizes.LANDSCAPE[1])
	var turns: Array[Vector2i] = [ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]]
	for unfold: HudState.Unfold in [
		HudState.Unfold.DRAWER,
		HudState.Unfold.RADAR,
		HudState.Unfold.ECONOMY,
		HudState.Unfold.PAUSE,
	]:
		_state.open(unfold)
		_state.pinned = unfold == HudState.Unfold.RADAR
		for size: Vector2i in turns:
			get_window().size = size
			await _settle()
			(
				assert_int(_state.current)
				. override_failure_message("%d at %s" % [unfold, size])
				. is_equal(unfold)
			)
			assert_bool(_state.pinned).is_equal(unfold == HudState.Unfold.RADAR)
		_state.pinned = false
		_state.close(unfold)


func test_a_new_match_starts_with_nothing_unfolded_and_nothing_pinned() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_state.open(HudState.Unfold.RADAR)
		_state.pinned = true
		_runner.start()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_feed._process(0.0)  # The next frame sees another match_serial.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_bool(_state.pinned).override_failure_message(why).is_false()
		_state.open(HudState.Unfold.DRAWER)
		_feed._process(0.0)  # The same match: nothing to reset.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.DRAWER)


## A new main scene at `size`, the match paused, the Commands caught and the structure ready in the
## published snapshot; the feed's frames run on the test's steps, and so does the touch input's
## clock.
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
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_units = _main.get_node("UnitLayer")
	_feed = _hud("HudStateFeed") as HudStateFeed
	_state = _feed.state
	_feed.set_process(false)
	_pill = _hud("EconomyPill") as EconomyPill
	var instant: InputSettings = _camera.settings.duplicate()  # The snap is a tween on wall time.
	instant.zoom_snap_ms = 0
	_camera.settings = instant
	(_hud("BuildSidebar") as BuildSidebar).set_process(false)
	_now_ms = 0
	_sent.clear()
	_taps_on_pill = 0
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	Rig.make_ready(_runner.snapshot)
	Rig.explore(_runner.snapshot)
	await _settle()


## Counts the taps on the pill's numbers; the pill itself asks for the economy card (P119b).
func _on_economy_pressed() -> void:
	_taps_on_pill += 1


## The selection, the camera and the Commands as a gesture's work expects them, and a finger down
## ahead of the unfold the case opens next (nothing opens the card without a touch of its own).
func _prepare() -> void:
	_state.touch_down()
	_sent.clear()
	_controller.selection.clear()
	_camera.zoom = Vector2.ONE
	_aim_camera(IsoProjection.cell_centre_px(16, 12))
	_state.pinned = false


## Makes gesture `kind` on the map and returns what its own work missed, or "" when it was done.
func _gesture(kind: StringName) -> String:
	var ground: Vector2 = _view_point()
	var missed: String = "no such gesture"
	var zoom: float = _camera.zoom.x
	var at: Vector2 = _camera.position
	match kind:
		&"tap":  # With a tank selected, a tap on the ground orders it there.
			_controller.selection.set_ids(PackedInt32Array([TANK_A]))
			_tap(ground)
			var moved: bool = _sent.size() == 1 and _sent[0].type == Command.Type.MOVE
			missed = "" if moved else "no MOVE: %d Commands" % _sent.size()
		&"double_tap":  # On a tank: every tank of the type on screen.
			_double_tap(_tank_at(TANK_A))
			var both: bool = _controller.selection.selected == PackedInt32Array([TANK_A, TANK_B])
			missed = "" if both else "selected %s" % _controller.selection.selected
		&"box":  # A box with no tank in it: the selection is cleared.
			_controller.selection.set_ids(PackedInt32Array([TANK_A]))
			_box(ground, ground + Vector2(60.0, 40.0))
			var cleared: bool = _controller.selection.selected.is_empty()
			missed = "" if cleared else "selected %s" % _controller.selection.selected
		&"pan":
			_drag(ground, Vector2(80.0, 30.0))
			missed = "" if _camera.position != at else "the camera did not move"
		&"pinch":
			_pinch(ground, 100.0, 150.0)
			missed = "" if _camera.zoom.x != zoom else "the zoom did not change"
		&"wheel":
			TouchEvents.wheel(get_viewport(), MOUSE_BUTTON_WHEEL_UP, ground)
			missed = "" if _camera.zoom.x != zoom else "the zoom did not change"
	return missed


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


func _double_tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 100
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## Holds the long-press time at `from`, drags to `to` and lets go.
func _box(from: Vector2, to: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	_now_ms += _touch.settings.long_press_ms
	_touch._process(0.0)
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	TouchEvents.release(get_viewport(), 0, to)
	_now_ms += 1000


func _drag(from: Vector2, by: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, from + by, by)
	TouchEvents.release(get_viewport(), 0, from + by)
	_now_ms += 1000


## Two fingers `from_half` px either side of `centre` move to `to_half` px, one after the other.
func _pinch(centre: Vector2, from_half: float, to_half: float) -> void:
	var left: Vector2 = centre - Vector2(from_half, 0.0)
	var right: Vector2 = centre + Vector2(from_half, 0.0)
	TouchEvents.press(get_viewport(), 0, left)
	TouchEvents.press(get_viewport(), 1, right)
	var left_to: Vector2 = centre - Vector2(to_half, 0.0)
	var right_to: Vector2 = centre + Vector2(to_half, 0.0)
	TouchEvents.drag(get_viewport(), 0, left_to, left_to - left)
	TouchEvents.drag(get_viewport(), 1, right_to, right_to - right)
	TouchEvents.release(get_viewport(), 1, right_to)
	TouchEvents.release(get_viewport(), 0, left_to)
	_now_ms += 1000


## Where unit `id` is on the screen, with the camera on it.
func _tank_at(id: int) -> Vector2:
	var row: int = _runner.snapshot.index_of(id)
	_aim_camera(_camera.screen_to_world(_units.unit_screen_position(row)))
	return _units.unit_screen_position(row)


## A ground point clear of the HUD and of the buildings, at the middle of the view.
## Where the camera's aim is held: the middle of the screen, and upright the middle of the upper
## half, because the open drawer is a sheet over the lower half.
func _view_point() -> Vector2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(size.x * 0.5, size.y * (0.25 if HudLayout.is_portrait() else 0.5))


## Centres the camera on `world` so that it shows at `_view_point()`.
func _aim_camera(world: Vector2) -> void:
	_camera.centre_on(world)
	if HudLayout.is_portrait():
		_camera.position.y += get_viewport().get_visible_rect().size.y * 0.25 / _camera.zoom.y


func _ground() -> Vector2:
	_aim_camera(IsoProjection.cell_centre_px(16, 12))
	return _view_point()


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _settle() -> void:
	await await_idle_frame()
