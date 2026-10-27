class_name TickJob
extends RefCounted
## One tick of a match (ADR 0012 sections 1 to 3, plan P38j): MatchLoop.step on the World, the
## capture into the new MatchSnapshot, then the timings. MatchRunner runs it inline in SYNC mode,
## and on its worker thread through serve() in WORKER mode (plan P38w). The runner hands it its
## current world, loop and StepProbe before every run or post, so a swap takes effect on the next
## tick.
##
## Before the step it lets the match's computer players think (AiDriver.think_all, ADR 0020
## section 3), so their Commands follow the human's in the list and are stamped and recorded alike.
##
## It touches only those objects, the controllers and the PlayerViews they get, the command list and
## the two snapshots, and none of them is a Node or a Resource (tests/core/test_tick_job.gd walks
## them). It reads the clock and nothing else of the engine: no tree, no autoload, no signal, no
## deferred call.

var world: World
var loop: MatchLoop
## The runner's StepProbe, whose target is the runner's probe (a HUD's TimingProbe, or null).
## run() reads step_usec only from a StepProbe and phase_usec only from its TimingProbe target, so
## a direct driver (a perf test) passes a StepProbe whose target is the TimingProbe.
var probe: SimProbe
## This tick's commands in submission order. MatchLoop stamps them in place and only reads the
## list, so run() empties it after the step: a command passed again would be applied again.
var commands: Array[Command] = []
## The match's computer players (ADR 0020 sections 2 and 3), set by the runner at start(): run()
## hands them to AiDriver.think_all before the step. A controller keeps only ints, arrays and its
## DetRandom stream, so the walk stays free of Nodes and Resources.
var controllers: Array[AiController] = []
## The new snapshot this job fills. The runner sets its match_serial before the run, because
## capture() compares it with the one of `previous`, the published snapshot (or null).
var snapshot: MatchSnapshot
var previous: MatchSnapshot
## Time.get_ticks_usec() when the runner handed the job over, and when run() ended.
var post_usec: int = 0
var end_usec: int = 0
## The worker's hand-off (ADR 0012 section 1), set by the runner before it starts the thread: one
## `work` token per job posted, one `done` token per job run, and `quit`, read after a `work`
## token, ends serve(). The two semaphores are the only synchronisation between the threads.
var work: Semaphore
var done: Semaphore
var quit: bool = false


## The worker thread's loop: wait for `work`, return once `quit` is set, run one job, post `done`.
## The fields run() reads are set before each `work` post and read back after the `done` token.
func serve() -> void:
	while true:
		work.wait()
		if quit:
			return
		run()
		done.post()


## One tick: the controllers' thinks (their Commands appended after the ones the list holds), the
## step, the hash of the last checkpoint, the capture, then the timings: Sim.step from the
## StepProbe, the TimingProbe's phases (a copy; empty without one) and the whole job, with the
## thinks.
func run() -> void:
	var started: int = Time.get_ticks_usec()
	AiDriver.think_all(world, controllers, commands)
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
