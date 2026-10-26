class_name FactionDef
extends Resource
## One faction (ADR 0023 section 6): its names, its look and its roster. Plain data; the sim copies
## what it needs into World at match start and never reads the Resource during a tick. A type
## belongs to a faction through UnitDef.faction, which names `id`; the roster lists the types the
## scenario registers for the faction. No AI reference: the faction's dummy is the AiDef file
## data/ai/dummy_<id>.tres.

## The internal id, also the value of UnitDef.faction (`fossil`, `renew`).
@export var id: StringName = &""
## Shown in the UI (Derrick League, Lumen Accord).
@export var display_name: String = ""
## The art id of the emblem.
@export var emblem: StringName = &""
## The faction's key triad, light, mid and dark, as `#rrggbb` hex strings: art paints its team zones
## in these three and the atlas bake replaces them with the player's triad (ADR 0023 section 5).
## Hex strings, not a PackedColorArray: no colour type is allowed in game/sim (test_sim_purity).
@export var key_triad: PackedStringArray = PackedStringArray()
## Every unit and building type of the faction, which the scenario registers after its spawns.
@export var roster: Array[UnitDef] = []
