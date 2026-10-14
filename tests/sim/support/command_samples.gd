extends RefCounted
## Commands for the encoding and replay tests (P35a): one with every field set to a different
## value, so a field that decode drops or swaps shows, and a command's fields as one Array to
## compare. Not a test suite.


## A command of `type` with the stamps `tick` and `sequence`, player 2, three ids and two payload
## ints, and a different value in every other field.
static func full(type: int, tick: int, sequence: int) -> Command:
	var command: Command = Command.new()
	command.type = type
	command.tick = tick
	command.player_id = 2
	command.sequence = sequence
	command.target_x = 12500
	command.target_y = -700
	command.target_id = 31
	command.unit_ids = PackedInt32Array([5, 9, 40])
	command.payload = PackedInt32Array([7, -8])
	return command


## tick, player_id, sequence, type, target_x, target_y, target_id, the ids, the payload.
static func fields(c: Command) -> Array:
	var all: Array = [c.tick, c.player_id, c.sequence, c.type]
	all.append_array([c.target_x, c.target_y, c.target_id])
	return all + [Array(c.unit_ids), Array(c.payload)]


## `decode` of `ints` at 0 into `out`.
static func decode(ints: Array, out: Command = null) -> int:
	return Command.decode(PackedInt32Array(ints), 0, Command.new() if out == null else out)
