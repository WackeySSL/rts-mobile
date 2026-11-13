extends GdUnitTestSuite
## Airfield rules (plan row P241, ADR 0036 section 6): the FLIGHT cap at QUEUE, the spawn over a
## free pad with the airfield as `home`, ammo in `Combat.fire`, re-homing, and the derived
## `air_rows`. The worlds are `air_worlds.gd`'s (one airfield with two pads, a jet with 3 shots).
## The return and the reload are in test_airfield_return.gd.

const Worlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const FLIGHT: int = World.Tab.FLIGHT
const SHOT: int = Combat.SHOT


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


func _queue_count(world: World, player: int = 1) -> int:
	return world.queue_count[player * World.TABS + FLIGHT]


func _aircraft(world: World) -> Array[int]:
	var found: Array[int] = []
	for row: int in world.unit_id.size():
		if world.type_layer_bit[world.type_index[row]] == World.Layer.AIR:
			found.append(row)
	return found


## ATTACK_MOVE with the goal where the row stands, so that it does not fly away.
func _hold(world: World, row: int) -> void:
	world.order[row] = World.Order.ATTACK_MOVE
	world.goal_x[row] = world.pos_x[row]
	world.goal_y[row] = world.pos_y[row]


func test_air_rows_are_the_aircraft_ascending_and_a_derived_array() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add(world, 1, "jet", 9000, 9000)
	var drone: int = Worlds.add(world, 1, "drone", 9000, 9500)
	var fighter: int = Worlds.add(world, 2, "fighter", 15000, 9000)
	Worlds.step(world)
	assert_array(Array(world.air_rows)).is_equal([jet, fighter])
	assert_bool(Array(world.air_rows).has(drone)).is_false()
	assert_array(World.DERIVED_ARRAYS).contains([&"air_rows"])
	assert_array(MatchSnapshot.NOT_COPIED).contains([&"air_rows"])
	# A row that dies leaves the list at the next rebuild.
	world.hp[jet] = 0
	Worlds.step(world)
	assert_array(Array(world.air_rows)).is_equal([_aircraft(world)[0]])


func test_a_spawned_aircraft_joins_air_rows() -> void:
	var world: World = Worlds.world()
	Worlds.step(world, [Worlds.queue(world, "jet")])
	Worlds.run(world, Worlds.BUILD + 2)
	var found: Array[int] = _aircraft(world)
	assert_int(found.size()).is_equal(1)
	assert_array(Array(world.air_rows)).is_equal(found)


func test_the_flight_queue_is_capped_by_the_pads_of_the_complete_airfields() -> void:
	var world: World = Worlds.world()
	Worlds.step(world, [Worlds.queue(world, "jet"), Worlds.queue(world, "jet")])
	assert_int(_queue_count(world)).is_equal(2)
	Worlds.step(world, [Worlds.queue(world, "jet")])
	assert_array([_queue_count(world), world.dropped_commands]).is_equal([2, 1])
	assert_int(world.credits[1]).is_equal(world.start_credits - 200)
	# Aircraft alive count like queued ones: after both spawn the queue is empty and still full.
	Worlds.run(world, 2 * Worlds.BUILD + 4)
	assert_int(_queue_count(world)).is_equal(0)
	assert_int(_aircraft(world).size()).is_equal(2)
	Worlds.step(world, [Worlds.queue(world, "jet")])
	assert_int(world.dropped_commands).is_equal(2)
	assert_int(_queue_count(world)).is_equal(0)


func test_a_drone_squad_is_no_aircraft_for_the_cap_and_a_second_airfield_adds_pads() -> void:
	var world: World = Worlds.world(true)
	Worlds.add(world, 1, "drone", 9000, 9000)
	for _i: int in 4:
		Worlds.step(world, [Worlds.queue(world, "jet")])
	assert_array([_queue_count(world), world.dropped_commands]).is_equal([4, 0])
	Worlds.step(world, [Worlds.queue(world, "jet")])
	assert_array([_queue_count(world), world.dropped_commands]).is_equal([4, 1])


func test_an_incomplete_airfield_adds_no_pads_to_the_cap() -> void:
	var world: World = Worlds.world(true)
	var site: int = world.add_building(1, Worlds.type_of(world, "field"), 14, 2)
	world.build_left[world.index_of(site)] = 500
	for _i: int in 4:
		Worlds.step(world, [Worlds.queue(world, "jet")])
	assert_array([_queue_count(world), world.dropped_commands]).is_equal([4, 0])
	Worlds.step(world, [Worlds.queue(world, "jet")])
	assert_array([_queue_count(world), world.dropped_commands]).is_equal([4, 1])


func test_a_site_is_no_airfield_for_the_cap() -> void:
	var world: World = Worlds.world()
	world.build_left[world.index_of(Worlds.FIELD)] = 500
	Worlds.step(world, [Worlds.queue(world, "jet")])
	assert_array([_queue_count(world), world.dropped_commands]).is_equal([0, 1])


func test_a_finished_aircraft_spawns_over_the_first_free_pad_with_its_airfield_as_home() -> void:
	var world: World = Worlds.world()
	var field: int = world.index_of(Worlds.FIELD)
	var pad_0: Vector2i = Air.pad_point(world, field, 0)
	var pad_1: Vector2i = Air.pad_point(world, field, 1)
	# Both pads are tile centres inside the 3x3 footprint, two tiles apart.
	var origin: Vector2i = world.footprint_origin(field)
	for pad: Vector2i in [pad_0, pad_1]:
		var tile: Vector2i = pad / World.MILLI_PER_TILE - origin
		assert_bool(tile.x >= 0 and tile.y >= 0 and tile.x < 3 and tile.y < 3).is_true()
		assert_int(pad.x % World.MILLI_PER_TILE).is_equal(World.TILE_CENTRE)
	assert_int(maxi(absi(pad_0.x - pad_1.x), absi(pad_0.y - pad_1.y))).is_equal(2000)
	Worlds.step(world, [Worlds.queue(world, "jet")])
	Worlds.run(world, Worlds.BUILD + 1)
	var first: Array[int] = _aircraft(world)
	assert_int(first.size()).is_equal(1)
	assert_array([world.pos_x[first[0]], world.pos_y[first[0]]]).is_equal([pad_0.x, pad_0.y])
	assert_array([world.home[first[0]], world.order[first[0]]]).is_equal([Worlds.FIELD, 0])
	assert_int(world.ammo[first[0]]).is_equal(Worlds.AMMO)
	Worlds.step(world, [Worlds.queue(world, "jet")])
	Worlds.run(world, Worlds.BUILD + 1)
	var both: Array[int] = _aircraft(world)
	assert_int(both.size()).is_equal(2)
	assert_array([world.pos_x[both[1]], world.pos_y[both[1]]]).is_equal([pad_1.x, pad_1.y])
	assert_int(world.home[both[1]]).is_equal(Worlds.FIELD)


func test_a_head_waits_at_full_progress_with_no_free_pad_and_spawns_when_one_frees() -> void:
	var world: World = Worlds.world()
	Worlds.step(world, [Worlds.queue(world, "jet")])
	var one: int = Worlds.add_homed(world, "fighter", Worlds.FIELD, 0)
	var two: int = Worlds.add_homed(world, "fighter", Worlds.FIELD, 1)
	Worlds.run(world, Worlds.BUILD + 5)
	var queue: int = World.TABS + FLIGHT
	assert_int(_queue_count(world)).is_equal(1)
	assert_int(world.queue_progress[queue]).is_equal(Worlds.BUILD * Production.PROGRESS_PER_TICK)
	assert_int(_aircraft(world).size()).is_equal(2)
	assert_int(world.spawn_refused).is_equal(0)
	world.hp[one] = 0
	Worlds.step(world)
	Worlds.step(world)
	assert_int(_queue_count(world)).is_equal(0)
	(
		assert_array(_aircraft(world).map(func(row: int) -> int: return world.home[row]))
		. is_equal([Worlds.FIELD, Worlds.FIELD])
	)
	# `two` was parked on pad 1 and is now the first aircraft: it seats itself on pad 0 and the
	# new jet is on the other pad, so each is nearest its own pad once they have settled.
	Worlds.run(world, 60)
	_assert_seated(world)
	assert_int(world.unit_id.size()).is_greater(two)


func test_a_second_airfield_takes_the_spawn_when_the_producers_pads_are_full() -> void:
	var world: World = Worlds.world(true)
	Worlds.add_homed(world, "fighter", Worlds.FIELD, 0)
	Worlds.add_homed(world, "fighter", Worlds.FIELD, 1)
	Worlds.step(world, [Worlds.queue(world, "jet")])
	Worlds.run(world, Worlds.BUILD + 2)
	var jets: Array[int] = _aircraft(world).filter(
		func(row: int) -> bool: return world.type_ids[world.type_index[row]] == &"jet"
	)
	assert_int(jets.size()).is_equal(1)
	assert_int(world.home[jets[0]]).is_equal(Worlds.FIELD_2)
	var at: Vector2i = Air.pad_point(world, world.index_of(Worlds.FIELD_2), 0)
	assert_array([world.pos_x[jets[0]], world.pos_y[jets[0]]]).is_equal([at.x, at.y])


func test_a_flight_item_takes_no_rally_point_and_the_aircraft_has_no_order() -> void:
	var world: World = Worlds.world()
	Worlds.step(world, [Command.rally(1, Worlds.FIELD, 15000, 9000)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.rally_x[World.TABS + FLIGHT]).is_equal(-1)


## Ammo (ADR 0036 section 6): a shot of a type with ammo costs 1, at 0 the row does not fire (its
## target and cooldown stay), and a type with no limit never spends.
func test_a_shot_costs_one_ammo_and_a_row_at_zero_holds_fire(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.world()
	assert_array(SimImpls.use(world, impl)).is_empty()
	# Player 2 owns no airfield, so nothing re-homes the jet or sends it back.
	var jet: int = Worlds.add(world, 2, "jet", 9000, 9000)
	var fighter: int = Worlds.add(world, 2, "fighter", 9000, 9500)
	var dummy: int = Worlds.add(world, 1, "dummy", 11000, 9000)
	var shots: Dictionary[int, int] = {jet: 0, fighter: 0}
	_hold(world, jet)
	_hold(world, fighter)
	for _tick: int in 60:
		Worlds.step(world)
		for at: int in range(0, world.events.size(), World.EVENT_STRIDE):
			if world.events[at] == SHOT:
				var shooter: int = world.index_of(world.events[at + 1])
				shots[shooter] = shots.get(shooter, 0) + 1
	assert_int(shots[jet]).is_equal(Worlds.AMMO)
	assert_int(world.ammo[jet]).is_equal(0)
	assert_int(world.target[jet]).is_equal(world.unit_id[dummy])
	assert_int(world.cooldown[jet]).is_equal(0)
	assert_int(shots[fighter]).is_greater(Worlds.AMMO)
	assert_int(world.ammo[fighter]).is_equal(0)


## With a home and no ammo the aircraft turns for it (Air.run, the same tick); without a home it
## keeps its order, its target and holds fire.
func test_an_empty_homeless_aircraft_keeps_its_order_and_holds_fire() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add(world, 2, "jet", 9000, 9000)
	Worlds.add(world, 1, "dummy", 11000, 9000)
	world.order[jet] = World.Order.ATTACK_MOVE
	world.goal_x[jet] = 20000
	world.goal_y[jet] = 9000
	world.ammo[jet] = 0
	Worlds.run(world, 20)
	assert_array([world.order[jet], world.home[jet]]).is_equal([World.Order.ATTACK_MOVE, 0])
	assert_int(world.target[jet]).is_not_equal(0)
	assert_int(world.ammo[jet]).is_equal(0)
	assert_int(world.pos_x[jet]).is_greater(9000)  # Still on its way to its goal.


## Re-homing: a dead airfield sends its aircraft to the lowest-row own complete airfield with a
## free pad, or to 0; a homeless aircraft is taken by an airfield that appears.
func test_a_dead_airfield_re_homes_its_aircraft_to_one_with_a_free_pad() -> void:
	var world: World = Worlds.world(true)
	var one: int = Worlds.add_homed(world, "fighter", Worlds.FIELD, 0)
	var two: int = Worlds.add_homed(world, "fighter", Worlds.FIELD, 1)
	var third: int = Worlds.add_homed(world, "fighter", Worlds.FIELD_2, 0)
	var ids: Array[int] = [world.unit_id[one], world.unit_id[two], world.unit_id[third]]
	world.hp[world.index_of(Worlds.FIELD)] = 0
	Worlds.step(world)
	var homes: Array[int] = []
	for id: int in ids:
		homes.append(world.home[world.index_of(id)])
	# FIELD_2 has two pads: its own aircraft and the first of the others fit; the last has none.
	assert_array(homes).is_equal([Worlds.FIELD_2, 0, Worlds.FIELD_2])
	# A new airfield takes the homeless one at the next step.
	world.add_building(1, Worlds.type_of(world, "field"), 14, 2)
	Worlds.step(world)
	assert_int(world.home[world.index_of(ids[1])]).is_not_equal(0)


func test_an_airfield_that_is_not_complete_or_not_the_owners_is_no_home() -> void:
	var world: World = Worlds.world()
	var jet: int = Worlds.add_homed(world, "fighter", Worlds.FIELD, 0)
	world.build_left[world.index_of(Worlds.FIELD)] = 100
	Worlds.step(world)
	assert_int(world.home[jet]).is_equal(0)
	var other: int = Worlds.add(world, 2, "fighter", 15000, 9000)
	world.home[other] = Worlds.FIELD
	Worlds.step(world)
	assert_int(world.home[other]).is_equal(0)


## Every aircraft is within reach of the pad of its rank among the aircraft of its home and nearer
## to it than to the other pad of the field (separation may nudge it off the exact point).
func _assert_seated(world: World) -> void:
	var ranks: Dictionary[int, int] = {}
	for row: int in _aircraft(world):
		var home: int = world.home[row]
		assert_int(home).is_not_equal(0)
		var pad: int = ranks.get(home, 0)
		ranks[home] = pad + 1
		var field: int = world.index_of(home)
		var mine: Vector2i = Air.pad_point(world, field, pad)
		var other: Vector2i = Air.pad_point(world, field, 1 - pad)
		var here: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row])
		assert_int(here.distance_squared_to(mine)).is_less_equal(Worlds.REACH * Worlds.REACH)
		assert_int(here.distance_squared_to(mine)).is_less(here.distance_squared_to(other))


func test_the_pad_offsets_turn_to_the_airfields_facing() -> void:
	var world: World = Worlds.world()
	var field: int = world.index_of(Worlds.FIELD)
	# The rig's airfield at tile (2, 2) faces east, so (0, 0) and (2, 0) turn a quarter.
	assert_array([Air.pad_point(world, field, 0), Air.pad_point(world, field, 1)]).is_equal(
		[Vector2i(2500, 4500), Vector2i(2500, 2500)]
	)


## A death shifts the pads of the aircraft after it: the one that was on pad 1 is on pad 0 now,
## goes there, and goes on reloading (rank 0, so its pad is pad 0, 2000 away).
func test_a_death_on_the_airfield_moves_the_others_up_and_the_reload_goes_on() -> void:
	var world: World = Worlds.world()
	var first: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 0)
	var second: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 1)
	var id: int = world.unit_id[second]
	world.ammo[second] = 1
	world.hp[first] = 0
	Worlds.run(world, 80)
	var row: int = world.index_of(id)
	var pad: Vector2i = Air.pad_point(world, world.index_of(Worlds.FIELD), 0)
	assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([pad.x, pad.y])
	assert_int(world.ammo[row]).is_equal(Worlds.AMMO)


## A re-home to an airfield takes the rank of the aircraft in row order: the resident that is
## after it moves to the next pad and reloads there; the arrival (empty) flies to its own pad.
func test_a_re_homed_aircraft_does_not_stop_the_resident_reloading_nor_land_on_it() -> void:
	var world: World = Worlds.world(true)
	var arrival: int = Worlds.add_homed(world, "jet", Worlds.FIELD, 0)
	var resident: int = Worlds.add_homed(world, "jet", Worlds.FIELD_2, 0)
	world.ammo[resident] = 1
	world.ammo[arrival] = 0
	world.hp[world.index_of(Worlds.FIELD)] = 0
	var ids: Array[int] = [world.unit_id[arrival], world.unit_id[resident]]
	Worlds.run(world, 200)
	assert_int(world.ammo[world.index_of(ids[1])]).is_equal(Worlds.AMMO)
	assert_int(world.ammo[world.index_of(ids[0])]).is_equal(Worlds.AMMO)
	_assert_seated(world)


## `ProductionSpawn.spawn` sets `home` itself (checked before any `Air.run`), over the pad of
## the airfield it chose: the producer first, else the lowest other airfield with a free pad.
func test_spawn_order_is_the_producer_then_the_lowest_airfield_with_a_free_pad() -> void:
	var world: World = Worlds.world(true)  # Fields 1 and 3.
	var third: int = world.add_building(1, Worlds.type_of(world, "field"), 14, 2)  # Id 4.
	var jet: int = Worlds.type_of(world, "jet")
	# The producer is the highest row with free pads: it spawns there, not on the lowest.
	assert_bool(ProductionSpawn.spawn(world, 1, jet, world.index_of(third))).is_true()
	var row: int = world.unit_id.size() - 1
	assert_int(world.home[row]).is_equal(third)
	var at: Vector2i = Air.pad_point(world, world.index_of(third), 0)
	assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([at.x, at.y])
	# The middle airfield is the producer with both pads full: the lowest other one is next.
	Worlds.add_homed(world, "fighter", Worlds.FIELD_2, 0)
	Worlds.add_homed(world, "fighter", Worlds.FIELD_2, 1)
	assert_bool(ProductionSpawn.spawn(world, 1, jet, world.index_of(Worlds.FIELD_2))).is_true()
	row = world.unit_id.size() - 1
	assert_int(world.home[row]).is_equal(Worlds.FIELD)
	at = Air.pad_point(world, world.index_of(Worlds.FIELD), 0)
	assert_array([world.pos_x[row], world.pos_y[row]]).is_equal([at.x, at.y])


## Ammo is spent by a shot only: not while the cooldown runs, not with a target out of range.
func test_ammo_is_spent_by_a_shot_only() -> void:
	var world: World = Worlds.world()
	var far: int = Worlds.add(world, 2, "jet", 9000, 9000)
	Worlds.add(world, 1, "dummy", 17000, 9000)  # Beyond the jet's acquire range.
	_hold(world, far)
	Worlds.run(world, 20)
	assert_int(world.ammo[far]).is_equal(Worlds.AMMO)
	var near: int = Worlds.add(world, 2, "jet", 9000, 12000)
	Worlds.add(world, 1, "dummy", 11000, 12000)
	_hold(world, near)
	var spent: Array[int] = []
	for _tick: int in 12:
		Worlds.step(world)
		spent.append(world.ammo[near])
	# The weapon's cooldown is 3 ticks: one shot, then two ticks with the same ammo.
	assert_array(spent.slice(0, 6)).is_equal([2, 2, 2, 1, 1, 1])
