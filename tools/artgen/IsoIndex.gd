class_name IsoIndex
extends Resource
## `assets/art/iso/index.tres` (ADR 0023 section 5): every art id's sheet, both factions, sorted by
## art id. Written by `bash scripts/gen-art.sh`; the per-match atlas bake (P113) loads it once.

const PATH: String = "res://assets/art/iso/index.tres"

@export var sheets: Array[IsoSheetDef] = []


## The sheet of `art_id`, or null.
func sheet(art_id: StringName) -> IsoSheetDef:
	for found: IsoSheetDef in sheets:
		if found.art_id == art_id:
			return found
	return null
