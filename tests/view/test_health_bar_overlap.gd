extends GdUnitTestSuite
## Bars of neighbours in a formation under the 2:1 projection (P117b). STYLE.md's two overlap
## inequalities (P34b's sweep) were measured on the top-down view, where a neighbour east of a unit
## is a spacing to the right and one north a spacing above. In iso a grid step along x is
## (32, 16) px x the spacing and one along y (-32, 16), so a formation's neighbours are 2:1
## diagonals: the one on the grid's (1, 1) diagonal stands straight below, the one on (1, -1)
## straight beside. Every bar of a class has the same lift, so two bars overlap exactly when their
## units' screen offsets are under the bar's width and under its height. The sweep puts two own
## units of a class at each of the four distinct neighbour steps at the class's formation spacing
## (900 milli for squads, 1200 for tanks and mixed groups), selects both and reads the plan of the
## layer, at the three zooms on every profile of both orientations (1.0 to 2.37 base px per dp).
## The result, which the two tests pin: tank bars never overlap; squad bars never overlap either,
## except those of grid-axis neighbours at zoom 0.75 on a screen above 1.8 px per dp (the two web
## phones), where they overlap by at most 1.5 dp (a quarter of a bar's height) at the bar's edge.
## Whether a bar covers the unit above it has no iso rule: the bar stands over its own unit's frame
## and the unit above is only half a spacing higher, so a bar may cover that unit's feet.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ARENA: String = "res://data/scenarios/perf_arena.tres"
const EDGE: Color = Color("1C2127")
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
const SPACING_MILLI: Dictionary[StringName, int] = {&"vehicle": 1200, &"infantry": 900}
const TYPE_OF: Dictionary[StringName, StringName] = {
	&"vehicle": &"light_tank", &"infantry": &"rifle_squad"
}
## The neighbours of a unit that differ: along grid x, along grid y, down the grid's diagonal (which
## is straight down the screen) and across it (straight sideways).
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
## Squads at zoom 0.75 overlap above this many base px per dp: 14.4 px x 0.75 is the vertical offset
## of a grid-axis neighbour, and a bar is 6 dp high.
const SQUAD_CLEAR_DP_PX: float = 1.8
const MAX_OVERLAP_DP: float = 1.5

var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _bars: HealthBarLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_build()


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_tank_bars_of_formation_neighbours_never_overlap_on_any_screen() -> void:
	for profile_name: StringName in _both_orientations():
		UiScale.set_override(UiProfiles.by_name(profile_name))
		_make_bars()
		for zoom: float in ZOOMS:
			_camera.zoom = Vector2(zoom, zoom)
			for step: Vector2i in STEPS:
				var note: String = "%s zoom %s step %s" % [profile_name, zoom, step]
				(
					assert_float(_overlap_dp(&"vehicle", step))
					. override_failure_message("overlap in dp, " + note)
					. is_equal(0.0)
				)


func test_squad_bars_overlap_only_at_zoom_075_above_1_8_px_per_dp_and_by_at_most_1_5_dp() -> void:
	var worst: float = 0.0
	for profile_name: StringName in _both_orientations():
		UiScale.set_override(UiProfiles.by_name(profile_name))
		_make_bars()
		var dp_px: float = UiScale.base_px_per_dp()
		assert_bool(dp_px >= 1.0 and dp_px <= 2.4).is_true()  # STYLE.md: 1.0 to 2.37 px per dp.
		for zoom: float in ZOOMS:
			_camera.zoom = Vector2(zoom, zoom)
			for step: Vector2i in STEPS:
				var note: String = "%s zoom %s step %s" % [profile_name, zoom, step]
				var depth: float = _overlap_dp(&"infantry", step)
				if zoom == 0.75 and dp_px > SQUAD_CLEAR_DP_PX:
					(
						assert_float(depth)
						. override_failure_message("overlap in dp, " + note)
						. is_less_equal(MAX_OVERLAP_DP)
					)
					worst = maxf(worst, depth)
				else:
					assert_float(depth).override_failure_message("overlap in dp, " + note).is_equal(
						0.0
					)
	# The residual is real, so a layer that stopped overlapping them would be noticed here too.
	assert_float(worst).is_greater(1.0)


## The depth in dp by which the bars of two own units of `class_key`, standing `step` formation
## spacings apart, overlap on the screen under the profile and zoom that are in force: the smaller
## side of the overlapping rect, 0 when the bars are clear of each other (touching is clear).
func _overlap_dp(class_key: StringName, step: Vector2i) -> float:
	var rows: Array[int] = _place_pair(class_key, step * SPACING_MILLI[class_key])
	_frame()
	var first: Rect2 = _screen_box(rows[0])
	var second: Rect2 = _screen_box(rows[1])
	if not first.intersects(second):
		return 0.0
	var overlap: Rect2 = first.intersection(second)
	return minf(overlap.size.x, overlap.size.y) / UiScale.base_px_per_dp()


## Puts two own units of `class_key` in the published snapshot, the first on the tile (20, 20) and
## the second `offset` milli from it, selects both, points the camera at them and returns their
## rows. Test-only writes into the snapshot (allowed in SYNC, ADR 0012 section 3).
func _place_pair(class_key: StringName, offset: Vector2i) -> Array[int]:
	var first: int = _first_row_of(TYPE_OF[class_key], 1)
	var rows: Array[int] = [first, first + 1]
	var snap: MatchSnapshot = _runner.snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for index: int in 2:
		var at: Vector2i = Vector2i(20000, 20000) + offset * index
		snap.pos_x[rows[index]] = at.x
		snap.pos_y[rows[index]] = at.y
		snap.prev_pos_x[rows[index]] = at.x
		snap.prev_pos_y[rows[index]] = at.y
		ids.append(snap.unit_id[rows[index]])
	_units.set_selected(ids)
	_camera.position = IsoProjection.ground_to_px(20000, 20000)
	return rows


## The names of every profile of both orientations: UiProfiles.all() and its portrait twins.
func _both_orientations() -> Array[StringName]:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	return profiles.keys()


func _build() -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(ARENA)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.reveal_enemies = true
	add_child(_units)
	_units.set_process(false)
	_bars = null
	_make_bars()


## A fresh bar layer, which reads the dp that is in force now.
func _make_bars() -> void:
	if _bars != null:
		_bars.free()
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = _units
	add_child(_bars)
	_bars.set_process(false)


## One frame: the unit layer, then the bar layer, in the scene's order.
func _frame() -> void:
	_units._process(0.0)
	_bars._process(0.0)


## The first row of type `type_id` owned by `owner_id`.
func _first_row_of(type_id: StringName, owner_id: int) -> int:
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		if snap.type_ids[snap.type_index[row]] == type_id and snap.owner[row] == owner_id:
			return row
	return -1


## The box of bar `row` (the union of its edge rects) on the screen, in base px.
func _screen_box(row: int) -> Rect2:
	var box: Rect2 = Rect2()
	var found: bool = false
	for bar: int in _bars.bar_count():
		if _bars.bar_row(bar) != row:
			continue
		for index: int in range(_bars.bar_first_rect(bar), _bars.bar_end_rect(bar)):
			if _bars.rect_color(index) == EDGE:
				box = _bars.rect_at(index) if not found else box.merge(_bars.rect_at(index))
				found = true
	assert_bool(found).override_failure_message("no bar for row %d" % row).is_true()
	var top_left: Vector2 = _camera.world_to_screen(box.position)
	return Rect2(top_left, _camera.world_to_screen(box.end) - top_left)
