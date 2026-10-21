extends GdUnitTestSuite
## The golden hashes of the perf arena (plan P49a, ADR 0011 section 4, ADR 0012 section 4, ADR 0013
## section 3). The seed-42 arena is stepped once through MatchLoop for 900 ticks, under each
## implementation of the simulation (the GDScript twins, then the C++ kernels through SimImpls),
## and its checkpoints every 150 ticks and its final hash must equal the literals in
## data/dev/perf_gate.tres (golden_ticks and golden_hex): one set of hashes for both, because the
## choice of implementation is never hashed. The first checkpoint that differs fails the case,
## and the message names its tick and the parts of the state at that tick (World.hash_parts()
## under World.hash_section_names()), so the section that moved is read off the message.
##
## The suite reads no clock and attaches no probe, so it can run alone by path on another
## architecture (P51b runs it on arm64) and the native-clang CI job runs it beside the native
## suites (P51). A sim PR that moves the arena run (P46b is the first) updates the two arrays in
## the gate file on purpose, with a note: plan exception 3.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const TICKS: int = 900
const SEED: int = 42
## The golden checkpoints are 150 ticks apart (ten of the 15-tick checkpoints MatchLoop records).
const GOLDEN_STEP: int = 150
## What a golden hash looks like in the file: World.hash_hex(), 16 lower-case hex digits.
const HEX_FORM: String = "^[0-9a-f]{16}$"
## Names that would put a clock or a probe into this file. Written in pieces here, so that the scan
## of the case below does not find itself; a probe or a timing driver belongs in test_sim_perf.gd.
const BANNED_PARTS: Array[Array] = [
	["Time", ".get_ticks"],
	["OS", ".get_ticks"],
	["Timing", "Probe"],
	["Step", "Probe"],
	["Tick", "Job"],
	["Ref", "Loop"],
	["Performance", ".get_monitor"],
]


## What one run of the arena leaves: the checkpoints MatchLoop recorded, the state hash after the
## last tick, the tick it ended on, the parts of the state at each golden tick and the mask the
## World ran with. An engine base class, so it may sit inside this file (P56c).
class Played:
	extends RefCounted
	var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
	var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
	var final_tick: int = 0
	var final_hash: int = 0
	## World.hash_parts() at each golden tick, by tick.
	var parts: Dictionary[int, PackedInt64Array] = {}
	var native_phases: int = 0


## The arena ends every golden checkpoint, and its last tick, on the hashes of the gate file, in
## the GDScript twins and in the C++ kernels alike. A native run that attached nothing, or a
## GDScript run that did, fails before the hashes are read.
func test_the_arena_ends_on_the_golden_hashes_under_both_implementations(
	impl: int, _test_parameters := _both()
) -> void:
	var gate: PerfGateDef = _gate()
	var played: Played = _play(impl, gate)
	assert_int(played.native_phases).is_equal(
		SimImpls.expected_mask() if impl == SimImpls.Impl.NATIVE else 0
	)
	var problem: String = _first_difference(gate, played)
	var label: String = "native" if impl == SimImpls.Impl.NATIVE else "gdscript"
	assert_str(problem).override_failure_message("%s: %s" % [label, problem]).is_empty()


## The file holds a hash for every 150 ticks up to the last tick of the run, each one a hash and
## each from another state; an emptied or shortened pair of arrays would otherwise pass for want
## of anything to compare.
func test_the_gate_file_holds_a_golden_hash_every_150_ticks_and_the_final() -> void:
	var gate: PerfGateDef = _gate()
	var expected: Array[int] = []
	for tick: int in range(GOLDEN_STEP, TICKS + 1, GOLDEN_STEP):
		expected.append(tick)
	assert_array(Array(gate.golden_ticks)).is_equal(expected)
	assert_int(gate.golden_hex.size()).is_equal(expected.size())
	var form: RegEx = RegEx.create_from_string(HEX_FORM)
	var distinct: Dictionary[String, bool] = {}
	for hex: String in gate.golden_hex:
		assert_object(form.search(hex)).override_failure_message(hex).is_not_null()
		distinct[hex] = true
	assert_int(distinct.size()).is_equal(expected.size())


## The comparison names what a developer needs: the first checkpoint that differs and only that
## one, with the parts of the state at its tick; a final hash, an empty gate and a golden tick that
## the run has no checkpoint at are failures of their own. The run here is made by hand.
func test_the_first_differing_checkpoint_is_named_with_the_parts_of_the_state() -> void:
	var names: PackedStringArray = World.hash_section_names()
	var played: Played = _hand_played(names.size())
	var gate: PerfGateDef = _hand_gate([150, 300], [0x1111, 0x2222])
	assert_str(_first_difference(gate, played)).is_empty()
	# The second checkpoint differs: its tick, the golden and the real hash, every section name.
	gate = _hand_gate([150, 300], [0x1111, 0x2223])
	var message: String = _first_difference(gate, played)
	assert_str(message).contains("tick 300").contains(World.hash_hex(0x2223))
	assert_str(message).contains(World.hash_hex(0x2222)).not_contains("tick 150")
	for index: int in names.size():
		assert_str(message).contains("%s=%s" % [names[index], World.hash_hex(300 + index)])
	# Both differ: the first one is named, and the second is not.
	gate = _hand_gate([150, 300], [0x1112, 0x2223])
	message = _first_difference(gate, played)
	assert_str(message).contains("tick 150").not_contains("tick 300")
	# The final hash is checked after the checkpoints, and the last golden tick must be the last.
	played.final_hash = 0x3334
	message = _first_difference(_hand_gate([150, 300], [0x1111, 0x2222]), played)
	assert_str(message).contains("final").contains(World.hash_hex(0x3334))
	played.final_hash = 0x2222
	message = _first_difference(_hand_gate([150], [0x1111]), played)
	assert_str(message).contains("final").contains("tick 300")
	# A golden tick the run has no checkpoint at, and a gate that holds nothing.
	message = _first_difference(_hand_gate([150, 301], [0x1111, 0x2222]), played)
	assert_str(message).contains("tick 301").contains("no checkpoint")
	message = _first_difference(_hand_gate([], []), played)
	assert_str(message).contains("no golden")
	message = _first_difference(_hand_gate([150, 300], [0x1111]), played)
	assert_str(message).contains("pair")


## No clock and no probe in this file (the header's promise to P51b), by a scan of its own source.
func test_the_suite_reads_no_clock_and_attaches_no_probe() -> void:
	var source: String = FileAccess.get_file_as_string("res://tests/perf/test_golden_hashes.gd")
	assert_str(source).contains("class Played")
	var found: Array[String] = []
	for parts: Array in BANNED_PARTS:
		var name: String = "".join(PackedStringArray(parts))
		if source.contains(name):
			found.append(name)
	assert_array(found).is_empty()


## The parameter sets of a test that runs under both implementations (gdUnit4 calls it by name).
func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The gate file read again, past the resource cache.
func _gate() -> PerfGateDef:
	var gate: PerfGateDef = (
		ResourceLoader.load(GATE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PerfGateDef
	)
	assert_object(gate).is_not_null()
	return gate


## The seed-42 arena for TICKS ticks through MatchLoop, nothing else: no queued command, no probe.
## `impl` is a SimImpls.Impl; the parts of the state are taken at the gate's golden ticks.
func _play(impl: int, gate: PerfGateDef) -> Played:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, world)
	assert_array(SimImpls.use(world, impl)).is_empty()
	for phase: int in SimImpls.EXPECTED_PHASES:
		assert_bool(SimImpls.is_native(world, phase)).is_equal(impl == SimImpls.Impl.NATIVE)
	var played: Played = Played.new()
	var queued: Array[Command] = []
	for _tick: int in TICKS:
		loop.step(world, queued)
		if gate.golden_ticks.has(world.tick):
			played.parts[world.tick] = world.hash_parts()
	played.checkpoint_ticks = loop.replay.checkpoint_ticks
	played.checkpoint_hashes = loop.replay.checkpoint_hashes
	played.final_tick = world.tick
	played.final_hash = world.state_hash()
	played.native_phases = world.native_phases
	return played


## "" when every golden checkpoint of `gate` equals the run's and its last tick is the run's final
## tick with the final hash; else the first thing that is wrong, named: a gate that holds nothing or
## whose arrays do not pair, a golden tick the run has no checkpoint at, the first checkpoint whose
## hash differs (its tick, both hashes and the parts of the state at that tick), then the final.
func _first_difference(gate: PerfGateDef, played: Played) -> String:
	var problem: String = _gate_problem(gate)
	if problem.is_empty():
		problem = _checkpoint_problem(gate, played)
	if problem.is_empty():
		problem = _final_problem(gate, played)
	return problem


## What is wrong with the gate's arrays alone: nothing in them, or unequal sizes.
func _gate_problem(gate: PerfGateDef) -> String:
	var ticks: int = gate.golden_ticks.size()
	var hexes: int = gate.golden_hex.size()
	if ticks == 0 or hexes == 0:
		return "the gate file holds no golden hashes"
	if ticks != hexes:
		return "golden_ticks (%d) and golden_hex (%d) do not pair up" % [ticks, hexes]
	return ""


## The first golden tick that the run has no checkpoint at, or whose hash differs.
func _checkpoint_problem(gate: PerfGateDef, played: Played) -> String:
	for index: int in gate.golden_ticks.size():
		var tick: int = gate.golden_ticks[index]
		var at: int = played.checkpoint_ticks.find(tick)
		if at < 0:
			return "golden tick %d: the run has no checkpoint at tick %d" % [tick, tick]
		var got: String = World.hash_hex(played.checkpoint_hashes[at])
		if got != gate.golden_hex[index]:
			return (
				"first differing checkpoint, tick %d: golden %s, got %s; parts at that tick: %s"
				% [
					tick,
					gate.golden_hex[index],
					got,
					_parts_text(played.parts.get(tick, PackedInt64Array()))
				]
			)
	return ""


## The last golden tick is the run's last tick, and the hash after it is the last golden hash.
func _final_problem(gate: PerfGateDef, played: Played) -> String:
	var final_hex: String = World.hash_hex(played.final_hash)
	if gate.golden_ticks[-1] != played.final_tick:
		return (
			"the last golden tick %d is not the run's last tick %d (final hash %s)"
			% [gate.golden_ticks[-1], played.final_tick, final_hex]
		)
	if final_hex != gate.golden_hex[-1]:
		return (
			"final hash at tick %d: golden %s, got %s"
			% [played.final_tick, gate.golden_hex[-1], final_hex]
		)
	return ""


## The parts of a state as `name=hex` pairs under World.hash_section_names(), in that order.
func _parts_text(parts: PackedInt64Array) -> String:
	var names: PackedStringArray = World.hash_section_names()
	var pairs: PackedStringArray = PackedStringArray()
	for index: int in mini(names.size(), parts.size()):
		pairs.append("%s=%s" % [names[index], World.hash_hex(parts[index])])
	return " ".join(pairs) if not pairs.is_empty() else "(not taken)"


## A run that no match produced: checkpoints at ticks 150 and 300 with the hashes 0x1111 and 0x2222,
## the final tick 300 with 0x2222 and, at each, parts that name their tick (150 + index, 300 +
## index).
func _hand_played(section_count: int) -> Played:
	var played: Played = Played.new()
	played.checkpoint_ticks = PackedInt32Array([150, 300])
	played.checkpoint_hashes = PackedInt64Array([0x1111, 0x2222])
	played.final_tick = 300
	played.final_hash = 0x2222
	for tick: int in [150, 300]:
		var parts: PackedInt64Array = PackedInt64Array()
		for index: int in section_count:
			parts.append(tick + index)
		played.parts[tick] = parts
	return played


## A gate with the given golden ticks and hashes (the hashes as ints, written in the file's form).
func _hand_gate(ticks: Array[int], hashes: Array[int]) -> PerfGateDef:
	var gate: PerfGateDef = PerfGateDef.new()
	gate.golden_ticks = PackedInt32Array(ticks)
	var hexes: PackedStringArray = PackedStringArray()
	for hash_value: int in hashes:
		hexes.append(World.hash_hex(hash_value))
	gate.golden_hex = hexes
	return gate
