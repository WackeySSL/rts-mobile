extends GdUnitTestSuite
## UnitLayer on data/scenarios/controls_test.tres: 40 rigs in World row order, ids 1-30 blue and
## 31-40 red. Tank 1 stands at px (544, 1184), tank 2 at (640, 1184) and tank 7 at (544, 1280).
## The runner is not in the tree, so only the calls here move time: runner._process() moves the
## interpolation clock and layer._process() draws a frame.

const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const ART: String = "res://assets/art/svg/units/light_tank_%s.svg"
const BASE_SIZE: Vector2i = Vector2i(1280, 720)
const BLUE: Color = Color("2F80ED")
const RED: Color = Color("E5484D")
const TANK_1: PackedInt32Array = [1]

var _window_size_before: Vector2i
var _runner: MatchRunner
var _camera: RtsCamera
var _layer: UnitLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	get_window().size = BASE_SIZE
	await await_idle_frame()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO)
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)  # Frames come only from _render().


func after_test() -> void:
	CommandQueue.clear()


func test_one_rig_per_unit_with_hull_team_and_turret_layers_in_draw_order() -> void:
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.get_child_count()).is_equal(40)
	for row: int in 40:
		var names: Array = _rig(row).get_children().map(func(n: Node) -> StringName: return n.name)
		assert_array(names).is_equal([&"Hull", &"Team", &"Turret"])
	assert_str(_rig(0).name).is_equal("Unit1")
	for layer: String in ["hull", "team", "turret"]:
		var texture: Texture2D = _rig(0).get_node(layer.capitalize()).texture
		assert_str(texture.resource_path).is_equal(ART % layer)


func test_team_layers_are_tinted_by_owner_and_the_other_layers_are_not() -> void:
	for row: int in 40:
		assert_that(_rig(row).get_node("Team").modulate).is_equal(BLUE if row < 30 else RED)
		assert_that(_rig(row).get_node("Hull").modulate).is_equal(Color.WHITE)
		assert_that(_rig(row).get_node("Turret").modulate).is_equal(Color.WHITE)
	assert_array(_layer.team_colors).is_equal(PackedColorArray([Color("9AA5B1"), BLUE, RED]))


func test_rigs_start_on_the_unit_positions_in_px() -> void:
	assert_that(_rig(0).position).is_equal(Vector2(544, 1184))
	assert_that(_rig(1).position).is_equal(Vector2(640, 1184))
	assert_that(_rig(6).position).is_equal(Vector2(544, 1280))
	assert_that(_rig(30).position).is_equal(Vector2(2208, 672))  # Red target, tile (34, 10).
	assert_that(_rig(39).position).is_equal(Vector2(1952, 2592))  # Red target, tile (26, 40).


func test_rig_positions_are_prev_plus_cur_minus_prev_times_alpha() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 11500, 18500))
	_runner.run_ticks(1)  # Tank 1 moves 120 milli east: px 544 -> 551.68.
	_render(0.0)
	assert_that(_rig(0).position).is_equal(Vector2(544, 1184))  # alpha 0 shows the old tick.
	for expected_x: float in [545.92, 547.84, 549.76]:  # alpha 0.25, 0.5, 0.75
		_runner._process(1.0 / 60.0)
		_render(0.0)
		var tolerance: Vector2 = Vector2(0.001, 0.001)
		assert_vector(_rig(0).position).is_equal_approx(Vector2(expected_x, 1184), tolerance)
		assert_that(_rig(1).position).is_equal(Vector2(640, 1184))  # Tank 2 stands still.


func test_frames_without_ticks_leave_every_world_array_unchanged() -> void:
	CommandQueue.submit(Command.attack_move(1, PackedInt32Array(range(1, 11)), 20000, 30000))
	_runner.run_ticks(3)
	var before: int = _world_hash()
	for _frame: int in 8:
		_runner._process(0.004)  # 32 ms in all: under one tick.
		_render(0.016)
	assert_float(_runner.alpha()).is_greater(0.0)
	assert_int(_runner.world.tick).is_equal(3)
	assert_int(_world_hash()).is_equal(before)


func test_frames_leave_no_new_objects_alive() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 8500, 30000))
	_runner.run_ticks(1)
	_render(0.016)  # The first turn.
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame: int in 20:
		_layer._process(0.016)
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)


func test_a_restarted_match_gets_new_rigs() -> void:
	var old_rig: Node2D = _rig(0)
	_runner.start()
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.get_child_count()).is_equal(40)
	assert_object(_rig(0)).is_not_same(old_rig)
	await await_idle_frame()  # The old rigs are freed.


func test_the_hull_turns_toward_where_the_tank_moves_and_keeps_its_heading_when_it_stops() -> void:
	var hull: Sprite2D = _rig(0).get_node("Hull")
	# South, then west (a turn of 90 degrees), then east (a turn of 180). Each leg is 3 tiles.
	var goals_x: Array[int] = [8500, 5500, 8500]  # milli; y is 21500 for all three.
	var headings: Array[float] = [PI / 2.0, PI, 0.0]
	for leg: int in 3:
		CommandQueue.submit(Command.attack_move(1, TANK_1, goals_x[leg], 21500))
		_runner.run_ticks(1)
		_render(0.5)
		assert_float(absf(angle_difference(hull.rotation, headings[leg]))).is_less(0.05)
		_runner.run_ticks(40)  # 25 ticks to arrive; then it stands still.
		assert_int(_runner.world.order[0]).is_equal(World.Order.IDLE)
		_render(0.5)
		assert_float(absf(angle_difference(hull.rotation, headings[leg]))).is_less(0.05)
		assert_float(_rig(0).get_node("Team").rotation).is_equal(hull.rotation)
		assert_float(_rig(0).get_node("Turret").rotation).is_equal(hull.rotation)


func test_unit_screen_position_is_the_rig_seen_through_the_camera() -> void:
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	assert_that(_layer.unit_screen_position(0)).is_equal(Vector2(684, 444))  # 640 + 44, 360 + 84


func _rig(row: int) -> Node2D:
	return _layer.get_child(row)


## One frame of zero length, then frames of 50 ms that add up to `seconds`.
func _render(seconds: float) -> void:
	_layer._process(0.0)
	for _frame: int in roundi(seconds / 0.05):
		_layer._process(0.05)


## A hash of everything in the World and the runner's prev arrays that a view could damage.
func _world_hash() -> int:
	var w: World = _runner.world
	var state: Array = [w.tick, w.next_id, w.dropped_commands, w.unit_id, w.owner, w.type_index]
	state.append_array([w.pos_x, w.pos_y, w.goal_x, w.goal_y, w.order])
	state.append_array([_runner.prev_pos_x, _runner.prev_pos_y])
	return hash(state)
