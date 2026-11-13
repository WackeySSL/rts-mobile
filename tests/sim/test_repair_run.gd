extends GdUnitTestSuite
## `Repair.run` (plan row P276, ADR 0037 sections 5 and 6): the ground repair buildings and the
## medics. The rig's types are its own (the shipped repair data arrives with P278): a shed (2 x 2,
## classes 6 = WHEELED and TRACKED, 30 hp per 15 ticks, reach 2700, 2 slots, 25 percent), a medic
## (FOOT only, unarmed, 6 hp per 15 ticks, reach 1500, 1 slot, free, seek 4000), a tank (100 hp,
## costs 100, TRACKED) and a squad (100 hp, FOOT).

const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")
const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const SHED: Vector2i = Vector2i(2, 2)  # Its footprint centre is (3000, 3000).


func _unit(id: String, move_class: int, speed: int) -> UnitDef:
	var def: UnitDef = Rig.unit(StringName(id), 6000, 5000, 0, 0, [])
	def.move_class = move_class
	def.speed = speed
	def.cost = 100
	return def


func _world() -> World:
	var shed: BuildingDef = BuildingDef.new()
	shed.type_id = &"shed"
	shed.max_hp = 1000
	shed.armour = World.Armour.BUILDING
	shed.footprint = Vector2i(2, 2)
	shed.sight_range = 4000
	shed.repair_classes = 6
	shed.repair_hp = 30
	shed.repair_period_ticks = 15
	shed.repair_cost_percent = 25
	shed.repair_reach_milli = 2700
	shed.repair_slots = 2
	var hq: BuildingDef = BuildingDef.new()
	hq.type_id = &"hq"
	hq.max_hp = 1000
	hq.armour = World.Armour.BUILDING
	hq.footprint = Vector2i(3, 3)
	hq.sight_range = 4000
	var medic: UnitDef = _unit("medic", World.MoveClass.FOOT, 67)
	medic.repair_classes = 1
	medic.repair_hp = 6
	medic.repair_period_ticks = 15
	medic.repair_cost_percent = 0
	medic.repair_reach_milli = 1500
	medic.repair_slots = 1
	medic.repair_seek_milli = 4000
	var units: Array[UnitDef] = [
		shed,
		hq,
		medic,
		_unit("tank", World.MoveClass.TRACKED, 67),
		_unit("squad", 0, 67),
		_unit("drone", World.MoveClass.AIR, 67)
	]
	var made: World = Rig.world_of(units, 24, 16, true, 2)
	made.add_building(1, Worlds.type_of(made, "shed"), SHED.x, SHED.y)
	made.add_building(1, Worlds.type_of(made, "hq"), 10, 10)
	made.add_building(2, Worlds.type_of(made, "hq"), 20, 12)
	made.credits[1] = 1000
	return made


func _add(world: World, player: int, id: String, x: int, y: int, hp: int = 100) -> int:
	var row: int = Worlds.add(world, player, id, x, y)
	world.hp[row] = hp
	return row


func _step(world: World, ticks: int = 1) -> void:
	for _tick: int in ticks:
		Worlds.step(world)


func _repaired(world: World) -> Array[PackedInt32Array]:
	var found: Array[PackedInt32Array] = []
	var at: int = 0
	while at < world.events.size():
		if world.events[at] == World.Event.REPAIRED:
			found.append(world.events.slice(at, at + World.EVENT_STRIDE))
		at += World.EVENT_STRIDE
	return found


func test_a_shed_repairs_a_hurt_tank_in_reach_on_its_turn_and_writes_repaired() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 4000, 3000, 50)
	_step(world)
	assert_int(world.hp[tank]).is_equal(80)  # Rank 0 acts at tick 0: +30.
	assert_int(world.credits[1]).is_equal(1000 - 8)  # ceil(100 * 30 * 25 / (100 * 100)) = 8.
	var events: Array[PackedInt32Array] = _repaired(world)
	assert_int(events.size()).is_equal(1)
	var shed_id: int = world.unit_id[world.repair_rows[0]]
	assert_array(events[0]).is_equal(
		[World.Event.REPAIRED, shed_id, 4000, 3000, world.unit_id[tank], 1, 30, 0]
	)
	_step(world, 14)
	assert_int(world.hp[tank]).is_equal(80)
	_step(world)
	assert_int(world.hp[tank]).is_equal(100)  # Tick 15: 20 of 30, not above the maximum.
	assert_int(world.credits[1]).is_equal(1000 - 8 - 5)


func test_the_slots_serve_the_most_hurt_share_first_then_the_lowest_id() -> void:
	var world: World = _world()
	var a: int = _add(world, 1, "tank", 4000, 3000, 60)
	var b: int = _add(world, 1, "tank", 4000, 3500, 30)
	var c: int = _add(world, 1, "tank", 4000, 2500, 60)
	var d: int = _add(world, 1, "tank", 3500, 4000, 60)
	_step(world)
	assert_int(_repaired(world).size()).is_equal(2)  # At most `repair_slots` records.
	assert_array([world.hp[a], world.hp[b], world.hp[c], world.hp[d]]).is_equal([90, 60, 60, 60])
	_step(world, 15)
	# Tick 15: b, c and d tie at 60 (a is at 90); the lowest two ids, b and c, are served.
	assert_array([world.hp[a], world.hp[b], world.hp[c], world.hp[d]]).is_equal([90, 90, 90, 60])


func test_rows_out_of_reach_unserved_classes_enemies_and_full_rows_are_left_alone() -> void:
	var world: World = _world()
	var far: int = _add(world, 1, "tank", 6000, 3000, 50)  # 3000 from the centre: past 2700.
	var squad: int = _add(world, 1, "squad", 3500, 3000, 50)
	var foe: int = _add(world, 2, "tank", 3500, 3500, 50)
	var full: int = _add(world, 1, "tank", 3500, 2500, 100)
	_step(world)
	assert_array([world.hp[far], world.hp[squad], world.hp[foe], world.hp[full]]).is_equal(
		[50, 50, 50, 100]
	)
	assert_int(world.credits[1]).is_equal(1000)
	assert_int(_repaired(world).size()).is_equal(0)


func test_reach_is_measured_from_the_footprint_centre() -> void:
	var world: World = _world()
	var inside: int = _add(world, 1, "tank", 3000, 5700, 50)  # 2700 below the centre.
	var outside: int = _add(world, 1, "tank", 5701, 3000, 50)  # 2701 to its right.
	_step(world)
	assert_array([world.hp[inside], world.hp[outside]]).is_equal([80, 50])


func test_a_row_it_cannot_pay_for_is_skipped_and_the_next_one_is_served() -> void:
	var world: World = _world()
	var dear: int = _add(world, 1, "tank", 4000, 3000, 10)
	var cheap: int = _add(world, 1, "tank", 4000, 3500, 50)
	world.type_cost[world.type_index[dear]] = 100000
	world.type_cost[world.type_index[cheap]] = 100000
	world.credits[1] = 5
	_step(world)
	assert_array([world.hp[dear], world.hp[cheap], world.credits[1]]).is_equal([10, 50, 5])
	assert_int(_repaired(world).size()).is_equal(0)


func test_a_blackout_an_unfinished_shed_and_a_defeated_owner_stop_it() -> void:
	var blacked: World = _world()
	var tank: int = _add(blacked, 1, "tank", 4000, 3000, 50)
	Buildings.rebuild_lists(blacked)
	blacked.offline_until[blacked.repair_rows[0]] = blacked.tick + 1000
	_step(blacked)
	assert_int(blacked.hp[tank]).is_equal(50)
	var unfinished: World = _world()
	tank = _add(unfinished, 1, "tank", 4000, 3000, 50)
	Buildings.rebuild_lists(unfinished)
	unfinished.build_left[unfinished.repair_rows[0]] = 10
	_step(unfinished)
	assert_int(unfinished.hp[tank]).is_equal(50)
	var beaten: World = _world()
	tank = _add(beaten, 1, "tank", 4000, 3000, 50)
	beaten.defeated_tick[1] = 5
	_step(beaten)
	assert_int(beaten.hp[tank]).is_equal(50)


func test_repairers_act_staggered_by_rank_with_one_scan_each() -> void:
	var world: World = _world()
	world.add_building(1, Worlds.type_of(world, "shed"), 2, 6)  # Centre (3000, 7000).
	var tank: int = _add(world, 1, "tank", 4000, 5000, 50)  # In reach of both (2236, 2236).
	var rows: int = world.unit_count()
	_step(world)  # Tick 0: rank 0 only.
	assert_int(world.hp[tank]).is_equal(80)
	assert_int(world.stats[World.Stat.REPAIR_CHECKS]).is_equal(rows)
	_step(world)  # Tick 1: rank 1 only.
	assert_int(world.hp[tank]).is_equal(100)
	assert_int(world.stats[World.Stat.REPAIR_CHECKS]).is_equal(rows)
	_step(world)  # Tick 2: nobody acts, nothing is scanned.
	assert_int(world.stats[World.Stat.REPAIR_CHECKS]).is_equal(0)


func test_repair_rows_are_the_roles_without_pads_in_row_order() -> void:
	var world: World = _world()
	_add(world, 1, "medic", 8000, 8000)
	_step(world)
	assert_array(world.repair_rows).is_equal([0, 3])
	var padded: World = Worlds.world()
	_step(padded)
	assert_array(padded.repair_rows).is_empty()


func test_a_medic_heals_a_hurt_squad_in_reach_for_free_and_never_a_vehicle_or_itself() -> void:
	var world: World = _world()
	var medic: int = _add(world, 1, "medic", 12000, 3000, 40)
	var squad: int = _add(world, 1, "squad", 12500, 3000, 50)
	var tank: int = _add(world, 1, "tank", 12500, 3500, 50)
	world.type_max_hp[world.type_index[medic]] = 100
	_step(world, 2)
	assert_array([world.hp[squad], world.hp[tank], world.hp[medic]]).is_equal([56, 50, 40])
	assert_int(world.credits[1]).is_equal(1000)
	assert_int(world.order[medic]).is_equal(World.Order.IDLE)


func test_an_idle_medic_walks_to_the_most_hurt_squad_in_seek_reach_and_a_busy_one_does_not(
) -> void:
	var world: World = _world()
	var medic: int = _add(world, 1, "medic", 12000, 3000)
	_add(world, 1, "squad", 14000, 3000, 80)
	var worse: int = _add(world, 1, "squad", 15500, 3000, 40)
	_add(world, 1, "squad", 17000, 3000, 10)  # 5000 away: past the seek reach of 4000.
	_step(world, 2)  # The medic is rank 1 after the shed: its turn is tick 1.
	assert_int(world.order[medic]).is_equal(World.Order.MOVE)
	assert_int(world.pos_x[worse]).is_equal(15500)
	assert_bool(world.goal_x[medic] > 14500).is_true()  # Its slot is around the most hurt one.
	var busy: World = _world()
	medic = _add(busy, 1, "medic", 12000, 3000)
	_add(busy, 1, "squad", 14000, 3000, 40)
	var sent: PackedInt32Array = PackedInt32Array([busy.unit_id[medic]])
	Worlds.step(busy, [Command.move(1, sent, 21000, 3000)])
	_step(busy)
	assert_int(busy.order[medic]).is_equal(World.Order.MOVE)
	assert_int(busy.goal_x[medic]).is_greater(20000)  # Its own goal, not the squad's.


func test_a_medic_with_a_hurt_squad_in_reach_stays_where_it_is() -> void:
	var world: World = _world()
	var medic: int = _add(world, 1, "medic", 12000, 3000)
	_add(world, 1, "squad", 12500, 3000, 90)
	_add(world, 1, "squad", 15000, 3000, 10)
	_step(world, 2)
	assert_int(world.order[medic]).is_equal(World.Order.IDLE)


func test_the_airfield_writes_repaired_once_per_pad_per_period() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add_homed(world, "jet", Worlds.FIELD)
	world.hp[jet] = 50
	world.credits[1] = 1000
	_step(world)
	var events: Array[PackedInt32Array] = _repaired(world)
	assert_int(events.size()).is_equal(1)
	assert_array(events[0]).is_equal(
		[
			World.Event.REPAIRED,
			Worlds.FIELD,
			world.pos_x[jet],
			world.pos_y[jet],
			world.unit_id[jet],
			1,
			10,
			0
		]
	)
	_step(world)
	assert_int(_repaired(world).size()).is_equal(0)


func test_a_medic_leaves_buildings_alone_and_a_building_never_takes_a_squads_slot() -> void:
	var world: World = _world()
	var medic: int = _add(world, 1, "medic", 11000, 11500)
	var hq: int = world.index_of(2)  # Player 1's headquarters (id 2) at tile (10, 10).
	world.hp[hq] = 100
	var squad: int = _add(world, 1, "squad", 11500, 10500, 50)
	_step(world, 2)
	assert_int(world.hp[hq]).is_equal(100)
	assert_int(world.hp[squad]).is_equal(56)  # The one slot goes to the squad, not the building.
	var alone: World = _world()
	medic = _add(alone, 1, "medic", 4500, 3000)
	var shed: int = alone.index_of(1)
	alone.hp[shed] = 500
	alone.hp[alone.index_of(2)] = 100
	_step(alone, 2)
	assert_array([alone.hp[shed], alone.hp[alone.index_of(2)]]).is_equal([500, 100])
	assert_int(alone.order[medic]).is_equal(World.Order.IDLE)  # No seek to a building either.


func test_a_medic_never_heals_an_air_squad() -> void:
	var world: World = _world()
	_add(world, 1, "medic", 12000, 3000)
	var drone: int = _add(world, 1, "drone", 12500, 3000, 50)
	_step(world, 2)
	assert_int(world.hp[drone]).is_equal(50)


func test_a_medic_with_a_pending_order_target_does_not_seek() -> void:
	var world: World = _world()
	var medic: int = _add(world, 1, "medic", 12000, 3000)
	_add(world, 1, "squad", 14000, 3000, 40)
	world.order_target[medic] = 99  # A LOAD mark: the medic waits for its carrier.
	_step(world, 2)
	assert_int(world.order[medic]).is_equal(World.Order.IDLE)


func test_a_row_that_moved_this_tick_is_judged_at_its_new_place() -> void:
	var world: World = _world()
	var tank: int = _add(world, 1, "tank", 5750, 3000, 50)  # 2750 out: past the reach of 2700.
	var sent: PackedInt32Array = PackedInt32Array([world.unit_id[tank]])
	Worlds.step(world, [Command.move(1, sent, 3000, 3000)])
	assert_bool(world.pos_x[tank] < 5700).is_true()
	assert_int(world.hp[tank]).is_equal(80)
