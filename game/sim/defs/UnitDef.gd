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
## The faction that owns the type (ADR 0023 section 6): a FactionDef `id`. Empty = any faction, so
## a producer of any faction may queue it. A BuildingDef has the field through UnitDef.
@export var faction: StringName = &""
@export var speed: int = 0
@export var radius: int = 0
@export var selection_radius: int = 0
@export var formation_spacing: int = 0
## At least 1 by default, so a definition built in a test never spawns dead.
@export var max_hp: int = 1
@export_enum("Infantry", "Light", "Heavy", "Building") var armour: int = 0
@export_enum("Foot", "Wheeled", "Tracked", "Air") var move_class: int = 0
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
## 2 Vehicles, 3 Flight, 4 Research; ADR 0036 section 2).
@export_enum("None:-1", "Structures:0", "Infantry:1", "Vehicles:2", "Flight:3", "Research:4")
var tab: int = -1
## The type the player must own a building of before this one can be queued. Null = none.
@export var requires: UnitDef
## Cargo capacity in credits. 0 = not a harvester; else a multiple of RulesDef.credits_per_ore.
@export var harvest_capacity: int = 0

## Air (ADR 0036 section 2), AIR only, a data test. A low-flying row (a drone squad) is hit by the
## LOW_AIR weapon bit. `ammo` is the shots before a return (0 = no limit) and `rearm_ticks` the
## ticks to refill from 0 on a pad.
@export var low_flying: bool = false
@export var ammo: int = 0
@export var rearm_ticks: int = 0

## The repair role (ADR 0036 section 2, ADR 0037 section 2); a building or a squad may hold it.
## `repair_classes` is a move-class bit mask (FOOT 1, WHEELED 2, TRACKED 4, AIR 8), 0 = no role.
## `repair_hp` is gained per `repair_period_ticks`, `repair_cost_percent` is the share of the unit's
## cost a repair from 0 to full costs, `repair_reach_milli` the service reach, `repair_slots` the
## rows served per turn (1-8, or 0 only with pads) and `repair_seek_milli` the reach in which an
## idle mobile row walks to a hurt one (0 = never).
@export var repair_classes: int = 0
@export var repair_hp: int = 0
@export var repair_period_ticks: int = 1
@export var repair_cost_percent: int = 0
@export var repair_reach_milli: int = 0
@export var repair_slots: int = 0
@export var repair_seek_milli: int = 0

## The carrier role (ADR 0036 sections 2 and 8): the squads a carrier holds (0 = not a carrier) and
## a move-class bit mask of who may board (FOOT 1, WHEELED 2, TRACKED 4, AIR 8; transports take 1).
@export var carry_slots: int = 0
@export var carry_classes: int = 0
