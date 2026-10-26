class_name MatchRunner
extends Node
## Runs one match: builds the World from a scenario and the match seed, and steps it at
## Sim.TICK_RATE through a MatchLoop, which stamps, records and checkpoints (ADR 0003 section 7,
## ADR 0007 sections 6 and 9). Frame delta lives only here; the sim never sees time. Each tick is a
## TickJob that fills a new MatchSnapshot, which the runner publishes as `snapshot` (ADR 0012
## sections 1 and 3, plan P38j); the view interpolates from its prev positions to its positions
## with alpha() (ADR 0011 section 2). In SYNC mode the job runs inline in the frame; in WORKER mode
## it runs on one worker thread, one tick ahead (plan P38w): at a boundary the runner publishes the
## finished job, emits `ticked`, then drains the queue and posts the next job. While a job runs,
## the World, `loop`, `replay` and `probe` belong to the worker and their getters refuse the main
## thread (plan P38w1b); it reads the World only inside `ticked` or after wait_idle(). Once a
## published snapshot shows the end of the match, the runner emits `match_ended` and plays no
## further tick until start() (ADR 0017 section 6, ADR 0018 section 7, plan P81).
## It needs the CommandQueue and DetRng autoloads, so a headless `godot -s` tool must load() this
## script at runtime; naming MatchRunner in the entry script does not compile.

## Emitted after each publish with the snapshot's tick, the number of ticks played so far.
signal ticked(tick: int)
## Emitted once per match, after the `ticked` of the first published snapshot that shows
## `match_end_tick` (ADR 0018 section 7), with its `winner`: the player, or 0 for a draw. From then
## on no tick runs: frames and run_ticks() do nothing, and in WORKER mode no job is posted, until
## start() begins a new match. A `ticked` handler that restarted the match gets none for the old.
signal match_ended(winner: int)

## Where the tick runs (ADR 0012 section 1): inline in the frame, on a worker thread one tick
## ahead, or AUTO, which start() resolves with resolve_mode().
enum TickMode { SYNC = 0, WORKER = 1, AUTO = 2 }
## The hand-off (ADR 0012 section 1): no job posted, or the last one published or discarded; a job
## posted whose `done` token is not taken; the token taken and the job not published yet.
enum HandOff { IDLE = 0, RUNNING = 1, FINISHED = 2 }
## What happens to the hand-off: a frame (FRAME_TAKEN when its one try_wait() in RUNNING took the
## token), a tick boundary of the clock, wait_idle(), start(), run_ticks() and the join (STOP).
enum HandOffEvent {
	FRAME = 0,
	FRAME_TAKEN = 1,
	BOUNDARY = 2,
	WAIT_IDLE = 3,
	START = 4,
	RUN_TICKS = 5,
	STOP = 6,
}
## The steps of a hand_off() cell, a bit set run in this order: the timed wait for the token; the
## finished job dropped, or published with `ticked`; the queue drained and the next job posted (from
## IDLE that is the refill, which sets the clock to 0); the boundary held. What the event itself
## does (start()'s tick-0 snapshot, run_ticks()'s inline ticks, the join) is not a step.
enum HandOffStep { NONE = 0, WAIT = 1, DISCARD = 2, PUBLISH = 4, POST = 8, HOLD = 16 }
## What runs the ported phases (ADR 0013 section 3): the GDScript twins, the native kernels, or
## the kernels whenever the library is loaded. start() resolves it with resolve_impl().
enum SimImpl { GDSCRIPT = 0, NATIVE = 1, AUTO = 2 }
## What start() logs about the implementation it resolved (fallback_log()).
enum ImplLog { NONE = 0, WARNING = 1, ERROR = 2 }

## A tick is split into this many parts, so the frame clock is an integer and frame lengths
## that add up to whole ticks (four times 1/60 s) step exactly.
const MICRO_TICKS_PER_TICK: int = 1_000_000
## OS.get_name() of the platform that requires the library (ADR 0013 section 3) and of the web
## preview, which packs no library (section 7) and falls back silently.
const OS_ANDROID: String = "Android"
const OS_WEB: String = "Web"
## Every wait for a job gives up after this long, with an error (ADR 0012 section 1).
const WAIT_CAP_MSEC: int = 5000
## The tick period in microseconds, 66 666 (ADR 0012 section 1): a job whose post-to-done time is
## above it is late. Derived from the tick rate, never a literal.
@warning_ignore("integer_division") const TICK_USEC: int = 1_000_000 / Sim.TICK_RATE
## hand_off()'s table (ADR 0012 section 1): per HandOffEvent, the next state and the steps from
## IDLE, RUNNING and FINISHED in turn. A cell the runner never reaches (FRAME_TAKEN without a poll,
## a boundary in IDLE, which the refill comes before) keeps the state and does nothing.
const HAND_OFF_TABLE: Array[Array] = [
	# FRAME: the refill from IDLE; nothing while the job runs or waits for its boundary.
	[
		Vector2i(HandOff.RUNNING, HandOffStep.POST),
		Vector2i(HandOff.RUNNING, HandOffStep.NONE),
		Vector2i(HandOff.FINISHED, HandOffStep.NONE),
	],
	# FRAME_TAKEN: reached only from RUNNING.
	[
		Vector2i(HandOff.IDLE, HandOffStep.NONE),
		Vector2i(HandOff.FINISHED, HandOffStep.NONE),
		Vector2i(HandOff.FINISHED, HandOffStep.NONE),
	],
	# BOUNDARY: a running job holds it; a finished one is published and the next one posted.
	[
		Vector2i(HandOff.IDLE, HandOffStep.NONE),
		Vector2i(HandOff.RUNNING, HandOffStep.HOLD),
		Vector2i(HandOff.RUNNING, HandOffStep.PUBLISH | HandOffStep.POST),
	],
	# WAIT_IDLE: true at once, or after the timed wait.
	[
		Vector2i(HandOff.IDLE, HandOffStep.NONE),
		Vector2i(HandOff.FINISHED, HandOffStep.WAIT),
		Vector2i(HandOff.FINISHED, HandOffStep.NONE),
	],
	# START: a job in flight is dropped (start() then publishes the tick-0 snapshot).
	[
		Vector2i(HandOff.IDLE, HandOffStep.NONE),
		Vector2i(HandOff.IDLE, HandOffStep.WAIT | HandOffStep.DISCARD),
		Vector2i(HandOff.IDLE, HandOffStep.DISCARD),
	],
	# RUN_TICKS: a job in flight is the first of the n ticks (the rest run inline).
	[
		Vector2i(HandOff.IDLE, HandOffStep.NONE),
		Vector2i(HandOff.IDLE, HandOffStep.WAIT | HandOffStep.PUBLISH),
		Vector2i(HandOff.IDLE, HandOffStep.PUBLISH),
	],
	# STOP: a job in flight is dropped before the join.
	[
		Vector2i(HandOff.IDLE, HandOffStep.NONE),
		Vector2i(HandOff.IDLE, HandOffStep.WAIT | HandOffStep.DISCARD),
		Vector2i(HandOff.IDLE, HandOffStep.DISCARD),
	],
]

## Started worker threads not joined yet, over every runner (live_workers()). Main thread only.
static var _live_workers: int = 0

@export var scenario: ScenarioDef
## The seed of the match, 0 to 2^31-1 (DetRandom masks it). start() makes the sim stream from it
## and records it in the replay.
@export var match_seed: int = 1
## Ticks one frame may play. Time beyond that is dropped, not carried to the next frame.
@export var max_catch_up_ticks: int = 4
## The implementation of the ported phases. GDSCRIPT by default, as tick modes default to SYNC: a
## runner a test builds runs the twins unless it asks otherwise. The scenes set AUTO from P50b.
@export var sim_impl: SimImpl = SimImpl.GDSCRIPT
## Where the tick runs. SYNC by default: a runner a test builds ticks inline unless it asks for
## WORKER. The scenes set AUTO from P50b.
@export var tick_mode: TickMode = TickMode.SYNC

## The World, `loop`, `replay` and `probe` belong to the worker while a job runs (ADR 0012
## section 1): read or swap them in SYNC mode, inside `ticked` or after wait_idle(). Each is a
## property over a private field, guarded by shared_access_allowed(): in WORKER mode while a job is
## RUNNING, its getter logs an error and returns null, and its setter logs an error and changes
## nothing. A setter is needed because Godot ignores an assignment to a getter-only property
## without a word. Tests swap in a World with it; the job gets the swap at the next run or post.
var world: World:
	get:
		return _world if _shared(&"world") else null
	set(value):
		if _shared(&"world"):
			_world = value
## The match's tick driver (ADR 0007 section 9) and its log, `loop.replay`. start() makes both.
var loop: MatchLoop:
	get:
		return _loop if _shared(&"loop") else null
	set(value):
		if _shared(&"loop"):
			_loop = value
var replay: Replay:
	get:
		return _replay if _shared(&"replay") else null
	set(value):
		if _shared(&"replay"):
			_replay = value
## Counts the start() calls, so a view layer sees a restart without comparing World identity.
var match_serial: int = 0
## The published fields, set from each published snapshot. The state hash of the last checkpoint,
## `loop.last_hash`: 0 until tick 15, then the hash of the last tick that 15 divides.
var last_hash: int = 0
## Microseconds the last tick spent in Sim.step, without the checkpoint hash that MatchLoop.step
## adds (ADR 0012 section 3), and in the whole tick job, which includes that hash and the capture.
var last_tick_usec: int = 0
var last_runner_tick_usec: int = 0
## The diagnostics of ADR 0012 section 1, reset by start(). held_ticks: boundaries the WORKER clock
## reached while their job still ran, one per held job. late_ticks: published jobs whose
## post-to-done time (end_usec - post_usec) was above TICK_USEC, a slow job rather than a held
## boundary, and latency_usec_max: the largest post-to-done time. An inline tick (SYNC mode,
## run_ticks()) counts too: its post is the start of its run.
var held_ticks: int = 0
var late_ticks: int = 0
var latency_usec_max: int = 0
## A probe for the per-phase split, null unless a HUD sets one (P38t's TimingProbe). It gets every
## begin() and mark() of Sim.step; a probe changes no hash. Guarded like `world`; setting it calls
## set_probe().
var probe: SimProbe:
	get:
		return _probe if _shared(&"probe") else null
	set(value):
		set_probe(value)
## The published snapshot: a new object from every tick and from start(), never written after its
## publish (ADR 0012 section 3). A frame without a tick keeps the same object.
var snapshot: MatchSnapshot
## Positions before the last tick, aligned to the rows: read-only forwards to the published
## snapshot's arrays, so they are safe in WORKER mode too. No view reads them since P40 (tests do).
## Their identity changes with every tick.
var prev_pos_x: PackedInt32Array:
	get:
		return snapshot.prev_pos_x if snapshot != null else PackedInt32Array()
var prev_pos_y: PackedInt32Array:
	get:
		return snapshot.prev_pos_y if snapshot != null else PackedInt32Array()
## Stops _process from ticking, also between two ticks of one frame. run_ticks ignores it. In
## WORKER mode the job in flight finishes, and the clock restarts at 0 in the first frame after it.
var paused: bool = false

var _micro_ticks: int = 0
var _app_paused: bool = false
## Set by a frame that a pause skipped, and by an application pause: the next WORKER frame restarts
## the clock at 0.
var _resumed: bool = false
## True from a held boundary until the frame that publishes the held job.
var _held: bool = false
## Reused every tick, so a tick allocates no command list. MatchLoop.step stamps the commands in
## place and never empties the list, so the job does, after every step: a command left in it would
## be stamped, recorded and applied again on the next tick.
var _commands: Array[Command] = []
## Times Sim.step and passes every call on to `probe`; handed to every loop.step through the job.
var _step_probe: StepProbe = StepProbe.new()
## Reused every tick. It holds no World, loop or snapshot between ticks, so the old snapshot is
## freed at publish and a restart frees the old match at once, before its first tick.
var _job: TickJob = TickJob.new()
## The mode start() resolved; SYNC for good once Thread.start() failed (mode_after_start()).
var _mode: int = TickMode.SYNC
var _start_failed: bool = false
var _state: int = HandOff.IDLE
## The worker, made for the first job posted; null until then and after the join.
var _thread: Thread
## The fields behind `world`, `loop`, `replay` and `probe`. The runner itself uses only these.
var _world: World
var _loop: MatchLoop
var _replay: Replay
var _probe: SimProbe


func _ready() -> void:
	if scenario != null:
		start()


## Builds a new world from the scenario with the sim stream of `match_seed`, and a new MatchLoop:
## empty queue, clock at zero, held_ticks, late_ticks and latency_usec_max at zero, sequences from
## 0 again, no checkpoint yet. It publishes the tick-0 snapshot, without `ticked`: its match_serial
## and last_hash first, then a capture with no previous one, so prev = current and nothing slides
## from the old match. The World runs the implementation that sim_impl resolves to on this platform
## (_use_impl()), and the ticks run in the mode tick_mode resolves to (resolve_mode()). A job in
## flight is waited for and dropped first; if that wait reaches its cap, start() logs it and
## returns with the old match.
func start() -> void:
	var step: Vector2i = hand_off(_state, HandOffEvent.START)
	if step.y & HandOffStep.WAIT and not _take_done(WAIT_CAP_MSEC):
		return
	_release_job()
	_state = step.x
	var headless: bool = DisplayServer.get_name() == "headless"
	var threads: bool = OS.has_feature("threads")
	_mode = resolve_mode(tick_mode, threads, OS.has_feature("web"), headless)
	if _start_failed:
		_mode = TickMode.SYNC
	_world = World.from_scenario(scenario, DetRng.create(match_seed, DetRandom.STREAM_SIM))
	var kernels: Object = null if sim_impl == SimImpl.GDSCRIPT else NativeKernels.create()
	_use_impl(_world, kernels, OS.get_name())
	var scenario_path: String = scenario.resource_path if scenario != null else ""
	_loop = MatchLoop.create(scenario, scenario_path, match_seed, _world)
	_replay = _loop.replay
	match_serial += 1
	var first: MatchSnapshot = MatchSnapshot.new()
	first.match_serial = match_serial
	first.last_hash = _loop.last_hash
	first.capture(_world, null)
	_publish(first)
	_micro_ticks = 0
	held_ticks = 0
	late_ticks = 0
	latency_usec_max = 0
	_commands.clear()
	CommandQueue.clear()


## Plays `n` ticks now. It ignores time and both pauses; tests and replays call it. In WORKER mode
## a job in flight is waited for and published as the first of the `n` ticks, and the rest run
## inline, so the published tick advances by exactly `n` (ADR 0012 section 1). The next frame
## refills. It stops after the tick that publishes the end of the match, and does nothing after it.
func run_ticks(n: int) -> void:
	if _world == null or n <= 0 or _ended():
		return
	var step: Vector2i = hand_off(_state, HandOffEvent.RUN_TICKS)
	if step.y & HandOffStep.WAIT and not _take_done(WAIT_CAP_MSEC):
		return
	var inline: int = n
	if step.y & HandOffStep.PUBLISH:
		_publish_job()
		inline -= 1
	_state = step.x
	for _i: int in inline:
		if _ended():
			return
		_tick()


## Waits until no job runs (ADR 0012 section 1): true at once when none is in flight, else after
## taking the job's `done` token, or false with an error after `timeout_msec`. The finished job
## stays unpublished until the next boundary or run_ticks().
func wait_idle(timeout_msec: int = WAIT_CAP_MSEC) -> bool:
	var step: Vector2i = hand_off(_state, HandOffEvent.WAIT_IDLE)
	if step.y & HandOffStep.WAIT and not _take_done(timeout_msec):
		return false
	_state = step.x
	return true


## True while a posted job's `done` token is not taken (RUNNING).
func job_in_flight() -> bool:
	return _state == HandOff.RUNNING


## True while a started worker thread has not been joined.
func worker_active() -> bool:
	return _thread != null and _thread.is_started()


## Installs `new_probe` (null removes it) for the next job (ADR 0012 section 1). It waits idle
## first, so the job in flight keeps the probe it was handed; if that wait reaches its cap, it logs
## the error and installs nothing. The `probe` setter calls it.
func set_probe(new_probe: SimProbe) -> void:
	if wait_idle():
		_probe = new_probe


## How far the clock is into the next tick, 0 to 1.
func alpha() -> float:
	return clampf(float(_micro_ticks) / float(MICRO_TICKS_PER_TICK), 0.0, 1.0)


## The implementation that runs for `impl` (ADR 0013 section 3): NATIVE when NATIVE or AUTO is
## asked and the library is loaded (`has_library`: NativeKernels.create() gives kernels), on every
## OS, since AUTO means NATIVE whenever the class exists; GDSCRIPT otherwise, never AUTO. The web
## runs the twins because its export packs no library (section 7), not by a rule here, so the OS
## name (OS.get_name(), part of the contract) does not change the result. Pure; start() logs a
## fallback (fallback_log()).
static func resolve_impl(impl: int, has_library: bool, _os_name: String) -> int:
	var asks_native: bool = impl == SimImpl.NATIVE or impl == SimImpl.AUTO
	return SimImpl.NATIVE if asks_native and has_library else SimImpl.GDSCRIPT


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


## The mode `mode` (a TickMode) runs in (ADR 0012 section 1): AUTO is WORKER only where threads
## exist, outside the web and outside a headless run, so the scene tests stay synchronous; SYNC and
## WORKER stay as asked. Pure: start() passes OS.has_feature() and the DisplayServer's name.
static func resolve_mode(mode: int, threads: bool, web: bool, headless: bool) -> int:
	if mode == TickMode.AUTO:
		return TickMode.WORKER if threads and not web and not headless else TickMode.SYNC
	return TickMode.WORKER if mode == TickMode.WORKER else TickMode.SYNC


## The mode after Thread.start() returned `start_error` in `mode` (ADR 0012 section 1): a worker
## that failed to start makes the runner SYNC for good.
static func mode_after_start(mode: int, start_error: int) -> int:
	return TickMode.SYNC if mode == TickMode.WORKER and start_error != OK else mode


## Whether the main thread may touch the World, `loop`, `replay` and `probe` in `mode` (the resolved
## TickMode) and `state` (a HandOff state): never in WORKER mode while a job is RUNNING, because the
## worker owns them then (ADR 0012 section 1); always otherwise. Pure: the getters and setters ask
## it with the runner's mode and state, and tests read it without the getters' error.
static func shared_access_allowed(mode: int, state: int) -> bool:
	return mode != TickMode.WORKER or state != HandOff.RUNNING


## Started worker threads not joined yet, over every runner (ADR 0012 section 1, stop): a static
## counter, main thread only. A test compares it before and after it frees a runner, so it proves
## the join without calling the freed object.
static func live_workers() -> int:
	return _live_workers


## The next state and the steps (a HandOffStep bit set) for `event` in `state`: the table of ADR
## 0012 section 1. Pure: what a frame's try_wait() returned is part of the event (FRAME_TAKEN).
static func hand_off(state: int, event: int) -> Vector2i:
	if event < 0 or event >= HAND_OFF_TABLE.size() or state < 0 or state > HandOff.FINISHED:
		return Vector2i(state, HandOffStep.NONE)
	return HAND_OFF_TABLE[event][state]


func _process(delta: float) -> void:
	if _world == null or paused or _app_paused:
		_resumed = true
		return
	if _ended():
		return
	if _mode == TickMode.WORKER:
		_process_worker(delta)
		return
	_micro_ticks += roundi(maxf(delta, 0.0) * float(Sim.TICK_RATE * MICRO_TICKS_PER_TICK))
	var limit: int = maxi(max_catch_up_ticks, 1)
	var played: int = 0
	while _micro_ticks >= MICRO_TICKS_PER_TICK and played < limit and not paused and not _ended():
		_micro_ticks -= MICRO_TICKS_PER_TICK
		_tick()
		played += 1
	# Whole ticks left over are the backlog. Keep only the part of a tick.
	_micro_ticks %= MICRO_TICKS_PER_TICK


## On a phone no frame runs between PAUSED and RESUMED. The background time reaches the first
## frame after RESUMED, which the engine caps at about 0.14 s, so in SYNC mode it plays about two
## ticks; in WORKER mode that frame restarts the clock at 0 instead (ADR 0012 section 1).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_app_paused = true
		_resumed = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_app_paused = false
	elif what == NOTIFICATION_PREDELETE:
		_join_worker()


## Ends the worker. Its job in flight is dropped although the World has played that tick, so a
## WORKER runner must not leave the tree during a match: its published ticks would skip one. Back
## in the tree, start() a new match; its first job starts a new worker.
func _exit_tree() -> void:
	_join_worker()


## One WORKER frame (ADR 0012 section 1): one try_wait() while a job runs, then the clock. Three
## kinds of frame set the clock to 0 and do not advance it: the refill from IDLE (drain and post);
## the first frame that finds a held job finished, which publishes it and posts the next one; and
## the first frame after a pause. Any other frame advances the clock, and at a boundary it publishes
## the finished job and posts the next one, dropping the whole ticks still owed and keeping the part
## of a tick (at most one publish per frame, as SYNC drops its backlog), or holds while the job
## runs: nothing published, no job started, the clock stopped at the boundary, so alpha() is 1.0
## until the hold ends, and held_ticks counts the held job once.
func _process_worker(delta: float) -> void:
	var event: int = HandOffEvent.FRAME
	if _state == HandOff.RUNNING and _job.done.try_wait():
		event = HandOffEvent.FRAME_TAKEN
	var step: Vector2i = hand_off(_state, event)
	_state = step.x
	var resumed: bool = _resumed
	_resumed = false
	if step.y & HandOffStep.POST:
		_held = false
		_micro_ticks = 0
		_post_next()
		return
	if _held:
		if hand_off(_state, HandOffEvent.BOUNDARY).y & HandOffStep.HOLD:
			return
		_held = false
		_micro_ticks = 0
		_publish_and_post()
		return
	if resumed:
		_micro_ticks = 0
		return
	_micro_ticks += roundi(maxf(delta, 0.0) * float(Sim.TICK_RATE * MICRO_TICKS_PER_TICK))
	if _micro_ticks < MICRO_TICKS_PER_TICK:
		return
	if hand_off(_state, HandOffEvent.BOUNDARY).y & HandOffStep.HOLD:
		_micro_ticks = MICRO_TICKS_PER_TICK
		_held = true
		held_ticks += 1
		return
	_micro_ticks %= MICRO_TICKS_PER_TICK
	_publish_and_post()


## A boundary with the job finished (ADR 0012 section 1): publishes it with `ticked`, then drains
## and posts the next job. A `ticked` handler that restarted the match in SYNC mode gets no job
## posted, so no job runs beside its inline ticks, and a published end gets none either.
func _publish_and_post() -> void:
	_publish_job()
	if _mode == TickMode.WORKER and not _ended():
		_post_next()


## Steps 2 and 3 of a boundary, and the refill (ADR 0012 section 1): drains the queue and posts the
## next job to the worker, which starts with the first job. If Thread.start() fails, the runner is
## SYNC for good (mode_after_start()) and runs this job inline.
func _post_next() -> void:
	if _thread == null:
		var thread: Thread = Thread.new()
		_job.work = Semaphore.new()
		_job.done = Semaphore.new()
		_job.quit = false
		var error: int = thread.start(_job.serve)
		_mode = mode_after_start(_mode, error)
		if _mode != TickMode.WORKER:
			_start_failed = true
			push_warning("MatchRunner: no worker thread (error %d); the ticks run inline" % error)
			_tick()
			return
		_thread = thread
		_live_workers += 1
	CommandQueue.drain_into(_commands)
	_hand_over()
	_state = HandOff.RUNNING
	_job.post_usec = Time.get_ticks_usec()
	_job.work.post()


## Takes the job's `done` token in a try_wait() loop with 1 ms steps (ADR 0012 section 1). At the
## cap it logs an error and returns false, so a slip fails a test instead of hanging CI.
func _take_done(timeout_msec: int) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not _job.done.try_wait():
		if Time.get_ticks_msec() >= until:
			push_error("MatchRunner: the tick job did not finish within %d ms" % timeout_msec)
			return false
		OS.delay_msec(1)
	return true


## Ends the worker (ADR 0012 section 1, stop): waits for a job in flight, then sets `quit`, wakes
## the worker, joins it and drops the job. Only for a started thread, because wait_to_finish() on
## an unstarted Thread logs an error; idempotent. _exit_tree() and NOTIFICATION_PREDELETE call it,
## so a runner never added to the tree is joined when it is freed. After a wait that reached its
## cap, the join still waits for the job, so the job's objects are never taken from under it.
func _join_worker() -> void:
	if _thread == null or not _thread.is_started():
		return
	var step: Vector2i = hand_off(_state, HandOffEvent.STOP)
	if step.y & HandOffStep.WAIT:
		_take_done(WAIT_CAP_MSEC)
	_job.quit = true
	_job.work.post()
	_thread.wait_to_finish()
	_thread = null
	_live_workers -= 1
	_release_job()
	_state = step.x


## One tick, run inline (SYNC, and run_ticks()): drain the queue, hand the job over, run it, then
## publish and emit `ticked`.
func _tick() -> void:
	CommandQueue.drain_into(_commands)
	_hand_over()
	_job.post_usec = Time.get_ticks_usec()
	_job.run()
	_publish_job()


## Hands the job the next snapshot, created with this match's serial (set before the run, because
## capture() compares it with the published one's), the published snapshot as `previous`, and the
## current world, loop and StepProbe, whose target is the current probe: read from the private
## fields at every run or post, so a setter's swap takes effect on the next tick.
func _hand_over() -> void:
	var next: MatchSnapshot = MatchSnapshot.new()
	next.match_serial = match_serial
	_step_probe.target = _probe
	_job.world = _world
	_job.loop = _loop
	_job.probe = _step_probe
	_job.commands = _commands
	_job.snapshot = next
	_job.previous = snapshot


## Step 1 of a boundary (ADR 0012 section 1): takes the finished job's snapshot and the World, loop
## and snapshots back from the job, counts its post-to-done time into late_ticks and
## latency_usec_max, publishes the snapshot and emits `ticked`, then `match_ended` when the
## snapshot shows the end and is still the published one. No job is in flight inside a `ticked`
## handler, so the World there equals the published snapshot.
func _publish_job() -> void:
	var next: MatchSnapshot = _job.snapshot
	_release_job()
	_state = HandOff.IDLE
	var latency: int = next.end_usec - next.post_usec
	latency_usec_max = maxi(latency_usec_max, latency)
	if latency > TICK_USEC:
		late_ticks += 1
	_publish(next)
	ticked.emit(next.tick)
	if next.match_end_tick > 0 and snapshot == next:
		match_ended.emit(next.winner)


## Takes the World, loop and snapshots back from the job (a published or a dropped one), so the old
## snapshot is freed at publish and a restart frees the old match at once.
func _release_job() -> void:
	_job.world = null
	_job.loop = null
	_job.snapshot = null
	_job.previous = null


## Resolves sim_impl for `kernels` (NativeKernels.create(), or null) on `os_name` (OS.get_name())
## and logs a fallback; on NATIVE it attaches `kernels` to `target` with the phases they report
## (ADR 0013 section 3). A GDSCRIPT World keeps no kernels and the mask 0. start() calls it before
## the first tick, so the choice holds for the whole match; tests pass both arguments.
func _use_impl(target: World, kernels: Object, os_name: String) -> void:
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


## The guard of `world`, `loop`, `replay` and `probe` (ADR 0012 section 1): true when
## shared_access_allowed() gives the main thread the runner's mode and state; else an error that
## names `what`, and false, so the getter returns null and the setter changes nothing.
func _shared(what: StringName) -> bool:
	if shared_access_allowed(_mode, _state):
		return true
	push_error("MatchRunner: %s used while a job runs on the worker (ADR 0012 section 1)" % what)
	return false


## Whether the published snapshot shows the end of the match: then no tick runs until start().
func _ended() -> bool:
	return snapshot != null and snapshot.match_end_tick > 0


## Makes `published` the runner's snapshot and sets the published fields from it (ADR 0012
## section 1).
func _publish(published: MatchSnapshot) -> void:
	snapshot = published
	last_hash = published.last_hash
	last_tick_usec = published.step_usec
	last_runner_tick_usec = published.job_usec
