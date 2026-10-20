extends GdUnitTestSuite
## When a health bar shows (plan P45, assets/art/STYLE.md "Health bars", Density): over a unit that
## is selected and over one that lost hp within the last 3000 ms on the frame clock, and nowhere
## else. A hit is an hp drop between two snapshots, as UnitLayer sees them, and not a SHOT event:
## the drop is what a unit lost, whichever weapon did it and whenever a shell lands (P42b), and it
## covers every tick since the last frame, which the events of one tick do not. UnitLayer keeps the
## hit time per row and re-aligns it by unit id when rows compact on a death (ADR 0007 section 3).
## The shape and place of a bar are in test_health_bars.gd (gdlint allows 20 public methods per
## file). On data/scenarios/controls_test.tres: ids 1-30 are blue light tanks, 31-40 red ones; the
## runner is not in the tree, so only the calls here move time.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const WINDOW_MS: int = 3000  ## STYLE.md: "hit within the last 3000 ms".
const SENTINEL_SIZE: Vector2i = Vector2i(640, 360)  ## A window size no profile has.

var _window_size_before: Vector2i
var _now_ms: int = 0
var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _bars: HealthBarLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_now_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.clock = func() -> int: return _now_ms
	add_child(_units)
	_units.set_process(false)
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = _units
	add_child(_bars)
	_bars.set_process(false)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_bars_exist_only_for_selected_units_and_units_hit_within_the_window() -> void:
	_frame()
	assert_int(_bars.bar_count()).is_equal(0)
	assert_int(_bars.rect_count()).is_equal(0)
	_units.set_selected(PackedInt32Array([2, 31]))  # An own tank and an enemy tank, at full hp.
	_frame()
	assert_array(_bar_rows()).is_equal([1, 30])
	_hit(4, 40)  # Tank 5.
	_frame()
	assert_array(_bar_rows()).is_equal([1, 4, 30])  # In row order.
	_units.set_selected(PackedInt32Array())  # Nobody selected: the hit unit keeps its bar.
	_frame()
	assert_array(_bar_rows()).is_equal([4])
	_now_ms += WINDOW_MS + 1
	_frame()
	assert_array(_bar_rows()).is_empty()
	assert_int(_bars.rect_count()).is_equal(0)


func test_the_window_is_3000_ms_on_the_frame_clock_and_a_new_hit_restarts_it() -> void:
	_now_ms = 10000
	_hit(4, 40)
	_frame()
	assert_int(_units.hit_time_ms(4)).is_equal(10000)
	for age: int in [0, 1, 1500, 2999, WINDOW_MS]:  # Up to and including 3000 ms.
		_now_ms = 10000 + age
		_frame()
		assert_array(_bar_rows()).override_failure_message("age %d" % age).is_equal([4])
	_now_ms = 10000 + WINDOW_MS + 1
	_frame()
	assert_array(_bar_rows()).is_empty()
	_now_ms = 12000  # A later hit stamps again; the first one no longer matters.
	_hit(4, 10)
	_frame()
	assert_int(_units.hit_time_ms(4)).is_equal(12000)
	_now_ms = 15000
	_frame()
	assert_array(_bar_rows()).is_equal([4])
	_now_ms = 15001
	_frame()
	assert_array(_bar_rows()).is_empty()


func test_a_hit_at_clock_zero_counts() -> void:
	_now_ms = 0  # The first frame of the engine: 0 is a time, not "never".
	_hit(0, 5)
	_frame()
	assert_int(_units.hit_time_ms(0)).is_equal(0)
	assert_array(_bar_rows()).is_equal([0])
	assert_int(_units.hit_time_ms(1)).is_equal(UnitLayer.NEVER_HIT)


func test_a_bar_follows_set_selected_and_a_death_in_the_selection() -> void:
	_units.set_selected(PackedInt32Array([2, 30]))
	_frame()
	assert_array(_bar_rows()).is_equal([1, 29])
	_runner.world.hp[1] = 0  # Tank 2 dies; tank 30 moves up to row 28.
	_runner.run_ticks(1)
	_frame()
	assert_int(_runner.snapshot.unit_count()).is_equal(39)
	assert_array(_bar_rows()).is_equal([28])
	assert_int(_runner.snapshot.unit_id[28]).is_equal(30)
	assert_bool(_units.is_ringed(28)).is_true()
	assert_bool(_units.is_ringed(1)).is_false()  # Row 1 is tank 3 now.
	_units.set_selected(PackedInt32Array([2, 3]))  # The dead id is skipped like any unknown one.
	_frame()
	assert_array(_bar_rows()).is_equal([1])


func test_a_hit_is_an_hp_drop_and_not_a_shot_event_or_a_heal_or_a_spawn() -> void:
	# A SHOT record naming tank 7 as the target (a miss, or a shell in flight): no hp change.
	var shot: PackedInt32Array = PackedInt32Array([World.Event.SHOT, 31, 0, 0, 7, 0, 0, 0])
	assert_int(shot.size()).is_equal(World.EVENT_STRIDE)
	_runner.run_ticks(1)
	_runner.snapshot.events.append_array(shot)
	_frame()
	assert_array(_bar_rows()).is_empty()
	assert_int(_units.hit_time_ms(6)).is_equal(UnitLayer.NEVER_HIT)
	# A heal is not a hit, but a later drop is one.
	_runner.world.hp[6] -= 100
	_runner.run_ticks(1)
	_now_ms = 100
	_frame()
	assert_int(_units.hit_time_ms(6)).is_equal(100)
	_now_ms = 200
	_runner.world.hp[6] += 50
	_runner.run_ticks(1)
	_frame()
	assert_int(_units.hit_time_ms(6)).is_equal(100)  # Not 200.
	# The healed hp is the one the layer compares with: a drop to 240 is below 250 but not below
	# the 200 of before the heal, and it is a hit.
	_now_ms = 250
	_hit(6, 10)
	_frame()
	assert_int(_units.hit_time_ms(6)).is_equal(250)
	# A unit that appears is not hit, whatever its hp, and nor is a neighbour.
	_now_ms = 300
	_runner.world.add_unit(2, 0, 30500, 12500)
	_runner.run_ticks(1)
	_frame()
	assert_int(_units.hit_time_ms(40)).is_equal(UnitLayer.NEVER_HIT)
	assert_int(_units.hit_time_ms(6)).is_equal(250)
	# Hits between two frames, however many ticks, are one stamp of the frame that saw them.
	_now_ms = 400
	_hit(8, 10)
	_hit(8, 10)
	_hit(9, 10)
	_frame()
	assert_int(_units.hit_time_ms(8)).is_equal(400)
	assert_int(_units.hit_time_ms(9)).is_equal(400)


func test_unit_5_is_hit_then_unit_2_dies_in_a_later_tick_and_the_bar_stays_on_unit_5() -> void:
	_now_ms = 1000
	_hit(4, 50)  # Tank 5, row 4.
	_frame()
	assert_array(_bar_rows()).is_equal([4])
	_now_ms = 1500
	_runner.world.hp[1] = 0  # Tank 2 dies in a later tick: tank 5 is row 3, and tank 6 is row 4.
	_runner.run_ticks(1)
	_frame()
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_id[3]).is_equal(5)
	assert_array(_bar_rows()).is_equal([3])  # On unit 5 and on no other unit.
	assert_int(_units.hit_time_ms(3)).is_equal(1000)
	for row: int in snap.unit_count():
		if row != 3:
			assert_int(_units.hit_time_ms(row)).is_equal(UnitLayer.NEVER_HIT)
	# The window is still that of the hit: unit 5 goes at 4000 ms, whatever else happened.
	_now_ms = 4000
	_frame()
	assert_array(_bar_rows()).is_equal([3])
	_now_ms = 4001
	_frame()
	assert_array(_bar_rows()).is_empty()


func test_hit_times_follow_their_units_through_every_kind_of_row_change() -> void:
	# Units 5, 6 and 7 are hit at different times, then the rows around them change in every way:
	# a death before them, one after them, two in a row, and a spawn, in ticks with no frame
	# between some of them. Each hit time stays on its unit.
	_now_ms = 100
	_hit(4, 10)
	_frame()
	_now_ms = 200
	_hit(5, 10)
	_frame()
	_now_ms = 300
	_hit(6, 10)
	_frame()
	_runner.world.hp[0] = 0  # Unit 1 (before them) and unit 40 (after them) in one tick.
	_runner.world.hp[39] = 0
	_runner.run_ticks(1)
	_runner.world.hp[0] = 0  # Units 2 and 3, now rows 0 and 1, a tick later with no frame between
	_runner.world.hp[1] = 0  # (two neighbours go together), and a unit that appears.
	_runner.world.add_unit(2, 0, 30500, 12500)
	_runner.run_ticks(1)
	_frame()
	var snap: MatchSnapshot = _runner.snapshot
	var expected: Dictionary[int, int] = {5: 100, 6: 200, 7: 300}
	for row: int in snap.unit_count():
		var id: int = snap.unit_id[row]
		assert_int(_units.hit_time_ms(row)).is_equal(expected.get(id, UnitLayer.NEVER_HIT))
	assert_int(snap.unit_count()).is_equal(37)
	assert_array(_bar_rows()).is_equal([snap.index_of(5), snap.index_of(6), snap.index_of(7)])


func test_a_hit_in_the_tick_of_a_death_before_any_frame_still_marks_the_survivor() -> void:
	_frame()  # The layer has seen full hp.
	_now_ms = 700
	_runner.world.hp[4] -= 30  # Unit 5 is hit and unit 2 dies in the same tick.
	_runner.world.hp[1] = 0
	_runner.run_ticks(1)
	_frame()
	assert_int(_runner.snapshot.unit_id[3]).is_equal(5)
	assert_array(_bar_rows()).is_equal([3])
	assert_int(_units.hit_time_ms(3)).is_equal(700)


func test_a_unit_hit_and_destroyed_in_one_tick_leaves_no_bar() -> void:
	_hit(4, 1000)  # Tank 5 takes more than its hp: it is removed in the tick.
	_frame()
	assert_int(_runner.snapshot.unit_count()).is_equal(39)
	assert_array(_bar_rows()).is_empty()


func test_rows_that_do_not_exist_have_no_hit_and_no_ring() -> void:
	# A packed array counts a negative index from its end, so the last row (39) is hit and ringed:
	# row -1 must still answer "none" and not read it.
	_units.set_selected(PackedInt32Array([40]))
	_now_ms = 500
	_hit(39, 40)
	_frame()
	assert_int(_units.hit_time_ms(39)).is_equal(500)
	assert_bool(_units.is_ringed(39)).is_true()
	for row: int in [-1, 40, 1000]:
		assert_int(_units.hit_time_ms(row)).is_equal(UnitLayer.NEVER_HIT)
		assert_bool(_units.is_ringed(row)).is_false()


func test_a_new_match_clears_the_selection_the_hits_and_the_bars() -> void:
	_units.set_selected(PackedInt32Array([2, 31]))
	_now_ms = 50
	_hit(4, 40)
	_frame()
	assert_array(_bar_rows()).is_equal([1, 4, 30])
	_runner.start()  # Same rows_version, another match_serial.
	_frame()
	assert_array(_bar_rows()).is_empty()
	assert_int(_bars.rect_count()).is_equal(0)
	for row: int in 40:
		assert_int(_units.hit_time_ms(row)).is_equal(UnitLayer.NEVER_HIT)
		assert_bool(_units.is_ringed(row)).is_false()
	_hit(4, 40)  # The new match is hit like any other.
	_frame()
	assert_array(_bar_rows()).is_equal([4])


func test_a_bar_follows_its_unit_between_ticks() -> void:
	CommandQueue.submit(Command.attack_move(1, PackedInt32Array([30]), 17800, 26900))
	_runner.run_ticks(1)
	_units.set_selected(PackedInt32Array([30]))
	for fraction: float in [0.0, 0.25, 0.5, 0.75]:
		_runner._micro_ticks = roundi(fraction * MatchRunner.MICRO_TICKS_PER_TICK)
		_frame()
		var at: Vector2 = _units.unit_screen_position(29)
		var top_left: Vector2 = _camera.world_to_screen(_bars.rect_at(0).position)
		var bottom_right: Vector2 = _camera.world_to_screen(_bars.rect_at(0).end)
		assert_float((top_left.x + bottom_right.x) * 0.5).is_equal_approx(at.x, 0.05)
		assert_float(at.y - bottom_right.y).is_equal_approx(26.0 * _camera.zoom.x + 1.75, 0.05)
	assert_float(_runner.alpha()).is_equal_approx(0.75, 0.001)


func test_a_resize_sizes_the_bars_again_for_the_new_dp() -> void:
	get_window().size = SENTINEL_SIZE
	await await_idle_frame()  # Every size below differs from this one, so each one is a resize.
	_units.set_selected(PackedInt32Array([2]))
	_frame()
	var zoom: float = _camera.zoom.x
	assert_float(_bars.rect_at(0).size.x * zoom).is_equal_approx(22.0 * 1.75, 0.01)
	var desktop: UiMetrics = UiProfiles.by_name(&"desktop")
	UiScale.set_override(desktop)
	get_window().size = desktop.window_size
	await await_idle_frame()  # size_changed: 1 dp is 1 px.
	_frame()
	assert_float(_bars.rect_at(0).size.x * zoom).is_equal_approx(22.0, 0.01)
	var tablet: UiMetrics = UiProfiles.by_name(&"web_tablet")
	UiScale.set_override(tablet)
	get_window().size = tablet.window_size
	await await_idle_frame()
	_frame()
	assert_float(_bars.rect_at(0).size.x * zoom).is_equal_approx(22.0 * 1.25, 0.01)


func test_a_layer_without_a_runner_a_snapshot_or_a_unit_layer_plans_nothing() -> void:
	var waiting: MatchRunner = auto_free(MatchRunner.new())  # Not started: no snapshot yet.
	waiting.scenario = load(SCENARIO)
	var layers: Array[HealthBarLayer] = [
		auto_free(HealthBarLayer.new()),  # No runner, no unit layer.
		auto_free(HealthBarLayer.new()),  # A runner without a snapshot.
		auto_free(HealthBarLayer.new()),  # A snapshot, no unit layer.
	]
	layers[1].runner = waiting
	layers[1].unit_layer = _units
	layers[2].runner = _runner
	for layer: HealthBarLayer in layers:
		add_child(layer)
		layer.set_process(false)
		layer._process(0.0)
		assert_int(layer.bar_count()).is_equal(0)
		assert_int(layer.rect_count()).is_equal(0)


func test_frames_leave_no_new_objects_alive() -> void:
	_units.set_selected(PackedInt32Array([2, 31]))
	_hit(4, 40)
	_hit(35, 40)
	_frame()
	await await_idle_frame()
	await await_idle_frame()  # The first idle frame leaves an object of the test runner behind.
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame_index: int in 25:  # 2500 ms: inside the window.
		_now_ms += 100
		_frame()
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)
	assert_int(_bars.bar_count()).is_equal(4)  # Bars were planned in every one of them.


## One frame: the unit layer, then the bar layer, in the scene's order.
func _frame() -> void:
	_units._process(0.0)
	_bars._process(0.0)


## Row `row` loses `amount` hp in one tick.
func _hit(row: int, amount: int) -> void:
	_runner.world.hp[row] -= amount
	_runner.run_ticks(1)


## The unit rows that have a bar, in the order the layer planned them.
func _bar_rows() -> Array[int]:
	var rows: Array[int] = []
	for bar: int in _bars.bar_count():
		rows.append(_bars.bar_row(bar))
	return rows
