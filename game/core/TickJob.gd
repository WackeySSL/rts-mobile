class_name TickJob
extends RefCounted
## One tick of a match (ADR 0012 sections 1 to 3, plan P38j): MatchLoop.step on the World, the
## capture into the new MatchSnapshot, then the timings. MatchRunner runs it inline in SYNC mode,
## the only mode until P38w runs it on a worker thread. The runner hands it its current world, loop
## and StepProbe before every run, so a swap takes effect on the next tick.
##
## It touches only those objects, the command list and the two snapshots, and none of them is a
## Node or a Resource (tests/core/test_tick_job.gd walks them). It reads the clock and nothing else
## of the engine: no tree, no autoload, no signal, no deferred call.

var world: World
var loop: MatchLoop
## The runner's StepProbe, whose target is the runner's probe (a HUD's TimingProbe, or null).
## run() reads step_usec only from a StepProbe and phase_usec only from its TimingProbe target, so
## a direct driver (a perf test) passes a StepProbe whose target is the TimingProbe.
var probe: SimProbe
## This tick's commands in submission order. MatchLoop stamps them in place and only reads the
## list, so run() empties it after the step: a command passed again would be applied again.
var commands: Array[Command] = []
## The new snapshot this job fills. The runner sets its match_serial before the run, because
## capture() compares it with the one of `previous`, the published snapshot (or null).
var snapshot: MatchSnapshot
var previous: MatchSnapshot
## Time.get_ticks_usec() when the runner handed the job over, and when run() ended.
var post_usec: int = 0
var end_usec: int = 0


## One tick: the step, the hash of the last checkpoint, the capture, then the timings: Sim.step from
## the StepProbe, the TimingProbe's phases (a copy; empty without one) and the whole job.
func run() -> void:
	var started: int = Time.get_ticks_usec()
	loop.step(world, commands, probe)
	commands.clear()
	var out: MatchSnapshot = snapshot
	out.last_hash = loop.last_hash
	out.capture(world, previous)
	var step_probe: StepProbe = probe as StepProbe
	if step_probe != null:
		out.step_usec = step_probe.step_usec
		var timing: TimingProbe = step_probe.target as TimingProbe
		if timing != null:
			out.phase_usec = timing.phase_usec.duplicate()
	out.post_usec = post_usec
	end_usec = Time.get_ticks_usec()
	out.end_usec = end_usec
	out.job_usec = end_usec - started
