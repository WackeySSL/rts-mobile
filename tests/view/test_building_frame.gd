extends GdUnitTestSuite
## The selection of a building in the bar layer (plan P115b, ADR 0023 section 3, assets/art/
## STYLE.md "Health bars"): a selected building shows its bar at any hp, as a hit one does, and a
## frame of four brackets round its silhouette box, an outline and an arm for each of eight arms.
## Both show only while the building layer says the building is shown. The frame is 2 dp thick with
## arms of at most 12 dp (a third of the box and no more), the same size in dp at every zoom and on
## every screen, white for an own building and the enemy bar's amber for an enemy one, over a dark
## outline. On a 32 x 32 map: player 1's Headquarters (3x3, row 0), power plant (2x2, row 1) and
## Redoubt (1x1, row 2), player 2's Headquarters (3x3, row 3) and defence (1x1, row 4); 1 dp is
## 1.75 px.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const EDGE: Color = Color("1C2127")
const WHITE: Color = Color("FFFFFF")
const ENEMY: Color = Color("F5A524")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 4, 4],
	[1, "power_plant", 10, 4],
	[1, "defence_turret", 14, 4],
	[2, "renew_hq", 4, 12],
	[2, "renew_defence", 10, 12],
]
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
const ARMS: int = 8  ## Two for each of four corners.
## The six screens of the shared list (ScreenSizes.ALL, entry by entry).
const PROFILES: Array[StringName] = [
	&"desktop",
	&"android_6in",
	&"web_tablet",
	&"desktop_portrait",
	&"android_6in_portrait",
	&"web_tablet_portrait",
]

var _now_ms: int = 0
var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _buildings: BuildingLayer
var _bars: HealthBarLayer


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


func test_a_selected_building_has_a_bar_at_any_hp_and_a_frame_and_a_let_go_one_has_neither(
) -> void:
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)  # Never hit, not selected.
	assert_int(_bars.frame_count()).is_equal(0)
	_select([0, 3])
	_frame()
	assert_array(_bar_rows()).is_equal([0, 3])
	assert_int(_bars.frame_count()).is_equal(2)
	# The frames come after the bars' rects: own plain 2 rects, enemy notched 6, then 16 each.
	assert_int(_bars.frame_first_rect()).is_equal(_bars.bar_end_rect(1))
	assert_int(_bars.rect_count()).is_equal(8 + 2 * HealthBarLayer.FRAME_RECTS)
	_select([3])
	_frame()
	assert_array(_bar_rows()).is_equal([3])
	assert_int(_bars.frame_count()).is_equal(1)
	_select([])
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)
	assert_int(_bars.frame_count()).is_equal(0)
	assert_int(_bars.rect_count()).is_equal(0)


func test_the_frame_is_four_brackets_round_the_silhouette_box() -> void:
	for row: int in 5:
		_select([row])
		_frame()
		var note: String = "row %d" % row
		var box: Rect2 = _buildings.frame_box(row)
		var unit: float = _unit_px()
		var outlines: Array[Rect2] = _frame_rects(0, ARMS)
		var arms: Array[Rect2] = _frame_rects(ARMS, 2 * ARMS)
		assert_int(outlines.size()).is_equal(ARMS)
		assert_int(arms.size()).is_equal(ARMS)
		# The arms lie inside the box and reach its four corners; the outline is each grown by 1 dp.
		_assert_rect(_union(arms), box, note)
		_assert_rect(_union(outlines), box.grow(unit), note)
		var arm: float = minf(
			HealthBarLayer.FRAME_ARM_DP * unit, 0.4 * minf(box.size.x, box.size.y)
		)
		for at: int in ARMS:
			_assert_rect(outlines[at], arms[at].grow(unit), note)
			var thin: float = minf(arms[at].size.x, arms[at].size.y)
			var long: float = maxf(arms[at].size.x, arms[at].size.y)
			assert_float(thin).override_failure_message(note).is_equal_approx(
				HealthBarLayer.FRAME_THICK_DP * unit, 0.01
			)
			assert_float(long).override_failure_message(note).is_equal_approx(arm, 0.01)
			assert_float(box.size.x).is_greater(2.0 * long)  # The arms of two corners never meet.
			assert_float(box.size.y).is_greater(2.0 * long)
		for corner: Vector2 in [
			box.position,
			Vector2(box.end.x, box.position.y),
			Vector2(box.position.x, box.end.y),
			box.end
		]:
			var touching: int = 0
			for rect: Rect2 in arms:
				touching += 1 if rect.grow(0.01).has_point(corner) else 0
			assert_int(touching).override_failure_message("%s %s" % [note, corner]).is_equal(2)


func test_an_own_frame_is_white_an_enemy_one_amber_and_both_have_the_dark_outline() -> void:
	_select([0, 3])
	_frame()
	var first: int = _bars.frame_first_rect()
	for frame: int in 2:
		var at: int = first + frame * HealthBarLayer.FRAME_RECTS
		for index: int in range(at, at + ARMS):
			assert_that(_bars.rect_color(index)).is_equal(EDGE)
		for index: int in range(at + ARMS, at + 2 * ARMS):
			assert_that(_bars.rect_color(index)).is_equal(WHITE if frame == 0 else ENEMY)
	# The frames are in the order of the selection: row 0 (own, the box of the Headquarters) first.
	_assert_rect(_union(_frame_rects(ARMS, 2 * ARMS)), _buildings.frame_box(0), "first frame")


func test_the_arms_keep_their_size_in_dp_at_every_zoom_and_on_every_screen() -> void:
	_select([0, 2, 4])
	var sizes: Array[Vector2i] = []
	for profile_name: StringName in PROFILES:
		var profile: UiMetrics = UiProfiles.by_name(profile_name)
		sizes.append(profile.window_size)
		UiScale.set_override(profile)
		_bars._read_dp()
		var dp_px: float = UiScale.base_px_per_dp()
		for zoom: float in ZOOMS:
			_camera.zoom = Vector2(zoom, zoom)
			_frame()
			assert_int(_bars.frame_count()).is_equal(3)
			for frame: int in 3:
				var at: int = _bars.frame_first_rect() + frame * HealthBarLayer.FRAME_RECTS
				var note: String = "%s zoom %s frame %d" % [profile_name, zoom, frame]
				for index: int in range(at + ARMS, at + 2 * ARMS):
					var rect: Rect2 = _bars.rect_at(index)
					var thin: float = minf(rect.size.x, rect.size.y) * zoom
					assert_float(thin).override_failure_message(note).is_equal_approx(
						2.0 * dp_px, 0.01
					)
					# An arm is at most 12 dp long on the screen.
					(
						assert_float(maxf(rect.size.x, rect.size.y) * zoom)
						. override_failure_message(note)
						. is_less_equal(12.0 * dp_px + 0.01)
					)
	assert_array(sizes).is_equal(ScreenSizes.ALL)  # 1280x720, 2400x1080, 2048x1536, both ways.


func test_a_frame_and_a_bar_show_only_where_the_building_is_shown() -> void:
	_buildings.reveal_enemies = false
	Rig.see(_runner.snapshot, 1, [])
	_buildings._process(0.0)
	_select([0, 3])  # The enemy Headquarters is in the selection, and hidden.
	_frame()
	assert_array(_bar_rows()).is_equal([0])
	assert_int(_bars.frame_count()).is_equal(1)
	assert_array(_buildings.selected_ids()).is_equal([1, 4])
	Rig.see(_runner.snapshot, 1, [Vector2i(6, 14)])  # A corner cell of its footprint.
	_frame()
	assert_array(_bar_rows()).is_equal([0, 3])
	assert_int(_bars.frame_count()).is_equal(2)
	Rig.see(_runner.snapshot, 1, [Vector2i(7, 14)])  # And it goes out of sight again.
	_frame()
	assert_array(_bar_rows()).is_equal([0])
	assert_int(_bars.frame_count()).is_equal(1)


func test_every_building_selected_gets_a_frame_in_a_plan_with_room_for_all() -> void:
	_select([0, 1, 2, 3, 4])
	_frame()
	assert_int(_bars.bar_count()).is_equal(5)
	assert_int(_bars.frame_count()).is_equal(5)
	var bars: int = _bars.bar_end_rect(4)
	assert_int(_bars.rect_count()).is_equal(bars + 5 * HealthBarLayer.FRAME_RECTS)
	_select([0])  # And a smaller plan after a larger one does not keep the old frames.
	_frame()
	assert_int(_bars.rect_count()).is_equal(2 + HealthBarLayer.FRAME_RECTS)


func test_a_selected_unit_has_a_bar_and_no_frame_and_a_layer_without_buildings_has_none() -> void:
	_units.set_selected(PackedInt32Array([1]))  # A building takes no ring.
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)
	_select([0])
	_bars.building_layer = null
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)
	assert_int(_bars.frame_count()).is_equal(0)
	assert_int(_bars.rect_count()).is_equal(0)


func test_draw_paints_the_frames_with_the_bars() -> void:
	await await_idle_frame()
	_select([3])
	_frame()
	await await_idle_frame()
	assert_int(_bars.drawn_count()).is_equal(6 + HealthBarLayer.FRAME_RECTS)
	_select([])
	_frame()
	await await_idle_frame()
	assert_int(_bars.drawn_count()).is_equal(0)


## Selects the buildings of rows `rows` in the building layer, as the controller's signal does.
func _select(rows: Array[int]) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in rows:
		ids.append(_runner.snapshot.unit_id[row])
	_buildings.set_selected(ids)


func _frame() -> void:
	_units._process(0.0)
	_buildings._process(0.0)
	_bars._process(0.0)


func _unit_px() -> float:
	return UiScale.base_px_per_dp() / _camera.zoom.x


func _bar_rows() -> Array[int]:
	var rows: Array[int] = []
	for bar: int in _bars.bar_count():
		rows.append(_bars.bar_row(bar))
	return rows


## Rects `from` to `to` (exclusive) of the first frame of the plan, in world px.
func _frame_rects(from: int, to: int) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for index: int in range(_bars.frame_first_rect() + from, _bars.frame_first_rect() + to):
		found.append(_bars.rect_at(index))
	return found


func _union(rects: Array[Rect2]) -> Rect2:
	var box: Rect2 = rects[0]
	for rect: Rect2 in rects:
		box = box.merge(rect)
	return box


func _assert_rect(actual: Rect2, expected: Rect2, note: String) -> void:
	var tolerance: Vector2 = Vector2(0.01, 0.01)
	assert_vector(actual.position).override_failure_message(note).is_equal_approx(
		expected.position, tolerance
	)
	assert_vector(actual.size).override_failure_message(note).is_equal_approx(
		expected.size, tolerance
	)
