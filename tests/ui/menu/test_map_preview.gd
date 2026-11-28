extends GdUnitTestSuite
## The map select's picture of the chosen map (plan P666b): built from the scenario's data (the
## terrain in the minimap's colours, each start in its team colour), changing with the map and the
## side, dimmed for a locked map, and in the frame at the six sizes of ADR 0015 section 6.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const FakeRank: GDScript = preload("res://tests/ui/support/fake_rank_progression.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const KESTREL: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const KESTREL_MIRRORED: String = "res://data/scenarios/skirmish_kestrel_flats_mirrored.tres"
const HERON: String = "res://data/scenarios/skirmish_heron_fords.tres"

var _window_size_before: Vector2i
var _menu: Control
var _stack: MenuStack
var _screen: MapSelect
var _progression: Node
var _flow: Node


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_progression = FakeRank.new()
	_flow = FakeFlow.new()


func after_test() -> void:
	UiScale.clear_override()
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	for node: Node in [_progression, _flow]:
		if is_instance_valid(node):
			node.free()


func test_the_image_comes_from_the_map_data() -> void:
	var scenario: ScenarioDef = load(KESTREL) as ScenarioDef
	var image: Image = MapPreview.build(scenario)
	var size: Vector2i = scenario.map.size_tiles()
	assert_vector(Vector2i(image.get_size())).is_equal(size * MapPreview.PX_PER_CELL)
	# Every cell is the palette's colour of the terrain the map's symbol names (away from a start).
	var by_symbol: Dictionary[String, StringName] = {}
	for def: TerrainDef in scenario.map.terrain.terrains:
		by_symbol[def.symbol] = def.id
	var starts: Dictionary[int, Vector2i] = MapPreview.starts(scenario)
	var reach: int = MapPreview.MARK_RADIUS + MapPreview.OUTLINE
	for y: int in size.y:
		for x: int in size.x:
			if _near_a_start(Vector2i(x, y), starts, reach):
				continue
			var want: Color = TerrainPalette.colour(by_symbol[scenario.map.rows[y][x]])
			(
				assert_object(_centre(image, Vector2i(x, y)))
				. override_failure_message("cell %d,%d" % [x, y])
				. is_equal(want)
			)
	# Two spot checks against the table itself: a sand cell and a grass cell.
	assert_object(_centre(image, Vector2i(51, 2))).is_equal(Color("CDB98F"))
	assert_object(_centre(image, Vector2i(0, 0))).is_equal(Color("5E7D4A"))
	# Both starts are marked in the team colour: Ironward orange, Facet blue.
	assert_array(starts.keys()).contains_exactly([1, 2])
	assert_object(_centre(image, starts[1])).is_equal(Color("#E8681F"))
	assert_object(_centre(image, starts[2])).is_equal(Color("#3F6FE0"))
	# The mark has an ink edge and is wider than one cell.
	var edge: Vector2i = starts[1] + Vector2i(MapPreview.MARK_RADIUS + 1, 0)
	assert_object(_centre(image, edge)).is_equal(MapPreview.INK)
	var inside: Vector2i = starts[1] + Vector2i(MapPreview.MARK_RADIUS, 0)
	assert_object(_centre(image, inside)).is_equal(Color("#E8681F"))
	# Another map is another picture, and the mirrored scenario swaps the two colours.
	var other: Image = MapPreview.build(load(HERON) as ScenarioDef)
	assert_bool(other.get_data() == image.get_data()).is_false()
	var mirrored: Image = MapPreview.build(load(KESTREL_MIRRORED) as ScenarioDef)
	assert_object(_centre(mirrored, starts[1])).is_equal(Color("#3F6FE0"))


func test_the_picture_is_kept_per_scenario_file() -> void:
	MapPreview.forget()
	var first: ImageTexture = MapPreview.texture_for(KESTREL)
	assert_object(first).is_not_null()
	assert_object(MapPreview.texture_for(KESTREL)).is_same(first)
	assert_object(MapPreview.texture_for(HERON)).is_not_same(first)
	assert_object(MapPreview.texture_for("res://data/nothing.tres")).is_null()


func test_the_preview_follows_the_map_and_the_side() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]))
	assert_object(_screen._preview.texture).is_same(MapPreview.texture_for(KESTREL))
	assert_str(_screen._preview_name.text).is_equal("KESTREL FLATS")
	assert_bool(_screen._preview_dim.visible).is_false()
	_progression.rank_now = 99
	_screen._refresh()
	_screen._pick_map(&"map_2")
	assert_object(_screen._preview.texture).is_same(MapPreview.texture_for(HERON))
	assert_str(_screen._preview_name.text).is_equal("HERON FORDS")
	_screen._pick_map(&"kestrel_flats")
	_screen._pick_side(&"renew")
	assert_object(_screen._preview.texture).is_same(MapPreview.texture_for(KESTREL_MIRRORED))


func test_a_locked_map_still_shows_its_picture_dimmed_with_its_lock() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]))
	assert_bool(_screen.is_open(&"map", &"map_2")).is_false()
	_screen.map_id = &"map_2"
	_screen._refresh()
	assert_object(_screen._preview.texture).is_same(MapPreview.texture_for(HERON))
	assert_bool(_screen._preview_dim.visible).is_true()
	assert_str(_screen._preview_dim.theme_type_variation).is_equal("MenuMapPreviewDim")
	assert_bool(_screen._notes[&"map_2"].visible).is_true()


func test_the_preview_fits_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size))
		var label: String = str(size)
		var slot: Control = _screen.find_child("MapPreviewSlot", true, false) as Control
		var rect: Rect2 = slot.get_global_rect()
		var window: Rect2 = Rect2(Vector2.ZERO, Vector2(size))
		assert_float(rect.position.x).override_failure_message(label).is_greater_equal(0.0)
		assert_float(rect.end.x).override_failure_message(label).is_less_equal(window.end.x)
		assert_float(rect.size.y).override_failure_message(label).is_greater(UiScale.dp(60.0))
		# The picture sits above the map rows, and the rows keep their touch size.
		var first_row: Rect2 = _screen._map_cards[&"kestrel_flats"].get_global_rect()
		assert_float(rect.end.y).override_failure_message(label).is_less_equal(first_row.position.y)
		assert_float(first_row.size.y).override_failure_message(label).is_greater_equal(
			UiScale.dp(48.0) - 0.5
		)
		assert_int(slot.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		_close()


func _centre(image: Image, cell: Vector2i) -> Color:
	var half: int = MapPreview.PX_PER_CELL / 2
	return image.get_pixel(
		cell.x * MapPreview.PX_PER_CELL + half, cell.y * MapPreview.PX_PER_CELL + half
	)


func _near_a_start(cell: Vector2i, starts: Dictionary[int, Vector2i], reach: int) -> bool:
	for start: Vector2i in starts.values():
		if absi(cell.x - start.x) <= reach and absi(cell.y - start.y) <= reach:
			return true
	return false


func _open(profile: UiMetrics) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_screen = MapSelect.new()
	_screen.progression = _progression
	_screen.flow = _flow
	_screen.catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	_stack.push(_screen)
	for _frame: int in range(3):
		await await_idle_frame()


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	assert_bool(false).override_failure_message("no profile for %s" % size).is_true()
	return null
