class_name AudioCueDef
extends Resource
## One battle sound (ADR 0041 section 6): its id, its variants, level, pitch steps and the limits
## the voice pool and `BattleSounds` apply. View data, never loaded by `game/sim` and not in
## `defs_hash`; the instances live in `data/audio_cues.tres` (CLAUDE.md rule 5).

@export var id: StringName = &""
## The variants. Empty until the real files exist (P504); then `BattleSounds` makes `variants`
## placeholder tones from `tone_hz`, `tone_ms` and `noise_permille` (`PlaceholderTone`).
@export var streams: Array[AudioStream] = []
@export var volume_db: float = 0.0
## Pitch steps in milli (1000 = 1.0). Variant and step are picked from `(id * 31 + tick)`, with no
## random generator (ADR 0041 section 4).
@export var pitch_steps: PackedInt32Array = PackedInt32Array([1000])
## Same-cue events inside this window coalesce into one voice; negative takes
## `AudioSettings.cooldown_ms`.
@export var cooldown_ms: int = -1
@export var priority: int = 0
## Voices of this cue that may play at once; 0 means only the pool limits it.
@export var max_voices: int = 0
## Events of this cue in one tick that make a coalesced voice louder: `stack_db` for each one after
## the first, up to this many.
@export var max_stack: int = 3
## The placeholder tone: frequency, length and the share of noise in permille.
@export var tone_hz: int = 220
@export var tone_ms: int = 120
@export var noise_permille: int = 0
@export var variants: int = 1
