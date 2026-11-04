extends GdUnitTestSuite
## `LifeFx` and `GroundFx` in the scene and in a long run (plan P138, ADR 0027 sections 3 and 9):
## `main.tscn` holds one `LifeFx` between `DecalLayer` and `WorldSort`, wired to the runner and the
## camera; it makes `GroundFx` at absolute z 3; the layer draws from the one texture of the life
## atlas, paints the plan one quad for one; and a long drive makes no node and no object after the
## first puffs. The dust rules are in test_ground_fx.gd. Also the two small helpers of
## `LifeRegions` that the life layers read (the mirror rule).

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"

var _runner: MatchRunner
var _camera: RtsCamera
var _fx: LifeFx
var _tick: int = 100


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_fx = auto_free(LifeFx.new())
	_fx.runner = _runner
	_fx.camera = _camera
	add_child(_fx)
	_fx.ground.set_process(false)
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(Rig.LIGHT)
	_camera.position = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])


func after_test() -> void:
	CommandQueue.clear()


func test_main_scene_has_one_life_fx_between_the_decals_and_the_sort_wired_to_runner_and_camera(
) -> void:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var names: Array[String] = []
	for index: int in state.get_node_count():
		if str(state.get_node_path(index, true)) == ".":  # The root's own children.
			names.append(state.get_node_name(index))
	assert_int(names.count("LifeFx")).is_equal(1)
	assert_int(names.find("LifeFx")).is_equal(names.find("DecalLayer") + 1)
	assert_int(names.find("WorldSort")).is_equal(names.find("LifeFx") + 1)
	for index: int in state.get_node_count():
		if state.get_node_name(index) != "LifeFx":
			continue
		var wired: Dictionary[StringName, Variant] = {}
		for at: int in state.get_node_property_count(index):
			wired[state.get_node_property_name(index, at)] = state.get_node_property_value(
				index, at
			)
		assert_that(wired[&"runner"]).is_equal(NodePath("../MatchRunner"))
		assert_that(wired[&"camera"]).is_equal(NodePath("../Camera"))


func test_life_fx_makes_ground_fx_at_absolute_z_3_with_its_numbers_and_wiring() -> void:
	var ground: GroundFx = _fx.ground
	assert_object(ground).is_not_null()
	assert_object(ground.get_parent()).is_same(_fx)
	assert_int(ground.z_index).is_equal(3)
	assert_bool(ground.z_as_relative).is_false()
	assert_object(ground.runner).is_same(_runner)
	assert_object(ground.camera).is_same(_camera)
	assert_object(ground.life).is_same(_fx.life)
	assert_object(_fx.life).is_same(load("res://data/life_settings.tres"))  # The fallback.
	assert_int(_fx.get_child_count()).is_equal(3)  # GroundFx, StrikeFx and AirFx.


func test_the_layer_draws_one_texture_the_life_atlas_and_paints_its_plan_one_for_one() -> void:
	var ground: GroundFx = _fx.ground
	assert_str(ground.texture().resource_path).is_equal(LifeRegions.texture_path(&"dust"))
	assert_str(ground.texture().resource_path).is_equal(LifeRegions.LIFE_ART)
	_drive(0, 900, 3)
	Rig.at(_runner, _tick, 0.0)
	ground.set_process(true)  # The engine's own frame plans and draws.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(ground.quad_count()).is_equal(3)
	assert_int(ground.drawn_quads()).is_equal(3)
	ground.set_process(false)


@warning_ignore("integer_division")
func test_a_long_drive_makes_no_node_and_no_object_after_the_first_puffs() -> void:
	var ground: GroundFx = _fx.ground
	var forward: int = 700
	for tick: int in 60:  # Warm-up: the ring fills, the travel table is made.
		_drive_one(forward if (tick / 10) % 2 == 0 else -forward, 0)
		for _frame: int in 4:
			Rig.at(_runner, _tick, 0.25 * _frame)
			ground._process(0.0)
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = _fx.get_child_count() + ground.get_child_count()
	var most: int = 0
	for tick: int in 300:
		_drive_one(forward if (tick / 10) % 2 == 0 else -forward, 0)
		for frame: int in 4:
			Rig.at(_runner, _tick, 0.25 * frame)
			ground._process(0.0)
			most = maxi(most, ground.quad_count())
	assert_int(int(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(objects)
	assert_int(_fx.get_child_count() + ground.get_child_count()).is_equal(nodes)
	assert_int(most).is_between(1, 48)  # Never over the quota; a puff lives 9 ticks.


func test_the_mirror_rule_is_flames_and_sparks_only_and_every_frame_resolves() -> void:
	for kind: StringName in LifeRegions.FIRST:
		var allowed: bool = kind in [&"flare", &"fire", &"spark", &"jet"]
		assert_bool(LifeRegions.mirrorable(kind)).override_failure_message(kind).is_equal(allowed)
		var last: int = LifeRegions.FRAMES[kind] - 1
		var step: int = LifeRegions.STEP[kind]
		var expected: Vector2i = LifeRegions.FIRST[kind].position + Vector2i(last * step, 0)
		assert_that(LifeRegions.region(kind, last).position).is_equal(expected)
	assert_array(LifeRegions.MIRRORABLE).has_size(4)


func _drive(dx: int, dy: int, ticks: int) -> void:
	for _i: int in ticks:
		_drive_one(dx, dy)


func _drive_one(dx: int, dy: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.prev_pos_x = snap.pos_x.duplicate()
	snap.prev_pos_y = snap.pos_y.duplicate()
	var row: int = snap.index_of(Rig.LIGHT)
	snap.pos_x[row] += dx
	snap.pos_y[row] += dy
	_tick += 1
	snap.tick = _tick
	_runner.ticked.emit(_tick)
