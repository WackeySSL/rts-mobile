extends GdUnitTestSuite
## The golden hashes of the perf arena (plan P49a, ADR 0011 section 4, ADR 0012 section 4, ADR 0013
## section 3). The seed-42 arena is stepped once through MatchLoop for 900 ticks, under each
## implementation of the simulation (the GDScript twins, then the C++ kernels through SimImpls),
## and its checkpoints every 150 ticks and its final hash must equal the literals in
## data/dev/perf_gate.tres (golden_ticks and golden_hex): one set of hashes for both, because the
## choice of implementation is never hashed. The first checkpoint that differs fails the case,
## and the message names its tick, the golden and the real hash and the parts of the run's state at
## that tick (World.hash_parts() under World.hash_section_names()). The gate file holds only the
## combined hash of each checkpoint, so the parts are the run's own: the section that moved is
## found by comparing them with the same message from a run on the base commit. The message ends
## with the two lines of the gate file that would pin the run, to paste over the old ones, so a
## re-pin (exception 3) needs one failing run and not one for each checkpoint.
##
## The suite reads no clock and attaches no probe, so it can run alone by path on another
## architecture (P51b runs it on arm64) and the native-clang CI job runs it beside the native
## suites (P51). A sim PR that moves the arena run (P46b is the first) updates the two arrays in
## the gate file on purpose, with a note: plan exception 3.
##
## The base arena (plan P93, ADR 0021 section 2) is pinned here too, the same way, because this is
## the suite that the native-clang job and the arm64 job run: its seed-42 run of
## data/scenarios/perf_bases.tres for 900 ticks must end on `bases_golden_ticks` and
## `bases_golden_hex` of the gate file under both implementations. Each helper takes the prefix of
## the gate fields ("" for the perf arena, BASES_PREFIX for the base arena), so a failure of the
## base arena names its own fields and prints its own two lines to paste. A later sim row that moves
## the base arena re-pins them under plan exception 3, with the reason.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const BASES_PATH: String = "res://data/scenarios/perf_bases.tres"
## The prefix of the base arena's gate fields: `bases_golden_ticks` and `bases_golden_hex`.
const BASES_PREFIX: String = "bases_"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const TICKS: int = 900
const SEED: int = 42
## The golden checkpoints are 150 ticks apart (ten of the 15-tick checkpoints MatchLoop records).
const GOLDEN_STEP: int = 150
## What a golden hash looks like in the file: World.hash_hex(), 16 lower-case hex digits.
const HEX_FORM: String = "^[0-9a-f]{16}$"
## How the two arrays begin in the gate file, which is how a failure prints the lines to paste.
const TICKS_LINE: String = "golden_ticks = PackedInt32Array("
const HEX_LINE: String = "golden_hex = PackedStringArray("
## The checkpoints of the runs made by hand. World.hash_hex() writes the lowest byte of a hash
## first, so these differ in both ends of the 16 digits, and a comparison that reads part of a
## hash shows; the two flips change the first two digits and the last two.
const HAND_TICKS: Array[int] = [150, 300, 450, 600]
const HAND_HASHES: Array[int] = [
	0x1000000000000001, 0x2000000000000002, 0x3000000000000003, 0x4000000000000004
]
const FIRST_DIGITS_FLIP: int = 0x1
const LAST_DIGITS_FLIP: int = 0x7 << 56
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
	_assert_ends_on_the_golden_hashes(impl, ARENA_PATH, "")


## The base arena (plan P93) ends every checkpoint of `bases_golden_ticks`, and its last tick, on
## `bases_golden_hex`, in the GDScript twins and in the C++ kernels alike: one set of hashes for
## both, as for the perf arena. The two implementations agreeing is the cross-check, and a native
## run that attached nothing fails before the hashes are read.
func test_the_base_arena_ends_on_its_golden_hashes_under_both_implementations(
	impl: int, _test_parameters := _both()
) -> void:
	_assert_ends_on_the_golden_hashes(impl, BASES_PATH, BASES_PREFIX)


## The two tests above run once for each parameter set, so a `_both()` that dropped one would leave
## the suite green with one implementation unchecked: the sets are the two implementations, once
## each.
func test_the_parameter_sets_are_both_implementations_once_each() -> void:
	var seen: Array[int] = []
	for parameters: Array in _both():
		seen.append(parameters[0])
	assert_array(seen).is_equal(SimImpls.IMPLS)


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


## The base arena's pair of arrays has the same shape (a hash every 150 ticks up to the 900th, each
## a hash and each from another state), and none of its hashes is one of the perf arena's: the base
## arena is another match (its own map, factions, buildings and strikes), so a pair copied from the
## wrong arrays, or a scenario that fell back to the perf arena, shows here.
func test_the_gate_file_holds_a_base_arena_hash_every_150_ticks_none_of_the_perf_arenas() -> void:
	var gate: PerfGateDef = _gate()
	var expected: Array[int] = []
	for tick: int in range(GOLDEN_STEP, TICKS + 1, GOLDEN_STEP):
		expected.append(tick)
	assert_array(Array(gate.bases_golden_ticks)).is_equal(expected)
	assert_int(gate.bases_golden_hex.size()).is_equal(expected.size())
	var form: RegEx = RegEx.create_from_string(HEX_FORM)
	var distinct: Dictionary[String, bool] = {}
	for hex: String in gate.bases_golden_hex:
		assert_object(form.search(hex)).override_failure_message(hex).is_not_null()
		assert_bool(gate.golden_hex.has(hex)).override_failure_message(hex).is_false()
		distinct[hex] = true
	assert_int(distinct.size()).is_equal(expected.size())


## The comparison names what a developer needs: the first checkpoint that differs and only that
## one, with the golden and the real hash and the parts of the state at its tick. Each of the four
## checkpoints of a run made by hand is the one that differs in turn, in the first and in the last
## digits of its hash (the others stay equal), and when two differ the first one is named.
func test_the_first_differing_checkpoint_is_named_with_the_parts_of_the_state() -> void:
	var names: PackedStringArray = World.hash_section_names()
	var played: Played = _hand_played(names.size())
	assert_str(_first_difference(_hand_gate(HAND_TICKS, HAND_HASHES), played)).is_empty()
	for index: int in HAND_TICKS.size():
		for flip: int in [FIRST_DIGITS_FLIP, LAST_DIGITS_FLIP]:
			var hashes: Array[int] = HAND_HASHES.duplicate()
			hashes[index] ^= flip
			var tick: int = HAND_TICKS[index]
			var message: String = _first_difference(_hand_gate(HAND_TICKS, hashes), played)
			assert_str(message).contains(_differing(tick)).contains(
				(
					"golden %s, got %s"
					% [World.hash_hex(hashes[index]), World.hash_hex(HAND_HASHES[index])]
				)
			)
			for other: int in HAND_TICKS:
				if other != tick:
					assert_str(message).not_contains(_differing(other))
			for section: int in names.size():
				assert_str(message).contains(
					"%s=%s" % [names[section], World.hash_hex(tick + section)]
				)
	var two: Array[int] = HAND_HASHES.duplicate()
	two[1] ^= LAST_DIGITS_FLIP
	two[3] ^= FIRST_DIGITS_FLIP
	var both: String = _first_difference(_hand_gate(HAND_TICKS, two), played)
	assert_str(both).contains(_differing(300)).not_contains(_differing(600))


## The failures that are not a differing checkpoint: a final hash that is not the last
## checkpoint's, a last golden tick that is not the run's last, a golden tick the run has no
## checkpoint at, a gate that holds nothing and arrays that do not pair up.
func test_the_other_ways_a_gate_can_fail_are_named() -> void:
	var played: Played = _hand_played(World.hash_section_names().size())
	played.final_hash = 0x3334
	var message: String = _first_difference(_hand_gate(HAND_TICKS, HAND_HASHES), played)
	assert_str(message).contains("final hash at tick 600").contains(World.hash_hex(0x3334))
	played = _hand_played(World.hash_section_names().size())
	message = _first_difference(_hand_gate(HAND_TICKS.slice(0, 3), HAND_HASHES.slice(0, 3)), played)
	assert_str(message).contains("last golden tick 450").contains("last tick 600")
	var ticks: Array[int] = [150, 300, 450, 601]
	message = _first_difference(_hand_gate(ticks, HAND_HASHES), played)
	assert_str(message).contains("tick 601").contains("no checkpoint")
	message = _first_difference(_hand_gate([], []), played)
	assert_str(message).contains("no golden")
	message = _first_difference(_hand_gate(HAND_TICKS, HAND_HASHES.slice(0, 3)), played)
	assert_str(message).contains("pair")


## Every failure ends with the two lines that would pin the run: the checkpoints every 150 ticks
## up to its last tick, in the form of the gate file (the real run is held to that form by the
## case that runs the arena). A re-pin is then a paste, whatever the failure was.
func test_a_failure_ends_with_the_two_lines_that_would_pin_the_run() -> void:
	var played: Played = _hand_played(World.hash_section_names().size())
	var quoted: PackedStringArray = PackedStringArray()
	for hash_value: int in HAND_HASHES:
		quoted.append('"%s"' % World.hash_hex(hash_value))
	var lines: String = "%s150, 300, 450, 600)\n%s%s)" % [TICKS_LINE, HEX_LINE, ", ".join(quoted)]
	assert_str(_repin_text(played)).is_equal(lines)
	var wrong: Array[int] = HAND_HASHES.duplicate()
	wrong[1] ^= FIRST_DIGITS_FLIP
	for gate: PerfGateDef in [
		_hand_gate(HAND_TICKS, wrong), _hand_gate([], []), _hand_gate(HAND_TICKS, wrong.slice(0, 3))
	]:
		assert_str(_first_difference(gate, played)).is_not_empty().ends_with(lines)
	# A run that stopped at tick 300 can pin only what it did.
	played.final_tick = 300
	assert_str(_repin_text(played)).starts_with(TICKS_LINE + "150, 300)\n")


## A failure of the base arena reads and names its own fields: a hand-made gate with a wrong
## `bases_golden_hex` is judged by its `bases_` arrays, and the lines to paste are
## `bases_golden_ticks` and `bases_golden_hex`; the same gate read as the perf arena's, whose arrays
## it leaves empty, is the "no golden hashes" failure; and a pair that does not pair up names the
## base arena's arrays.
func test_a_base_arena_failure_reads_and_names_the_bases_fields() -> void:
	var played: Played = _hand_played(World.hash_section_names().size())
	var right: PerfGateDef = _hand_gate(HAND_TICKS, HAND_HASHES, BASES_PREFIX)
	assert_str(_first_difference(right, played, BASES_PREFIX)).is_empty()
	var wrong: Array[int] = HAND_HASHES.duplicate()
	wrong[2] ^= LAST_DIGITS_FLIP
	var gate: PerfGateDef = _hand_gate(HAND_TICKS, wrong, BASES_PREFIX)
	var message: String = _first_difference(gate, played, BASES_PREFIX)
	assert_str(message).contains(_differing(450)).not_contains(_differing(300))
	var lines: String = (
		"%s150, 300, 450, 600)\n%s" % [BASES_PREFIX + TICKS_LINE, BASES_PREFIX + HEX_LINE]
	)
	assert_str(message).contains(lines)
	assert_str(_repin_text(played, BASES_PREFIX)).starts_with(BASES_PREFIX + TICKS_LINE + "150, ")
	assert_str(_first_difference(gate, played)).contains("no golden")
	var short: PerfGateDef = _hand_gate(HAND_TICKS, HAND_HASHES, BASES_PREFIX)
	short.bases_golden_hex = short.bases_golden_hex.slice(0, 3)
	assert_str(_first_difference(short, played, BASES_PREFIX)).contains("bases_golden_ticks (4)")


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


## One arena under `impl` against its pair of arrays in the gate file (`prefix` "" for the perf
## arena at `path`, BASES_PREFIX for the base arena): the run took the implementation asked for,
## took the parts of the state at every golden tick, and ended on the golden hashes; and the lines a
## failure would print are the lines of the file when it does.
func _assert_ends_on_the_golden_hashes(impl: int, path: String, prefix: String) -> void:
	var gate: PerfGateDef = _gate()
	var played: Played = _play(impl, path, _ticks_of(gate, prefix))
	assert_int(played.native_phases).is_equal(
		SimImpls.expected_mask() if impl == SimImpls.Impl.NATIVE else 0
	)
	# A failure names the parts of the state at its tick, so the run took them at every golden tick.
	var taken: Array[int] = []
	taken.assign(played.parts.keys())
	assert_array(taken).is_equal(Array(_ticks_of(gate, prefix)))
	for tick: int in played.parts:
		assert_int(played.parts[tick].size()).is_equal(World.hash_section_names().size())
	var problem: String = _first_difference(gate, played, prefix)
	var label: String = "native" if impl == SimImpls.Impl.NATIVE else "gdscript"
	assert_str(problem).override_failure_message("%s: %s" % [label, problem]).is_empty()
	# The lines that a failure would print are the lines of the file when the run matches it (no
	# second failure, and not the whole file in the message, when it does not).
	if problem.is_empty():
		assert_str(FileAccess.get_file_as_string(GATE_PATH)).contains(_repin_text(played, prefix))


## The golden ticks and the golden hashes of the gate for `prefix` ("" or BASES_PREFIX).
func _ticks_of(gate: PerfGateDef, prefix: String) -> PackedInt32Array:
	var ticks: PackedInt32Array = gate.get(prefix + "golden_ticks")
	return ticks


func _hexes_of(gate: PerfGateDef, prefix: String) -> PackedStringArray:
	var hexes: PackedStringArray = gate.get(prefix + "golden_hex")
	return hexes


## The seed-42 scenario at `path` for TICKS ticks through MatchLoop, nothing else: no queued
## command, no probe. `impl` is a SimImpls.Impl; the parts of the state are taken at `golden_ticks`.
func _play(impl: int, path: String, golden_ticks: PackedInt32Array) -> Played:
	var scenario: ScenarioDef = load(path) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, path, SEED, world)
	assert_array(SimImpls.use(world, impl)).is_empty()
	for phase: int in SimImpls.EXPECTED_PHASES:
		assert_bool(SimImpls.is_native(world, phase)).is_equal(impl == SimImpls.Impl.NATIVE)
	var played: Played = Played.new()
	var queued: Array[Command] = []
	for _tick: int in TICKS:
		loop.step(world, queued)
		if golden_ticks.has(world.tick):
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
## hash differs (its tick, both hashes and the parts of the state at that tick), then the final;
## the problem is followed by the lines that would pin the run (_repin_text).
func _first_difference(gate: PerfGateDef, played: Played, prefix: String = "") -> String:
	var problem: String = _gate_problem(gate, prefix)
	if problem.is_empty():
		problem = _checkpoint_problem(gate, played, prefix)
	if problem.is_empty():
		problem = _final_problem(gate, played, prefix)
	if problem.is_empty():
		return ""
	return (
		"%s\nlines of %s that would pin this run:\n%s"
		% [problem, GATE_PATH, _repin_text(played, prefix)]
	)


## What is wrong with the gate's arrays alone: nothing in them, or unequal sizes.
func _gate_problem(gate: PerfGateDef, prefix: String) -> String:
	var ticks: int = _ticks_of(gate, prefix).size()
	var hexes: int = _hexes_of(gate, prefix).size()
	if ticks == 0 or hexes == 0:
		return "the gate file holds no golden hashes"
	if ticks != hexes:
		return (
			"%sgolden_ticks (%d) and %sgolden_hex (%d) do not pair up"
			% [prefix, ticks, prefix, hexes]
		)
	return ""


## The first golden tick that the run has no checkpoint at, or whose hash differs.
func _checkpoint_problem(gate: PerfGateDef, played: Played, prefix: String) -> String:
	var ticks: PackedInt32Array = _ticks_of(gate, prefix)
	var hexes: PackedStringArray = _hexes_of(gate, prefix)
	for index: int in ticks.size():
		var tick: int = ticks[index]
		var at: int = played.checkpoint_ticks.find(tick)
		if at < 0:
			return "golden tick %d: the run has no checkpoint at tick %d" % [tick, tick]
		var got: String = World.hash_hex(played.checkpoint_hashes[at])
		if got != hexes[index]:
			return (
				"%s golden %s, got %s; parts at that tick: %s"
				% [
					_differing(tick),
					hexes[index],
					got,
					_parts_text(played.parts.get(tick, PackedInt64Array()))
				]
			)
	return ""


## The last golden tick is the run's last tick, and the hash after it is the last golden hash.
func _final_problem(gate: PerfGateDef, played: Played, prefix: String) -> String:
	var ticks: PackedInt32Array = _ticks_of(gate, prefix)
	var hexes: PackedStringArray = _hexes_of(gate, prefix)
	var final_hex: String = World.hash_hex(played.final_hash)
	if ticks[-1] != played.final_tick:
		return (
			"the last golden tick %d is not the run's last tick %d (final hash %s)"
			% [ticks[-1], played.final_tick, final_hex]
		)
	if final_hex != hexes[-1]:
		return (
			"final hash at tick %d: golden %s, got %s" % [played.final_tick, hexes[-1], final_hex]
		)
	return ""


## How the message of a differing checkpoint begins.
func _differing(tick: int) -> String:
	return "first differing checkpoint, tick %d:" % tick


## The two lines of the gate file that would pin `played`: its checkpoints every GOLDEN_STEP ticks
## up to its last tick, in the form of the file (a missing checkpoint is left out); the fields are
## the base arena's when `prefix` is BASES_PREFIX.
func _repin_text(played: Played, prefix: String = "") -> String:
	var ticks: PackedStringArray = PackedStringArray()
	var hexes: PackedStringArray = PackedStringArray()
	for tick: int in range(GOLDEN_STEP, played.final_tick + 1, GOLDEN_STEP):
		var at: int = played.checkpoint_ticks.find(tick)
		if at >= 0:
			ticks.append(str(tick))
			hexes.append('"%s"' % World.hash_hex(played.checkpoint_hashes[at]))
	return (
		"%s%s%s)\n%s%s%s)"
		% [prefix, TICKS_LINE, ", ".join(ticks), prefix, HEX_LINE, ", ".join(hexes)]
	)


## The parts of a state as `name=hex` pairs under World.hash_section_names(), in that order.
func _parts_text(parts: PackedInt64Array) -> String:
	var names: PackedStringArray = World.hash_section_names()
	var pairs: PackedStringArray = PackedStringArray()
	for index: int in mini(names.size(), parts.size()):
		pairs.append("%s=%s" % [names[index], World.hash_hex(parts[index])])
	return " ".join(pairs) if not pairs.is_empty() else "(not taken)"


## A run that no match produced: a checkpoint at each of HAND_TICKS with the HAND_HASHES, the final
## tick 600 with the last hash and, at each checkpoint, parts that name their tick (the tick plus
## the index of the section).
func _hand_played(section_count: int) -> Played:
	var played: Played = Played.new()
	played.checkpoint_ticks = PackedInt32Array(HAND_TICKS)
	played.checkpoint_hashes = PackedInt64Array(HAND_HASHES)
	played.final_tick = HAND_TICKS[-1]
	played.final_hash = HAND_HASHES[-1]
	for tick: int in HAND_TICKS:
		var parts: PackedInt64Array = PackedInt64Array()
		for index: int in section_count:
			parts.append(tick + index)
		played.parts[tick] = parts
	return played


## A gate with the given golden ticks and hashes (the hashes as ints, written in the file's form),
## in the perf arena's fields or, with BASES_PREFIX, the base arena's.
func _hand_gate(ticks: Array[int], hashes: Array[int], prefix: String = "") -> PerfGateDef:
	var gate: PerfGateDef = PerfGateDef.new()
	gate.set(prefix + "golden_ticks", PackedInt32Array(ticks))
	var hexes: PackedStringArray = PackedStringArray()
	for hash_value: int in hashes:
		hexes.append(World.hash_hex(hash_value))
	gate.set(prefix + "golden_hex", hexes)
	return gate
