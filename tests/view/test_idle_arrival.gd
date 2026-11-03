extends GdUnitTestSuite
## The rumble across a real arrival (plan P140b, ADR 0027 section 3): 30 blue tanks of the
## controls_test scenario get one Command.move and the real sim plays their drive, the camera sees
## both the start and the point, the separation pushes on arrival included (it moves tanks that are
## IDLE by a few milli for about a second). The layer draws every tick at two alphas. While they
## drive some Hull is off rest; once a tank's order is IDLE (from its second idle tick on, the first
## one still holds its last step) its Hull is at rest in every frame, though the separation still
## moves it, by up to half a step: a unit with no order is not driving.

const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const POINT: Vector2i = Vector2i(20016, 21516)
const TANKS: int = 30
const TICKS: int = 450
const FAR: float = 1.0e6

var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera


func before_test() -> void:
	CommandQueue.clear()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = load(SCENARIO_PATH) as ScenarioDef
	_runner.paused = true
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(FAR, FAR)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	_layer.life = LifeSettings.new()
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)
	var centre: Vector2 = Vector2.ZERO
	for row: int in TANKS:
		centre += _layer.rig(row).position / float(TANKS)
	var goal: Vector2 = IsoProjection.ground_to_px(POINT.x, POINT.y)
	_camera.position = (centre + goal) * 0.5  # Between the start and the point.
	_camera.zoom = Vector2(0.4, 0.4)


func after_test() -> void:
	CommandQueue.clear()


func test_a_move_order_rumbles_while_the_tanks_drive_and_never_after_they_arrive() -> void:
	var ids: PackedInt32Array = PackedInt32Array(range(1, TANKS + 1))
	CommandQueue.submit(Command.move(1, ids, POINT.x, POINT.y))
	var snap: MatchSnapshot = _runner.snapshot
	var idle_ticks: PackedInt32Array = PackedInt32Array()
	idle_ticks.resize(TANKS)
	var rumbling: int = 0
	var settled: int = 0
	var creeping: int = 0
	var wrong: int = 0
	for _tick: int in TICKS:
		_runner.run_ticks(1)
		snap = _runner.snapshot
		for row: int in TANKS:
			idle_ticks[row] = idle_ticks[row] + 1 if snap.order[row] == World.Order.IDLE else 0
		for micro: int in [0, 8]:
			_runner._micro_ticks = micro
			_layer._process(0.0)
			var view: Rect2 = _camera.visible_world_rect().grow(UnitLayer.IDLE_MARGIN_PX)
			for row: int in TANKS:
				var hull: Sprite2D = _layer.rig(row).get_node("Hull")
				if not view.has_point(_layer.rig(row).position):
					continue  # Life is written for rigs in view only.
				if idle_ticks[row] >= 2:
					settled += 1
					wrong += 0 if hull.position == Vector2.ZERO else 1
					var dx: int = snap.pos_x[row] - _runner.prev_pos_x[row]
					var dy: int = snap.pos_y[row] - _runner.prev_pos_y[row]
					creeping += 1 if dx != 0 or dy != 0 else 0
				elif hull.position != Vector2.ZERO:
					rumbling += 1
	assert_int(rumbling).is_greater(100)  # They rumbled while they drove.
	assert_int(settled).is_greater(1000)
	assert_int(creeping).is_greater(0)  # And the separation did move arrived tanks.
	assert_int(wrong).is_equal(0)
	assert_int(snap.order.count(World.Order.IDLE)).is_equal(snap.unit_count())
