class_name TerrainDef
extends Resource
## One kind of ground (ADR 0008 section 1). A map row writes it as `symbol`.

## One character.
@export var symbol: String = ""
@export var id: StringName = &""
## Movement cost per UnitDef.move_class: foot, wheeled, tracked. 0 is blocked, 10 is normal and
## above 10 is slower ground for pathing, up to 40.
@export var cost: PackedInt32Array = PackedInt32Array([10, 10, 10])
