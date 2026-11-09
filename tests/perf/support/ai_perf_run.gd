extends RefCounted
## One match of `data/scenarios/perf_ai.tres` for the AI perf suite (plan row P189, ADR 0030 section
## 4): two Normal `OpponentAi` through `AiDriver.think_all` and `MatchLoop.step` for `TICKS` ticks,
## the way the smoke harness plays a match (`tests/smoke/smoke_run.gd`). It keeps the time of every
## think (report only), the lines of the counted bounds that a think broke (deterministic), the
## peak of every judged counter and the state hash at every checkpoint. It also builds the three
## report-only lines, so the suite and its pin of their heads share one source. Not a test suite.

const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")

const PATH: String = "res://data/scenarios/perf_ai.tres"
const TICKS: int = 900
const SEED: int = 42
const LEVELS: Array[String] = ["normal", "normal"]
## The passes of one think: the view's own (1) and at most two more for a slot (ADR 0030 section 4).
const PASSES_MAX: int = 3
## The report-only lines: `WATCH <area> <name> key=value ...`.
const THINK_HEAD: String = "WATCH ai think"
const FLOW_HEAD: String = "WATCH ai flow"
const PEAKS_HEAD: String = "WATCH ai peaks"

## The microseconds of each call of `think_all` that made a think (the view of the think included,
## as the snapshot's `think_usec` is), in tick order.
var think_usec: PackedFloat64Array = PackedFloat64Array()
## The lines of the counted bounds that some think broke, each once; empty inside every bound.
var violations: Array[String] = []
## The largest value of each judged counter over every think of both AIs, by name (counts only).
var peaks: Dictionary[String, int] = {}
## Thinks seen, the most that one tick made, and the thinks the driver's rule owes in `TICKS`.
var thinks: int = 0
var most_in_a_tick: int = 0
var thinks_owed: int = 0
## The ticks after which every slot of the flow cache was referenced (ADR 0030 section 4).
var flow_full_ticks: int = 0
var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
var final_hash: int = 0
var dropped_commands: int = 0
var match_end_tick: int = 0
var controllers: Array[AiController] = []
## The implementation the sim ran with: "native" or "gdscript" (the AI is GDScript in both).
var impl: String = ""

## The shipped AI defs the controllers were made from, by the same path (`SmokeRun.def_path`).
var _defs: Array[OpponentDef] = []


## The nearest-rank p95 of the think times `usec` (microseconds).
static func p95_of(usec: PackedFloat64Array) -> float:
	return PerfReport.p95(usec)


## The largest of the think times `usec` (0.0 for none).
static func max_of(usec: PackedFloat64Array) -> float:
	var most: float = 0.0
	for sample: float in usec:
		most = maxf(most, sample)
	return most


## `WATCH ai think impl= slots= thinks= p95_us= max_us= est_phone_p95_ms=`; the estimate is the
## p95 in ms times `ratio`. `thinks=` is added to ADR 0030 section 4's keys.
static func think_line(
	p95_us: float, max_us: float, impl_name: String, count: int, ratio: float
) -> String:
	var values: Dictionary = {
		"impl": impl_name,
		"slots": OpponentAi.SLOTS,
		"thinks": count,
		"p95_us": p95_us,
		"max_us": max_us,
		"est_phone_p95_ms": p95_us / 1000.0 * ratio,
	}
	return PerfReport.sub_line(THINK_HEAD, values, false)


## `WATCH ai flow full_ticks= hash=`.
static func flow_line(full_ticks: int, hash_hex: String) -> String:
	return PerfReport.sub_line(FLOW_HEAD, {"full_ticks": full_ticks, "hash": hash_hex}, false)


## `WATCH ai peaks name=count ...` in the order the peaks were first seen.
static func peaks_line(counts: Dictionary[String, int]) -> String:
	var values: Dictionary = {}
	for name: String in counts:
		values[name] = counts[name]
	return PerfReport.sub_line(PEAKS_HEAD, values, false)


## Plays the match.
func play() -> void:
	var world: World = SmokeRun.world_of(SEED, PATH)
	impl = SmokeRun.impl_name()
	for problem: String in SmokeRun.attach_impl(world):
		violations.append("sim impl: " + problem)
	var loop: MatchLoop = SmokeRun.loop_of(world, SEED, PATH)
	controllers = SmokeRun.controllers_of(SEED, PATH, LEVELS)
	var scenario: ScenarioDef = load(PATH) as ScenarioDef
	for index: int in controllers.size():
		var faction: String = String(scenario.factions[index + 1].id)
		_defs.append(load(SmokeRun.def_path(faction, LEVELS[index])) as OpponentDef)
	var counter: SmokeCount = SmokeCount.new(controllers.size())
	counter.start(world)
	var commands: Array[Command] = []
	for tick: int in TICKS:
		for ai: AiController in controllers:
			if (tick + ai.think_offset) % maxi(ai.think_period, 1) == 0:
				thinks_owed += 1
		commands.clear()
		var before: PackedInt32Array = _commands_of()
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


## Judges the think that just ran, for each controller that thought this tick, against the bounds
## of ADR 0030 sections 3 and 4 (all of them caps of the defs or the rules, none a time), and keeps
## the peaks. A manager's counters are read only in the slot that runs it, because they keep their
## value from its last run. `before` holds each controller's `commands` before the call and `sent`
## the Commands the call appended.
func _check(world: World, before: PackedInt32Array, sent: int) -> void:
	var counted: int = 0
	for index: int in controllers.size():
		var ai: OpponentAi = controllers[index] as OpponentAi
		if ai == null or (world.tick + ai.think_offset) % ai.think_period != 0:
			continue
		var delta: int = ai.commands - before[index]
		counted += delta
		_peak("commands", delta)
		var def: OpponentDef = _defs[index]
		var memory: AiMemory = ai.memory
		var tag: String = "player %d slot %d" % [ai.player_id, ai.last_slot]
		_cap(tag, "work", ai.work, PASSES_MAX)
		_cap(tag, "commands_cut", ai.commands_cut, 0)
		match ai.last_slot:
			OpponentAi.Slot.ECONOMY:
				_cap(tag, "placement_tries", ai.economy.placement_tries, def.place_tries_per_think)
			OpponentAi.Slot.ARMY:
				_cap(tag, "army_tests", ai.army.tests, def.target_tests_max)
				_cap(tag, "hit_tests", ai.army.hit_tests, def.target_tests_max)
			_:
				_cap(tag, "strike_tests", ai.striker.tests, def.target_tests_max)
		_cap(tag, "goal_keys", memory.goal_keys(), def.goal_keys_max)
		_cap(tag, "keys_army", memory.goal_keys_of(AiMemory.Owner.ARMY), 2)
		_cap(tag, "keys_staging", memory.goal_keys_of(AiMemory.Owner.STAGING), 2)
		_cap(tag, "keys_scout", memory.goal_keys_of(AiMemory.Owner.SCOUT), 1)
		_cap(tag, "sectors", ai.intel.sector_count(), def.sectors_max)
		_cap(tag, "squads", _squads_used(memory), def.squads_max)
		_check_lists(world, memory, tag)
	if counted != sent:
		_fail(
			(
				"the thinks' commands counters (%d) do not add up to the commands sent (%d)"
				% [counted, sent]
			)
		)


## The id lists of the memory against their caps: own lists at `unit_cap` (a building list at
## `building_cap`), seen lists at (players - 1) times that (ADR 0030 section 3 and its notes). Note
## `own_mobile_id` sits at the cap here, because `perf_ai.tres` spawns exactly `unit_cap` mobile
## rows
## for each player.
func _check_lists(world: World, memory: AiMemory, tag: String) -> void:
	var others: int = world.player_count - 1
	var lists: Dictionary[String, PackedInt32Array] = {
		"unit_id": memory.unit_id,
		"own_mobile_id": memory.own_mobile_id,
		"hp_id": memory.hp_id,
		"member_id": memory.member_id,
		"withdrawn_id": memory.withdrawn_id,
		"site_id": memory.site_id,
		"seen_unit_id": memory.seen_unit_id,
		"seen_mobile_id": memory.seen_mobile_id,
		"seen_site_id": memory.seen_site_id,
	}
	var caps: Dictionary[String, int] = {
		"unit_id": memory.unit_cap,
		"own_mobile_id": memory.unit_cap,
		"hp_id": memory.unit_cap,
		"member_id": memory.unit_cap,
		"withdrawn_id": memory.unit_cap,
		"site_id": world.building_cap,
		"seen_unit_id": others * memory.unit_cap,
		"seen_mobile_id": others * memory.unit_cap,
		"seen_site_id": others * world.building_cap,
	}
	for name: String in lists:
		_cap(tag, name, lists[name].size(), caps[name])


func _squads_used(memory: AiMemory) -> int:
	var used: int = 0
	for role: int in memory.squad_role:
		if role != AiMemory.NONE:
			used += 1
	return used


## Keeps the peak of `name` and records a violation when `value` is above `cap`.
func _cap(tag: String, name: String, value: int, cap: int) -> void:
	_peak(name, value)
	if value > cap:
		_fail("%s: %s is %d, above its cap %d" % [tag, name, value, cap])


func _peak(name: String, value: int) -> void:
	peaks[name] = maxi(peaks.get(name, 0), value)


func _fail(line: String) -> void:
	if not violations.has(line):
		violations.append(line)


func _commands_of() -> PackedInt32Array:
	var counts: PackedInt32Array = PackedInt32Array()
	for ai: AiController in controllers:
		counts.append(ai.commands)
	return counts
