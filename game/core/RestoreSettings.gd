class_name RestoreSettings
extends Resource
## The numbers of the match restore (ADR 0042 section 6): view-side data, never loaded by
## `game/sim` and not in `defs_hash`. The instance is `res://data/restore_settings.tres`; the
## defaults here are the ones that file holds.

## How long one frame may spend replaying ticks, in milliseconds. The restore screen is opaque and
## static, so nearly the whole frame goes to ticks; the progress bar still redraws about 19 times a
## second and a Cancel tap is seen within a frame.
@export var restore_slice_ms: int = 50
