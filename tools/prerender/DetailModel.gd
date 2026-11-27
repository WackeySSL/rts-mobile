class_name DetailModel
extends Resource
## The 3D detail of one art id, `assets/art/models/<faction>/<id>_detail.tres` (ADR 0053 section
## 5): materials and parts, plus a seed for the variation of repeated parts. Data only; the
## builder (`BakeMesh`, `BakeShapes`) is code. The footprint, anchors and cuts stay in the id's
## `ArtModel` and `IsoSheetDef`.

@export var art_id: StringName = &""
@export var faction: StringName = &""
@export var variation_seed: int = 0
@export var materials: Array[DetailMaterial] = []
@export var parts: Array[DetailPart] = []


## A value in [0, 1) that depends only on the three integers: an integer hash, no random stream,
## so a bake gives the same model every time.
static func hash01(seed_value: int, a: int, b: int) -> float:
	var h: int = (seed_value * 73856093) ^ (a * 19349663) ^ (b * 83492791)
	h = ((h >> 15) ^ h) * 0x2C1B3C6D & 0x7FFFFFFF
	h = ((h >> 12) ^ h) * 0x297A2D39 & 0x7FFFFFFF
	return float((h >> 8) ^ (h & 0xFFFFFF)) / 16777216.0


## The model in `path`, or null (with an error) when it is not a `DetailModel`.
static func read(path: String) -> DetailModel:
	var found: DetailModel = load(path) as DetailModel
	if found == null:
		push_error("%s is not a DetailModel" % path)
	return found


## The sheet parts the model has pieces for, in file order.
func part_names() -> Array[StringName]:
	var found: Array[StringName] = []
	for piece: DetailPart in parts:
		if piece.part not in found:
			found.append(piece.part)
	return found


func material_named(name: StringName) -> DetailMaterial:
	for found: DetailMaterial in materials:
		if found.id == name:
			return found
	return null


## What is wrong with the data, one line each; empty when it is sound.
func problems() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for index: int in parts.size():
		var piece: DetailPart = parts[index]
		if piece.shape not in DetailPart.SHAPES:
			found.append("%s part %d: unknown shape %s" % [art_id, index, piece.shape])
		if material_named(piece.material) == null:
			found.append("%s part %d: unknown material %s" % [art_id, index, piece.material])
		if piece.count < 1:
			found.append("%s part %d: count under 1" % [art_id, index])
	return found


## Builds the pieces of sheet part `part` into `m`.
func build(part: StringName, m: BakeMesh) -> void:
	for index: int in parts.size():
		var piece: DetailPart = parts[index]
		if piece.part != part:
			continue
		for side: int in 2 if piece.mirror else 1:
			for copy: int in piece.count:
				var h: float = hash01(variation_seed, index, copy * 2 + side)
				var shift: Vector3 = piece.step * (float(copy) + piece.jitter * (h - 0.5))
				m.offset = shift * Vector3(1.0, -1.0 if side == 1 else 1.0, 1.0)
				piece.emit(m, side == 1)
	m.offset = Vector3.ZERO
