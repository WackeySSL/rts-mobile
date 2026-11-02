extends GdUnitTestSuite
## The full radar map under the scope (plan P121, ADR 0025 sections 1, 2 and 7), in the main scene
## at the six sizes of ScreenSizes.ALL and at every profile of both orientations, also with a
## cutout: it unfolds under the scope, right-aligned, or left of the right column on a screen too
## short for a 96 dp box, with a 48 dp head (the title, the pin and the collapse button, 48 dp
## each) and the moved `Minimap` node in the box under it (ADR 0025 section 2's table of numbers
## on the phone profiles); the pin keeps it open through every gesture and the timer and lasts for
## the match (its glyph shows at every opening); the collapse button folds it at once; unpinned it
## folds `radar_close_ms` of stepped frame time after the last touch on it, a touch restarts the
## count and a finger held still on it (which sends no event) keeps it open; the unfold rules
## through `HudState` (one at a time, a gesture on the map closes it and still does its work, a
## touch on a HUD control or on the map itself closes nothing); P88's tap, drag and hold on the
## moved node; and the pinned map is an island that the placement buttons keep clear of
## (`GhostControls.clear_of`).
## The scope that opens it is test_radar_scope's, the state's own rules are test_hud_state's.
## Player 1 has a Headquarters, two light tanks, a Heavy Yard and a Bunkhouse.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const BuildingRig: GDScript = preload("res://tests/view/support/building_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const RadarRig: GDScript = preload("res://tests/ui/support/radar_rig.gd")
const ICONS: String = "res://assets/art/svg/icons/%s.svg"
const ROSTER: Array = ["power_plant", "barracks", "vehicle_factory", "defence_turret", "light_tank"]
const MORE: Array = [
	["light_tank", 12, 10], ["light_tank", 13, 10], ["vehicle_factory", 14, 3], ["barracks", 10, 14]
]
const TANK_A: int = 3
## A match where player 1 owns a Deep Bore: the strike button stands at the top, left of the scope,
## until P120c moves it above BUILD.
const STRIKE_SPAWNS: Array[Array] = [
	[1, "fossil_strike", 6, 6], [1, "light_tank", 14, 14], [2, "renew_hq", 20, 20]
]
const HOME: Vector2i = Vector2i(11, 7)
const CLOSE_MS: float = 4000.0
const STEP_S: float = 0.25
const TOLERANCE_PX: float = 1.5
## ADR 0025 section 2's table on the profiles it names: the full map's size in dp (head and box)
## and its distance under the safe rect's top, with no strike button.
const TABLE_DP: Dictionary[String, Vector2] = {
	"web_phone_small": Vector2(192.0, 144.0),
	"web_phone": Vector2(240.0, 168.0),
	"android_6in": Vector2(240.0, 168.0),
	"web_phone_portrait": Vector2(260.0, 178.0),
}
const TABLE_TOP_DP: float = 64.0

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _placement: PlacementController
var _feed: HudStateFeed
var _state: HudState
var _scope: RadarScope
var _map: RadarMap
var _minimap: Minimap
var _now_ms: int = 0
var _sent: Array[Command] = []
var _told: int = 0  ## `map_gesture`s.


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


func test_the_full_map_stands_under_the_scope_with_a_48_dp_head_at_every_screen() -> void:
	for screen: Dictionary in RadarRig.screens():
		await _open(screen["size"], screen["metrics"])
		assert_bool(_map.is_visible_in_tree()).is_false()  # Folded away until the scope's tap.
		assert_bool(_minimap.is_visible_in_tree()).is_false()
		_state.open(HudState.Unfold.RADAR)
		await _settle()
		var why: String = str(screen["label"])
		var expected: Dictionary[StringName, Rect2] = RadarRig.rects(get_viewport(), true)
		var map: Rect2 = _map.get_global_rect()
		var head: Rect2 = _rect("MapHead")
		var box: Rect2 = _minimap.get_global_rect()
		var scope: Rect2 = _scope.get_global_rect()
		var edge: Rect2 = SafeAreaMargin.rect_inside(
			get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
		)
		var at: String = "%s: map %s, head %s, box %s, scope %s" % [why, map, head, box, scope]
		assert_bool(_map.is_visible_in_tree()).override_failure_message(at).is_true()
		assert_bool(_minimap.is_visible_in_tree()).override_failure_message(at).is_true()
		for pair: Array in [
			[map, expected[HudCorners.MAP]],
			[head, expected[HudCorners.MAP_HEAD]],
			[box, expected[HudCorners.MAP_BOX]],
		]:
			assert_vector((pair[0] as Rect2).position).override_failure_message(at).is_equal_approx(
				(pair[1] as Rect2).position, Vector2.ONE * TOLERANCE_PX
			)
			assert_vector((pair[0] as Rect2).size).override_failure_message(at).is_equal_approx(
				(pair[1] as Rect2).size, Vector2.ONE * TOLERANCE_PX
			)
		# Under the scope, right-aligned with it, a gap below it; inside the safe area.
		assert_float(map.end.x).override_failure_message(at).is_equal_approx(
			scope.end.x, TOLERANCE_PX
		)
		assert_float(map.position.y).override_failure_message(at).is_equal_approx(
			scope.end.y + UiScale.dp(8.0), TOLERANCE_PX
		)
		assert_bool(UiScale.safe_rect_base().encloses(map)).override_failure_message(at).is_true()
		assert_bool(map.intersects(scope)).override_failure_message(at).is_false()
		assert_bool(map.intersects(_rect("EconomyPill"))).override_failure_message(at).is_false()
		# The head is 48 dp high over the box, the box a 2:1 rectangle at least 96 dp high and at
		# most 240 x 120 dp (260 x 130 upright), and the moved node's own box fills it.
		assert_float(head.size.y).override_failure_message(at).is_equal_approx(
			UiScale.dp(48.0), TOLERANCE_PX
		)
		assert_float(head.end.y).override_failure_message(at).is_equal_approx(
			box.position.y, TOLERANCE_PX
		)
		assert_float(box.size.x).override_failure_message(at).is_equal_approx(
			box.size.y * 2.0, TOLERANCE_PX
		)
		assert_float(box.size.y).override_failure_message(at).is_greater_equal(
			UiScale.dp(96.0) - TOLERANCE_PX
		)
		var cap: Vector2 = (
			HudCorners.MAP_BOX_PORTRAIT_DP if HudLayout.is_portrait() else (HudCorners.MAP_BOX_DP)
		)
		assert_float(box.size.y).override_failure_message(at).is_less_equal(
			UiScale.dp(cap.y) + TOLERANCE_PX
		)
		assert_vector(_minimap.box_rect().size).override_failure_message(at).is_equal_approx(
			_minimap.size, Vector2.ONE * 0.01
		)
		_expect_head(why, head)
		if TABLE_DP.has(why):
			var table: Vector2 = TABLE_DP[why] * UiScale.base_px_per_dp()
			# The safe rect's margin rounds to whole px, which moves the box by a fraction of a dp.
			assert_vector(map.size).override_failure_message(at).is_equal_approx(
				table, Vector2.ONE * UiScale.dp(1.0)
			)
			(
				assert_float(map.position.y - edge.position.y)
				. override_failure_message(at)
				. is_equal_approx(UiScale.dp(TABLE_TOP_DP), TOLERANCE_PX)
			)
		_state.close(HudState.Unfold.RADAR)


## ADR 0025 section 2's second place: where the room under the scope down to the next part of the
## right column cannot hold the head and a 96 dp box, the map stands left of the column with its top
## at the safe top, a gap clear of the scope and the column.
func test_on_a_short_screen_the_full_map_stands_left_of_the_right_column() -> void:
	var short: UiMetrics = RadarRig.short_landscape()
	await _open(short.window_size, short)
	_state.open(HudState.Unfold.RADAR)
	await _settle()
	var expected: Dictionary[StringName, Rect2] = RadarRig.rects(get_viewport(), true)
	var map: Rect2 = _map.get_global_rect()
	var box: Rect2 = _minimap.get_global_rect()
	var edge: Rect2 = SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	var why: String = "map %s, box %s, safe %s" % [map, box, edge]
	assert_vector(map.position).override_failure_message(why).is_equal_approx(
		expected[HudCorners.MAP].position, Vector2.ONE * TOLERANCE_PX
	)
	assert_vector(box.size).override_failure_message(why).is_equal_approx(
		expected[HudCorners.MAP_BOX].size, Vector2.ONE * TOLERANCE_PX
	)
	assert_float(map.position.y).override_failure_message(why).is_equal_approx(
		edge.position.y, TOLERANCE_PX
	)
	assert_float(box.size.x).override_failure_message(why).is_equal_approx(
		UiScale.dp(HudCorners.MAP_BOX_DP.x), TOLERANCE_PX
	)
	assert_float(box.size.y).override_failure_message(why).is_equal_approx(
		UiScale.dp(HudCorners.MAP_BOX_DP.y), TOLERANCE_PX
	)
	# Left of the right column (the strike button's 72 dp and a gap), clear of the scope.
	assert_float(map.end.x).override_failure_message(why).is_less_equal(
		edge.end.x - UiScale.dp(HudCorners.GAP_DP + StrikeButton.SIZE_DP) + TOLERANCE_PX
	)
	assert_bool(map.intersects(_scope.get_global_rect())).override_failure_message(why).is_false()
	assert_bool(UiScale.safe_rect_base().encloses(map)).override_failure_message(why).is_true()
	_expect_head("short screen", _rect("MapHead"))


## A turn keeps the map open and moves it to the other layout's place.
func test_a_turn_keeps_the_map_open_and_puts_it_in_the_other_layouts_place() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	_state.open(HudState.Unfold.RADAR)
	for turn: UiMetrics in [portrait, landscape, portrait, landscape]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		var why: String = str(turn.window_size)
		var expected: Dictionary[StringName, Rect2] = RadarRig.rects(get_viewport(), true)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_bool(_minimap.is_visible_in_tree()).override_failure_message(why).is_true()
		assert_object(_hud("Minimap")).override_failure_message(why).is_same(_minimap)
		(
			assert_vector(_minimap.get_global_rect().position)
			. override_failure_message(why)
			. is_equal_approx(expected[HudCorners.MAP_BOX].position, Vector2.ONE * TOLERANCE_PX)
		)
		(
			assert_vector(_minimap.get_global_rect().size)
			. override_failure_message(why)
			. is_equal_approx(expected[HudCorners.MAP_BOX].size, Vector2.ONE * TOLERANCE_PX)
		)


func test_the_head_says_radar_and_the_pin_shows_its_state() -> void:
	await _open(ScreenSizes.LANDSCAPE[0])
	_state.open(HudState.Unfold.RADAR)
	await _settle()
	assert_str((_hud("MapTitle") as Label).text).is_equal("RADAR")
	for label: Node in _map.find_children("*", "Label", true, false):
		var words: String = (label as Label).text.to_upper()
		assert_bool("ONLINE" in words or "OFFLINE" in words).is_false()  # Never offline.
	assert_str(_pin().icon.resource_path).is_equal(ICONS % "glyph_pin_off")
	assert_str(_collapse().icon.resource_path).is_equal(ICONS % "glyph_collapse")
	_state.pinned = true
	assert_str(_pin().icon.resource_path).is_equal(ICONS % "glyph_pin")
	_state.pinned = false
	assert_str(_pin().icon.resource_path).is_equal(ICONS % "glyph_pin_off")


## The pin keeps the map open through every gesture on the map and the timer, the collapse button
## folds even a pinned map, the pin outlives that and shows at the next opening, and a new match
## takes it away.
func test_the_pin_keeps_the_map_open_and_lasts_for_the_match() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_feed.set_process(false)
		_state.open(HudState.Unfold.RADAR)
		await _settle()
		_tap(_pin().get_global_rect().get_center())  # The pin goes on.
		assert_bool(_state.pinned).override_failure_message(why).is_true()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_str(_pin().icon.resource_path).is_equal(ICONS % "glyph_pin")
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		_tap(_ground())  # A gesture on the map still orders, and the map stays.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
		for step: int in 40:  # Ten seconds.
			_feed._process(STEP_S)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_tap(_collapse().get_global_rect().get_center())  # The button folds a pinned map.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_bool(_state.pinned).override_failure_message(why).is_true()
		assert_bool(_map.is_visible_in_tree()).override_failure_message(why).is_false()
		_tap(_scope.get_global_rect().get_center())  # And the next opening shows the pin as it is.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_str(_pin().icon.resource_path).override_failure_message(why).is_equal(
			ICONS % "glyph_pin"
		)
		_state.open(HudState.Unfold.DRAWER)  # Another unfold closes it too; the pin stays.
		_state.open(HudState.Unfold.RADAR)
		assert_str(_pin().icon.resource_path).is_equal(ICONS % "glyph_pin")
		_tap(_pin().get_global_rect().get_center())  # Tapped again, it comes off and the map stays.
		assert_bool(_state.pinned).override_failure_message(why).is_false()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_str(_pin().icon.resource_path).is_equal(ICONS % "glyph_pin_off")
		_tap(_pin().get_global_rect().get_center())
		_runner.start()  # A new match: nothing pinned, nothing unfolded.
		_feed._process(0.0)
		assert_bool(_state.pinned).override_failure_message(why).is_false()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		_state.open(HudState.Unfold.RADAR)
		assert_str(_pin().icon.resource_path).is_equal(ICONS % "glyph_pin_off")


func test_the_collapse_button_folds_the_map_at_once_and_orders_nothing() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		_state.open(HudState.Unfold.RADAR)
		await _settle()
		_tap(_collapse().get_global_rect().get_center())
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_bool(_map.visible).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).is_empty()
		assert_int(_told).override_failure_message(why).is_equal(0)
		assert_array(_controller.selection.selected).is_equal([TANK_A])


## Unpinned, the map folds `radar_close_ms` of frame time after it opened or was last touched, a
## touch on the map or on its head starts the count over, and so does a touch on the pin.
func test_an_unpinned_map_folds_after_radar_close_ms_and_a_touch_starts_the_count_over() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_feed.set_process(false)
		_state.open(HudState.Unfold.RADAR)
		await _settle()
		_step(3750.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_tap((_hud("MapTitle") as Control).get_global_rect().get_center())  # The head.
		_step(3750.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_tap(_minimap.get_global_rect().get_center())  # The box: the camera jumps, the map stays.
		_step(3750.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_tap(_pin().get_global_rect().get_center())  # The pin: it is a touch on the map too.
		_tap(_pin().get_global_rect().get_center())
		_step(CLOSE_MS - STEP_S * 1000.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_step(STEP_S * 1000.0)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_bool(_map.visible).override_failure_message(why).is_false()
		assert_int(_told).override_failure_message(why).is_equal(0)  # The touches were the map's own.


## A finger held still on the map or its head sends no event, so the count would run out under it:
## every frame it stays down is a touch. Its lift starts the count over; a finger that went down
## elsewhere is not counted; a cancelled one is not counted any more.
func test_a_finger_held_still_on_the_map_keeps_it_open_and_its_lift_starts_the_count() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		_feed.set_process(false)
		_minimap.clock = func() -> int: return _now_ms
		for place: String in ["the box", "the head"]:
			var why: String = "%s: a finger held on %s" % [size, place]
			_state.open(HudState.Unfold.RADAR)
			await _settle()  # The head's row is laid out in the frame after it shows.
			var at: Vector2 = (
				_minimap.get_global_rect().get_center()
				if place == "the box"
				else (_hud("MapTitle") as Control).get_global_rect().get_center()
			)
			assert_bool(_map.is_processing()).override_failure_message(why).is_false()  # At rest.
			TouchEvents.press(get_viewport(), 0, at)
			assert_bool(_map.is_processing()).override_failure_message(why).is_true()
			for frame: int in 40:  # Ten seconds without one event, in either order of the nodes.
				if place == "the box":
					_feed._process(STEP_S)
					_map._process(STEP_S)
				else:
					_map._process(STEP_S)
					_feed._process(STEP_S)
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
			TouchEvents.release(get_viewport(), 0, at)
			assert_bool(_map.is_processing()).override_failure_message(why).is_false()
			_step(3750.0)  # The count starts at the lift.
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
			_step(STEP_S * 1000.0)
			assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		# A finger that went down on the ground is not the map's, and a cancelled one stops counting.
		_state.open(HudState.Unfold.RADAR)
		TouchEvents.press(get_viewport(), 1, _ground())
		assert_bool(_map.is_processing()).is_false()
		TouchEvents.release(get_viewport(), 1, _ground())
		TouchEvents.press(get_viewport(), 0, _minimap.get_global_rect().get_center())
		_map.cancel_gestures()
		assert_bool(_map.is_processing()).is_false()
		_step(CLOSE_MS)
		assert_int(_state.current).is_equal(HudState.Unfold.NONE)
		TouchEvents.release(get_viewport(), 0, _minimap.get_global_rect().get_center())


## One unfold at a time; a gesture on the map closes the map and still does its work; a touch on a
## HUD control or on the map itself closes nothing; PAUSE takes the map away and keeps it shut.
func test_the_unfold_rules_through_the_state() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_tap(_scope.get_global_rect().get_center())
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		_tap(_hud("AllArmy").get_global_rect().get_center())  # A HUD control.
		_tap(_minimap.get_global_rect().get_center())  # And the map itself: the camera jumps.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		assert_int(_told).override_failure_message(why).is_equal(0)
		for other: HudState.Unfold in [HudState.Unfold.DRAWER, HudState.Unfold.ECONOMY]:
			_state.open(other)  # One at a time: the map is folded away, its parts hidden.
			assert_bool(_map.is_visible_in_tree()).override_failure_message(why).is_false()
			assert_bool(_minimap.is_visible_in_tree()).override_failure_message(why).is_false()
			_state.open(HudState.Unfold.RADAR)
			assert_bool(_map.is_visible_in_tree()).override_failure_message(why).is_true()
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		_sent.clear()
		_tap(_ground())  # A tap on the ground: the map closes, the tank moves.
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.NONE)
		assert_bool(_map.visible).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
		assert_int(_told).override_failure_message(why).is_equal(1)
		_state.open(HudState.Unfold.RADAR)
		_state.open(HudState.Unfold.PAUSE)
		assert_bool(_map.visible).override_failure_message(why).is_false()
		assert_bool(_state.open(HudState.Unfold.RADAR)).override_failure_message(why).is_false()
		assert_bool(_map.visible).override_failure_message(why).is_false()
		_state.close(HudState.Unfold.PAUSE)


## P88's and P88b's gestures on the moved node: a tap and a drag jump the camera to the ground
## point under the finger, a hold with units selected sends one MOVE to the point the view went to.
func test_the_maps_tap_drag_and_hold_work_on_the_moved_node() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_minimap.clock = func() -> int: return _now_ms
		_state.open(HudState.Unfold.RADAR)
		await _settle()
		var first: Vector2i = Vector2i(12000, 10000)
		var second: Vector2i = Vector2i(20000, 18000)
		_tap(_where(first))  # A tap jumps.
		assert_vector(_camera.position).override_failure_message(why).is_equal_approx(
			IsoProjection.ground_to_px(first.x, first.y), Vector2.ONE * 0.1
		)
		TouchEvents.press(get_viewport(), 0, _where(first))  # A drag goes on jumping.
		TouchEvents.drag(get_viewport(), 0, _where(second), _where(second) - _where(first))
		assert_vector(_camera.position).override_failure_message(why).is_equal_approx(
			IsoProjection.ground_to_px(second.x, second.y), Vector2.ONE * 0.1
		)
		TouchEvents.release(get_viewport(), 0, _where(second))
		assert_array(_sent).override_failure_message(why).is_empty()  # Nothing was ordered.
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		TouchEvents.press(get_viewport(), 0, _where(first))  # A hold with a tank selected.
		_now_ms += _controller.settings.long_press_ms
		_minimap._process(0.0)
		TouchEvents.release(get_viewport(), 0, _where(first))
		assert_array(_sent).override_failure_message(why).has_size(1)
		assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)


## Until P120c the strike button stands on the top line, left of the scope, 72 dp high, and the full
## map starts 64 dp below the top: the open map covers the foot of the button (8 dp) and nothing of
## its middle, and the button's 64 dp stay tappable. Upright the button stands at the right edge
## above the army bar, far from the map.
func test_with_a_strike_building_the_open_map_covers_only_the_foot_of_the_button_in_landscape(
) -> void:
	var spawns: Array[SpawnDef] = []
	for entry: Array in STRIKE_SPAWNS:
		spawns.append(BuildingRig.spawn(entry[0], entry[1], entry[2], entry[3]))
	for screen: UiMetrics in [
		UiProfiles.by_name(&"android_6in"),
		UiProfiles.by_name(&"web_phone"),
		UiProfiles.by_name(&"web_phone_small"),
		UiProfiles.by_name(&"android_6in_portrait"),
	]:
		await _open(screen.window_size, screen, BuildingRig.scenario(spawns))
		_state.open(HudState.Unfold.RADAR)
		await _settle()
		var button: Rect2 = _rect("StrikeButton")
		var map: Rect2 = _map.get_global_rect()
		var why: String = "%s: button %s, map %s" % [screen.window_size, button, map]
		assert_bool((_hud("StrikeButton") as Control).is_visible_in_tree()).is_true()
		assert_bool(map.has_point(button.get_center())).override_failure_message(why).is_false()
		if HudLayout.is_portrait():
			assert_bool(button.intersects(map)).override_failure_message(why).is_false()
		else:
			var covered: float = button.intersection(map).size.y
			assert_float(covered).override_failure_message(why).is_less_equal(
				UiScale.dp(8.0) + TOLERANCE_PX
			)


## The pinned map is an island the check mark and the X keep clear of (ADR 0025 section 6): the
## scene lists both parts of the radar, and with the map pinned beside the ghost the buttons leave
## the side the map is on; without the entry they would stand on the map.
func test_the_pinned_map_is_an_island_the_placement_buttons_keep_clear_of() -> void:
	var ghost: GhostControls = null
	for orientation: UiMetrics in [
		UiProfiles.by_name(&"android_6in"), UiProfiles.by_name(&"android_6in_portrait")
	]:
		await _open(orientation.window_size, orientation)
		ghost = _main.get_node("Hud/GhostControls") as GhostControls
		var why: String = str(orientation.window_size)
		assert_bool(ghost.clear_of.has(_scope)).override_failure_message(why).is_true()
		assert_bool(ghost.clear_of.has(_map)).override_failure_message(why).is_true()
		Rig.make_ready(_runner.snapshot)
		_state.open(HudState.Unfold.RADAR)
		_state.pinned = true
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		assert_int(_state.current).override_failure_message(why).is_equal(HudState.Unfold.RADAR)
		# The ghost beside the map, so that the column on its right would stand on it.
		var map: Rect2 = _map.get_global_rect()
		var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
		tap.position = Vector2(map.position.x - UiScale.dp(70.0), map.get_center().y)
		_controller.handle_gesture(tap)
		await _settle()
		var group: Rect2 = _rect("PlaceConfirm").merge(_rect("PlaceCancel"))
		var at: String = "%s: buttons %s, map %s" % [why, group, map]
		assert_bool(group.intersects(map)).override_failure_message(at).is_false()
		var listed: Array[Control] = ghost.clear_of.duplicate()
		ghost.clear_of.erase(_map)  # Without the entry the column stands on the map.
		await _settle()
		group = _rect("PlaceConfirm").merge(_rect("PlaceCancel"))
		assert_bool(group.intersects(map)).override_failure_message(at + " (unlisted)").is_true()
		ghost.clear_of = listed
		_placement.cancel()
		_state.pinned = false


## The pin and the collapse button are 48 dp each, inside the head, the collapse button at its end.
func _expect_head(why: String, head: Rect2) -> void:
	var pin: Rect2 = _pin().get_global_rect()
	var collapse: Rect2 = _collapse().get_global_rect()
	var title: Rect2 = _rect("MapTitle")
	var least: float = UiScale.dp(48.0) - TOLERANCE_PX
	for button: Rect2 in [pin, collapse]:
		var at: String = "%s: button %s in head %s" % [why, button, head]
		assert_float(button.size.x).override_failure_message(at).is_greater_equal(least)
		assert_float(button.size.y).override_failure_message(at).is_greater_equal(least)
		assert_bool(head.grow(TOLERANCE_PX).encloses(button)).override_failure_message(at).is_true()
	assert_float(collapse.end.x).override_failure_message(why).is_equal_approx(
		head.end.x, TOLERANCE_PX
	)
	assert_float(pin.end.x).override_failure_message(why).is_less_equal(
		collapse.position.x + TOLERANCE_PX
	)
	assert_float(title.end.x).override_failure_message(why).is_less_equal(
		pin.position.x + TOLERANCE_PX
	)
	# The word "RADAR" fits its room whole (the label clips what does not).
	var label: Label = _hud("MapTitle") as Label
	var word: float = (
		label
		. get_theme_font(&"font")
		. get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")
		)
		. x
	)
	var fits: String = "%s: %s is %s wide in %s" % [why, label.text, word, title]
	assert_float(word).override_failure_message(fits).is_less_equal(title.size.x + TOLERANCE_PX)


func _pin() -> Button:
	return _hud("MapPin") as Button


func _collapse() -> Button:
	return _hud("MapCollapse") as Button


## Frames of `ms` in 250 ms steps through the feed, as the engine would run them.
func _step(ms: float) -> void:
	var left: float = ms
	while left > 0.0:
		var step: float = minf(left, STEP_S * 1000.0)
		_feed._process(step / 1000.0)
		left -= step


## Where ground point `ground` (milli-tiles) is on the screen, on the full map.
func _where(ground: Vector2i) -> Vector2:
	var local: Vector2 = _minimap.world_to_local(IsoProjection.ground_to_px(ground.x, ground.y))
	return _minimap.get_global_rect().position + local


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## A ground point clear of the HUD and of the buildings, at the middle of the view.
func _ground() -> Vector2:
	_camera.centre_on(IsoProjection.cell_centre_px(16, 12))
	return get_viewport().get_visible_rect().size * 0.5


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), the match
## paused, the Commands caught and the touch input's clock the test's.
func _open(size: Vector2i, metrics: UiMetrics = null, scenario: ScenarioDef = null) -> void:
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
	_runner.scenario = (
		Rig.scenario_for(1, "headquarters", MORE, ROSTER) if scenario == null else scenario
	)
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_feed = _hud("HudStateFeed") as HudStateFeed
	_state = _feed.state
	_scope = _hud("RadarScope") as RadarScope
	_map = _hud("RadarMap") as RadarMap
	_minimap = _hud("Minimap") as Minimap
	(_hud("BuildSidebar") as BuildSidebar).set_process(false)
	var instant: InputSettings = _camera.settings.duplicate()  # The snap is a tween on wall time.
	instant.zoom_snap_ms = 0
	_camera.settings = instant
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
