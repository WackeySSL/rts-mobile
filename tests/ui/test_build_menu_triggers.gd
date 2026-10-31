extends GdUnitTestSuite
## What opens and collapses the build menu (plan P85f, ADR 0024 sections 1, 5, 6 and 9), in the main
## scene through the real GUI at the six sizes of ScreenSizes.ALL. A match starts open. A tap, a
## double-tap, a long-press with its box, a pan, a pinch and a wheel step on the map collapse it and
## still do their own work; a touch on the ArmyBar, the SelectionPanel, the minimap, a tab, a card,
## a hold on a card or a scroll of the item row never does. The start of placement collapses it,
## the end of placement by a build or the X opens it again (it returns to the state placement began
## in) and a strike aim that ends placement leaves it down; the Ready badge shows only while the
## menu is collapsed and no placement runs, and a tap on it opens the menu on the Structures tab
## with the READY card in view and starts nothing; a tap on an own producer opens the menu on its
## tab with no visible move; a turn and a cancel_all() keep the state; a new match starts open.
## Player 1 has a Headquarters, two light tanks, a Heavy Yard and a Bunkhouse, and a finished
## structure in its queue.

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


func test_a_match_starts_open_and_each_gesture_on_the_map_collapses_it_and_still_does_its_work(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		_camera.centre_on(IsoProjection.cell_centre_px(16, 12))
		var ground: Vector2 = get_viewport().get_visible_rect().size * 0.5
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
		_camera.centre_on(IsoProjection.cell_centre_px(16, 12))
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


func test_a_touch_on_a_hud_control_never_collapses_the_menu() -> void:
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
			_hud("SelectionPanel") as Control,
			_hud("Minimap") as Control,
			_hud("TabVehicles") as Control,
			_hud("TabStructures") as Control,
			card,
		]
		for control: Control in touches:
			var note: String = "%s: a tap on %s" % [why, control.name]
			_tap(control.get_global_rect().get_center())
			assert_bool(_sidebar.is_open()).override_failure_message(note).is_true()
			assert_int(_told).override_failure_message(note).is_equal(0)
		assert_int(card.shakes).override_failure_message(why).is_equal(shakes + 1)  # A locked card.
		# A hold on a card (nothing queued, so nothing is cancelled), then a scroll of the row.
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


func test_the_ready_badge_shows_only_while_collapsed_and_not_placing() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(size)
		var why: String = str(size)
		var badge: Control = _hud("Ready") as Control
		assert_bool(badge.is_visible_in_tree()).override_failure_message(why).is_false()  # Open.
		_sidebar.collapse()
		await _settle()
		assert_bool(badge.is_visible_in_tree()).override_failure_message(why).is_true()
		_sidebar.open()
		await _settle()
		assert_bool(badge.is_visible_in_tree()).override_failure_message(why).is_false()
		_sidebar.collapse()
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
		await _settle()
		assert_bool(badge.is_visible_in_tree()).override_failure_message(why).is_false()
		_placement.cancel()  # Placement began collapsed: it ends collapsed.
		await _settle()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_false()
		assert_bool(badge.is_visible_in_tree()).override_failure_message(why).is_true()
		# Nothing ready, nothing to show.
		_runner.snapshot.queue_count[World.TABS + World.Tab.STRUCTURES] = 0
		_sidebar.refresh()
		await _settle()
		assert_bool(badge.is_visible_in_tree()).override_failure_message(why).is_false()


## A tap on the badge opens the menu on the Structures tab, the READY card in view, and starts no
## placement and no Command. The ready structure is the last card of its tab, so on the narrow
## phone the row has to scroll to it.
func test_a_tap_on_the_ready_badge_opens_the_structures_tab_with_the_card_in_view() -> void:
	var cases: Array[Dictionary] = []
	for size: Vector2i in ScreenSizes.ALL:
		cases.append({"size": size, "metrics": null, "label": str(size)})
	var narrow: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	cases.append({"size": narrow.window_size, "metrics": narrow, "label": "web_phone_portrait"})
	for case: Dictionary in cases:
		await _open(case["size"], case["metrics"])
		var why: String = str(case["label"])
		var turret: int = _runner.snapshot.type_ids.find(&"defence_turret")
		_runner.snapshot.queue_count[World.TABS + World.Tab.STRUCTURES] = 0
		Rig.make_ready(_runner.snapshot, turret)
		_sidebar.refresh()
		_sidebar.select_tab(World.Tab.VEHICLES)
		_sidebar.collapse()
		await _settle()
		var badge: Control = _hud("Ready") as Control
		assert_bool(badge.is_visible_in_tree()).override_failure_message(why).is_true()
		_tap(badge.get_global_rect().get_center())
		await _settle()
		await _settle()
		assert_bool(_sidebar.is_open()).override_failure_message(why).is_true()
		assert_int(_sidebar.tab).override_failure_message(why).is_equal(World.Tab.STRUCTURES)
		assert_bool(_placement.active).override_failure_message(why).is_false()
		assert_array(_sent).override_failure_message(why).is_empty()
		assert_int(_told).override_failure_message(why).is_equal(0)  # A HUD touch.
		var card: ItemTile = _sidebar.find_child("Tile_defence_turret", true, false) as ItemTile
		assert_int(card.state).is_equal(ItemTile.State.READY)
		var items: Control = _hud("Items") as Control
		var card_rect: Rect2 = card.get_global_rect()
		var in_view: String = "%s: card %s, row %s" % [why, card_rect, items.get_global_rect()]
		(
			assert_bool(items.get_global_rect().grow(TOLERANCE_PX).encloses(card_rect))
			. override_failure_message(in_view)
			. is_true()
		)
		if case["label"] == "web_phone_portrait":  # The fifth of five cards on a 360 dp phone.
			(
				assert_int((items as ScrollContainer).scroll_horizontal)
				. override_failure_message(in_view)
				. is_greater(0)
			)


func test_a_tap_on_an_own_producer_opens_the_menu_on_its_tab_with_no_visible_move() -> void:
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


func test_placement_collapses_the_menu_and_a_build_or_the_x_gives_it_back() -> void:
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


func test_a_build_gives_the_menu_back_and_a_strike_aim_or_the_matchs_end_does_not() -> void:
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
	# The end of the match opens nothing (the result screen covers the HUD).
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_sidebar.open()
	_runner.snapshot.match_end_tick = 5
	_sidebar.collapse()
	_placement.cancel()
	assert_bool(_sidebar.is_open()).is_false()
	# Placement that began in the collapsed menu ends in it.
	_runner.snapshot.match_end_tick = 0
	_sidebar.collapse()
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_placement.cancel()
	assert_bool(_sidebar.is_open()).is_false()


func test_a_turn_and_a_cancelled_gesture_keep_the_state_and_a_new_match_starts_open() -> void:
	await _open(ScreenSizes.LANDSCAPE[1], null)
	for open: bool in [true, false]:
		if open:
			_sidebar.open()
		else:
			_sidebar.collapse()
		_camera.centre_on(IsoProjection.cell_centre_px(16, 12))
		var ground: Vector2 = get_viewport().get_visible_rect().size * 0.5
		TouchEvents.press(get_viewport(), 0, ground)  # A finger down, no gesture yet.
		for size: Vector2i in [ScreenSizes.PORTRAIT[1], ScreenSizes.LANDSCAPE[1]]:
			get_window().size = size
			await _settle()
			assert_bool(_sidebar.is_open()).override_failure_message(str(size)).is_equal(open)
			assert_int(_told).is_equal(0)  # The cancel of the turn is no gesture on the map.
		TouchEvents.release(get_viewport(), 0, ground)
		assert_int(_told).is_equal(0)  # And the lift after it makes no tap.
		assert_bool(_sidebar.is_open()).is_equal(open)
	# A new match starts open, whatever the state at the end of the last.
	_sidebar.collapse()
	_runner.start()
	_sidebar.refresh()
	assert_bool(_sidebar.is_open()).is_true()


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
	_camera.centre_on(_camera.screen_to_world(_units.unit_screen_position(row)))
	return _units.unit_screen_position(row)


## A tap on the picture of building `id`, the camera on it.
func _tap_building(id: int) -> void:
	var node: Node2D = _buildings.building(id)
	_camera.centre_on(node.position)
	_forget()
	_tap(_camera.world_to_screen(node.position))


## A ground point clear of the HUD and of the buildings, at the middle of the view.
func _ground() -> Vector2:
	_camera.centre_on(IsoProjection.cell_centre_px(16, 12))
	return get_viewport().get_visible_rect().size * 0.5


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
func _open(size: Vector2i, metrics: UiMetrics = null, built: bool = false) -> void:
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
	await _settle()
