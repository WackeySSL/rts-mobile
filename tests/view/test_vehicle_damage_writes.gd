extends "res://tests/view/support/vehicle_damage_suite.gd"
## The writes of the vehicle overlays (plan P161, ADR 0028 section 8): the follow writes of a hull
## frame change, the flip at a side switch, the stage queue in the vehicles' share and a recoil rock
## that costs the overlays nothing. Fixtures: support/vehicle_damage_suite.gd.

const CROWD: int = 100


func test_a_hull_frame_change_writes_one_position_at_stage_one_and_two_at_stage_two() -> void:
	_hit(LIGHT, 40)
	var right: int = _dir_on(LIGHT, true)
	_turn(LIGHT, right)
	var writes: int = _layer.life_writes()
	var at: Vector2 = _scar(LIGHT).position
	_turn(LIGHT, (right + 1) % UnitLayer.DIRECTIONS)
	assert_int(_layer.life_writes() - writes).is_equal(1)
	var sheet: IsoSheetDef = _sheet(LIGHT)
	var texels: Vector2 = _layer.world_sort.texels(sheet, &"hull")
	var point: Vector2 = sheet.emitter_point(sheet.emitters.find("damage"), _rig(LIGHT).damage.dir)
	assert_vector(_scar(LIGHT).position).is_equal_approx(point * texels, Vector2(0.001, 0.001))
	assert_bool(at != _scar(LIGHT).position).is_true()
	_hit(LIGHT, 10)
	writes = _layer.life_writes()
	_turn(LIGHT, (right + 2) % UnitLayer.DIRECTIONS)
	assert_int(_layer.life_writes() - writes).is_equal(2 + _flips(LIGHT, right + 1, right + 2))


func test_the_flip_is_one_write_only_when_the_hang_point_changes_side() -> void:
	_hit(HEAVY, 10)
	var right: int = _dir_on(HEAVY, true)
	var left: int = _dir_on(HEAVY, false)
	_turn(HEAVY, right)
	var writes: int = _layer.life_writes()
	_turn(HEAVY, left)
	assert_int(_layer.life_writes() - writes).is_equal(3)  # Two positions and the flip.
	assert_float(_loose(HEAVY).scale.x).is_less(0.0)
	writes = _layer.life_writes()
	_turn(HEAVY, right)
	assert_int(_layer.life_writes() - writes).is_equal(3)
	assert_float(_loose(HEAVY).scale.x).is_greater(0.0)
	# A full turn crosses the side four times (ADR 0028 section 8's note), 16 + 4 writes at stage 2.
	writes = _layer.life_writes()
	for step: int in range(1, UnitLayer.DIRECTIONS + 1):
		_turn(HEAVY, (right + step) % UnitLayer.DIRECTIONS)
	assert_int(_layer.life_writes() - writes).is_equal(2 * UnitLayer.DIRECTIONS + 4)


func test_loose_off_drops_its_position_and_flip_writes() -> void:
	_hit(HEAVY, 10)
	_life.damage_loose = false
	var right: int = _dir_on(HEAVY, true)
	_turn(HEAVY, right)
	var writes: int = _layer.life_writes()
	_turn(HEAVY, _dir_on(HEAVY, false))
	assert_int(_layer.life_writes() - writes).is_equal(1)


func test_an_intact_vehicle_writes_nothing_when_it_turns() -> void:
	var writes: int = _layer.life_writes()
	_turn(LIGHT, 0)
	_turn(LIGHT, 3)
	assert_int(_layer.life_writes()).is_equal(writes)


func test_a_hull_rock_moves_the_overlays_with_the_hull_and_writes_none_to_them() -> void:
	_hit(HEAVY, 10)
	var scar: Vector2 = _scar(HEAVY).position
	var loose: Vector2 = _loose(HEAVY).position
	var hull: Sprite2D = _rig(HEAVY).sprites[UnitLayer.HULL]
	var writes: int = _layer.life_writes()
	hull.position = Vector2(1.0, 0.5)  # What a rock or a rumble does.
	assert_that(_scar(HEAVY).position).is_equal(scar)
	assert_that(_loose(HEAVY).position).is_equal(loose)
	assert_int(_layer.life_writes()).is_equal(writes)
	var moved: Vector2 = _scar(HEAVY).get_global_transform().origin
	hull.position = Vector2.ZERO
	assert_bool(moved != _scar(HEAVY).get_global_transform().origin).is_true()


func test_a_crowd_dropped_to_forty_percent_is_applied_in_eight_frames_and_never_past_forty(
) -> void:
	var type: int = _runner.world.type_ids.find(&"light_tank")
	var ids: PackedInt32Array = PackedInt32Array()
	for index: int in CROWD:
		ids.append(
			_runner.world.add_unit(1, type, 6000 + 300 * (index % 20), 10000 + 600 * (index / 20))
		)
	_runner.run_ticks(1)
	_layer._process(0.0)
	for id: int in ids:
		_set_hp(id, 40)
	_runner.run_ticks(1)
	var frames: int = 0
	var share: int = _life.damage_writes_per_frame - _life.damage_building_writes
	var done: int = 0
	while done < CROWD and frames < 20:
		var writes: int = _layer.life_writes()
		_layer._process(0.0)
		var spent: int = _layer.life_writes() - writes
		assert_int(spent).is_less_equal(share)
		frames += 1
		done = 0
		for id: int in ids:
			done += 1 if _scar(id).visible else 0
	assert_int(frames).is_equal(8)
	assert_int(done).is_equal(CROWD)


func test_the_queue_is_oldest_first() -> void:
	var type: int = _runner.world.type_ids.find(&"light_tank")
	var ids: PackedInt32Array = PackedInt32Array()
	for index: int in 30:
		ids.append(_runner.world.add_unit(1, type, 6000 + 300 * index, 12000))
	_runner.run_ticks(1)
	_layer._process(0.0)
	for id: int in ids:
		_set_hp(id, 40)
	_runner.run_ticks(1)
	_layer._process(0.0)  # 13 of the 30, in row order.
	var seen: int = 0
	for id: int in ids:
		seen += 1 if _scar(id).visible else 0
	assert_int(seen).is_equal(13)
	for index: int in 13:
		assert_bool(_scar(ids[index]).visible).is_true()
	assert_bool(_scar(ids[13]).visible).is_false()


func test_the_follow_writes_come_first_and_the_queue_takes_what_is_left() -> void:
	_life.damage_writes_per_frame = _life.damage_building_writes + 10  # A share of 10.
	var type: int = _runner.world.type_ids.find(&"light_tank")
	var movers: PackedInt32Array = PackedInt32Array([LIGHT, HEAVY])
	for index: int in 4:
		movers.append(_runner.world.add_unit(1, type, 6000 + 800 * index, 14000))
	_runner.run_ticks(1)
	_layer._process(0.0)
	for id: int in movers:
		_hit(id, 40)
	for _frame: int in 3:
		_layer._process(0.0)
	assert_int(_layer._damage_queue.size()).is_equal(0)
	var late: PackedInt32Array = PackedInt32Array()
	for index: int in 2:
		late.append(_runner.world.add_unit(1, type, 6000 + 800 * index, 16000))
	_runner.run_ticks(1)
	_layer._process(0.0)
	for id: int in late:
		_set_hp(id, 40)
	_runner.run_ticks(1)
	_layer._sync_rigs()
	for id: int in movers:  # Six hulls change frame: six follow writes, four left, one change of 3.
		_turn(id, 2)
	var writes: int = _layer.life_writes()
	_layer._process(0.0)
	assert_int(_layer.life_writes() - writes).is_equal(3)
	assert_bool(_scar(late[0]).visible).is_true()
	assert_bool(_scar(late[1]).visible).is_false()
	_layer._process(0.0)  # Nothing follows now: the second one is written.
	assert_bool(_scar(late[1]).visible).is_true()


## The flips between hull frames `from` and `to` (mod 16) of unit `id`, a frame at a time.
func _flips(id: int, from: int, to: int) -> int:
	var sheet: IsoSheetDef = _sheet(id)
	var at: int = sheet.emitters.find("hang")
	var count: int = 0
	for dir: int in range(from, to):
		var a: float = sheet.emitter_point(at, dir % UnitLayer.DIRECTIONS).x
		var b: float = sheet.emitter_point(at, (dir + 1) % UnitLayer.DIRECTIONS).x
		count += 1 if (a < 0.0) != (b < 0.0) else 0
	return count
