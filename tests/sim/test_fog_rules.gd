extends GdUnitTestSuite
## The fog rules of combat (P46b; ADR 0010 section 1 "Users", ADR 0009 section 2), part 2 of
## test_fog.gd: a unit acts only on an enemy that its player sees. An enemy is seen when the visible
## count of the cell that holds it is above 0 in the player's block of the fog (by any unit of the
## player, whichever stamped the disc). The rule is in both versions of the TARGETING phase, the
## GDScript twin and the C++ kernel, and in the validation of `ATTACK`, which is GDScript in both
## implementations; every case runs under both (ADR 0013 section 3, P46b) through `_both()` and
## `_in()`.
## - an enemy just outside every sight disc is not acquired, and is once it is seen;
## - an `ATTACK` on an enemy that is not seen is dropped and counted, and is taken once it is seen;
## - an `ATTACK` whose target leaves sight becomes an attack-move to where the target was last seen;
## - a held target that leaves sight is let go on the unit's next turn;
## - the best candidate that is not seen is passed over for the next one that is;
## - the sight of another unit of the player counts;
## - a neutral subject (owner 0, an armed neutral: none ships) has no grid and sees every cell;
## - `Targeting.sees`, the reference of the rule, at the edges of the grid;
## - two runs give the same hashes, and the C++ run gives those of the GDScript run.
##
## Hand-built worlds on a 30 x 30 map with literal numbers. A gun (type 0) sees 3000, acquires at
## 5000 and shoots 4000; its sight disc is the tiles with dx^2 + dy^2 <= 9 from its own tile, so the
## tile 3 east of it is seen and the one 4 east is not, 3500 and 3499 milli away alike (the unit
## stands in the middle of its tile). The scout (type 1) sees 3000 and has no weapon. The fog is
## real: the units are stamped by `Worlds.stamp_fog`, and every cadence is 1 unless a case says.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/targeting_worlds.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const GUN: int = 0
const SCOUT: int = 1
const COLS: int = 30
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"


func test_an_enemy_just_outside_every_sight_disc_is_not_acquired_and_is_once_it_is_seen(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	var mine: int = world.add_unit(1, GUN, 10500, 10500)
	var theirs: int = world.add_unit(2, GUN, 14000, 10500)
	Worlds.stamp_fog(world)
	_in(world, impl)
	# The disc of tile (10, 10) holds the tiles 7 to 13 of its row: the enemy stands in tile 14.
	assert_bool(world.fog.is_visible(1, 10 * COLS + 13)).is_true()
	assert_bool(world.fog.is_visible(1, 10 * COLS + 14)).is_false()
	assert_bool(world.fog.is_visible(2, 10 * COLS + 11)).is_true()
	assert_bool(world.fog.is_visible(2, 10 * COLS + 10)).is_false()
	for tick: int in 3:
		Sim.step(world, [])
		# Both guns look at each other (3500 away, inside the weapon range of 4000) and see nothing.
		assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(2)
		(
			assert_array([world.target[0], world.target[1]])
			. override_failure_message("tick %d" % tick)
			. is_equal([0, 0])
		)
	# One milli west, the enemy stands in tile 13, inside the disc of the gun: the gun takes it at
	# once. The enemy's own disc is still the one stamped at tile 14 (its player's FOG update comes
	# at the end of the tick, and moves the disc), so it sees the gun's tile 10 a tick later.
	world.pos_x[1] = 13999
	Sim.step(world, [])
	assert_array([world.target[0], world.target[1]]).is_equal([theirs, 0])
	Sim.step(world, [])
	assert_array([world.target[0], world.target[1]]).is_equal([theirs, mine])
	assert_int(world.dropped_commands).is_equal(0)


func test_an_attack_on_an_enemy_that_is_not_seen_is_dropped_and_counted_and_taken_once_it_is_seen(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	var mine: int = world.add_unit(1, GUN, 10500, 10500)
	var theirs: int = world.add_unit(2, GUN, 14000, 10500)
	var scout: int = world.add_unit(1, SCOUT, 6500, 10500)
	Worlds.stamp_fog(world)
	_in(world, impl)
	# The enemy stands in tile 14, outside the disc of the gun (the tiles 7 to 13 of its row) and
	# outside the scout's (3 to 9): the order is dropped and counted, and changes nothing.
	Sim.step(world, [_attack(world, mine, theirs)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal([IDLE, 0, 0])
	# One milli west it stands in tile 13: the same order is taken, and locks the target.
	world.pos_x[1] = 13999
	Sim.step(world, [_attack(world, mine, theirs)])
	assert_int(world.dropped_commands).is_equal(1)
	assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal(
		[ATTACK, theirs, theirs]
	)
	# Seen or not, the scout has no weapon: the order for it is dropped as well.
	Sim.step(world, [_attack(world, scout, theirs)])
	assert_int(world.dropped_commands).is_equal(2)
	assert_int(world.order[2]).is_equal(IDLE)


func test_an_attack_whose_target_leaves_sight_becomes_an_attack_move_to_where_it_was_last_seen(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.retarget_period_ticks = 5
	var mine: int = world.add_unit(1, GUN, 10500, 10500)
	var theirs: int = world.add_unit(2, GUN, 13500, 10500)
	Worlds.stamp_fog(world)
	_in(world, impl)
	Sim.step(world, [_attack(world, mine, theirs)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal(
		[ATTACK, theirs, theirs]
	)
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([13500, 10500])
	# The enemy steps out of every disc of player 1 (tile 20): on the next tick, whether or not the
	# unit has a turn, the lock is gone and the order is an attack-move to the point it was seen at.
	world.pos_x[1] = 20500
	Sim.step(world, [])
	assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal(
		[ATTACK_MOVE, 0, 0]
	)
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([13500, 10500])
	for _tick: int in 80:
		Sim.step(world, [])
	# It walked there and stopped. The enemy stays unseen: the disc of tile 13 ends at tile 16.
	assert_int(world.order[0]).is_equal(IDLE)
	assert_int(world.target[0]).is_equal(0)
	assert_int(world.pos_x[0]).is_between(13400, 13600)
	assert_int(world.pos_y[0]).is_equal(10500)
	assert_int(world.dropped_commands).is_equal(0)


func test_a_held_target_that_leaves_sight_is_let_go_on_the_units_next_turn(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.retarget_period_ticks = 5
	var mine: int = world.add_unit(1, GUN, 10500, 10500)
	var theirs: int = world.add_unit(2, GUN, 13999, 10500)
	Worlds.stamp_fog(world)
	_in(world, impl)
	world.tick = Rig.due_tick_for(world, mine)
	Sim.step(world, [])
	assert_int(world.target[0]).is_equal(theirs)
	# Tile 14 is outside the disc, but still 3500 milli away, in the range of the gun. The target is
	# held, as its range is, until the turn of the unit, 5 ticks after the one that took it.
	world.pos_x[1] = 14000
	for _tick: int in 4:
		assert_bool(Rig.is_due(world, 0)).is_false()
		Sim.step(world, [])
		assert_int(world.target[0]).is_equal(theirs)
	assert_bool(Rig.is_due(world, 0)).is_true()
	Sim.step(world, [])
	assert_int(world.target[0]).is_equal(0)


func test_the_best_candidate_that_is_not_seen_is_passed_over_for_the_next_one_that_is(
	impl: int, _test_parameters := _both()
) -> void:
	for revealed: bool in [false, true]:
		var world: World = _world()
		world.add_unit(1, GUN, 10500, 10500)
		# Unit 2 is the nearer, 2549 away, in tile (13, 11): 3 east and 1 south, outside the disc
		# (10 > 9). Unit 3 is 3499 away in tile (10, 13), inside it.
		var near: int = world.add_unit(2, GUN, 13000, 11000)
		var far: int = world.add_unit(2, GUN, 10500, 13999)
		Worlds.stamp_fog(world)
		_in(world, impl)
		if revealed:
			Rig.reveal(world)
		Sim.step(world, [])
		var want: int = near if revealed else far
		assert_int(world.target[0]).override_failure_message("revealed %s" % revealed).is_equal(
			want
		)


func test_the_sight_of_another_unit_of_the_player_counts(
	impl: int, _test_parameters := _both()
) -> void:
	for with_scout: bool in [false, true]:
		var world: World = _world()
		var mine: int = world.add_unit(1, GUN, 10500, 10500)
		var theirs: int = world.add_unit(2, GUN, 14000, 10500)
		if with_scout:
			world.add_unit(1, SCOUT, 16500, 10500)
		Worlds.stamp_fog(world)
		_in(world, impl)
		var order: Command = _attack(world, mine, theirs)
		Sim.step(world, [order])
		var label: String = "scout %s" % with_scout
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(
			0 if with_scout else 1
		)
		assert_int(world.target[0]).override_failure_message(label).is_equal(
			theirs if with_scout else 0
		)


func test_a_neutral_subject_has_no_grid_and_sees_every_cell(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world()
	world.add_unit(0, GUN, 10500, 10500)
	var blue: int = world.add_unit(1, GUN, 12500, 10500)
	var red: int = world.add_unit(2, GUN, 8500, 10500)
	Worlds.stamp_fog(world)
	_in(world, impl)
	# Nobody sees anything, and the neutral row was never stamped (it has no player).
	world.fog.visible.fill(0)
	assert_int(world.fog_cell[0]).is_equal(-1)
	Sim.step(world, [])
	# Both players' units stand 2000 from the neutral gun, which takes the lower row; the two
	# players' guns, 4000 apart and blind, take nobody.
	assert_array(world.target).is_equal([blue, 0, 0])
	# The lock of an ATTACK row of the neutral player holds on an unseen unit as well.
	world.order[0] = ATTACK
	world.order_target[0] = red
	Sim.step(world, [])
	assert_array([world.order[0], world.target[0]]).is_equal([ATTACK, red])
	assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([8500, 10500])


## A subject with no block in the fog sees every cell, as the neutral one does: a World with no map
## has no cells at all, and an owner past the fog's player count (a hand-built World whose
## `player_count` was raised after `prepare()`) has no block. The lock of an ATTACK row holds on
## an enemy that is far outside every disc in both.
func test_a_world_with_no_map_and_an_owner_past_the_fog_have_no_grid_and_see_every_cell(
	impl: int, _test_parameters := _both()
) -> void:
	var bare: World = World.new()
	bare.type_ids.append(&"unit")
	bare.type_speed.append(120)
	bare.add_unit(1, 0, 4500, 4500)
	bare.add_unit(2, 0, 9500, 4500)
	_in(bare, impl)
	assert_int(bare.fog.cells).is_equal(0)
	bare.order[0] = ATTACK
	bare.order_target[0] = 2
	Sim.step(bare, [])
	assert_array([bare.order[0], bare.order_target[0], bare.target[0]]).is_equal([ATTACK, 2, 2])
	var world: World = _world()
	world.add_unit(1, GUN, 3500, 3500)
	world.add_unit(2, GUN, 27500, 27500)
	Worlds.stamp_fog(world)
	_in(world, impl)
	# Owner 3 has no block (the fog has two): its row locks on the unit that no disc of the map covers.
	world.owner[0] = 3
	world.order[0] = ATTACK
	world.order_target[0] = 2
	Sim.step(world, [])
	assert_bool(Targeting.sees(world, 3, 27500, 27500)).is_true()
	assert_bool(world.fog.is_visible(2, 27 * COLS + 27)).is_true()
	assert_bool(world.fog.is_visible(1, 27 * COLS + 27)).is_false()
	assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal([ATTACK, 2, 2])
	# Owner 1 does not: the same lock ends, and the order becomes an attack-move to where it stood.
	world.owner[0] = 1
	Sim.step(world, [])
	assert_array([world.order[0], world.order_target[0], world.target[0]]).is_equal(
		[ATTACK_MOVE, 0, 0]
	)


## Targeting.sees, the rule that Sim.step uses to validate an ATTACK and the loops of the phase
## inline: the cell of the point is World.cell_of's (a point off the map is in the nearest edge
## cell), a player with no block sees every cell, and so does a fog without cells.
func test_sees_is_the_visible_count_of_the_cell_in_the_players_block() -> void:
	var world: World = _world()
	world.add_unit(1, GUN, 500, 500)
	world.add_unit(2, GUN, 29500, 29500)
	world.add_unit(2, GUN, 29500, 13500)
	world.add_unit(2, GUN, 13500, 29500)
	Worlds.stamp_fog(world)
	# In the corner disc of player 1 (tiles (0, 0) to (3, 0)), just outside it, and not in player 2's.
	assert_bool(Targeting.sees(world, 1, 3999, 999)).is_true()
	assert_bool(Targeting.sees(world, 1, 4000, 500)).is_false()
	assert_bool(Targeting.sees(world, 1, 500, 4000)).is_false()
	assert_bool(Targeting.sees(world, 2, 500, 500)).is_false()
	assert_bool(Targeting.sees(world, 2, 29500, 29500)).is_true()
	# Off the map: the nearest edge cell, whichever way it is off.
	assert_bool(Targeting.sees(world, 1, -5000, -5000)).is_true()
	assert_bool(Targeting.sees(world, 1, -1, 999)).is_true()
	assert_bool(Targeting.sees(world, 1, 99000, 99000)).is_false()
	assert_bool(Targeting.sees(world, 2, 99000, 99000)).is_true()
	assert_bool(Targeting.sees(world, 2, 30000, 29000)).is_true()
	# The east and south edges: the discs of player 2's units at tiles (29, 13) and (13, 29) reach
	# the tile 3 north or west of the edge cell, the edge cell itself and nothing between.
	assert_bool(Targeting.sees(world, 2, 29500, 16500)).is_true()
	assert_bool(Targeting.sees(world, 2, 99000, 16500)).is_true()
	assert_bool(Targeting.sees(world, 2, 28500, 16500)).is_false()
	assert_bool(Targeting.sees(world, 2, 16500, 29500)).is_true()
	assert_bool(Targeting.sees(world, 2, 16500, 99000)).is_true()
	assert_bool(Targeting.sees(world, 2, 16500, 28500)).is_false()
	# No block: the neutral player, a player past the count, a negative one.
	for player: int in [0, 3, 99, -1]:
		assert_bool(Targeting.sees(world, player, 15500, 15500)).is_true()
	# No cells: a World with no map has no fog.
	var bare: World = World.new()
	bare.add_unit(1, 0, 4500, 4500)
	bare.prepare()
	assert_int(bare.fog.cells).is_equal(0)
	assert_bool(Targeting.sees(bare, 1, 4500, 4500)).is_true()
	assert_bool(Targeting.sees(bare, 1, 1000000, -1000000)).is_true()


func test_two_runs_give_the_same_hashes_and_the_native_run_the_hashes_of_the_gdscript_run(
	impl: int, _test_parameters := _both()
) -> void:
	var first: Array = _hash_run(impl)
	var second: Array = _hash_run(impl)
	assert_array(first[0]).is_equal(second[0])
	assert_int(first[0].size()).is_equal(151)
	# The ATTACK at tick 0 names a red tank that no blue tank sees (red 31 starts 18 tiles from the
	# block), so it is dropped and counted, in every run.
	assert_int(first[1]).is_greater(0)
	assert_int(first[1]).is_equal(second[1])
	assert_array(first[0]).is_not_equal(_hash_run_without_orders(impl))
	if impl == SimImpls.Impl.NATIVE:
		var twin: Array = _hash_run(SimImpls.Impl.GDSCRIPT)
		assert_array(first[0]).is_equal(twin[0])
		assert_int(first[1]).is_equal(twin[1])


## The state hash at tick 0 and after each of 150 ticks of the controls scenario with thirty blue
## tanks ordered to attack-move across the map, and with ATTACK orders at tick 0 and 60 at red tank
## 31, as [hashes, commands dropped in the run].
func _hash_run(impl: int, with_orders: bool = true) -> Array:
	var world: World = _in(World.from_scenario(load(SCENARIO_PATH) as ScenarioDef), impl)
	var ids: PackedInt32Array = PackedInt32Array(range(1, 31))
	var hashes: PackedInt64Array = PackedInt64Array([world.state_hash()])
	var commands: Array[Command] = []
	for _t: int in 150:
		commands.clear()
		if with_orders and world.tick == 0:
			commands.append(_attack(world, 1, 31))
			commands.append(Command.attack_move(1, ids, 30000, 14000))
		if with_orders and world.tick == 60:
			commands.append(_attack(world, 2, 31))
		for command: Command in commands:
			command.tick = world.tick
		Sim.step(world, commands)
		hashes.append(world.state_hash())
	return [hashes, world.dropped_commands]


## The same run with no orders at all.
func _hash_run_without_orders(impl: int) -> PackedInt64Array:
	return _hash_run(impl, false)[0]


## gdUnit4's parameter sets: the GDScript phase and the C++ kernel, a case each (SimImpls.CASES).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and TARGETING really in the implementation asked
## for (the problems of SimImpls.attach, none).
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
	return world


## A 30 x 30 map with the gun (type 0) and the scout (type 1), real fog, every cadence 1: each unit
## has a turn on every tick and the fog of both players is updated on every tick.
func _world() -> World:
	var gun: UnitDef = Rig.unit(&"gun", 3000, 5000, 4000, 0, [100, 100, 100, 100])
	var scout: UnitDef = Rig.unit(&"scout", 3000, 3000, 0, 0, [])
	var units: Array[UnitDef] = [gun, scout]
	var world: World = Rig.world_of(units, COLS, COLS, false)
	world.retarget_period_ticks = 1
	world.fog_period_ticks = 1
	return world


## An ATTACK of the unit `id` (any player's, whose it is) on `target`, for the tick the World is at.
func _attack(world: World, id: int, target: int) -> Command:
	var player: int = world.owner[world.index_of(id)]
	var command: Command = Command.attack(player, PackedInt32Array([id]), target)
	command.tick = world.tick
	return command
