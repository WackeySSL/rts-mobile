class_name Replay
extends RefCounted
## The log of one match (ADR 0007 section 9): the scenario path, the seed, the defs hash, every
## command in stamping order and a checkpoint hash every CHECKPOINT_PERIOD ticks. The sim is a pure
## function of these. Pure sim code: no Node, no clock and no file access (the runner saves and
## loads files). A replay is valid only for the code and data that recorded it. `play` runs it
## again through MatchLoop and finds where it stops matching.

const FORMAT: int = 1
## Ticks between two checkpoints; MatchLoop adds one when `tick % CHECKPOINT_PERIOD == 0`.
const CHECKPOINT_PERIOD: int = 15

## What `play` returns besides the tick of the first checkpoint that differs (a tick is never
## negative): every checkpoint up to `until_tick` matched, the world's defs_hash is not the
## replay's, or the replay is malformed (a command that does not decode, a command out of tick
## order, a checkpoint with a negative tick).
const PLAY_MATCHED: int = -1
const PLAY_DEFS_DIFFER: int = -2
const PLAY_BAD_LOG: int = -3

## The keys of the dictionary that to_bytes() writes, with the Variant type each value must have.
## An array kind is part of the type: the commands and the tick list are PackedInt32Array, the
## hash list is PackedInt64Array.
const KINDS: Dictionary[String, int] = {
	"format": TYPE_INT,
	"scenario": TYPE_STRING,
	"seed": TYPE_INT,
	"defs_hash": TYPE_INT,
	"commands": TYPE_PACKED_INT32_ARRAY,
	"checkpoint_ticks": TYPE_PACKED_INT32_ARRAY,
	"checkpoint_hashes": TYPE_PACKED_INT64_ARRAY,
	"final_tick": TYPE_INT,
	"final_hash": TYPE_INT,
}
## The wire header (core/io/marshalls.cpp, Godot 4.7.2) of an int that needs 64 bits: the type with
## bit 16 set. The other kinds a replay holds are their plain type.
const WIRE_INT_64: int = TYPE_INT | (1 << 16)

var scenario_path: String = ""
## The match seed. It is a whole int (not int32) and is stored as one.
@warning_ignore("shadowed_global_identifier") var seed: int = 0
## World.defs_hash() of the world that recorded; an int64.
var defs_hash: int = 0
## Every command, back to back in Command.encode's layout (int32 each), in the order it was
## recorded: the order Sim.step saw them, with the stamps MatchLoop gave them.
var commands: PackedInt32Array = PackedInt32Array()
## The ticks of the checkpoints, ascending, and their World.state_hash() values (int64). The two
## arrays have equal sizes.
var checkpoint_ticks: PackedInt32Array = PackedInt32Array()
var checkpoint_hashes: PackedInt64Array = PackedInt64Array()
## The tick and the state hash `finish` saw.
var final_tick: int = 0
var final_hash: int = 0

## An empty replay for the match that starts from `scenario_path` with `seed` on data whose
## World.defs_hash() is `defs_hash`. The parameters keep the contract's names.
@warning_ignore("shadowed_variable", "shadowed_global_identifier")
static func begin(scenario_path: String, seed: int, defs_hash: int) -> Replay:
	var replay: Replay = Replay.new()
	replay.scenario_path = scenario_path
	replay.seed = seed
	replay.defs_hash = defs_hash
	return replay


## Appends `command`, not null, as Command.encode writes it. MatchLoop calls it after stamping and
## before Sim.step, for every command, so a command that Sim.step then drops is in the log too.
func record(command: Command) -> void:
	command.encode(commands)


## Adds the checkpoint of `tick`, an int32 (a tick beyond it saturates, as in Command.encode), and
## its state hash.
@warning_ignore("shadowed_global_identifier")
func add_checkpoint(tick: int, hash: int) -> void:
	checkpoint_ticks.append(clampi(tick, Command.INT32_MIN, Command.INT32_MAX))
	checkpoint_hashes.append(hash)


## Takes the tick and the state hash of `world`: the end of the match.
func finish(world: World) -> void:
	final_tick = world.tick
	final_hash = world.state_hash()


## Steps `world`, a fresh world of the replay's scenario made with the replay's seed, from its
## tick up to `until_tick` and compares the checkpoints. The world goes through
## MatchLoop.create(null, ...), which issues no scenario orders because the log already holds the
## stamped ones, and every tick gets the commands the log holds for it as `queued`, in log order,
## so the loop gives them the sequences they were recorded with. A command that Sim.step dropped
## in the run (an over-limit one too) is in the log and is dropped again. Returns PLAY_MATCHED
## when every checkpoint with a tick up to `until_tick` equals the replay's, else the tick of the
## first one that does not (a recorded checkpoint whose tick the loop never reaches counts as
## differing); PLAY_DEFS_DIFFER, before any step, when `world.defs_hash()` is not `defs_hash`; and
## PLAY_BAD_LOG when the log has a command that does not decode, or one whose tick is behind the
## world's tick when its turn comes (a log is in tick order), or a checkpoint has a negative tick.
## It reads the log only as far as `until_tick` needs, steps at most `until_tick - world.tick`
## ticks, and never crashes on bytes. Commands the log holds for ticks after `until_tick` are not
## read, and the replay's `final_hash` is not checked: the caller compares that.
static func play(replay: Replay, world: World, until_tick: int) -> int:
	world.prepare()
	if replay.defs_hash != world.defs_hash():
		return PLAY_DEFS_DIFFER
	var loop: MatchLoop = MatchLoop.create(null, replay.scenario_path, replay.seed, world)
	var data: PackedInt32Array = replay.commands
	var data_size: int = data.size()
	var at: int = 0
	var checkpoint_ticks: PackedInt32Array = replay.checkpoint_ticks
	var checkpoint_hashes: PackedInt64Array = replay.checkpoint_hashes
	var checkpoints: int = mini(checkpoint_ticks.size(), checkpoint_hashes.size())
	var checked: int = 0
	var queued: Array[Command] = []
	while world.tick < until_tick:
		queued.clear()
		# The first int of a record is its tick. A record that is behind the world, or that does
		# not decode, ends the play.
		while at < data_size and data[at] <= world.tick:
			if data[at] < world.tick:
				return PLAY_BAD_LOG
			var command: Command = Command.new()
			var end: int = Command.decode(data, at, command)
			if end < 0:
				return PLAY_BAD_LOG
			queued.append(command)
			at = end
		loop.step(world, queued)
		while checked < checkpoints and checkpoint_ticks[checked] <= world.tick:
			# A negative tick would read as one of the codes, so it is a bad replay instead.
			if checkpoint_ticks[checked] < 0:
				return PLAY_BAD_LOG
			var reached: bool = (
				checkpoint_ticks[checked] == world.tick
				and world.tick % CHECKPOINT_PERIOD == 0
				and checkpoint_hashes[checked] == loop.last_hash
			)
			if not reached:
				return checkpoint_ticks[checked]
			checked += 1
	return PLAY_MATCHED


## The replay as bytes: var_to_bytes of a Dictionary with the KINDS keys in that order, so equal
## replays give equal bytes. Objects are never written.
func to_bytes() -> PackedByteArray:
	# Not a typed Dictionary: that writes its key and value types into the header.
	var data: Dictionary = {
		"format": FORMAT,
		"scenario": scenario_path,
		"seed": seed,
		"defs_hash": defs_hash,
		"commands": commands,
		"checkpoint_ticks": checkpoint_ticks,
		"checkpoint_hashes": checkpoint_hashes,
		"final_tick": final_tick,
		"final_hash": final_hash,
	}
	return var_to_bytes(data)


## The replay that to_bytes() wrote, or null for anything else: bytes that are not a Dictionary of
## ints, Strings and the two Packed arrays, a wrong `format`, a missing key, a value of another
## type or array kind than KINDS says, checkpoint arrays of unequal sizes, or a command log that
## Command.decode cannot read from 0 to exactly its size (a cut record, a negative count, a count
## past the end, ints after the last record). So the log of a loaded replay always decodes; one
## built in memory is for `play` (P35b) to judge. A command over MAX_UNITS or MAX_PAYLOAD is not
## malformed. It decodes with bytes_to_var, never the variant that makes objects, and only after
## _is_plain_dictionary has walked the bytes, the UTF-8 of every String included: the engine prints
## an ERROR line for every buffer it cannot decode, so truncated, random and corrupt bytes must not
## reach it, and a refused buffer makes no engine output at all.
static func from_bytes(bytes: PackedByteArray) -> Replay:
	if not _is_plain_dictionary(bytes):
		return null
	var raw: Variant = bytes_to_var(bytes)
	# A guard: the walk has made sure of one Dictionary, so this does not fail.
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = raw
	for key: String in KINDS:
		if not data.has(key) or typeof(data[key]) != KINDS[key]:
			return null
	if data["format"] != FORMAT:
		return null
	var replay: Replay = Replay.new()
	replay.scenario_path = data["scenario"]
	replay.seed = data["seed"]
	replay.defs_hash = data["defs_hash"]
	replay.commands = data["commands"]
	replay.checkpoint_ticks = data["checkpoint_ticks"]
	replay.checkpoint_hashes = data["checkpoint_hashes"]
	replay.final_tick = data["final_tick"]
	replay.final_hash = data["final_hash"]
	if replay.checkpoint_ticks.size() != replay.checkpoint_hashes.size():
		return null
	if not _log_decodes(replay.commands):
		return null
	return replay


## True when Command.decode reads `ints`, a command log, record after record from 0 and ends exactly
## at its size. The empty log is one.
static func _log_decodes(ints: PackedInt32Array) -> bool:
	var scratch: Command = Command.new()
	var at: int = 0
	# Each record takes at least Command.ENCODED_MIN ints, so the loop ends.
	while at < ints.size():
		at = Command.decode(ints, at, scratch)
		if at < 0:
			return false
	return true


## True when `bytes` is one Dictionary and nothing after it, whose keys and values are only ints,
## Strings (in UTF-8), PackedInt32Arrays and PackedInt64Arrays, each with a size that fits the
## buffer. That is the whole of what to_bytes() writes, and bytes_to_var decodes such a buffer
## without an error. It reads only inside `bytes` and ends at the first value that does not fit.
static func _is_plain_dictionary(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8 or bytes.decode_u32(0) != TYPE_DICTIONARY:
		return false
	var at: int = 8
	# A pair is a key and a value, and each value takes at least 8 bytes, so the loop ends at the
	# buffer's end even when the count is 2^32 - 1.
	for _part: int in bytes.decode_u32(4) * 2:
		var length: int = _wire_size(bytes, at)
		if length < 0:
			return false
		at += length
	return at == bytes.size()


## The bytes the Variant at `at` takes (its header included), or -1 when it is not one of the four
## kinds, does not end inside `bytes`, or is a String that is not UTF-8. The wire form is a u32
## header, then: 4 bytes for an int (8 with WIRE_INT_64), and for a String or an array a u32 count
## and the elements (a String's bytes padded to a multiple of 4; 4 bytes per element for
## PackedInt32Array, 8 for PackedInt64Array). Header, counts and sizes are below 2^36, so nothing
## overflows.
static func _wire_size(bytes: PackedByteArray, at: int) -> int:
	var end: int = bytes.size()
	if at > end - 4:
		return -1
	var header: int = bytes.decode_u32(at)
	if header == TYPE_INT:
		return 8 if at <= end - 8 else -1
	if header == WIRE_INT_64:
		return 12 if at <= end - 12 else -1
	var body: int = -1
	var count: int = 0
	if at <= end - 8:
		count = bytes.decode_u32(at + 4)
		match header:
			TYPE_STRING:
				body = ((count + 3) >> 2) << 2
			TYPE_PACKED_INT32_ARRAY:
				body = count << 2
			TYPE_PACKED_INT64_ARRAY:
				body = count << 3
	if body < 0 or at + 8 + body > end:
		return -1
	# The engine prints an ERROR for a String that is not UTF-8, and a key is a String too.
	if header == TYPE_STRING and not _is_utf8(bytes, at + 8, at + 8 + count):
		return -1
	return 8 + body


## True when bytes[from, to) are well formed UTF-8, which is what the engine's String decoding
## (append_utf8, Godot 4.7.2) takes: a lead byte of 1 to 4 bytes, each continuation byte 10xxxxxx,
## no overlong form, no surrogate (U+D800 to U+DFFF) and nothing above U+10FFFF. A NUL byte is ASCII
## here, though the engine ends a string at one; to_bytes() never writes it.
static func _is_utf8(bytes: PackedByteArray, from: int, to: int) -> bool:
	var at: int = from
	while at < to:
		var lead: int = bytes[at]
		at += 1
		if lead < 0x80:
			continue
		# 80 to BF is a continuation byte, C0 and C1 start an overlong form, F5 to FF start a code
		# point above U+10FFFF or a sequence of 5 or 6 bytes.
		if lead < 0xC2 or lead > 0xF4:
			return false
		# The second byte is 80 to BF, narrowed after four leads; the others are always 80 to BF.
		var low: int = 0x80
		var high: int = 0xBF
		if lead == 0xE0:
			low = 0xA0  # E0 80 to 9F is an overlong form.
		elif lead == 0xF0:
			low = 0x90  # F0 80 to 8F is an overlong form.
		elif lead == 0xED:
			high = 0x9F  # ED A0 to BF is a surrogate.
		elif lead == 0xF4:
			high = 0x8F  # F4 90 to BF is above U+10FFFF.
		var extra: int = 1 if lead < 0xE0 else (2 if lead < 0xF0 else 3)
		if at + extra > to or bytes[at] < low or bytes[at] > high:
			return false
		for k: int in range(1, extra):
			if (bytes[at + k] & 0xC0) != 0x80:
				return false
		at += extra
	return true
