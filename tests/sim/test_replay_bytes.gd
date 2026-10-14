extends GdUnitTestSuite
## Part 1b of the replay tests (P35a, ADR 0007 section 9): what Replay.from_bytes lets reach
## bytes_to_var. The engine prints an ERROR line for a buffer it cannot decode, a String that is
## not UTF-8 among them, and verify.sh fails on that line, so the walk must refuse every such
## buffer first. EngineErrors listens to the engine's log and after_test fails a test that made one.
## The buffers are built by hand from the words of the wire format (core/io/marshalls.cpp, Godot
## 4.7.2), so no encoder agrees with its own decoder by being wrong. test_replay has the rest.

const STRING_WORD: int = 4
## The layout of Replay.begin("", 0, 0).to_bytes(): the Dictionary header (8 bytes), the key
## "format" (16) and its int (8), the key "scenario" (16) and its value, the empty String (8).
const FORMAT_KEY_AT: int = 8
const FORMAT_VALUE_AT: int = 24
const SCENARIO_AT: int = 48
const SCENARIO_END: int = 56
## Well formed UTF-8: the code point, then its bytes. The first and last of every length, and the
## edges of the ranges that the second byte is narrowed to after E0, ED, F0 and F4.
const WELL_FORMED: Array = [
	[0x41, "41"],
	[0x80, "C280"],
	[0x7FF, "DFBF"],
	[0x800, "E0A080"],
	[0x1000, "E18080"],
	[0xCFFF, "ECBFBF"],
	[0xD7FF, "ED9FBF"],
	[0xE000, "EE8080"],
	[0xFFFF, "EFBFBF"],
	[0x10000, "F0908080"],
	[0x40000, "F1808080"],
	[0xFFFFF, "F3BFBFBF"],
	[0x10FFFF, "F48FBFBF"],
]
## Bytes the engine refuses (4.7.2), a name and the hex of the String's bytes. A group per rule.
const NOT_UTF8: Array = [
	["continuation byte as a lead", "80"],
	["continuation byte as a lead 2", "BF"],
	["continuation byte after ASCII", "6180"],
	["two continuation bytes", "8080"],
	["continuation bytes after a whole sequence", "C3A68080"],
	["lead of 5 bytes", "F888808080"],
	["lead of 6 bytes", "FC8480808080"],
	["FE", "FE"],
	["FF", "FF"],
	["overlong 2 bytes C0", "C080"],
	["overlong 2 bytes C1", "C1BF"],
	["overlong 3 bytes", "E08080"],
	["overlong 3 bytes 2", "E09FBF"],
	["overlong 4 bytes", "F0808080"],
	["overlong 4 bytes 2", "F08FBFBF"],
	["surrogate D800", "EDA080"],
	["surrogate DFFF", "EDBFBF"],
	["surrogate pair", "EDA0BDEDB880"],
	["above 10FFFF", "F4908080"],
	["above 10FFFF 2", "F4BFBFBF"],
	["lead F5", "F5808080"],
	["lead F7", "F7BFBFBF"],
	["2 bytes, ASCII second", "C361"],
	["2 bytes, lead second", "C3C3"],
	["2 bytes, 7F second", "C27F"],
	["2 bytes, C0 second", "C2C0"],
	["3 bytes, lead second", "E2C3A6"],
	["3 bytes, ASCII third", "E28261"],
	["3 bytes, 7F third", "E1807F"],
	["3 bytes, C0 third", "E180C0"],
	["4 bytes, ASCII third", "F09F6180"],
	["4 bytes, ASCII fourth", "F09F9861"],
	["4 bytes, C0 fourth", "F18080C0"],
	["4 bytes, 7F fourth", "F480807F"],
	["cut after a 2 byte lead", "C3"],
	["cut after a 3 byte lead", "E2"],
	["cut inside 3 bytes", "E282"],
	["cut after a 4 byte lead", "F0"],
	["cut inside 4 bytes", "F09F"],
	["cut inside 4 bytes 2", "F09F98"],
	["ASCII, then cut", "61C3"],
	["ASCII, then cut 2", "6162E282"],
	["whole, then cut", "C3A6F09F98"],
]
## A sequence cut at the end of the String, whose missing byte is the filler in the padding after
## it: the String ends where its count says, not where the padding does. Hex and the filler.
const CUT_BEFORE_FILLER: Array = [["C3", 0xA6], ["E282", 0xAC], ["F09F98", 0x80], ["6162C3", 0x80]]


## The errors the engine logs while a test runs, the lines scripts/verify.sh scans for.
class EngineErrors:
	extends Logger

	var hits: PackedStringArray = PackedStringArray()

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			hits.append("%s:%d %s %s" % [file, line, code, rationale])


var _errors: EngineErrors


func before_test() -> void:
	_errors = EngineErrors.new()
	OS.add_logger(_errors)


## The logger is global and must not outlive the test.
func after_test() -> void:
	OS.remove_logger(_errors)
	assert_array(_errors.hits).is_empty()


func test_the_helpers_build_replays_that_load() -> void:
	var base: PackedByteArray = Replay.begin("", 0, 0).to_bytes()
	assert_array([base.decode_u32(FORMAT_KEY_AT), base.decode_u32(FORMAT_KEY_AT + 4)]).is_equal(
		[STRING_WORD, 6]
	)
	assert_str(base.slice(FORMAT_KEY_AT + 8, FORMAT_KEY_AT + 14).get_string_from_utf8()).is_equal(
		"format"
	)
	assert_int(base.decode_u32(FORMAT_VALUE_AT)).is_equal(2)
	assert_array([base.decode_u32(SCENARIO_AT), base.decode_u32(SCENARIO_AT + 4)]).is_equal(
		[STRING_WORD, 0]
	)
	assert_int(SCENARIO_END - SCENARIO_AT).is_equal(8)
	var path: Replay = Replay.from_bytes(_with_scenario(_string("maps/a.tres".to_utf8_buffer())))
	assert_object(path).is_not_null()
	assert_str(path.scenario_path).is_equal("maps/a.tres")
	assert_object(Replay.from_bytes(_with_key(_string("format".to_utf8_buffer())))).is_not_null()
	assert_object(Replay.from_bytes(_with_key(_string("formax".to_utf8_buffer())))).is_null()
	# The filler is what pads the String, and the count is the bytes before it.
	assert_array(_string(PackedByteArray([0x61]), 0x7A)).is_equal(
		[4, 0, 0, 0, 1, 0, 0, 0, 0x61, 0x7A, 0x7A, 0x7A]
	)
	assert_int(_string(PackedByteArray([1, 2, 3, 4])).size()).is_equal(12)


## No valid replay is refused: every well formed String that the engine reads, from_bytes reads.
func test_a_scenario_path_in_well_formed_utf8_round_trips() -> void:
	var mixed: String = "maps/æøå.tres"
	var back: Replay = Replay.from_bytes(Replay.begin(mixed, 3, 4).to_bytes())
	assert_object(back).is_not_null()
	assert_str(back.scenario_path).is_equal(mixed)
	for entry: Array in WELL_FORMED:
		var code: int = entry[0]
		var hex: String = entry[1]
		var one: String = String.chr(code)
		assert_str(one.to_utf8_buffer().hex_encode().to_upper()).is_equal(hex)
		# One code point, and the code point among others (the walk goes on after a sequence).
		for text: String in [one, "a" + one + "b", one + one, mixed + one + mixed]:
			var written: Replay = Replay.from_bytes(Replay.begin(text, 1, 2).to_bytes())
			assert_object(written).override_failure_message("U+%X" % code).is_not_null()
			assert_str(written.scenario_path).is_equal(text)
		var bytes: PackedByteArray = hex.hex_decode()
		var by_hand: Replay = Replay.from_bytes(_with_scenario(_string(bytes)))
		assert_object(by_hand).override_failure_message("U+%X by hand" % code).is_not_null()
		assert_str(by_hand.scenario_path).is_equal(one)


## A key or the scenario path whose bytes are not UTF-8 is refused before bytes_to_var sees it: the
## answer is null and the engine logs nothing (after_test). Each rule of the check has a case here.
func test_from_bytes_gives_null_for_a_key_or_the_scenario_that_is_not_utf8() -> void:
	for entry: Array in NOT_UTF8:
		var name: String = entry[0]
		var string: PackedByteArray = _string(String(entry[1]).hex_decode())
		(
			assert_object(Replay.from_bytes(_with_scenario(string)))
			. override_failure_message("scenario: " + name)
			. is_null()
		)
		(
			assert_object(Replay.from_bytes(_with_key(string)))
			. override_failure_message("key: " + name)
			. is_null()
		)
	for entry: Array in CUT_BEFORE_FILLER:
		var string: PackedByteArray = _string(String(entry[0]).hex_decode(), entry[1])
		(
			assert_object(Replay.from_bytes(_with_scenario(string)))
			. override_failure_message("scenario cut: " + str(entry[0]))
			. is_null()
		)
		(
			assert_object(Replay.from_bytes(_with_key(string)))
			. override_failure_message("key cut: " + str(entry[0]))
			. is_null()
		)


## The walker takes the four kinds that to_bytes() writes and nothing else. A buffer per kind that
## it refuses is whole and well sized, so only the kind stands between it and bytes_to_var.
func test_the_walker_takes_only_ints_strings_and_the_two_packed_arrays() -> void:
	var good: PackedByteArray = var_to_bytes(_data())
	assert_bool(Replay._is_plain_dictionary(good)).is_true()
	assert_object(Replay.from_bytes(good)).is_not_null()
	# 32 and 64 bit ints, the empty and a long String, empty and full arrays are all taken.
	var data: Dictionary = _data()
	data["seed"] = -2147483648
	data["defs_hash"] = 1 << 62
	data["final_tick"] = 2147483647
	data["scenario"] = "a".repeat(1001)
	data["commands"] = PackedInt32Array()
	data["checkpoint_ticks"] = PackedInt32Array([1, 2, 3])
	data["checkpoint_hashes"] = PackedInt64Array([1, 2, 3])
	assert_bool(Replay._is_plain_dictionary(var_to_bytes(data))).is_true()
	var refused: Dictionary = {
		"float 32": 1.5,
		"float 64": 0.1,
		"bool true": true,
		"bool false": false,
		"nil": null,
		"Array": [7],
		"empty Array": [],
		"PackedByteArray": PackedByteArray([1, 2, 3, 4]),
		"PackedStringArray": PackedStringArray(["a"]),
		"PackedFloat32Array": PackedFloat32Array([1.5]),
		"StringName": &"seed",
		"NodePath": ^"a/b",
		"Dictionary": {"k": 1},
		"Vector2i": Vector2i(1, 2),
	}
	for kind: String in refused:
		for key: String in ["seed", "final_hash", "format"]:
			var other: Dictionary = _data()
			other[key] = refused[kind]
			var bytes: PackedByteArray = var_to_bytes(other)
			(
				assert_bool(Replay._is_plain_dictionary(bytes))
				. override_failure_message("%s as %s" % [kind, key])
				. is_false()
			)
			assert_object(Replay.from_bytes(bytes)).is_null()


## The value that ends the buffer is a String or an array as often as an int: it fits exactly,
## with nothing after it, whatever its size, the empty ones and the padded ones included.
func test_a_string_or_an_array_that_ends_the_buffer_is_taken() -> void:
	var record: PackedInt32Array = PackedInt32Array([1, 0, 0, 3, 0, 0, 0, 0, 0])
	var none: Dictionary = {
		"checkpoint_ticks": PackedInt32Array(), "checkpoint_hashes": PackedInt64Array()
	}
	var cases: Array = [
		["scenario", {"scenario": ""}],
		["scenario", {"scenario": "a"}],
		["scenario", {"scenario": "abcd"}],
		["scenario", {"scenario": "maps/æøå.tres"}],
		["commands", {"commands": PackedInt32Array()}],
		["commands", {"commands": record}],
		["commands", {"commands": record + record}],
		["checkpoint_ticks", none],
		["checkpoint_hashes", none],
		["checkpoint_hashes", {}],
		["checkpoint_ticks", {}],
	]
	for entry: Array in cases:
		var key: String = entry[0]
		var data: Dictionary = _data()
		data.merge(entry[1], true)
		var value: Variant = data[key]
		data.erase(key)
		data[key] = value
		var last: String = data.keys().back()
		assert_str(last).is_equal(key)
		var bytes: PackedByteArray = var_to_bytes(data)
		(
			assert_bool(Replay._is_plain_dictionary(bytes))
			. override_failure_message("%s %s" % [key, str(entry[1])])
			. is_true()
		)
		var back: Replay = Replay.from_bytes(bytes)
		assert_object(back).override_failure_message("%s %s" % [key, str(entry[1])]).is_not_null()
		# One byte less and one more are cut or too long, wherever the end is.
		assert_bool(Replay._is_plain_dictionary(bytes.slice(0, bytes.size() - 1))).is_false()
		assert_bool(Replay._is_plain_dictionary(bytes + PackedByteArray([0]))).is_false()


## A replay with every field set: one command record, one checkpoint, ints of both widths.
func _data() -> Dictionary:
	return {
		"format": 1,
		"scenario": "maps/a.tres",
		"seed": 5_000_000_000,
		"defs_hash": -7,
		"commands": PackedInt32Array([1, 0, 0, 3, 0, 0, 0, 0, 0]),
		"checkpoint_ticks": PackedInt32Array([15]),
		"checkpoint_hashes": PackedInt64Array([5]),
		"final_tick": 15,
		"final_hash": -9,
	}


## Little-endian u32 words, the way the engine writes a Variant.
func _words(words: Array) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(words.size() * 4)
	for k: int in words.size():
		bytes.encode_u32(k * 4, words[k])
	return bytes


## A String as the engine writes it: the type word, the byte count, the bytes, and `filler` up to
## a multiple of 4 bytes.
func _string(body: PackedByteArray, filler: int = 0) -> PackedByteArray:
	var out: PackedByteArray = _words([STRING_WORD, body.size()]) + body
	while out.size() % 4 != 0:
		out.append(filler)
	return out


## Replay.begin("", 0, 0).to_bytes() with its scenario value replaced by `string`.
func _with_scenario(string: PackedByteArray) -> PackedByteArray:
	var base: PackedByteArray = Replay.begin("", 0, 0).to_bytes()
	return base.slice(0, SCENARIO_AT) + string + base.slice(SCENARIO_END)


## Replay.begin("", 0, 0).to_bytes() with its first key, "format", replaced by `string`.
func _with_key(string: PackedByteArray) -> PackedByteArray:
	var base: PackedByteArray = Replay.begin("", 0, 0).to_bytes()
	return base.slice(0, FORMAT_KEY_AT) + string + base.slice(FORMAT_VALUE_AT)
