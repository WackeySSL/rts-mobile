class_name MatchRunner
extends Node
## Runs one match: builds the World from a scenario and the match seed, and steps it at
## Sim.TICK_RATE through a MatchLoop, which stamps, records and checkpoints (ADR 0003 section 7,
## ADR 0007 sections 6 and 9). Frame delta lives only here; the sim never sees time. The view
## interpolates between prev_pos_* and world.pos_* with alpha() (ADR 0011 section 2).
## It needs the CommandQueue and DetRng autoloads, so a headless `godot -s` tool must load() this
## script at runtime; naming MatchRunner in the entry script does not compile.

## Emitted after each tick with world.tick, the number of ticks played so far.
signal ticked(tick: int)

## A tick is split into this many parts, so the frame clock is an integer and frame lengths
## that add up to whole ticks (four times 1/60 s) step exactly.
const MICRO_TICKS_PER_TICK: int = 1_000_000

@export var scenario: ScenarioDef
## The seed of the match, 0 to 2^31-1 (DetRandom masks it). start() makes the sim stream from it
## and records it in the replay.
@export var match_seed: int = 1
## Ticks one frame may play. Time beyond that is dropped, not carried to the next frame.
@export var max_catch_up_ticks: int = 4

var world: World
## The match's tick driver (ADR 0007 section 9) and its log, `loop.replay`. start() makes both.
var loop: MatchLoop
var replay: Replay
## Counts the start() calls, so a view layer sees a restart without comparing World identity.
var match_serial: int = 0
## The state hash of the last checkpoint, `loop.last_hash`: 0 until tick 15, then the hash of the
## last tick that 15 divides.
var last_hash: int = 0
## Microseconds the last tick spent in Sim.step, without the checkpoint hash that MatchLoop.step
## adds (ADR 0012 section 3), and in the whole runner tick, which includes that hash.
var last_tick_usec: int = 0
var last_runner_tick_usec: int = 0
## A probe for the per-phase split, null unless a HUD sets one (P38t's TimingProbe). It gets every
## begin() and mark() of Sim.step; a probe changes no hash.
var probe: SimProbe
## Positions before the last tick, same indices as world.pos_x and world.pos_y.
var prev_pos_x: PackedInt32Array = PackedInt32Array()
var prev_pos_y: PackedInt32Array = PackedInt32Array()
## Stops _process from ticking, also between two ticks of one frame. run_ticks ignores it.
var paused: bool = false

var _micro_ticks: int = 0
var _app_paused: bool = false
## Reused every tick, so a tick allocates no command list. MatchLoop.step stamps the commands in
## place and never empties the list, so _tick does, after every step: a command left in it would
## be stamped, recorded and applied again on the next tick.
var _commands: Array[Command] = []
## Times Sim.step and passes every call on to `probe`; handed to every loop.step.
var _step_probe: StepProbe = StepProbe.new()


func _ready() -> void:
	if scenario != null:
		start()


## Builds a new world from the scenario with the sim stream of `match_seed`, and a new MatchLoop:
## empty queue, clock at zero, sequences from 0 again, no checkpoint yet.
func start() -> void:
	world = World.from_scenario(scenario, DetRng.create(match_seed, DetRandom.STREAM_SIM))
	var scenario_path: String = scenario.resource_path if scenario != null else ""
	loop = MatchLoop.create(scenario, scenario_path, match_seed, world)
	replay = loop.replay
	match_serial += 1
	last_hash = loop.last_hash
	last_tick_usec = 0
	last_runner_tick_usec = 0
	prev_pos_x = world.pos_x.duplicate()
	prev_pos_y = world.pos_y.duplicate()
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


func _tick() -> void:
	var started: int = Time.get_ticks_usec()
	# Copied by index, not duplicate(), so the arrays keep their buffers. They only change size
	# when a unit is added to a running world, which nothing does before P42a; re-alignment by id
	# comes with MatchSnapshot (P38s).
	var count: int = world.unit_count()
	if prev_pos_x.size() != count:
		prev_pos_x.resize(count)
		prev_pos_y.resize(count)
	for row: int in count:
		prev_pos_x[row] = world.pos_x[row]
		prev_pos_y[row] = world.pos_y[row]
	CommandQueue.drain_into(_commands)
	_step_probe.target = probe
	loop.step(world, _commands, _step_probe)
	_commands.clear()
	last_hash = loop.last_hash
	last_tick_usec = _step_probe.step_usec
	last_runner_tick_usec = Time.get_ticks_usec() - started
	ticked.emit(world.tick)
