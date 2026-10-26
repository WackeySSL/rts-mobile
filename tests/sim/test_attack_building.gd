extends GdUnitTestSuite
## The ATTACK approach point (plan row P71b, ADR 0017 section 1): an ATTACK on a building aims each
## unit at the centre of the nearest passable ring tile (`Buildings.approach_point`, written once by
## `Sim._apply_attack`), TARGETING's lock leaves that goal alone for a target that stands still
## (both twins), `World.add_building` re-picks it when a footprint lands on it, and the unit walks
## to weapon range and holds, whatever the footprint, behind rock too, under both implementations.
## The artillery check of the plan (P68c) is here too: an artillery unit fires and holds at range
## before it reaches an approach point that lies inside its `min_range`.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TICKS: int = 700
const SIZES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## One parameter set per implementation and footprint size.
func _sizes() -> Array[Array]:
	var sets: Array[Array] = []
	for impl: int in SimImpls.IMPLS:
		for size: Vector2i in SIZES:
			sets.append([impl, size])
	return sets


func _step_with(world: World, command: Command) -> MatchLoop:
	var loop: MatchLoop = MatchLoop.create(null, "", 0, world)
	loop.step(world, [command] as Array[Command])
	return loop


func _ids_of(world: World, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_speed[world.type_index[row]] > 0:
			ids.append(world.unit_id[row])
	return ids


func _goal(world: World, row: int) -> Vector2i:
	return Vector2i(world.goal_x[row], world.goal_y[row])


## Whether the milli point (x, y) is the centre of a tile of the ring of `row`'s footprint:
## 8-adjacent to it and outside it.
@warning_ignore("integer_division")
func _is_ring_centre(world: World, row: int, x: int, y: int) -> bool:
	var origin: Vector2i = world.footprint_origin(row)
	var type: int = world.type_index[row]
	var width: int = world.type_foot_w[type]
	var height: int = world.type_foot_h[type]
	var col: int = x / 1000
	var line: int = y / 1000
	var inside: bool = (
		col >= origin.x and col < origin.x + width and line >= origin.y and line < origin.y + height
	)
	var near: bool = (
		col >= origin.x - 1
		and col <= origin.x + width
		and line >= origin.y - 1
		and line <= origin.y + height
	)
	return x % 1000 == 500 and y % 1000 == 500 and near and not inside


func test_the_approach_point_is_the_nearest_passable_ring_tile_then_the_lower_index() -> void:
	var rows: PackedStringArray = GridWorld.grass(20, 20, [Vector2i(11, 9)])
	var world: World = Worlds.world(rows)
	var hq: int = world.index_of(
		world.add_building(2, Worlds.type_of(world, "headquarters"), 10, 10)
	)
	var type: int = Worlds.type_of(world, "light_tank")
	var tank: int = world.index_of(world.add_unit(1, type, 4500, 11500))
	# The building spans tiles 10..12 on both axes; its ring is tiles 9..13 outside it.
	assert_vector(Buildings.approach_point(world, tank, hq)).is_equal(Vector2i(9500, 11500))
	world.pos_x[tank] = 11000
	world.pos_y[tank] = 8000  # Above the footprint, between ring tiles (10, 9) and (11, 9).
	assert_vector(Buildings.approach_point(world, tank, hq)).is_equal(Vector2i(10500, 9500))
	world.pos_x[tank] = 11500  # Straight above (11, 9), which is rock: the next nearest.
	assert_vector(Buildings.approach_point(world, tank, hq)).is_equal(Vector2i(10500, 9500))
	world.pos_x[tank] = 9500
	world.pos_y[tank] = 9500  # On a corner tile of the ring.
	assert_vector(Buildings.approach_point(world, tank, hq)).is_equal(Vector2i(9500, 9500))


func test_the_approach_point_skips_tiles_the_class_cannot_enter_and_the_map_edge() -> void:
	var world: World = Worlds.world(GridWorld.grass(12, 12))
	var plant: int = world.index_of(
		world.add_building(2, Worlds.type_of(world, "power_plant"), 0, 0)
	)
	var type: int = Worlds.type_of(world, "light_tank")
	var tank: int = world.index_of(world.add_unit(1, type, 6500, 1500))
	# A 2x2 in the corner has ring tiles (2, 0), (2, 1), (2, 2), (0, 2) and (1, 2) only.
	assert_vector(Buildings.approach_point(world, tank, plant)).is_equal(Vector2i(2500, 1500))
	# Scrub is foot only: a tracked unit's nearest ring tile is the next one, (2, 0) on the tie
	# with (2, 2) (the lower index).
	world.set_terrain(1 * 12 + 2, GridWorld.GROUND.find("^"))
	assert_vector(Buildings.approach_point(world, tank, plant)).is_equal(Vector2i(2500, 500))
	world.type_move_class[type] = World.MoveClass.FOOT
	assert_vector(Buildings.approach_point(world, tank, plant)).is_equal(Vector2i(2500, 1500))


func test_an_attack_with_no_passable_ring_tile_is_dropped_and_counted() -> void:
	var rows: PackedStringArray = GridWorld.grass(12, 12)
	for tile: Vector2i in [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(0, 2)]:
		rows[tile.y] = rows[tile.y].left(tile.x) + "#" + rows[tile.y].substr(tile.x + 1)
	rows[2] = rows[2].left(1) + "^" + rows[2].substr(2)  # The last ring tile: foot only.
	var world: World = Worlds.world(rows)
	var plant: int = world.add_building(2, Worlds.type_of(world, "power_plant"), 0, 0)
	var tank: int = world.add_unit(1, Worlds.type_of(world, "light_tank"), 6500, 6500)
	var rifle: int = world.add_unit(1, Worlds.type_of(world, "rifle_squad"), 6500, 7500)
	var loop: MatchLoop = MatchLoop.create(null, "", 0, world)
	loop.step(world, [Command.attack(1, PackedInt32Array([tank]), plant)] as Array[Command])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.order[world.index_of(tank)]).is_equal(World.Order.IDLE)
	# A foot unit has the scrub tile: the command applies to it and leaves the tank out.
	loop.step(world, [Command.attack(1, PackedInt32Array([tank, rifle]), plant)] as Array[Command])
	assert_int(world.dropped_commands).is_equal(1)
	assert_int(world.order[world.index_of(tank)]).is_equal(World.Order.IDLE)
	assert_int(world.order[world.index_of(rifle)]).is_equal(World.Order.ATTACK)
	assert_vector(_goal(world, world.index_of(rifle))).is_equal(Vector2i(1500, 2500))


func test_the_goal_of_an_attack_on_a_building_is_written_once_and_kept(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.behind_rock(3, 3)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var ids: PackedInt32Array = _ids_of(world, 1)
	var loop: MatchLoop = _step_with(world, Command.attack(1, ids, world.unit_id[0]))
	var goals: Array[Vector2i] = []
	for id: int in ids:
		goals.append(_goal(world, world.index_of(id)))
		assert_bool(_is_ring_centre(world, 0, goals[-1].x, goals[-1].y)).is_true()
	for _tick: int in 60:
		loop.step(world, [] as Array[Command])
	for at: int in ids.size():
		var row: int = world.index_of(ids[at])
		assert_vector(_goal(world, row)).is_equal(goals[at])
		assert_int(world.order[row]).is_equal(World.Order.ATTACK)


func test_a_mobile_target_still_sets_the_goal_every_tick(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.open(24, 12)
	var tank: int = Worlds.type_of(world, "light_tank")
	var hunter: int = world.add_unit(1, tank, 3500, 5500)
	var prey: int = world.add_unit(2, tank, 15500, 5500)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var loop: MatchLoop = _step_with(world, Command.attack(1, PackedInt32Array([hunter]), prey))
	var row: int = world.index_of(hunter)
	var other: int = world.index_of(prey)
	world.order[other] = World.Order.MOVE  # The prey walks, so its position changes every tick.
	world.goal_x[other] = 15500
	world.goal_y[other] = 9500
	for _tick: int in 20:
		var standing: Vector2i = Vector2i(world.pos_x[other], world.pos_y[other])
		loop.step(world, [] as Array[Command])
		# The goal is the target's position as it stood at the start of the tick.
		assert_vector(_goal(world, row)).is_equal(standing)
	assert_int(world.pos_y[other]).is_greater(5500)  # It did walk.


func test_a_target_of_speed_0_without_a_footprint_is_aimed_at_once_and_the_lock_keeps_it(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.open(24, 12)
	var tank: int = Worlds.type_of(world, "light_tank")
	var post: int = Worlds.type_of(world, "rocket_squad")
	world.type_speed[post] = 0  # A post: speed 0 and no footprint.
	var hunter: int = world.add_unit(1, tank, 3500, 5500)
	var target: int = world.add_unit(2, post, 15500, 5500)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var loop: MatchLoop = _step_with(world, Command.attack(1, PackedInt32Array([hunter]), target))
	var row: int = world.index_of(hunter)
	assert_vector(_goal(world, row)).is_equal(Vector2i(15500, 5500))
	world.pos_x[world.index_of(target)] += 2000  # Moved by hand: no rule writes the goal again.
	loop.step(world, [] as Array[Command])
	assert_vector(_goal(world, row)).is_equal(Vector2i(15500, 5500))
	assert_int(world.target[row]).is_equal(target)


func test_a_placement_on_an_attack_goal_re_picks_the_approach_point() -> void:
	var world: World = Worlds.open(24, 12)
	var hq: int = world.add_building(2, Worlds.type_of(world, "headquarters"), 10, 4)
	var type: int = Worlds.type_of(world, "light_tank")
	var near: int = world.add_unit(1, type, 3500, 5500)
	var far: int = world.add_unit(1, type, 3500, 9500)
	_step_with(world, Command.attack(1, PackedInt32Array([near, far]), hq))
	var near_row: int = world.index_of(near)
	var far_row: int = world.index_of(far)
	var far_goal: Vector2i = _goal(world, far_row)
	assert_vector(_goal(world, near_row)).is_equal(Vector2i(9500, 5500))
	var version: int = world.map_version
	world.add_building(1, Worlds.type_of(world, "defence_turret"), 9, 5)
	assert_int(world.map_version).is_equal(version + 1)
	# The tile of the goal is now a footprint: the next nearest ring tile, the lower index on the
	# tie between (9, 4) and (9, 6). The other unit's goal is not in it and stays.
	assert_vector(_goal(world, near_row)).is_equal(Vector2i(9500, 4500))
	assert_vector(_goal(world, far_row)).is_equal(far_goal)
	assert_int(world.order[near_row]).is_equal(World.Order.ATTACK)


func test_an_attack_on_a_building_behind_rock_reaches_weapon_range_and_holds(
	impl: int, size: Vector2i, _test_parameters := _sizes()
) -> void:
	var world: World = Worlds.behind_rock(size.x, size.y)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var building: int = world.unit_id[0]
	var ids: PackedInt32Array = _ids_of(world, 1)
	var loop: MatchLoop = _step_with(world, Command.attack(1, ids, building))
	for _tick: int in TICKS:
		loop.step(world, [] as Array[Command])
	var weapon: int = world.type_weapon[world.type_index[world.index_of(ids[0])]]
	var reach: int = world.weapon_range[weapon]
	for id: int in ids:
		var row: int = world.index_of(id)
		var dx: int = world.pos_x[row] - world.pos_x[0]
		var dy: int = world.pos_y[row] - world.pos_y[0]
		assert_int(world.order[row]).is_equal(World.Order.ATTACK)
		assert_int(world.nav_mode[row]).is_equal(World.NavMode.HOLD)
		assert_int(world.target[row]).is_equal(building)
		assert_bool(dx * dx + dy * dy <= reach * reach).is_true()
	assert_int(world.hp[0]).is_less(world.type_max_hp[world.type_index[0]])


## The artillery check (plan P68c). The building is the Headquarters of player 2, which outlives
## 300 ticks of shells (2,000 hit points, 120 a shell, one every 60 ticks).
func test_an_artillery_unit_fires_and_holds_at_range_before_its_approach_point(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.artillery_range(12000)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var weapon: int = world.type_weapon[0]
	assert_int(world.weapon_range[weapon]).is_equal(9000)
	assert_int(world.weapon_min_range[weapon]).is_equal(3000)
	assert_int(world.type_speed[0]).is_equal(67)
	var gun: int = 1  # The building was added first.
	var loop: MatchLoop = _step_with(
		world, Command.attack(1, PackedInt32Array([world.unit_id[gun]]), world.unit_id[0])
	)
	var approach: Vector2i = _goal(world, gun)
	var close: int = -1  # The first tick that ends with the distance to the centre at 9000 or less.
	var fired: int = -1  # The first tick with a SHOT event.
	for tick: int in 300:
		if tick > 0:
			loop.step(world, [] as Array[Command])
		var dx: int = world.pos_x[gun] - world.pos_x[0]
		var dy: int = world.pos_y[gun] - world.pos_y[0]
		var d2: int = dx * dx + dy * dy
		(
			assert_bool(d2 >= 3000 * 3000)
			. override_failure_message("inside 3000 at %d" % tick)
			. is_true()
		)
		assert_bool(Vector2i(world.pos_x[gun], world.pos_y[gun]) != approach).is_true()
		if close < 0 and d2 <= 9000 * 9000:
			close = tick
		if fired < 0 and _shots(world) > 0:
			fired = tick
		if close >= 0 and tick > close:
			assert_int(world.nav_mode[gun]).override_failure_message("HOLD at %d" % tick).is_equal(
				World.NavMode.HOLD
			)
	assert_int(close).is_greater(0)
	assert_int(fired).is_between(0, close + 1)
	assert_int(world.hp[0]).is_greater(0)


## An artillery unit inside the first ring tile (2,200 from the centre on an axis) does not fire
## and does not back away: it walks to the tile's centre, 2,000 out, and waits there.
func test_an_artillery_unit_inside_min_range_never_fires_and_never_backs_away(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = Worlds.artillery_range(2200)
	assert_array(SimImpls.attach(world, impl, SimProbe.Phase.TARGETING)).is_empty()
	var gun: int = 1
	var loop: MatchLoop = _step_with(
		world, Command.attack(1, PackedInt32Array([world.unit_id[gun]]), world.unit_id[0])
	)
	assert_vector(_goal(world, gun)).is_equal(Vector2i(19500, 11500))
	for tick: int in 300:
		if tick > 0:
			loop.step(world, [] as Array[Command])
		var dx: int = world.pos_x[gun] - world.pos_x[0]
		var dy: int = world.pos_y[gun] - world.pos_y[0]
		assert_bool(dx * dx + dy * dy < 3000 * 3000).is_true()
		assert_int(_shots(world)).override_failure_message("fired at %d" % tick).is_equal(0)
	assert_vector(Vector2i(world.pos_x[gun], world.pos_y[gun])).is_equal(Vector2i(19500, 11500))


func _shots(world: World) -> int:
	var count: int = 0
	var at: int = 0
	while at + World.EVENT_STRIDE <= world.events.size():
		count += int(world.events[at] == World.Event.SHOT)
		at += World.EVENT_STRIDE
	return count
