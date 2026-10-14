extends GdUnitTestSuite
## Formation.assign on maps that are not square, with a unit radius over half a tile, and against
## FixedMath.line_clear (P37a fix 1). The tile rules are in test_formation_tiles on square maps, so
## a mix-up of columns and rows in the tile lookups needs these: every case here runs on a wide
## map (12 x 6) or a tall one (6 x 12). A tile of the map is read from the lattice point by the
## rule of World.cell_of (a point on a tile's left or top edge is in it), and a goal must be a
## point from which every class of the group has a clear line inside its own tile.

const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const FOOT: int = World.MoveClass.FOOT
const WHEELED: int = World.MoveClass.WHEELED
const TRACKED: int = World.MoveClass.TRACKED
const TILE: int = World.MILLI_PER_TILE


## A target on rock moves to the first open tile in ring order on a wide map, for rock at the right
## edge, the bottom edge and the top right corner (a clamp by the wrong dimension, or a lookup that
## reads the wrong row, gives another goal).
func test_a_target_on_rock_moves_to_the_first_open_tile_on_a_wide_map() -> void:
	var cases: Array[Array] = [
		# the rock tiles, the target, the goal of a lone unit
		[[[9, 4]], Vector2i(9500, 4500), Vector2i(8500, 3500)],
		# On the bottom edge: the target (0, 6000) is clamped to (400, 5600), in tile (0, 5).
		[[[0, 5]], Vector2i(0, 6000), Vector2i(500, 4500)],
		# On the far right edge: (12000, 0) is clamped to (11600, 400), in tile (11, 0).
		[[[11, 0]], Vector2i(12000, 0), Vector2i(10500, 500)],
		# An open tile keeps the target. Read with a stride of 6 instead of 12, tile (11, 3) would
		# be (5, 2).
		[[[5, 2]], Vector2i(11500, 3500), Vector2i(11500, 3500)],
	]
	for case: Array in cases:
		var rock: Array[Vector2i] = GridWorld.tiles(case[0])
		var goal: Vector2i = _lone(GridWorld.grass(12, 6, rock), case[1], [FOOT])
		assert_that(goal).override_failure_message(str(case)).is_equal(case[2])
	# The bottom half of the map is rock: the ring of the target (3, 5) in the bottom row has a row
	# below the map, and it is no tile. The first open tile is in row 2, three rings up.
	var half_rock: PackedStringArray = GridWorld.grass(12, 6)
	for y: int in range(3, 6):
		half_rock[y] = "#".repeat(12)
	assert_that(_lone(half_rock, Vector2i(3500, 5500), [FOOT])).is_equal(Vector2i(500, 2500))


## The same on a tall map, with the cases turned over: a rock at the bottom edge (clamped by the
## row count), a ring that reaches past the right edge of the map before an open tile, and a ring
## that is all rock in the rows of the lower half.
func test_a_target_on_rock_moves_to_the_first_open_tile_on_a_tall_map() -> void:
	var cases: Array[Array] = [
		[[[4, 9]], Vector2i(4500, 9500), Vector2i(3500, 8500)],
		[[[0, 11]], Vector2i(0, 12000), Vector2i(500, 10500)],
		[[[5, 0]], Vector2i(6000, 0), Vector2i(4500, 500)],
		# Read with a stride of 12 instead of 6, tile (5, 3) would be (5, 6).
		[[[5, 6]], Vector2i(5500, 3500), Vector2i(5500, 3500)],
		# Tile (6, 0), right of the map, is no tile: the first open one is (4, 1), not (6, 0).
		[[[5, 0], [4, 0]], Vector2i(6000, 0), Vector2i(4500, 1500)],
		# Ring 1 is all rock except (3, 9), in a row below the number of columns.
		[
			[[2, 8], [1, 7], [2, 7], [3, 7], [1, 8], [3, 8], [1, 9], [2, 9]],
			Vector2i(2500, 8500),
			Vector2i(3500, 9500)
		],
	]
	for case: Array in cases:
		var rock: Array[Vector2i] = GridWorld.tiles(case[0])
		var goal: Vector2i = _lone(GridWorld.grass(6, 12, rock), case[1], [TRACKED])
		assert_that(goal).override_failure_message(str(case)).is_equal(case[2])


## The ring search runs as many rings as the longer side of the map has tiles: rock everywhere but
## one tile in the far corner, and a target in the corner on the other side, is 11 rings away on a
## 12 x 6 map and on a 6 x 12 one, more than the shorter side (a search over min(cols, rows) rings,
## or over one dimension only, leaves the target on the rock) and the last ring that the loop runs.
func test_the_search_covers_the_longer_side_of_a_wide_and_a_tall_map() -> void:
	var cases: Array[Array] = [
		# the map, its open tile, the target, the goal of a lone unit
		[Vector2i(12, 6), Vector2i(11, 0), Vector2i(0, 6000), Vector2i(11500, 500)],
		[Vector2i(12, 6), Vector2i(0, 5), Vector2i(12000, 0), Vector2i(500, 5500)],
		[Vector2i(6, 12), Vector2i(5, 11), Vector2i(0, 0), Vector2i(5500, 11500)],
		[Vector2i(6, 12), Vector2i(0, 0), Vector2i(6000, 12000), Vector2i(500, 500)],
		[Vector2i(6, 12), Vector2i(0, 11), Vector2i(6000, 0), Vector2i(500, 11500)],
	]
	for case: Array in cases:
		var shape: Vector2i = case[0]
		var open: Vector2i = case[1]
		var rows: PackedStringArray = PackedStringArray()
		for y: int in shape.y:
			if y == open.y:
				rows.append("#".repeat(open.x) + "." + "#".repeat(shape.x - open.x - 1))
			else:
				rows.append("#".repeat(shape.x))
		for move_class: int in [FOOT, WHEELED, TRACKED]:
			var goal: Vector2i = _lone(rows, case[2], [move_class])
			assert_that(goal).override_failure_message(str(case)).is_equal(case[3])


## Slots on the far edge and below the number of columns are read in their own tile, on both
## shapes: the rock sits where a wrong stride or a clamp by the other dimension would look.
func test_slots_are_read_in_their_own_tile_on_a_wide_and_a_tall_map() -> void:
	# Wide: slot (11000, 3500) is tile (11, 3), and (5, 2) and (5, 3) are what a stride of 6 and a
	# clamp of x to 5 read. Three units take the target, the slot above it and the one left of it.
	var wide: Array[Vector2i] = _group_goals(
		GridWorld.grass(12, 6, [Vector2i(5, 2), Vector2i(5, 3)]), Vector2i(11000, 3500), 3
	)
	var wide_expected: Array[Vector2i] = [
		Vector2i(11000, 3500), Vector2i(11000, 2300), Vector2i(9800, 3500)
	]
	assert_array(wide).contains_exactly_in_any_order(wide_expected)
	# Tall: slot (1500, 2500) is tile (1, 2), and (1, 4) is what a stride of 12 reads.
	var tall: Array[Vector2i] = _group_goals(
		GridWorld.grass(6, 12, [Vector2i(1, 4)]), Vector2i(1500, 2500), 3
	)
	var tall_expected: Array[Vector2i] = [
		Vector2i(1500, 2500), Vector2i(1500, 1300), Vector2i(2700, 2500)
	]
	assert_array(tall).contains_exactly_in_any_order(tall_expected)
	# Tall: slot (3500, 9500) is tile (3, 9); a clamp of y to the 5 columns would read (3, 5).
	var bottom: Array[Vector2i] = _group_goals(
		GridWorld.grass(6, 12, [Vector2i(3, 5)]), Vector2i(3500, 9500), 3
	)
	var bottom_expected: Array[Vector2i] = [
		Vector2i(3500, 9500), Vector2i(3500, 8300), Vector2i(2300, 9500)
	]
	assert_array(bottom).contains_exactly_in_any_order(bottom_expected)


## A unit radius above half a tile (UnitDef.radius has no cap in the World): a target moved off
## rock goes to the centre of the nearest open tile inside the radius inset, so the slots start
## inside it and spread, instead of one stacked goal outside it.
func test_a_moved_target_stays_inside_the_radius_inset() -> void:
	# Rock in the corner tile (0, 0), radius 700. The clamped target (700, 700) is on it, and the
	# centres (1500, 500) and (500, 1500) of its open neighbours are outside the box.
	var corner: World = GridWorld.from_rows(GridWorld.grass(8, 8, [Vector2i(0, 0)]))
	corner.type_radius[0] = 700
	var rows: PackedInt32Array = GridWorld.add_block(corner, 3, 3, 7000, 7000, 100, 0)
	Formation.assign(corner, rows, 200, 300)
	var goals: Array[Vector2i] = GridWorld.goals(corner, rows)
	var distinct: Dictionary[Vector2i, bool] = {}
	for goal: Vector2i in goals:
		distinct[goal] = true
		assert_bool(_in_box(goal, 700, 8000, 8000)).override_failure_message(str(goal)).is_true()
	assert_int(distinct.size()).is_equal(3)
	assert_array(goals).contains(Vector2i(1500, 1500))
	# Rock across the whole of row 1, radius 700, on a map 10 wide and 5 tall: the open tiles of
	# row 0 are outside the box, so the target goes to row 2, and five units spread.
	var wall: World = GridWorld.from_rows(
		PackedStringArray(["..........", "##########", "..........", "..........", ".........."])
	)
	wall.type_radius[0] = 700
	var group: PackedInt32Array = GridWorld.add_block(wall, 5, 5, 9000, 4000, 100, 0)
	Formation.assign(wall, group, 5000, 1500)
	var found: Dictionary[Vector2i, bool] = {}
	for goal: Vector2i in GridWorld.goals(wall, group):
		found[goal] = true
		assert_bool(_in_box(goal, 700, 10000, 5000)).override_failure_message(str(goal)).is_true()
	assert_int(found.size()).is_equal(5)
	assert_array(GridWorld.goals(wall, group)).contains(Vector2i(4500, 2500))


## No open tile has its centre in the box: the clamped target stays, as when no tile is open.
func test_no_open_tile_centre_in_the_box_leaves_the_clamped_target() -> void:
	# A 2 x 2 map with rock at (0, 0) and radius 900: the box is (900, 900) to (1100, 1100), and the
	# centres of the three open tiles (1500, 500), (500, 1500) and (1500, 1500) are outside it.
	# The clamped target (900, 900) is on the rock, so it has no slot either.
	var world: World = GridWorld.from_rows(PackedStringArray(["#.", ".."]))
	world.type_radius[0] = 900
	var rows: PackedInt32Array = GridWorld.add_block(world, 2, 2, 1500, 1500, 100, 0)
	Formation.assign(world, rows, 0, 0)
	for goal: Vector2i in GridWorld.goals(world, rows):
		assert_that(goal).is_equal(Vector2i(900, 900))


## The wheeled and the tracked class are told apart: 'w' is open to wheels only and 't' to tracks
## only, so a target on it moves for the other vehicle class and not for its own, and a group of
## both moves for either.
func test_the_vehicle_classes_read_their_own_tiles() -> void:
	var map: PackedStringArray = GridWorld.grass(8, 6)
	map[3] = "...w.t.."
	var wheels_tile: Vector2i = Vector2i(3500, 3500)
	var tracks_tile: Vector2i = Vector2i(5500, 3500)
	# the unit classes of the group, the target, the goal of its first unit
	var cases: Array[Array] = [
		[[WHEELED], wheels_tile, wheels_tile],
		[[TRACKED], wheels_tile, Vector2i(2500, 2500)],
		[[TRACKED], tracks_tile, tracks_tile],
		[[WHEELED], tracks_tile, Vector2i(4500, 2500)],
		[[WHEELED, TRACKED], wheels_tile, Vector2i(2500, 2500)],
		[[FOOT], tracks_tile, tracks_tile],
	]
	for case: Array in cases:
		var world: World = GridWorld.from_rows(map, [FOOT, WHEELED, TRACKED])
		var group: PackedInt32Array = PackedInt32Array()
		for move_class: int in case[0]:
			world.add_unit(1, move_class, 7500, 5500)
			group.append(world.unit_count() - 1)
		var target: Vector2i = case[1]
		Formation.assign(world, group, target.x, target.y)
		assert_that(GridWorld.goals(world, group)[0]).override_failure_message(str(case)).is_equal(
			case[2]
		)
	# The slots read the class too. Four units around (5500, 1500) take it, its neighbours left and
	# right, and the next slot in order: (3100, 1500), a tile of 'w', for wheeled units, and the
	# one on the other side, (7900, 1500), for tracked ones.
	var line: PackedStringArray = GridWorld.grass(9, 3)
	line[1] = "...w....."
	var wheeled: Array[Vector2i] = _group_goals(line, Vector2i(5500, 1500), 4, WHEELED)
	var tracked: Array[Vector2i] = _group_goals(line, Vector2i(5500, 1500), 4, TRACKED)
	var near: Array[Vector2i] = [Vector2i(5500, 1500), Vector2i(4300, 1500), Vector2i(6700, 1500)]
	assert_array(wheeled).contains_exactly_in_any_order(near + [Vector2i(3100, 1500)])
	assert_array(tracked).contains_exactly_in_any_order(near + [Vector2i(7900, 1500)])


## The goals of Formation are the same on a wide and on a tall map as the definition of the slots
## gives (an exhaustive, sorted list of the lattice points in the box on open tiles), on random
## maps with rock, scrub and the two vehicle terrains, mixed groups, radii from 0 to 900 and
## targets also outside the map. Every slot is a point from which every class of the group has a
## clear line inside its own tile (FixedMath.line_clear, ADR 0008 section 2).
@warning_ignore("integer_division")
func test_the_goals_equal_the_definition_on_wide_and_tall_maps() -> void:
	var rng: DetRandom = DetRandom.create(37, 5)
	var radii: Array[int] = [0, 300, 400, 500, 700, 900]
	var spacings: Array[int] = [600, 900, 1200, 1500]
	var wrong: Array[String] = []
	var moved: int = 0
	var skipped: int = 0
	for shape: Vector2i in [Vector2i(12, 6), Vector2i(6, 12), Vector2i(9, 5), Vector2i(4, 9)]:
		for _case: int in 60:
			var rows: PackedStringArray = _random_map(rng, shape)
			var world: World = GridWorld.from_rows(rows, [FOOT, WHEELED, TRACKED])
			for kind: int in 3:
				world.type_radius[kind] = radii[rng.next_int(radii.size())]
				world.type_spacing[kind] = spacings[rng.next_int(spacings.size())]
			var group: PackedInt32Array = PackedInt32Array()
			var classes: Array[int] = []
			var radius: int = 0
			var spacing: int = 1
			var count: int = 1 + rng.next_int(14)
			var mix: int = 1 + rng.next_int(7)
			for k: int in count:
				var kind: int = k % 3
				while ((mix >> kind) & 1) == 0:
					kind = (kind + 1) % 3
				world.add_unit(
					1, kind, rng.range_int(0, shape.x * TILE), rng.range_int(0, shape.y * TILE)
				)
				group.append(world.unit_count() - 1)
				if kind not in classes:
					classes.append(kind)
				radius = maxi(radius, world.type_radius[kind])
				spacing = maxi(spacing, world.type_spacing[kind])
			var target: Vector2i = Vector2i(
				rng.range_int(-2000, shape.x * TILE + 2000),
				rng.range_int(-2000, shape.y * TILE + 2000)
			)
			Formation.assign(world, group, target.x, target.y)
			var extent: Vector2i = shape * TILE
			var low: Vector2i = Vector2i(mini(radius, extent.x / 2), mini(radius, extent.y / 2))
			var high: Vector2i = extent - low
			var point: Vector2i = Vector2i(
				clampi(target.x, low.x, high.x), clampi(target.y, low.y, high.y)
			)
			var centre: Vector2i = _definition_centre(rows, classes, point, low, high)
			moved += 1 if centre != point else 0
			var slots: Array[Vector2i] = _definition_slots(
				rows, classes, count, centre, spacing, low, high
			)
			skipped += 1 if slots.size() < count else 0
			var expected: Array[int] = []
			for k: int in count:
				expected.append(_code(slots[k] if k < slots.size() else centre))
			var actual: Array[int] = []
			for goal: Vector2i in GridWorld.goals(world, group):
				actual.append(_code(goal))
			expected.sort()
			actual.sort()
			if actual != expected:
				wrong.append(
					"%s target %s group %s radius %d: %s" % [shape, target, classes, radius, rows]
				)
			for slot: Vector2i in slots:
				for move_class: int in classes:
					var tile: Vector2i = Vector2i(
						mini(slot.x / TILE, shape.x - 1), mini(slot.y / TILE, shape.y - 1)
					)
					var from: Vector2i = tile * TILE + Vector2i(TILE / 2, TILE / 2)
					var reached: bool = (
						FixedMath.line_clear(world, slot.x, slot.y, slot.x, slot.y, move_class)
						and FixedMath.line_clear(world, from.x, from.y, slot.x, slot.y, move_class)
					)
					if not reached:
						wrong.append("slot %s class %d unreachable: %s" % [slot, move_class, rows])
	assert_array(wrong).is_empty()
	# The cases must hold moved targets and groups that outgrow the open slots, or they prove little.
	assert_int(moved).is_greater(20)
	assert_int(skipped).is_greater(10)


## A spacing of 900 puts slots on tile edges (500 + 900 * i is a multiple of 1000 for i = 5):
## around a target that moved to the centre of tile (9, 9), next to rock, every slot is a point
## from which the foot units of the group have a clear line inside its own tile, and a plain tap
## on an open tile beside rock keeps its goal and is reached from other tiles.
func test_slots_on_a_tile_edge_next_to_rock_are_in_reach() -> void:
	var rock: Array[Vector2i] = [Vector2i(10, 10), Vector2i(13, 9)]
	var world: World = GridWorld.from_rows(GridWorld.grass(20, 20, rock), [FOOT])
	world.type_spacing[0] = 900
	world.type_radius[0] = 300
	var group: PackedInt32Array = GridWorld.add_block(world, 90, 10, 2500, 2500, 400, 0)
	Formation.assign(world, group, 10500, 10500)
	var on_edge: int = 0
	for goal: Vector2i in GridWorld.goals(world, group):
		var from: Vector2i = goal / TILE * TILE + Vector2i(TILE / 2, TILE / 2)
		on_edge += 1 if goal.x % TILE == 0 or goal.y % TILE == 0 else 0
		assert_bool(world.is_passable(world.cell_of(goal.x, goal.y), FOOT)).is_true()
		assert_bool(FixedMath.line_clear(world, goal.x, goal.y, goal.x, goal.y, FOOT)).is_true()
		assert_bool(FixedMath.line_clear(world, from.x, from.y, goal.x, goal.y, FOOT)).is_true()
	assert_int(on_edge).is_greater(5)
	# A tap on the left edge of tile (5, 5), beside the rock (4, 5).
	var tap: World = GridWorld.from_rows(GridWorld.grass(10, 10, [Vector2i(4, 5)]), [TRACKED])
	var lone: PackedInt32Array = GridWorld.add_block(tap, 1, 1, 8500, 8500, 0, 0)
	Formation.assign(tap, lone, 5000, 5500)
	assert_that(GridWorld.goals(tap, lone)[0]).is_equal(Vector2i(5000, 5500))
	for start: Vector2i in [Vector2i(8500, 8500), Vector2i(7500, 5500), Vector2i(5500, 5500)]:
		assert_bool(FixedMath.line_clear(tap, start.x, start.y, 5000, 5500, TRACKED)).is_true()
	# And away from the rock, from the goal.
	assert_bool(FixedMath.line_clear(tap, 5000, 5500, 9500, 5500, TRACKED)).is_true()


## A random map of `shape` (columns, rows) tiles: grass, with rock, scrub, and the wheels-only and
## tracks-only terrain in a density that differs from map to map.
func _random_map(rng: DetRandom, shape: Vector2i) -> PackedStringArray:
	var density: int = 4 + rng.next_int(5)
	var rows: PackedStringArray = PackedStringArray()
	for _y: int in shape.y:
		var line: String = ""
		for _x: int in shape.x:
			var kind: int = rng.next_int(40)
			if kind < density * 2:
				line += "#"
			elif kind < density * 2 + 3:
				line += "^"
			elif kind < density * 2 + 6:
				line += "w"
			elif kind < density * 2 + 9:
				line += "t"
			else:
				line += "."
		rows.append(line)
	return rows


## Whether the tile (x, y) of `rows` is open to every class in `classes`.
func _open(rows: PackedStringArray, classes: Array[int], x: int, y: int) -> bool:
	var terrain: int = GridWorld.GROUND.find(rows[y][x])
	for move_class: int in classes:
		if GridWorld.GROUND_COST[terrain * 3 + move_class] == 0:
			return false
	return true


## The tile of a point (World.cell_of: the far edge of the map is in the last tile) is open.
@warning_ignore("integer_division")
func _open_at(rows: PackedStringArray, classes: Array[int], point: Vector2i) -> bool:
	return _open(
		rows, classes, mini(point.x / TILE, len(rows[0]) - 1), mini(point.y / TILE, rows.size() - 1)
	)


func _in_box(point: Vector2i, radius: int, width: int, height: int) -> bool:
	return (
		point.x >= radius
		and point.x <= width - radius
		and point.y >= radius
		and point.y <= height - radius
	)


## The target of a group by the definition (ADR 0008 section 2): the point itself on an open tile,
## otherwise the centre of the first open tile whose centre is in the box, in rings around the
## tile of the point (ring, then row, then column), or the point when there is none.
@warning_ignore("integer_division")
func _definition_centre(
	rows: PackedStringArray, classes: Array[int], point: Vector2i, low: Vector2i, high: Vector2i
) -> Vector2i:
	var cols: int = len(rows[0])
	var tile: Vector2i = Vector2i(
		mini(point.x / TILE, cols - 1), mini(point.y / TILE, rows.size() - 1)
	)
	if _open(rows, classes, tile.x, tile.y):
		return point
	for ring: int in range(1, maxi(cols, rows.size())):
		for j: int in range(-ring, ring + 1):
			for i: int in range(-ring, ring + 1):
				var x: int = tile.x + i
				var y: int = tile.y + j
				if (
					maxi(absi(i), absi(j)) != ring
					or x < 0
					or y < 0
					or x >= cols
					or y >= rows.size()
				):
					continue
				var centre: Vector2i = Vector2i(x * TILE + TILE / 2, y * TILE + TILE / 2)
				if (
					_open(rows, classes, x, y)
					and centre.x >= low.x
					and centre.x <= high.x
					and centre.y >= low.y
					and centre.y <= high.y
				):
					return centre
	return point


## The first `count` slots by the definition (ADR 0003 section 4, ADR 0008 section 2): every lattice
## point centre + spacing * (i, j) in the box on an open tile, nearest first by squared lattice
## distance, then by ring, then row, then column.
@warning_ignore("integer_division")
func _definition_slots(
	rows: PackedStringArray,
	classes: Array[int],
	count: int,
	centre: Vector2i,
	spacing: int,
	low: Vector2i,
	high: Vector2i
) -> Array[Vector2i]:
	var reach: int = maxi(high.x - low.x, high.y - low.y) / spacing + 1
	var by_key: Dictionary[int, Vector2i] = {}
	for j: int in range(-reach, reach + 1):
		for i: int in range(-reach, reach + 1):
			var point: Vector2i = centre + Vector2i(i, j) * spacing
			if point.x < low.x or point.x > high.x or point.y < low.y or point.y > high.y:
				continue
			if not _open_at(rows, classes, point):
				continue
			var ring: int = maxi(absi(i), absi(j))
			var key: int = (((i * i + j * j) * 256 + ring) * 256 + j + reach) * 256 + i + reach
			by_key[key] = point
	var keys: Array = by_key.keys()
	keys.sort()
	var slots: Array[Vector2i] = []
	for key: int in keys:
		if slots.size() == count:
			break
		slots.append(by_key[key])
	return slots


func _code(point: Vector2i) -> int:
	return (point.x + 100000) * 1000000 + point.y + 100000


## The goals of one unit of class `move_classes[0]` on `rows`, far from the target.
func _lone(rows: PackedStringArray, target: Vector2i, move_classes: Array) -> Vector2i:
	var world: World = GridWorld.from_rows(rows, move_classes)
	var group: PackedInt32Array = GridWorld.add_block(world, 1, 1, 500, 500, 0, 0)
	Formation.assign(world, group, target.x, target.y)
	return GridWorld.goals(world, group)[0]


## The goals of `count` units of class `move_class` on `rows`, units near the map's far corner.
func _group_goals(
	rows: PackedStringArray, target: Vector2i, count: int, move_class: int = TRACKED
) -> Array[Vector2i]:
	var world: World = GridWorld.from_rows(rows, [move_class])
	var x: int = (len(rows[0]) - 1) * TILE
	var y: int = (rows.size() - 1) * TILE
	var group: PackedInt32Array = GridWorld.add_block(world, count, count, x, y, 50, 0)
	Formation.assign(world, group, target.x, target.y)
	return GridWorld.goals(world, group)
