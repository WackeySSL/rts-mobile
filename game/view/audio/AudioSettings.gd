class_name AudioSettings
extends Resource
## Every number of the audio service (ADR 0041 sections 2, 3, 5 and 6): view only, never loaded by
## `game/sim` and not in `defs_hash`. The instance is `res://data/audio_settings.tres`, where all
## tuning happens (CLAUDE.md rule 5). The defaults here are the ones that file holds. A test that
## wants another value calls `duplicate()` first.

## Volume steps per bus (ADR 0041 section 2): a step is an int from 0 to `steps`, step 0 mutes the
## bus and `steps` is full volume. The player's Sound setting sets Sfx and Ui together.
@export var steps: int = 10
@export var default_music_step: int = 7
@export var default_sfx_step: int = 10
@export var default_ui_step: int = 10

## The pool (section 3): made once at the autoload's `_ready`, never grown.
@export var world_voices: int = 16
@export var ui_voices: int = 4
## New world voices one tick may start; the rest are dropped.
@export var voices_per_tick: int = 6
## Off-screen events farther than this from the view are not played (BattleSounds, P502).
@export var hear_margin_px: float = 128.0
## World voice reach and its attenuation exponent (AudioStreamPlayer2D). The distance is measured
## in canvas space (screen px of the base size), not in world px; the zoom check is P502's.
@export var max_distance: float = 1400.0
@export var attenuation: float = 1.0
## Same-cue events inside this window coalesce into one voice, louder by `stack_db` (P502).
@export var cooldown_ms: int = 80
@export var stack_db: float = 2.0

## Music (P501b): the crossfade, and the duck under a strike or a sting.
@export var crossfade_ms: int = 1500
@export var duck_db: float = 6.0
@export var duck_ms: int = 600

## The Master fade in and out when a mute reason is added or cleared, and the level it fades to.
@export var fade_ms: int = 150
@export var mute_floor_db: float = -80.0
