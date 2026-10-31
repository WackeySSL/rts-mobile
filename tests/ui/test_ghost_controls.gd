extends GdUnitTestSuite
## The check mark and the X beside the ghost (plan P86c, ADR 0024 section 10, ADR 0019 section 2),
## in the main scene through the real GUI at the six sizes of ScreenSizes.ALL with the engine's own
## metrics and at every profile of both orientations, also with a cutout (the two short landscape
## phones, web_phone_small and web_phone, among them): a tap on a READY card begins the mode, the
## cards stay and the buttons stand beside the ghost, 64 dp each, inside the safe rect above the
## menu's real top; they hide while the ghost is dragged (and during its edge pan), come back beside
## the new tile, follow a turn, and the check mark is dimmed by `can_confirm()` (not fitting,
## pending, "Blocked") while the X works. One press on the check mark sends one PLACE and the
## recognizer sees no tap. The placement function on crafted rects is test_ghost_place.gd's.
## Player 1 has a Headquarters and a finished power plant in its queue.

## The sides the buttons may stand on, in the order they are tried; NONE is no free place.
enum Spot { RIGHT, LEFT, ABOVE, NONE }

const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const GestureSpy: GDScript = preload("res://tests/input/support/gesture_spy.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BUILD_TICKS: int = 160  ## The plant takes 150 ticks.
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
const HOME: Vector2i = Vector2i(11, 7)  ## The tile that holds the middle of the plant at FITS.
const FRAME: float = 1.0 / 60.0

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _sidebar: BuildSidebar
var _controller: PlayerController
var _placement: PlacementController
var _ghost: GhostControls
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
	HudLayout.menu_top_px = INF
	CommandQueue.clear()


func test_the_node_stands_before_the_safe_area_with_the_hud_theme_and_the_old_row_is_gone() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var hud: Node = _main.get_node("Hud")
	var safe: Node = hud.get_node("SafeArea")
	assert_int(_ghost.get_index()).is_less(safe.get_index())
	assert_int(_ghost.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_object(_ghost.theme).is_same((safe as Control).theme)  # The dp copy of theme.tres.
	assert_object(_ghost.theme.get_meta(HudTheme.SOURCE_META)).is_not_null()
	assert_array(_ghost.clear_of).has_size(7)
	assert_object(_sidebar.find_child("Placement", true, false)).is_null()
	for global: Dictionary in ProjectSettings.get_global_class_list():
		assert_str(str(global["class"])).is_not_equal("PlacementControls")
	assert_bool(_ghost.visible).is_false()  # No mode, no buttons.


func test_a_tap_on_a_ready_card_stands_the_buttons_beside_the_ghost_and_the_cards_stay() -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		var card: ItemTile = _tile()
		assert_int(card.state).override_failure_message(why).is_equal(ItemTile.State.READY)
		assert_bool(_ghost.visible).override_failure_message(why).is_false()
		var panel: Rect2 = _sidebar.get_global_rect()
		_tap(card)
		await _settle()
		assert_bool(_placement.active).override_failure_message(why).is_true()
		assert_int(_placement.type_index).override_failure_message(why).is_equal(card.type_index)
		assert_bool(_ghost.visible).override_failure_message(why).is_true()
		assert_bool((_hud("Items") as Control).visible).override_failure_message(why).is_true()
		(
			assert_vector(_sidebar.get_global_rect().size)
			. override_failure_message(why)
			. is_equal_approx(panel.size, Vector2.ONE * 1.5)
		)
		assert_array(_sent).override_failure_message(why).is_empty()
		_expect_placed(why)
		_placement.cancel()
		await _settle()
		assert_bool(_ghost.visible).override_failure_message(why).is_false()
		assert_bool((_hud("Items") as Control).visible).override_failure_message(why).is_true()


## Where the buttons must stand, checked against an oracle that does not share the placement
## function's way of searching: for each of the three sides in turn (right, left, above) every
## position along the side in whole px is tried against the safe rect down to the menu's real top
## and the visible HUD controls' rects, the first side with a free one is the side that must be
## used, and where there is none the right column is clamped into the allowed rect (and may lie
## under a HUD control or over the ring). Either way the buttons are 64 dp across with 16 dp between
## them, the check mark first, a gap out from the silhouette box and inside the allowed rect.
func _expect_placed(why: String) -> void:
	var box: Rect2 = _placement.silhouette_rect()
	var confirm: Rect2 = _rect("PlaceConfirm")
	var cancel: Rect2 = _rect("PlaceCancel")
	var group: Rect2 = confirm.merge(cancel)
	var allowed: Rect2 = _allowed()
	var hud: Array[Rect2] = []
	for part: Control in _ghost.clear_of:
		if part.is_visible_in_tree():
			hud.append(part.get_global_rect())
	var button: float = UiScale.dp(64.0)
	var column: Vector2 = Vector2(button, 2.0 * button + UiScale.dp(GhostControls.BETWEEN_DP))
	var row: Vector2 = Vector2(column.y, column.x)
	var side: Spot = Spot.NONE
	for candidate: Spot in [Spot.RIGHT, Spot.LEFT, Spot.ABOVE]:
		if (
			side == Spot.NONE
			and _room_on(candidate, box, allowed, hud, row if candidate == Spot.ABOVE else column)
		):
			side = candidate
	var at: String = (
		"%s: side %s, box %s, check mark %s, X %s, allowed %s"
		% [why, Spot.find_key(side), box, confirm, cancel, allowed]
	)
	for rect: Rect2 in [confirm, cancel]:
		assert_vector(rect.size).override_failure_message(at).is_equal_approx(
			Vector2.ONE * button, Vector2.ONE * TOLERANCE_PX
		)
	var along: Vector2 = cancel.position - confirm.position
	var wanted_along: Vector2 = Vector2(button + UiScale.dp(GhostControls.BETWEEN_DP), 0.0)
	if side != Spot.ABOVE:
		wanted_along = Vector2(wanted_along.y, wanted_along.x)
	assert_vector(along).override_failure_message(at).is_equal_approx(wanted_along, Vector2.ONE)
	assert_bool(allowed.grow(TOLERANCE_PX).encloses(group)).override_failure_message(at).is_true()
	assert_bool(UiScale.safe_rect_base().encloses(group)).override_failure_message(at).is_true()
	match side:
		Spot.RIGHT:
			assert_float(group.position.x).override_failure_message(at).is_equal_approx(
				box.end.x + _gap_px(), 1.0
			)
		Spot.LEFT:
			assert_float(group.end.x).override_failure_message(at).is_equal_approx(
				box.position.x - _gap_px(), 1.0
			)
		Spot.ABOVE:
			assert_float(group.end.y).override_failure_message(at).is_equal_approx(
				box.position.y - _gap_px(), 1.0
			)
	if side != Spot.NONE:  # A place was free: the buttons are in one, clear of the ring and the HUD.
		(
			assert_bool(group.intersects(box.grow(_grab_px() - TOLERANCE_PX)))
			. override_failure_message(at)
			. is_false()
		)
		for part: Rect2 in hud:
			(
				assert_bool(group.grow(-TOLERANCE_PX).intersects(part))
				. override_failure_message("%s, clashes with %s" % [at, part])
				. is_false()
			)


## Whether a group of `size` fits on `side` of `box`: its fixed edge a gap out, and some position
## along the side, tried at every whole px, inside `allowed` and clear of every rect of `hud`.
func _room_on(side: Spot, box: Rect2, allowed: Rect2, hud: Array[Rect2], size: Vector2) -> bool:
	var gap: float = _gap_px()
	var vertical: bool = side != Spot.ABOVE  # The group slides up and down beside the box.
	var fixed: float = box.position.y - gap - size.y
	if side == Spot.RIGHT:
		fixed = box.end.x + gap
	elif side == Spot.LEFT:
		fixed = box.position.x - gap - size.x
	var low: float = allowed.position.y if vertical else allowed.position.x
	var high: float = (allowed.end.y - size.y) if vertical else (allowed.end.x - size.x)
	var across_ok: bool = (
		fixed >= allowed.position.x - 0.01 and fixed + size.x <= allowed.end.x + 0.01
		if vertical
		else fixed >= allowed.position.y - 0.01
	)
	if not across_ok or high < low:
		return false
	for step: int in int(high - low) + 2:
		var along: float = minf(low + step, high)
		var at: Rect2 = Rect2(Vector2(fixed, along) if vertical else Vector2(along, fixed), size)
		var free: bool = true
		for part: Rect2 in hud:
			free = free and not at.grow(-0.1).intersects(part)
		if free:
			return true
	return false


func test_the_buttons_flip_left_near_the_right_edge_and_stay_right_near_the_left_edge() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null)
		_tap(_tile())
		await _settle()
		var safe: Rect2 = UiScale.safe_rect_base()
		var edge: float = UiScale.dp(20.0)
		var why: String = str(size)
		_ghost_at(Vector2(safe.end.x - edge, safe.get_center().y))
		await _settle()
		var box: Rect2 = _placement.silhouette_rect()
		var group: Rect2 = _group()
		(
			assert_bool(box.end.x + _gap_px() + group.size.x > safe.end.x)
			. override_failure_message(why)
			. is_true()
		)  # The right side has no room,
		assert_float(group.end.x).override_failure_message(why).is_equal_approx(
			box.position.x - _gap_px(), 1.0
		)  # so the column stands on the left.
		(
			assert_bool(_allowed().encloses(group.grow(-TOLERANCE_PX)))
			. override_failure_message(why)
			. is_true()
		)
		_ghost_at(Vector2(safe.position.x + edge, safe.get_center().y))
		await _settle()
		box = _placement.silhouette_rect()
		(
			assert_float(_rect("PlaceConfirm").position.x)
			. override_failure_message(why)
			. is_equal_approx(box.end.x + _gap_px(), 1.0)
		)


## The ghost low in the map view, just above the build menu: the column slides up, never onto the
## menu (in portrait the open band, the case a pinned menu will keep), and a ghost at the top slides
## it down inside the safe rect.
func test_the_column_stays_above_the_menus_real_top_and_below_the_safe_rects_top() -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		_tap(_tile())
		await _settle()
		var safe: Rect2 = UiScale.safe_rect_base()
		var low: float = HudLayout.map_bottom_px(safe) - UiScale.dp(30.0)
		_ghost_at(Vector2(safe.get_center().x, low))
		await _settle()
		var group: Rect2 = _group()
		var at: String = "%s: group %s, menu top %s" % [why, group, HudLayout.menu_top_px]
		assert_float(group.end.y).override_failure_message(at).is_less_equal(
			HudLayout.map_bottom_px(safe) + TOLERANCE_PX
		)
		if HudLayout.is_portrait():
			assert_float(HudLayout.menu_top_px).override_failure_message(at).is_equal_approx(
				_sidebar.get_global_rect().position.y, 1.0
			)
			(
				assert_bool(group.intersects(_sidebar.get_global_rect()))
				. override_failure_message(at)
				. is_false()
			)
		_ghost_at(Vector2(safe.get_center().x, safe.position.y + UiScale.dp(10.0)))
		await _settle()
		group = _group()
		assert_float(group.position.y).override_failure_message(why).is_greater_equal(
			safe.position.y - TOLERANCE_PX
		)
		assert_bool(safe.grow(TOLERANCE_PX).encloses(group)).override_failure_message(why).is_true()


## HUD controls in the way, as the scene lists them (`clear_of`): one that covers the right side
## sends the column left, one on each side the row above, and where nothing fits the right column
## is clamped into the allowed rect; hidden again, the buttons are where they were.
func test_the_scenes_hud_list_is_what_the_buttons_keep_clear_of() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_tap(_tile())
	await _settle()
	var box: Rect2 = _placement.silhouette_rect()
	var allowed: Rect2 = _allowed()
	var reach: float = _gap_px() + UiScale.dp(64.0) + 10.0  # Over a column's width and its gap.
	var below: float = box.position.y - _gap_px() * 0.5  # Under the row above the box.
	var depth: float = allowed.end.y - below
	var right: Control = _block(Rect2(box.end.x, below, reach, depth))
	var group: Rect2 = _group()
	assert_float(group.end.x).is_equal_approx(box.position.x - _gap_px(), 1.0)  # Left.
	assert_bool(group.size.y > group.size.x).is_true()
	var left: Control = _block(Rect2(box.position.x - reach, below, reach, depth))
	group = _group()
	assert_bool(group.size.x > group.size.y).is_true()  # Above: a row, the check mark left of the X.
	assert_float(group.end.y).is_equal_approx(box.position.y - _gap_px(), 1.0)
	assert_float(_rect("PlaceConfirm").position.x).is_less(_rect("PlaceCancel").position.x)
	var top: Control = _block(
		Rect2(allowed.position, Vector2(allowed.size.x, below - allowed.position.y))
	)
	group = _group()
	assert_bool(group.size.y > group.size.x).is_true()  # The right column, clamped in.
	assert_bool(allowed.grow(TOLERANCE_PX).encloses(group)).is_true()
	for block: Control in [right, left, top]:  # A hidden control is no obstacle.
		block.visible = false
	await _settle()
	_expect_placed("blocks hidden")


## Where nothing fits (a HUD control over the whole allowed rect) the right column is clamped into
## the allowed rect, so even then it stands above the menu's real top, also with a top cutout where
## the band sits higher than the safe rect's bottom less its height.
func test_where_nothing_fits_the_clamped_column_stays_above_the_menus_real_top() -> void:
	for profile_name: StringName in [&"android_6in_portrait", &"web_phone_portrait"]:
		var m: UiMetrics = UiProfiles.by_name(profile_name)
		var cut: Rect2i = Rect2i(0, CUTOUT_PX, m.window_size.x, m.window_size.y - CUTOUT_PX)
		for metrics: UiMetrics in [m, UiProfiles.with_safe_area(m, cut)]:
			await _open(metrics.window_size, metrics)
			var why: String = "%s, safe %s" % [profile_name, metrics.safe_area]
			_tap(_tile())
			await _settle()
			var safe: Rect2 = UiScale.safe_rect_base()
			# The band sits higher than the safe rect's bottom less its height: the margin is above it.
			assert_float(HudLayout.menu_top_px).override_failure_message(why).is_less(
				safe.end.y - HudLayout.bottom_zone_px()
			)
			_ghost_at(Vector2(safe.get_center().x, HudLayout.menu_top_px - UiScale.dp(10.0)))
			_block(_allowed())
			var group: Rect2 = _group()
			assert_bool(group.size.y > group.size.x).override_failure_message(why).is_true()
			assert_float(group.end.y).override_failure_message(why).is_less_equal(
				HudLayout.menu_top_px + TOLERANCE_PX
			)
			assert_float(group.end.y).override_failure_message(why).is_equal_approx(
				_sidebar.get_global_rect().position.y, 1.0
			)  # It lies on the band's drawn top.
			(
				assert_bool(_allowed().grow(TOLERANCE_PX).encloses(group))
				. override_failure_message(why)
				. is_true()
			)


func test_the_check_mark_sends_exactly_one_place_and_the_recognizer_sees_no_tap() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var spy: PlayerController = auto_free(GestureSpy.new())
	_touch.controller = spy
	_tap(_tile())
	await _settle()
	_move_ghost(HOME)
	await _settle()
	# A press on bare ground reaches the recognizer: this is what a tap would show.
	var ground: Vector2 = UiScale.safe_rect_base().get_center() + Vector2(0.0, UiScale.dp(120.0))
	TouchEvents.press(get_viewport(), 0, ground)
	TouchEvents.release(get_viewport(), 0, ground)
	assert_array(spy.kinds).is_equal([GestureEvent.Kind.TAP])
	spy.kinds.clear()
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_false()
	_tap_control(_hud("PlaceConfirm"))
	assert_array(_sent).has_size(1)
	var place: Command = _sent[0]
	assert_array([place.type, place.player_id]).is_equal([Command.Type.PLACE, 1])
	assert_array([place.target_x, place.target_y]).is_equal([10500, 6500])
	assert_array(spy.kinds).is_empty()  # The press was the button's, not the map's.
	assert_bool(_placement.pending).is_true()
	await _settle()
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_true()  # Spent.
	_tap_control(_hud("PlaceConfirm"))  # A second press finds a dimmed button.
	assert_array(_sent).has_size(1)
	assert_array(spy.kinds).is_empty()
	_tap_control(_hud("PlaceCancel"))  # The X works while pending and sends nothing.
	assert_bool(_placement.active).is_false()
	assert_array(_sent).has_size(1)
	assert_array(spy.kinds).is_empty()
	await _settle()
	assert_bool(_ghost.visible).is_false()


func test_the_check_mark_is_dimmed_by_can_confirm_and_a_tap_on_it_then_does_nothing() -> void:
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
		assert_bool((_hud("PlaceConfirm") as Button).disabled).is_equal(
			not _placement.can_confirm()
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


## A PLACE pending and a ghost "Blocked" (P86b) change the check mark's state and nothing else: at
## every screen the two buttons stay where they were, 64 dp across, the check mark dimmed and the X
## working. The plant is built through the queue, so it is still ready after the tick; the sim's
## refusal is stood in for by a tick that never got the Command (this suite's sink only catches
## it), which the test stamps with the tick the runner would have taken it at.
func test_pending_and_blocked_dim_the_check_mark_and_leave_both_buttons_where_they_are() -> void:
	for screen: Dictionary in _screens(null):
		await _open(screen["size"], screen["metrics"], true)
		var why: String = str(screen["label"])
		_tap(_tile())
		await _settle()
		_move_ghost(HOME)
		await _settle()
		var rests: Array[Rect2] = [_rect("PlaceConfirm"), _rect("PlaceCancel")]
		(
			assert_bool((_hud("PlaceConfirm") as Button).disabled)
			. override_failure_message(why)
			. is_false()
		)
		assert_bool(_placement.confirm()).override_failure_message(why).is_true()
		await _settle()
		_expect_dimmed_in_place(rests, why + " pending")
		_sent[0].tick = _runner.snapshot.tick
		_runner.run_ticks(1)
		await _settle()
		assert_bool(_placement.blocked).override_failure_message(why).is_true()
		assert_bool(_placement.pending).override_failure_message(why).is_false()
		_expect_dimmed_in_place(rests, why + " blocked")
		_tap_control(_hud("PlaceCancel"))
		assert_bool(_placement.active).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).has_size(1)


## A finger that holds the ghost hides the buttons (from the first move past the slop, through the
## edge pan of a finger resting in a band) and a release shows them again beside the ghost's new
## tile. Landscape and portrait phones.
func test_the_buttons_hide_while_the_ghost_is_dragged_and_come_back_beside_the_new_tile() -> void:
	for profile_name: StringName in [&"android_6in", &"android_6in_portrait"]:
		var phone: UiMetrics = UiProfiles.by_name(profile_name)
		await _open(phone.window_size, phone)
		var why: String = str(profile_name)
		_tap(_tile())
		await _settle()
		assert_bool(_ghost.visible).override_failure_message(why).is_true()
		var tile: Vector2i = _placement.tile
		var from: Vector2 = _placement.silhouette_rect().get_center()
		var to: Vector2 = from + Vector2(UiScale.dp(60.0), UiScale.dp(40.0))
		TouchEvents.press(get_viewport(), 0, from)
		assert_bool(_placement.dragging).override_failure_message(why).is_false()  # Still a press.
		assert_bool(_ghost.visible).override_failure_message(why).is_true()
		TouchEvents.drag(get_viewport(), 0, to, to - from)
		assert_bool(_placement.dragging).override_failure_message(why).is_true()
		await _settle()
		assert_bool(_ghost.visible).override_failure_message(why).is_false()
		assert_bool((_hud("PlaceConfirm") as Control).is_visible_in_tree()).is_false()
		TouchEvents.release(get_viewport(), 0, to)
		assert_bool(_placement.dragging).override_failure_message(why).is_false()
		await _settle()
		assert_bool(_ghost.visible).override_failure_message(why).is_true()
		assert_vector(_placement.tile).override_failure_message(why).is_not_equal(tile)
		(
			assert_float(_rect("PlaceConfirm").position.x)
			. override_failure_message(why)
			. is_equal_approx(_placement.silhouette_rect().end.x + _gap_px(), 1.0)
		)
		# The edge pan: the finger rests in the left band; the map scrolls and the buttons stay hidden.
		var safe: Rect2 = UiScale.safe_rect_base()
		var band: float = UiScale.dp(_controller.settings.edge_band_dp)
		var centre: Vector2 = _placement.silhouette_rect().get_center()
		var finger: Vector2 = Vector2(
			safe.position.x + band * 0.5, safe.get_center().y + UiScale.dp(64.0)
		)
		TouchEvents.press(get_viewport(), 0, centre)
		TouchEvents.drag(get_viewport(), 0, finger, finger - centre)
		var held: Vector2 = _camera.position
		for frame: int in 12:
			_touch._process(FRAME)
			_ghost._process(FRAME)
			assert_bool(_ghost.visible).override_failure_message(why).is_false()
		assert_vector(_camera.position).override_failure_message(why).is_not_equal(held)  # It scrolled.
		TouchEvents.release(get_viewport(), 0, finger)
		await _settle()
		assert_bool(_ghost.visible).override_failure_message(why).is_true()
		(
			assert_float(_rect("PlaceConfirm").position.x)
			. override_failure_message(why)
			. is_equal_approx(_placement.silhouette_rect().end.x + _gap_px(), 1.0)
		)


## A press on the ghost or in the ring round it still grabs it and a drag from there moves it; the
## buttons stand beyond the ring, so no press in it can land on one.
func test_a_press_in_the_grab_ring_still_grabs_and_the_buttons_stand_outside_it() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_tap(_tile())
	await _settle()
	var box: Rect2 = _placement.silhouette_rect()
	var in_ring: Vector2 = Vector2(box.end.x + _grab_px() * 0.8, box.get_center().y)
	var group: Rect2 = _group()
	assert_bool(_placement.grabs(in_ring)).is_true()
	assert_bool(group.has_point(in_ring)).is_false()
	assert_bool(_placement.grabs(Vector2(group.position.x + 4.0, group.get_center().y))).is_false()
	var tile: Vector2i = _placement.tile
	var to: Vector2 = in_ring + Vector2(0.0, UiScale.dp(80.0))
	TouchEvents.press(get_viewport(), 0, in_ring)
	TouchEvents.drag(get_viewport(), 0, to, to - in_ring)
	assert_bool(_placement.dragging).is_true()
	TouchEvents.release(get_viewport(), 0, to)
	assert_vector(_placement.tile).is_not_equal(tile)
	assert_array(_sent).is_empty()


## A turn keeps the ghost's tile and the buttons stand beside the ghost at both orientations' sizes;
## a drag in flight is cancelled by the turn and the buttons come back at once.
func test_a_turn_keeps_the_buttons_beside_the_ghost_at_both_orientations() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	_tap(_tile())
	await _settle()
	_move_ghost(HOME)
	for turn: UiMetrics in [portrait, landscape, portrait]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		var why: String = str(turn.window_size)
		assert_bool(_placement.active).override_failure_message(why).is_true()
		assert_vector(_placement.tile).override_failure_message(why).is_equal(HOME)
		assert_bool(_ghost.visible).override_failure_message(why).is_true()
		_expect_placed(why)
	# A finger holds the ghost, then the phone turns: the recognizer lets go, the buttons are back.
	var from: Vector2 = _placement.silhouette_rect().get_center()
	var to: Vector2 = from + Vector2(UiScale.dp(60.0), 0.0)
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	assert_bool(_placement.dragging).is_true()
	UiScale.set_override(landscape)
	get_window().size = landscape.window_size
	await _settle()
	assert_bool(_placement.dragging).is_false()
	assert_bool(_ghost.visible).is_true()
	assert_array(_sent).is_empty()


## The follow reads the dp and the safe area cached on the last resize: another override put in
## without one is not seen until `read_metrics`, and the buttons keep their place meanwhile.
func test_the_follow_reads_the_cached_metrics_and_makes_no_object() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_tap(_tile())
	await _settle()
	var rests: Array[Rect2] = [_rect("PlaceConfirm"), _rect("PlaceCancel")]
	UiScale.set_override(UiProfiles.by_name(&"web_phone_small"))  # Another dp, no resize.
	_ghost._process(FRAME)
	assert_that(_rect("PlaceConfirm")).is_equal(rests[0])
	assert_that(_rect("PlaceCancel")).is_equal(rests[1])
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame: int in 60:
		_camera.pan_by_screen(Vector2(0.5, 0.25))  # The ghost's box moves, the buttons follow.
		_ghost._process(FRAME)
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)
	_ghost.read_metrics()  # A resize does this: the new dp is taken.
	_ghost._process(FRAME)
	assert_float(_rect("PlaceConfirm").size.x).is_equal_approx(UiScale.dp(64.0), TOLERANCE_PX)
	assert_bool(absf(_rect("PlaceConfirm").size.x - rests[0].size.x) > 1.0).is_true()


## The per-frame path makes no array, dictionary, object or call that builds one: only values
## (Vector2 and Rect2), so a frame of the follow costs the phone no allocation. A source scan of
## `_follow` and the functions below it, the comments taken out.
func test_the_per_frame_path_has_no_array_literal_new_or_building_call() -> void:
	var source: String = FileAccess.get_file_as_string("res://game/ui/GhostControls.gd")
	var start: int = source.find("func _follow()")
	assert_int(start).is_greater(0)
	var literal: RegEx = (
		RegEx
		. create_from_string(
			r"(?:[=(,:]|\bin|\breturn)\s*[\[{]|\.new\(|\brange\(|\.duplicate\(|\.map\(|\.filter\(|\bArray\("
		)
	)
	var hits: Array[String] = []
	for line: String in source.substr(start).split("\n"):
		var code: String = line.get_slice("#", 0)
		if literal.search(code) != null:
			hits.append(code.strip_edges())
	assert_array(hits).is_empty()
	var fixture: String = "for side: Array in [[right, 1]]:"  # The scan sees what it must.
	assert_object(literal.search(fixture)).is_not_null()


func test_only_a_ready_card_begins_the_mode() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	var other: ItemTile = _sidebar.find_child("Tile_barracks", true, false)
	assert_int(other.state).is_not_equal(ItemTile.State.READY)
	_tap(other)
	assert_bool(_placement.active).is_false()
	assert_bool(_ghost.visible).is_false()


## A scene with no placement controller (a sidebar built without one) takes a tap on a ready card
## for nothing at all: no mode, no Command, no error.
func test_a_sidebar_without_a_placement_controller_ignores_a_ready_card() -> void:
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	await _open(phone.window_size, phone)
	_sidebar.placement = null
	_tap(_tile())
	assert_bool(_placement.active).is_false()
	assert_array(_sent).is_empty()


## The check mark is dimmed and the X is not, both at `rests` (the check mark's and the X's rect
## before), 64 dp across and inside the safe rect.
func _expect_dimmed_in_place(rests: Array[Rect2], why: String) -> void:
	assert_bool((_hud("PlaceConfirm") as Button).disabled).override_failure_message(why).is_true()
	assert_bool((_hud("PlaceCancel") as Button).disabled).override_failure_message(why).is_false()
	var safe: Rect2 = UiScale.safe_rect_base()
	var now: Array[Rect2] = [_rect("PlaceConfirm"), _rect("PlaceCancel")]
	for index: int in 2:
		var at: String = "%s: %s was %s" % [why, now[index], rests[index]]
		assert_vector(now[index].position).override_failure_message(at).is_equal_approx(
			rests[index].position, Vector2.ONE * TOLERANCE_PX
		)
		assert_vector(now[index].size).override_failure_message(at).is_equal_approx(
			Vector2.ONE * UiScale.dp(GhostControls.ACTION_DP), Vector2.ONE * TOLERANCE_PX
		)
		assert_bool(safe.encloses(now[index])).override_failure_message(at).is_true()


func _tile() -> ItemTile:
	return _sidebar.find_child("Tile_%s" % Rig.PLANT, true, false) as ItemTile


## The ghost on the tile that holds the middle of the plant at `tile`, by a tap on the ground.
func _move_ghost(tile: Vector2i) -> void:
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	_ghost_at(_camera.world_to_screen(IsoProjection.cell_centre_px(tile.x, tile.y)))


## The ghost on the tile under the screen point `at`, by the tap gesture the controller takes.
func _ghost_at(at: Vector2) -> void:
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = at
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


## A Control over `area` that the buttons must keep clear of, added to the scene's list.
func _block(area: Rect2) -> Control:
	var block: Control = Control.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.add_child(block)
	block.position = area.position
	block.size = area.size
	_ghost.clear_of.append(block)
	_ghost._process(FRAME)
	return block


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## The rect the buttons may stand in: the safe rect down to the menu's real top.
func _allowed() -> Rect2:
	var safe: Rect2 = UiScale.safe_rect_base()
	return Rect2(
		safe.position, Vector2(safe.size.x, HudLayout.map_bottom_px(safe) - safe.position.y)
	)


func _group() -> Rect2:
	return _rect("PlaceConfirm").merge(_rect("PlaceCancel"))


## The grab ring's width and the buttons' distance from the silhouette, base px.
func _grab_px() -> float:
	return UiScale.dp(_controller.settings.ghost_grab_dp)


func _gap_px() -> float:
	return UiScale.dp(_controller.settings.ghost_grab_dp + GhostControls.RING_GAP_DP)


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
## paused, the Commands caught, the plant ready and the sidebar showing it: in the published
## snapshot only, or with `built` through the queue, so that it stays ready on the next tick. The
## touch input runs only when the test says so, on the suite's clock.
func _open(size: Vector2i, metrics: UiMetrics, built: bool = false) -> void:
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
	if built:
		CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
		_runner.run_ticks(BUILD_TICKS)
	else:
		Rig.make_ready(_runner.snapshot)
	Rig.explore(_runner.snapshot)
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	_ghost = _main.get_node("Hud/GhostControls")
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_touch.set_process(false)  # The frames of the test are the only frames.
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_sent.clear()
	_now_ms = 0
	_touch.clock = func() -> int: return _now_ms
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(_ms: int) -> void: pass
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	_sidebar.refresh()
	await _settle()
