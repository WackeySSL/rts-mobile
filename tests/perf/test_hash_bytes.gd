extends GdUnitTestSuite
## The bytes the state hash feeds per checkpoint (plan P65q, ADR 0016): the seed-42 perf arena for
## 900 ticks through MatchLoop, the run that the golden hashes pin, GDScript phases and no clock.
## At each of its 60 checkpoints the suite rebuilds the byte stream of World.state_hash() from the
## shape lists (tests/perf/support/hash_bytes.gd), counts it and feeds it to its own SHA-256; the
## count is the real one only if that digest equals state_hash(), which a case checks at every
## checkpoint (ticks 150 and 900 and the ones with shells in flight among them). It prints the
## third watch line, `WATCH sim hash_bytes checkpoints=60 min_bytes=... max_bytes=...`, beside the
## two of test_sim_perf.gd, with no bound: ADR 0016 keeps it so that the growth of the hashed state
## (Phase 3) and P65's drop show in every CI log. It starts with `WATCH`, not `PERF `, so the job
## summary of P51 (which selects `^PERF sim` lines) does not change.

const HashBytes: GDScript = preload("res://tests/perf/support/hash_bytes.gd")
const PerfReport: GDScript = preload("res://tests/perf/support/perf_report.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const GATE_PATH: String = "res://data/dev/perf_gate.tres"
const TICKS: int = 900
const SEED: int = 42
## The value written to the columns of a shell in a World made by hand (proj_free excepted).
const SHELL_VALUE: int = 10
## The blocks the `ghosts` section feeds: the count of each player and the live records.
const GHOST_BLOCKS: int = 2

## For each checkpoint, in order: its tick, the bytes fed, the digest of the rebuilt stream,
## World.state_hash() taken at that point and the projectile slots in use.
var _ticks: PackedInt32Array = PackedInt32Array()
var _counts: PackedInt32Array = PackedInt32Array()
var _rebuilt: PackedInt64Array = PackedInt64Array()
var _hashes: PackedInt64Array = PackedInt64Array()
var _live: PackedInt32Array = PackedInt32Array()
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
		_live.append(PerfReport.live_projectiles(_world))
	_recorded = loop.replay.checkpoint_hashes
	_line = PerfReport.sub_line(HashBytes.HEAD, HashBytes.values(_counts), false)
	print(_line)


## The rebuilt stream hashes to state_hash() at all 60 checkpoints, ticks 15 to 900, and to the
## hash MatchLoop recorded there: the count is of the bytes the digest really takes. Some of the
## checkpoints have shells in flight, so the live-slot block is counted with content too.
func test_the_rebuilt_stream_hashes_to_state_hash_at_every_checkpoint() -> void:
	var ticks: Array[int] = []
	for tick: int in range(Replay.CHECKPOINT_PERIOD, TICKS + 1, Replay.CHECKPOINT_PERIOD):
		ticks.append(tick)
	assert_int(ticks.size()).is_equal(60)
	assert_array(Array(_ticks)).is_equal(ticks)
	assert_int(_recorded.size()).is_equal(_ticks.size())
	var wrong: Array[int] = []
	var with_shells: int = 0
	for at: int in _ticks.size():
		if _rebuilt[at] != _hashes[at] or _recorded[at] != _hashes[at]:
			wrong.append(_ticks[at])
		elif _live[at] > 0:
			with_shells += 1
	assert_array(wrong).is_empty()
	assert_array(Array(_ticks)).contains([150, 900])
	assert_int(with_shells).is_greater(0)


## The run is the one that data/dev/perf_gate.tres pins: its golden ticks are checkpoints here and
## carry the golden hashes (a re-pin moves the file and this run together).
func test_the_checkpoints_carry_the_golden_hashes_of_the_gate_file() -> void:
	var gate: PerfGateDef = (
		ResourceLoader.load(GATE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PerfGateDef
	)
	assert_int(gate.golden_ticks.size()).is_greater(0)
	assert_int(gate.golden_hex.size()).is_equal(gate.golden_ticks.size())
	for index: int in gate.golden_ticks.size():
		var at: int = _ticks.find(gate.golden_ticks[index])
		assert_int(at).override_failure_message("no checkpoint at the golden tick").is_greater(-1)
		assert_str(World.hash_hex(_hashes[at])).is_equal(gate.golden_hex[index])


## The count is the blocks of the shape lists, each with its 16-byte header: after the last tick,
## the walk over the stream finds the header block, the map digest, one block per row column, the
## live slots and the used free stack, one block per FogGrid.HASHED array, one per PLAYER_ARRAYS
## and ORE_ARRAYS array, and the counts and the live records of the ghosts, in section order, each
## with the size that its array has, and ends exactly at the end of the stream.
func test_the_count_is_the_blocks_of_the_shape_lists_with_a_header_each() -> void:
	var bytes: PackedByteArray = HashBytes.stream(_world)
	var names: PackedStringArray = World.hash_section_names()
	var rows_end: int = 2 + World.ROW_ARRAYS.size()
	var expected: Array[Vector2i] = [
		Vector2i(0, (1 + World.HASHED_SCALARS.size() + _world.rng.state().size()) * 8),
		Vector2i(1, 8),
	]
	for index: int in World.ROW_ARRAYS.size():
		var column: Variant = _world.get(World.ROW_ARRAYS[index])
		expected.append(Vector2i(2 + index, HashBytes.bytes_of(column).size()))
	# A live slot is its index and the nine columns other than proj_free: ten ints.
	var slot_bytes: int = World.PROJECTILE_ARRAYS.size() * 4
	expected.append(Vector2i(rows_end, PerfReport.live_projectiles(_world) * slot_bytes))
	expected.append(Vector2i(rows_end, _world.proj_free_top * 4))
	for array_name: StringName in FogGrid.HASHED:
		var grid: Variant = _world.fog.get(array_name)
		expected.append(Vector2i(names.find("fog"), HashBytes.bytes_of(grid).size()))
	for array_name: StringName in World.PLAYER_ARRAYS:
		var column: Variant = _world.get(array_name)
		expected.append(Vector2i(names.find("players"), HashBytes.bytes_of(column).size()))
	for array_name: StringName in World.ORE_ARRAYS:
		var column: Variant = _world.get(array_name)
		expected.append(Vector2i(names.find("ore"), HashBytes.bytes_of(column).size()))
	# The arena has no last-seen record: the counts of its players, then no live record.
	expected.append(Vector2i(names.find("ghosts"), (_world.player_count + 1) * 4))
	expected.append(Vector2i(names.find("ghosts"), 0))
	assert_array(_blocks(bytes)).is_equal(expected)
	var payload: int = 0
	for block: Vector2i in expected:
		payload += block.y
	assert_int(bytes.size()).is_equal(payload + HashBytes.HEADER_BYTES * expected.size())
	assert_int(expected.size()).is_equal(_block_count())


## On Worlds made by hand the rebuilt stream still hashes to state_hash(): at tick 0, with a shell
## in the first and the last slot (each adds its ten ints and takes one entry off the free stack,
## 40 - 4 bytes), and not prepared, where the fog and the projectile blocks are empty: only their
## 16-byte headers are fed.
func test_the_count_follows_shells_and_an_unprepared_world() -> void:
	var world: World = World.from_scenario(load(ARENA_PATH) as ScenarioDef)
	var bare: PackedByteArray = HashBytes.stream(world)
	assert_int(HashBytes.digest(bare)).is_equal(world.state_hash())
	var slots: int = world.proj_id.size()
	assert_int(slots).is_greater(1)
	var added: int = 0
	for slot: int in [0, slots - 1]:
		for column_name: StringName in World.PROJECTILE_ARRAYS:
			if column_name != &"proj_free":
				var column: PackedInt32Array = world.get(column_name)
				column[slot] = SHELL_VALUE + slot
		world.proj_free_top -= 1
		added += 36
		var bytes: PackedByteArray = HashBytes.stream(world)
		assert_int(bytes.size()).is_equal(bare.size() + added)
		assert_int(HashBytes.digest(bytes)).is_equal(world.state_hash())
	var unprepared: World = World.new()
	unprepared.map_w = 5000
	unprepared.map_h = 4000
	unprepared.add_unit(1, 0, 1500, 500)
	unprepared.add_unit(2, 0, 3500, 2500)
	var empty: PackedByteArray = HashBytes.stream(unprepared)
	assert_int(HashBytes.digest(empty)).is_equal(unprepared.state_hash())
	var blocks: Array[Vector2i] = _blocks(empty)
	assert_int(blocks.size()).is_equal(_block_count())
	var fog_tag: int = World.hash_section_names().find("fog")
	var fog_blocks: Array[Vector2i] = []
	fog_blocks.resize(FogGrid.HASHED.size())
	fog_blocks.fill(Vector2i(fog_tag, 0))
	var fog_at: int = 2 + World.ROW_ARRAYS.size() + 2  # After the header, the map, rows, projectiles.
	assert_array(blocks.slice(fog_at, fog_at + FogGrid.HASHED.size())).is_equal(fog_blocks)


## The watch line: the head, then the checkpoints and the smallest and the largest count, as
## integers and in that order; the values of none, one and three counts; and the line the suite
## printed holds the 60 checkpoints and the extremes of its own counts. It is no `PERF ` line.
func test_the_watch_line_holds_the_checkpoints_and_the_smallest_and_largest_count() -> void:
	assert_str(HashBytes.HEAD).is_equal("WATCH sim hash_bytes")
	assert_bool(HashBytes.HEAD.begins_with("PERF ")).is_false()
	var three: PackedInt32Array = PackedInt32Array([55544, 49332, 50001])
	assert_str(PerfReport.sub_line(HashBytes.HEAD, HashBytes.values(three), false)).is_equal(
		"WATCH sim hash_bytes checkpoints=3 min_bytes=49332 max_bytes=55544"
	)
	assert_dict(HashBytes.values(PackedInt32Array([7]))).is_equal(
		{"checkpoints": 1, "min_bytes": 7, "max_bytes": 7}
	)
	assert_dict(HashBytes.values(PackedInt32Array())).is_equal(
		{"checkpoints": 0, "min_bytes": 0, "max_bytes": 0}
	)
	var low: int = _counts[0]
	var high: int = _counts[0]
	for count: int in _counts:
		low = mini(low, count)
		high = maxi(high, count)
	assert_int(low).is_greater(0)
	assert_str(_line).is_equal(
		"WATCH sim hash_bytes checkpoints=60 min_bytes=%d max_bytes=%d" % [low, high]
	)


## The blocks of a stream, section by section: the header, the map, one per row column, the live
## slots and the free stack, FogGrid.HASHED, PLAYER_ARRAYS, ORE_ARRAYS and the ghosts' two.
func _block_count() -> int:
	var count: int = 1 + 1 + World.ROW_ARRAYS.size() + 2 + FogGrid.HASHED.size()
	return count + World.PLAYER_ARRAYS.size() + World.ORE_ARRAYS.size() + GHOST_BLOCKS


## The (tag, byte count) of every block of `bytes`, read from the headers. A stream that stops in
## the middle of a header or a block adds one entry with a size of -1.
func _blocks(bytes: PackedByteArray) -> Array[Vector2i]:
	var blocks: Array[Vector2i] = []
	var at: int = 0
	while at < bytes.size():
		if at + HashBytes.HEADER_BYTES > bytes.size():
			blocks.append(Vector2i(-1, -1))
			break
		var tag: int = bytes.decode_s64(at)
		var size: int = bytes.decode_s64(at + 8)
		at += HashBytes.HEADER_BYTES + size
		blocks.append(Vector2i(tag, size if at <= bytes.size() else -1))
	return blocks
