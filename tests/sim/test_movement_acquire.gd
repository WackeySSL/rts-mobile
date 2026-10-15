extends GdUnitTestSuite
## What Movement asks the flow cache for (P37b; ADR 0008 section 3): the move class of the unit, the
## tick and the map version of every acquire(). The class decides which terrain the field avoids,
## the tick decides which unreferenced slot the cache evicts (`last_used`), and the map version
## decides whether a key matches. Every case reads the cache's columns (`key_class`, `key_version`,
## `last_used`, `key_goal`) after the call, on a World whose map version is above 0 (GridWorld's
## set_terrain calls make it so) and at a tick above 0, so that a literal 0 in place of the World's
## value shows. Scrub is the terrain that tells the classes apart: open to foot units, closed to
## tanks. Maps are built in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FOOT: int = World.MoveClass.FOOT
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD


## A tank ordered to attack a target behind a wall (20 x 12 map, column 8 rock in rows 0 to 10
## except one scrub tile in row 5, open ground in row 11) must take the field of its own class,
## which leads round the wall's end through row 11. A foot field would lead it through the scrub,
## where the tank stops for good. The first acquire is at the tick of the line check, for the
## target's tile, class TRACKED and the World's map version; the tank is never on scrub or rock
## and ends on its target.
func test_an_attack_unit_takes_the_field_of_its_own_class_round_the_scrub() -> void:
	var world: World = GridWorld.from_rows(_scrub_gate_map())
	world.player_count = 2
	world.type_weapon[0] = 0
	world.add_unit(1, 0, 3500, 5500)
	world.add_unit(2, 0, 14500, 5500)
	assert_int(world.map_version).is_greater(0)
	var order: Command = Command.attack(1, PackedInt32Array([1]), 2)
	var taken_at: int = -1
	for tick: int in 600:
		var before: int = world.tick
		Sim.step(world, _given(order, tick))
		var cell: int = world.cell_of(world.pos_x[0], world.pos_y[0])
		(
			assert_bool(world.is_passable(cell, TRACKED))
			. override_failure_message("tick %d" % tick)
			. is_true()
		)
		if taken_at == -1 and world.field[0] >= 0:
			taken_at = before
			var slot: int = world.field[0]
			var flow: FlowCache = world.flow
			(
				assert_array([flow.key_class[slot], flow.key_version[slot], flow.last_used[slot]])
				. is_equal([TRACKED, world.map_version, before])
			)
			assert_int(flow.key_goal[slot]).is_equal(world.cell_of(14500, 5500))
		if world.pos_x[0] == 14500 and world.pos_y[0] == 5500:
			break
	assert_int(taken_at).is_greater(0)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([14500, 5500, ATTACK])


## An ATTACK unit re-keys when its goal is more than `attack_rekey_milli` from the tile its field is
## keyed on, and takes the field of the new tile for its own class, the tick it asks and the map
## version, whichever event finds the goal moved: the lookup before the step (`nav_next` -1 on a
## complete field), or the tile the step enters. Each case calls `integrate` on a hand-set tank on
## a complete TRACKED field with its goal moved 5000 south, at tick 7 (no line-check turn for
## unit 1).
func test_an_attack_rekey_takes_the_field_of_the_units_class_at_both_events() -> void:
	for on_entry: bool in [false, true]:
		var world: World = GridWorld.from_rows(_scrub_gate_map())
		world.add_unit(1, 0, 3950, 5500)
		world.order[0] = ATTACK
		world.goal_x[0] = 14500
		world.goal_y[0] = 5500
		Movement.reset_nav(world, PackedInt32Array([0]), DIRECT)
		var old: int = world.flow.acquire(world.cell_of(14500, 5500), TRACKED, world.map_version, 0)
		world.field[0] = old
		world.nav_mode[0] = FIELD
		FlowCache.run(world, 100000)
		assert_bool(world.flow.field(old).complete).is_true()
		world.goal_y[0] = 10500
		world.tick = 7
		var label: String = "on a tile entry" if on_entry else "before the step"
		if on_entry:
			# A next tile is known and the tick is no turn; the step crosses from tile 3 into 4.
			world.nav_next[0] = 5 * 20 + 4
			world.intent_x[0] = 100
		else:
			world.nav_next[0] = -1
		Movement.integrate(world)
		var fresh: int = world.field[0]
		assert_int(fresh).override_failure_message(label).is_not_equal(old)
		assert_int(world.cell_of(world.pos_x[0], world.pos_y[0])).is_equal(
			5 * 20 + (4 if on_entry else 3)
		)
		var flow: FlowCache = world.flow
		(
			assert_array([flow.key_class[fresh], flow.key_version[fresh], flow.last_used[fresh]])
			. override_failure_message(label)
			. is_equal([TRACKED, world.map_version, 7])
		)
		assert_int(flow.key_goal[fresh]).override_failure_message(label).is_equal(
			world.cell_of(14500, 10500)
		)


## The three ways a line check asks for a field, each at a tick above 0 on a World with a map
## version above 0, for class TRACKED: a goal nobody has a field for takes the field of its own tile
## (tick 4); a goal 1000 from a held key, in sight of it, shares that slot and refreshes its
## `last_used` to the tick of the sharing (tick 8, not the tick of the first acquire); an ATTACK
## unit takes the field of its goal's tile (tick 12). Unit n checks on the ticks where
## (tick + n) % 5 == 0, and `Movement.run` is called on its own at the ticks chosen.
func test_a_field_is_acquired_at_the_tick_and_map_version_of_the_check() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, _wall(10)))
	assert_int(world.map_version).is_greater(0)
	var starts: Array[Vector2i] = [Vector2i(3500, 2500), Vector2i(3500, 4500), Vector2i(3500, 6500)]
	var goals: Array[Vector2i] = [
		Vector2i(14500, 3500), Vector2i(14500, 4500), Vector2i(14500, 7500)
	]
	for index: int in 3:
		world.add_unit(1, 0, starts[index].x, starts[index].y)
		world.order[index] = ATTACK if index == 2 else MOVE
		world.goal_x[index] = goals[index].x
		world.goal_y[index] = goals[index].y
	Movement.reset_nav(world, PackedInt32Array([0, 1, 2]), DIRECT)
	var flow: FlowCache = world.flow
	world.tick = 4
	Movement.run(world)
	assert_array([world.nav_mode[0], world.field[0], world.nav_mode[1]]).is_equal(
		[FIELD, 0, DIRECT]
	)
	_assert_slot(world, 0, world.cell_of(14500, 3500), 4)
	world.tick = 8
	Movement.run(world)
	assert_array([world.nav_mode[1], world.field[1]]).is_equal([FIELD, 0])
	assert_int(flow.key_goal[1]).is_equal(0)
	_assert_slot(world, 0, world.cell_of(14500, 3500), 8)
	world.tick = 12
	Movement.run(world)
	assert_array([world.nav_mode[2], world.field[2]]).is_equal([FIELD, 1])
	_assert_slot(world, 1, world.cell_of(14500, 7500), 12)


## The line check on a tile entry uses the move class of the unit that enters it, not of unit 0's
## type. A map 14 x 7 with one rock tile (4, 3) and scrub across columns 8 and 9; type 0 is TRACKED
## and type 1 FOOT. A foot soldier ordered along row 3 has its line blocked by the rock and takes a
## field round it; as soon as it stands in row 2 its line is clear for foot units (scrub is no
## obstacle to them), so on that tile entry it is DIRECT with no field, at x 3185 and well before
## the scrub at 8000. Checked with the tank's class the scrub would block the line and keep the
## soldier on its field until it had passed the scrub.
func test_a_unit_checks_its_line_for_its_own_class_when_it_enters_a_tile() -> void:
	var map: PackedStringArray = GridWorld.grass(14, 7, [Vector2i(4, 3)])
	for row: int in 7:
		map[row] = map[row].left(8) + "^^" + map[row].substr(10)
	var world: World = GridWorld.from_rows(map, [TRACKED, FOOT])
	world.add_unit(1, 1, 1500, 3500)
	var order: Command = Command.move(1, PackedInt32Array([1]), 12500, 3500)
	var fielded: bool = false
	var switched_at: int = -1
	for tick: int in 300:
		Sim.step(world, _given(order, tick))
		fielded = fielded or world.nav_mode[0] == FIELD
		if fielded and switched_at == -1 and world.nav_mode[0] == DIRECT:
			switched_at = world.pos_x[0]
			assert_array([world.field[0], world.nav_next[0]]).is_equal([-1, -1])
		if world.order[0] == IDLE:
			break
	assert_bool(fielded).is_true()
	assert_int(switched_at).is_between(2000, 7000)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([12500, 3500, IDLE])


## A slot's key, last use and map version, as one acquire() leaves them.
func _assert_slot(world: World, slot: int, goal_cell: int, tick: int) -> void:
	var flow: FlowCache = world.flow
	(
		assert_array(
			[
				flow.key_goal[slot],
				flow.key_class[slot],
				flow.key_version[slot],
				flow.last_used[slot]
			]
		)
		. is_equal([goal_cell, TRACKED, world.map_version, tick])
	)


## A 20 x 12 map: column 8 is rock in rows 0 to 10 except scrub in row 5, row 11 is open.
func _scrub_gate_map() -> PackedStringArray:
	var map: PackedStringArray = GridWorld.grass(20, 12, _wall(11))
	map[5] = map[5].left(8) + "^" + map[5].substr(9)
	return map


## A wall in column 8, rows 0 to `rows` - 1.
func _wall(rows: int) -> Array[Vector2i]:
	var rock: Array[Vector2i] = []
	for row: int in rows:
		rock.append(Vector2i(8, row))
	return rock


## The commands of tick `tick`: `order` on tick 0, none after.
func _given(order: Command, tick: int) -> Array[Command]:
	var commands: Array[Command] = []
	if tick == 0:
		order.tick = 0
		commands.append(order)
	return commands
