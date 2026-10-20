extends GdUnitTestSuite
## A frame of the health bars from end to end (plan P45): that `_draw` paints the plan and stops
## painting it when the last bar goes, that a layer whose first plan sees no units plans nothing
## and raises no script error, that the bar layer brings the unit layer's rows up to date itself
## and so does not depend on running after it, and two defaults of the view. The shapes and places
## of bars are in test_health_bars.gd and when a bar shows is in test_health_bar_hits.gd (gdlint
## allows 20 public methods per file, and both are full). On data/scenarios/controls_test.tres:
## ids 1-30 are blue light tanks, 31-40 red ones; the runner is not in the tree, so only the calls
## here move time.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const OWN_TANK_RECTS: int = 2  ## STYLE.md: the box and its fill.
const ENEMY_TANK_RECTS: int = 6  ## Three edge rects and three fill rects.

var _now_ms: int = 0
var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _bars: HealthBarLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_now_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	_units = _new_units()
	_bars = _new_bars(_units)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_draw_paints_every_planned_rect_and_paints_none_once_the_last_bar_is_gone() -> void:
	await await_idle_frame()  # The first draw of the new layers is behind us.
	assert_int(_bars.drawn_count()).is_equal(0)
	_units.set_selected(PackedInt32Array([2, 31]))  # An own tank and an enemy tank.
	_frame()
	assert_int(_bars.rect_count()).is_equal(OWN_TANK_RECTS + ENEMY_TANK_RECTS)
	await await_idle_frame()
	assert_int(_bars.drawn_count()).is_equal(OWN_TANK_RECTS + ENEMY_TANK_RECTS)
	_units.set_selected(PackedInt32Array([31]))  # One bar goes: the old plan must not stay.
	_frame()
	await await_idle_frame()
	assert_int(_bars.drawn_count()).is_equal(ENEMY_TANK_RECTS)
	_units.set_selected(PackedInt32Array())  # The last bar goes: a frame with no rect redraws too.
	_frame()
	assert_int(_bars.rect_count()).is_equal(0)
	await await_idle_frame()
	assert_int(_bars.drawn_count()).is_equal(0)
	_units.set_selected(PackedInt32Array([2]))  # And a bar can come back.
	_frame()
	await await_idle_frame()
	assert_int(_bars.drawn_count()).is_equal(OWN_TANK_RECTS)


func test_a_first_plan_that_sees_no_units_plans_nothing_and_a_later_match_is_planned() -> void:
	for row: int in _runner.snapshot.unit_count():
		_runner.world.hp[row] = 0
	_runner.run_ticks(1)
	assert_int(_runner.snapshot.unit_count()).is_equal(0)
	var units: UnitLayer = _new_units()  # Layers whose first frame is this empty one.
	var bars: HealthBarLayer = _new_bars(units)
	units._process(0.0)
	bars._process(0.0)
	assert_int(bars.bar_count()).is_equal(0)
	assert_int(bars.rect_count()).is_equal(0)
	units._process(0.0)  # And again: nothing is left over.
	bars._process(0.0)
	assert_int(bars.rect_count()).is_equal(0)
	_runner.start()  # Their arrays grow from that state when units come.
	units.set_selected(PackedInt32Array([2, 31]))
	bars._process(0.0)
	assert_int(bars.bar_count()).is_equal(2)
	assert_int(bars.rect_count()).is_equal(OWN_TANK_RECTS + ENEMY_TANK_RECTS)


func test_the_bar_layer_brings_the_unit_layer_up_to_date_and_so_may_run_before_it() -> void:
	_units.set_selected(PackedInt32Array([3]))
	_frame()
	_now_ms = 1000
	_runner.world.hp[4] -= 50  # Unit 5 is hit and unit 2 dies in the same tick: unit 3 is row 1
	_runner.world.hp[1] = 0  # and unit 5 row 3 now, while the unit layer still has 40 rows.
	_runner.run_ticks(1)
	_bars._process(0.0)  # The bar layer first: the unit layer has not had its frame.
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_id[1]).is_equal(3)
	assert_int(snap.unit_id[3]).is_equal(5)
	assert_array(_bar_rows()).is_equal([1, 3])  # Selected unit 3, and the recently hit unit 5.
	assert_int(_units.hit_time_ms(3)).is_equal(1000)
	_units._process(0.0)  # The unit layer's own frame changes nothing for the bars.
	_bars._process(0.0)
	assert_array(_bar_rows()).is_equal([1, 3])
	assert_int(_units.hit_time_ms(3)).is_equal(1000)


func test_without_a_scenario_the_local_player_is_player_1() -> void:
	_units.set_selected(PackedInt32Array([2, 31]))  # Blue tank 2 (owner 1), red tank 31 (owner 2).
	_runner.scenario = null  # World.from_scenario takes none, so a runner can have none.
	_frame()
	assert_int(_bars.bar_count()).is_equal(2)
	assert_int(_bars.bar_end_rect(0) - _bars.bar_first_rect(0)).is_equal(OWN_TANK_RECTS)
	assert_int(_bars.bar_end_rect(1) - _bars.bar_first_rect(1)).is_equal(ENEMY_TANK_RECTS)


func test_one_clock_read_stamps_every_hit_the_frame_sees() -> void:
	var reads: Array[int] = [0]
	_units.clock = func() -> int:
		reads[0] += 1
		return 700
	_units._process(0.0)
	assert_int(reads[0]).is_equal(0)  # No hp fell: no read.
	_runner.world.hp[4] -= 10
	_runner.world.hp[5] -= 10
	_runner.run_ticks(1)
	_runner.world.hp[6] -= 10
	_runner.world.hp[4] -= 10
	_runner.run_ticks(1)
	_units._process(0.0)
	assert_int(reads[0]).is_equal(1)  # Four drops on three rows over two ticks: one read.
	for row: int in [4, 5, 6]:
		assert_int(_units.hit_time_ms(row)).is_equal(700)
	_units._process(0.0)  # The same tick again is not scanned again.
	assert_int(reads[0]).is_equal(1)


## A unit layer on the runner and the camera, not processed by the tree.
func _new_units() -> UnitLayer:
	var units: UnitLayer = auto_free(UnitLayer.new())
	units.runner = _runner
	units.camera = _camera
	units.clock = func() -> int: return _now_ms
	add_child(units)
	units.set_process(false)
	return units


## A bar layer over `units`, not processed by the tree.
func _new_bars(units: UnitLayer) -> HealthBarLayer:
	var bars: HealthBarLayer = auto_free(HealthBarLayer.new())
	bars.runner = _runner
	bars.unit_layer = units
	add_child(bars)
	bars.set_process(false)
	return bars


## One frame: the unit layer, then the bar layer, in the scene's order.
func _frame() -> void:
	_units._process(0.0)
	_bars._process(0.0)


## The unit rows that have a bar, in the order the layer planned them.
func _bar_rows() -> Array[int]:
	var rows: Array[int] = []
	for bar: int in _bars.bar_count():
		rows.append(_bars.bar_row(bar))
	return rows
