extends GdUnitTestSuite
## The tanker's cargo cue (plan P84b revision 5): the bar under a tanker's rig follows the
## snapshot's `cargo` for empty, partly and full, for the tankers of both factions, is empty again
## when a pooled rig is taken by another unit, belongs to tankers only, and costs no object once the
## pool has warmed up. The view reads the snapshot: the tests set `World.cargo` by hand, as the
## harvest rows would have left it, and publish a tick.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const FOSSIL: StringName = &"harvester"
const RENEW: StringName = &"renew_tanker"
const TANK: StringName = &"light_tank"

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: UnitLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	# The sim knows the types a scenario spawns: both tankers are in it, far from where the tests act.
	var spawns: Array[SpawnDef] = [Rig.spawn(1, "light_tank", 4, 4)]
	spawns.append(Rig.spawn(1, "harvester", 4, 10))
	spawns.append(Rig.spawn(2, "renew_tanker", 20, 10))
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_the_bar_follows_the_cargo_from_empty_through_partly_to_full_for_both_factions() -> void:
	for type_id: StringName in [FOSSIL, RENEW]:
		var row: int = _spawn(type_id, 8000)
		var capacity: int = _capacity(type_id)
		var bar: TankerCargo = _bar(row)
		assert_object(bar).is_not_null()
		assert_int(bar.steps).is_equal(0)  # Empty.
		_carry(row, capacity / 2)
		assert_int(bar.steps).is_between(1, TankerCargo.STEPS - 1)  # Partly.
		_carry(row, 1)
		assert_int(bar.steps).is_equal(1)  # The least load is not empty.
		_carry(row, capacity - 1)
		assert_int(bar.steps).is_equal(TankerCargo.STEPS - 1)  # One short of full is not full.
		_carry(row, capacity)
		assert_int(bar.steps).is_equal(TankerCargo.STEPS)  # Full.
		_carry(row, 0)  # Delivered.
		assert_int(bar.steps).is_equal(0)


func test_the_bar_is_drawn_in_dp_at_the_zoom() -> void:
	var row: int = _spawn(FOSSIL, 8000)
	var one: float = _layer.rig(row).get_node("Cargo").scale.x
	assert_float(one).is_equal_approx(UiScale.base_px_per_dp() / _camera.zoom.x, 0.0001)
	_camera.zoom = _camera.zoom * 2.0
	_layer._process(0.0)
	assert_float(_bar(row).scale.x).is_equal_approx(one / 2.0, 0.0001)


func test_only_a_tanker_has_a_bar() -> void:
	var tank: int = _spawn(TANK, 8000)
	assert_object(_bar(tank)).is_null()
	assert_bool(_layer.rig(tank).has_node("Cargo")).is_false()
	assert_int(_layer.rig(tank).kind & UnitLayer.CARGO_KIND).is_equal(0)
	assert_int(_layer.rig(_spawn(FOSSIL, 9000)).kind & UnitLayer.CARGO_KIND).is_not_equal(0)


func test_a_pooled_rig_comes_back_with_an_empty_bar_for_the_next_tanker() -> void:
	var row: int = _spawn(FOSSIL, 8000)
	var rig: Node2D = _layer.rig(row)
	_carry(row, _capacity(FOSSIL))
	assert_int(_bar(row).steps).is_equal(TankerCargo.STEPS)
	_lose(row)
	var made: int = _layer.rigs_made()
	var next: int = _spawn(FOSSIL, 11000)  # Its own load is nothing.
	assert_object(_layer.rig(next)).is_same(rig)
	assert_int(_layer.rigs_made()).is_equal(made)
	assert_int(_bar(next).steps).is_equal(0)
	# The renew tanker has the same kind of rig, and takes the pooled one with an empty bar as well.
	_carry(next, _capacity(FOSSIL) / 2)
	_lose(next)
	var other: int = _spawn(RENEW, 12000)
	assert_object(_layer.rig(other)).is_same(rig)
	assert_int(_bar(other).steps).is_equal(0)


func test_following_the_cargo_every_frame_makes_no_object_and_redraws_only_on_a_new_step() -> void:
	var row: int = _spawn(FOSSIL, 8000)
	var bar: TankerCargo = _bar(row)
	_carry(row, _capacity(FOSSIL) / 2)
	var draws: int = bar.draws
	var objects: int = _objects_made_by(
		func() -> void:
			for _frame: int in 30:
				_layer._process(0.0)
	)
	assert_int(objects).is_equal(0)
	assert_int(bar.draws).is_equal(draws)  # The same load: no redraw.
	_carry(row, _capacity(FOSSIL) / 2 + 1)  # Within the same step.
	assert_int(bar.draws).is_equal(draws)
	_carry(row, _capacity(FOSSIL))
	assert_int(bar.draws).is_equal(draws + 1)


func test_steps_of_never_reads_a_load_as_empty_or_full_and_an_unknown_capacity_as_empty() -> void:
	assert_int(TankerCargo.steps_of(0, 500)).is_equal(0)
	assert_int(TankerCargo.steps_of(1, 500)).is_equal(1)
	assert_int(TankerCargo.steps_of(499, 500)).is_equal(TankerCargo.STEPS - 1)
	assert_int(TankerCargo.steps_of(500, 500)).is_equal(TankerCargo.STEPS)
	assert_int(TankerCargo.steps_of(900, 500)).is_equal(TankerCargo.STEPS)
	assert_int(TankerCargo.steps_of(50, 0)).is_equal(0)


func test_the_bar_leaves_the_sim_alone() -> void:
	var row: int = _spawn(FOSSIL, 8000)
	_carry(row, 100)
	var before: int = _runner.world.state_hash()
	_layer._process(0.0)
	assert_int(_runner.world.state_hash()).is_equal(before)


## A tanker of player 1 at x, y 12000, published.
func _spawn(type_id: StringName, x: int) -> int:
	var type: int = _runner.world.type_ids.find(type_id)
	_runner.world.add_unit(1, type, x, 12000)
	_runner.run_ticks(1)
	_layer._process(0.0)
	return _runner.snapshot.unit_count() - 1


## Sets the cargo of row `row` in the sim as the harvest rows would, publishes and draws a frame.
func _carry(row: int, cargo: int) -> void:
	_runner.world.cargo[row] = cargo
	_runner.run_ticks(1)
	_layer._process(0.0)


## Loses the last row, publishes and draws a frame.
func _lose(row: int) -> void:
	_runner.world.hp[row] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)


func _bar(row: int) -> TankerCargo:
	return (_layer.rig(row) as UnitLayer.Rig).cargo


func _capacity(type_id: StringName) -> int:
	var snap: MatchSnapshot = _runner.snapshot
	return snap.type_harvest[snap.type_ids.find(type_id)]


func _objects_made_by(step: Callable) -> int:
	var first: int = RefCounted.new().get_instance_id() >> 24
	step.call()
	return (RefCounted.new().get_instance_id() >> 24) - first - 1
