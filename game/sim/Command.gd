class_name Command
extends RefCounted
## One order to the simulation (ADR 0003 section 2, ADR 0007 section 5). Integers only. The
## target is a point in milli-tiles, not a cell. Sim.step applies a command at the start of the
## tick that equals `tick`, in `compare` order. 10-19 are reserved for Phase 3 and 20-29 for
## match-level commands: every type without a branch in Sim.step is dropped as unknown.

enum Type { NONE = 0, ATTACK_MOVE = 1, MOVE = 2, ATTACK = 3, STOP = 4 }

## The most unit ids and payload ints a command may hold; a command over either is dropped.
const MAX_UNITS: int = 256
const MAX_PAYLOAD: int = 16

## -1 until the runner stamps it.
var tick: int = -1
var player_id: int = 0
## Breaks ties between commands of one player in one tick.
var sequence: int = 0
var type: int = Type.NONE
var unit_ids: PackedInt32Array = PackedInt32Array()
var target_x: int = 0
var target_y: int = 0
## The unit an ATTACK goes after, 0 = none.
var target_id: int = 0
## Type-specific ints, empty for the Phase 2 types.
var payload: PackedInt32Array = PackedInt32Array()

## An attack-move order. Every factory copies the ids it is given (a command changes hands once,
## ADR 0012 section 2), so the caller may reuse its array. The parameters keep the contract's
## names, so they shadow the fields of the same name.
@warning_ignore("shadowed_variable")
static func attack_move(
	player_id: int, unit_ids: PackedInt32Array, target_x: int, target_y: int
) -> Command:
	var command: Command = _of(Type.ATTACK_MOVE, player_id, unit_ids)
	command.target_x = target_x
	command.target_y = target_y
	return command


## Like attack-move, but the units do not acquire targets until they arrive.
@warning_ignore("shadowed_variable")
static func move(
	player_id: int, unit_ids: PackedInt32Array, target_x: int, target_y: int
) -> Command:
	var command: Command = _of(Type.MOVE, player_id, unit_ids)
	command.target_x = target_x
	command.target_y = target_y
	return command


## Go after one enemy unit.
@warning_ignore("shadowed_variable")
static func attack(player_id: int, unit_ids: PackedInt32Array, target_id: int) -> Command:
	var command: Command = _of(Type.ATTACK, player_id, unit_ids)
	command.target_id = target_id
	return command


## Halt where the units stand.
@warning_ignore("shadowed_variable")
static func stop(player_id: int, unit_ids: PackedInt32Array) -> Command:
	return _of(Type.STOP, player_id, unit_ids)


@warning_ignore("shadowed_variable")
static func _of(type: int, player_id: int, unit_ids: PackedInt32Array) -> Command:
	var command: Command = Command.new()
	command.type = type
	command.player_id = player_id
	command.unit_ids = unit_ids.duplicate()
	return command


## Ascending (tick, player_id, sequence), for sort_custom: true when `a` goes first.
static func compare(a: Command, b: Command) -> bool:
	if a.tick != b.tick:
		return a.tick < b.tick
	if a.player_id != b.player_id:
		return a.player_id < b.player_id
	return a.sequence < b.sequence
