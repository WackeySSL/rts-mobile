extends GdUnitTestSuite
## A unit whose own slot cannot be reached from its group's target (P37b; ADR 0008 section 3, lead
## decision of 2026-10-15). The group's field is keyed on the group target, so a unit with a goal
## elsewhere follows it only to the group target, or as far as the field names a next tile. When
## `Movement.integrate` finds the field complete and naming no tile (NO_NEXT) on a field keyed on a
## tile other than the unit's goal's, the unit takes the field of its own goal tile
## (`_take_own_field`): the new slot, `nav_next` -1 (looked up at the next event) and a fresh stall
## count. With every slot referenced it keeps its field and NO_NEXT and asks again at its next
## turn. A key that is rock now counts as naming no tile (`_refresh_next`; the runs of that are in
## test_movement_blocked_key.gd). The rule holds for every order that follows a field: MOVE,
## ATTACK_MOVE, and an ATTACK unit whose key tile is still within `attack_rekey_milli` of its
## goal (the second way an ATTACK unit changes its field besides the re-key; ADR 0008 section 3
## names only the first). The hand-set cases call `integrate` on its own (zero intents, so no unit
## leaves its tile); the whole run through a thin wall is in test_movement_fields.gd. Maps are
## built in code (GridWorld).
## Every case runs under both implementations of the INTEGRATE phase (P37n), the GDScript twin and
## the C++ kernel, through SimImpls: gdUnit4 runs it once for each.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TRACKED: int = World.MoveClass.TRACKED
const FOOT: int = World.MoveClass.FOOT
const MOVE: int = World.Order.MOVE
const FIELD: int = World.NavMode.FIELD
## The terrain indexes of scrub (foot units only) and rock (nothing) in GridWorld's GROUND string.
const SCRUB: int = 1
const ROCK: int = 2


## A unit stands on the tile its group field is keyed on, 2000 from its own goal. The field is
## complete and names no tile for the key tile itself, so the unit takes the field of its goal's
## tile: slot 1, keyed on that tile, `nav_next` -1. Once that field is complete the next event
## gives it a tile on the way (13, 4), and the unit keeps the field of its own tile from then on.
func test_a_group_field_naming_no_tile_gives_the_unit_the_field_of_its_own_goal_tile(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	var key: int = world.cell_of(12500, 4500)
	var own: int = world.cell_of(14500, 4500)
	_hold(world, 0, 12500, 4500, 14500, 4500, key)
	assert_int(world.field[0]).is_equal(0)
	world.tick = 7
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0], world.flow.key_goal[1]]).is_equal([1, -1, own])
	assert_int(world.flow.key_class[1]).is_equal(TRACKED)
	assert_array([world.flow.last_used[1], world.flow.key_version[1]]).is_equal(
		[7, world.map_version]
	)
	assert_int(world.map_version).is_greater(0)
	FlowCache.run(world, 100000)
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([1, 4 * 20 + 13])
	assert_int(world.flow.status.count(FlowCache.Status.FREE)).is_equal(6)


## A unit on the field of its own goal's tile that finds no next tile (it stands on the tile, 400
## short of its goal) takes no other field: NO_NEXT stays, the slot stays, and no slot is taken.
func test_a_unit_on_the_field_of_its_own_goal_tile_takes_no_other_field(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	_hold(world, 0, 12500, 4500, 12900, 4500, world.cell_of(12500, 4500))
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([0, Movement.NO_NEXT])
	assert_int(world.flow.status.count(FlowCache.Status.FREE)).is_equal(7)


## The new slot may be slot 0: a cache of two slots, slot 0 held by a field nobody follows, the
## group's field in slot 1. The own goal tile takes the unreferenced slot 0 (the field in it is
## replaced), and the unit follows it.
func test_the_unit_takes_slot_0_when_that_is_the_one_nobody_follows(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(2, impl)
	(
		assert_int(world.flow.acquire(world.cell_of(3500, 11500), TRACKED, world.map_version, 0))
		. is_equal(0)
	)
	_hold(world, 0, 12500, 4500, 14500, 4500, world.cell_of(12500, 4500))
	assert_int(world.field[0]).is_equal(1)
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([0, -1])
	assert_int(world.flow.key_goal[0]).is_equal(world.cell_of(14500, 4500))


## With every slot referenced the unit keeps the group's field and NO_NEXT, and asks again on its
## next turns only. A cache of two slots: unit 1 holds the group's field in slot 0, unit 2 another
## in slot 1. Unit 1 (a turn on ticks where (tick + 1) % 5 == 0) finds no slot on the tick its
## field completes (3) and on its turn (4). Unit 2 then stops; a free slot is no reason to ask on
## tick 5, which is not a turn, and on tick 9, the next turn, unit 1 takes the field of its own
## goal tile in slot 1.
func test_with_every_slot_referenced_the_unit_keeps_its_field_and_asks_again_on_its_turn(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(2, impl)
	var key: int = world.cell_of(12500, 4500)
	_hold(world, 0, 12500, 4500, 14500, 4500, key)
	_hold(world, 1, 3500, 8500, 18500, 11500, world.cell_of(18500, 11500))
	assert_array([world.field[0], world.field[1]]).is_equal([0, 1])
	for tick: int in [3, 4]:
		world.tick = tick
		FlowCache.run(world, 0)
		Movement.integrate(world)
		assert_array([world.field[0], world.nav_next[0]]).is_equal([0, Movement.NO_NEXT])
	world.order[1] = World.Order.IDLE
	world.field[1] = -1
	for tick: int in [5, 6, 7, 8]:
		world.tick = tick
		FlowCache.run(world, 0)
		Movement.integrate(world)
		assert_array([world.field[0], world.nav_next[0]]).is_equal([0, Movement.NO_NEXT])
	world.tick = 9
	FlowCache.run(world, 0)
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([1, -1])
	assert_int(world.flow.key_goal[1]).is_equal(world.cell_of(14500, 4500))


## The start of the unit's stall count goes with the field: a unit that waited at the key tile for a
## free slot has counted stalled ticks and holds the best distance of the group's field, neither of
## which is progress on the new one. It takes the field of its own goal (here after a cache of two
## slots had one free) with a fresh best distance and a stall count of 0. With every slot referenced
## it keeps both and goes on counting: the best distance 1000 is below the 2000 to the goal, so the
## stall count 12 is 13 after the call.
func test_taking_the_field_of_its_own_goal_starts_the_stall_count_over(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	_hold(world, 0, 12500, 4500, 14500, 4500, world.cell_of(12500, 4500))
	world.best_dist[0] = 1000
	world.stall[0] = 12
	Movement.integrate(world)
	assert_array([world.field[0], world.best_dist[0], world.stall[0]]).is_equal(
		[1, FlowField.UNREACHED, 0]
	)
	var full: World = _world(1, impl)
	_hold(full, 0, 12500, 4500, 14500, 4500, full.cell_of(12500, 4500))
	full.best_dist[0] = 1000
	full.stall[0] = 12
	Movement.integrate(full)
	assert_array([full.field[0], full.nav_next[0]]).is_equal([0, Movement.NO_NEXT])
	assert_array([full.best_dist[0], full.stall[0]]).is_equal([1000, 13])


## ATTACK_MOVE takes the field of its own goal like MOVE (Formation gives it a group target the same
## way): the unit stands on the group target, 2000 from its goal.
func test_an_attack_move_unit_takes_the_field_of_its_own_goal_tile(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	_hold(world, 0, 12500, 4500, 14500, 4500, world.cell_of(12500, 4500))
	world.order[0] = World.Order.ATTACK_MOVE
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([1, -1])
	assert_int(world.flow.key_goal[1]).is_equal(world.cell_of(14500, 4500))


## An ATTACK unit takes the field of its goal's tile when it has outrun its field. It stands on the
## tile its field is keyed on (the goal's tile when it acquired it), and the target has since moved
## 2000 away, inside `attack_rekey_milli` (4000), so the re-key rule keeps the field. The field
## names no tile for the key tile itself: the unit takes the field of the goal's tile now
## (`group_cell` is -1 for an ATTACK unit), so it does not stand still on a tile the target has
## left until the target is 4000 away. This is the second trigger for an ATTACK unit's field
## besides the re-key.
func test_an_attack_unit_that_outran_its_field_takes_the_field_of_its_goal_tile(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	_hold(world, 0, 12500, 4500, 14500, 4500, world.cell_of(12500, 4500))
	world.order[0] = World.Order.ATTACK
	world.group_cell[0] = -1
	assert_int(world.attack_rekey_milli).is_equal(4000)
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([1, -1])
	assert_int(world.flow.key_goal[1]).is_equal(world.cell_of(14500, 4500))
	assert_int(world.order[0]).is_equal(World.Order.ATTACK)


## A key that turned to rock is no next tile for a unit without a group cell either: an ATTACK unit,
## and the ATTACK_MOVE unit its order becomes when the target dies (`Targeting.run` leaves
## `group_cell` at -1), stand next to the key tile of their field with the goal 2000 from it, inside
## `attack_rekey_milli` (no re-key). Each takes the field of its goal's tile instead of pressing on
## the rock for good (an ATTACK unit never stalls). The blocked-key rule is for every unit that
## follows a field, not for the ones with a group cell; the run end to end is in
## test_movement_blocked_key.gd.
func test_an_attack_unit_next_to_a_key_that_turned_to_rock_takes_the_field_of_its_goal(
	impl: int, _test_parameters := _both()
) -> void:
	for order: int in [World.Order.ATTACK, World.Order.ATTACK_MOVE]:
		var world: World = _world(8, impl)
		var key: int = world.cell_of(12500, 4500)
		_hold(world, 0, 11500, 4500, 14500, 4500, key)
		world.order[0] = order
		world.group_cell[0] = -1
		(
			assert_int(world.flow.field(world.field[0]).best_neighbour(world.cell_of(11500, 4500)))
			. is_equal(key)
		)
		world.set_terrain(key, ROCK)
		Movement.integrate(world)
		var label: String = "order %d" % order
		assert_array([world.field[0], world.nav_next[0]]).override_failure_message(label).is_equal(
			[1, -1]
		)
		assert_int(world.flow.key_goal[1]).override_failure_message(label).is_equal(
			world.cell_of(14500, 4500)
		)


## The same end to end. Two walls (columns 10 and 20 of a 30 x 14 map, rows 0 to 9, so the way round
## each is south) and an enemy at (19500, 5500): the tank's first line check is blocked by the first
## wall, so its field is keyed on the enemy's tile (19, 5). On tick 20 the enemy is moved to
## (21500, 5500), behind the second wall and 2000 from the key (no re-key). The tank follows the
## field to the key tile, finds no tile there, takes the field of the enemy's new tile and goes
## round the second wall: it ends east of it, next to the enemy.
func test_an_attack_unit_whose_target_moved_across_a_wall_takes_its_own_field(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 10:
		rock.append(Vector2i(10, row))
		rock.append(Vector2i(20, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(30, 14, rock)), impl)
	world.player_count = 2
	world.type_weapon[0] = 0
	world.add_unit(1, 0, 3500, 5500)
	world.add_unit(2, 0, 19500, 5500)
	var keyed_on: int = -1
	for tick: int in 900:
		var commands: Array[Command] = []
		if tick == 0:
			var attack: Command = Command.attack(1, PackedInt32Array([1]), 2)
			attack.tick = 0
			commands.append(attack)
		if tick == 20:
			world.pos_x[1] = 21500
		Sim.step(world, commands)
		if tick == 19:
			keyed_on = world.flow.key_goal[world.field[0]]
	assert_int(keyed_on).is_equal(world.cell_of(19500, 5500))
	assert_int(world.pos_x[0]).is_greater(21000)
	assert_int(world.order[0]).is_equal(World.Order.ATTACK)


## A key tile that turned to rock names no tile: `best_neighbour` still names it (the field seeds
## its key at cost 0 whatever the terrain), and the unit next to it takes the field of its own
## goal's tile instead, which leads round the rock.
func test_a_key_tile_that_turned_to_rock_gives_the_unit_the_field_of_its_own_goal(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	var key: int = world.cell_of(12500, 4500)
	_hold(world, 0, 11500, 4500, 14500, 4500, key)
	(
		assert_int(world.flow.field(world.field[0]).best_neighbour(world.cell_of(11500, 4500)))
		. is_equal(key)
	)
	world.set_terrain(key, ROCK)
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([1, -1])
	assert_int(world.flow.key_goal[1]).is_equal(world.cell_of(14500, 4500))
	FlowCache.run(world, 100000)
	Movement.integrate(world)
	assert_bool(world.is_passable(world.nav_next[0], TRACKED)).is_true()
	assert_int(world.nav_next[0]).is_not_equal(key)


## A unit whose goal is the rock key tile has no field to change to: NO_NEXT stays, the field stays
## and no slot is taken. It stalls like any unit that cannot get closer (test_movement_stall.gd).
func test_a_unit_whose_goal_is_the_rock_key_tile_keeps_no_next_tile_and_takes_no_field(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	var key: int = world.cell_of(12500, 4500)
	_hold(world, 0, 11500, 4500, 12500, 4500, key)
	world.set_terrain(key, ROCK)
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([0, Movement.NO_NEXT])
	assert_int(world.flow.status.count(FlowCache.Status.FREE)).is_equal(7)


## Only the key counts: a next tile that is rock but not the key keeps the old field's answer, so
## that a map change does not send every unit looking for a new field before the cache has swapped
## the re-integrated one in (test_movement_fields.gd runs that). The unit stands next to rock that
## is on the way to the key, two tiles on.
func test_a_rock_tile_on_the_way_that_is_not_the_key_stays_the_next_tile(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _world(8, impl)
	_hold(world, 0, 11500, 4500, 14500, 4500, world.cell_of(13500, 4500))
	var on_the_way: int = world.cell_of(12500, 4500)
	world.set_terrain(on_the_way, ROCK)
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([0, on_the_way])


## "Blocked" is the class of the unit's: a key tile of scrub is rock to a tank and open ground to a
## foot soldier. Two units stand next to it on fields keyed on it, a tank (type 0) and a soldier
## (type 1): the tank finds no next tile and takes the field of its own goal's tile; the soldier
## goes on to the key.
func test_a_key_tile_is_blocked_for_the_class_of_the_unit_that_asks(
	impl: int, _test_parameters := _both()
) -> void:
	var rock: Array[Vector2i] = []
	for row: int in 11:
		rock.append(Vector2i(8, row))
	var world: World = _in(
		GridWorld.from_rows(GridWorld.grass(20, 12, rock), [TRACKED, FOOT]), impl
	)
	world.flow_cache_size = 8
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), 8)
	var key: int = world.cell_of(12500, 4500)
	_hold(world, 0, 11500, 4500, 14500, 4500, key, 0)
	_hold(world, 1, 11500, 4500, 14500, 4500, key, 1)
	world.set_terrain(key, SCRUB)
	Movement.integrate(world)
	assert_int(world.nav_next[0]).is_equal(-1)
	assert_int(world.flow.key_goal[world.field[0]]).is_equal(world.cell_of(14500, 4500))
	assert_int(world.nav_next[1]).is_equal(key)
	assert_int(world.flow.key_goal[world.field[1]]).is_equal(key)


## Hand-set unit `row` (the first unit of a World, or the next) of unit type `type` on a MOVE order
## from (x, y) to (goal_x, goal_y), FIELD on the complete field of its class keyed on `key`, with
## `nav_next` -1. Its tile is the key's in most cases, so integrate asks `best_neighbour` for the
## key tile itself.
func _hold(
	world: World, row: int, x: int, y: int, goal_x: int, goal_y: int, key: int, type: int = 0
) -> void:
	world.add_unit(1, type, x, y)
	world.order[row] = MOVE
	world.goal_x[row] = goal_x
	world.goal_y[row] = goal_y
	world.group_cell[row] = key
	Movement.reset_nav(world, PackedInt32Array([row]), World.NavMode.DIRECT)
	world.nav_mode[row] = FIELD
	world.field[row] = world.flow.acquire(key, world.type_move_class[type], world.map_version, 0)
	world.nav_cell[row] = world.cell_of(x, y)
	FlowCache.run(world, 100000)
	assert_bool(world.flow.field(world.field[row]).complete).is_true()


## 20 x 12, a wall in column 8 (rows 0 to 10), a cache of `slots` fields.
func _world(slots: int, impl: int) -> World:
	var rock: Array[Vector2i] = []
	for row: int in 11:
		rock.append(Vector2i(8, row))
	var world: World = _in(GridWorld.from_rows(GridWorld.grass(20, 12, rock)), impl)
	world.flow_cache_size = slots
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), slots)
	return world


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## `world` running `impl`: the kernels attached and INTEGRATE in the implementation asked for.
func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.INTEGRATE)).is_empty()
	return world
