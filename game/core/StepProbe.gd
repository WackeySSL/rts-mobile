class_name StepProbe
extends SimProbe
## The probe MatchRunner hands MatchLoop.step on every tick. It times Sim.step alone (ADR 0012
## section 3): from begin() to the last mark(), which leaves out the checkpoint hash that
## MatchLoop.step adds after Sim.step on every 15th tick. It passes every begin() and mark() on to
## `target`, the runner's `probe` (P38t's TimingProbe sits there, beside this one), when that is
## not null. It reads the clock and never touches the World, so hashes are equal with and without
## it. The runner makes it; this file never names its own class (the P56c rule for a class with a
## script base).

## The probe that gets every call as well, or null. The runner sets it before every step.
var target: SimProbe
## Microseconds from the last begin() to the last mark() after it, 0 until that tick's first mark.
var step_usec: int = 0

var _begin_usec: int = 0


## The start of Sim.step. The target begins first, so its time stays out of this one.
func begin() -> void:
	if target != null:
		target.begin()
	step_usec = 0
	_begin_usec = Time.get_ticks_usec()


## The end of `phase`. The clock is read before the target's mark, so after the last phase none of
## the target's time is in `step_usec`.
func mark(phase: int) -> void:
	step_usec = Time.get_ticks_usec() - _begin_usec
	if target != null:
		target.mark(phase)
