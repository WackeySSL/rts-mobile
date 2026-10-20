extends GdUnitTestSuite
## The wiring and the table indexes of target acquisition (P41; ADR 0009 section 2) that the other
## targeting suites leave open: `Targeting.run` on every tick of `Sim.step` (the checkpoint ticks
## among them) and once per step, the percents of a weapon that is not weapon 0 (the index
## `weapon * 4 + armour` of `weapon_vs_armour`), and the cell size the search reads from the grid.
## The priority, the stagger and the position in the tick are in test_targeting.gd; the edges of
## the search are in test_targeting_edges.gd. The worlds are those of TargetingRig.
##
## Every case runs under both implementations (ADR 0013 section 3, P41n): the GDScript phase and the
## C++ kernel, through `_both()` and `_in()`. The kernel-only cases are in
## tests/sim/native/test_targeting_kernel*.gd.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const RIFLE: int = 0


## `Sim.step` runs the TARGETING phase on every tick, the ticks that `MatchLoop` hashes included
## (the new tick is a multiple of 15: 15, 30, 45 and 60 after the steps at 14, 29, 44 and 59). A
## period of 1 makes every unit due, so a step that skipped the phase on those ticks, as FLOW does
## for its slice, would leave the target at 0. A hash that differs between two runs would not show
## it, because both runs would skip alike.
func test_targeting_runs_on_checkpoint_ticks_too(impl: int, _test_parameters := _both()) -> void:
	for first_tick: int in [14, 29, 44, 59]:
		var world: World = _in(Rig.data_world(), impl)
		world.retarget_period_ticks = 1
		world.add_unit(1, RIFLE, 5000, 3000)
		world.add_unit(2, RIFLE, 8000, 3000)
		world.tick = first_tick
		Sim.step(world, [])
		var label: String = "step at tick %d" % first_tick
		assert_int(world.target[0]).override_failure_message(label).is_equal(2)


## One `Sim.step` scans a due unit once. A friend 1000 away is looked at and rejected, so the unit
## finds nothing and a second `Targeting.run` in the same step would scan it again: the work count
## would be 2, not 1. Unit 1 is due at tick 4, unit 2 (the friend) is not.
func test_one_step_scans_a_due_unit_once(impl: int, _test_parameters := _both()) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 5000, 3000)
	world.add_unit(1, RIFLE, 6000, 3000)
	world.tick = 4
	Sim.step(world, [])
	assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(1)


## A weapon that is not weapon 0 reads its own four percents: weapon 1 sits at indexes 4 to 7 of
## `weapon_vs_armour`, so the stride is the four armour classes. Gun 1 does 10% against infantry
## and 90% against buildings, gun 0 100% against everything. With a stride of 3 gun 1 would read
## gun 0's 100 for the infantry unit and its own 10 (the heavy column) for the building, and take
## the nearer infantry unit; a stride of 5 reads past the end of the table.
func test_a_second_weapon_reads_its_own_four_percents(
	impl: int, _test_parameters := _both()
) -> void:
	var gun0: UnitDef = Rig.unit(&"gun0", 8000, 8000, 6000, 0, [100, 100, 100, 100])
	var gun1: UnitDef = Rig.unit(&"gun1", 8000, 8000, 6000, 0, [10, 10, 10, 90])
	var infantry: UnitDef = Rig.unit(&"infantry", 8000, 8000, 0, 0, [])
	var building: UnitDef = Rig.unit(&"building", 8000, 8000, 0, 0, [])
	building.armour = World.Armour.BUILDING
	var world: World = _in(Rig.world_of([gun0, gun1, infantry, building]), impl)
	world.add_unit(1, 1, 10000, 6000)
	world.add_unit(2, 2, 11500, 6000)
	world.add_unit(2, 3, 13000, 6000)
	assert_int(Rig.target_of(world, 1)).is_equal(3)


## The percents of the shipped weapons in the roster order of the perf arena (light tank, rifle
## squad, rocket squad), where the rifle's percents are weapon 1 (indexes 4 to 7) and the rocket's
## weapon 2 (8 to 11); the other targeting suites list the types as rifle, rocket, tank, where type
## and weapon index are equal for the first one. A rifle squad takes the 100% infantry over a
## nearer tank (10%) and a rocket squad the tank (100%) over a nearer rifle squad (20%). A stride of
## 3 would give the rifle 40 against infantry (the tank cannon's building column) and 100 against
## the tank (its own infantry column).
func test_the_percents_of_weapons_one_and_two_are_read_in_the_arenas_roster_order(
	impl: int, _test_parameters := _both()
) -> void:
	var units: Array[UnitDef] = [
		load(Rig.TANK_PATH) as UnitDef,
		load(Rig.RIFLE_PATH) as UnitDef,
		load(Rig.ROCKET_PATH) as UnitDef
	]
	var rifle: World = _in(Rig.world_of(units), impl)
	rifle.add_unit(1, 1, 10000, 6000)
	rifle.add_unit(2, 0, 11500, 6000)
	rifle.add_unit(2, 1, 13000, 6000)
	assert_int(Rig.target_of(rifle, 1)).override_failure_message("rifle").is_equal(3)
	var rocket: World = _in(Rig.world_of(units), impl)
	rocket.add_unit(1, 2, 10000, 6000)
	rocket.add_unit(2, 1, 11500, 6000)
	rocket.add_unit(2, 0, 13000, 6000)
	assert_int(Rig.target_of(rocket, 1)).override_failure_message("rocket").is_equal(3)


## The search reads the cell size of the grid it is given, not a 4000 of its own. A grid of
## 2000-milli cells (set up by hand after `prepare`, which would otherwise size it again) holds an
## enemy exactly 4000 away, the rifle's reach, in column 7 (the subject is in column 5): a search
## that divided by 4000 would cover only columns 1 to 3 of the finer grid and miss it.
func test_the_search_reads_the_cell_size_of_the_grid(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Rig.data_world(), impl)
	world.add_unit(1, RIFLE, 10000, 6000)
	world.add_unit(2, RIFLE, 14000, 6000)
	world.prepare()
	world.target_grid.configure(world.map_w, world.map_h, 2000, world.max_rows)
	assert_int(world.target_grid.cell_milli).is_equal(2000)
	assert_int(Rig.target_of(world, 1)).is_equal(2)


## A held target is dropped when it is out of reach along y alone: the enemy stands 6000 above the
## unit (the same x), past the reach of an idle rifle squad (weapon range 4000) and of an
## attack-moving one (acquire range 5000). A keep check that left y out of the distance would find
## it 0 away and keep it. With no other enemy the unit has no target after its next due tick.
func test_a_held_target_6000_away_in_y_only_is_dropped_at_the_next_due_tick(
	impl: int, _test_parameters := _both()
) -> void:
	for order: int in [World.Order.IDLE, World.Order.ATTACK_MOVE]:
		var world: World = _in(Rig.data_world(), impl)
		world.add_unit(1, RIFLE, 10000, 3000)
		world.add_unit(2, RIFLE, 10000, 9000)
		world.order[0] = order
		world.target[0] = 2
		assert_int(Rig.target_of(world, 1)).override_failure_message("order %d" % order).is_equal(0)


## A type that names weapon 1 when the weapon tables hold one row is unarmed, not an error: its
## unit acquires nothing, with an enemy 1000 away, and the run reads no entry past the tables
## (`weapon_range[1]`), through acquisition and engagement both.
func test_a_type_naming_weapon_1_with_one_weapon_table_row_gets_no_target(
	impl: int, _test_parameters := _both()
) -> void:
	var gun: UnitDef = Rig.unit(&"gun", 8000, 5000, 4000, 0, [100, 100, 100, 100])
	var world: World = _in(Rig.world_of([gun]), impl)
	assert_int(world.weapon_range.size()).is_equal(1)
	world.type_weapon[0] = 1
	world.add_unit(1, 0, 10000, 6000)
	world.add_unit(2, 0, 11000, 6000)
	world.order[0] = World.Order.ATTACK_MOVE
	assert_int(Rig.target_of(world, 1)).is_equal(0)
	assert_int(Rig.retarget(world, 1)).is_equal(0)
	assert_int(world.nav_mode[0]).is_equal(World.NavMode.NONE)


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and the TARGETING phase really in the implementation
## asked for (the problems of SimImpls.attach, none).
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
	return world
