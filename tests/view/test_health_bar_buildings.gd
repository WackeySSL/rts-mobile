extends GdUnitTestSuite
## The bar of a building (plan P115, assets/art/STYLE.md "Health bars", ADR 0023 section 2): as wide
## as its footprint (24, 40 and 56 dp for 1x1, 2x2 and 3x3), centred on the footprint centre, its
## bottom edge a gap above the sheet's `bar_lift_px`, plain for an own building and notched for an
## enemy one, filled by the hp it has left. It shows for a few seconds after a hit (selection comes
## with P115b) and only while the building layer says the building is shown: an enemy building has
## none unless a cell of its footprint is seen. Units' bars are in test_health_bars.gd. On a 32 x 32
## map: player 1's Headquarters (3x3, row 0), power plant (2x2, row 1) and Redoubt (1x1, row 2), and
## player 2's Headquarters (3x3, row 3) and defence (1x1, row 4); 1 dp is 1.75 px.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const EDGE: Color = Color("1C2127")
const OWN: Color = Color("30A46C")
const ENEMY: Color = Color("F5A524")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 4, 4],
	[1, "power_plant", 10, 4],
	[1, "defence_turret", 14, 4],
	[2, "renew_hq", 4, 12],
	[2, "renew_defence", 10, 12],
]
const WIDTH_DP: Array[int] = [56, 40, 24, 56, 24]
const HEIGHT_DP: int = 6
const GAP_DP: int = 1
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
	for layer: Node in [_units, _buildings, _bars]:
		layer.set_process(false)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_hit_building_has_a_bar_as_wide_as_its_footprint_over_the_sheets_lift() -> void:
	_hit([0, 1, 2, 3, 4], 1)
	_frame()
	assert_int(_bars.bar_count()).is_equal(5)
	for row: int in 5:
		var node: Node2D = _buildings.building(_runner.snapshot.unit_id[row])
		var box: Rect2 = _box(row)
		var unit: float = _unit_px()
		assert_float(box.size.x).is_equal_approx(WIDTH_DP[row] * unit, 0.01)
		assert_float(box.size.y).is_equal_approx(HEIGHT_DP * unit, 0.01)
		# Centred on the footprint centre, and the bottom edge a gap over the sheet's lift.
		assert_float(box.get_center().x).is_equal_approx(node.position.x, 0.01)
		var lift: float = float(_sheet(row).bar_lift_px)
		assert_float(box.end.y).is_equal_approx(node.position.y - lift - GAP_DP * unit, 0.01)
		assert_float(lift).is_greater(0.0)
	# The lifts are the sheets' own: a 3x3 hall is taller than the 1x1 bunker.
	assert_float(_buildings.bar_lift_px(0)).is_greater(_buildings.bar_lift_px(2))
	assert_float(_buildings.bar_lift_px(0)).is_equal(float(_sheet(0).bar_lift_px))


func test_the_size_in_dp_and_the_lift_on_screen_hold_at_every_zoom() -> void:
	_hit([0, 2], 1)
	var dp_px: float = UiScale.base_px_per_dp()
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_frame()
		for row: int in [0, 2]:
			var at: Vector2 = _camera.world_to_screen(_buildings.building(_id(row)).position)
			var top_left: Vector2 = _camera.world_to_screen(_box(row).position)
			var bottom_right: Vector2 = _camera.world_to_screen(_box(row).end)
			var note: String = "row %d zoom %s" % [row, zoom]
			(
				assert_float(bottom_right.x - top_left.x)
				. override_failure_message(note)
				. is_equal_approx(WIDTH_DP[row] * dp_px, 0.05)
			)
			# The lift is world px, so it grows with the zoom; the gap is 1 dp on the screen.
			var gap: float = _sheet(row).bar_lift_px * zoom + GAP_DP * dp_px
			assert_float(at.y - bottom_right.y).override_failure_message(note).is_equal_approx(
				gap, 0.05
			)


func test_the_bar_is_the_same_size_in_dp_on_every_screen_and_orientation() -> void:
	_hit([0, 1, 2], 1)
	var sizes: Array[Vector2i] = []
	for profile_name: StringName in SCREEN_PROFILES:
		var profile: UiMetrics = UiProfiles.by_name(profile_name)
		sizes.append(profile.window_size)
		UiScale.set_override(profile)
		get_window().size = profile.window_size
		await await_idle_frame()  # size_changed: the layer reads the dp again.
		var dp_px: float = UiScale.base_px_per_dp()
		_camera.zoom = Vector2.ONE  # A turn of the phone moves the camera's zoom with the window.
		_frame()
		for row: int in 3:
			var note: String = "%s row %d" % [profile_name, row]
			var box: Rect2 = _box(row)
			assert_float(box.size.x).override_failure_message(note).is_equal_approx(
				WIDTH_DP[row] * dp_px, 0.05
			)
			assert_float(box.size.y).override_failure_message(note).is_equal_approx(
				HEIGHT_DP * dp_px, 0.05
			)
	assert_array(sizes).is_equal(ScreenSizes.ALL)  # 1280x720, 2400x1080, 2048x1536, both ways.


func test_a_footprint_larger_than_3x3_takes_the_widest_bar_and_never_another_class() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.type_foot_w[snap.type_index[0]] = 4  # Data allows at most 3x3; the layer must not stray.
	_hit([0, 3], 1)
	_frame()
	assert_float(_box(0).size.x).is_equal_approx(56 * _unit_px(), 0.01)
	assert_int(_parts(0, OWN).size()).is_equal(1)  # Still the own bar, not an enemy's.
	assert_int(_parts(3, ENEMY).size()).is_equal(3)


func test_an_own_building_bar_is_plain_and_an_enemy_one_has_the_notch() -> void:
	_hit([0, 3, 4], 1)
	_frame()
	var unit: float = _unit_px()
	assert_array(_dp_rects(0, EDGE)).is_equal([Rect2i(0, 0, 56, 6)])
	# a = (56 - 4) / 2 = 26 for the enemy 3x3, (24 - 4) / 2 = 10 for the enemy 1x1.
	assert_array(_dp_rects(3, EDGE)).is_equal(
		[Rect2i(0, 0, 26, 6), Rect2i(30, 0, 26, 6), Rect2i(26, 2, 4, 4)]
	)
	assert_array(_dp_rects(4, EDGE)).is_equal(
		[Rect2i(0, 0, 10, 6), Rect2i(14, 0, 10, 6), Rect2i(10, 2, 4, 4)]
	)
	assert_int(_parts(0, OWN).size()).is_equal(1)
	assert_int(_parts(3, OWN).size()).is_equal(0)  # Never the own colour on an enemy.
	assert_int(_parts(3, ENEMY).size()).is_equal(3)
	assert_float(unit).is_greater(0.0)


@warning_ignore("integer_division")
func test_the_fill_is_the_hp_it_has_left_with_a_floor_of_one_dp() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var max_hp: int = snap.type_max_hp[snap.type_index[1]]
	for hp: int in [max_hp - 1, max_hp / 2, max_hp / 10, 1]:
		snap.hp[1] = max_hp
		_units.sync_rows()
		_units._note_hits(snap)  # The layer sees it whole.
		snap.hp[1] = hp
		_units._note_hits(snap)
		_frame()
		var fill: Array[Rect2i] = _dp_rects(1, OWN)
		assert_int(fill.size()).is_equal(1)
		var expected: int = HealthBarLayer.fill_end_dp(hp, max_hp, 40)
		assert_that(fill[0]).is_equal(Rect2i(1, 1, expected - 1, 4))


func test_a_bar_shows_for_three_seconds_after_the_hit_and_not_for_an_unhit_building() -> void:
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)  # Full hp, never hit, not selectable yet.
	_now_ms = 10000
	_hit([1], 1)
	for elapsed: int in [0, 1500, 3000]:
		_now_ms = 10000 + elapsed
		_frame()
		assert_int(_bars.bar_count()).override_failure_message("%d ms" % elapsed).is_equal(1)
	_now_ms = 13001
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)


func test_an_enemy_building_has_a_bar_only_where_a_cell_of_its_footprint_is_seen() -> void:
	_buildings.reveal_enemies = false
	_units.reveal_enemies = false
	_hit([0, 3], 1)
	Rig.see(_runner.snapshot, 1, [])
	_buildings._process(0.0)
	_frame()
	assert_array(_bar_rows()).is_equal([0])  # Own: always. The enemy Headquarters: unseen.
	# One corner cell of the 3x3 is seen, which is not the cell of its centre: the unit layer's
	# rule (the cell of the position) would hide it, the building's does not.
	Rig.see(_runner.snapshot, 1, [Vector2i(6, 14)])
	_buildings._process(0.0)
	_frame()
	assert_bool(_units.is_shown(3)).is_false()
	assert_array(_bar_rows()).is_equal([0, 3])
	Rig.see(_runner.snapshot, 1, [Vector2i(7, 14)])  # Just outside the footprint.
	_frame()
	assert_array(_bar_rows()).is_equal([0])


func test_without_a_building_layer_no_building_has_a_bar() -> void:
	_bars.building_layer = null
	_hit([0, 3], 1)
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)
	_units.set_selected(PackedInt32Array([_id(0)]))  # A building takes no ring either.
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)


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


func _sheet(row: int) -> IsoSheetDef:
	var snap: MatchSnapshot = _runner.snapshot
	return _buildings.world_sort.sheet(snap.type_ids[snap.type_index[row]])


func _unit_px() -> float:
	return UiScale.base_px_per_dp() / _camera.zoom.x


func _bar_rows() -> Array[int]:
	var rows: Array[int] = []
	for bar: int in _bars.bar_count():
		rows.append(_bars.bar_row(bar))
	return rows


## Bar `row`'s rects of colour `color` in world px, in the plan's order.
func _parts(row: int, color: Color) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for bar: int in _bars.bar_count():
		if _bars.bar_row(bar) == row:
			for index: int in range(_bars.bar_first_rect(bar), _bars.bar_end_rect(bar)):
				if _bars.rect_color(index) == color:
					found.append(_bars.rect_at(index))
	return found


## The box of bar `row`: the union of its edge rects.
func _box(row: int) -> Rect2:
	var edges: Array[Rect2] = _parts(row, EDGE)
	assert_int(edges.size()).is_greater(0)
	var box: Rect2 = edges[0]
	for rect: Rect2 in edges:
		box = box.merge(rect)
	return box


## Bar `row`'s rects of colour `color` in whole dp from the bar's top-left corner.
func _dp_rects(row: int, color: Color) -> Array[Rect2i]:
	var origin: Vector2 = _box(row).position
	var unit: float = _unit_px()
	var found: Array[Rect2i] = []
	for rect: Rect2 in _parts(row, color):
		var scaled: Rect2 = Rect2((rect.position - origin) / unit, rect.size / unit)
		found.append(
			Rect2i(
				roundi(scaled.position.x),
				roundi(scaled.position.y),
				roundi(scaled.size.x),
				roundi(scaled.size.y)
			)
		)
	return found
