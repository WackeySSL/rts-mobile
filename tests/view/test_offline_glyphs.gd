extends GdUnitTestSuite
## The mark on a building a Blackout Array has switched off (plan P112b, ADR 0023 sections 2 and
## 10, assets/art/STYLE.md "Icons and glyphs"): the offline glyph over each building whose
## `offline_until` is above the snapshot's tick, in the bar layer at z 30, GLYPH_DP (32 dp) square
## at every zoom and on every screen, centred on the footprint centre and standing a dp over the
## place of the bar, so that a bar and a glyph never overlap. Own buildings always wear it, an
## enemy one only where the building layer shows it (the fog), a unit never, and it goes the tick
## the building is back on. The layer plans the squares (`glyph_rect`) and `_draw` paints that
## plan. On a 32 x 32 map: player 1's Headquarters (3x3, row 0), power plant (2x2, row 1) and rifle
## squad (row 4), and player 2's Headquarters (3x3, row 2) and defence (1x1, row 3); 1 dp is 1.75
## px.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const EDGE: Color = Color("1C2127")
const AMBER: Color = Color("F5A524")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 4, 4],
	[1, "power_plant", 10, 4],
	[2, "renew_hq", 4, 12],
	[2, "renew_defence", 10, 12],
	[1, "rifle_squad", 20, 20],
]
const GLYPH_DP: int = 32
const GAP_DP: int = 1  ## The bar's gap over the sprite, and the glyph's over the bar.
const BAR_HEIGHT_DP: int = 6
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
## The six screens of the shared list (ScreenSizes.ALL, entry by entry), each with its profile.
const SCREEN_PROFILES: Array[StringName] = [
	&"desktop",
	&"android_6in",
	&"web_tablet",
	&"desktop_portrait",
	&"android_6in_portrait",
	&"web_tablet_portrait",
]

var _window_size_before: Vector2i
var _now_ms: int = 0
var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _buildings: BuildingLayer
var _bars: HealthBarLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(0, 400)  # No map rect is set, so nothing clamps it.
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.runner = _runner
	add_child(sort)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.world_sort = sort
	_units.clock = func() -> int: return _now_ms
	add_child(_units)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.world_sort = sort
	_buildings.reveal_enemies = true
	add_child(_buildings)
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = _units
	_bars.building_layer = _buildings
	add_child(_bars)
	for layer: Node in [_units, _buildings]:
		layer.set_process(false)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_switched_off_building_wears_a_glyph_over_the_place_of_its_bar() -> void:
	_hit([0, 1], 1)  # Both show a bar, to measure the glyph against it.
	_off([0, 1])
	_frame()
	assert_int(_bars.glyph_count()).is_equal(2)
	var unit: float = _unit_px()
	for row: int in 2:
		var glyph: Rect2 = _bars.glyph_rect(row)
		var node: Node2D = _buildings.building(_id(row))
		assert_float(glyph.size.x).is_equal_approx(GLYPH_DP * unit, 0.01)
		assert_float(glyph.size.y).is_equal_approx(GLYPH_DP * unit, 0.01)
		assert_float(glyph.get_center().x).is_equal_approx(node.position.x, 0.01)
		# A dp over the top of the bar, which is a dp over the sheet's lift.
		var lift: float = _buildings.bar_lift_px(row)
		assert_float(lift).is_greater(0.0)
		var bar_top: float = node.position.y - lift - (GAP_DP + BAR_HEIGHT_DP) * unit
		assert_float(glyph.end.y).is_equal_approx(bar_top - GAP_DP * unit, 0.01)
		assert_float(_bar_top(row)).is_equal_approx(bar_top, 0.01)
	assert_float(_bars.glyph_rect(0).end.y).is_less(_bars.glyph_rect(1).end.y)  # The hall is taller.


func test_a_glyph_shows_without_a_hit_or_a_selection_and_the_bar_stays_out_of_it() -> void:
	_off([0])
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)
	assert_int(_bars.glyph_count()).is_equal(1)
	assert_int(_bars.rect_count()).is_equal(0)  # The glyph is not a rect of the plan.


func test_it_goes_the_tick_the_building_is_back_on() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.offline_until[0] = snap.tick + 2
	for tick_now: int in [snap.tick, snap.tick + 1]:
		snap.tick = tick_now
		_frame()
		assert_int(_bars.glyph_count()).override_failure_message("tick %d" % tick_now).is_equal(1)
	snap.tick += 1  # offline_until is not above the tick any more: the sim has it on again.
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)
	snap.offline_until[0] = 0  # A building never switched off.
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)


func test_an_enemy_building_wears_it_only_where_the_player_sees_it() -> void:
	_buildings.reveal_enemies = false
	_units.reveal_enemies = false
	_off([0, 2, 3])
	Rig.see(_runner.snapshot, 1, [])
	_buildings._process(0.0)
	_frame()
	assert_int(_bars.glyph_count()).is_equal(1)  # Own: always. The enemy ones: unseen.
	Rig.see(_runner.snapshot, 1, [Vector2i(10, 12)])  # The enemy defence's tile.
	_buildings._process(0.0)
	_frame()
	assert_int(_bars.glyph_count()).is_equal(2)
	var defence: Node2D = _buildings.building(_id(3))
	assert_float(_bars.glyph_rect(1).get_center().x).is_equal_approx(defence.position.x, 0.01)
	Rig.see(_runner.snapshot, 1, [])  # Out of sight again: the mark goes with the building.
	_buildings._process(0.0)
	_frame()
	assert_int(_bars.glyph_count()).is_equal(1)


func test_a_unit_never_wears_one_and_a_layer_without_buildings_draws_none() -> void:
	_off([4])  # The rifle squad.
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)
	_off([0])
	_bars.building_layer = null
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)


func test_the_glyph_is_32_dp_on_the_screen_at_every_zoom() -> void:
	_off([0, 3])
	var dp_px: float = UiScale.base_px_per_dp()
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_frame()
		for glyph: int in 2:
			var rect: Rect2 = _bars.glyph_rect(glyph)
			var wide: float = (
				(_camera.world_to_screen(rect.end) - _camera.world_to_screen(rect.position)).x
			)
			(
				assert_float(wide)
				. override_failure_message("glyph %d zoom %s" % [glyph, zoom])
				. is_equal_approx(GLYPH_DP * dp_px, 0.05)
			)


func test_the_glyph_is_the_same_size_in_dp_and_on_the_screen_on_every_screen() -> void:
	_off([0])
	var node: Node2D = _buildings.building(_id(0))
	var sizes: Array[Vector2i] = []
	for profile_name: StringName in SCREEN_PROFILES:
		var profile: UiMetrics = UiProfiles.by_name(profile_name)
		sizes.append(profile.window_size)
		UiScale.set_override(profile)
		get_window().size = profile.window_size
		await await_idle_frame()  # size_changed: the layer reads the dp again.
		_camera.zoom = Vector2.ONE
		_camera.position = node.position  # The hall in the middle of the screen.
		_frame()
		var rect: Rect2 = _bars.glyph_rect(0)
		var note: String = str(profile_name)
		assert_float(rect.size.x).override_failure_message(note).is_equal_approx(
			GLYPH_DP * UiScale.base_px_per_dp(), 0.05
		)
		var view: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		var on_screen: Rect2 = Rect2(
			_camera.world_to_screen(rect.position), rect.size * _camera.zoom
		)
		assert_bool(view.encloses(on_screen)).override_failure_message(note).is_true()
	assert_array(sizes).is_equal(ScreenSizes.ALL)  # 1280x720, 2400x1080, 2048x1536, both ways.


func test_the_glyph_is_painted_tinted_and_comes_from_the_art() -> void:
	assert_str(HealthBarLayer.GLYPH.resource_path).is_equal(
		"res://assets/art/svg/icons/glyph_offline.svg"
	)
	assert_that(HealthBarLayer.GLYPH.get_size()).is_equal(Vector2(128, 128))
	assert_that(_bars.glyph_color).is_equal(AMBER)  # STYLE.md: the HUD tints it amber.
	_off([0, 1])
	_frame()
	await await_idle_frame()  # The engine draws the layer.
	assert_int(_bars.glyph_count()).is_equal(2)
	assert_int(_bars.drawn_glyphs()).is_equal(2)
	_off([])  # Back on: one more frame draws the empty plan.
	_frame()
	await await_idle_frame()
	assert_int(_bars.drawn_glyphs()).is_equal(0)


## Sets the buildings of rows `rows` (and no other) offline for a while.
func _off(rows: Array[int]) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.offline_until.fill(0)
	for row: int in rows:
		snap.offline_until[row] = snap.tick + 450


## Lowers the hp of rows `rows` by `amount` and lets the unit layer see the hits.
func _hit(rows: Array[int], amount: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_units.sync_rows()
	for row: int in rows:
		snap.hp[row] -= amount
	_units._note_hits(snap)


func _frame() -> void:
	_units._process(0.0)
	_buildings._process(0.0)
	_bars._process(0.0)


func _id(row: int) -> int:
	return _runner.snapshot.unit_id[row]


func _unit_px() -> float:
	return UiScale.base_px_per_dp() / _camera.zoom.x


## The top edge of bar `row`: the least y among its edge rects.
func _bar_top(row: int) -> float:
	var top: float = INF
	for bar: int in _bars.bar_count():
		if _bars.bar_row(bar) != row:
			continue
		for index: int in range(_bars.bar_first_rect(bar), _bars.bar_end_rect(bar)):
			if _bars.rect_color(index) == EDGE:
				top = minf(top, _bars.rect_at(index).position.y)
	return top
