class_name UiSoundsDef
extends Resource
## The interface sounds of `UiSounds` (ADR 0041 section 4): one stream, level and priority per
## cue. The instance is `res://data/audio_ui_sounds.tres` (CLAUDE.md rule 5). A cue without a
## stream stays silent; the files come with P505 and P507. View only, never in `defs_hash`.

@export var click_stream: AudioStream
@export var click_db: float = 0.0
@export var click_priority: int = 0
@export var order_stream: AudioStream
@export var order_db: float = -4.0
@export var order_priority: int = 1
@export var alert_stream: AudioStream
@export var alert_db: float = 0.0
@export var alert_priority: int = 2
## Voices one cue may hold at once on the Ui bus; a new one replaces its own oldest.
@export var max_voices: int = 1
