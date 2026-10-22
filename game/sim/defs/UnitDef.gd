class_name UnitDef
extends Resource
## Stats of one unit type (ADR 0003 section 6, ADR 0009 section 1). Integers only. Distances are
## milli-tiles and speed is milli-tiles per tick. The sim copies these into World at match start
## and never reads the Resource during a tick. Unit art is found from type_id by convention.
## type_id names the type, so it must be set and unique per definition. World.from_scenario
## merges definitions with the same type_id into one type, and the first one it meets wins.

@export var type_id: StringName = &""
## Shown in the UI. Empty reads as type_id capitalised.
@export var display_name: String = ""
@export var speed: int = 0
@export var radius: int = 0
@export var selection_radius: int = 0
@export var formation_spacing: int = 0
## At least 1 by default, so a definition built in a test never spawns dead.
@export var max_hp: int = 1
@export_enum("Infantry", "Light", "Heavy", "Building") var armour: int = 0
@export_enum("Foot", "Wheeled", "Tracked") var move_class: int = 0
## How far the unit sees (fog), and how far an attack-moving unit looks for a target. Milli-tiles.
@export var sight_range: int = 0
@export var acquire_range: int = 0
## Null = unarmed.
@export var weapon: WeaponDef

## Production (ADR 0018 section 9). Credits and ticks at 15 Hz. A type with tab -1 is not buildable
## (a scenario places it), which is every unit file of Phase 2 and the Headquarters.
@export var cost: int = 0
@export var build_ticks: int = 0
## The sidebar tab that builds this type: -1 none, else a World.Tab (0 Structures, 1 Infantry,
## 2 Vehicles).
@export_enum("None:-1", "Structures:0", "Infantry:1", "Vehicles:2") var tab: int = -1
## The type the player must own a building of before this one can be queued. Null = none.
@export var requires: UnitDef
## Cargo capacity in credits. 0 = not a harvester; else a multiple of RulesDef.credits_per_ore.
@export var harvest_capacity: int = 0
