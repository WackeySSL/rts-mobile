class_name Formation
extends RefCounted
## Formation slots for a group order (ADR 0003 section 4). Integers only and no state kept
## between calls. It runs once per command, never per tick, and is O(n^2) in the group size.

## A sort key is the squared lattice distance times this, plus the generation index (below it),
## so a plain sort puts nearer slots first and keeps generation order on ties.
const KEY_SHIFT: int = 1 << 20


## Sets goal_x/goal_y of the units at `unit_indices` (rows of `world`). The target is clamped to
## the map inset by the largest radius in the group, and the slots are spaced by the largest
## formation spacing in the group. Each slot, nearest to the target first, takes the nearest
## unassigned unit, ties to the lower id. Units left without a slot get the clamped target.
static func assign(
	world: World, unit_indices: PackedInt32Array, target_x: int, target_y: int
) -> void:
	var count: int = unit_indices.size()
	if count == 0:
		return
	var spacing: int = 1
	var radius: int = 0
	for row: int in unit_indices:
		spacing = maxi(spacing, world.type_spacing[world.type_index[row]])
		radius = maxi(radius, world.type_radius[world.type_index[row]])
	var low: Vector2i = Vector2i(mini(radius, world.map_w >> 1), mini(radius, world.map_h >> 1))
	var high: Vector2i = Vector2i(world.map_w, world.map_h) - low
	var centre: Vector2i = Vector2i(
		clampi(target_x, low.x, high.x), clampi(target_y, low.y, high.y)
	)
	for row: int in unit_indices:
		world.goal_x[row] = centre.x
		world.goal_y[row] = centre.y
	var taken: PackedByteArray = PackedByteArray()
	taken.resize(count)
	for slot: Vector2i in _slots(count, centre, spacing, low, high):
		var pick: int = _nearest_free(world, unit_indices, taken, slot)
		taken[pick] = 1
		world.goal_x[unit_indices[pick]] = slot.x
		world.goal_y[unit_indices[pick]] = slot.y


## Up to `count` slots inside [low, high], nearest to `centre` first. Candidates are the lattice
## points centre + spacing * (i, j), generated ring by ring (ring r: max(|i|, |j|) == r, row by
## row, j then i ascending). K is the first ring where rings 0..K hold `count` candidates. Rings
## up to isqrt(2 * K * K) are kept, since a ring-(K+1) point can be nearer than a ring-K corner.
static func _slots(
	count: int, centre: Vector2i, spacing: int, low: Vector2i, high: Vector2i
) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var keys: Array[int] = []
	var last_ring: int = -1
	var ring: int = 0
	# A ring r point is r * spacing away from the centre on an axis, and the centre is in the box,
	# so no ring beyond the box extent holds a point. This ends the loop on its own.
	var extent: int = maxi(high.x - low.x, high.y - low.y)
	while (last_ring < 0 or ring <= last_ring) and ring * spacing <= extent:
		var before: int = points.size()
		for j: int in range(-ring, ring + 1):
			# Inner rows only hold their two end points.
			for i: int in range(-ring, ring + 1, 1 if absi(j) == ring else maxi(2 * ring, 1)):
				var point: Vector2i = centre + Vector2i(i, j) * spacing
				if point.x < low.x or point.x > high.x or point.y < low.y or point.y > high.y:
					continue
				keys.append((i * i + j * j) * KEY_SHIFT + points.size())
				points.append(point)
		# A ring with no point inside the box means no later ring has one either, so stop early.
		if points.size() == before:
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
## ties to the lower id. Independent of the order of `unit_indices`.
static func _nearest_free(
	world: World, unit_indices: PackedInt32Array, taken: PackedByteArray, slot: Vector2i
) -> int:
	var best: int = -1
	var best_d2: int = 0
	for k: int in unit_indices.size():
		if taken[k] == 1:
			continue
		var row: int = unit_indices[k]
		var dx: int = world.pos_x[row] - slot.x
		var dy: int = world.pos_y[row] - slot.y
		var d2: int = dx * dx + dy * dy
		if best < 0 or d2 < best_d2:
			best = k
			best_d2 = d2
		elif d2 == best_d2 and world.unit_id[row] < world.unit_id[unit_indices[best]]:
			best = k
	return best
