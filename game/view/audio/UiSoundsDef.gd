class_name UiSoundsDef
extends Resource
## The interface sounds of `UiSounds` (ADR 0041 section 4): one stream, level and priority per
## cue. The instance is `res://data/audio_ui_sounds.tres` (CLAUDE.md rule 5). A cue without a
## stream stays silent. View only, never in `defs_hash`.

@export var click_stream: AudioStream
@export var click_db: float = 0.0
@export var click_priority: int = 0
## The order chirps: `UiSounds` takes them in turn, so a repeated order never repeats its sound.
@export var order_streams: Array[AudioStream] = []
@export var order_db: float = -4.0
@export var order_priority: int = 1
@export var alert_stream: AudioStream
@export var alert_db: float = 0.0
@export var alert_priority: int = 2
## A structure is finished and waits to be placed (the Ready chip), the power turns low, and a
## building's repair is switched on.
@export var ready_stream: AudioStream
@export var ready_db: float = 0.0
@export var ready_priority: int = 2
@export var power_stream: AudioStream
@export var power_db: float = 0.0
@export var power_priority: int = 2
@export var mend_stream: AudioStream
@export var mend_db: float = 0.0
@export var mend_priority: int = 1
## Voices one cue may hold at once on the Ui bus; a new one replaces its own oldest.
@export var max_voices: int = 1
