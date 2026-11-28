class_name TerrainKit
extends RefCounted
## Which kit piece a ground cell gets (ADR 0053 section 7, plan P656d1). Pure: static functions of
## the kit's mapping (`TerrainKitDef`), terrain ids and a cell's coordinates. No Node, no randomness
## (rule 3): the variant comes from a fixed integer hash of the cell, so a cell looks the same in
## every match and on every device. The ground layers stay flat (amendment A2): rock has no lip
## here, a blend or a shore is exactly its 128 x 64 diamond.
##
## Neighbours: `edges` are ne = (x, y - 1), se = (x + 1, y), sw = (x, y + 1), nw = (x - 1, y);
## `diagonals` are n = (x - 1, y - 1), e = (x + 1, y - 1), s = (x + 1, y + 1), w = (x - 1, y + 1).
## An empty id is off the map and counts as the cell's own terrain.

const EDGES: Array[StringName] = [&"ne", &"se", &"sw", &"nw"]
const DIAGONALS: Array[StringName] = [&"n", &"e", &"s", &"w"]
const BASE: StringName = &"base"
const BLEND: StringName = &"blend"
const SHORE: StringName = &"shore"
## The cell offset of each edge and each diagonal neighbour, in the order above.
const EDGE_STEPS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
const DIAGONAL_STEPS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)
]
## The two edges (indexes into EDGES) that meet at each diagonal: n = nw + ne, e = ne + se, ...
const _CORNER_EDGES: Array[Vector2i] = [
	Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)
]


## A fixed 32-bit mix of a cell's coordinates.
static func cell_hash(x: int, y: int) -> int:
	var h: int = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return h ^ (h >> 16)


## The variant of `kind` (a base, a wall top) of `terrain` on cell (`x`, `y`): -1 when the kit has
## none. The kit's variants are plain or stone (`stone_variants` of `terrain/kind`). A cell is a
## stone variant when its hash slice is under `stone_permille` scaled by `cluster_noise`, so stones
## come in patches with bare stretches between; another hash slice then picks which stone, or which
## plain variant. One function serves the flat ground and the raised walls (one hash rule), so a
## rock cell shows the same variant number either way when the two kinds list the same variants.
static func variant(
	kit: TerrainKitDef, terrain: StringName, kind: StringName, x: int, y: int
) -> int:
	var all: PackedInt32Array = kit.variants_of(terrain, kind)
	if all.is_empty():
		return -1
	var rule: StringName = StringName("%s/%s" % [terrain, kind])
	var marked: PackedInt32Array = kit.stone_variants.get(rule, PackedInt32Array())
	var stones: PackedInt32Array = PackedInt32Array()
	var plain: PackedInt32Array = PackedInt32Array()
	for number: int in all:
		if marked.has(number):
			stones.append(number)
		else:
			plain.append(number)
	var h: int = cell_hash(x, y)
	if not stones.is_empty():
		var chance: int = stone_chance(
			kit.stone_permille.get(rule, 0), kit.stone_cluster_cells, x, y
		)
		if plain.is_empty() or (h >> 8) % 1000 < chance:
			return stones[(h >> 16) % stones.size()]
	return plain[(h >> 12) % plain.size()]


## The chance, per mille, of a stone variant on (`x`, `y`): `permille` scaled by the cluster noise.
static func stone_chance(permille: int, cells: int, x: int, y: int) -> int:
	return permille * cluster_noise(x, y, cells) / 1000


## A low-frequency value noise of (`x`, `y`), 0 to 1000: a hashed value on every `cells`-th lattice
## point, linearly interpolated between them (integers only). `cells` 0 or less: 1000, no clusters.
@warning_ignore("integer_division")
static func cluster_noise(x: int, y: int, cells: int) -> int:
	if cells <= 0:
		return 1000
	var fx: int = posmod(x, cells) * 256 / cells
	var fy: int = posmod(y, cells) * 256 / cells
	var gx: int = (x - posmod(x, cells)) / cells
	var gy: int = (y - posmod(y, cells)) / cells
	var top: int = _lattice(gx, gy) * (256 - fx) + _lattice(gx + 1, gy) * fx
	var bottom: int = _lattice(gx, gy + 1) * (256 - fx) + _lattice(gx + 1, gy + 1) * fx
	return (top * (256 - fy) + bottom * fy) >> 16


static func _lattice(gx: int, gy: int) -> int:
	return cell_hash(gx + 4099, gy + 7919) % 1001


## The key of the base piece of `terrain` on (`x`, `y`), "" when the kit has no base piece.
static func base_key(kit: TerrainKitDef, terrain: StringName, x: int, y: int) -> StringName:
	var number: int = variant(kit, terrain, BASE, x, y)
	return TerrainKitDef.key(terrain, BASE, StringName(str(number))) if number >= 0 else &""


## The key of the edge piece of a cell of `own` with the neighbours `edges` (ne, se, sw, nw) and
## `diagonals` (n, e, s, w), "" for none. Water gets a shore on its own cell; a land terrain in
## `kit.priority` gets the blend of the highest-priority terrain next to it (ore > scrub > sand >
## grass); rock and the rest get none (flat, A2). A mask the kit has no piece for takes the nearest.
static func edge_key(
	kit: TerrainKitDef, own: StringName, edges: Array[StringName], diagonals: Array[StringName]
) -> StringName:
	if _has_kind(kit, own, SHORE):
		var mask: StringName = _shore_mask(_differs(own, edges), _differs(own, diagonals))
		return _existing(kit, own, SHORE, mask)
	var rank: int = kit.priority.find(own)
	if rank < 0:
		return &""
	for higher: int in rank:
		var terrain: StringName = StringName(kit.priority[higher])
		if not _has_kind(kit, terrain, BLEND):
			continue
		var hit: StringName = _blend_mask(_equals(terrain, edges), _equals(terrain, diagonals))
		var key: StringName = _existing(kit, terrain, BLEND, hit)
		if key != &"":
			return key
	return &""


static func _has_kind(kit: TerrainKitDef, terrain: StringName, kind: StringName) -> bool:
	var kinds: PackedStringArray = kit.kinds.get(terrain, PackedStringArray())
	return kinds.has(kind)


static func _existing(
	kit: TerrainKitDef, terrain: StringName, kind: StringName, mask: StringName
) -> StringName:
	if mask == &"" or not kit.has_piece(terrain, kind, mask):
		return &""
	return TerrainKitDef.key(terrain, kind, mask)


## Bit i is set when `around[i]` is a terrain other than `own` (off the map is not).
static func _differs(own: StringName, around: Array[StringName]) -> int:
	var bits: int = 0
	for at: int in around.size():
		if around[at] != &"" and around[at] != own:
			bits |= 1 << at
	return bits


static func _equals(terrain: StringName, around: Array[StringName]) -> int:
	var bits: int = 0
	for at: int in around.size():
		if around[at] == terrain:
			bits |= 1 << at
	return bits


## The blend mask for the edge bits and diagonal bits that hold the higher terrain: one edge is
## `side_<edge>`, no edge and a diagonal is `corner_<diag>`; two or more edges (no piece) take the
## first edge's side, several diagonals the first diagonal's corner.
static func _blend_mask(edge_bits: int, diagonal_bits: int) -> StringName:
	if edge_bits != 0:
		return StringName("side_%s" % EDGES[_lowest(edge_bits)])
	if diagonal_bits != 0:
		return StringName("corner_%s" % DIAGONALS[_lowest(diagonal_bits)])
	return &""


## The shore mask for the edge and diagonal bits that hold another terrain: one edge `side_<edge>`,
## two adjacent edges `outer_<diag>`, only a diagonal `inner_<diag>`. No piece (two opposite edges,
## three or four): the first outer corner they hold, else the first edge's side; several diagonals
## alone: the first one's inner corner.
static func _shore_mask(edge_bits: int, diagonal_bits: int) -> StringName:
	if edge_bits == 0:
		if diagonal_bits == 0:
			return &""
		return StringName("inner_%s" % DIAGONALS[_lowest(diagonal_bits)])
	if _count(edge_bits) > 1:
		for diagonal: int in 4:
			var pair: Vector2i = _CORNER_EDGES[diagonal]
			if edge_bits & (1 << pair.x) != 0 and edge_bits & (1 << pair.y) != 0:
				return StringName("outer_%s" % DIAGONALS[diagonal])
	return StringName("side_%s" % EDGES[_lowest(edge_bits)])


static func _lowest(bits: int) -> int:
	var at: int = 0
	while bits & (1 << at) == 0:
		at += 1
	return at


static func _count(bits: int) -> int:
	var total: int = 0
	for at: int in 4:
		total += (bits >> at) & 1
	return total
