class_name Command
extends RefCounted
## One order to the simulation (ADR 0003 section 2, ADR 0007 section 5). Integers only. The
## target is a point in milli-tiles, not a cell. Sim.step applies a command at the start of the
## tick that equals `tick`, in `compare` order. PLACE, QUEUE, CANCEL, RALLY and HARVEST (10-14) are
## the Phase 3 economy and production commands, SUPERWEAPON (15) fires a strike building (ADR 0023
## section 10) and SURRENDER (20) is the first match-level one (ADR 0017 section 4); 16-19 and 21-29
## stay reserved. Every type without a branch in Sim.step is dropped as unknown.

enum Type {
	NONE = 0,
	ATTACK_MOVE = 1,
	MOVE = 2,
	ATTACK = 3,
	STOP = 4,
	PLACE = 10,
	QUEUE = 11,
	CANCEL = 12,
	RALLY = 13,
	HARVEST = 14,
	SUPERWEAPON = 15,
	SURRENDER = 20,
}

## The most unit ids and payload ints a command may hold; Sim.step drops a command over either.
## Encoding is not validation: encode() writes and decode() reads such a command whole, because
## the replay log holds every stamped command and the drop is counted in the state hash.
const MAX_UNITS: int = 256
const MAX_PAYLOAD: int = 16

## The int32 range. A PackedInt32Array holds only values in it (ADR 0007 section 1), and an
## encoded command is one, so encode() saturates every int that is wider.
const INT32_MIN: int = -2147483648
const INT32_MAX: int = 2147483647
## The ints an encoded command starts with: tick, player_id, sequence, type, target_x, target_y and
## target_id. The unit count follows them.
const ENCODED_HEADER: int = 7
## The fewest ints an encoded command takes: the header, a unit count and a payload count, both 0.
const ENCODED_MIN: int = ENCODED_HEADER + 2

## -1 until the runner stamps it.
var tick: int = -1
var player_id: int = 0
## Breaks ties between commands of one player in one tick.
var sequence: int = 0
var type: int = Type.NONE
var unit_ids: PackedInt32Array = PackedInt32Array()
var target_x: int = 0
var target_y: int = 0
## The unit an ATTACK goes after, the production building a RALLY sets or the strike building a
## SUPERWEAPON fires, 0 = none.
var target_id: int = 0
## Type-specific ints (ADR 0017 section 4): QUEUE `[type_index]`, CANCEL `[tab, slot]`, empty for
## every other type.
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


## Place the ready head of the player's STRUCTURES queue, its footprint's origin tile being the tile
## of the point (milli-tiles).
@warning_ignore("shadowed_variable")
static func place(player_id: int, target_x: int, target_y: int) -> Command:
	var command: Command = _of(Type.PLACE, player_id, PackedInt32Array())
	command.target_x = target_x
	command.target_y = target_y
	return command


## Queue one unit or building of World type `type_index`; the payload is [type_index].
@warning_ignore("shadowed_variable")
static func queue(player_id: int, type_index: int) -> Command:
	var command: Command = _of(Type.QUEUE, player_id, PackedInt32Array())
	command.payload = PackedInt32Array([type_index])
	return command


## Cancel the item in `slot` of the queue of `tab` (a World.Tab); the payload is [tab, slot].
@warning_ignore("shadowed_variable")
static func cancel(player_id: int, tab: int, slot: int) -> Command:
	var command: Command = _of(Type.CANCEL, player_id, PackedInt32Array())
	command.payload = PackedInt32Array([tab, slot])
	return command


## Set the rally point of the tab that the own production building `building_id` produces.
@warning_ignore("shadowed_variable")
static func rally(player_id: int, building_id: int, target_x: int, target_y: int) -> Command:
	var command: Command = _of(Type.RALLY, player_id, PackedInt32Array())
	command.target_id = building_id
	command.target_x = target_x
	command.target_y = target_y
	return command


## Send harvesters to the ore near a point.
@warning_ignore("shadowed_variable")
static func harvest(
	player_id: int, unit_ids: PackedInt32Array, target_x: int, target_y: int
) -> Command:
	var command: Command = _of(Type.HARVEST, player_id, unit_ids)
	command.target_x = target_x
	command.target_y = target_y
	return command


## Fire the own strike building `building_id` at the point (milli-tiles).
@warning_ignore("shadowed_variable")
static func superweapon(player_id: int, building_id: int, target_x: int, target_y: int) -> Command:
	var command: Command = _of(Type.SUPERWEAPON, player_id, PackedInt32Array())
	command.target_id = building_id
	command.target_x = target_x
	command.target_y = target_y
	return command


## Lose the match at once.
@warning_ignore("shadowed_variable")
static func surrender(player_id: int) -> Command:
	return _of(Type.SURRENDER, player_id, PackedInt32Array())


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


## Appends this command to `out` for the replay log (ADR 0007 section 9): tick, player_id,
## sequence, type, target_x, target_y, target_id, the unit count, the ids, the payload count, the
## payload. Every int is written as it is when it fits int32 and saturates to INT32_MIN or
## INT32_MAX when it does not. That keeps a replay equal to the run in the one place it could
## differ: Sim.step clamps a target to the map, and no id, player or type beyond int32 names
## anything (a tick beyond int32 would be 4.5 years of play at 15 Hz). `tick` is -1 or in
## 0..INT32_MAX, and so is `sequence`, which counts the commands of one match. The counts are the
## array sizes as they are: a command over MAX_UNITS or MAX_PAYLOAD is written whole, and
## decode() reads it back whole. Sim.step drops it and adds 1 to dropped_commands, which the
## state hash covers, so a log that skipped or cut it would not replay to the same hash.
func encode(out: PackedInt32Array) -> void:
	out.append(_fit(tick))
	out.append(_fit(player_id))
	out.append(_fit(sequence))
	out.append(_fit(type))
	out.append(_fit(target_x))
	out.append(_fit(target_y))
	out.append(_fit(target_id))
	out.append(unit_ids.size())
	out.append_array(unit_ids)
	out.append(payload.size())
	out.append_array(payload)


## Reads the command that encode() wrote at offset `at` of `data` into `out` and returns the
## offset after it, or -1 for malformed data: `out` null, `at` outside the data, a count past the
## end of `data` or a negative count. A count above MAX_UNITS or MAX_PAYLOAD is not malformed (see
## encode). It reads only inside `data` and allocates nothing before every count is checked
## against the size of `data`, so a count of 2^31 - 1 in a short buffer costs nothing. It writes
## nothing to `out` when it returns -1, and gives `out` copies of the ids and the payload, so
## changing `data` or `out` afterwards does not reach the other. The type is not judged: Sim.step
## drops an unknown one.
static func decode(data: PackedInt32Array, at: int, out: Command) -> int:
	var size: int = data.size()
	# Compared as `at > size - ENCODED_MIN`, so a huge `at` cannot overflow.
	if out == null or at < 0 or at > size - ENCODED_MIN:
		return -1
	var unit_count: int = data[at + ENCODED_HEADER]
	if unit_count < 0:
		return -1
	var payload_at: int = at + ENCODED_HEADER + 1 + unit_count
	if payload_at >= size:
		return -1
	var payload_count: int = data[payload_at]
	if payload_count < 0:
		return -1
	var end: int = payload_at + 1 + payload_count
	if end > size:
		return -1
	out.tick = data[at]
	out.player_id = data[at + 1]
	out.sequence = data[at + 2]
	out.type = data[at + 3]
	out.target_x = data[at + 4]
	out.target_y = data[at + 5]
	out.target_id = data[at + 6]
	out.unit_ids = data.slice(at + ENCODED_HEADER + 1, payload_at)
	out.payload = data.slice(payload_at + 1, end)
	return end


static func _fit(value: int) -> int:
	return clampi(value, INT32_MIN, INT32_MAX)
