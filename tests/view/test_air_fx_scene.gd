extends GdUnitTestSuite
## `AirFx` in the scene (plan P145, ADR 0027 sections 3 and 9): `LifeFx` makes it at absolute z 25
## with the same wiring as the other layers, it draws from the one life atlas and paints its plan
## one quad for one in a real frame, with emitting buildings of both factions (the Derrick League's
## Refinery with steam and a flame, a Turbine Hall with two stacks; the Lumen Accord's Refinery with
## two steam vents) in a real `BuildingLayer`; a long run makes no node and no object after the
## first puffs, and `reduced` takes the quads to zero in the frame. The rules are in test_air_fx.gd.

const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const START: int = 100

var _runner: MatchRunner
var _camera: RtsCamera
var _buildings: BuildingLayer
var _fx: LifeFx


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Buildings.spawn(1, "refinery", 6, 8),
		Buildings.spawn(1, "power_plant", 10, 8),
		Buildings.spawn(2, "renew_refinery", 12, 12),
	]
	_runner = auto_free(Buildings.runner(Buildings.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.camera = _camera
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
	var snap: MatchSnapshot = _runner.snapshot
	var tiles: Array[Vector2i] = []
	for y: int in 32:
		for x: int in 32:
			tiles.append(Vector2i(x, y))
	Buildings.see(snap, 1, tiles)
	var row: int = snap.index_of(1)
	var other: int = snap.index_of(3)
	var middle: Vector2 = IsoProjection.ground_to_px(
		(snap.pos_x[row] + snap.pos_x[other]) / 2, (snap.pos_y[row] + snap.pos_y[other]) / 2
	)
	_camera.position = middle


func after_test() -> void:
	CommandQueue.clear()


func test_life_fx_makes_air_fx_at_absolute_z_25_with_the_wiring_of_the_others() -> void:
	var air: AirFx = _fx.air
	assert_object(air).is_not_null()
	assert_object(air.get_parent()).is_same(_fx)
	assert_int(air.z_index).is_equal(25)
	assert_bool(air.z_as_relative).is_false()
	assert_object(air.runner).is_same(_runner)
	assert_object(air.camera).is_same(_camera)
	assert_object(air.life).is_same(_fx.life)
	assert_object(air.building_layer).is_same(_buildings)
	assert_int(_fx.get_child_count()).is_equal(3)  # GroundFx, StrikeFx and AirFx.
	assert_str(air.texture().resource_path).is_equal(LifeRegions.LIFE_ART)
	assert_str(air.texture().resource_path).is_equal(_fx.ground.texture().resource_path)


func test_a_real_frame_paints_the_plan_one_quad_for_one_for_both_factions() -> void:
	_fx.air.set_process(false)
	for tick: int in range(START, START + 45):
		Rig.deliver(_runner, PackedInt32Array(), tick)
	Rig.at(_runner, START + 44, 0.5)
	_fx.air.set_process(true)  # The engine's own frame plans and draws.
	await await_idle_frame()
	await await_idle_frame()
	var air: AirFx = _fx.air
	assert_int(air.quad_count()).is_between(5, 40)
	assert_int(air.drawn_quads()).is_equal(air.quad_count())
	var owners: Dictionary[int, bool] = {}
	var snap: MatchSnapshot = _runner.snapshot
	for slot: int in air.slot_count():
		var at: Vector2 = air.puff_at(slot)
		for id: int in [1, 2, 3]:
			var row: int = snap.index_of(id)
			var centre: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
			if at.distance_to(centre) < 200.0:
				owners[snap.owner[row]] = true
	assert_array(owners.keys()).contains_exactly_in_any_order([1, 2])
	air.set_process(false)


func test_reduced_takes_the_plan_and_the_draw_to_zero_in_the_frame() -> void:
	for tick: int in range(START, START + 45):
		Rig.deliver(_runner, PackedInt32Array(), tick)
	Rig.at(_runner, START + 44, 0.5)
	_fx.air.set_process(true)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_fx.air.drawn_quads()).is_greater(0)
	_fx.life = _fx.life.duplicate() as LifeSettings
	_fx.air.life = _fx.life
	_fx.life.reduced = true
	await await_idle_frame()
	await await_idle_frame()
	assert_int(_fx.air.slot_count()).is_equal(0)
	assert_int(_fx.air.quad_count()).is_equal(0)
	assert_int(_fx.air.drawn_quads()).is_equal(0)
	_fx.air.set_process(false)


func test_a_long_run_makes_no_node_and_no_object_after_the_first_puffs() -> void:
	var air: AirFx = _fx.air
	var tick: int = START
	for step: int in 120:  # Warm-up: the ring fills, the table is made.
		Rig.deliver(_runner, PackedInt32Array(), tick)
		air._process(0.0)
		tick += 1
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = _fx.get_child_count() + air.get_child_count()
	var most: int = 0
	for step: int in 600:
		Rig.deliver(_runner, PackedInt32Array(), tick)
		for frame: int in 4:
			Rig.at(_runner, tick, 0.25 * float(frame))
			air._process(0.0)
			most = maxi(most, air.quad_count())
		tick += 1
	assert_int(int(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(objects)
	assert_int(_fx.get_child_count() + air.get_child_count()).is_equal(nodes)
	assert_int(most).is_between(1, 80)
