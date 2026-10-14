class_name Formation
extends RefCounted
## Formation slots for a group order (ADR 0003 section 4, ADR 0008 section 2). Integers only and
## no state kept between calls. It runs once per command, never per tick, and is O(n^2) in the
## group size. A slot on a tile that a movement class of the group cannot enter is skipped.

## A sort key is the squared lattice distance times this, plus the generation index (below it),
## so a plain sort puts nearer slots first and keeps generation order on ties.
const KEY_SHIFT: int = 1 << 20


## Sets goal_x/goal_y of the units at `unit_indices` (rows of `world`). The world is prepared
## first (one bool check; the tick has done it already), because the types' movement classes and
## the tile grid exist only after prepare(). The target is clamped to the map inset by the largest
## radius in the group (the box [low, high] below). On a tile that a class of the group cannot
## enter it moves to the centre of the nearest tile that every class can and whose centre is in the
## box (_open_centre), so the slot lattice always starts inside the box. The slots are spaced by
## the largest formation spacing in the group. Each slot, nearest to the target first, takes the
## nearest unassigned unit, ties to the lower id. Units left without a slot get the clamped target.
## It runs on the worker, so the World's arrays are aliased into locals before the loops (ADR
## 0012 section 2).
static func assign(
	world: World, unit_indices: PackedInt32Array, target_x: int, target_y: int
) -> void:
	world.prepare()
	var count: int = unit_indices.size()
	if count == 0:
		return
	var types: PackedInt32Array = world.type_index
	var type_spacing: PackedInt32Array = world.type_spacing
	var type_radius: PackedInt32Array = world.type_radius
	var type_class: PackedInt32Array = world.type_move_class
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	var ids: PackedInt32Array = world.unit_id
	var spacing: int = 1
	var radius: int = 0
	var group: int = 0
	for row: int in unit_indices:
		spacing = maxi(spacing, type_spacing[types[row]])
		radius = maxi(radius, type_radius[types[row]])
		group |= 1 << type_class[types[row]]
	# The offset into move_cost of each class in the group; none without a map, which blocks no tile.
	var bases: PackedInt32Array = PackedInt32Array()
	var cells: int = world.map_cols * world.map_rows
	if cells > 0:
		for move_class: int in World.MoveClass.size():
			if ((group >> move_class) & 1) == 1:
				bases.append(move_class * cells)
	var low: Vector2i = Vector2i(mini(radius, world.map_w >> 1), mini(radius, world.map_h >> 1))
	var high: Vector2i = Vector2i(world.map_w, world.map_h) - low
	var centre: Vector2i = _open_centre(
		world,
		bases,
		Vector2i(clampi(target_x, low.x, high.x), clampi(target_y, low.y, high.y)),
		low,
		high
	)
	for row: int in unit_indices:
		goal_x[row] = centre.x
		goal_y[row] = centre.y
	var taken: PackedByteArray = PackedByteArray()
	taken.resize(count)
	for slot: Vector2i in _slots(world, bases, count, centre, spacing, low, high):
		var pick: int = _nearest_free(pos_x, pos_y, ids, unit_indices, taken, slot)
		taken[pick] = 1
		goal_x[unit_indices[pick]] = slot.x
		goal_y[unit_indices[pick]] = slot.y


## `point` itself when its tile is open to every class in `bases` (the offsets into move_cost, see
## assign) or when no tile is blocked at all. Otherwise the centre of the nearest open tile whose
## centre is in the box [low, high]: rings of tiles around the point's tile, each ring row by row
## (j, then i, ascending), and the first hit wins. A tile centre outside the box (a unit radius
## above half a tile, or a map that is not a whole number of tiles wide) would put the slots
## outside the radius inset, and _slots would find none. `point`, which is in the box, again when no
## such tile is open.
@warning_ignore("integer_division")
static func _open_centre(
	world: World, bases: PackedInt32Array, point: Vector2i, low: Vector2i, high: Vector2i
) -> Vector2i:
	if bases.is_empty():
		return point
	var cost: PackedByteArray = world.move_cost
	var cols: int = world.map_cols
	var rows: int = world.map_rows
	var tile_x: int = mini(point.x / World.MILLI_PER_TILE, cols - 1)
	var tile_y: int = mini(point.y / World.MILLI_PER_TILE, rows - 1)
	for ring: int in maxi(cols, rows):
		for j: int in range(-ring, ring + 1):
			var y: int = tile_y + j
			if y < 0 or y >= rows:
				continue
			for i: int in range(-ring, ring + 1, 1 if absi(j) == ring else maxi(2 * ring, 1)):
				var x: int = tile_x + i
				if x < 0 or x >= cols:
					continue
				var open: bool = true
				for base: int in bases:
					if cost[base + y * cols + x] == 0:
						open = false
						break
				if not open:
					continue
				if ring == 0:
					return point
				var centre: Vector2i = (
					Vector2i(x, y) * World.MILLI_PER_TILE
					+ Vector2i(World.TILE_CENTRE, World.TILE_CENTRE)
				)
				if (
					centre.x >= low.x
					and centre.x <= high.x
					and centre.y >= low.y
					and centre.y <= high.y
				):
					return centre
	return point


## Up to `count` slots inside [low, high] on open tiles (see assign for `bases`), nearest to
## `centre` first. Candidates are the lattice points centre + spacing * (i, j), generated ring by
## ring (ring r: max(|i|, |j|) == r, row by row, j then i ascending). K is the first ring where
## rings 0..K hold `count` candidates. Rings up to isqrt(2 * K * K) are kept, since a ring-(K+1)
## point can be nearer than a ring-K corner. A candidate on a blocked tile is not generated, so
## the ring counts and the generation index see only the open ones.
@warning_ignore("integer_division")
static func _slots(
	world: World,
	bases: PackedInt32Array,
	count: int,
	centre: Vector2i,
	spacing: int,
	low: Vector2i,
	high: Vector2i
) -> Array[Vector2i]:
	var cost: PackedByteArray = world.move_cost
	var cols: int = world.map_cols
	var rows: int = world.map_rows
	var points: Array[Vector2i] = []
	var keys: Array[int] = []
	var last_ring: int = -1
	var ring: int = 0
	# A ring r point is r * spacing away from the centre on an axis, and the centre is in the box
	# (assign clamps the target, and _open_centre keeps a moved one inside), so no ring beyond the
	# box extent holds a point. This ends the loop on its own.
	var extent: int = maxi(high.x - low.x, high.y - low.y)
	while (last_ring < 0 or ring <= last_ring) and ring * spacing <= extent:
		var inside: int = 0
		for j: int in range(-ring, ring + 1):
			# Inner rows only hold their two end points.
			for i: int in range(-ring, ring + 1, 1 if absi(j) == ring else maxi(2 * ring, 1)):
				var point: Vector2i = centre + Vector2i(i, j) * spacing
				if point.x < low.x or point.x > high.x or point.y < low.y or point.y > high.y:
					continue
				inside += 1
				# The tile of the point; a point on the far edge of the map belongs to the last tile.
				var cell: int = mini(point.y / World.MILLI_PER_TILE, rows - 1) * cols
				cell += mini(point.x / World.MILLI_PER_TILE, cols - 1)
				var open: bool = true
				for base: int in bases:
					if cost[base + cell] == 0:
						open = false
						break
				if not open:
					continue
				keys.append((i * i + j * j) * KEY_SHIFT + points.size())
				points.append(point)
		# A ring with no point inside the box means no later ring has one either, so stop early.
		# A ring whose points are all blocked says nothing about the later ones.
		if inside == 0:
			break
		if last_ring < 0 and points.size() >= count:
			last_ring = FixedMath.isqrt(2 * ring * ring)
		ring += 1
	keys.sort()
	var slots: Array[Vector2i] = []
	for key: int in keys:
		if slots.size() == count:
			break
		slots.append(points[key & (KEY_SHIFT - 1)])
	return slots


## The position in `unit_indices` of the unassigned unit nearest to `slot` (squared distance),
## ties to the lower id. Independent of the order of `unit_indices`. The columns are the World's
## pos_x, pos_y and unit_id, aliased by the caller.
static func _nearest_free(
	pos_x: PackedInt32Array,
	pos_y: PackedInt32Array,
	ids: PackedInt32Array,
	unit_indices: PackedInt32Array,
	taken: PackedByteArray,
	slot: Vector2i
) -> int:
	var best: int = -1
	var best_d2: int = 0
	for k: int in unit_indices.size():
		if taken[k] == 1:
			continue
		var row: int = unit_indices[k]
		var dx: int = pos_x[row] - slot.x
		var dy: int = pos_y[row] - slot.y
		var d2: int = dx * dx + dy * dy
		if best < 0 or d2 < best_d2:
			best = k
			best_d2 = d2
		elif d2 == best_d2 and ids[row] < ids[unit_indices[best]]:
			best = k
	return best
