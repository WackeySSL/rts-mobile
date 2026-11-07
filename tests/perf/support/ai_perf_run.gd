extends RefCounted
## One match of `data/scenarios/perf_ai.tres` for the AI perf suite (plan row P189, ADR 0030 section
## 4): two Normal `OpponentAi` through `AiDriver.think_all` and `MatchLoop.step` for `TICKS` ticks,
## the way the smoke harness plays a match (`tests/smoke/smoke_run.gd`). It keeps the time of every
## think (report only), the lines of the counted bounds that a think broke (deterministic) and the
## state hash at every checkpoint. Not a test suite.

const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")

const PATH: String = "res://data/scenarios/perf_ai.tres"
const TICKS: int = 900
const SEED: int = 42
const LEVELS: Array[String] = ["normal", "normal"]
const FACTION_DEF: String = "res://data/ai/opponent_%s.tres"

## The microseconds of each call of `think_all` that made a think (the view of the think included,
## as the snapshot's `think_usec` is), in tick order.
var think_usec: PackedFloat64Array = PackedFloat64Array()
## The lines of the counted bounds that some think broke, each once; empty inside every bound.
var violations: Array[String] = []
## Thinks seen, the most that one tick made, and the commands the two AIs sent over the match.
var thinks: int = 0
var most_in_a_tick: int = 0
## The ticks after which every slot of the flow cache was referenced (ADR 0030 section 4).
var flow_full_ticks: int = 0
var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
var final_hash: int = 0
var dropped_commands: int = 0
var match_end_tick: int = 0
var controllers: Array[AiController] = []
## The implementation the sim ran with: "native" or "gdscript".
var impl: String = ""


## Plays the match and returns what it left.
static func play() -> RefCounted:
	var run: RefCounted = (load("res://tests/perf/support/ai_perf_run.gd") as GDScript).new()
	run._play()
	return run


func _play() -> void:
	var world: World = SmokeRun.world_of(SEED, PATH)
	impl = SmokeRun.impl_name()
	for problem: String in SmokeRun.attach_impl(world):
		violations.append("sim impl: " + problem)
	var loop: MatchLoop = SmokeRun.loop_of(world, SEED, PATH)
	controllers = SmokeRun.controllers_of(SEED, PATH, LEVELS)
	var counter: SmokeCount = SmokeCount.new(controllers.size())
	counter.start(world)
	var commands: Array[Command] = []
	for _tick: int in TICKS:
		commands.clear()
		var before: PackedInt32Array = _commands_of(controllers)
		var started: int = Time.get_ticks_usec()
		var thought: int = AiDriver.think_all(world, controllers, commands)
		var spent: int = Time.get_ticks_usec() - started
		if thought > 0:
			think_usec.append(float(spent))
			thinks += thought
			most_in_a_tick = maxi(most_in_a_tick, thought)
			_check(world, before, commands.size())
		loop.step(world, commands)
		counter.after_step(world)
	flow_full_ticks = counter.flow_full_ticks
	checkpoint_ticks = loop.replay.checkpoint_ticks
	checkpoint_hashes = loop.replay.checkpoint_hashes
	final_hash = world.state_hash()
	dropped_commands = world.dropped_commands
	match_end_tick = world.match_end_tick


## The bounds of ADR 0030 section 4 on the controllers that thought this tick (their commands
## counter moved or their `work` was reset), read from the controllers' own counted ints and from
## the memory: all of them are caps of the defs, none is a time.
func _check(world: World, before: PackedInt32Array, sent: int) -> void:
	var counted: int = 0
	for index: int in controllers.size():
		var ai: OpponentAi = controllers[index] as OpponentAi
		if ai == null or (world.tick + ai.think_offset) % ai.think_period != 0:
			continue
		counted += ai.commands - before[index]
		var def: OpponentDef = _def_of(ai)
		var memory: AiMemory = ai.memory
		var tag: String = "player %d slot %d: " % [ai.player_id, ai.last_slot]
		_bound(ai.work <= 3, tag + "work %d above 3" % ai.work)
		_bound(
			ai.commands - before[index] <= ai.commands_per_think_max,
			tag + "commands above commands_per_think_max"
		)
		_bound(ai.commands_cut == 0, tag + "a think sent more than the level allows")
		_bound(
			ai.economy.placement_tries <= def.place_tries_per_think,
			tag + "placement tries above place_tries_per_think"
		)
		_bound(ai.army.tests <= def.target_tests_max, tag + "army tests above target_tests_max")
		_bound(ai.army.hit_tests <= def.target_tests_max, tag + "hit tests above target_tests_max")
		_bound(
			ai.striker.tests <= def.target_tests_max, tag + "strike tests above target_tests_max"
		)
		_bound(memory.goal_keys() <= def.goal_keys_max, tag + "goal keys above goal_keys_max")
		_bound(memory.goal_keys_of(AiMemory.Owner.ARMY) <= 2, tag + "army goal keys above 2")
		_bound(memory.goal_keys_of(AiMemory.Owner.STAGING) <= 2, tag + "staging goal keys above 2")
		_bound(memory.sector_own.size() <= def.sectors_max, tag + "sectors above sectors_max")
		_bound(memory.squad_role.size() <= def.squads_max, tag + "squads above squads_max")
		for list: PackedInt32Array in [memory.unit_id, memory.own_mobile_id, memory.hp_id]:
			_bound(list.size() <= memory.unit_cap, tag + "an id list above unit_cap")
	_bound(counted == sent, "the thinks' commands counters do not add up to the commands sent")


func _bound(holds: bool, line: String) -> void:
	if not holds and not violations.has(line):
		violations.append(line)


## The shipped OpponentDef of the controller's def id.
func _def_of(ai: OpponentAi) -> OpponentDef:
	return load(FACTION_DEF % String(ai.def_id).trim_prefix("opponent_")) as OpponentDef


func _commands_of(list: Array[AiController]) -> PackedInt32Array:
	var counts: PackedInt32Array = PackedInt32Array()
	for ai: AiController in list:
		counts.append(ai.commands)
	return counts
