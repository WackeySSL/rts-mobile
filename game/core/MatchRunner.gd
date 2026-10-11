class_name MatchRunner
extends Node
## Runs one match: builds the World from a scenario and steps it at Sim.TICK_RATE (ADR 0003
## section 7). Frame delta lives only here; the sim never sees time. The view interpolates
## between prev_pos_* and world.pos_* with alpha().
## It needs the CommandQueue autoload, so a headless `godot -s` tool must load() this script at
## runtime; naming MatchRunner in the entry script does not compile.

## Emitted after each tick with world.tick, the number of ticks played so far.
signal ticked(tick: int)

## A tick is split into this many parts, so the frame clock is an integer and frame lengths
## that add up to whole ticks (four times 1/60 s) step exactly.
const MICRO_TICKS_PER_TICK: int = 1_000_000

@export var scenario: ScenarioDef
## Ticks one frame may play. Time beyond that is dropped, not carried to the next frame.
@export var max_catch_up_ticks: int = 4

var world: World
## Positions before the last tick, same indices as world.pos_x and world.pos_y.
var prev_pos_x: PackedInt32Array = PackedInt32Array()
var prev_pos_y: PackedInt32Array = PackedInt32Array()
## Stops _process from ticking, also between two ticks of one frame. run_ticks ignores it.
var paused: bool = false

var _micro_ticks: int = 0
var _app_paused: bool = false
## Runner-wide, so every command of a match gets its own; start() restarts it. 0 is "not stamped".
var _next_sequence: int = 1
## Reused every tick, so a tick allocates no command list.
var _commands: Array[Command] = []


func _ready() -> void:
	if scenario != null:
		start()


## Builds a new world from the scenario: empty queue, clock at zero, sequence back at 1.
func start() -> void:
	world = World.from_scenario(scenario)
	prev_pos_x = world.pos_x.duplicate()
	prev_pos_y = world.pos_y.duplicate()
	_micro_ticks = 0
	_next_sequence = 1
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
	# Copied by index, not duplicate(), so the arrays keep their buffers. They only change size
	# when a unit is added to a running world, which Phase 1 never does.
	var count: int = world.unit_count()
	if prev_pos_x.size() != count:
		prev_pos_x.resize(count)
		prev_pos_y.resize(count)
	for row: int in count:
		prev_pos_x[row] = world.pos_x[row]
		prev_pos_y[row] = world.pos_y[row]
	CommandQueue.drain_into(_commands)
	for command: Command in _commands:
		command.tick = world.tick
		command.sequence = _next_sequence
		_next_sequence += 1
	Sim.step(world, _commands)
	_commands.clear()
	ticked.emit(world.tick)
