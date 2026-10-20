extends GdUnitTestSuite
## The C++ line_clear that the TARGETING kernel calls (core/fixed_math.cpp, plan P41n) against
## FixedMath.line_clear, its twin. line_clear is not bound (a core/ function lands with the kernel
## that calls it, and ADR 0013 section 2 allows no test-only entry), so the engagement pass is the
## probe: a subject whose target is set by hand, out of its weapon range and inside its acquire
## range, on its line-check turn, chases when the line to the target is clear (an attack-moving
## row) or keeps its checked line when it is clear (an ATTACK row whose line was marked clear).
## Each World holds up to 120 such segments, one subject and one target apiece, each between two
## points from a list that is rich in tile corners, tile edges, the map's own edges and points
## outside the map, over a map with random rock, scrub and the two test terrains that tell the move
## classes apart (the subjects take the three classes in turn). The twin and the kernel run the same
## World and must end in the same full state (StateDiff); the kernel's World must also agree with
## FixedMath.line_clear called on the segment, so the probe cannot agree with a wrong twin.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK
const DIRECT: int = World.NavMode.DIRECT
const CHASE: int = World.NavMode.CHASE
## A `retarget_period_ticks` that no tick of a test reaches: nobody scans, so the targets stay as
## they were set.
const NEVER_DUE: int = 1000000
## The segments in one World (two rows each; the rules' max_rows is 256).
const PER_WORLD: int = 120
## The weapon range of the subjects, below the shortest segment that these cases care about: a
## segment of 100 or less is in range, and the unit holds instead of testing its line.
const RANGE: int = 100
const ACQUIRE: int = 60000


## Random segments on maps of every shape the strips tell apart (one tile, a row, a column, wide,
## tall), five maps of each with random terrain. Both outcomes of the line test must occur, for
## the attack-moving rows and for the ATTACK rows, or the probe proves nothing.
func test_random_segments_on_random_maps_agree_with_the_twin() -> void:
	var rng: DetRandom = DetRandom.create(41, 1)
	var seen: Dictionary[String, int] = {"chase": 0, "blocked": 0, "kept": 0, "reset": 0}
	var shapes: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(6, 1),
		Vector2i(1, 6),
		Vector2i(3, 2),
		Vector2i(8, 6),
		Vector2i(12, 9)
	]
	for shape: Vector2i in shapes:
		for _map: int in 5:
			var terrain: PackedInt32Array = _random_terrain(rng, shape)
			var points: Array[Vector2i] = _points(shape)
			var segments: Array[Array] = []
			for _index: int in PER_WORLD:
				segments.append([_pick(rng, points), _pick(rng, points)])
			_compare(shape, terrain, segments, seen)
	for kind: String in seen:
		assert_int(seen[kind]).override_failure_message(kind).is_greater(100)


## Every segment between two points of the 500-milli lattice of a map of 3 x 2 tiles (7 x 5 points,
## 35 * 35 segments, a point to itself included), over a map whose terrain is every combination of
## open and rock for 6 tiles taken from a few patterns: each segment passes through, along or
## across tile corners, edges and centres, in each direction.
func test_every_segment_between_the_lattice_points_of_a_small_map_agrees_with_the_twin() -> void:
	var shape: Vector2i = Vector2i(3, 2)
	var points: Array[Vector2i] = []
	for y: int in range(0, 2 * shape.y + 1):
		for x: int in range(0, 2 * shape.x + 1):
			points.append(Vector2i(x * 500, y * 500))
	var segments: Array[Array] = []
	for from: Vector2i in points:
		for to: Vector2i in points:
			segments.append([from, to])
	# Terrain ids: 0 grass, 2 rock, 3 open to foot and wheeled, 4 open to foot and tracked.
	var patterns: Array[Array] = [
		[0, 0, 0, 0, 0, 0],
		[0, 2, 0, 0, 0, 0],
		[0, 0, 0, 0, 2, 0],
		[2, 0, 0, 0, 0, 2],
		[0, 3, 0, 4, 0, 0],
		[0, 0, 4, 0, 3, 0],
		[0, 2, 2, 2, 2, 0],
	]
	var seen: Dictionary[String, int] = {"chase": 0, "blocked": 0, "kept": 0, "reset": 0}
	for pattern: Array in patterns:
		var terrain: PackedInt32Array = PackedInt32Array(pattern)
		for start: int in range(0, segments.size(), PER_WORLD):
			_compare(shape, terrain, segments.slice(start, start + PER_WORLD), seen)
	# About 3400 chase, 2800 blocked, 1200 kept and 900 reset (the ATTACK rows are one in four).
	for kind: String in seen:
		assert_int(seen[kind]).override_failure_message(kind).is_greater(500)


## The move class is the unit's own: the same segment through a tile that only foot and wheeled
## units cross ('w'), and through one that only foot and tracked units cross ('t'), is clear for
## two of the three subjects and blocked for the third. Three subjects, one segment through each
## kind of tile, a map of 3 x 1 tiles with the odd tile in the middle.
func test_each_move_class_reads_its_own_cost_list() -> void:
	var expected: Dictionary[int, Array] = {3: [true, true, false], 4: [true, false, true]}
	for terrain_id: int in expected:
		var segments: Array[Array] = []
		for _kind: int in 3:
			segments.append([Vector2i(100, 500), Vector2i(2900, 500)])
		var terrain: PackedInt32Array = PackedInt32Array([0, terrain_id, 0])
		var pair: Array[World] = _pair(Vector2i(3, 1), terrain, segments)
		for world: World in pair:
			Rig.acquire(world)
			var label: String = "terrain %d, native %s" % [terrain_id, world.native_phases != 0]
			var clear: Array[bool] = []
			for kind: int in 3:
				clear.append(world.nav_mode[2 * kind] == CHASE)
			assert_array(clear).override_failure_message(label).is_equal(expected[terrain_id])
		assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The first section of the pass after a run: both Worlds from `segments`, compared, and the
## outcomes counted into `seen`.
func _compare(
	shape: Vector2i, terrain: PackedInt32Array, segments: Array, seen: Dictionary
) -> void:
	var pair: Array[World] = _pair(shape, terrain, segments)
	for world: World in pair:
		Rig.acquire(world)
	var found: String = StateDiff.first(pair[0], pair[1])
	assert_str(found).override_failure_message("%s %s" % [shape, found]).is_empty()
	var world: World = pair[1]
	for index: int in segments.size():
		var row: int = 2 * index
		var from: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row])
		var to: Vector2i = Vector2i(world.pos_x[row + 1], world.pos_y[row + 1])
		var d2: int = (to - from).length_squared()
		if d2 <= RANGE * RANGE:
			continue
		var kind: int = world.type_move_class[world.type_index[row]]
		var clear: bool = FixedMath.line_clear(world, from.x, from.y, to.x, to.y, kind)
		var label: String = "%s: %s to %s, class %d" % [shape, from, to, kind]
		if world.order[row] == ATTACK:
			# The ATTACK row marked its line checked (nav_cell 0); a blocked line resets it.
			assert_bool(world.nav_cell[row] >= 0).override_failure_message(label).is_equal(clear)
			seen["kept" if clear else "reset"] += 1
		else:
			assert_bool(world.nav_mode[row] == CHASE).override_failure_message(label).is_equal(
				clear
			)
			seen["chase" if clear else "blocked"] += 1


## Two Worlds of the same map and segments, the first running the GDScript phase and the second
## the kernel.
func _pair(shape: Vector2i, terrain: PackedInt32Array, segments: Array) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = _segments_world(shape, terrain, segments)
		assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
		pair.append(world)
	return pair


## The map of `shape` tiles with `terrain` (a terrain id per tile, row by row), and a subject and
## a target for each of `segments` (from, to): rows 2 * index and 2 * index + 1, ids 2 * index + 1
## and 2 * index + 2. Subject `index` takes the move class `index % 3`. Every fourth subject is an
## ATTACK row that has checked its line (nav_cell 0), the others attack-move with their target set
## by hand. Every row is on its line-check turn on every tick, and nobody scans.
func _segments_world(shape: Vector2i, terrain: PackedInt32Array, segments: Array) -> World:
	var units: Array[UnitDef] = []
	for move_class: int in 3:
		var name: StringName = StringName("lines%d" % move_class)
		var def: UnitDef = Rig.unit(name, 8000, ACQUIRE, RANGE, 0, [100, 100, 100, 100])
		def.move_class = move_class
		units.append(def)
	var world: World = Rig.world_of(units, shape.x, shape.y)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for cell: int in terrain.size():
		world.set_terrain(cell, terrain[cell])
	world.retarget_period_ticks = NEVER_DUE
	world.line_check_period_ticks = 1
	for index: int in segments.size():
		var from: Vector2i = segments[index][0]
		var to: Vector2i = segments[index][1]
		var row: int = world.unit_count()
		world.add_unit(1, index % 3, from.x, from.y)
		world.add_unit(2, index % 3, to.x, to.y)
		if index % 4 == 3:
			world.order[row] = ATTACK
			world.order_target[row] = world.unit_id[row + 1]
			world.nav_mode[row] = DIRECT
			world.nav_cell[row] = 0
		else:
			world.order[row] = ATTACK_MOVE
			world.target[row] = world.unit_id[row + 1]
	return world


## A terrain id for each tile: mostly grass, some rock, scrub, and the two test terrains.
func _random_terrain(rng: DetRandom, shape: Vector2i) -> PackedInt32Array:
	var weights: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 2, 2, 1, 3, 4, 0])
	var terrain: PackedInt32Array = PackedInt32Array()
	for _cell: int in shape.x * shape.y:
		terrain.append(weights[rng.next_int(weights.size())])
	return terrain


## The points of a map of `shape` tiles that the segments run between: the corners, the edge
## midpoints and the centres of the tiles, a milli either side of each tile border, the map's own
## edges, and points outside it on every side.
func _points(shape: Vector2i) -> Array[Vector2i]:
	var xs: Array[int] = [-1500, -1]
	var ys: Array[int] = [-1500, -1]
	for column: int in range(0, shape.x + 1):
		xs.append_array([column * 1000 - 1, column * 1000, column * 1000 + 1, column * 1000 + 500])
	for line: int in range(0, shape.y + 1):
		ys.append_array([line * 1000 - 1, line * 1000, line * 1000 + 1, line * 1000 + 500])
	xs.append(shape.x * 1000 + 1500)
	ys.append(shape.y * 1000 + 1500)
	var points: Array[Vector2i] = []
	for y: int in ys:
		for x: int in xs:
			points.append(Vector2i(x, y))
	return points


func _pick(rng: DetRandom, points: Array[Vector2i]) -> Vector2i:
	return points[rng.next_int(points.size())]
