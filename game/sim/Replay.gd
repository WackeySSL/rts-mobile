class_name Replay
extends RefCounted
## The log of one match (ADR 0007 section 9): the scenario path, the seed, the defs hash, every
## command in stamping order and a checkpoint hash every CHECKPOINT_PERIOD ticks. The sim is a pure
## function of these. Pure sim code: no Node, no clock and no file access (the runner saves and
## loads files). A replay is valid only for the code and data that recorded it. `play` comes with
## MatchLoop in P35b.

const FORMAT: int = 1
## Ticks between two checkpoints; MatchLoop adds one when `tick % CHECKPOINT_PERIOD == 0`.
const CHECKPOINT_PERIOD: int = 15

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
## type or array kind than KINDS says, or checkpoint arrays of unequal sizes. It decodes with
## bytes_to_var, never the variant that makes objects, and only after _is_plain_dictionary has
## walked the bytes: the engine prints an ERROR line for every buffer it cannot decode, so
## truncated and random bytes must not reach it. A string whose bytes are not UTF-8 still passes
## the walk and still makes the engine print that error, and from_bytes returns null for it.
## Whether the commands in the log decode is for `play` to find out (Command.decode gives -1).
static func from_bytes(bytes: PackedByteArray) -> Replay:
	if not _is_plain_dictionary(bytes):
		return null
	var raw: Variant = bytes_to_var(bytes)
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
	return replay


## True when `bytes` is one Dictionary and nothing after it, whose keys and values are only ints,
## Strings, PackedInt32Arrays and PackedInt64Arrays, each with a size that fits the buffer. That
## is the whole of what to_bytes() writes, and bytes_to_var decodes such a buffer without an error.
## It reads only inside `bytes` and ends at the first value that does not fit.
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
## kinds, or does not end inside `bytes`. The wire form is a u32 header, then: 4 bytes for an int
## (8 with WIRE_INT_64), and for a String or an array a u32 count and the elements (a String's
## bytes padded to a multiple of 4; 4 bytes per element for PackedInt32Array, 8 for
## PackedInt64Array). Header, counts and sizes are below 2^36, so nothing overflows.
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
	if at <= end - 8:
		var count: int = bytes.decode_u32(at + 4)
		match header:
			TYPE_STRING:
				body = ((count + 3) >> 2) << 2
			TYPE_PACKED_INT32_ARRAY:
				body = count << 2
			TYPE_PACKED_INT64_ARRAY:
				body = count << 3
	if body < 0 or at + 8 + body > end:
		return -1
	return 8 + body
