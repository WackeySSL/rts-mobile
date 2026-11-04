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
	var before: Vector2 = _scar(HEAVY).get_global_transform().origin
	var writes: int = _layer.life_writes()
	# The recoil path: the rock moves the Hull by one write and nothing else.
	_layer._apply_kick(_row(HEAVY), Vector2.ZERO, Vector2(1.0, 0.5))
	assert_int(_layer.life_writes() - writes).is_equal(1)
	assert_that(_scar(HEAVY).position).is_equal(scar)
	assert_that(_loose(HEAVY).position).is_equal(loose)
	assert_bool(before != _scar(HEAVY).get_global_transform().origin).is_true()


func test_a_crowd_dropped_to_forty_percent_is_applied_in_eight_frames_and_never_past_forty(
) -> void:
	var type: int = _runner.world.type_ids.find(&"light_tank")
	var ids: PackedInt32Array = PackedInt32Array()
	for index: int in CROWD:
		var at: Vector2i = Vector2i(6000 + 300 * (index % 20), 10000 + 600 * (index / 20))
		ids.append(_runner.world.add_unit(1, type, at.x, at.y))
	_runner.run_ticks(1)
	_layer._process(0.0)
	for id: int in ids:
		_set_hp(id, 40)
	_runner.run_ticks(1)
	var spent: Array[int] = []
	for _frame: int in 8:
		var writes: int = _layer.life_writes()
		_layer._process(0.0)
		spent.append(_layer.life_writes() - writes)
	# 13 changes of 3 writes a frame (39 of the share of 40) seven times, then the last 9.
	assert_array(spent).is_equal([39, 39, 39, 39, 39, 39, 39, 27])
	for id: int in ids:
		assert_bool(_scar(id).visible).is_true()


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
	for index: int in 2:
		movers.append(_runner.world.add_unit(1, type, 6000 + 800 * index, 14000))
	_runner.run_ticks(1)
	_layer._process(0.0)
	for id: int in movers:
		_set_hp(id, 40)
	_runner.run_ticks(1)
	for _frame: int in 3:
		_layer._process(0.0)
	assert_int(_layer._damage_queue.size()).is_equal(0)
	var late: PackedInt32Array = PackedInt32Array()
	for index: int in 5:
		late.append(_runner.world.add_unit(1, type, 6000 + 800 * index, 16000))
	_runner.run_ticks(1)
	_layer._process(0.0)
	for id: int in late:
		_set_hp(id, 40)
	_runner.run_ticks(1)
	_layer._sync_rigs()
	var writes: int = _layer.life_writes()
	for id: int in movers:  # Four hulls change frame: four follow writes, six left.
		_turn(id, 2)
	_layer._process(0.0)
	# Two changes of 3 fit exactly (6 of 6; a third finds none left): 4 follow + 6 = 10.
	assert_int(_layer.life_writes() - writes).is_equal(4 + 6)
	assert_bool(_scar(late[1]).visible and not _scar(late[2]).visible).is_true()
	writes = _layer.life_writes()
	_layer._process(0.0)  # Nothing follows now: the whole share, three changes, 9 writes.
	assert_int(_layer.life_writes() - writes).is_equal(9)
	assert_bool(_scar(late[4]).visible).is_true()


func test_a_hidden_stage_two_enemy_that_turns_writes_nothing_and_is_placed_when_seen() -> void:
	Rig.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	_layer._process(0.0)
	_set_hp(ENEMY, 10)
	_runner.run_ticks(1)
	Rig.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	_layer._process(0.0)
	assert_int(_rig(ENEMY).damage.shown).is_equal(2)
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	var writes: int = _layer.life_writes()
	for dir: int in range(0, 8):
		_turn(ENEMY, dir)
	_layer._process(0.0)
	assert_int(_layer.life_writes()).is_equal(writes)
	Rig.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	_layer._process(0.0)
	assert_int(_layer.life_writes() - writes).is_equal(7)  # The stage of now, positions with it.
	var sheet: IsoSheetDef = _sheet(ENEMY)
	var texels: Vector2 = _layer.world_sort.texels(sheet, &"hull")
	var point: Vector2 = sheet.emitter_point(sheet.emitters.find("damage"), 7)
	assert_vector(_scar(ENEMY).position).is_equal_approx(point * texels, Vector2(0.001, 0.001))
	var hang: Vector2 = sheet.emitter_point(sheet.emitters.find("hang"), 7)
	assert_vector(_loose(ENEMY).position).is_equal_approx(hang * texels, Vector2(0.001, 0.001))
	assert_bool(_loose(ENEMY).scale.x < 0.0).is_equal(hang.x < 0.0)


func test_the_vehicles_share_of_the_write_budget_fits_the_dearest_change() -> void:
	var share: int = _life.damage_writes_per_frame - _life.damage_building_writes
	assert_int(share).is_greater_equal(VehicleDamage.cost(0, 2, true))  # The queue never stalls.


func test_reduced_effects_keep_the_overlays() -> void:
	_life.reduced = true
	var writes: int = _layer.life_writes()
	_hit(LIGHT, 10)
	assert_bool(_scar(LIGHT).visible and _loose(LIGHT).visible).is_true()
	assert_int(_layer.life_writes() - writes).is_equal(7)


func test_a_vehicle_that_dies_while_queued_leaves_the_queue() -> void:
	Rig.see(_runner.snapshot, 1, [Vector2i(28, 28)])
	_layer._process(0.0)
	_life.damage_writes_per_frame = _life.damage_building_writes  # A share of 0: it waits.
	_set_hp(LIGHT, 40)
	_runner.run_ticks(1)
	_layer._process(0.0)
	var rig: UnitLayer.Rig = _rig(LIGHT)
	assert_array(_layer._damage_queue).is_equal([rig])
	_kill(LIGHT)
	assert_int(_layer._damage_queue.size()).is_equal(0)
	assert_bool(rig.damage.queued).is_false()


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
