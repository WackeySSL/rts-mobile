class_name WallKit
extends RefCounted
## The raised rock walls' piece choice (ADR 0053 section 7, amendment A1 and A3, plan P656d2): pure
## and static, no Node and no random. A raised cell draws up to three pieces of the kit's `rock`
## terrain, in this order: its front face, its top and its back rim. A face is drawn where a front
## edge neighbour is not raised, a rim where a back edge neighbour is not raised, and the top
## always. A cell off the map counts as not raised, so a wall at the map's edge shows its face.
## The masks: front bit 1 is (c + 1, r) open (the south-east edge), bit 2 is (c, r + 1) open (the
## south-west edge); back bit 1 is (c, r - 1) open (the north-east edge), bit 2 is (c - 1, r) open
## (the north-west edge), bit 4 is the diagonal (c - 1, r - 1) open.

const TERRAIN: StringName = &"rock"
const TOP: StringName = &"wall_top"
const FACE: StringName = &"wall_face"
const RIM: StringName = &"wall_rim"
const KINDS: Array[StringName] = [FACE, TOP, RIM]  ## The draw order of a cell's pieces.
const KIT_PATH: String = "res://assets/art/terrain/kit.tres"  ## When a caller passes no kit.
## Front mask (0 to 3) -> the face's mask name, "" for none (both neighbours are raised).
const FACE_OF: PackedStringArray = ["", "se", "sw", "s"]
## Back mask (0 to 7) -> the rim's mask name, "" for none. With neither edge neighbour open only the
## diagonal can leave a rim: the inner corner.
const RIM_OF: PackedStringArray = ["", "ne", "nw", "n", "inner_n", "ne", "nw", "n"]


## Whether cell (`col`, `row`) is raised in `raised` (a byte per cell, `cols` wide); off the map no.
static func is_raised(raised: PackedByteArray, cols: int, col: int, row: int) -> bool:
	if col < 0 or row < 0 or col >= cols:
		return false
	var at: int = row * cols + col
	return at < raised.size() and raised[at] != 0


## The front mask of a cell: which of its two front edge neighbours are not raised.
static func front_mask(raised: PackedByteArray, cols: int, col: int, row: int) -> int:
	return (
		int(not is_raised(raised, cols, col + 1, row))
		| (int(not is_raised(raised, cols, col, row + 1)) << 1)
	)


## The back mask of a cell: which back edge neighbours and the back diagonal are not raised.
static func back_mask(raised: PackedByteArray, cols: int, col: int, row: int) -> int:
	return (
		int(not is_raised(raised, cols, col, row - 1))
		| (int(not is_raised(raised, cols, col - 1, row)) << 1)
		| (int(not is_raised(raised, cols, col - 1, row - 1)) << 2)
	)


## The kit key of the face for front mask `mask`, `&""` for none.
static func face_key(mask: int) -> StringName:
	return TerrainKitDef.key(TERRAIN, FACE, StringName(FACE_OF[mask])) if mask != 0 else &""


## The kit key of the top of cell (`col`, `row`): `TerrainKit.variant`, the one hash and stone rule
## of the flat ground, over the kit's `rock/wall_top` variants (`&""` when it has none). No kit: the
## standard one.
static func top_key(col: int, row: int, kit: TerrainKitDef = null) -> StringName:
	var def: TerrainKitDef = kit if kit != null else load(KIT_PATH)
	var number: int = TerrainKit.variant(def, TERRAIN, TOP, col, row)
	return TerrainKitDef.key(TERRAIN, TOP, StringName(str(number))) if number >= 0 else &""


## The kit key of the rim for back mask `mask`, `&""` for none.
static func rim_key(mask: int) -> StringName:
	var name: String = RIM_OF[mask]
	return TerrainKitDef.key(TERRAIN, RIM, StringName(name)) if name != "" else &""


## The keys of the pieces of raised cell (`col`, `row`) in draw order (face, top, rim), a slot
## `&""` when that piece is not drawn: always three entries, so a layer indexes by kind.
static func pieces(
	raised: PackedByteArray, cols: int, col: int, row: int, kit: TerrainKitDef = null
) -> Array[StringName]:
	return [
		face_key(front_mask(raised, cols, col, row)),
		top_key(col, row, kit),
		rim_key(back_mask(raised, cols, col, row)),
	]


## Every key the choice can return, for the atlas to pack: 3 faces, the kit's wall tops, 4 rims.
static func all_keys(kit: TerrainKitDef = null) -> Array[StringName]:
	var def: TerrainKitDef = kit if kit != null else load(KIT_PATH)
	var keys: Array[StringName] = []
	for mask: String in FACE_OF:
		if mask != "":
			keys.append(TerrainKitDef.key(TERRAIN, FACE, StringName(mask)))
	for variant: int in def.variants_of(TERRAIN, TOP):
		keys.append(TerrainKitDef.key(TERRAIN, TOP, StringName(str(variant))))
	for mask: String in ["ne", "nw", "n", "inner_n"]:
		keys.append(TerrainKitDef.key(TERRAIN, RIM, StringName(mask)))
	return keys
