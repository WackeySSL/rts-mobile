extends GdUnitTestSuite
## `StrikeFx` in the scene (plan P141, ADR 0027 sections 3 and 9): `main.tscn` wires `LifeFx` to the
## `BuildingLayer` (one property line), `LifeFx` makes `StrikeFx` at absolute z 55 and hands it the
## same wiring as `GroundFx`, the layer draws from the one strike atlas and paints its plan one
## quad for one, and an idle layer costs nothing. The rules of the strikes are in test_strike_fx.gd.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const POINT: Vector2i = Vector2i(28500, 8500)  ## Dark and off the diagonal.
const BLACKOUT: int = 2
const EPS: float = 0.01

var _runner: MatchRunner
var _camera: RtsCamera
var _buildings: BuildingLayer
var _fx: LifeFx


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Buildings.spawn(1, "fossil_strike", 6, 12), Buildings.spawn(1, "renew_strike", 16, 10)
	]
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
		assert_that(wired[&"unit_layer"]).is_equal(NodePath("../UnitLayer"))
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


func test_a_net_is_painted_as_one_pass_while_it_falls_and_as_two_while_it_settles() -> void:
	var strike: StrikeFx = _fx.strike
	var events: PackedInt32Array = PackedInt32Array(
		[World.Event.STRIKE, 2, POINT.x, POINT.y, BLACKOUT, 1, 0, 0]
	)
	Rig.deliver(_runner, events, 100)
	var nets: StrikeNet = strike.nets()
	var lattice: int = nets.lattice_for(IsoProjection.ellipse_px(_array_radius()))
	strike.set_process(true)  # The engine's own frames plan and draw.
	Rig.at(_runner, 104, 0.5)  # Half way down the 600 ms: scale 1.6 to 1 eased 0.25.
	await await_idle_frame()
	await await_idle_frame()
	assert_int(nets.drawn_nets()).is_equal(1)
	# One pass of every line, no ring pass, at the net's alpha, the width in world px unchanged.
	assert_int(nets.drawn_segments(0, 0)).is_equal(nets.edges(lattice).size() / 2)
	assert_int(nets.drawn_segments(0, 1)).is_equal(0)
	assert_float(nets.drawn_alpha(0, 0)).is_equal_approx(strike.net_alpha(0), 0.001)
	var scale_now: float = strike.net_scale(0)
	assert_float(scale_now).is_greater(1.0)
	var edge_world: float = nets.drawn_edge_width(0, 0) * scale_now
	assert_float(edge_world).is_equal_approx(LifeRegions.NET_EDGE_PX, 0.001)
	var light_world: float = nets.drawn_light_width(0, 0) * scale_now
	assert_float(light_world).is_equal_approx(LifeRegions.NET_LIGHT_PX, 0.001)
	Rig.at(_runner, 112, 0.75)  # 250 ms into the 500 ms settle (the net landed at 9 ticks).
	await await_idle_frame()
	await await_idle_frame()
	var life: LifeSettings = _fx.life
	assert_int(nets.drawn_segments(0, 0)).is_equal(nets.interior(lattice).size() / 2)
	assert_int(nets.drawn_segments(0, 1)).is_equal(nets.ring(lattice).size() / 2)
	assert_float(nets.drawn_alpha(0, 0)).is_equal_approx(life.net_alpha * 0.25, 0.001)
	assert_float(nets.drawn_alpha(0, 1)).is_equal_approx(life.net_alpha * 0.5, 0.001)
	assert_float(nets.drawn_alpha(0, 1)).is_greater(nets.drawn_alpha(0, 0))
	for pass_of: int in 2:
		var edge: float = nets.drawn_edge_width(0, pass_of) * strike.net_scale(0)
		assert_float(edge).is_equal_approx(LifeRegions.NET_EDGE_PX, 0.001)
	strike.set_process(false)


func _array_radius() -> int:
	var snap: MatchSnapshot = _runner.snapshot
	return snap.type_strike_radius[snap.type_index[snap.index_of(2)]]
