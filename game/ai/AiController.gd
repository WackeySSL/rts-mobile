class_name AiController
extends RefCounted
## One computer player (ADR 0020 section 2, plan row P83). A controller reads the match only
## through a `PlayerView`, answers with `Command`s appended to a list and keeps no Resource and no
## Node, so the tick job's walk (ADR 0020 section 3) stays green: a subclass copies its `AiDef` into
## ints and arrays when it is made. It uses no clock; its only random numbers come from `rng`, the
## match's stream for this player (`DetRandom.STREAM_AI_BASE` plus the player id).
##
## The driver (`AiDriver.think_all`, plan row P82) calls `think` on every tick where
## `(tick + think_offset) % think_period == 0`, each time with a fresh `PlayerView`. `think` itself
## does not test the tick: a call is a turn.

## The player the controller plays, from 1.
var player_id: int = 0
## Ticks between two thinks, and the shift that puts a think on a tick whose step does not end in a
## checkpoint (ADR 0020 section 2). 1 and 0 think on every tick.
var think_period: int = 1
var think_offset: int = 0
## The player's random stream. A controller that needs a draw takes it here and nowhere else.
var rng: DetRandom = null


## One turn: appends this player's Commands to `out` (the caller stamps and records them). The
## base class has nothing to do.
func think(_view: PlayerView, _out: Array[Command]) -> void:
	pass
