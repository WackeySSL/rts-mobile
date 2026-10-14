extends GdUnitTestSuite
## Part 1 of the replay tests (P35a, ADR 0007 sections 5 and 9): the command round trip, the
## Replay log and its bytes. The layout, the limits and the int32 bound of Command.encode and
## decode are in test_command. Replay.play and the MatchLoop cases come with P35b. The numbers
## are literals, so no encoder can agree with its own decoder by being wrong. A push_error or an
## engine ERROR line would fail verify, which scans the log: every malformed buffer below must be
## refused before the engine tries to decode it.

const Samples: GDScript = preload("res://tests/sim/support/command_samples.gd")
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
## The first words of a Variant on the wire (core/io/marshalls.cpp, Godot 4.7.2): the type, and
## for an int bit 16 for 64 bits.
const DICTIONARY_WORD: int = 27
const STRING_WORD: int = 4
const INT_WORD: int = 2
const INT64_WORD: int = 2 | (1 << 16)
const PACKED_INT32_WORD: int = 30
const PACKED_INT64_WORD: int = 31
const OBJECT_WORD: int = 24
const FLOAT_WORD: int = 3


func test_the_contract_numbers_and_begin() -> void:
	assert_array([Replay.FORMAT, Replay.CHECKPOINT_PERIOD]).is_equal([1, 15])
	assert_array(Replay.KINDS.keys()).is_equal(_keys())
	var kinds: Array[int] = [TYPE_INT, TYPE_STRING, TYPE_INT, TYPE_INT]
	kinds.append_array([TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT32_ARRAY])
	kinds.append_array([TYPE_PACKED_INT64_ARRAY, TYPE_INT, TYPE_INT])
	assert_array(Replay.KINDS.values()).is_equal(kinds)
	var replay: Replay = Replay.begin(SCENARIO_PATH, 42, -9)
	assert_str(replay.scenario_path).is_equal(SCENARIO_PATH)
	assert_array([replay.seed, replay.defs_hash]).is_equal([42, -9])
	assert_array([replay.final_tick, replay.final_hash]).is_equal([0, 0])
	assert_array(replay.commands).is_empty()
	assert_array(replay.checkpoint_ticks).is_empty()
	assert_array(replay.checkpoint_hashes).is_empty()
	assert_int(typeof(replay.checkpoint_hashes)).is_equal(TYPE_PACKED_INT64_ARRAY)
	# A seed beyond int32 and a hash with the sign bit set are kept as they are.
	var big: Replay = Replay.begin("x", 5_000_000_000, -9223372036854775807 - 1)
	assert_array([big.seed, big.defs_hash]).is_equal([5_000_000_000, -9223372036854775807 - 1])


func test_every_type_with_ids_and_payload_round_trips() -> void:
	# Phase 2's five types, two reserved ones and a negative one: decode does not judge the type.
	var types: Array[int] = [0, 1, 2, 3, 4, 12, 25, -3]
	var data: PackedInt32Array = PackedInt32Array()
	for k: int in types.size():
		Samples.full(types[k], 100 + k, 7 * k).encode(data)
	var at: int = 0
	for k: int in types.size():
		var out: Command = Command.new()
		at = Command.decode(data, at, out)
		assert_array(Samples.fields(out)).is_equal(
			Samples.fields(Samples.full(types[k], 100 + k, 7 * k))
		)
	assert_int(at).is_equal(data.size())
	# The factories' commands, with no payload or no ids at all.
	var plain: Array[Command] = [
		Command.attack_move(1, PackedInt32Array([4]), 800, 900),
		Command.move(2, PackedInt32Array([4, 5]), 0, 2147483647),
		Command.attack(1, PackedInt32Array([8]), 77),
		Command.stop(2, PackedInt32Array()),
		Command.new(),
	]
	for command: Command in plain:
		var one: PackedInt32Array = PackedInt32Array()
		command.encode(one)
		var out: Command = Samples.full(1, 1, 1)
		assert_int(Command.decode(one, 0, out)).is_equal(one.size())
		assert_array(Samples.fields(out)).is_equal(Samples.fields(command))


func test_a_count_past_the_end_or_a_negative_count_is_malformed() -> void:
	# Each starts with tick 1, player 0, sequence 0, type 3 and the target 0, 0, 0.
	var head: Array = [1, 0, 0, 3, 0, 0, 0]
	# A unit count of 3 with only 2 ids left.
	assert_int(Samples.decode(head + [3, 5, 9])).is_equal(-1)
	# 3 ids and no payload count after them.
	assert_int(Samples.decode(head + [3, 5, 9, 40])).is_equal(-1)
	# A payload count of 2 with 1 payload int left, and 1 with 1 left, which is complete.
	assert_int(Samples.decode(head + [0, 2, 7])).is_equal(-1)
	assert_int(Samples.decode(head + [0, 1, 7])).is_equal(10)
	# Negative counts, with enough ints after them for a count of the same size.
	for bad: int in [-1, -2, -2147483648]:
		assert_int(Samples.decode(head + [bad, 5, 9, 40, 0, 0])).is_equal(-1)
		assert_int(Samples.decode(head + [0, bad, 7, 8, 9, 0])).is_equal(-1)
	# A count of the whole int32 range is past the end too.
	assert_int(Samples.decode(head + [2147483647, 5, 9, 40, 0, 0])).is_equal(-1)
	assert_int(Samples.decode(head + [0, 2147483647, 7, 8, 9, 0])).is_equal(-1)


func test_record_appends_each_command_as_encoded_in_order() -> void:
	var replay: Replay = Replay.begin(SCENARIO_PATH, 1, 2)
	var first: Command = Samples.full(Command.Type.MOVE, 3, 1)
	var second: Command = Command.stop(2, PackedInt32Array([7]))
	second.tick = 3
	second.sequence = 2
	replay.record(first)
	replay.record(second)
	var expected: PackedInt32Array = PackedInt32Array()
	first.encode(expected)
	second.encode(expected)
	assert_array(replay.commands).is_equal(expected)
	var out: Command = Command.new()
	var at: int = Command.decode(replay.commands, 0, out)
	assert_array(Samples.fields(out)).is_equal(Samples.fields(first))
	assert_int(Command.decode(replay.commands, at, out)).is_equal(expected.size())
	assert_array(Samples.fields(out)).is_equal(Samples.fields(second))
	# The log holds a copy: a later change of the command does not reach it.
	first.unit_ids[0] = 1
	assert_array(replay.commands.slice(8, 11)).is_equal([5, 9, 40])


func test_add_checkpoint_and_finish() -> void:
	var replay: Replay = Replay.begin(SCENARIO_PATH, 1, 2)
	replay.add_checkpoint(15, 0x7FFFFFFFFFFFFFFF)
	replay.add_checkpoint(30, -1)
	replay.add_checkpoint(45, 1 << 40)
	assert_array(replay.checkpoint_ticks).is_equal([15, 30, 45])
	assert_array(replay.checkpoint_hashes).is_equal([0x7FFFFFFFFFFFFFFF, -1, 1 << 40])
	# A tick is stored in an int32 array: one beyond it saturates.
	replay.add_checkpoint(1 << 40, 0)
	assert_int(replay.checkpoint_ticks[3]).is_equal(2147483647)
	# finish takes the tick and the state hash of the world as it is when it is called.
	var world: World = _world(0)
	var tick_0_hash: int = world.state_hash()
	var none: Array[Command] = []
	Sim.step(world, none)
	Sim.step(world, none)
	replay.finish(world)
	assert_array([replay.final_tick, replay.final_hash]).is_equal([2, world.state_hash()])
	assert_bool(replay.final_hash != tick_0_hash).is_true()
	Sim.step(world, none)
	assert_int(replay.final_tick).is_equal(2)
	replay.finish(world)
	assert_array([replay.final_tick, replay.final_hash]).is_equal([3, world.state_hash()])


func test_to_bytes_writes_the_documented_dictionary_and_the_same_bytes_every_time() -> void:
	var replay: Replay = _replay()
	var data: Dictionary = bytes_to_var(replay.to_bytes())
	assert_array(data.keys()).is_equal(_keys())
	assert_int(data["format"]).is_equal(1)
	assert_str(data["scenario"]).is_equal(SCENARIO_PATH)
	assert_array([data["seed"], data["defs_hash"]]).is_equal([replay.seed, replay.defs_hash])
	assert_array(data["commands"]).is_equal(replay.commands)
	assert_array(data["checkpoint_ticks"]).is_equal([15, 30, 45])
	assert_array(data["checkpoint_hashes"]).is_equal([0x7FFFFFFFFFFFFFFF, -1, 1 << 40])
	assert_array([data["final_tick"], data["final_hash"]]).is_equal(
		[replay.final_tick, replay.final_hash]
	)
	for key: String in data:
		assert_int(typeof(data[key])).override_failure_message(key).is_equal(Replay.KINDS[key])
	# Equal replays, and the same replay twice, give equal bytes; another log gives other bytes.
	var bytes: PackedByteArray = replay.to_bytes()
	assert_array(replay.to_bytes()).is_equal(bytes)
	assert_array(_replay().to_bytes()).is_equal(bytes)
	replay.record(Command.new())
	assert_bool(replay.to_bytes() == bytes).is_false()


func test_to_bytes_and_from_bytes_round_trip_every_field() -> void:
	var replay: Replay = _replay()
	var back: Replay = Replay.from_bytes(replay.to_bytes())
	assert_object(back).is_not_null()
	assert_str(back.scenario_path).is_equal(SCENARIO_PATH)
	assert_array([back.seed, back.defs_hash]).is_equal([5_000_000_000, -7_000_000_000_000])
	assert_array(back.commands).is_equal(replay.commands)
	assert_int(back.commands.size()).is_equal(2 * 14)
	assert_array(back.checkpoint_ticks).is_equal([15, 30, 45])
	assert_array(back.checkpoint_hashes).is_equal([0x7FFFFFFFFFFFFFFF, -1, 1 << 40])
	assert_array([back.final_tick, back.final_hash]).is_equal([2, replay.final_hash])
	assert_array(back.to_bytes()).is_equal(replay.to_bytes())
	# A replay that holds nothing yet keeps its array kinds.
	var empty: Replay = Replay.from_bytes(Replay.begin("", 0, 0).to_bytes())
	assert_object(empty).is_not_null()
	assert_array(empty.commands).is_empty()
	assert_array(empty.checkpoint_ticks).is_empty()
	assert_int(typeof(empty.checkpoint_ticks)).is_equal(TYPE_PACKED_INT32_ARRAY)
	assert_int(typeof(empty.checkpoint_hashes)).is_equal(TYPE_PACKED_INT64_ARRAY)


func test_from_bytes_gives_null_for_a_wrong_format_or_a_missing_key() -> void:
	assert_object(_with("format", 1)).is_not_null()
	for format: Variant in [0, 2, -1, 1 << 40, 1.0, "1", true, PackedInt32Array([1])]:
		assert_object(_with("format", format)).override_failure_message(str(format)).is_null()
	for key: String in _keys():
		var data: Dictionary = bytes_to_var(_replay().to_bytes())
		assert_bool(data.erase(key)).is_true()
		(
			assert_object(Replay.from_bytes(var_to_bytes(data)))
			. override_failure_message("without %s" % key)
			. is_null()
		)
	assert_object(Replay.from_bytes(var_to_bytes({}))).is_null()


func test_from_bytes_gives_null_for_a_value_of_the_wrong_type_or_array_kind() -> void:
	var wrong: Dictionary = {
		"scenario": [5, 1.5, &"res://x", PackedByteArray([65, 66]), PackedInt32Array()],
		"seed": ["7", 7.0, PackedInt64Array([7]), null],
		"defs_hash": ["7", 7.5, PackedInt32Array([7])],
		"commands": [PackedInt64Array([1, 2]), PackedByteArray([1, 2]), [1, 2], 5, "x", null],
		"checkpoint_ticks":
		[PackedInt64Array([15, 30, 45]), PackedFloat32Array([15.0, 30.0, 45.0])],
		"checkpoint_hashes":
		[PackedInt32Array([15, 30, 45]), [1, 2, 3], PackedByteArray([1, 2, 3])],
		"final_tick": ["2", 2.0, PackedInt32Array([2])],
		"final_hash": ["2", 2.0, PackedInt64Array([2]), {}],
	}
	for key: String in wrong:
		for value: Variant in wrong[key]:
			(
				assert_object(_with(key, value))
				. override_failure_message("%s = %s" % [key, str(value)])
				. is_null()
			)
	# The right kinds with checkpoint arrays of unequal sizes are no replay either.
	assert_object(_with("checkpoint_ticks", PackedInt32Array([15, 30, 45]))).is_not_null()
	assert_object(_with("checkpoint_ticks", PackedInt32Array([15, 30]))).is_null()
	assert_object(_with("checkpoint_ticks", PackedInt32Array([15, 30, 45, 60]))).is_null()
	assert_object(_with("checkpoint_hashes", PackedInt64Array([1, 2]))).is_null()


func test_from_bytes_gives_null_for_bytes_that_are_not_a_replay_or_cut_short() -> void:
	var values: Array = [null, 1, "replay", PackedInt32Array([1, 2]), [1, 2], {}, {"format": 1}]
	for value: Variant in values:
		(
			assert_object(Replay.from_bytes(var_to_bytes(value)))
			. override_failure_message(str(value))
			. is_null()
		)
	assert_object(Replay.from_bytes(PackedByteArray())).is_null()
	# Every prefix of a replay is refused, and so is a replay with more bytes after it.
	var bytes: PackedByteArray = _replay().to_bytes()
	assert_object(Replay.from_bytes(bytes)).is_not_null()
	var accepted: Array[int] = []
	for length: int in bytes.size():
		if Replay.from_bytes(bytes.slice(0, length)) != null:
			accepted.append(length)
	assert_array(accepted).is_empty()
	for extra: PackedByteArray in [PackedByteArray([0]), PackedByteArray([0, 0, 0, 0])]:
		assert_object(Replay.from_bytes(bytes + extra)).is_null()


func test_from_bytes_gives_null_for_random_bytes() -> void:
	var rng: DetRandom = DetRandom.create(7, DetRandom.STREAM_SIM)
	var accepted: int = 0
	for round_index: int in 400:
		var junk: PackedByteArray = PackedByteArray()
		for k: int in rng.next_int(120):
			junk.append(rng.next_int(256))
		# Plain, and behind a Dictionary header with a pair count of 0 to 3, which takes the walk
		# into the pairs.
		var framed: PackedByteArray = _words([DICTIONARY_WORD, rng.next_int(4)]) + junk
		for bytes: PackedByteArray in [junk, framed]:
			if Replay.from_bytes(bytes) != null:
				accepted += 1
	assert_int(accepted).is_equal(0)


## Counts and sizes that point past the buffer, and headers of kinds a replay never holds. A case
## with a wrong kind ends exactly where a value of that kind would, so only the kind check stands
## between it and the engine, which prints an ERROR for an object.
func test_from_bytes_gives_null_for_a_header_or_size_that_does_not_fit() -> void:
	var key: Array[int] = [STRING_WORD, 1, 0x6B]  # The key "k".
	var one: Array[int] = [DICTIONARY_WORD, 1]
	var cases: Array[Array] = [
		[DICTIONARY_WORD, 0xFFFFFFFF],
		[DICTIONARY_WORD, 0x80000001],
		[DICTIONARY_WORD, 1],
		[DICTIONARY_WORD, 1, STRING_WORD, 0xFFFFFFFF],
		[DICTIONARY_WORD, 1, STRING_WORD, 0xFFFFFFFD, 0],
		[DICTIONARY_WORD, 1, STRING_WORD, 2, 0x6B],
		key + [INT_WORD],
		one + key + [INT_WORD],
		one + key + [INT64_WORD, 5],
		one + key + [PACKED_INT32_WORD, 0x40000000],
		one + key + [PACKED_INT32_WORD, 0xFFFFFFFF, 0],
		one + key + [PACKED_INT64_WORD, 0x20000000, 0],
		one + key + [OBJECT_WORD, 0],
		one + key + [FLOAT_WORD, 0],
		[DICTIONARY_WORD | (5 << 16), 0],  # A typed Dictionary.
		one + key + [DICTIONARY_WORD, 0],  # A Dictionary inside.
		[DICTIONARY_WORD, 1, STRING_WORD | (1 << 16), 1, 0x6B, INT_WORD, 5],
	]
	for words: Array in cases:
		(
			assert_object(Replay.from_bytes(_words(words)))
			. override_failure_message(str(words))
			. is_null()
		)
	# Well formed, and still not a replay: an empty Dictionary and one with a single pair.
	assert_object(Replay.from_bytes(_words([DICTIONARY_WORD, 0]))).is_null()
	assert_object(Replay.from_bytes(_words(one + key + [INT_WORD, 5]))).is_null()


func test_from_bytes_never_makes_objects() -> void:
	var data: Dictionary = bytes_to_var(_replay().to_bytes())
	data["scenario"] = RefCounted.new()
	assert_object(Replay.from_bytes(var_to_bytes_with_objects(data))).is_null()
	assert_object(Replay.from_bytes(var_to_bytes_with_objects(RefCounted.new()))).is_null()
	# Only the variant that does not make objects may be named in the source.
	var source: String = FileAccess.get_file_as_string("res://game/sim/Replay.gd")
	assert_bool(source.contains("bytes_to_var(")).is_true()
	assert_bool(source.contains("_with_objects")).is_false()


func _keys() -> Array[String]:
	var keys: Array[String] = ["format", "scenario", "seed", "defs_hash", "commands"]
	keys.append_array(["checkpoint_ticks", "checkpoint_hashes", "final_tick", "final_hash"])
	return keys


## Little-endian u32 words, the way the engine writes a Variant.
func _words(words: Array) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(words.size() * 4)
	for k: int in words.size():
		bytes.encode_u32(k * 4, words[k])
	return bytes


func _world(ticks: int) -> World:
	var scenario: ScenarioDef = load(SCENARIO_PATH) as ScenarioDef
	var world: World = World.from_scenario(scenario, DetRandom.create(1, DetRandom.STREAM_SIM))
	var none: Array[Command] = []
	for k: int in ticks:
		Sim.step(world, none)
	return world


## A replay with every field set, the extremes of int32 and int64 among them.
func _replay() -> Replay:
	var replay: Replay = Replay.begin(SCENARIO_PATH, 5_000_000_000, -7_000_000_000_000)
	replay.record(Samples.full(Command.Type.MOVE, 3, 1))
	replay.record(Samples.full(Command.Type.STOP, 3, 2))
	replay.add_checkpoint(15, 0x7FFFFFFFFFFFFFFF)
	replay.add_checkpoint(30, -1)
	replay.add_checkpoint(45, 1 << 40)
	replay.finish(_world(2))
	return replay


## from_bytes of _replay() with one value of its dictionary replaced.
func _with(key: String, value: Variant) -> Replay:
	var data: Dictionary = bytes_to_var(_replay().to_bytes())
	data[key] = value
	return Replay.from_bytes(var_to_bytes(data))
