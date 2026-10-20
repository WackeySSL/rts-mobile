class_name MatchRunner
extends Node
## Runs one match: builds the World from a scenario and the match seed, and steps it at
## Sim.TICK_RATE through a MatchLoop, which stamps, records and checkpoints (ADR 0003 section 7,
## ADR 0007 sections 6 and 9). Frame delta lives only here; the sim never sees time. Each tick is a
## TickJob that fills a new MatchSnapshot, which the runner publishes as `snapshot` (ADR 0012
## sections 1 and 3, plan P38j); the view interpolates from its prev positions to its positions
## with alpha() (ADR 0011 section 2).
## It needs the CommandQueue and DetRng autoloads, so a headless `godot -s` tool must load() this
## script at runtime; naming MatchRunner in the entry script does not compile.

## Emitted after each publish with the snapshot's tick, the number of ticks played so far.
signal ticked(tick: int)

## What runs the ported phases (ADR 0013 section 3): the GDScript twins, the native kernels, or
## the kernels whenever the library is loaded. start() resolves it with resolve_impl().
enum SimImpl { GDSCRIPT = 0, NATIVE = 1, AUTO = 2 }
## What start() logs about the implementation it resolved (fallback_log()).
enum ImplLog { NONE = 0, WARNING = 1, ERROR = 2 }

## A tick is split into this many parts, so the frame clock is an integer and frame lengths
## that add up to whole ticks (four times 1/60 s) step exactly.
const MICRO_TICKS_PER_TICK: int = 1_000_000
## OS.get_name() of the platform that requires the library (ADR 0013 section 3) and of the web
## preview, which runs the GDScript twins (section 7).
const OS_ANDROID: String = "Android"
const OS_WEB: String = "Web"

@export var scenario: ScenarioDef
## The seed of the match, 0 to 2^31-1 (DetRandom masks it). start() makes the sim stream from it
## and records it in the replay.
@export var match_seed: int = 1
## Ticks one frame may play. Time beyond that is dropped, not carried to the next frame.
@export var max_catch_up_ticks: int = 4
## The implementation of the ported phases. GDSCRIPT by default, as tick modes default to SYNC: a
## runner a test builds runs the twins unless it asks otherwise. The scenes set AUTO from P50b.
@export var sim_impl: SimImpl = SimImpl.GDSCRIPT

var world: World
## The match's tick driver (ADR 0007 section 9) and its log, `loop.replay`. start() makes both.
var loop: MatchLoop
var replay: Replay
## Counts the start() calls, so a view layer sees a restart without comparing World identity.
var match_serial: int = 0
## The published fields, set from each published snapshot. The state hash of the last checkpoint,
## `loop.last_hash`: 0 until tick 15, then the hash of the last tick that 15 divides.
var last_hash: int = 0
## Microseconds the last tick spent in Sim.step, without the checkpoint hash that MatchLoop.step
## adds (ADR 0012 section 3), and in the whole tick job, which includes that hash and the capture.
var last_tick_usec: int = 0
var last_runner_tick_usec: int = 0
## A probe for the per-phase split, null unless a HUD sets one (P38t's TimingProbe). It gets every
## begin() and mark() of Sim.step; a probe changes no hash.
var probe: SimProbe
## The published snapshot: a new object from every tick and from start(), never written after its
## publish (ADR 0012 section 3). A frame without a tick keeps the same object.
var snapshot: MatchSnapshot
## Positions before the last tick, aligned to the rows: read-only forwards to the snapshot's, for
## Phase 1's UnitLayer until P40. Their identity changes with every tick.
var prev_pos_x: PackedInt32Array:
	get:
		return snapshot.prev_pos_x if snapshot != null else PackedInt32Array()
var prev_pos_y: PackedInt32Array:
	get:
		return snapshot.prev_pos_y if snapshot != null else PackedInt32Array()
## Stops _process from ticking, also between two ticks of one frame. run_ticks ignores it.
var paused: bool = false

var _micro_ticks: int = 0
var _app_paused: bool = false
## Reused every tick, so a tick allocates no command list. MatchLoop.step stamps the commands in
## place and never empties the list, so the job does, after every step: a command left in it would
## be stamped, recorded and applied again on the next tick.
var _commands: Array[Command] = []
## Times Sim.step and passes every call on to `probe`; handed to every loop.step through the job.
var _step_probe: StepProbe = StepProbe.new()
## Reused every tick. It holds no World, loop or snapshot between ticks, so the old snapshot is
## freed at publish and a restart frees the old match at once, before its first tick.
var _job: TickJob = TickJob.new()


func _ready() -> void:
	if scenario != null:
		start()


## Builds a new world from the scenario with the sim stream of `match_seed`, and a new MatchLoop:
## empty queue, clock at zero, sequences from 0 again, no checkpoint yet. It publishes the tick-0
## snapshot, without `ticked`: its match_serial and last_hash first, then a capture with no
## previous one, so prev = current and nothing slides from the old match. The World runs the
## implementation that sim_impl resolves to on this platform (_use_impl()).
func start() -> void:
	world = World.from_scenario(scenario, DetRng.create(match_seed, DetRandom.STREAM_SIM))
	_use_impl(world)
	var scenario_path: String = scenario.resource_path if scenario != null else ""
	loop = MatchLoop.create(scenario, scenario_path, match_seed, world)
	replay = loop.replay
	match_serial += 1
	var first: MatchSnapshot = MatchSnapshot.new()
	first.match_serial = match_serial
	first.last_hash = loop.last_hash
	first.capture(world, null)
	_publish(first)
	_micro_ticks = 0
	_commands.clear()
	CommandQueue.clear()


## Plays `n` ticks now. It ignores time and both pauses; tests and replays call it.
func run_ticks(n: int) -> void:
	if world == null:
		return
	for _i: int in n:
		_tick()


## How far the clock is into the next tick, 0 to 1.
func alpha() -> float:
	return clampf(float(_micro_ticks) / float(MICRO_TICKS_PER_TICK), 0.0, 1.0)


## The implementation that runs for `impl` (ADR 0013 section 3): NATIVE when NATIVE or AUTO is
## asked, the library is loaded (`has_library`: NativeKernels.create() gives kernels) and
## `os_name` (OS.get_name()) is not the web, whose preview runs the GDScript twins (section 7);
## GDSCRIPT otherwise, never AUTO. Pure, so tests pass any OS name; start() logs a fallback
## (fallback_log()).
static func resolve_impl(impl: int, has_library: bool, os_name: String) -> int:
	var asks_native: bool = impl == SimImpl.NATIVE or impl == SimImpl.AUTO
	if asks_native and has_library and os_name != OS_WEB:
		return SimImpl.NATIVE
	return SimImpl.GDSCRIPT


## What start() logs when `impl` resolved to `resolved` on `os_name` (ADR 0013 section 3): nothing
## when NATIVE runs or GDSCRIPT was asked; an error when NATIVE was asked, and when AUTO falls
## back on Android, where the library is required; nothing for AUTO on the web; a warning for AUTO
## on the other platforms. Pure: tests pass the OS name, so no test logs the Android error.
static func fallback_log(impl: int, resolved: int, os_name: String) -> int:
	if resolved == SimImpl.NATIVE or (impl != SimImpl.NATIVE and impl != SimImpl.AUTO):
		return ImplLog.NONE
	if impl == SimImpl.NATIVE or os_name == OS_ANDROID:
		return ImplLog.ERROR
	return ImplLog.NONE if os_name == OS_WEB else ImplLog.WARNING


func _process(delta: float) -> void:
	if world == null or paused or _app_paused:
		return
	_micro_ticks += roundi(maxf(delta, 0.0) * float(Sim.TICK_RATE * MICRO_TICKS_PER_TICK))
	var limit: int = maxi(max_catch_up_ticks, 1)
	var played: int = 0
	while _micro_ticks >= MICRO_TICKS_PER_TICK and played < limit and not paused:
		_micro_ticks -= MICRO_TICKS_PER_TICK
		_tick()
		played += 1
	# Whole ticks left over are the backlog. Keep only the part of a tick.
	_micro_ticks %= MICRO_TICKS_PER_TICK


## On a phone no frame runs between PAUSED and RESUMED. The background time reaches the first
## frame after RESUMED, which the engine caps at about 0.14 s, so it plays about two ticks.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_app_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_app_paused = false


## One tick, run inline (SYNC): drain the queue, create the next snapshot with this match's serial
## (set before the run, because capture() compares it with the published one's), hand the job the
## current world, loop and StepProbe, run it, take the world, loop and snapshots back, then publish
## and emit `ticked`.
func _tick() -> void:
	CommandQueue.drain_into(_commands)
	var next: MatchSnapshot = MatchSnapshot.new()
	next.match_serial = match_serial
	_step_probe.target = probe
	var job: TickJob = _job
	job.world = world
	job.loop = loop
	job.probe = _step_probe
	job.commands = _commands
	job.snapshot = next
	job.previous = snapshot
	job.post_usec = Time.get_ticks_usec()
	job.run()
	job.world = null
	job.loop = null
	job.snapshot = null
	job.previous = null
	_publish(next)
	ticked.emit(next.tick)


## Resolves sim_impl on this platform and logs a fallback; on NATIVE it attaches new kernels to
## `target` with the phases the library reports (ADR 0013 section 3). A GDSCRIPT World keeps no
## kernels and the mask 0. It runs before the first tick, so the choice holds for the whole match.
func _use_impl(target: World) -> void:
	var kernels: Object = null if sim_impl == SimImpl.GDSCRIPT else NativeKernels.create()
	var os_name: String = OS.get_name()
	var resolved: int = resolve_impl(sim_impl, kernels != null, os_name)
	var level: int = fallback_log(sim_impl, resolved, os_name)
	if level != ImplLog.NONE:
		var text: String = (
			"MatchRunner: sim_impl %s runs the GDScript twins on %s: no SimKernels library of ABI %d"
			% [SimImpl.keys()[sim_impl], os_name, NativeKernels.ABI_VERSION]
		)
		if level == ImplLog.ERROR:
			push_error(text)
		else:
			push_warning(text)
	if resolved == SimImpl.NATIVE:
		target.kernels = kernels
		target.native_phases = kernels.phases()


## Makes `published` the runner's snapshot and sets the published fields from it (ADR 0012
## section 1).
func _publish(published: MatchSnapshot) -> void:
	snapshot = published
	last_hash = published.last_hash
	last_tick_usec = published.step_usec
	last_runner_tick_usec = published.job_usec
