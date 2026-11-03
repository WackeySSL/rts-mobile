extends GdUnitTestSuite
## Where the minimap is at the six sizes of ScreenSizes.ALL with the engine's own metrics and at
## every profile of both orientations, also with a cutout (plan P88, moved by P121; ADR 0015
## section 5, ADR 0025 section 7). Since P121 it is the full radar map: the one `Minimap` node
## stands in the box under the 48 dp head of `RadarMap` (a 2:1 box at least 96 dp high, the rect
## of `HudCorners.place`), in both orientations, and nowhere else. Nothing of it remains in the
## build menu: the portrait band's body row and the strip have no minimap, `MinimapSlot` is gone,
## the item row takes the band's whole row (and keeps its three whole tiles on the 6-inch phone and
## two at 360 dp), and neither the scope nor the full map stands in the bottom band. A turn keeps
## the one node and its picture and it goes on jumping the camera. How the rest of the band sits is
## test_build_sidebar_layout's and test_build_sidebar_items_layout's, the full map's head, pin and
## timer are test_radar_map's, and the jump itself is test_minimap's.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const RadarRig: GDScript = preload("res://tests/ui/support/radar_rig.gd")
const TOLERANCE_PX: float = 0.5
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]

var _window_size_before: Vector2i
var _main: Node2D
var _sidebar: BuildSidebar
var _minimap: Minimap
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_the_minimap_fills_the_box_of_the_full_map_in_both_orientations() -> void:
	for screen: Dictionary in RadarRig.screens():
		await _open(screen["size"], screen["metrics"])
		_open_radar()
		await _settle()
		var why: String = str(screen["label"])
		var expected: Rect2 = RadarRig.rects(get_viewport(), true)[HudCorners.MAP_BOX]
		var mini: Rect2 = _rect(_minimap)
		var box: Rect2 = _box()
		var safe: Rect2 = UiScale.safe_rect_base()
		var at: String = "%s: minimap %s, box %s, expected %s" % [why, mini, box, expected]
		assert_object(_minimap.get_parent()).override_failure_message(at).is_same(_hud("RadarMap"))
		assert_bool(_minimap.is_visible_in_tree()).override_failure_message(at).is_true()
		assert_vector(mini.position).override_failure_message(at).is_equal_approx(
			expected.position, Vector2.ONE * TOLERANCE_PX
		)
		assert_vector(mini.size).override_failure_message(at).is_equal_approx(
			expected.size, Vector2.ONE * TOLERANCE_PX
		)
		assert_vector(box.size).override_failure_message(at).is_equal_approx(
			mini.size, Vector2.ONE * 0.01
		)
		assert_bool(safe.encloses(mini)).override_failure_message(at).is_true()
		assert_float(box.size.x).override_failure_message(at).is_equal_approx(
			box.size.y * 2.0, 0.01
		)
		assert_float(box.size.y).override_failure_message(at).is_greater_equal(
			UiScale.dp(96.0) - TOLERANCE_PX
		)
		assert_array(_sent).is_empty()


## Nothing of the minimap is in the build menu any more, in the open band or the strip upright or
## the floating panel sideways: no `MinimapSlot`, no minimap among the band's descendants, the item
## row as wide as the band's inner row, and neither the scope nor the open full map in the band.
func test_the_band_the_strip_and_the_panel_have_no_minimap_and_the_radar_stays_off_the_bottom(
) -> void:
	for screen: Dictionary in RadarRig.screens():
		await _open(screen["size"], screen["metrics"])
		var why: String = str(screen["label"])
		assert_object(_hud("MinimapSlot")).override_failure_message(why).is_null()
		(
			assert_object(_sidebar.find_child("Minimap", true, false))
			. override_failure_message(why)
			. is_null()
		)
		assert_bool(_sidebar.is_ancestor_of(_minimap)).override_failure_message(why).is_false()
		assert_object(_minimap.get_parent()).override_failure_message(why).is_same(_hud("RadarMap"))
		if not UiScale.is_portrait_size(screen["size"]):
			continue
		for collapsed: bool in [false, true]:
			if collapsed:
				_sidebar.collapse()
			_open_radar()
			await _settle()
			var band: Rect2 = _rect(_sidebar)
			var at: String = "%s, %s: band %s" % [why, "strip" if collapsed else "band", band]
			for part: String in ["RadarScope", "RadarMap"]:
				(
					assert_float(_rect(part).end.y)
					. override_failure_message("%s, %s %s" % [at, part, _rect(part)])
					. is_less_equal(band.position.y + TOLERANCE_PX)
				)
			if not collapsed:
				var edge: StyleBox = _hud("Backdrop").get_theme_stylebox(&"panel")
				var inner_end: float = band.end.x - edge.get_margin(SIDE_RIGHT)
				assert_float(_rect("Items").end.x).override_failure_message(at).is_equal_approx(
					inner_end, 1.5
				)
				assert_float(_rect("Tabs").end.x).override_failure_message(at).is_less_equal(
					inner_end + TOLERANCE_PX
				)
		_sidebar.open()


## ADR 0015 section 5's budget: the item row keeps three whole 64 dp tiles on the 6-inch phone and
## two at 360 dp, and the three tabs 48 dp (the minimap no longer takes a share of the row, P121).
func test_the_item_row_keeps_three_whole_tiles_on_the_6_inch_phone_and_two_at_360_dp() -> void:
	for case: Array in [[&"android_6in_portrait", 3], [&"web_phone_portrait", 2]]:
		var metrics: UiMetrics = UiProfiles.by_name(case[0])
		await _open(metrics.window_size, metrics)
		var items: Rect2 = _rect("Items")
		var whole: int = 0
		for node: Node in _sidebar.find_children("Tile_*", "", true, false):
			var tile: Control = node as Control
			whole += 1 if tile.visible and items.encloses(tile.get_global_rect().grow(-1.0)) else 0
		var why: String = "%s: %d whole tiles in %s" % [case[0], whole, items]
		assert_int(whole).override_failure_message(why).is_greater_equal(case[1])
		var least: float = UiScale.dp(48.0) - TOLERANCE_PX
		for tab: String in ["TabStructures", "TabInfantry", "TabVehicles"]:
			assert_float(_rect(tab).size.x).override_failure_message(why).is_greater_equal(least)


## A turn keeps the one node, its parent and its picture, puts the box in the other orientation's
## place and the minimap goes on centring the camera where it is touched; it sends no Command.
func test_a_turn_keeps_the_one_minimap_in_the_full_map_and_it_goes_on_jumping() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
	await _open(landscape.window_size, landscape)
	_open_radar()
	_state().pinned = true  # No timer folds it under the case.
	var camera: RtsCamera = _main.get_node("Camera")
	var picture: MinimapImage = _minimap.picture()
	var target: Vector2 = IsoProjection.ground_to_px(10000, 6000)
	for turn: UiMetrics in [portrait, landscape, portrait, landscape]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		var why: String = "%s: minimap in %s" % [turn.window_size, _minimap.get_parent().name]
		var expected: Rect2 = RadarRig.rects(get_viewport(), true)[HudCorners.MAP_BOX]
		assert_object(_hud("Minimap")).override_failure_message(why).is_same(_minimap)
		assert_object(_minimap.get_parent()).override_failure_message(why).is_same(_hud("RadarMap"))
		assert_object(_minimap.picture()).is_same(picture)
		assert_bool(_minimap.is_visible_in_tree()).override_failure_message(why).is_true()
		assert_bool(UiScale.safe_rect_base().encloses(_rect(_minimap))).is_true()
		assert_vector(_rect(_minimap).position).override_failure_message(why).is_equal_approx(
			expected.position, Vector2.ONE * TOLERANCE_PX
		)
		camera.centre_on(Vector2.ZERO)
		var at: Vector2 = _rect(_minimap).position + _minimap.world_to_local(target)
		TouchEvents.press(get_viewport(), 0, at)
		TouchEvents.release(get_viewport(), 0, at)
		assert_vector(camera.position).override_failure_message(why).is_equal_approx(
			target, Vector2(0.1, 0.1)
		)
	assert_array(_sent).is_empty()


## Unfolds the full map, which the minimap is the body of.
func _open_radar() -> void:
	_state().open(HudState.Unfold.RADAR)


func _state() -> HudState:
	return (_hud("HudStateFeed") as HudStateFeed).state


## The minimap's 2:1 box in base px on the screen.
func _box() -> Rect2:
	var box: Rect2 = _minimap.box_rect()
	return Rect2(_rect(_minimap).position + box.position, box.size)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## The rect of a HUD Control, by name or itself.
func _rect(control: Variant) -> Rect2:
	var node: Control = control if control is Control else _hud(control as String)
	return node.get_global_rect()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


## A new main scene at `size`, under `metrics` (a profile; null for the engine's own), its match
## paused, the Commands caught, the sidebar reading a runner of its own with a base for its tiles
## (the map's layers have no art for a building before P84).
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
	_main.get_node("MatchRunner").paused = true
	add_child(_main)
	await await_idle_frame()
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = _main.get_node("MatchRunner").scenario
	_sidebar = _hud("BuildSidebar")
	_sidebar.runner = runner
	var world: World = Sw.world()
	Sw.own(world, BASE)
	runner.snapshot = Sw.snapshot(world)
	_sidebar.refresh()
	_minimap = _hud("Minimap")
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = (func(
		command: Command
	) -> void:
		_sent.append(command))
	await _settle()
