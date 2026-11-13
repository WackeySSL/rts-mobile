extends GdUnitTestSuite
## The eject of a dying ground carrier (plan row P289, ADR 0037 section 7). A carrier of a type with
## `type_carry_eject_percent` above 0 whose hp is 0 or less puts each squad aboard back as a row in
## the REMOVE mark (`Carry.perish`): the unload's ring walk, `max(1, hp * percent / 100)` hit
## points, order IDLE, an `UNLOADED` event. A squad with no cell, or one `insert_row` refuses, dies
## with the carrier and counts as lost. Worlds are `carry_rig.gd`'s: carrier 5 at (14500, 2500).

const Rig: GDScript = preload("res://tests/sim/support/carry_rig.gd")
const CARRIER: int = 5


func _loaded(percent: int, rock: Array = []) -> World:
	var world: World = Rig.world(Rig.REACH, 8, rock)
	world.type_carry_eject_percent[Rig.TRUCK] = percent
	world.hp[world.index_of(2)] = 60
	Rig.aboard(world, 1, CARRIER)
	Rig.aboard(world, 2, CARRIER)
	world.had_producer[1] = 1
	return world


func _kill_carrier(world: World) -> void:
	world.hp[world.index_of(CARRIER)] = 0
	Rig.step(world)


func _count(world: World, kind: int) -> int:
	var found: int = 0
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == kind:
			found += 1
		at += World.EVENT_STRIDE
	return found


func _fenced(open: Array[Vector2i]) -> Array:
	var rock: Array = []
	for x: int in range(11, 18):
		for y: int in 6:
			if Vector2i(x, y) != Vector2i(14, 2) and not open.has(Vector2i(x, y)):
				rock.append(Vector2i(x, y))
	return rock


func test_half_the_hp_survives_on_free_cells_with_unloaded_events() -> void:
	var world: World = _loaded(50)
	_kill_carrier(world)
	assert_int(world.pass_count).is_equal(0)
	assert_int(world.index_of(CARRIER)).is_equal(-1)
	var first: int = world.index_of(1)
	var second: int = world.index_of(2)
	assert_array([world.hp[first], world.hp[second]]).is_equal([50, 30])
	assert_array([world.order[first], world.order[second]]).is_equal(
		[World.Order.IDLE, World.Order.IDLE]
	)
	(
		assert_bool(
			(
				world.cell_of(world.pos_x[first], world.pos_y[first])
				!= world.cell_of(world.pos_x[second], world.pos_y[second])
			)
		)
		. is_true()
	)
	assert_int(_count(world, World.Event.UNLOADED)).is_equal(2)
	assert_int(world.stat_lost_units[1]).is_equal(1)  # The carrier only.


func test_a_tiny_hp_is_raised_to_one() -> void:
	var world: World = _loaded(50)
	world.pass_hp[1] = 1
	_kill_carrier(world)
	assert_int(world.hp[world.index_of(2)]).is_equal(1)


func test_zero_percent_keeps_the_rule_that_squads_die() -> void:
	var world: World = _loaded(0)
	_kill_carrier(world)
	assert_int(world.index_of(1)).is_equal(-1)
	assert_int(_count(world, World.Event.UNLOADED)).is_equal(0)
	assert_int(world.stat_lost_units[1]).is_equal(3)


func test_a_carrier_that_lives_ejects_nothing() -> void:
	var world: World = _loaded(50)
	Rig.step(world)
	assert_int(world.pass_count).is_equal(2)
	assert_int(_count(world, World.Event.UNLOADED)).is_equal(0)


func test_no_free_cell_kills_the_squads_as_lost() -> void:
	var world: World = _loaded(50, _fenced([]))
	_kill_carrier(world)
	assert_int(world.pass_count).is_equal(0)
	assert_int(world.index_of(1)).is_equal(-1)
	assert_int(_count(world, World.Event.UNLOADED)).is_equal(0)
	assert_int(world.stat_lost_units[1]).is_equal(3)


func test_one_free_cell_ejects_the_first_squad_and_the_second_dies() -> void:
	var world: World = _loaded(50, _fenced([Vector2i(15, 3)]))
	_kill_carrier(world)
	assert_int(world.hp[world.index_of(1)]).is_equal(50)
	assert_int(world.index_of(2)).is_equal(-1)
	assert_int(world.pass_count).is_equal(0)
	assert_int(world.stat_lost_units[1]).is_equal(2)  # The second squad and the carrier.


func test_a_row_refusal_kills_the_squad() -> void:
	var world: World = _loaded(50)
	world.max_rows = world.unit_id.size()
	_kill_carrier(world)
	assert_int(world.index_of(1)).is_equal(-1)
	assert_int(world.pass_count).is_equal(0)
	assert_int(world.stat_lost_units[1]).is_equal(3)


func test_the_eject_is_deterministic() -> void:
	var one: World = _loaded(50)
	var two: World = _loaded(50)
	_kill_carrier(one)
	_kill_carrier(two)
	assert_int(one.state_hash()).is_equal(two.state_hash())


func test_the_unloaded_record_and_the_new_row_are_complete() -> void:
	var world: World = _loaded(50)
	_kill_carrier(world)
	var records: Array = []
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == World.Event.UNLOADED:
			records.append(Array(world.events.slice(at, at + World.EVENT_STRIDE)))
		at += World.EVENT_STRIDE
	assert_array(records[0]).is_equal([6, 1, 15500, 1500, Rig.RIFLE, 1, CARRIER, 0])
	assert_array(records[1]).is_equal([6, 2, 15500, 2500, Rig.RIFLE, 1, CARRIER, 0])
	# The fog stamps a new row later in the same tick; right after `perish` it has none.
	var direct: World = _loaded(50)
	direct.hp[direct.index_of(CARRIER)] = 0
	Carry.perish(direct)
	assert_int(direct.fog_cell[direct.index_of(1)]).is_equal(-1)
	assert_int(direct.fog_cell[direct.index_of(2)]).is_equal(-1)


func test_a_hundred_percent_keeps_the_hp() -> void:
	var world: World = _loaded(100)
	_kill_carrier(world)
	assert_array([world.hp[world.index_of(1)], world.hp[world.index_of(2)]]).is_equal([100, 60])


func test_the_unit_cap_count_is_unchanged_by_an_eject_and_drops_by_the_losses() -> void:
	var placed: World = _loaded(50)
	var before: int = ProductionSpawn.mobile_rows(placed, 1)
	_kill_carrier(placed)
	assert_int(ProductionSpawn.mobile_rows(placed, 1)).is_equal(before - 1)  # Only the carrier.
	var fenced: World = _loaded(50, _fenced([]))
	var start: int = ProductionSpawn.mobile_rows(fenced, 1)
	_kill_carrier(fenced)
	assert_int(ProductionSpawn.mobile_rows(fenced, 1)).is_equal(start - 3)  # Carrier, two squads.


func test_a_carrier_in_unload_mode_that_dies_ejects_at_its_percent() -> void:
	var world: World = _loaded(50)
	world.carry_mode[world.index_of(CARRIER)] = 1
	_kill_carrier(world)
	assert_array([world.hp[world.index_of(1)], world.hp[world.index_of(2)]]).is_equal([50, 30])
	assert_int(_count(world, World.Event.UNLOADED)).is_equal(2)


func test_two_carriers_dying_on_one_tick_each_eject_their_own_squads() -> void:
	var world: World = _loaded(50)
	world.type_carry_eject_percent[Rig.TRUCK] = 50
	world.add_unit(1, Rig.TRUCK, 4500, 4500)  # Carrier 7.
	Rig.aboard(world, 3, 7)
	world.hp[world.index_of(CARRIER)] = 0
	world.hp[world.index_of(7)] = 0
	Rig.step(world)
	assert_int(world.pass_count).is_equal(0)
	for id: int in [1, 2, 3]:
		assert_bool(world.index_of(id) >= 0).override_failure_message("squad %d" % id).is_true()
	assert_int(world.hp[world.index_of(3)]).is_equal(50)
	assert_int(world.pos_x[world.index_of(3)] / 1000).is_less(6)  # Round carrier 7.
	var carriers: Array = []
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == World.Event.UNLOADED:
			carriers.append(world.events[at + 6])
		at += World.EVENT_STRIDE
	assert_array(carriers).is_equal([CARRIER, CARRIER, 7])
