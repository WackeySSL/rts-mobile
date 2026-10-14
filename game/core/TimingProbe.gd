class_name TimingProbe
extends SimProbe
## The per-phase split of one tick (ADR 0007 section 4, ADR 0012 section 4): microseconds per
## SimProbe phase for the last tick. A HUD sets it as the runner's `probe`, and the runner's
## StepProbe passes every begin() and mark() of Sim.step on to it. begin() zeroes every phase and
## reads the clock; mark(phase) stores the time since the previous mark, or since begin() for the
## first, under that phase, so a phase that is not marked reads 0. It reads the clock and never
## the World, so hashes are equal with and without it. It takes no reference samples (ADR 0014
## section 3: the worker stays raw). Callers make it; this file never names its own class (the
## P56c rule for a class with a script base).

## Microseconds per phase id for the last tick, SimProbe.Phase.COUNT entries.
var phase_usec: PackedInt64Array = PackedInt64Array()

var _last_usec: int = 0


func _init() -> void:
	phase_usec.resize(SimProbe.Phase.COUNT)


## The start of a tick: every phase back to 0, and the clock the first mark counts from.
func begin() -> void:
	phase_usec.fill(0)
	_last_usec = Time.get_ticks_usec()


## The end of `phase`, a Phase id: the time since the previous mark, or since begin().
func mark(phase: int) -> void:
	var now: int = Time.get_ticks_usec()
	phase_usec[phase] = now - _last_usec
	_last_usec = now
