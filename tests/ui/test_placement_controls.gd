extends GdUnitTestSuite
## The build menu's side of placement mode (plan P86, ADR 0019 section 2, ADR 0023 section 12), in
## the main scene through the real GUI. A tap on a READY card begins the mode; the check mark and
## the X take the card row's place in the floating panel (the band in portrait), the panel keeping
## its size. The check mark is dimmed while the ghost does not fit; a tap on it sends exactly one
## PLACE and ends the mode, and the X ends it with no Command. At the six sizes of ScreenSizes.ALL
## with the engine's own metrics and at every profile of both orientations, also with a cutout,
## each of the two is inside the safe rect and its panel, 64 dp across, a gap from the other and
## clear of every other HUD control, and the HUD does not grow. A turn keeps the ghost and moves the
## controls with the layout. Player 1 has a Headquarters and a finished power plant in its queue.

const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
const OTHERS: Array[String] = [
	"DevButton", "AllArmy", "Group1", "Group2", "Group3", "SelectionPanel", "StrikeControls"
]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _sidebar: BuildSidebar
var _controller: PlayerController
var _placement: PlacementController
var _now_ms: int = 0
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	CommandQueue.clear()


func test_a_tap_on_a_ready_card_begins_the_mode_and_the_controls_take_the_cards_place() -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var card: ItemTile = _tile()
		assert_int(card.state).override_failure_message(why).is_equal(ItemTile.State.READY)
		assert_bool(_hud("Placement").visible).override_failure_message(why).is_false()
		assert_bool((_hud("Items") as Control).visible).override_failure_message(why).is_true()
		var panel: Vector2 = _sidebar.get_global_rect().size
		_tap(card)
		await _settle()
		assert_bool(_placement.active).override_failure_message(why).is_true()
		assert_int(_placement.type_index).override_failure_message(why).is_equal(card.type_index)
		assert_vector(_placement.foot).override_failure_message(why).is_equal(Rig.FOOT)
		assert_bool(_hud("Placement").visible).override_failure_message(why).is_true()
		assert_bool((_hud("Items") as Control).visible).override_failure_message(why).is_false()
		(
			assert_vector(_sidebar.get_global_rect().size)
			. override_failure_message(why)
			. is_equal_approx(panel, Vector2.ONE * 1.5)
		)
		assert_array(_sent).override_failure_message(why).is_empty()
		_placement.cancel()
		await _settle()
		assert_bool((_hud("Items") as Control).visible).override_failure_message(why).is_true()
		assert_bool(_hud("Placement").visible).override_failure_message(why).is_false()


func test_the_check_mark_sends_exactly_one_place_and_the_x_sends_nothing() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_tap(_tile())
	await _settle()
	_move_ghost(Vector2i(11, 7))
	await _settle()
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_false()
	_tap_control(_hud("PlaceCancel"))
	assert_bool(_placement.active).is_false()
	assert_array(_sent).is_empty()
	await _settle()
	assert_bool(_hud("Placement").visible).is_false()
	_tap(_tile())  # The structure is still ready: its card begins the mode again.
	await _settle()
	_move_ghost(Vector2i(11, 7))
	_tap_control(_hud("PlaceConfirm"))
	_tap_control(_hud("PlaceConfirm"))  # The controls are gone: a second tap finds no button.
	assert_array(_sent).has_size(1)
	var place: Command = _sent[0]
	assert_array([place.type, place.player_id]).is_equal([Command.Type.PLACE, 1])
	assert_array([place.target_x, place.target_y]).is_equal([10500, 6500])
	assert_bool(_placement.active).is_false()
	await _settle()
	assert_bool((_hud("Items") as Control).visible).is_true()


func test_the_check_mark_is_dimmed_while_the_ghost_does_not_fit_and_a_tap_on_it_does_nothing(
) -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_tap(_tile())
	for origin: Vector2i in [Rig.TOO_FAR, Rig.ON_THE_HQ, Rig.FITS]:
		_move_ghost(origin + Vector2i.ONE)
		await _settle()
		var fits: bool = _placement.reason == Placement.Reason.OK
		var why: String = "%s: %s" % [origin, Placement.Reason.find_key(_placement.reason)]
		(
			assert_bool((_hud("PlaceConfirm") as Button).disabled)
			. override_failure_message(why)
			. is_equal(not fits)
		)
		(
			assert_bool((_hud("PlaceCancel") as Button).disabled)
			. override_failure_message(why)
			. is_false()
		)
		if not fits:
			_tap_control(_hud("PlaceConfirm"))
			assert_array(_sent).override_failure_message(why).is_empty()
			assert_bool(_placement.active).override_failure_message(why).is_true()


func test_every_control_is_64_dp_inside_the_safe_rect_and_its_panel_and_clear_of_the_hud() -> void:
	assert_float(PlacementControls.ACTION_DP).is_equal(64.0)
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		_tap(_tile())
		await _settle()
		var safe: Rect2 = UiScale.safe_rect_base()
		var panel: Rect2 = _rect("BuildSidebar")
		var parts: Array[Rect2] = [_rect("PlaceConfirm"), _rect("PlaceCancel")]
		for index: int in 2:
			var rect: Rect2 = parts[index]
			var at: String = "%s: %s of %s, safe %s" % [why, rect, panel, safe]
			assert_bool(safe.encloses(rect)).override_failure_message(at).is_true()
			assert_bool(panel.encloses(rect)).override_failure_message(at).is_true()
			assert_float(rect.size.x).override_failure_message(at).is_equal_approx(
				UiScale.dp(64.0), TOLERANCE_PX
			)
			assert_float(rect.size.y).override_failure_message(at).is_equal_approx(
				UiScale.dp(64.0), TOLERANCE_PX
			)
			var others: Array[Rect2] = []
			for other: String in OTHERS:
				var control: Control = _hud(other)
				if control.is_visible_in_tree():
					others.append(control.get_global_rect())
			if not HudLayout.is_portrait():
				others.append(_rect("StatusPill"))
				others.append(_rect("MinimapSlot"))
			for other: Rect2 in others:
				var clash: String = "%s: %s clashes with %s" % [why, rect, other]
				assert_bool(rect.intersects(other)).override_failure_message(clash).is_false()
		var gap: float = parts[1].position.x - parts[0].end.x
		assert_float(gap).override_failure_message("%s: gap %s" % [why, gap]).is_greater_equal(
			UiScale.dp(8.0) - TOLERANCE_PX
		)
		var area: Rect2 = (_hud("SafeArea") as Control).get_global_rect()
		assert_that(area).override_failure_message(why).is_equal(get_viewport().get_visible_rect())


## A turn of the phone with the mode on: the ghost keeps its tile and the controls are in the
## other layout's panel, nothing is sent.
func test_a_turn_keeps_the_ghost_and_the_controls_follow_the_layout() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	_tap(_tile())
	await _settle()
	_move_ghost(Vector2i(11, 7))
	for turn: UiMetrics in [portrait, landscape, portrait]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		assert_bool(_placement.active).is_true()
		assert_vector(_placement.tile).is_equal(Vector2i(11, 7))
		var panel: Rect2 = _rect("BuildSidebar")
		(
			assert_bool(panel.encloses(_rect("PlaceConfirm")))
			. override_failure_message(str(turn.window_size))
			. is_true()
		)
		(
			assert_bool(panel.encloses(_rect("PlaceCancel")))
			. override_failure_message(str(turn.window_size))
			. is_true()
		)
		assert_bool((_hud("Items") as Control).visible).is_false()
	assert_array(_sent).is_empty()


## A tap on a card that is not READY does not begin the mode: a ready one only.
func test_only_a_ready_card_begins_the_mode() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var other: ItemTile = _sidebar.find_child("Tile_barracks", true, false)
	assert_int(other.state).is_not_equal(ItemTile.State.READY)
	_tap(other)
	assert_bool(_placement.active).is_false()


## A scene with no placement controller (a sidebar built without one) takes a tap on a ready card
## for nothing at all: no mode, no Command, no error.
func test_a_sidebar_without_a_placement_controller_ignores_a_ready_card() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_sidebar.placement = null
	_tap(_tile())
	assert_bool(_placement.active).is_false()
	assert_array(_sent).is_empty()


func _tile() -> ItemTile:
	return _sidebar.find_child("Tile_%s" % Rig.PLANT, true, false) as ItemTile


## The ghost on the tile that holds the middle of the plant at `tile`, by a tap on the ground.
func _move_ghost(tile: Vector2i) -> void:
	var camera: RtsCamera = _main.get_node("Camera")
	camera.centre_on(IsoProjection.cell_centre_px(11, 7))
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = camera.world_to_screen(IsoProjection.cell_centre_px(tile.x, tile.y))
	_controller.handle_gesture(tap)


## A tap on the card, with the suite's clock in it so no hold is ever seen.
func _tap(card: ItemTile) -> void:
	card.clock = func() -> int: return _now_ms
	var at: Vector2 = card.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## A tap on the middle of a control, with the touch events a finger sends.
func _tap_control(control: Node) -> void:
	var at: Vector2 = (control as Control).get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}; each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait). `portrait`: only that orientation (true or
## false), or both (null).
func _screens(portrait: Variant) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		all.append({"label": "size %s" % size, "size": size, "metrics": null})
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	for profile_name: StringName in profiles:
		var m: UiMetrics = profiles[profile_name]
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		if not UiScale.is_portrait_size(m.window_size):
			cut = Rect2i(CUTOUT_PX, 0, m.window_size.x - CUTOUT_PX, m.window_size.y)
		all.append({"label": str(profile_name), "size": m.window_size, "metrics": m})
		var with_cutout: UiMetrics = UiProfiles.with_safe_area(m, cut)
		all.append(
			{
				"label": "%s with a cutout" % profile_name,
				"size": m.window_size,
				"metrics": with_cutout
			}
		)
	var out: Array[Dictionary] = []
	for screen: Dictionary in all:
		if portrait == null or UiScale.is_portrait_size(screen["size"]) == portrait:
			out.append(screen)
	return out


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	return (_hud(node_name) as Control).get_global_rect()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, the Commands caught, the plant ready in the snapshot and the sidebar showing it.
func _open(size: Vector2i, metrics: UiMetrics) -> void:
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
	_runner.scenario = Rig.scenario()
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	Rig.make_ready(_runner.snapshot)
	Rig.explore(_runner.snapshot)
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_sent.clear()
	_now_ms = 0
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(_ms: int) -> void: pass
	_sidebar.refresh()
	await _settle()
