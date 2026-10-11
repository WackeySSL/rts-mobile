class_name Command
extends RefCounted
## One order to the simulation (ADR 0003 section 2). Integers only. The target is a point in
## milli-tiles, not a cell. Sim.step applies a command at the start of the tick that equals
## `tick`, in `compare` order.

enum Type { NONE = 0, ATTACK_MOVE = 1 }

## -1 until the runner stamps it.
var tick: int = -1
var player_id: int = 0
## Breaks ties between commands of one player in one tick.
var sequence: int = 0
var type: int = Type.NONE
var unit_ids: PackedInt32Array = PackedInt32Array()
var target_x: int = 0
var target_y: int = 0
## 0 = none. Unused in Phase 1.
var target_id: int = 0

## An attack-move order. The ids are copied, so the caller may reuse its array. The parameters
## keep the contract's names, so they shadow the fields of the same name.
@warning_ignore("shadowed_variable")
static func attack_move(
	player_id: int, unit_ids: PackedInt32Array, target_x: int, target_y: int
) -> Command:
	var command: Command = Command.new()
	command.type = Type.ATTACK_MOVE
	command.player_id = player_id
	command.unit_ids = unit_ids.duplicate()
	command.target_x = target_x
	command.target_y = target_y
	return command


## Ascending (tick, player_id, sequence), for sort_custom: true when `a` goes first.
static func compare(a: Command, b: Command) -> bool:
	if a.tick != b.tick:
		return a.tick < b.tick
	if a.player_id != b.player_id:
		return a.player_id < b.player_id
	return a.sequence < b.sequence
