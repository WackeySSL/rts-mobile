class_name AudioCueTable
extends Resource
## The cues and the maps from what the sim reports to a cue id (ADR 0041 section 6). A weapon or
## type without a mapping takes its family's cue: a hitscan weapon (projectile speed 0) the
## `shot_hitscan` cue and any other `shot_shell`, an impact `impact_default`, a death the cue of its
## move class or the building's collapse. An empty id plays nothing. The instance is
## `res://data/audio_cues.tres`.

@export var cues: Array[AudioCueDef] = []
## Weapon id -> cue id.
@export var shot_cues: Dictionary[StringName, StringName] = {}
@export var impact_cues: Dictionary[StringName, StringName] = {}
@export var shot_hitscan: StringName = &""
@export var shot_shell: StringName = &""
@export var impact_default: StringName = &""
@export var mine_blast: StringName = &""
@export var repaired: StringName = &""
@export var unloaded: StringName = &""
@export var death_foot: StringName = &""
@export var death_vehicle: StringName = &""
@export var death_air: StringName = &""
@export var death_building: StringName = &""
## A sold building's pack-up (DIED flag 3).
@export var sold: StringName = &""
## An own unit comes out of its factory (SPAWNED of a mobile type, own rows only), an own building
## is placed (SPAWNED of a building type, own rows only) and a unit boards a carrier (DIED flag 2).
@export var unit_ready: StringName = &""
@export var building_placed: StringName = &""
@export var board: StringName = &""
## The strikes (`World.Event.STRIKE`, `Strike.Kind`): the rupture's launch when it is accepted and
## its landing at the landing tick, the blackout when it is fired and the sweep's hum.
@export var strike_rupture_launch: StringName = &""
@export var strike_rupture_land: StringName = &""
@export var strike_blackout: StringName = &""
@export var strike_sweep: StringName = &""


## The index of cue `cue_id` in `cues`, or -1.
func index_of(cue_id: StringName) -> int:
	for i: int in cues.size():
		if cues[i].id == cue_id:
			return i
	return -1
