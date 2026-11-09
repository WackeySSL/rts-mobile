class_name Formation
extends RefCounted
## Formation slots for a group order (ADR 0003 section 4, ADR 0008 section 2). Integers only and
## no state kept between calls. It runs once per command, never per tick, and is O(n^2) in the
## group size. A slot on a tile that a movement class of the group cannot enter is skipped.

## A sort key is the squared lattice distance times this, plus the generation index (below it).
## The sort compares the distance part (key / KEY_SHIFT), then the offset along the approach, then
## across it, and the generation index only on a tie of all three (the index is the last word).
const KEY_SHIFT: int = 1 << 20


## Sets goal_x/goal_y of the units at `unit_indices` (rows of `world`) and their `group_cell`, the
## cell of the centre below, the key of their flow field (ADR 0008 section 3). The world is prepared
## first (one bool check; the tick has done it already), because the types' movement classes and
## the tile grid exist only after prepare(). The target is clamped to the map inset by the largest
## radius in the group (the box [low, high] below). On a tile that a class of the group cannot
## enter it moves to the centre of the nearest tile that every class can and whose centre is in the
## box (_open_centre), so the slot lattice always starts inside the box. The slots are spaced by
## the largest formation spacing in the group. Each slot, nearest to the target first (an equal
## distance: the one further along the approach, then across it), takes the nearest unassigned
## unit (an equal distance: the larger offset along the approach, then across it, then the lower
## id). Units left without a slot get the clamped target.
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
	var group_of: PackedInt32Array = world.group_cell
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
	var wanted: Vector2i = Vector2i(
		clampi(target_x, low.x, high.x), clampi(target_y, low.y, high.y)
	)
	var way: Vector2i = wanted * count
	for row: int in unit_indices:
		way -= Vector2i(pos_x[row], pos_y[row])
	var centre: Vector2i = _open_centre(world, bases, wanted, low, high, way)
	var centre_cell: int = world.cell_of(centre.x, centre.y)
	for row: int in unit_indices:
		goal_x[row] = centre.x
		goal_y[row] = centre.y
		group_of[row] = centre_cell
	var taken: PackedByteArray = PackedByteArray()
	taken.resize(count)
	# The group's approach, scaled by the unit count so that it is exact: centre * count - sum of the
	# positions. A slot tie goes to the slot with the larger share along it, then across it, which a
	# half turn of the whole situation keeps (both the offset and the approach change sign).
	var approach: Vector2i = centre * count
	for row: int in unit_indices:
		approach -= Vector2i(pos_x[row], pos_y[row])
	for slot: Vector2i in _slots(world, bases, count, centre, spacing, low, high, approach):
		var pick: int = _nearest_free(pos_x, pos_y, ids, unit_indices, taken, slot, approach)
		taken[pick] = 1
		goal_x[unit_indices[pick]] = slot.x
		goal_y[unit_indices[pick]] = slot.y


## `point` itself when its tile is open to every class in `bases` (the offsets into move_cost, see
## assign) or when no tile is blocked at all. Otherwise the centre of the nearest open tile whose
## centre is in the box [low, high], in the first ring of tiles around the point's tile that has one
## (the tile by the rule of World.cell_of): the one nearest to the point, an equal distance to the
## one further along `way` (the group's approach, the target * count - the sum of the positions: the
## dot product of the offset from the point with it), then to the one with the larger cross product
## (offset.x * way.y - offset.y * way.x). Both products keep their value when the map and the group
## are turned half a turn about the map centre, as the distance does, so the tile moves with them. A
## tile centre outside the box (a unit radius above half a tile, or a map that is not a whole number
## of tiles wide) would put the slots outside the radius inset, and _slots would find none. `point`,
## which is in the box, again when no such tile is open.
@warning_ignore("integer_division")
static func _open_centre(
	world: World,
	bases: PackedInt32Array,
	point: Vector2i,
	low: Vector2i,
	high: Vector2i,
	way: Vector2i
) -> Vector2i:
	if bases.is_empty():
		return point
	var cost: PackedByteArray = world.move_cost
	var cols: int = world.map_cols
	var rows: int = world.map_rows
	var tile_x: int = mini(
		FixedMath.centre_side(point.x, cols * World.MILLI_PER_TILE) / World.MILLI_PER_TILE, cols - 1
	)
	var tile_y: int = mini(
		FixedMath.centre_side(point.y, rows * World.MILLI_PER_TILE) / World.MILLI_PER_TILE, rows - 1
	)
	for ring: int in maxi(cols, rows):
		var found: bool = false
		var best: Vector2i = point
		var best_d2: int = 0
		var best_along: int = 0
		var best_across: int = 0
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
					# The nearest to the point, then the one further along the approach and on
					# the larger cross side: a rule that a half turn of the map keeps.
					var gap: Vector2i = centre - point
					var d2: int = gap.x * gap.x + gap.y * gap.y
					var along: int = -(gap.x * way.x + gap.y * way.y)
					var across: int = -(gap.x * way.y - gap.y * way.x)
					if (
						not found
						or d2 < best_d2
						or (
							d2 == best_d2
							and (
								along < best_along
								or (along == best_along and across < best_across)
							)
						)
					):
						found = true
						best = centre
						best_d2 = d2
						best_along = along
						best_across = across
		if found:
			return best
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
	high: Vector2i,
	approach: Vector2i
) -> Array[Vector2i]:
	var cost: PackedByteArray = world.move_cost
	var cols: int = world.map_cols
	var rows: int = world.map_rows
	var points: Array[Vector2i] = []
	var keys: Array[int] = []
	var along: Array[int] = []
	var across: Array[int] = []
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
				# The tile of the point by the rule of World.cell_of: a point on a tile border past
				# the middle of the map is in the tile before it (FixedMath.centre_side), and one on
				# the far edge of the map in the last tile.
				var cell: int = (
					mini(
						(
							FixedMath.centre_side(point.y, rows * World.MILLI_PER_TILE)
							/ World.MILLI_PER_TILE
						),
						rows - 1
					)
					* cols
				)
				cell += mini(
					(
						FixedMath.centre_side(point.x, cols * World.MILLI_PER_TILE)
						/ World.MILLI_PER_TILE
					),
					cols - 1
				)
				var open: bool = true
				for base: int in bases:
					if cost[base + cell] == 0:
						open = false
						break
				if not open:
					continue
				keys.append((i * i + j * j) * KEY_SHIFT + points.size())
				along.append(i * approach.x + j * approach.y)
				across.append(i * approach.y - j * approach.x)
				points.append(point)
		# A ring with no point inside the box means no later ring has one either, so stop early.
		# A ring whose points are all blocked says nothing about the later ones.
		if inside == 0:
			break
		if last_ring < 0 and points.size() >= count:
			last_ring = FixedMath.isqrt(2 * ring * ring)
		ring += 1
	var order: Array[int] = []
	for at: int in keys.size():
		order.append(at)
	order.sort_custom(
		func(left: int, right: int) -> bool:
			var left_ring: int = keys[left] / KEY_SHIFT
			var right_ring: int = keys[right] / KEY_SHIFT
			if left_ring != right_ring:
				return left_ring < right_ring
			if along[left] != along[right]:
				return along[left] > along[right]
			if across[left] != across[right]:
				return across[left] > across[right]
			return left < right
	)
	var slots: Array[Vector2i] = []
	for at: int in order:
		if slots.size() == count:
			break
		slots.append(points[at])
	return slots


## The position in `unit_indices` of the unassigned unit nearest to `slot` (squared distance),
## ties by `_prefer` (along, across, lower id). Independent of the order of `unit_indices`. The columns are the World's
## pos_x, pos_y and unit_id, aliased by the caller.
static func _nearest_free(
	pos_x: PackedInt32Array,
	pos_y: PackedInt32Array,
	ids: PackedInt32Array,
	unit_indices: PackedInt32Array,
	taken: PackedByteArray,
	slot: Vector2i,
	approach: Vector2i
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
		elif d2 == best_d2 and _prefer(pos_x, pos_y, ids, row, unit_indices[best], slot, approach):
			best = k
	return best


## Whether `row` beats `held` for `slot` on an equal distance: the larger offset along the approach,
## then across it, then the lower id. The first two are the same after a half turn of everything.
static func _prefer(
	pos_x: PackedInt32Array,
	pos_y: PackedInt32Array,
	ids: PackedInt32Array,
	row: int,
	held: int,
	slot: Vector2i,
	approach: Vector2i
) -> bool:
	var ax: int = pos_x[row] - slot.x
	var ay: int = pos_y[row] - slot.y
	var bx: int = pos_x[held] - slot.x
	var by: int = pos_y[held] - slot.y
	var along_a: int = ax * approach.x + ay * approach.y
	var along_b: int = bx * approach.x + by * approach.y
	if along_a != along_b:
		return along_a > along_b
	var across_a: int = ax * approach.y - ay * approach.x
	var across_b: int = bx * approach.y - by * approach.x
	if across_a != across_b:
		return across_a > across_b
	return ids[row] < ids[held]
