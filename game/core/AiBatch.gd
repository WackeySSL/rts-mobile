class_name AiBatch
extends RefCounted
## The AI Commands one tick's thinks made, kept until the next tick's job collects them (ADR 0038
## section 1). Pure data: no Node, no Resource, no rule. At most one batch is in flight, so one
## holder per match is enough; the runner's TickJob owns it.

## The Commands of the thinks, in think order and, inside a think, the order they were appended.
var commands: Array[Command] = []
## True from the tick that made the batch until the job that collects or drops it.
var pending: bool = false
## The microseconds the batch's views and thinks took, set by the job that ran them (0 until then).
var usec: int = 0
## The `usec` of the batch the last collect() took, 0 when it took none. The job stamps it into
## the snapshot of the tick that collects (ADR 0038 section 7).
var collected_usec: int = 0


## Drops a pending batch unsent: a restart's new World must not see the old match's Commands, and
## a match that has ended applies nothing more.
func clear() -> void:
	commands.clear()
	pending = false
	usec = 0
	collected_usec = 0


## Moves the pending batch's Commands to the end of `out` (after the human's) and empties the
## batch, or drops them when `ended` (a batch collected after the match's end is not stamped, not
## recorded and not counted). Returns how many Commands went to `out`. A tick with no batch
## collects nothing and reads `collected_usec` 0.
func collect(out: Array[Command], ended: bool) -> int:
	collected_usec = 0
	if not pending:
		return 0
	var moved: int = 0
	if not ended:
		out.append_array(commands)
		moved = commands.size()
		collected_usec = usec
	commands.clear()
	pending = false
	usec = 0
	return moved
