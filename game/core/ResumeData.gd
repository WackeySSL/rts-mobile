class_name ResumeData
extends RefCounted
## What a valid resume file holds (ADR 0042 section 6), as `ResumeStore.read` returns it: the match
## setup, the log up to `tick`, the tick the match had reached when the app went to the background,
## and the build that wrote it. The restore (plan P515) replays `replay` from tick 0 to `tick`.

## The match's setup (never a lesson: lessons are not resumed).
var setup: MatchSetup
## The recorded log: the local player's Commands, the AI's applied Commands and a checkpoint hash
## every `Replay.CHECKPOINT_PERIOD` ticks, up to the last tick played.
var replay: Replay
## The ticks the match had played when the file was written (the World's tick). Past the last
## checkpoint by less than one checkpoint period; the restore plays exactly this many ticks.
var tick: int = 0
## The local player's id.
var local_player: int = 0
## `application/config/version` of the build that wrote the file.
var app_version: String = ""
## `World.defs_hash()` of the match that wrote the file (an int64).
var defs_hash: int = 0
