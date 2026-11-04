extends GdUnitTestSuite
## What opens and closes the build drawer (plan P120, ADR 0025 sections 1 and 5; it grew out of
## P85f, ADR 0024 sections 1, 5, 6 and 9), in the main scene through the real GUI at the six sizes
## of ScreenSizes.ALL. A match starts closed. A tap, a double-tap, a long-press with its box, a pan,
## a pinch and a wheel step on the map close it and still do their own work; a touch on the group
## column, the command bar's chip,
## a tab, a card, a hold on a card or a scroll of the grid never does. The start
## of placement closes it, and so does a restart of placement by a READY card tapped in a drawer
## opened meanwhile; the end of placement by a build or the X opens it again (it returns to the
## state placement began in) and a strike aim that ends placement leaves it closed; a tap on an own
## producer opens it on its tab with no visible move; a turn and a cancel_all() keep the state; a
## new match starts closed. Player 1 has a Headquarters, two light tanks, a Heavy Yard and a
## Bunkhouse, and a finished structure in its queue.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ROSTER: Array = ["power_plant", "barracks", "vehicle_factory", "defence_turret", "light_tank"]
const MORE: Array = [
	["light_tank", 12, 10], ["light_tank", 13, 10], ["vehicle_factory", 14, 3], ["barracks", 10, 14]
]
const TANK_A: int = 3
const TANK_B: int = 4
const FACTORY: int = 5
const BARRACKS: int = 6
const HOME: Vector2i = Vector2i(11, 7)  ## The tile that holds the middle of a plant that fits.
const BUILD_TICKS: int = 160
const TOLERANCE_PX: float = 1.5

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _sidebar: BuildSidebar
var _controller: PlayerController
var _placement: PlacementController
var _units: UnitLayer
var _buildings: BuildingLayer
var _now_ms: int = 0
var _sent: Array[Command] = []
var _told: int = 0  ## `map_gesture`s since the last `_forget`.
var _physics_before: int = 60


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	_physics_before = Engine.physics_ticks_per_second


func after_test() -> void:
	MenuRig.end()
	Engine.physics_ticks_per_second = _physics_before
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0
	HudLayout.menu_top_px = INF
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_each_gesture_on_the_map_closes_the_drawer_and_still_does_its_work() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		_aim_camera(IsoProjection.cell_centre_px(16, 12))
		var ground: Vector2 = _view_point()
		# A tap on the ground with a tank selected: the tank is ordered there.
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		_tap(ground)
		_expect_down(why + " tap")
		assert_int(_sent.size()).override_failure_message(why).is_equal(1)
		assert_int(_sent[0].type).override_failure_message(why).is_equal(Command.Type.MOVE)
		# A double-tap on a tank: every tank of the type on screen is selected.
		_reopen()
		_controller.selection.clear()
		_double_tap(_tank_at(TANK_A))
		_expect_down(why + " double-tap", 2)  # The first tap collapsed it, and the second told too.
		assert_array(_controller.selection.selected).override_failure_message(why).is_equal(
			[TANK_A, TANK_B]
		)
		# A long-press and a drag: a box with no tank in it clears the selection.
		_reopen()
		_aim_camera(IsoProjection.cell_centre_px(16, 12))
		_box(ground, ground + Vector2(60.0, 40.0))
		_expect_down(why + " long-press")
		assert_array(_controller.selection.selected).override_failure_message(why).is_empty()
		# A pan moves the camera.
		_reopen()
		var at: Vector2 = _camera.position
		_drag(ground, Vector2(80.0, 30.0))
		_expect_down(why + " pan")
		assert_vector(_camera.position).override_failure_message(why).is_not_equal(at)
		# A pinch zooms.
		_reopen()
		var zoom: float = _camera.zoom.x
		_pinch(ground, 100.0, 150.0)
		_expect_down(why + " pinch")
		assert_float(_camera.zoom.x).override_failure_message(why).is_not_equal(zoom)
		# A wheel step (the desktop preview's zoom).
		_reopen()
		_camera.zoom = Vector2.ONE
		zoom = _camera.zoom.x
		TouchEvents.wheel(get_viewport(), MOUSE_BUTTON_WHEEL_UP, ground)
		_expect_down(why + " wheel")
		assert_float(_camera.zoom.x).override_failure_message(why).is_not_equal(zoom)


func test_a_touch_on_a_hud_control_never_closes_the_drawer() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		_controller.selection.set_ids(PackedInt32Array([TANK_A]))
		await _settle()
		var card: ItemTile = _sidebar.find_child("Tile_barracks", true, false) as ItemTile
		assert_int(card.state).is_equal(ItemTile.State.LOCKED)
		card.clock = func() -> int: return _now_ms
		var shakes: int = card.shakes
		var touches: Array[Control] = [
			_hud("AllArmy") as Control,
			_hud("Group1") as Control,
			_hud("TabVehicles") as Control,
			_hud("TabStructures") as Control,
			card,
		]
		var chip: Control = _hud("Chip") as Control
		if chip.is_visible_in_tree() and not HudLayout.is_portrait():  # The sheet covers it upright.
			touches.append(chip)
		for control: Control in touches:
			var note: String = "%s: a tap on %s" % [why, control.name]
			_tap(control.get_global_rect().get_center())
			assert_bool(_sidebar.is_open()).override_failure_message(note).is_true()
			assert_int(_told).override_failure_message(note).is_equal(0)
		assert_int(card.shakes).override_failure_message(why).is_equal(shakes + 1)  # A locked card.
		# Upright the sheet covers the group column, so a tap at its centre may land on an item of the
		# queue row (P120b), which cancels it: at most such CANCELs, and nothing sideways.
		for command: Command in _sent:
			assert_bool(HudLayout.is_portrait()).override_failure_message(why).is_true()
			assert_int(command.type).override_failure_message(why).is_equal(Command.Type.CANCEL)
		_sent.clear()
		# A hold on a locked card (it shakes, nothing is queued), then a scroll of the row.
		var at: Vector2 = card.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, at)
		_now_ms += _touch.settings.long_press_ms
		card._process(0.0)
		TouchEvents.release(get_viewport(), 0, at)
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.drag(get_viewport(), 0, at + Vector2(-90.0, 0.0), Vector2(-90.0, 0.0))
		TouchEvents.release(get_viewport(), 0, at + Vector2(-90.0, 0.0))
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_int(_told).override_failure_message(why).is_equal(0)
		assert_int(_sent.size()).override_failure_message(why).is_equal(0)  # Nothing was ordered.
		_tap(_ground())  # And one tap on the map does collapse it.
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()


func test_a_tap_on_an_own_producer_opens_the_drawer_on_its_tab_with_no_visible_move() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		BuildSidebar.set_slide_ms_override(160)
		var heights: Array[Vector2] = []
		_sidebar.zone_changed.connect(
			func(top: float, height: float) -> void: heights.append(Vector2(top, height))
		)
		var zone: float = HudLayout.bottom_zone_dp
		var top: float = HudLayout.menu_top_px
		_sidebar.select_tab(World.Tab.STRUCTURES)
		_tap_building(FACTORY)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_int(_sidebar.tab).override_failure_message(why).is_equal(World.Tab.VEHICLES)
		assert_int(_told).override_failure_message(why).is_equal(1)  # The tap collapsed it first.
		_sidebar.advance(0.05)  # And any frames of a slide that did not start move nothing.
		await _settle()
		assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_equal(zone)
		assert_float(HudLayout.menu_top_px).override_failure_message(why).is_equal(top)
		assert_array(heights).override_failure_message(why).is_empty()
		_tap_building(BARRACKS)
		assert_int(_sidebar.tab).override_failure_message(why).is_equal(World.Tab.INFANTRY)
		assert_bool(_sidebar.is_open()).is_true()
		# From the collapsed menu the same tap opens it, and it slides up.
		BuildSidebar.set_slide_ms_override(0)
		_sidebar.collapse()
		BuildSidebar.set_slide_ms_override(160)
		var down: float = HudLayout.bottom_zone_dp
		_tap_building(FACTORY)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_int(_sidebar.tab).override_failure_message(why).is_equal(World.Tab.VEHICLES)
		if HudLayout.is_portrait():
			assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_equal(down)
			_sidebar.advance(0.05)
			assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_greater(down)
		# A unit does not: selecting one leaves the tab and the state as they are.
		BuildSidebar.set_slide_ms_override(0)
		_sidebar.collapse()
		_tap(_tank_at(TANK_A))
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_int(_sidebar.tab).override_failure_message(why).is_equal(World.Tab.VEHICLES)


func test_placement_closes_the_drawer_and_a_build_or_the_x_gives_it_back() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var card: ItemTile = _sidebar.find_child("Tile_power_plant", true, false) as ItemTile
		assert_int(card.state).is_equal(ItemTile.State.READY)
		card.clock = func() -> int: return _now_ms
		_tap(card.get_global_rect().get_center())  # The READY card: placement begins.
		assert_bool(_placement.active).override_failure_message(why).is_true()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_int(_told).override_failure_message(why).is_equal(0)  # A card is no map gesture.
		await _settle()
		assert_bool((_hud("Items") as Control).is_visible_in_tree()).is_false()
		# Map gestures during placement change nothing: it stays collapsed.
		_tap(_ground())
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_bool(_placement.active).is_true()
		# The X returns it to the state placement began in.
		_placement.cancel()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		await _settle()
		assert_bool((_hud("Items") as Control).is_visible_in_tree()).is_true()


## The Build button stays live while the ghost is out (a HUD touch): the cards are back, the READY
## card can be tapped again, and the end of placement leaves the menu up.
func test_build_brings_the_cards_back_while_the_ghost_is_out_and_ready_restarts_it_closed() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null, false, false)
		var why: String = str(size)
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		await _settle()
		_tap((_hud("BuildButton") as Control).get_global_rect().get_center())
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_bool(_placement.active).override_failure_message(why).is_true()
		assert_int(_told).override_failure_message(why).is_equal(0)
		await _settle()
		var card: ItemTile = _sidebar.find_child("Tile_power_plant", true, false) as ItemTile
		assert_bool(card.is_visible_in_tree()).override_failure_message(why).is_true()
		# ADR 0025 section 5: the start of placement closes the drawer, a restart too.
		card.clock = func() -> int: return _now_ms
		_tap(card.get_global_rect().get_center())
		assert_bool(_placement.active).override_failure_message(why).is_true()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		_placement.cancel()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()  # Began closed.


## A tap on the READY card closes the drawer only when placement really begins: where the game
## refuses it (here the type has no footprint in the snapshot) the drawer stays open, nothing is
## sent and no placement runs.
func test_a_ready_tap_that_placement_refuses_leaves_the_drawer_open_and_sends_nothing() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var card: ItemTile = _sidebar.find_child("Tile_power_plant", true, false) as ItemTile
		assert_int(card.state).override_failure_message(why).is_equal(ItemTile.State.READY)
		card.clock = func() -> int: return _now_ms
		var foot: int = _runner.snapshot.type_foot_w[card.type_index]
		_runner.snapshot.type_foot_w[card.type_index] = 0
		_tap(card.get_global_rect().get_center())
		assert_bool(_placement.active).override_failure_message(why).is_false()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_array(_sent).override_failure_message(why).is_empty()
		_runner.snapshot.type_foot_w[card.type_index] = foot
		_tap(card.get_global_rect().get_center())  # Accepted now: it begins and closes the drawer.
		assert_bool(_placement.active).override_failure_message(why).is_true()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()


func test_a_build_gives_the_drawer_back_and_a_strike_aim_or_the_matchs_end_does_not() -> void:
	await _open(ScreenSizes.LANDSCAPE[0], null, true)
	# A build: the check mark, the tick that answers it, and the menu is open again.
	assert_bool(_sidebar.is_open()).is_true()
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	assert_bool(_sidebar.is_open()).is_false()
	_move_ghost(HOME)
	assert_bool(_placement.confirm()).is_true()
	assert_bool(_sidebar.is_open()).is_false()  # Pending: the ghost is held, the menu down.
	_runner.run_ticks(1)
	assert_bool(_placement.active).is_false()
	assert_bool(_sidebar.is_open()).is_true()
	# A strike aim ends placement and the menu stays down, so the strike row does not move.
	await _open(ScreenSizes.PORTRAIT[0], null, true)
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	assert_bool(_sidebar.is_open()).is_false()
	var aim: StrikeAim = _main.get_node("StrikeAim")
	aim.owned = true
	aim.building_id = 1
	assert_bool(aim.begin()).is_true()  # PlacementController ends its mode.
	assert_bool(_placement.active).is_false()
	assert_bool(_sidebar.is_open()).is_false()
	aim.cancel()
	assert_bool(_sidebar.is_open()).is_false()  # Ending the aim opens nothing either.
	# The end of the match opens nothing (the result screen covers the HUD): placement began in the
	# open menu, so only the match's end keeps it down.
	_sidebar.open()
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	assert_bool(_sidebar.is_open()).is_false()
	_runner.snapshot.match_end_tick = 5
	_placement.cancel()
	assert_bool(_sidebar.is_open()).is_false()
	# Placement that began in the collapsed menu ends in it.
	_runner.snapshot.match_end_tick = 0
	_sidebar.collapse()
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_placement.cancel()
	assert_bool(_sidebar.is_open()).is_false()


## The strike aim takes the menu down as it starts, as placement does (ADR 0024's R1 rule, extended
## to the aim's start): upright the strike row rides on the menu's top, and the first tap on the map
## that places the aim's point would otherwise slide it, with its check mark and X lit up, about
## 100 dp under the thumb. Nothing moves between the aim's start and its confirm.
func test_a_strike_aim_closes_the_drawer_at_its_start_and_the_strike_row_stays_put() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var aim: StrikeAim = _main.get_node("StrikeAim")
		aim.owned = true
		aim.building_id = 1
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_bool(aim.begin()).override_failure_message(why).is_true()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()  # Before any tap.
		assert_int(_told).override_failure_message(why).is_equal(0)
		await _settle()
		var confirm: Control = _hud("StrikeConfirm") as Control
		assert_bool(confirm.is_visible_in_tree()).override_failure_message(why).is_true()
		var at: Rect2 = confirm.get_global_rect()
		var zone: float = HudLayout.bottom_zone_dp
		_tap(_ground())  # The aim's point.
		await _settle()
		assert_bool(aim.has_point).override_failure_message(why).is_true()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_bool(confirm.get_global_rect() == at).override_failure_message(why).is_true()
		assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_equal(zone)
		assert_bool(aim.confirm()).override_failure_message(why).is_true()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()  # Nothing reopens.


func test_a_turn_and_a_cancelled_gesture_keep_the_state_and_a_new_match_starts_closed() -> void:
	await _open(ScreenSizes.LANDSCAPE[1], null)
	for open: bool in [true, false]:
		if open:
			_sidebar.open()
		else:
			_sidebar.collapse()
		_aim_camera(IsoProjection.cell_centre_px(16, 12))
		var ground: Vector2 = _view_point()
		TouchEvents.press(get_viewport(), 0, ground)  # A finger down, no gesture yet.
		for size: Vector2i in [ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]]:
			get_window().size = size
			await _settle()
			assert_bool(_sidebar.is_open()).override_failure_message(str(size)).is_equal(open)
			assert_int(_told).is_equal(0)  # The cancel of the turn is no gesture on the map.
		TouchEvents.release(get_viewport(), 0, ground)
		assert_int(_told).is_equal(0)  # And the lift after it makes no tap.
		assert_bool(_sidebar.is_open()).is_equal(open)
	# A new match starts closed, whatever the state at the end of the last.
	_sidebar.open()
	_runner.start()
	_sidebar.refresh()
	await _settle()
	assert_bool(_sidebar.is_open()).is_false()


func test_a_match_starts_closed_and_build_close_and_the_map_unfold_it() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null, false, false)
		var why: String = str(size)
		var feed: HudStateFeed = _main.get_node("Hud/HudStateFeed")
		var build: Control = _hud("BuildButton") as Control
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_bool(_sidebar.visible).override_failure_message(why).is_false()
		assert_bool(build.visible).override_failure_message(why).is_true()
		_tap(build.get_global_rect().get_center())  # BUILD opens it and hides itself.
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_bool(feed.state.is_open(HudState.Unfold.DRAWER)).is_true()
		assert_bool(build.visible).override_failure_message(why).is_false()
		assert_int(_told).override_failure_message(why).is_equal(0)  # A HUD touch, no map gesture.
		await _settle()
		var close: Control = _hud("Close") as Control
		assert_float(close.size.x).is_greater_equal(UiScale.dp(48.0) - 0.5)
		_tap(close.get_global_rect().get_center())
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_bool(build.visible).override_failure_message(why).is_true()
		# The drawer folds the full map, and the full map folds the drawer.
		feed.state.open(HudState.Unfold.RADAR)
		_sidebar.open()
		(
			assert_bool(feed.state.is_open(HudState.Unfold.RADAR))
			. override_failure_message(why)
			. is_false()
		)
		assert_bool(_sidebar.is_open()).is_true()
		feed.state.open(HudState.Unfold.RADAR)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()


## ADR 0025 section 5: a drag toward the edge the drawer came from, past `drawer_swipe_dp`, closes
## it. Landscape: any horizontal drag on the panel; upright: one that starts on the head, while a
## vertical drag on the grid scrolls it and a drag the wrong way or too short closes nothing.
func test_a_swipe_toward_the_edge_closes_the_drawer_from_the_panel_or_the_head() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var portrait: bool = HudLayout.is_portrait()
		var far: float = UiScale.dp(_touch.settings.drawer_swipe_dp) + 10.0
		var toward: Vector2 = Vector2(0.0, 1.0) if portrait else Vector2(1.0, 0.0)
		var head: Vector2 = (_hud("Head") as Control).get_global_rect().get_center() - toward * 8.0
		var grid: Vector2 = (_hud("Tile_power_plant") as Control).get_global_rect().get_center()
		var panel: Vector2 = head if portrait else grid
		_swipe(panel, -toward * far)  # The wrong way.
		_swipe(panel, toward * (far - 20.0))  # Too short.
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		if portrait:
			_swipe(grid, toward * far * 1.5)  # From the grid: a scroll, not a swipe.
			assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		else:
			_swipe(head, Vector2(0.0, far * 1.5))  # Vertical: the grid scrolls.
			assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		_swipe(panel, toward * far)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_int(_told).override_failure_message(why).is_equal(0)


## A finger that went down on the drawer and then saw it fold (another unfold, the close button)
## swipes nothing when the drawer opens again under it: its swipe ended with the fold.
func test_a_finger_down_when_the_drawer_folds_swipes_nothing_when_it_opens_again() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var portrait: bool = HudLayout.is_portrait()
		var toward: Vector2 = Vector2(0.0, 1.0) if portrait else Vector2(1.0, 0.0)
		var far: float = UiScale.dp(_touch.settings.drawer_swipe_dp) + 10.0
		var zone: Control = (_hud("Head") if portrait else _hud("Backdrop")) as Control
		var from: Vector2 = zone.get_global_rect().get_center()
		TouchEvents.press(get_viewport(), 0, from)  # On the drawer.
		_sidebar.collapse()  # It folds under the finger,
		_sidebar.open()  # and opens again.
		TouchEvents.drag(get_viewport(), 0, from + toward * far * 0.5, toward * far * 0.5)
		TouchEvents.drag(get_viewport(), 0, from + toward * far, toward * far * 0.5)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		TouchEvents.release(get_viewport(), 0, from + toward * far)


## The pill folds while the drawer is open (P120d: the drawer's head shows the economy) and is back,
## where it was, when the drawer closes.
func test_the_pill_folds_while_the_drawer_is_open() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size, null, false, false)
		var pill: Control = _hud("EconomyPill") as Control
		var before: Rect2 = pill.get_global_rect()
		_sidebar.open()
		await _settle()
		assert_bool(pill.is_visible_in_tree()).override_failure_message(str(size)).is_false()
		_sidebar.collapse()
		await _settle()
		assert_bool(pill.is_visible_in_tree()).override_failure_message(str(size)).is_true()
		assert_bool(pill.get_global_rect() == before).override_failure_message(str(size)).is_true()


func _swipe(from: Vector2, by: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, from + by * 0.5, by * 0.5)
	TouchEvents.drag(get_viewport(), 0, from + by, by * 0.5)
	TouchEvents.release(get_viewport(), 0, from + by)
	_now_ms += 1000


## Fails when a gesture's work left the menu open or told the wrong number of times.
func _expect_down(why: String, told: int = 1) -> void:
	assert_bool(_sidebar.is_open()).override_failure_message("%s: still open" % why).is_false()
	assert_int(_told).override_failure_message("%s: told %d times" % [why, _told]).is_equal(told)


## The menu open again and the count of `map_gesture`s at 0, the selection and the Commands cleared.
func _reopen() -> void:
	_sidebar.open()
	_forget()


func _forget() -> void:
	_told = 0
	_sent.clear()


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


## A tap on the picture of building `id`, the camera on it.
func _tap_building(id: int) -> void:
	var node: Node2D = _buildings.building(id)
	_aim_camera(node.position)
	_forget()
	_tap(_camera.world_to_screen(node.position))


## The point of the screen where the camera's aim is held: the middle, and upright the middle of
## the upper half, because the open sheet covers the lower half.
func _view_point() -> Vector2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(size.x * 0.5, size.y * (0.25 if HudLayout.is_portrait() else 0.5))


## Centres the camera on `world` so that it shows at `_view_point()`.
func _aim_camera(world: Vector2) -> void:
	_camera.centre_on(world)
	if HudLayout.is_portrait():
		_camera.position.y += get_viewport().get_visible_rect().size.y * 0.25 / _camera.zoom.y


## A ground point clear of the HUD and of the buildings, at the middle of the view.
func _ground() -> Vector2:
	_aim_camera(IsoProjection.cell_centre_px(16, 12))
	return _view_point()


func _move_ghost(tile: Vector2i) -> void:
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = _camera.world_to_screen(IsoProjection.cell_centre_px(tile.x, tile.y))
	_controller.handle_gesture(tap)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size` (under `metrics`, a profile; null for the engine's own), the match
## paused, the Commands caught and the structure ready in the published snapshot, or with `built`
## through the queue so that it stays ready on the next tick. The menu's slide runs on the test's
## steps, and so does the touch input's clock.
func _open(
	size: Vector2i, metrics: UiMetrics = null, built: bool = false, drawer: bool = true
) -> void:
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
	_placement = _main.get_node("PlacementController")
	_units = _main.get_node("UnitLayer")
	_buildings = _main.get_node("BuildingLayer")
	_sidebar = _main.get_node("Hud").find_child("BuildSidebar", true, false)
	var instant: InputSettings = _camera.settings.duplicate()  # The snap is a tween on wall time.
	instant.zoom_snap_ms = 0
	_camera.settings = instant
	_sidebar.set_process(false)
	_now_ms = 0
	_sent.clear()
	_told = 0
	_touch.clock = func() -> int: return _now_ms
	_touch.vibrate = func(_ms: int) -> void: pass
	_touch.map_gesture.connect(func() -> void: _told += 1)
	_controller.vibrate = func(_ms: int) -> void: pass
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_camera.zoom = Vector2.ONE
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	if built:
		CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
		_runner.run_ticks(BUILD_TICKS)
	else:
		Rig.make_ready(_runner.snapshot)
	Rig.explore(_runner.snapshot)
	_sidebar.refresh()
	if drawer:
		_sidebar.open()
	await _settle()
