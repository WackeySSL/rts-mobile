extends GdUnitTestSuite
## The build sidebar's item tiles in both orientations (plan P85b, ADR 0015 section 5 and ADR
## 0019 section 1), at the six sizes of ScreenSizes.ALL with the engine's own metrics and at every
## profile of both orientations, also with a cutout: every tile of each tab is at least 64 dp,
## clear of its neighbours; in landscape the tiles are a grid as wide as the zone holds, with its
## first row inside the zone and the rest a scroll away; in the portrait band they are one row that
## scrolls sideways, with at least three whole tiles in view; a short screen's band, which gives
## way to its floor, still holds the row; and a turn keeps the tiles and sends nothing. The zone
## itself is test_build_sidebar_layout's, the tiles' states and orders are
## test_build_sidebar_items and test_build_sidebar_orders.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
## A grid rounds its row heights and its gap to whole px (each by less than 1).
const ROUNDING_PX: float = 2.0
const TABS: Array[int] = [World.Tab.STRUCTURES, World.Tab.INFANTRY, World.Tab.VEHICLES]
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]
## Whole tiles that a portrait band shows with the sidebar alone in it (the minimap of plan P88
## takes the band's right end, ADR 0015 section 5: P88 re-runs this with it).
const WHOLE_TILES: int = 3

var _window_size_before: Vector2i
var _main: Node2D
var _sidebar: BuildSidebar
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


## The override and the zone are static state: leaving one behind changes every later suite.
func after_test() -> void:
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


func test_the_tiles_of_every_tab_fit_the_zone_in_both_orientations_at_every_size() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		for tab: int in TABS:
			_sidebar.select_tab(tab)
			await _settle()
			var why: String = "%s, tab %d" % [screen["label"], tab]
			var items: Rect2 = _rect("Items")
			var tiles: Array[ItemTile] = _visible_tiles()
			assert_int(tiles.size()).override_failure_message(why).is_greater(0)
			var least: float = UiScale.dp(64.0) - TOLERANCE_PX
			for tile: ItemTile in tiles:
				var rect: Rect2 = tile.get_global_rect()
				var at: String = "%s: %s %s in items %s" % [why, tile.name, rect, items]
				assert_float(rect.size.x).override_failure_message(at).is_greater_equal(least)
				assert_float(rect.size.y).override_failure_message(at).is_greater_equal(least)
				assert_float(rect.size.x).override_failure_message(at).is_less_equal(least + 2.0)
				assert_bool(rect.position.x >= items.position.x - TOLERANCE_PX).is_true()
				assert_bool(rect.position.y >= items.position.y - TOLERANCE_PX).is_true()
				(
					assert_bool(rect.end.x <= items.end.x + TOLERANCE_PX or HudLayout.is_portrait())
					. is_true()
				)
			for first: int in tiles.size():
				for second: int in range(first + 1, tiles.size()):
					var pair: String = (
						"%s: %s and %s" % [why, tiles[first].name, tiles[second].name]
					)
					var meet: bool = tiles[first].get_global_rect().intersects(
						tiles[second].get_global_rect()
					)
					assert_bool(meet).override_failure_message(pair).is_false()
			_assert_zone(tiles, items, why)
		assert_array(_sent).is_empty()


## The first row is inside the zone and its safe rect; landscape wraps by the zone's width, with
## the rest of the rows below; portrait is one row.
func _assert_zone(tiles: Array[ItemTile], items: Rect2, why: String) -> void:
	var grid: GridContainer = _sidebar.find_children("*", "GridContainer", true, false)[0]
	var scroll: ScrollContainer = _sidebar.find_child("Items", true, false)
	var safe: Rect2 = UiScale.safe_rect_base()
	var gap: float = UiScale.dp(8.0)
	var first: Rect2 = tiles[0].get_global_rect()
	assert_bool(safe.encloses(first.intersection(items))).override_failure_message(why).is_true()
	(
		assert_bool(items.encloses(first))
		. override_failure_message("%s: first %s" % [why, first])
		. is_true()
	)
	if HudLayout.is_portrait():
		assert_int(grid.columns).override_failure_message(why).is_equal(tiles.size())
		assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_SHOW_NEVER)
		assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
		var whole: int = 0
		for tile: ItemTile in tiles:
			var rect: Rect2 = tile.get_global_rect()
			assert_float(rect.position.y).override_failure_message(why).is_equal_approx(
				first.position.y, TOLERANCE_PX
			)
			whole += 1 if items.encloses(rect.grow(-TOLERANCE_PX)) else 0
		assert_int(whole).override_failure_message(why).is_greater_equal(
			mini(tiles.size(), WHOLE_TILES)
		)
	else:
		var columns: int = maxi(floori((items.size.x + gap) / (UiScale.dp(64.0) + gap)), 1)
		assert_int(grid.columns).override_failure_message("%s: %s" % [why, items]).is_equal(columns)
		assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_SHOW_NEVER)
		assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
		for at: int in tiles.size():
			var rect: Rect2 = tiles[at].get_global_rect()
			(
				assert_bool(rect.end.x <= items.end.x + TOLERANCE_PX)
				. override_failure_message(why)
				. is_true()
			)
			if at >= columns:  # The next row starts below the one above it.
				var above: Rect2 = tiles[at - columns].get_global_rect()
				var rows: String = "%s: %s below %s, gap %.2f" % [why, rect, above, gap]
				assert_float(rect.position.y).override_failure_message(rows).is_equal_approx(
					above.end.y + gap, ROUNDING_PX
				)
				assert_float(rect.position.x).override_failure_message(why).is_equal_approx(
					above.position.x, TOLERANCE_PX
				)


## A short screen's band has given way to its floor (ADR 0015 section 5), and the row of tiles, at
## 64 dp, still fits it: the sidebar's own height is never above its zone, and nothing leaves it.
func test_the_band_that_gave_way_still_holds_the_row_of_tiles() -> void:
	for case: Array in [[1950, 184.0], [1680, 172.0]]:
		var stretch: float = minf(1080.0 / 720.0, float(case[0]) / 1280.0)
		var metrics: UiMetrics = UiMetrics.create(
			"Web", 288, 3.0, stretch, Vector2i(1080, case[0]), Rect2i()
		)
		await _open(metrics.window_size, metrics)
		var why: String = "%d px tall" % case[0]
		assert_float(HudLayout.bottom_zone_dp).override_failure_message(why).is_equal_approx(
			case[1], 0.01
		)
		var band: Rect2 = _rect(_sidebar)
		var items: Rect2 = _rect("Items")
		assert_float(items.size.y).override_failure_message(why).is_greater_equal(
			UiScale.dp(64.0) - TOLERANCE_PX
		)
		for tile: ItemTile in _visible_tiles():  # The row scrolls sideways: only its height is held.
			var rect: Rect2 = tile.get_global_rect()
			var inside: bool = rect.position.y >= items.position.y - TOLERANCE_PX
			inside = inside and rect.end.y <= items.end.y + TOLERANCE_PX
			(
				assert_bool(inside)
				. override_failure_message("%s: %s %s" % [why, tile.name, rect])
				. is_true()
			)
		assert_bool(band.encloses(items)).override_failure_message(why).is_true()
		var needs: String = (
			"%s: the band needs %.2f px of its zone %.2f"
			% [why, _sidebar.get_combined_minimum_size().y, HudLayout.bottom_zone_px()]
		)
		(
			assert_float(_sidebar.get_combined_minimum_size().y)
			. override_failure_message(needs)
			. is_less_equal(HudLayout.bottom_zone_px() + TOLERANCE_PX)
		)


## A turn keeps the tiles (the same nodes, the same states) and re-lays them for the other
## orientation; it sends no Command and moves no scroll that no longer exists.
func test_a_turn_keeps_the_tiles_and_lays_them_out_for_the_other_orientation() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(landscape.window_size, landscape)
	var tiles: Array[ItemTile] = _visible_tiles()
	var grid: GridContainer = _sidebar.find_children("*", "GridContainer", true, false)[0]
	assert_int(grid.columns).is_equal(2)
	for turn: UiMetrics in [portrait, landscape, portrait]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		assert_array(_visible_tiles()).is_equal(tiles)
		assert_int(grid.columns).is_equal(2 if turn == landscape else tiles.size())
		var row: Rect2 = tiles[0].get_global_rect()
		var last: Rect2 = tiles[-1].get_global_rect()
		assert_bool(row.position.y == last.position.y).is_equal(turn == portrait)
		(
			assert_array(tiles.map(func(tile: ItemTile) -> int: return tile.state))
			. is_equal([0, 0, 0, 0, 0])
		)
	assert_array(_sent).is_empty()


func _visible_tiles() -> Array[ItemTile]:
	var tiles: Array[ItemTile] = []
	for node: Node in _sidebar.find_children("Tile_*", "", true, false):
		if (node as Control).visible:
			tiles.append(node as ItemTile)
	return tiles


## Every screen to test, as {label, size, metrics (a profile, or null for the engine's own)}. Each
## profile comes twice, the second time with a cutout of 100 px on the side where a phone has its
## camera (the left in landscape, the top in portrait).
func _screens() -> Array[Dictionary]:
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
	return all


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
## paused, with a snapshot of a base for the sidebar (which reads a runner of its own: the map's
## layers have no art for a building before P84).
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
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = (func(
		command: Command
	) -> void:
		_sent.append(command))
	await _settle()
