extends GdUnitTestSuite
## Bars of neighbours in a formation under the 2:1 projection (P117b). STYLE.md's two overlap
## inequalities (P34b's sweep) were measured on the top-down view, where a neighbour east of a unit
## is a spacing to the right and one north a spacing above. In iso a grid step along x is (32, 16)
## px x the spacing and one along y (-32, 16), so a formation's neighbours are 2:1 diagonals: the
## one on the grid's (1, 1) diagonal stands straight below, the one on (1, -1) straight beside.
## A bar stands a lift above its unit's ground point and the lift is per type (P114b: the
## `bar_lift_px` of the type's sheet, the top of its frame; the numbers are generated data, so they
## are read and not typed here). Two bars overlap when their units' screen offsets are under the
## bars' width and under the bar's height once the lower unit's bar has risen by the difference of
## the lifts: below a light tank, a taller frame has its bar nearer to the light tank's than a
## second light tank would, by the difference of the two lifts at the zoom.
## The sweep puts two own units at each of the four distinct neighbour steps, at the larger
## formation_spacing of their two types (read from data/units: a group spaces by its largest type
## spacing, Formation.gd; 900 milli for two squads, 1200 for two light tanks, 1300 for a heavy tank
## with anything lighter), selects both and reads the plan of the layer, at the three zooms on
## every profile of both orientations (1.0 to 2.37 base px per dp). Its pairs are the units of one
## vehicle type, the squad pair, and every ordered pair of two different types out of the four
## vehicle types of the sweep and the rifle squad: each type stands once in front of and once
## behind every other, so all eight neighbour directions are covered. Units that stand closer than
## their formation spacing (two orders, a unit pushed aside) are outside the rule, as in P34b.
## The result, which the three tests pin: two vehicles of one type never overlap; two squads
## overlap only at zoom 0.75 on a screen above 1.8 base px per dp (web_phone, web_phone_small and
## web_phone_portrait) and then by at most 1.5 dp (a quarter of a bar's height) at the bar's edge,
## by 1.44 dp; two units of different types overlap by no more than their lifts differ (P114b: the
## lift difference at the zoom, in dp, which is where the taller frame's bar has risen to: on the
## sheets of P99b the worst pair is a light tank with another type, 5.6 dp at zoom 0.75 and 3.8 dp
## at zoom 1 on the 6-inch phone). Whether a bar covers the unit above it has no iso rule: the bar
## stands over its own unit's frame and the unit above is only half a spacing higher, so a bar may
## cover that unit's feet.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ARENA: String = "res://data/scenarios/perf_arena.tres"
const UNITS_DIR: String = "res://data/units/"
const EDGE: Color = Color("1C2127")
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
const SQUAD: StringName = &"rifle_squad"
## The four vehicle types of the sweep; a bar stands the sheet's `bar_lift_px` above its unit.
const VEHICLES: Array[StringName] = [&"light_tank", &"heavy_tank", &"artillery", &"harvester"]
## The neighbours of a unit that differ: along grid x, along grid y, down the grid's diagonal (which
## is straight down the screen) and across it (straight sideways).
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
## Bars overlap only above this many base px per dp: two squads standing on a grid axis are 14.4
## world px apart vertically, which is 10.8 px at zoom 0.75, and a bar is 6 dp high. A pair of two
## types needs more (a light and a heavy tank 1.85, a light tank and an artillery piece 1.9).
const OVERLAP_ABOVE_DP_PX: float = 1.8
const MAX_OVERLAP_DP: float = 1.5

var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _bars: HealthBarLayer
## Two own units of the arena, in two different type table entries. The sweep gives them the types
## of the pair under test (the arena holds a light tank and two squad types).
var _row_a: int = -1
var _row_b: int = -1


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_build()


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_bars_of_two_vehicles_of_one_type_never_overlap_on_any_screen() -> void:
	var pairs: Array[Array] = []
	for type_id: StringName in VEHICLES:
		pairs.append([type_id, type_id])
	assert_int(pairs.size()).is_greater_equal(4)  # Light, heavy, artillery, harvester.
	_sweep(pairs, false)


func test_squad_bars_overlap_only_at_zoom_075_above_1_8_px_per_dp_and_by_at_most_1_5_dp() -> void:
	var pairs: Array[Array] = [[SQUAD, SQUAD]]
	# The residual is real, so a layer that stopped overlapping them would be noticed here too.
	assert_float(_sweep(pairs, true)).is_greater(1.0)


func test_mixed_type_bars_overlap_by_no_more_than_their_lifts_differ() -> void:
	var types: Array[StringName] = [SQUAD]
	for type_id: StringName in VEHICLES:
		types.append(type_id)
	var pairs: Array[Array] = []
	for first: StringName in types:
		for second: StringName in types:
			if first != second:
				pairs.append([first, second])
	assert_int(pairs.size()).is_equal(types.size() * (types.size() - 1))
	# The residual is real (the sheets' frames are not one height), so a layer that stopped
	# lifting by the sheets would be noticed here too.
	assert_float(_sweep_bounded(pairs)).is_greater(0.0)


func test_the_sweep_pairs_the_types_it_names_at_the_larger_of_their_spacings() -> void:
	assert_int(_spacing(&"rifle_squad", &"rifle_squad")).is_equal(900)
	assert_int(_spacing(&"light_tank", &"heavy_tank")).is_equal(1300)
	assert_int(_spacing(SQUAD, &"heavy_tank")).is_equal(1300)
	assert_int(_spacing(&"heavy_tank", &"harvester")).is_equal(1400)
	var rows: Array[int] = _place_pair(&"heavy_tank", SQUAD, Vector2i(1300, 0))
	_frame()
	var snap: MatchSnapshot = _runner.snapshot
	var armours: Array[int] = [World.Armour.HEAVY, World.Armour.INFANTRY]
	var widths_dp: Array[int] = [HealthBarLayer.VEHICLE_WIDTH_DP, HealthBarLayer.INFANTRY_WIDTH_DP]
	for index: int in 2:
		assert_int(rows[index]).is_not_equal(rows[1 - index])
		assert_int(snap.owner[rows[index]]).is_equal(1)
		assert_int(snap.type_armour[snap.type_index[rows[index]]]).is_equal(armours[index])
		# The bar is a dp size: its width on the screen is its dp width in base px.
		var box: Rect2 = _screen_box(rows[index])
		assert_float(box.size.x).is_equal_approx(widths_dp[index] * UiScale.base_px_per_dp(), 0.01)
	assert_str(String(snap.type_ids[snap.type_index[rows[0]]])).is_equal("heavy_tank")
	assert_str(String(snap.type_ids[snap.type_index[rows[1]]])).is_equal("rifle_squad")
	assert_int(snap.pos_x[rows[1]] - snap.pos_x[rows[0]]).is_equal(1300)


## Runs the sweep for each pair of types in `pairs` (the pair is [first, second], the second
## standing a step from the first): every profile, zoom and step. With `may_overlap` the bars may
## overlap at zoom 0.75 on a screen above `OVERLAP_ABOVE_DP_PX`, by at most `MAX_OVERLAP_DP`, and
## nowhere else; without it they never overlap. Returns the worst overlap in dp that it met.
func _sweep(pairs: Array[Array], may_overlap: bool) -> float:
	var worst: float = 0.0
	for profile_name: StringName in _both_orientations():
		UiScale.set_override(UiProfiles.by_name(profile_name))
		_make_bars()
		var dp_px: float = UiScale.base_px_per_dp()
		assert_bool(dp_px >= 1.0 and dp_px <= 2.4).is_true()  # STYLE.md: 1.0 to 2.37 px per dp.
		for zoom: float in ZOOMS:
			_camera.zoom = Vector2(zoom, zoom)
			for pair: Array in pairs:
				var first: StringName = pair[0]
				var second: StringName = pair[1]
				for step: Vector2i in STEPS:
					var note: String = (
						"overlap in dp, %s zoom %s %s then %s step %s"
						% [profile_name, zoom, first, second, step]
					)
					var depth: float = _overlap_dp(first, second, step)
					if may_overlap and zoom == 0.75 and dp_px > OVERLAP_ABOVE_DP_PX:
						assert_float(depth).override_failure_message(note).is_less_equal(
							MAX_OVERLAP_DP
						)
						worst = maxf(worst, depth)
					else:
						assert_float(depth).override_failure_message(note).is_equal(0.0)
	return worst


## Runs the sweep for each pair of types in `pairs` with the bound of two bars whose lifts differ:
## the bars of equal lift never overlap, so the depth of an overlap is at most how far the taller
## frame's bar has risen towards the other's, the difference of the two sheets' lifts at the zoom
## in dp. Returns the worst depth in dp that it met.
func _sweep_bounded(pairs: Array[Array]) -> float:
	var worst: float = 0.0
	for profile_name: StringName in _both_orientations():
		UiScale.set_override(UiProfiles.by_name(profile_name))
		_make_bars()
		var dp_px: float = UiScale.base_px_per_dp()
		for zoom: float in ZOOMS:
			_camera.zoom = Vector2(zoom, zoom)
			for pair: Array in pairs:
				var first: StringName = pair[0]
				var second: StringName = pair[1]
				var rise: float = absf(_lift(first) - _lift(second)) * zoom / dp_px
				for step: Vector2i in STEPS:
					var note: String = (
						"overlap in dp, %s zoom %s %s then %s step %s"
						% [profile_name, zoom, first, second, step]
					)
					var depth: float = _overlap_dp(first, second, step)
					assert_float(depth).override_failure_message(note).is_less_equal(rise + 0.01)
					worst = maxf(worst, depth)
	return worst


## The depth in dp by which the bars of two own units, a `first_type` and a `second_type` one
## `step` formation spacings from it, overlap on the screen under the profile and zoom that are in
## force: the smaller side of the overlapping rect, 0 when the bars are clear of each other
## (touching is clear).
func _overlap_dp(first_type: StringName, second_type: StringName, step: Vector2i) -> float:
	var rows: Array[int] = _place_pair(
		first_type, second_type, step * _spacing(first_type, second_type)
	)
	_frame()
	var first: Rect2 = _screen_box(rows[0])
	var second: Rect2 = _screen_box(rows[1])
	if not first.intersects(second):
		return 0.0
	var overlap: Rect2 = first.intersection(second)
	return minf(overlap.size.x, overlap.size.y) / UiScale.base_px_per_dp()


## The formation spacing of a group of the two types: the larger of theirs (Formation.gd), in milli.
func _spacing(first_type: StringName, second_type: StringName) -> int:
	return maxi(_def(first_type).formation_spacing, _def(second_type).formation_spacing)


func _def(type_id: StringName) -> UnitDef:
	return load(UNITS_DIR + "%s.tres" % type_id)


## Puts two own units in the published snapshot, a `first_type` on the tile (20, 20) and a
## `second_type` `offset` milli from it, selects both, points the camera at them and returns their
## rows. Test-only writes into the snapshot (allowed in SYNC, ADR 0012 section 3).
func _place_pair(first_type: StringName, second_type: StringName, offset: Vector2i) -> Array[int]:
	var rows: Array[int] = [_row_a, _row_b]
	var types: Array[StringName] = [first_type, second_type]
	var snap: MatchSnapshot = _runner.snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for index: int in 2:
		_retype(rows[index], types[index])
		var at: Vector2i = Vector2i(20000, 20000) + offset * index
		snap.pos_x[rows[index]] = at.x
		snap.pos_y[rows[index]] = at.y
		snap.prev_pos_x[rows[index]] = at.x
		snap.prev_pos_y[rows[index]] = at.y
		ids.append(snap.unit_id[rows[index]])
	_units.set_selected(ids)
	_camera.position = IsoProjection.ground_to_px(20000, 20000)
	return rows


## Gives `row` the type `type_id` in the snapshot's tables, the id and the armour from data/units
## (the id picks the bar's lift, the armour its class). The row's type table entry is its own, so
## the other row keeps its type.
func _retype(row: int, type_id: StringName) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[row]
	snap.type_ids[type] = type_id
	snap.type_armour[type] = _def(type_id).armour


## The names of every profile of both orientations: UiProfiles.all() and its portrait twins.
func _both_orientations() -> Array[StringName]:
	var profiles: Dictionary[StringName, UiMetrics] = UiProfiles.all()
	profiles.merge(UiProfiles.portrait())
	return profiles.keys()


func _build() -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = _arena_with_the_vehicles()
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
	_row_a = _first_row_of(&"light_tank", 1)
	_row_b = _first_row_of(SQUAD, 1)
	assert_bool(_row_a >= 0 and _row_b >= 0).is_true()
	assert_int(_runner.snapshot.type_index[_row_a]).is_not_equal(
		_runner.snapshot.type_index[_row_b]
	)


## The arena with a roster that lists the four vehicle types, so that the match's atlas holds their
## sheets and a retyped row is lifted by its type's sheet (a type without one has its class's
## default). The scenario is a copy: the file's resource is shared with other suites.
func _arena_with_the_vehicles() -> ScenarioDef:
	var scenario: ScenarioDef = (load(ARENA) as ScenarioDef).duplicate()
	var roster: Array[UnitDef] = scenario.roster.duplicate()
	for type_id: StringName in VEHICLES:
		roster.append(_def(type_id))
	scenario.roster = roster
	return scenario


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


## The lift of the top of a unit's frame, world px at zoom 1: the `bar_lift_px` of its type's sheet.
func _lift(type_id: StringName) -> float:
	return float((load(IsoIndex.PATH) as IsoIndex).sheet(type_id).bar_lift_px)
