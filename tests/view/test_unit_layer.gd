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
	CommandQueue.submit(Command.attack_move(1, TANK_1, 11500, 20000))
	_runner.run_ticks(1)  # Tank 1 moves (107, 53) milli: px (544, 1184) -> (550.848, 1187.392).
	_render(0.0)
	var prev: Vector2 = Vector2(544, 1184)
	assert_that(_rig(0).position).is_equal(prev)  # alpha 0 shows the old tick.
	for alpha: float in [0.25, 0.5, 0.75]:
		_runner._process(1.0 / 60.0)
		_render(0.0)
		var expected: Vector2 = prev + (Vector2(550.848, 1187.392) - prev) * alpha
		assert_vector(_rig(0).position).is_equal_approx(expected, Vector2(0.001, 0.001))
		assert_that(_rig(1).position).is_equal(Vector2(640, 1184))  # Tank 2 stands still.


func test_frames_without_ticks_leave_every_world_array_unchanged() -> void:
	CommandQueue.submit(Command.attack_move(1, PackedInt32Array(range(1, 11)), 20000, 30000))
	_runner.run_ticks(3)
	var before: int = _world_hash()
	for _frame: int in 8:
		_runner._process(0.004)  # 32 ms in all: under one tick.
		_layer._process(0.016)  # The hulls turn on these frames.
	assert_float(_runner.alpha()).is_greater(0.0)
	assert_int(_runner.world.tick).is_equal(3)
	assert_int(_world_hash()).is_equal(before)


func test_frames_leave_no_new_objects_alive() -> void:
	CommandQueue.submit(Command.attack_move(1, TANK_1, 8500, 30000))
	_runner.run_ticks(1)
	_layer._process(0.016)  # The first turn.
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for _frame: int in 20:
		_layer._process(0.016)
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_equal(objects)


func test_a_restarted_match_gets_new_rigs_with_their_own_tint_and_heading() -> void:
	var south: Callable = func() -> void:
		CommandQueue.submit(Command.attack_move(1, TANK_1, 8500, 21500))
		_runner.run_ticks(1)
		_render(0.5)
	south.call()
	_layer.team_colors = PackedColorArray([Color("9AA5B1"), BLUE])  # Owner 2 has no colour.
	_runner.start()
	_layer._process(0.05)
	assert_int(_layer.rig_count()).is_equal(40)
	assert_int(_layer.get_child_count()).is_equal(40)
	assert_that(_rig(0).get_node("Team").modulate).is_equal(BLUE)
	assert_that(_rig(30).get_node("Team").modulate).is_equal(Color("9AA5B1"))  # The neutral one.
	assert_float(_rig(0).get_node("Hull").rotation).is_equal(0.0)  # Neither heading nor aim is kept.
	south.call()
	assert_float(_rig(0).get_node("Hull").rotation).is_equal_approx(PI / 2.0, 0.001)
	await await_idle_frame()  # The old rigs are freed.


func test_the_hull_eases_toward_where_the_tank_moves_and_keeps_its_heading_when_it_stops() -> void:
	var hull: Sprite2D = _rig(0).get_node("Hull")
	# 3 tiles (25 ticks) south-east on a 3-4-5 path, then west (127 degrees), then east (180).
	var goals: Array[Vector2i] = [Vector2i(10300, 20900), Vector2i(7300, 20900)]
	goals.append(goals[0])
	var headings: Array[float] = [atan2(4.0, 3.0), PI, 0.0]
	for leg: int in 3:
		CommandQueue.submit(Command.attack_move(1, TANK_1, goals[leg].x, goals[leg].y))
		_runner.run_ticks(1)
		var before: float = hull.rotation
		_layer._process(0.05)  # 12 rad/s * 0.05 s = 0.6 rad.
		assert_float(absf(angle_difference(before, hull.rotation))).is_equal_approx(0.6, 0.001)
		_render(0.5)
		assert_float(hull.rotation).is_equal_approx(headings[leg], 0.001)
		_runner.run_ticks(40)
		assert_int(_runner.world.order[0]).is_equal(World.Order.IDLE)
		_render(0.5)
		assert_float(hull.rotation).is_equal_approx(headings[leg], 0.001)
		assert_float(_rig(0).get_node("Team").rotation).is_equal(hull.rotation)
		assert_float(_rig(0).get_node("Turret").rotation).is_equal(hull.rotation)


func test_the_short_last_step_onto_the_goal_does_not_turn_the_hull() -> void:
	# Tank 1 drives 5.5 tiles almost due east. Its last tick moves (1, 1) milli, which is 45 degrees.
	CommandQueue.submit(Command.attack_move(1, TANK_1, 14021, 18540))
	for _tick: int in 50:  # 47 to arrive. Every tick is drawn, as on the phone.
		_runner.run_ticks(1)
		_layer._process(0.05)
	assert_int(_runner.world.order[0]).is_equal(World.Order.IDLE)
	assert_float(_rig(0).get_node("Hull").rotation).is_equal_approx(0.0, 0.02)


func test_unit_screen_position_is_the_rig_seen_through_the_camera() -> void:
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	assert_that(_layer.unit_screen_position(0)).is_equal(Vector2(684, 444))  # 640 + 44, 360 + 84
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(2000, 600)
	assert_that(_layer.unit_screen_position(30)).is_equal(Vector2(952, 468))  # 640 + 208 * 1.5, ...


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
	state.append_array([w.map_w, w.map_h, w.type_ids, w.type_speed, w.type_radius])
	state.append_array([w.type_selection_radius, w.type_spacing])
	state.append_array([w.pos_x, w.pos_y, w.goal_x, w.goal_y, w.order])
	state.append_array([_runner.prev_pos_x, _runner.prev_pos_y])
	return hash(state)
