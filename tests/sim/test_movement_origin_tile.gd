extends GdUnitTestSuite
## Tile (0, 0) is cell 0: a real tile, not a "none" (P37b). Movement's marks are -1 and NO_NEXT
## (-2), so a `nav_next` of 0, the cell a unit stands in and the cell its line was checked in
## (`nav_cell`) are all valid at 0, and each test here fails on a `> 0` where Movement says
## `>= 0`. The crowd that P39b's separation pushes into the top-left corner is the case that
## matters: such a unit must still follow a field through the corner tile and must still stall.
## Maps are built in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FieldCadence: GDScript = preload("res://tests/sim/support/field_cadence.gd")
const MOVE: int = World.Order.MOVE
const IDLE: int = World.Order.IDLE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const TRACKED: int = World.MoveClass.TRACKED


## A 5 x 2 map with a rock at (1, 1): a tank at (500, 1500) in tile (0, 1) is ordered to (3500,
## 1500), straight east, and the only way leads up through the corner tile (0, 0) and along row 0
## (the diagonal from (0, 1) to (1, 0) cuts the rock's corner). In (0, 1) its `nav_next` is cell 0,
## and it steers at the centre of that tile: it goes north, then east, and arrives. A `nav_next` of
## 0 taken for "none" would steer it straight at the goal, into the rock, for good.
func test_a_unit_whose_field_leads_through_the_corner_tile_arrives() -> void:
	var world: World = _corner_world()
	var seen_zero: bool = false
	var north_most: int = 1500
	var arrived_at: int = -1
	for tick: int in 300:
		var commands: Array[Command] = []
		if tick == 0:
			commands.append(_stamped(Command.move(1, PackedInt32Array([1]), 3500, 1500), 0))
		Sim.step(world, commands)
		seen_zero = seen_zero or world.nav_next[0] == 0
		north_most = mini(north_most, world.pos_y[0])
		if world.order[0] == IDLE:
			arrived_at = tick
			break
	assert_bool(seen_zero).is_true()
	assert_int(north_most).is_less(1000)
	assert_int(arrived_at).is_greater(0)
	assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([3500, 1500])


## The same run, counted: `best_neighbour` is asked on the tick the field completes, on every tile
## the unit enters (FieldCadence holds the rule) and on its line-check turns, and `nav_next` equals
## the answer. That includes the tick on which the unit leaves tile 0 for (1, 0): the tile it
## stood in has the number 0.
func test_a_unit_leaving_the_corner_tile_asks_at_the_tile_it_enters() -> void:
	var world: World = _corner_world()
	var order: Command = Command.move(1, PackedInt32Array([1]), 3500, 1500)
	var found: Dictionary = FieldCadence.run(world, order, 300)
	assert_array(found["violations"]).is_empty()
	assert_int(found["entry"]).is_greater(2)
	assert_int(found["completion"]).is_equal(1)
	assert_array([world.pos_x[0], world.pos_y[0], world.order[0]]).is_equal([3500, 1500, IDLE])


## A unit that is held in tile 0 stalls like a unit anywhere else: pushed back by its whole step
## each tick, 400 from its goal in the same tile, its distance is 400 on the first tick and does
## not improve, so it goes IDLE `stall_ticks` ticks later where it stands. A DIRECT unit has
## checked its line in tile 0 (`nav_cell` is 0, not -1); a FIELD unit stands in tile 0 on a
## complete field that names no next tile (`nav_next` is NO_NEXT). Neither is vacuous: the DIRECT
## unit has `nav_cell` 0 and the FIELD unit `nav_next` NO_NEXT while it is held.
func test_a_unit_held_in_the_corner_tile_stalls_whether_direct_or_following_a_field() -> void:
	for mode: int in [DIRECT, FIELD]:
		var kind: String = "DIRECT" if mode == DIRECT else "FIELD"
		var world: World = GridWorld.from_rows(GridWorld.grass(5, 3))
		world.add_unit(1, 0, 500, 500)
		world.order[0] = MOVE
		world.goal_x[0] = 900
		world.goal_y[0] = 500
		Movement.reset_nav(world, PackedInt32Array([0]), DIRECT)
		if mode == FIELD:
			# A field of the goal's own tile, already followed: the unit has no tile to go to.
			world.nav_mode[0] = FIELD
			world.nav_cell[0] = 0
			assert_int(world.flow.acquire(0, TRACKED, world.map_version, 0)).is_equal(0)
			world.field[0] = 0
		var first: int = -1
		var idle_at: int = -1
		for tick: int in 60:
			world.push_x[0] = -120
			Sim.step(world, [])
			var label: String = "%s, tick %d" % [kind, tick]
			if first == -1 and world.best_dist[0] != FlowField.UNREACHED:
				first = tick
				var marks: Array[int] = [world.nav_cell[0], world.nav_next[0]]
				var expected: Array[int] = [0, -1]
				if mode == FIELD:
					expected = [0, Movement.NO_NEXT]
					assert_int(world.flow.field(0).best_neighbour(0)).is_equal(-1)
				assert_array(marks).override_failure_message(label).is_equal(expected)
			if world.order[0] == IDLE:
				idle_at = tick
				break
		assert_int(first).override_failure_message(kind).is_greater(-1)
		assert_int(idle_at - first).override_failure_message(kind).is_equal(world.stall_ticks)
		# The goal is where it stood when it stalled; that tick's push still moved it.
		assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([500, 500])
		assert_array([world.pos_x[0], world.pos_y[0]]).is_equal([380, 500])
		assert_array([world.field[0], world.nav_mode[0], world.nav_next[0]]).is_equal(
			[-1, World.NavMode.NONE, -1]
		)


## The corner map: 5 x 2 tiles, rock at (1, 1), one tank at (500, 1500).
func _corner_world() -> World:
	var world: World = GridWorld.from_rows(GridWorld.grass(5, 2, [Vector2i(1, 1)]))
	world.add_unit(1, 0, 500, 1500)
	return world


func _stamped(command: Command, tick: int) -> Command:
	command.tick = tick
	return command
