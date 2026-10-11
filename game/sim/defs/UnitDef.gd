class_name UnitDef
extends Resource
## Stats of one unit type (ADR 0003 section 6). Integers only. Distances are milli-tiles and
## speed is milli-tiles per tick. The sim copies these into World at match start and never
## reads the Resource during a tick. Unit art is found from type_id by convention.
## type_id names the type, so it must be set and unique per definition. World.from_scenario
## merges definitions with the same type_id into one type, and the first one it meets wins.
## display_name is the name the HUD shows. Empty means the HUD shows type_id.

@export var type_id: StringName = &""
@export var display_name: String = ""
@export var speed: int = 0
@export var radius: int = 0
@export var selection_radius: int = 0
@export var formation_spacing: int = 0
