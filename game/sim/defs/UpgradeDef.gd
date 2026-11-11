class_name UpgradeDef
extends Resource
## One researchable upgrade (ADR 0036 section 2): one level, researched or not. The engineering
## centre (`requires`) researches it as a queue-only RESEARCH item. Plain data; the sim copies what
## it needs into World at match start. Integers only; times are ticks at 15 Hz.

enum Stat { DAMAGE_DEALT = 0, DAMAGE_TAKEN = 1, AMMO = 2 }

@export var id: StringName = &""
@export var display_name: String = ""
## A FactionDef `id`.
@export var faction: StringName = &""
@export var cost: int = 0
@export var research_ticks: int = 1
## The building whose owner may research it (the engineering centre). Null = none.
@export var requires: BuildingDef
@export_enum("Damage dealt:0", "Damage taken:1", "Ammo:2") var stat: int = 0
## A percent for the damage stats (100 = no change), an amount of extra shots for AMMO.
@export var value: int = 100
## The types it changes.
@export var applies_to: Array[UnitDef] = []
