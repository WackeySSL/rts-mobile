class_name UnitDef
extends Resource
## Stats of one unit type (ADR 0003 section 6). Integers only. Distances are milli-tiles and
## speed is milli-tiles per tick. The sim copies these into World at match start and never
## reads the Resource during a tick. Unit art is found from type_id by convention.

@export var type_id: StringName = &""
@export var speed: int = 0
@export var radius: int = 0
@export var selection_radius: int = 0
@export var formation_spacing: int = 0
