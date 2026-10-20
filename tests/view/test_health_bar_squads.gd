extends GdUnitTestSuite
## The fill of a damaged squad bar (plan P45, STYLE.md "Health bars"): the 16 dp bar of infantry,
## own and enemy, which test_health_bars.gd only checks full and test_health_bar_frames.gd cannot
## (its scenario has no squads). The fill ends at x_end = 1 + max(1, round((W - 2) x hp / max_hp))
## dp from the bar's left edge, W the width of the class, and a fill rect that would start at
## x_end or later is not planned at all. The tank fill is in test_health_bars.gd. On
## data/scenarios/perf_arena.tres: rifle squads have max hp 100 and light tanks 300, both sides.
## The runner is not in the tree, so only the calls here move time and alpha is 0.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ARENA: String = "res://data/scenarios/perf_arena.tres"
## STYLE.md "Health bars": the edge and the two fills.
const EDGE: Color = Color("1C2127")
const OWN: Color = Color("30A46C")
const ENEMY: Color = Color("F5A524")
const SQUAD_MAX_HP: int = 100

var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _bars: HealthBarLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(ARENA)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	add_child(_units)
	_units.set_process(false)
	_make_bars()


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_damaged_own_squad_fills_by_its_14_dp_interior_on_every_profile() -> void:
	var rifle: int = _first_row_of(&"rifle_squad", 1)
	assert_int(_runner.snapshot.type_max_hp[_runner.snapshot.type_index[rifle]]).is_equal(
		SQUAD_MAX_HP
	)
	# Interior 14 dp: x_end = 1 + max(1, round(14 x hp / 100)), halves up (25 hp is 3.5 dp). A
	# bar that took the tank's 20 dp interior would show 10 dp at 50 hp, and 5 at 25.
	var expected: Dictionary[int, int] = {100: 14, 50: 7, 25: 4, 24: 3, 10: 1, 1: 1}
	for profile_name: StringName in UiProfiles.all():
		UiScale.set_override(UiProfiles.by_name(profile_name))
		_make_bars()  # Reads the dp that is in force now.
		_select([rifle])
		for hp: int in expected:
			_runner.snapshot.hp[rifle] = hp
			_frame()
			var note: String = "%s hp %d" % [profile_name, hp]
			assert_array(_dp_rects(rifle, EDGE)).override_failure_message("edge, " + note).is_equal(
				[Rect2i(0, 0, 16, 6)]
			)
			assert_array(_dp_rects(rifle, OWN)).override_failure_message("fill, " + note).is_equal(
				[Rect2i(1, 1, expected[hp], 4)]
			)


func test_a_damaged_enemy_squad_clips_its_three_fill_rects_at_x_end() -> void:
	var rifle: int = _first_row_of(&"rifle_squad", 2)
	_select([rifle])
	# Enemy, W 16: the notch is dp 6..10, so the fill is a left arm (1, 1, 4, 2), a right arm
	# (11, 1, 4, 2) and a strip (1, 3, 14, 2), each clipped at x_end.
	var arms: Array[Rect2i] = [Rect2i(1, 1, 4, 2), Rect2i(11, 1, 4, 2), Rect2i(1, 3, 14, 2)]
	_runner.snapshot.hp[rifle] = SQUAD_MAX_HP
	_frame()
	assert_array(_dp_rects(rifle, ENEMY)).is_equal(arms)
	_runner.snapshot.hp[rifle] = 50  # x_end 8: the right arm (x 11..15) is clipped away.
	_frame()
	assert_array(_dp_rects(rifle, ENEMY)).is_equal([Rect2i(1, 1, 4, 2), Rect2i(1, 3, 7, 2)])
	_runner.snapshot.hp[rifle] = 25  # x_end 5: the left arm (x 1..5) is whole, the strip is 4.
	_frame()
	assert_array(_dp_rects(rifle, ENEMY)).is_equal([Rect2i(1, 1, 4, 2), Rect2i(1, 3, 4, 2)])
	_runner.snapshot.hp[rifle] = 10  # x_end 2: 1 dp on each rect that starts at x 1.
	_frame()
	assert_array(_dp_rects(rifle, ENEMY)).is_equal([Rect2i(1, 1, 1, 2), Rect2i(1, 3, 1, 2)])
	assert_array(_dp_rects(rifle, EDGE)).is_equal(
		[Rect2i(0, 0, 6, 6), Rect2i(10, 0, 6, 6), Rect2i(6, 2, 4, 4)]
	)


func test_a_fill_rect_that_starts_exactly_at_x_end_is_not_planned() -> void:
	var rifle: int = _first_row_of(&"rifle_squad", 2)
	var tank: int = _first_row_of(&"light_tank", 2)
	_select([rifle, tank])
	# Squad: 71 hp is round(14 x 0.71) = 10 dp, so x_end 11, where the right arm starts.
	_runner.snapshot.hp[rifle] = 71
	# Tank (W 22, interior 20, right arm from dp 14): 195 of 300 hp is 13 dp, so x_end 14.
	var max_tank: int = _runner.snapshot.type_max_hp[_runner.snapshot.type_index[tank]]
	assert_int(max_tank).is_equal(300)
	_runner.snapshot.hp[tank] = 195
	_frame()
	assert_array(_dp_rects(rifle, ENEMY)).is_equal([Rect2i(1, 1, 4, 2), Rect2i(1, 3, 10, 2)])
	assert_array(_dp_rects(tank, ENEMY)).is_equal([Rect2i(1, 1, 7, 2), Rect2i(1, 3, 13, 2)])
	# Edge: three rects each, fill: two each. A zero-width rect would make it 3 + 3 + 3 + 3.
	assert_int(_bars.rect_count()).is_equal(3 + 2 + 3 + 2)


## Selects `rows` and plans one frame.
func _select(rows: Array[int]) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in rows:
		ids.append(_runner.snapshot.unit_id[row])
	_units.set_selected(ids)
	_frame()


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


## Bar `row`'s rects of colour `color` in world px, in the plan's order.
func _parts(row: int, color: Color) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for bar: int in _bars.bar_count():
		if _bars.bar_row(bar) == row:
			for index: int in range(_bars.bar_first_rect(bar), _bars.bar_end_rect(bar)):
				if _bars.rect_color(index) == color:
					found.append(_bars.rect_at(index))
	return found


## Bar `row`'s rects of colour `color` in whole dp from the bar's top-left corner (the union of
## its edge rects), in the plan's order.
func _dp_rects(row: int, color: Color) -> Array[Rect2i]:
	var edges: Array[Rect2] = _parts(row, EDGE)
	assert_int(edges.size()).is_greater(0)
	var box: Rect2 = edges[0]
	for rect: Rect2 in edges:
		box = box.merge(rect)
	var unit: float = UiScale.base_px_per_dp() / _camera.zoom.x
	var found: Array[Rect2i] = []
	for rect: Rect2 in _parts(row, color):
		var scaled: Rect2 = Rect2((rect.position - box.position) / unit, rect.size / unit)
		for value: float in [scaled.position.x, scaled.position.y, scaled.size.x, scaled.size.y]:
			assert_float(value).is_equal_approx(roundf(value), 0.01)  # Whole dp.
		found.append(
			Rect2i(
				roundi(scaled.position.x),
				roundi(scaled.position.y),
				roundi(scaled.size.x),
				roundi(scaled.size.y)
			)
		)
	return found
