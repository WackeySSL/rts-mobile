class_name PlacementSpiral
extends RefCounted
## The fixed spiral of building slots around a base (ADR 0020 section 4, plan row P83). A slot is a
## lattice cell: the footprint's top-left tile is the base's origin plus the cell times the stride
## (`AiDef.place_stride_tiles`), so neighbouring slots leave a free tile between any two footprints.
## The centre cell (0, 0) is the base itself and is not a slot. Ring k holds the cells whose larger
## absolute coordinate is k, 8 * k of them, walked clockwise on the screen (y grows downwards):
## along the top row from its left end, down the right column, back along the bottom row and up the
## left column, each side holding its starting corner and not the next, so no cell repeats. Pure
## integers; no state.


## The first `count` slots as flat (column, line) pairs, ring 1 first: `count` * 2 ints, none for a
## `count` of 0 or less.
static func cells(count: int) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	var ring: int = 1
	while found.size() < count * 2:
		_append_ring(found, ring)
		ring += 1
	found.resize(maxi(count, 0) * 2)
	return found


## Ring `ring` (1 or more) after the cells already in `found`.
static func _append_ring(found: PackedInt32Array, ring: int) -> void:
	for x: int in range(-ring, ring + 1):
		_add(found, x, -ring)
	for y: int in range(1 - ring, ring + 1):
		_add(found, ring, y)
	for x: int in range(ring - 1, -ring - 1, -1):
		_add(found, x, ring)
	for y: int in range(ring - 1, -ring, -1):
		_add(found, -ring, y)


static func _add(found: PackedInt32Array, column: int, line: int) -> void:
	found.append(column)
	found.append(line)
