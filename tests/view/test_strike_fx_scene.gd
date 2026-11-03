extends GdUnitTestSuite
## `StrikeFx` in the scene (plan P141, ADR 0027 sections 3 and 9): `main.tscn` wires `LifeFx` to the
## `BuildingLayer` (one property line), `LifeFx` makes `StrikeFx` at absolute z 55 and hands it the
## same wiring as `GroundFx`, the layer draws from the one strike atlas and paints its plan one
## quad for one, and an idle layer costs nothing. The rules of the strikes are in test_strike_fx.gd.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const POINT: Vector2i = Vector2i(20500, 20500)

var _runner: MatchRunner
var _camera: RtsCamera
var _buildings: BuildingLayer
var _fx: LifeFx


func before_test() -> void:
	var spawns: Array[SpawnDef] = [Buildings.spawn(1, "fossil_strike", 10, 10)]
	_runner = auto_free(Buildings.runner(Buildings.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = IsoProjection.ground_to_px(POINT.x, POINT.y)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	add_child(_buildings)
	_buildings.set_process(false)
	_buildings._process(0.0)
	_fx = auto_free(LifeFx.new())
	_fx.runner = _runner
	_fx.camera = _camera
	_fx.building_layer = _buildings
	add_child(_fx)
	_fx.ground.set_process(false)
	_fx.strike.set_process(false)


func after_test() -> void:
	CommandQueue.clear()


func test_main_scene_wires_life_fx_to_the_building_layer() -> void:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) != "LifeFx":
			continue
		var wired: Dictionary[StringName, Variant] = {}
		for at: int in state.get_node_property_count(index):
			wired[state.get_node_property_name(index, at)] = state.get_node_property_value(
				index, at
			)
		assert_that(wired[&"building_layer"]).is_equal(NodePath("../BuildingLayer"))
		assert_that(wired[&"runner"]).is_equal(NodePath("../MatchRunner"))
		return
	fail("main.tscn has no LifeFx")


func test_life_fx_makes_strike_fx_at_absolute_z_55_with_the_same_wiring() -> void:
	var strike: StrikeFx = _fx.strike
	assert_object(strike).is_not_null()
	assert_object(strike.get_parent()).is_same(_fx)
	assert_int(strike.z_index).is_equal(55)
	assert_bool(strike.z_as_relative).is_false()
	assert_object(strike.runner).is_same(_runner)
	assert_object(strike.camera).is_same(_camera)
	assert_object(strike.life).is_same(_fx.life)
	assert_object(strike.building_layer).is_same(_buildings)
	assert_object(_fx.ground.get("building_layer")).is_null()  # A layer without the property.


func test_the_layer_draws_one_texture_the_strike_atlas_and_paints_its_plan_one_for_one() -> void:
	var strike: StrikeFx = _fx.strike
	assert_str(strike.texture().resource_path).is_equal(LifeRegions.STRIKE_ART)
	for kind: StringName in StrikeFx.KINDS:
		assert_str(LifeRegions.texture_path(kind)).is_equal(LifeRegions.STRIKE_ART)
	assert_int(strike.quad_count()).is_equal(0)  # Idle: nothing planned, nothing to draw.
	var events: PackedInt32Array = PackedInt32Array(
		[World.Event.STRIKE, 1, POINT.x, POINT.y, 1, 1, 100 + 45, 0]
	)
	Rig.deliver(_runner, events, 100)
	Rig.at(_runner, 100, 0.0)
	strike.set_process(true)  # The engine's own frame plans and draws.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(strike.quad_count()).is_equal(3)
	assert_int(strike.drawn_quads()).is_equal(3)
	strike.set_process(false)
