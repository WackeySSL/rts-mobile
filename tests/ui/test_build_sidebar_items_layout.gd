extends GdUnitTestSuite
## The drawer's item cards in both orientations (plan P85b and P120, ADR 0019 section 1, ADR 0025
## section 5), at the six sizes of ScreenSizes.ALL with the engine's own metrics and at every
## profile of both orientations, also with a cutout: what a state draws over the icon (the fill,
## the padlock, the banner) is seen above the cost's plate, the "Ready" banner takes the plate's
## place and never
## meets the count badge, and a turn keeps the tiles and sends nothing. The cards' sizes and columns
## and the drawer itself are test_build_drawer's, the tiles' states and orders are
## test_build_sidebar_items and test_build_sidebar_orders.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Sw: GDScript = preload("res://tests/ui/support/sidebar_world.gd")
const CUTOUT_PX: int = 100
const TOLERANCE_PX: float = 0.5
const TABS: Array[int] = [World.Tab.STRUCTURES, World.Tab.INFANTRY, World.Tab.VEHICLES]
const BASE: Array[String] = [
	"headquarters", "power_plant", "barracks", "refinery", "vehicle_factory"
]

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
	MenuRig.end()
	UiScale.clear_override()
	HudLayout.bottom_zone_dp = 0.0


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


## What a state draws over the icon is seen above the cost's plate (ADR 0019 section 1): the fill is
## a strip of the area above the plate even at a small share, rising to the tile's top at the end,
## and the padlock is whole above the plate, never under it. The "Ready" banner of a finished
## structure is the foot of the tile, in the plate's place (the item is paid for, so its cost is
## gone), and nothing is drawn under it either.
func test_the_fill_the_padlock_and_the_banner_stay_clear_of_the_cost_plate_at_every_size() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		var tile: ItemTile = _visible_tiles()[0]
		var whole: Rect2 = tile.get_global_rect()
		var plate: Rect2 = _part(tile, "Cost").get_global_rect()
		var above: Rect2 = Rect2(
			whole.position, Vector2(whole.size.x, plate.position.y - whole.position.y)
		)
		var why: String = "%s: tile %s, plate %s" % [screen["label"], whole, plate]
		assert_float(above.size.y).override_failure_message(why).is_greater(UiScale.dp(32.0))
		tile.show_state(ItemTile.State.LOCKED, 0, 0.0)
		await _settle()
		_assert_above(_part(tile, "Lock").get_global_rect(), above, "padlock, " + why)
		tile.show_state(ItemTile.State.READY, 1, 1.0)
		await _settle()
		var banner: Rect2 = _part(tile, "Banner").get_global_rect()
		var foot: String = "banner, %s: %s" % [why, banner]
		assert_bool(_part(tile, "Cost").visible).override_failure_message(foot).is_false()
		(
			assert_bool(whole.grow(TOLERANCE_PX).encloses(banner))
			. override_failure_message(foot)
			. is_true()
		)
		assert_float(banner.end.y).override_failure_message(foot).is_equal_approx(
			plate.end.y, TOLERANCE_PX
		)
		assert_float(banner.size.y).override_failure_message(foot).is_less_equal(plate.size.y)
		for share: float in [0.05, 0.1, 0.3, 0.99]:
			tile.show_state(ItemTile.State.AVAILABLE, 1, share)
			await _settle()
			var fill: Rect2 = _part(tile, "Fill").get_global_rect()
			var at: String = "fill at %.2f, %s: %s" % [share, why, fill]
			_assert_above(fill, above, at)
			assert_float(fill.size.y).override_failure_message(at).is_equal_approx(
				share * above.size.y, TOLERANCE_PX
			)
			assert_float(fill.end.y).override_failure_message(at).is_equal_approx(
				plate.position.y, TOLERANCE_PX
			)
		assert_array(_sent).is_empty()


## A finished structure is always the head of its queue, so its count badge always shows: the
## "Ready" banner and the badge share the tile and never meet, with the count of one digit or two,
## and the banner's text (the glyphs, not only its green chip) is whole inside the banner and tile.
func test_the_ready_banner_and_the_count_badge_never_meet_at_every_size() -> void:
	for screen: Dictionary in _screens():
		await _open(screen["size"], screen["metrics"])
		var tile: ItemTile = _visible_tiles()[0]
		var whole: Rect2 = tile.get_global_rect()
		for count: int in [1, 5, 12, 99]:
			tile.show_state(ItemTile.State.READY, count, 1.0)
			await _settle()
			var banner_label: Label = _part(tile, "Banner") as Label
			var banner: Rect2 = banner_label.get_global_rect()
			var text: Rect2 = _text_rect(banner_label)
			var badge: Rect2 = _part(tile, "Badge").get_global_rect()
			var why: String = (
				"%s, count %d: tile %s, banner %s, its text %s, badge %s"
				% [screen["label"], count, whole, banner, text, badge]
			)
			assert_bool(_part(tile, "Badge").visible).override_failure_message(why).is_true()
			assert_bool(banner_label.visible).override_failure_message(why).is_true()
			assert_bool(banner.intersects(badge)).override_failure_message(why).is_false()
			assert_bool(text.intersects(badge)).override_failure_message(why).is_false()
			(
				assert_bool(banner.grow(TOLERANCE_PX).encloses(text))
				. override_failure_message(why)
				. is_true()
			)
			(
				assert_bool(whole.grow(TOLERANCE_PX).encloses(badge))
				. override_failure_message(why)
				. is_true()
			)
			(
				assert_bool(whole.grow(TOLERANCE_PX).encloses(text))
				. override_failure_message(why)
				. is_true()
			)
		assert_array(_sent).is_empty()


## The rect of the glyphs of `label` (one line, centred), in the space of its global rect.
func _text_rect(label: Label) -> Rect2:
	var font: Font = label.get_theme_font(&"font")
	var font_size: int = label.get_theme_font_size(&"font_size")
	var text: Vector2 = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var box: Rect2 = label.get_global_rect()
	return Rect2(box.position + (box.size - text) / 2.0, text)


## `rect` lies inside the area `above` the cost plate, to half a px.
func _assert_above(rect: Rect2, above: Rect2, why: String) -> void:
	(
		assert_bool(above.grow(TOLERANCE_PX).encloses(rect))
		. override_failure_message("%s: %s, above %s" % [why, rect, above])
		. is_true()
	)


## A tile's part by name: the parts sit one level down, in the area above the cost and in a column.
func _part(tile: ItemTile, part: String) -> Control:
	return tile.find_child(part, true, false) as Control


## A turn keeps the tiles (the same nodes, the same states) and re-lays them for the other
## orientation: the card of the side panel, the card of the sheet, the grid in at least two columns;
## it sends no Command.
func test_a_turn_keeps_the_tiles_and_lays_them_out_for_the_other_orientation() -> void:
	var landscape: UiMetrics = UiProfiles.by_name(&"android_6in")
	var portrait: UiMetrics = UiProfiles.by_name(&"web_phone_portrait")
	await _open(landscape.window_size, landscape)
	var tiles: Array[ItemTile] = _visible_tiles()
	var grid: GridContainer = _sidebar.find_children("*", "GridContainer", true, false)[0]
	for turn: UiMetrics in [portrait, landscape, portrait]:
		UiScale.set_override(turn)
		get_window().size = turn.window_size
		await _settle()
		assert_bool(_sidebar.is_open()).is_true()
		assert_array(_visible_tiles()).is_equal(tiles)
		assert_int(grid.columns).is_greater_equal(2)
		var card: Vector2 = ItemTile.CARD_DP if turn == landscape else ItemTile.CARD_PORTRAIT_DP
		assert_float(tiles[0].get_global_rect().size.x).is_greater_equal(UiScale.dp(card.x) - 2.0)
		assert_bool((_part(tiles[0], "Caption") as Control).visible).is_true()
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
	_sidebar.open()
	_sent.clear()
	(_main.get_node("PlayerController") as PlayerController).command_sink = (func(
		command: Command
	) -> void:
		_sent.append(command))
	await _settle()
