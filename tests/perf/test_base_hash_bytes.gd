extends GdUnitTestSuite
## The bytes the state hash feeds per checkpoint on the base arena (plan P93, ADR 0021 section 2,
## ADR 0016): the seed-42 run of data/scenarios/perf_bases.tres for 900 ticks through MatchLoop,
## GDScript phases and no clock, counted the way test_hash_bytes.gd counts the perf arena. At each
## of its 60 checkpoints the suite rebuilds the byte stream of World.state_hash() from the shape
## lists (tests/perf/support/hash_bytes.gd), counts it and feeds it to its own SHA-256; the count is
## the real one only if that digest equals state_hash(), which a case checks at every checkpoint.
## It prints `WATCH bases hash_bytes checkpoints=60 min_bytes=... max_bytes=...`, with no bound: the
## base arena is the first run in which the `players` and `ore` sections hold real content (the
## perf arena has no producer and no ore), so its count shows what Phase 3 adds to every
## checkpoint. The line starts with `WATCH`, not `PERF `, so the job summary does not select it.

const HashBytes: GDScript = preload("res://tests/perf/support/hash_bytes.gd")
const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_bases.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const TICKS: int = 900
const SEED: int = 42

## For each checkpoint, in order: its tick, the bytes fed, the digest of the rebuilt stream and
## World.state_hash() taken at that point.
var _ticks: PackedInt32Array = PackedInt32Array()
var _counts: PackedInt32Array = PackedInt32Array()
var _rebuilt: PackedInt64Array = PackedInt64Array()
var _hashes: PackedInt64Array = PackedInt64Array()
## The hashes that MatchLoop recorded, the World after the last tick and the line printed.
var _recorded: PackedInt64Array = PackedInt64Array()
var _world: World
var _line: String = ""


func before() -> void:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	_world = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(scenario, ARENA_PATH, SEED, _world)
	var queued: Array[Command] = []
	for _tick: int in TICKS:
		loop.step(_world, queued)
		if _world.tick % Replay.CHECKPOINT_PERIOD != 0:
			continue
		var bytes: PackedByteArray = HashBytes.stream(_world)
		_ticks.append(_world.tick)
		_counts.append(bytes.size())
		_rebuilt.append(HashBytes.digest(bytes))
		_hashes.append(_world.state_hash())
	_recorded = loop.replay.checkpoint_hashes
	_line = PerfReport.sub_line(HashBytes.BASES_HEAD, HashBytes.values(_counts), false)
	print(_line)


## The rebuilt stream hashes to state_hash() at all 60 checkpoints, ticks 15 to 900, and to the hash
## MatchLoop recorded there: the count is of the bytes the digest really takes, with the producers'
## and the harvesters' state in the `players` and `ore` sections.
func test_the_rebuilt_stream_hashes_to_state_hash_at_every_checkpoint() -> void:
	var ticks: Array[int] = []
	for tick: int in range(Replay.CHECKPOINT_PERIOD, TICKS + 1, Replay.CHECKPOINT_PERIOD):
		ticks.append(tick)
	assert_int(ticks.size()).is_equal(60)
	assert_array(Array(_ticks)).is_equal(ticks)
	assert_int(_recorded.size()).is_equal(_ticks.size())
	var wrong: Array[int] = []
	for at: int in _ticks.size():
		if _rebuilt[at] != _hashes[at] or _recorded[at] != _hashes[at]:
			wrong.append(_ticks[at])
	assert_array(wrong).is_empty()
	assert_array(Array(_ticks)).contains([150, 900])


## The run is the one that data/dev/perf_gate.tres pins for the base arena: its golden ticks are
## checkpoints here and carry the golden hashes (a re-pin moves the file and this run together).
func test_the_checkpoints_carry_the_base_arena_golden_hashes_of_the_gate_file() -> void:
	var gate: PerfGateDef = (
		ResourceLoader.load(GATE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PerfGateDef
	)
	assert_int(gate.bases_golden_ticks.size()).is_greater(0)
	assert_int(gate.bases_golden_hex.size()).is_equal(gate.bases_golden_ticks.size())
	for index: int in gate.bases_golden_ticks.size():
		var at: int = _ticks.find(gate.bases_golden_ticks[index])
		assert_int(at).override_failure_message("no checkpoint at the golden tick").is_greater(-1)
		assert_str(World.hash_hex(_hashes[at])).is_equal(gate.bases_golden_hex[index])


## The sections of the stream come in the order of World.hash_section_names(), every block with
## its 16-byte header, and the walk over the headers ends exactly at the end of the stream. The
## arena fills what the perf arena leaves empty: each of the `players` and `ore` sections holds one
## block per array of its list, and the ore blocks carry bytes (the map has ore fields).
func test_the_stream_holds_the_blocks_of_every_section_and_the_ore_has_content() -> void:
	var bytes: PackedByteArray = HashBytes.stream(_world)
	var names: PackedStringArray = World.hash_section_names()
	var per_section: Dictionary[int, int] = {}
	var ore_bytes: int = 0
	var at: int = 0
	var last_tag: int = -1
	while at + HashBytes.HEADER_BYTES <= bytes.size():
		var tag: int = bytes.decode_s64(at)
		var size: int = bytes.decode_s64(at + 8)
		assert_int(tag).is_greater_equal(last_tag)
		last_tag = tag
		per_section[tag] = per_section.get(tag, 0) + 1
		if tag == names.find("ore"):
			ore_bytes += size
		at += HashBytes.HEADER_BYTES + size
	assert_int(at).is_equal(bytes.size())
	assert_int(per_section[names.find("players")]).is_equal(World.PLAYER_ARRAYS.size())
	assert_int(per_section[names.find("ore")]).is_equal(World.ORE_ARRAYS.size())
	assert_int(per_section[names.find("fog")]).is_equal(FogGrid.HASHED.size())
	assert_int(ore_bytes).is_greater(0)


## The watch line: the head `WATCH bases hash_bytes`, then the checkpoints and the smallest and the
## largest count, as integers and in that order; the line the suite printed holds the 60
## checkpoints and the extremes of its own counts, and it is no `PERF ` line.
func test_the_watch_line_holds_the_checkpoints_and_the_smallest_and_largest_count() -> void:
	assert_str(HashBytes.BASES_HEAD).is_equal("WATCH bases hash_bytes")
	assert_bool(HashBytes.BASES_HEAD.begins_with("PERF ")).is_false()
	assert_str(HashBytes.BASES_HEAD).is_not_equal(HashBytes.HEAD)
	var low: int = _counts[0]
	var high: int = _counts[0]
	for count: int in _counts:
		low = mini(low, count)
		high = maxi(high, count)
	assert_int(low).is_greater(0)
	assert_str(_line).is_equal(
		"WATCH bases hash_bytes checkpoints=60 min_bytes=%d max_bytes=%d" % [low, high]
	)
