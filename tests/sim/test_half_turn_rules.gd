extends GdUnitTestSuite
## The world-fixed rules of the sim are half-turn equivariant (ADR 0033, P195d2): apply a rule to a
## state and to the state turned half a turn about the map centre, and the results are each other's
## half turn, so that neither start corner of a map that is its own half turn has an edge from a
## scan that starts in the north west or from a `floor` on a tile border. One case and its half turn
## per rule, the turn being (x, y) -> (W - x, H - y) on a map W x H milli-tiles, tile (c, r) ->
## (cols - 1 - c, rows - 1 - r), cell -> cells - 1 - cell:
## - FixedMath.centre_side and World.cell_of (a point on a tile border is in the tile on the map
##   centre's side), and the fog stamp tile, under both implementations of FOG;
## - FixedMath.line_clear on segments with an end on a border;
## - Formation.assign: slot order, unit pick and the open centre of a target on rock;
## - Harvest's ore pick on an equal distance.
## The flow field's equal-cost step is in test_flow_tiebreak, its kernel in
## tests/sim/native/test_flow_tiebreak_lockstep.gd.
## A point that is itself a fixed point of the turn (on both centre lines of the map) has no tile
## that maps to itself: there the rules take one fixed answer, the tile to the +x/+y side for a
## border on a centre line (centre_side leaves it alone), and the first in list order for an ore
## cell tie when the point is the centre (no way to prefer either).

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const Worlds: GDScript = preload("res://tests/sim/support/harvest_worlds.gd")
const FogWorlds: GDScript = preload("res://tests/sim/support/fog_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const TILE: int = World.MILLI_PER_TILE
const FOG: int = SimProbe.Phase.FOG
const FOG_COLS: int = 30
const FOG_MAP: int = 30000


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The half turn of a point on a map of `size` milli-tiles.
func _turn(point: Vector2i, size: Vector2i) -> Vector2i:
	return size - point


## The half turn of a tile of a map of `shape` tiles.
func _turn_tile(tile: Vector2i, shape: Vector2i) -> Vector2i:
	return shape - Vector2i.ONE - tile


## `tiles` turned half a turn on a map of `shape` tiles.
func _turned_tiles(tiles: Array[Vector2i], shape: Vector2i) -> Array[Vector2i]:
	var turned: Array[Vector2i] = []
	for tile: Vector2i in tiles:
		turned.append(_turn_tile(tile, shape))
	return turned


func test_a_coordinate_on_a_border_belongs_to_the_tile_on_the_centre_side() -> void:
	# A map 10 tiles wide: the middle is 5000. Borders before it keep their tile (the one after the
	# border), borders past it give up a milli (the one before the border), the middle itself, on
	# the centre line, stays (the tile after it).
	assert_int(FixedMath.centre_side(3000, 10000)).is_equal(3000)
	assert_int(FixedMath.centre_side(7000, 10000)).is_equal(6999)
	assert_int(FixedMath.centre_side(5000, 10000)).is_equal(5000)
	assert_int(FixedMath.centre_side(10000, 10000)).is_equal(9999)
	assert_int(FixedMath.centre_side(0, 10000)).is_equal(0)
	# Off a border nothing moves, wherever it is.
	for coord: int in [1, 3500, 4999, 5001, 6999, 7001, 9999]:
		assert_int(FixedMath.centre_side(coord, 10000)).is_equal(coord)
	# The tile of a point and of its half turn are each other's half turn, off the centre lines.
	for x: int in range(0, 10001, 500):
		if x == 5000:
			continue
		var tile: int = FixedMath.centre_side(x, 10000) / TILE
		var turned: int = FixedMath.centre_side(10000 - x, 10000) / TILE
		assert_int(mini(turned, 9)).override_failure_message("x %d" % x).is_equal(9 - mini(tile, 9))


func test_cell_of_a_point_and_of_its_half_turn_are_half_turned_cells() -> void:
	for shape: Vector2i in [Vector2i(10, 8), Vector2i(7, 12)]:
		var world: World = GridWorld.from_rows(GridWorld.grass(shape.x, shape.y))
		var size: Vector2i = shape * TILE
		var cells: int = shape.x * shape.y
		var checked: int = 0
		for x: int in range(0, size.x + 1, 500):
			for y: int in range(0, size.y + 1, 500):
				if x * 2 == size.x or y * 2 == size.y:
					continue
				var point: Vector2i = Vector2i(x, y)
				var turned: Vector2i = _turn(point, size)
				(
					assert_int(world.cell_of(turned.x, turned.y))
					. override_failure_message("%s on %s" % [point, shape])
					. is_equal(cells - 1 - world.cell_of(point.x, point.y))
				)
				checked += 1
		assert_int(checked).is_greater(100)


## On a centre line the turn has no tile to map to: a border on the line is in the tile after it.
func test_a_border_on_a_centre_line_is_in_the_tile_after_it() -> void:
	var world: World = GridWorld.from_rows(GridWorld.grass(10, 8))
	assert_int(world.cell_of(5000, 500)).is_equal(5)
	assert_int(world.cell_of(500, 4000)).is_equal(4 * 10)
	assert_int(world.cell_of(5000, 4000)).is_equal(4 * 10 + 5)


## Units standing on tile borders and on their half turns are stamped in half-turned fog cells, and
## the fog they make is the half turn of itself, so `Targeting.sees` agrees at border points.
func test_the_fog_stamp_tile_of_a_unit_on_a_border_is_half_turned(
	impl: int, _test_parameters := _both()
) -> void:
	var spots: Array[Vector2i] = [
		Vector2i(8000, 10000), Vector2i(4000, 4000), Vector2i(12000, 22000), Vector2i(0, 7000)
	]
	var size: Vector2i = Vector2i(FOG_MAP, FOG_MAP)
	var units: Array = []
	for _spot: int in spots.size() * 2:
		units.append([1, 0, 15500, 15500])
	var members: Dictionary = {&"fog_period_ticks": 1}
	var world: World = FogWorlds.field(FOG_COLS, FOG_COLS, 1, [3000], units, members)
	assert_array(SimImpls.attach(world, impl, FOG)).is_empty()
	# Every unit steps from the middle to its border point, which its player's FOG turn stamps.
	for index: int in spots.size():
		var turned: Vector2i = _turn(spots[index], size)
		world.pos_x[index * 2] = spots[index].x
		world.pos_y[index * 2] = spots[index].y
		world.pos_x[index * 2 + 1] = turned.x
		world.pos_y[index * 2 + 1] = turned.y
	Sim.step(world, [])
	var cells: int = FOG_COLS * FOG_COLS
	for pair: int in spots.size():
		var cell: int = world.fog_cell[pair * 2]
		var image: int = world.fog_cell[pair * 2 + 1]
		assert_int(cell).override_failure_message("unit pair %d" % pair).is_greater_equal(0)
		assert_int(image).override_failure_message("unit pair %d" % pair).is_equal(cells - 1 - cell)
	var visible: PackedInt32Array = world.fog.visible.slice(0, cells)
	for cell: int in cells:
		assert_int(visible[cells - 1 - cell]).override_failure_message("cell %d" % cell).is_equal(
			visible[cell]
		)
	for x: int in range(0, FOG_MAP + 1, 1000):
		for y: int in range(0, FOG_MAP + 1, 1000):
			if x * 2 == FOG_MAP or y * 2 == FOG_MAP:
				continue
			var turned: Vector2i = _turn(Vector2i(x, y), size)
			(
				assert_bool(Targeting.sees(world, 1, turned.x, turned.y))
				. override_failure_message("%d, %d" % [x, y])
				. is_equal(Targeting.sees(world, 1, x, y))
			)


## A unit on a centre line is stamped in the tile past the middle: a point on both lines is its own
## half turn, so no rule can keep both it and its image, and the border rule leaves the pair rule
## (the half-turn tests above) to the points off the lines. The unit at the middle (15000, 15000) of
## the 30 x 30 map takes the cell 15 * 30 + 15, on a centre line in x only (15000, 10500) the column
## 15 and in y only (10500, 15000) the line 15 (the follow-up row of ADR 0033 for a pinwheel tie).
func test_the_fog_stamp_tile_of_a_unit_on_a_centre_line_is_the_one_past_the_middle(
	impl: int, _test_parameters := _both()
) -> void:
	var spots: Array[Vector2i] = [
		Vector2i(15000, 15000), Vector2i(15000, 10500), Vector2i(10500, 15000)
	]
	var expected: Array[int] = [15 * FOG_COLS + 15, 10 * FOG_COLS + 15, 15 * FOG_COLS + 10]
	var units: Array = []
	for _spot: int in spots.size():
		units.append([1, 0, 15500, 15500])
	var members: Dictionary = {&"fog_period_ticks": 1}
	var world: World = FogWorlds.field(FOG_COLS, FOG_COLS, 1, [3000], units, members)
	assert_array(SimImpls.attach(world, impl, FOG)).is_empty()
	for index: int in spots.size():
		world.pos_x[index] = spots[index].x
		world.pos_y[index] = spots[index].y
	Sim.step(world, [])
	for index: int in spots.size():
		assert_int(world.fog_cell[index]).override_failure_message(str(spots[index])).is_equal(
			expected[index]
		)
		assert_bool(Targeting.sees(world, 1, spots[index].x, spots[index].y)).is_true()


## A segment with an end on a border is as clear on a map with one rock tile as its half turn is on
## the half-turned map: every rock tile of a 6 x 6 map, every segment of the list, both ways round.
## The ends are on borders before and past the middle (3000), and the cases include ends that the
## floor would put in the tile after the border and so on the rock.
func test_line_clear_with_an_end_on_a_border_is_half_turned() -> void:
	var shape: Vector2i = Vector2i(6, 6)
	var size: Vector2i = shape * TILE
	var segments: Array[Array] = [
		[Vector2i(1000, 2500), Vector2i(4000, 2500)],
		[Vector2i(500, 4000), Vector2i(500, 1000)],
		[Vector2i(2000, 500), Vector2i(2000, 5000)],
		[Vector2i(1500, 1000), Vector2i(4500, 2000)],
		[Vector2i(2500, 2000), Vector2i(4000, 5000)],
		[Vector2i(1000, 1000), Vector2i(2500, 4000)],
		[Vector2i(1500, 2000), Vector2i(2500, 2000)],
		[Vector2i(4000, 4000), Vector2i(4000, 4000)],
	]
	var blocked: int = 0
	var cases: int = 0
	for cell: int in shape.x * shape.y:
		var rock: Array[Vector2i] = [Vector2i(cell % shape.x, cell / shape.x)]
		var world: World = GridWorld.from_rows(GridWorld.grass(shape.x, shape.y, rock))
		var turned_world: World = GridWorld.from_rows(
			GridWorld.grass(shape.x, shape.y, _turned_tiles(rock, shape))
		)
		for segment: Array in segments:
			var a: Vector2i = segment[0]
			var b: Vector2i = segment[1]
			var image_a: Vector2i = _turn(a, size)
			var image_b: Vector2i = _turn(b, size)
			var clear: bool = FixedMath.line_clear(world, a.x, a.y, b.x, b.y, 2)
			(
				assert_bool(
					FixedMath.line_clear(
						turned_world, image_a.x, image_a.y, image_b.x, image_b.y, 2
					)
				)
				. override_failure_message("rock %s, segment %s to %s" % [rock[0], a, b])
				. is_equal(clear)
			)
			cases += 1
			blocked += 0 if clear else 1
	assert_int(blocked).is_between(cases / 20, cases / 2)


## A group and its half turn on a map with some rock: each unit's goal is the half turn of the goal
## of its image. The cases are lattice aligned so that distances tie everywhere: the slot order (the
## ring-2 points that tie at squared distance 5, the ones at 8 and 10 with a 30 unit group), the
## unit picked for a slot, and the open centre of a target on rock.
func test_formation_goals_of_a_group_and_of_its_half_turn_are_half_turned() -> void:
	var shape: Vector2i = Vector2i(24, 18)
	var size: Vector2i = shape * TILE
	var cases: Array[Dictionary] = [
		# the units (columns, rows, step, first position), the target, the rock tiles
		{
			"count": 30,
			"columns": 6,
			"step": 1500,
			"from": Vector2i(2500, 3500),
			"to": Vector2i(15500, 9500),
			"rock": []
		},
		{
			"count": 13,
			"columns": 4,
			"step": 1200,
			"from": Vector2i(2400, 12000),
			"to": Vector2i(11000, 5400),
			"rock": []
		},
		{
			"count": 9,
			"columns": 3,
			"step": 1200,
			"from": Vector2i(19200, 3600),
			"to": Vector2i(8400, 12000),
			"rock": []
		},
		{
			"count": 1,
			"columns": 1,
			"step": 0,
			"from": Vector2i(2500, 2500),
			"to": Vector2i(15500, 9500),
			"rock": [Vector2i(15, 9)]
		},
		{
			"count": 5,
			"columns": 5,
			"step": 1000,
			"from": Vector2i(2500, 2500),
			"to": Vector2i(15500, 9500),
			"rock": [Vector2i(15, 9), Vector2i(14, 9), Vector2i(15, 8)]
		},
		{
			"count": 7,
			"columns": 7,
			"step": 1000,
			"from": Vector2i(20500, 15500),
			"to": Vector2i(6200, 5800),
			"rock": [Vector2i(6, 5), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 5)]
		},
	]
	for case: Dictionary in cases:
		var rock: Array[Vector2i] = []
		rock.assign(case["rock"])
		var world: World = GridWorld.from_rows(GridWorld.grass(shape.x, shape.y, rock))
		var turned_world: World = GridWorld.from_rows(
			GridWorld.grass(shape.x, shape.y, _turned_tiles(rock, shape))
		)
		var count: int = case["count"]
		var rows: PackedInt32Array = PackedInt32Array()
		var turned_rows: PackedInt32Array = PackedInt32Array()
		for k: int in count:
			var start: Vector2i = (
				case["from"]
				+ Vector2i(k % int(case["columns"]), k / int(case["columns"])) * int(case["step"])
			)
			var turned_start: Vector2i = _turn(start, size)
			world.add_unit(1, 0, start.x, start.y)
			turned_world.add_unit(1, 0, turned_start.x, turned_start.y)
			rows.append(world.unit_count() - 1)
			turned_rows.append(turned_world.unit_count() - 1)
		var target: Vector2i = case["to"]
		var turned_target: Vector2i = _turn(target, size)
		Formation.assign(world, rows, target.x, target.y)
		Formation.assign(turned_world, turned_rows, turned_target.x, turned_target.y)
		var goals: Array[Vector2i] = GridWorld.goals(world, rows)
		var turned_goals: Array[Vector2i] = GridWorld.goals(turned_world, turned_rows)
		for k: int in count:
			(
				assert_that(turned_goals[k])
				. override_failure_message("%d units to %s, unit %d" % [count, target, k])
				. is_equal(_turn(goals[k], size))
			)


## Two ore cells that are as far from the harvester's point as each other: the one further toward
## the map centre is taken, and the pick turns with the map. The small map is 12 x 8 tiles, with ore
## in tiles (3, 2) and (6, 2) and in their half turns (8, 5) and (5, 5).
func test_the_ore_pick_on_an_equal_distance_is_half_turned() -> void:
	var shape: Vector2i = Vector2i(12, 8)
	var size: Vector2i = shape * TILE
	var ore: Array[Vector2i] = [Vector2i(3, 2), Vector2i(6, 2)]
	var points: Array[Vector2i] = [Vector2i(5000, 2500), Vector2i(4500, 1500), Vector2i(3500, 3500)]
	var starts: Array[Vector2i] = [Vector2i(5500, 5500), Vector2i(500, 500), Vector2i(10500, 7500)]
	for index: int in points.size():
		var world: World = Worlds.world(Worlds.grass(shape.x, shape.y, ore))
		var turned_world: World = Worlds.world(
			Worlds.grass(shape.x, shape.y, _turned_tiles(ore, shape))
		)
		world.ore_cell_max = 0
		turned_world.ore_cell_max = 0
		var turned_point: Vector2i = _turn(points[index], size)
		var turned_start: Vector2i = _turn(starts[index], size)
		var id: int = Worlds.add_harvester(world, 1, starts[index].x, starts[index].y, 0)
		var turned_id: int = Worlds.add_harvester(
			turned_world, 1, turned_start.x, turned_start.y, 0
		)
		Worlds.send(
			world, [Command.harvest(1, PackedInt32Array([id]), points[index].x, points[index].y)]
		)
		Worlds.send(
			turned_world,
			[Command.harvest(1, PackedInt32Array([turned_id]), turned_point.x, turned_point.y)]
		)
		var goal: Vector2i = Vector2i(
			world.goal_x[world.index_of(id)], world.goal_y[world.index_of(id)]
		)
		var turned_goal: Vector2i = Vector2i(
			turned_world.goal_x[turned_world.index_of(turned_id)],
			turned_world.goal_y[turned_world.index_of(turned_id)]
		)
		assert_that(turned_goal).override_failure_message("point %s" % points[index]).is_equal(
			_turn(goal, size)
		)


## The scan of SEEK (a harvester with no cell looks at every ore cell) breaks a tie the same way:
## the harvester at (4500, 1500) is 2000 from (2500, 1500) and (6500, 1500) on the 10 x 6 map, and
## its half turn at (5500, 4500) is as far from their half turns. The cell toward the centre wins.
func test_the_seek_scan_on_an_equal_distance_is_half_turned() -> void:
	var shape: Vector2i = Vector2i(10, 6)
	var size: Vector2i = shape * TILE
	var ore: Array[Vector2i] = [Vector2i(2, 1), Vector2i(6, 1)]
	var world: World = Worlds.world(Worlds.grass(shape.x, shape.y, ore))
	var turned_world: World = Worlds.world(
		Worlds.grass(shape.x, shape.y, _turned_tiles(ore, shape))
	)
	world.ore_cell_max = 0
	turned_world.ore_cell_max = 0
	var start: Vector2i = Vector2i(4500, 1500)
	var turned_start: Vector2i = _turn(start, size)
	var id: int = Worlds.add_harvester(world, 1, start.x, start.y)
	var turned_id: int = Worlds.add_harvester(turned_world, 1, turned_start.x, turned_start.y)
	Worlds.step(world, world.harvest_retry_ticks + 1)
	Worlds.step(turned_world, turned_world.harvest_retry_ticks + 1)
	var row: int = world.index_of(id)
	var turned_row: int = turned_world.index_of(turned_id)
	var goal: Vector2i = Vector2i(world.goal_x[row], world.goal_y[row])
	var turned_goal: Vector2i = Vector2i(
		turned_world.goal_x[turned_row], turned_world.goal_y[turned_row]
	)
	assert_that(goal).is_equal(Vector2i(6500, 1500))
	assert_that(turned_goal).is_equal(_turn(goal, size))


## At the centre of the map the way to it is zero, so nothing prefers either cell of a pair that is
## symmetric about it: the first in list order is kept (the answer for a point on both centre
## lines).
func test_the_ore_pick_at_the_map_centre_keeps_the_first_cell() -> void:
	var world: World = Worlds.world(Worlds.grass(10, 6, [Vector2i(2, 2), Vector2i(7, 3)]))
	world.ore_cell_max = 0
	var id: int = Worlds.add_harvester(world, 1, 5000, 3000, 0)
	Worlds.send(world, [Command.harvest(1, PackedInt32Array([id]), 5000, 3000)])
	assert_int(world.harvest_slot[world.index_of(id)]).is_equal(0)
