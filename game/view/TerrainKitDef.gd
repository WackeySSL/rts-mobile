class_name TerrainKitDef
extends Resource
## The terrain kit's art mapping (ADR 0053 section 7): which PNG draws which terrain, kind, and mask
## or variant. Data only. It holds no balance number and no choice logic and no cell hash: which
## piece a cell gets is `TerrainKit`'s job (P656d). `assets/art/terrain/kit.tres` is the one file.
## A piece is addressed as `terrain/kind/mask`; a `base` piece's mask is its variant ("0" to
## `variants - 1`), a `road` piece's terrain is the ground it lies on.

const TILE: Vector2i = Vector2i(128, 64)  ## A ground diamond in texels (drawn at scale 0.5).
## A raised rock cell's rise, texels: one diamond height (ADR 0053 section 7, amendment A1).
const RISE_MAX: int = 64
## A wall piece's canvas, texels, and where the cell's ground centre lies in it (amendment A3): the
## prism fills rows 8 to 136, `RIM_MAX` rows above it may hold the ragged back edge.
const WALL_CANVAS: Vector2i = Vector2i(128, 136)
const WALL_ORIGIN: Vector2i = Vector2i(64, 104)
const RIM_MAX: int = 8
const DEFAULT_VARIANTS: int = 4  ## Variants of a kind that `variant_counts` does not list.

@export var dir: String = "res://assets/art/terrain"  ## Where the PNGs are.
@export var terrains: PackedStringArray = PackedStringArray()  ## The sim terrains the kit draws.
## The land terrains that blend onto their neighbours, highest priority first: a terrain's blend
## piece is drawn on the cell of a lower one.
@export var priority: PackedStringArray = PackedStringArray()
## The stone rule (P656d1; Michael, 2026-11-28: stones in different sizes, tones and a random
## pattern). Keyed `<terrain>/<kind>` (`grass/base`, `rock/base`, `rock/wall_top`).
## `variant_counts`:
## the variants a kind has, numbered from 0 (a key with no entry has 4). `stone_variants`: the
## indices that carry stones, the rest are plain (no entry: no stones). `stone_permille`: the base
## chance of a stone variant, 0 to 1000, scaled per cell by a value noise of period
## `stone_cluster_cells` (patches with stones and stretches with none; 0: no clusters).
@export var variant_counts: Dictionary[StringName, int] = {}
@export var stone_variants: Dictionary[StringName, PackedInt32Array] = {}
@export var stone_permille: Dictionary[StringName, int] = {}
@export var stone_cluster_cells: int = 10
@export var masks: Dictionary[StringName, PackedStringArray] = {}  ## Kind -> its mask names.
@export var kinds: Dictionary[StringName, PackedStringArray] = {}  ## Terrain -> the kinds it has.
@export var pieces: Dictionary[StringName, String] = {}  ## `terrain/kind/mask` -> PNG file name.

var _variants: Dictionary[StringName, PackedInt32Array] = {}  ## `variants_of` cache.


## The key of a piece.
static func key(terrain: StringName, kind: StringName, mask: StringName) -> StringName:
	return StringName("%s/%s/%s" % [terrain, kind, mask])


## The variant numbers of `kind` of `terrain` that have a piece: 0 to its count minus 1 (4 when
## `variant_counts` has no entry). Any count: a kit with 8 grass bases lists 8.
func variants_of(terrain: StringName, kind: StringName) -> PackedInt32Array:
	var cache_key: StringName = StringName("%s/%s" % [terrain, kind])
	if _variants.has(cache_key):
		return _variants[cache_key]
	var found: PackedInt32Array = PackedInt32Array()
	for number: int in variant_counts.get(cache_key, DEFAULT_VARIANTS):
		if has_piece(terrain, kind, StringName(str(number))):
			found.append(number)
	_variants[cache_key] = found
	return found


## Whether the kit has that piece.
func has_piece(terrain: StringName, kind: StringName, mask: StringName) -> bool:
	return pieces.has(key(terrain, kind, mask))


## The piece's PNG path, or "" when the kit has none (the caller falls back to the SVG diamond).
func path_of(terrain: StringName, kind: StringName, mask: StringName) -> String:
	var file: String = pieces.get(key(terrain, kind, mask), "")
	return dir.path_join(file) if file != "" else ""
