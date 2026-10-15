extends GdUnitTestSuite
## A unit whose own slot cannot be reached from its group's target (P37b; ADR 0008 section 3, lead
## decision of 2026-10-15). The group's field is keyed on the group target, so a unit with a goal
## elsewhere follows it only to the group target, or as far as the field names a next tile. When
## `Movement.integrate` finds the field complete and naming no tile (NO_NEXT) on a field keyed on a
## tile other than the unit's goal's, the unit takes the field of its own goal tile
## (`_take_own_field`): the new slot and `nav_next` -1 (looked up at the next event). With every
## slot referenced it keeps its field and NO_NEXT and asks again at its next turn. The cases call
## `integrate` on its own with hand-set state (zero intents, so no unit leaves its tile); the whole
## run through a thin wall is in test_movement_fields.gd. Maps are built in code (GridWorld).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const TRACKED: int = World.MoveClass.TRACKED
const MOVE: int = World.Order.MOVE
const FIELD: int = World.NavMode.FIELD


## A unit stands on the tile its group field is keyed on, 2000 from its own goal. The field is
## complete and names no tile for the key tile itself, so the unit takes the field of its goal's
## tile: slot 1, keyed on that tile, `nav_next` -1. Once that field is complete the next event
## gives it a tile on the way (13, 4), and the unit keeps the field of its own tile from then on.
func test_a_group_field_naming_no_tile_gives_the_unit_the_field_of_its_own_goal_tile() -> void:
	var world: World = _world(8)
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
func test_a_unit_on_the_field_of_its_own_goal_tile_takes_no_other_field() -> void:
	var world: World = _world(8)
	_hold(world, 0, 12500, 4500, 12900, 4500, world.cell_of(12500, 4500))
	Movement.integrate(world)
	assert_array([world.field[0], world.nav_next[0]]).is_equal([0, Movement.NO_NEXT])
	assert_int(world.flow.status.count(FlowCache.Status.FREE)).is_equal(7)


## The new slot may be slot 0: a cache of two slots, slot 0 held by a field nobody follows, the
## group's field in slot 1. The own goal tile takes the unreferenced slot 0 (the field in it is
## replaced), and the unit follows it.
func test_the_unit_takes_slot_0_when_that_is_the_one_nobody_follows() -> void:
	var world: World = _world(2)
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
func test_with_every_slot_referenced_the_unit_keeps_its_field_and_asks_again_on_its_turn() -> void:
	var world: World = _world(2)
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


## Hand-set unit `row` (the first unit of a World, or the next) of the tank type on a MOVE order
## from (x, y) to (goal_x, goal_y), FIELD on the complete field keyed on `key`, with `nav_next` -1.
## Slot 0 is the field's; its tile is the unit's own, so integrate asks `best_neighbour` for the
## key tile itself.
func _hold(world: World, row: int, x: int, y: int, goal_x: int, goal_y: int, key: int) -> void:
	world.add_unit(1, 0, x, y)
	world.order[row] = MOVE
	world.goal_x[row] = goal_x
	world.goal_y[row] = goal_y
	world.group_cell[row] = key
	Movement.reset_nav(world, PackedInt32Array([row]), World.NavMode.DIRECT)
	world.nav_mode[row] = FIELD
	world.field[row] = world.flow.acquire(key, TRACKED, world.map_version, 0)
	world.nav_cell[row] = world.cell_of(x, y)
	FlowCache.run(world, 100000)
	assert_bool(world.flow.field(world.field[row]).complete).is_true()


## 20 x 12, a wall in column 8 (rows 0 to 10), a cache of `slots` fields.
func _world(slots: int) -> World:
	var rock: Array[Vector2i] = []
	for row: int in 11:
		rock.append(Vector2i(8, row))
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 12, rock))
	world.flow.configure(world.map_cols, world.map_rows, World.MoveClass.size(), slots)
	return world
