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

@export var dir: String = "res://assets/art/terrain"  ## Where the PNGs are.
@export var terrains: PackedStringArray = PackedStringArray()  ## The sim terrains the kit draws.
@export var variants: int = 4  ## Base pieces per terrain.
## The land terrains that blend onto their neighbours, highest priority first: a terrain's blend
## piece is drawn on the cell of a lower one.
@export var priority: PackedStringArray = PackedStringArray()
## Terrain -> the boulder variant shows on one cell in this many (as P656d1 declares it).
@export var boulder_one_in: Dictionary[StringName, int] = {}
@export var masks: Dictionary[StringName, PackedStringArray] = {}  ## Kind -> its mask names.
@export var kinds: Dictionary[StringName, PackedStringArray] = {}  ## Terrain -> the kinds it has.
@export var pieces: Dictionary[StringName, String] = {}  ## `terrain/kind/mask` -> PNG file name.


## The key of a piece.
static func key(terrain: StringName, kind: StringName, mask: StringName) -> StringName:
	return StringName("%s/%s/%s" % [terrain, kind, mask])


## Whether the kit has that piece.
func has_piece(terrain: StringName, kind: StringName, mask: StringName) -> bool:
	return pieces.has(key(terrain, kind, mask))


## The piece's PNG path, or "" when the kit has none (the caller falls back to the SVG diamond).
func path_of(terrain: StringName, kind: StringName, mask: StringName) -> String:
	var file: String = pieces.get(key(terrain, kind, mask), "")
	return dir.path_join(file) if file != "" else ""
