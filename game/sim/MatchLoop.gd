class_name MatchLoop
extends RefCounted
## The one tick driver (ADR 0007 section 9): the runner, Replay.play, the perf test and the
## headless matches all step a match through it, so the phone and CI cannot drift through
## duplicated stamping code. Per tick it collects the scenario's orders, appends the queued
## commands, stamps tick and sequence, records every command in the replay, calls Sim.step and
## adds a checkpoint every Replay.CHECKPOINT_PERIOD ticks. Pure sim code: no Node, no clock.

## The match's log. Replay.begin(scenario_path, seed, defs_hash) made it; the caller finishes it.
var replay: Replay
## The state hash of the last checkpoint, 0 until the first one. The tick-0 state has no
## checkpoint: a checkpoint is the hash after a tick, and none has run yet.
var last_hash: int = 0
## The sequence the next command gets. It counts from 0 and every recorded command takes one, so
## the sequences of a match are unique and increasing.
var next_sequence: int = 0

var _orders: ScenarioOrders
## The commands of one tick, reused. Empty between two steps.
var _commands: Array[Command] = []

## A loop for the match of `world`. It records `scenario_path`, `seed` and the world's defs_hash
## (ADR 0007 section 8) in its replay. `seed` is only recorded: the caller made the world's
## DetRandom from it. A null `scenario` yields no scenario orders; Replay.play uses that, because
## its log already holds the orders the scenario gave. The parameters keep the contract's names.
@warning_ignore("shadowed_global_identifier")
static func create(
	scenario: ScenarioDef, scenario_path: String, seed: int, world: World
) -> MatchLoop:
	var loop: MatchLoop = MatchLoop.new()
	world.prepare()
	loop.replay = Replay.begin(scenario_path, seed, world.defs_hash())
	loop._orders = ScenarioOrders.create(scenario)
	return loop


## Runs one tick. The scenario's orders for this tick come first, then `queued` in the order it
## holds them; each gets `world.tick` and the next sequence, is recorded in the replay as it is
## (so a command that Sim.step then drops, an over-limit one among them, is in the log too, and
## drops again in a replay), and Sim.step runs. When the tick after the step is one that
## Replay.CHECKPOINT_PERIOD divides (the first is 15; none at tick 0) the state hash becomes a
## checkpoint and `last_hash`. Inside Sim.step that tick is still `world.tick + 1`, because
## Sim.step counts the tick last: a rule that must stay off the hashing step tests that.
##
## The commands in `queued` change hands here (ADR 0012 section 2): they are stamped in place, not
## copied, so the caller must not reuse or read them afterwards, and each one may appear once.
## `queued` itself is only read, never cleared (the caller, the runner, clears it after the step):
## a command passed again is stamped again, recorded again and applied again. A
## null in `queued` is skipped: it is not recorded, takes no sequence and is not counted as
## dropped, in the run and so in its replay (CommandQueue.submit ignores null, so none arrives
## from the runner). A tick with no orders and no queued commands creates nothing.
func step(world: World, queued: Array[Command], probe: SimProbe = null) -> void:
	var commands: Array[Command] = _commands
	_orders.collect(world, commands)
	for command: Command in queued:
		if command != null:
			commands.append(command)
	if not commands.is_empty():
		_stamp_and_record(world.tick, commands)
	Sim.step(world, commands, probe)
	commands.clear()
	if world.tick % Replay.CHECKPOINT_PERIOD == 0:
		last_hash = world.state_hash()
		replay.add_checkpoint(world.tick, last_hash)


## Gives each command `tick` and the next sequence, in list order, and records it. Runs before
## Sim.step sorts the list, so the log is in stamping order.
func _stamp_and_record(tick: int, commands: Array[Command]) -> void:
	for command: Command in commands:
		command.tick = tick
		command.sequence = next_sequence
		next_sequence += 1
		replay.record(command)
