extends GdUnitTestSuite
## UnitLayer's rig pool (plan P114b, P84b's old acceptance): a unit that is lost leaves its rig in
## the pool and a unit that is produced takes a rig of its kind from it, so once the pool has warmed
## up to the most units alive at one time, producing and losing 200 units makes no new rig, no new
## sprite and no new ring. Allocations are counted, never timed: `rigs_made()` for the rigs, and the
## engine's instance counter for every object the layer makes in a call (the id of an object counts
## the objects made, so the objects between two probes are the ids between them).
## Waves of WAVE units, alternately light tanks (Shadow, Hull, Turret) and rifle squads (Shadow,
## Hull), are produced with `World.add_unit`, as the production does, and lost by hp 0. The sim's
## own objects (a snapshot a tick) are made outside the probes. The runner is paused and not in the
## tree: only the calls here move time.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const WAVE: int = 20
const WAVES: int = 10  ## 200 units after the warm-up wave.
const BASE: int = 2  ## The scenario's own units: a tank and a squad of player 1.
const TANK: StringName = &"light_tank"
const SQUAD: StringName = &"rifle_squad"

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: UnitLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	var spawns: Array[SpawnDef] = [Rig.spawn(1, "light_tank", 4, 4)]
	spawns.append(Rig.spawn(1, "rifle_squad", 6, 4))
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


func test_producing_and_losing_200_units_after_the_warm_up_makes_no_new_object() -> void:
	assert_int(_layer.rigs_made()).is_equal(BASE)
	var warm_up: int = _wave()  # A rig for each of WAVE units alive at once, and a ring for each.
	assert_int(warm_up).override_failure_message("the probe sees no object made").is_greater(WAVE)
	var made: int = _layer.rigs_made()
	assert_int(made).is_equal(BASE + WAVE)
	var objects: int = 0
	for _wave_number: int in WAVES:
		objects += _wave()
	assert_int(objects).override_failure_message("objects made by the layer").is_equal(0)
	assert_int(_layer.rigs_made()).is_equal(made)
	assert_int(_runner.snapshot.unit_count()).is_equal(BASE)  # All 200 were lost again.
	assert_int(_layer.rig_count()).is_equal(BASE)
	assert_int(_layer.world_sort.get_child_count()).is_equal(BASE)


func test_a_rig_comes_back_clean_for_the_next_unit_of_its_kind() -> void:
	_wave()
	# Selected and lost, so every rig of the pool has shown its ring.
	var ids: PackedInt32Array = _add_units(WAVE)
	_layer._process(0.0)
	_layer.set_selected(ids)
	assert_bool(_layer.is_ringed(BASE) and _layer.is_ringed(BASE + 1)).is_true()
	_lose_added()
	_layer._process(0.0)
	var made: int = _layer.rigs_made()
	var after: PackedInt32Array = _add_units(WAVE)
	_layer._process(0.0)
	assert_int(_layer.rigs_made()).is_equal(made)
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in range(BASE, BASE + WAVE):
		var rig: Node2D = _layer.rig(row)
		assert_int(snap.unit_id[row]).is_equal(after[row - BASE])
		assert_str(rig.name).is_equal("Unit%d" % snap.unit_id[row])
		assert_bool(_layer.is_ringed(row)).is_false()  # The ring waits, hidden, for a selection.
		assert_bool(rig.has_node("Ring") and rig.get_node("Ring").visible).is_false()
		assert_float(_layer.heading(row)).is_equal(0.0)
		assert_int(Frames.dir(_layer, row, &"hull")).is_equal(6)  # Facing east, d06.
		assert_bool(rig.visible and rig.is_inside_tree()).is_true()
		var at: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		assert_vector(rig.position).is_equal_approx(at, Vector2(0.001, 0.001))
	_layer.set_selected(after)  # A selection shows the ring the rig kept.
	assert_array(_ringed_rows()).is_equal(range(BASE, BASE + WAVE))
	assert_int(_layer.rigs_made()).is_equal(made)


func test_a_unit_takes_a_rig_of_its_own_kind_and_the_pool_misses_only_when_it_is_empty() -> void:
	_wave()
	var made: int = _layer.rigs_made()
	_add_units(WAVE)
	_layer._process(0.0)
	for row: int in range(BASE, BASE + WAVE):
		var names: Array = _layer.rig(row).get_children().map(
			func(n: Node) -> StringName: return n.name
		)
		var tank: bool = _type_of(row) == TANK
		assert_bool(names.has(&"Turret")).override_failure_message("row %d" % row).is_equal(tank)
		assert_bool(names.has(&"Hull") and names.has(&"Shadow")).is_true()
	assert_int(_layer.rigs_made()).is_equal(made)  # Both kinds were in the pool.
	_add_units(1)  # A tank more than the pool held: only that one is made.
	_layer._process(0.0)
	assert_int(_layer.rigs_made()).is_equal(made + 1)


func test_another_match_pools_every_rig_and_the_next_match_takes_them_back() -> void:
	_wave()
	var made: int = _layer.rigs_made()
	_add_units(WAVE)
	_layer._process(0.0)
	var before: Array[Node] = []
	for row: int in BASE + WAVE:
		before.append(_layer.rig(row))
	_runner.start()  # A new match, with the scenario's two units again.
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(BASE)
	assert_int(_layer.world_sort.get_child_count()).is_equal(BASE)
	assert_int(_layer.rigs_made()).is_equal(made)  # Both rows took a rig of the match that ended.
	for row: int in BASE:
		assert_bool(before.has(_layer.rig(row))).is_true()
		assert_str(_layer.rig(row).name).is_equal("Unit%d" % _runner.snapshot.unit_id[row])
	_add_units(WAVE)  # And the next 20 units take the rest of the pool, with none made.
	_layer._process(0.0)
	assert_int(_layer.rig_count()).is_equal(BASE + WAVE)
	assert_int(_layer.rigs_made()).is_equal(made)
	assert_int(_layer.world_sort.get_child_count()).is_equal(BASE + WAVE)


func test_the_pool_is_off_the_sort_and_hidden_and_the_tree_frees_it() -> void:
	_wave()
	var pool: Node = _layer.get_node("Pool")
	assert_bool((pool as Node2D).visible).is_false()
	assert_int(pool.get_child_count()).is_equal(WAVE)  # The rigs of the lost wave wait there.
	assert_int(_layer.world_sort.get_child_count()).is_equal(BASE)
	for rig: Node2D in pool.get_children():
		assert_bool(rig.is_visible_in_tree()).is_false()
	var waiting: Array[Node] = pool.get_children()
	_layer.free()  # The pooled rigs are children of the layer: nothing is left behind.
	assert_bool(waiting.all(func(n: Variant) -> bool: return not is_instance_valid(n))).is_true()


## One wave: WAVE units are produced and selected, then all are lost. The objects the layer made in
## the four calls that see them, selection included.
func _wave() -> int:
	var made: int = 0
	var ids: PackedInt32Array = _add_units(WAVE)
	made += _objects_made_by(
		func() -> void:
			_layer._process(0.0)
			_layer.set_selected(ids)
	)
	assert_int(_layer.rig_count()).is_equal(BASE + WAVE)
	_lose_added()
	made += _objects_made_by(func() -> void: _layer._process(0.0))
	assert_int(_layer.rig_count()).is_equal(BASE)
	return made


## Produces `count` units of player 1, alternately a tank and a squad, in one tick of the sim.
func _add_units(count: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	var types: Array[StringName] = [TANK, SQUAD]
	for index: int in count:
		var type: int = _runner.world.type_ids.find(types[index % 2])
		var x: int = 8000 + 700 * (index % 10)
		var y: int = 12000 + 900 * (index / 10)
		ids.append(_runner.world.add_unit(1, type, x, y))
	_runner.run_ticks(1)
	return ids


## Loses every unit after the scenario's own, in one tick of the sim.
func _lose_added() -> void:
	for row: int in range(BASE, _runner.world.unit_count()):
		_runner.world.hp[row] = 0
	_runner.run_ticks(1)


## The objects `step` makes: the ids made between two probes, less the second probe's own.
func _objects_made_by(step: Callable) -> int:
	var first: int = RefCounted.new().get_instance_id() >> 24
	step.call()
	return (RefCounted.new().get_instance_id() >> 24) - first - 1


func _type_of(row: int) -> StringName:
	var snap: MatchSnapshot = _runner.snapshot
	return snap.type_ids[snap.type_index[row]]


## The rows whose ring shows.
func _ringed_rows() -> Array[int]:
	var rows: Array[int] = []
	for row: int in _runner.snapshot.unit_count():
		if _layer.is_ringed(row):
			rows.append(row)
	return rows
