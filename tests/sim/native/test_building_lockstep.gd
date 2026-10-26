extends GdUnitTestSuite
## Buildings in the lockstep of every kernel (plan row P71, ADR 0017 section 1, "Why no other kernel
## changes"): the kernels read the blocked tiles through `move_cost`, the radii, the rows as
## candidates and the rows' cells, so a World with buildings needs no new kernel rule, and this
## suite proves it. Two Worlds built by one function, the first on the GDScript phases and the
## second with one kernel alone (FLOW, TARGETING, SEPARATION, INTEGRATE or FOG) or with all of them
## on, each stepped by its own MatchLoop with the same orders, are compared after every tick by the
## state hash and the full state (LockstepRig.difference: every shape list, every scalar, the flow
## cache, both grids, the fog).
##
## The World is Worlds.fight(): two bases (Headquarters, power plant and turret each) either side of
## a wall of rock with a gap, a dozen units of one player and ten of the other attack-moving to the
## enemy base, the weak buildings dying in the fight, and two buildings placed while it goes on (a
## placement and a building death each bump `map_version`, so every field is integrated again). The
## tally at the end holds the rules the run reached, so that it cannot pass by never meeting them.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const LockstepRig: GDScript = preload("res://tests/sim/support/lockstep_rig.gd")
const TICKS: int = 450
## The tick at which both Worlds get a building: a power plant for player 1 and a turret for 2.
const PLACE_TICK: int = 100
## The ticks at which a building of each side is destroyed (player 2's turret, player 1's plant),
## the same way in both Worlds, so that two deaths happen whatever the fight does.
const DESTROY_TICKS: Array[int] = [200, 260]
const DESTROYED_IDS: Array[int] = [5, 2]
## The mask value that leaves every phase of the library on.
const ALL: int = -1


## One parameter set per kernel, and one with every kernel on.
func _kernels() -> Array[Array]:
	return [
		[SimProbe.Phase.FLOW],
		[SimProbe.Phase.TARGETING],
		[SimProbe.Phase.SEPARATION],
		[SimProbe.Phase.INTEGRATE],
		[SimProbe.Phase.FOG],
		[ALL]
	]


## The mobile ids of `player`, ascending.
func _army(world: World, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_speed[world.type_index[row]] > 0:
			ids.append(world.unit_id[row])
	return ids


## The commands of tick `tick` for `world`, which this also changes at PLACE_TICK and at the
## DESTROY_TICKS (the same way for both Worlds): each World gets its own Command objects.
func _orders(world: World, tick: int) -> Array[Command]:
	var orders: Array[Command] = []
	if tick == 0:
		orders.append(Command.attack_move(1, _army(world, 1), 22500, 7500))
		orders.append(Command.attack_move(2, _army(world, 2), 5500, 7500))
	if tick == PLACE_TICK:
		var plant: int = world.add_building(1, Worlds.type_of(world, "power_plant"), 10, 12)
		var turret: int = world.add_building(2, Worlds.type_of(world, "defence_turret"), 21, 3)
		world.hp[world.index_of(plant)] = 150
		world.hp[world.index_of(turret)] = 120
	for which: int in DESTROY_TICKS.size():
		var row: int = world.index_of(DESTROYED_IDS[which])
		if tick == DESTROY_TICKS[which] and row >= 0:
			world.hp[row] = 0
	return orders


## Adds what `world` did this tick to `tally`: the modes it saw and the buildings that died.
func _count(world: World, tally: Dictionary[String, int]) -> void:
	for row: int in world.unit_count():
		match world.nav_mode[row]:
			World.NavMode.HOLD:
				tally["hold"] += 1
			World.NavMode.FIELD:
				tally["field"] += 1
			World.NavMode.CHASE:
				tally["chase"] += 1
	var at: int = 0
	while at + World.EVENT_STRIDE <= world.events.size():
		if world.events[at] == World.Event.DIED:
			var type: int = world.events[at + 4]
			tally["died_buildings" if world.type_foot_w[type] > 0 else "died_units"] += 1
		at += World.EVENT_STRIDE


func test_a_base_fight_agrees_tick_by_tick_with_each_kernel_and_with_all(
	phase: int, _test_parameters := _kernels()
) -> void:
	var problems: Array[String] = []
	var worlds: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = Worlds.fight()
		problems.append_array(SimImpls.use(world, impl))
		if impl == SimImpls.Impl.NATIVE and phase != ALL:
			world.native_phases = 1 << phase
		worlds.append(world)
	assert_array(problems).is_empty()
	for index: int in worlds.size():
		for each: int in SimImpls.EXPECTED_PHASES:
			var native: bool = index == 1 and (phase == ALL or each == phase)
			assert_bool(SimImpls.is_native(worlds[index], each)).is_equal(native)
	var loops: Array[MatchLoop] = []
	for world: World in worlds:
		loops.append(MatchLoop.create(null, "", 0, world))
	var version: int = worlds[0].map_version
	var tally: Dictionary[String, int] = {
		"hold": 0, "field": 0, "chase": 0, "died_buildings": 0, "died_units": 0
	}
	for tick: int in TICKS:
		for index: int in worlds.size():
			loops[index].step(worlds[index], _orders(worlds[index], tick))
		var found: String = LockstepRig.difference(worlds[0], worlds[1])
		assert_str(found).override_failure_message("tick %d: %s" % [tick, found]).is_empty()
		if found != "":
			return
		_count(worlds[0], tally)
	# What the run reached: units holding and following fields round the wall and the buildings,
	# buildings that died (their tiles given back) and two that were placed.
	assert_int(tally["hold"]).is_greater(0)
	assert_int(tally["field"]).is_greater(0)
	assert_int(tally["died_buildings"]).is_greater_equal(2)
	assert_int(tally["died_units"]).is_greater(0)
	assert_int(worlds[0].map_version - version).is_greater_equal(4)
	for row: int in worlds[0].unit_count():
		if worlds[0].type_foot_w[worlds[0].type_index[row]] > 0:
			assert_int(worlds[0].fog_cell[row]).is_greater_equal(0)  # Stamped, and so kept.
