class_name RepairRules
extends RefCounted
## What the command bar's Repair asks of a published snapshot (ADR 0037 sections 5 and 9, plan
## P282, P282b). Pure statics, no Node. Repair shows while a complete own repair building serves an
## own ground unit of the selection (its `repair_classes` holds the unit's move class), damaged or
## not (`any_served`), and is dimmed while none of them is damaged; one tap sends one REPAIR with
## the damaged ones to the nearest such building, by straight distance from their centre.
## Units that building does not serve are left out; aircraft (an airfield's Home) and rows that
## are buildings never count, and a building with pads is an airfield, never a Repair target.

## The own repair buildings of the last `plan`, scratch (one thread; `plan` clears it).
static var _servers: PackedInt32Array = PackedInt32Array()


## Whether row `row` is a complete, living own repair building with no pads (a Weld Shed, a Drone
## Dock), that is a REPAIR target of ground units.
static func is_server(snap: MatchSnapshot, row: int, player: int) -> bool:
	if row < 0 or snap.owner[row] != player or snap.hp[row] <= 0 or snap.build_left[row] != 0:
		return false
	var type: int = snap.type_index[row]
	return (
		type < snap.type_repair_classes.size()
		and type < snap.type_pads.size()
		and type < snap.type_foot_w.size()
		and snap.type_repair_classes[type] != 0
		and snap.type_pads[type] == 0
		and snap.type_foot_w[type] > 0
	)


## Whether the row `row` is an own, living, finished ground unit (not a building, not an aircraft).
static func is_ground(snap: MatchSnapshot, row: int, player: int) -> bool:
	var type: int = snap.type_index[row]
	return (
		snap.owner[row] == player
		and snap.hp[row] > 0
		and snap.build_left[row] == 0
		and snap.type_speed[type] > 0
		and snap.type_foot_w[type] <= 0
		and (snap.type_layer_bit[type] & World.Layer.AIR) == 0
	)


## Whether the row `row` is a damaged own ground unit: the part of `is_served` no building changes.
static func is_hurt_ground(snap: MatchSnapshot, row: int, player: int) -> bool:
	return is_ground(snap, row, player) and snap.hp[row] < snap.type_max_hp[snap.type_index[row]]


## Whether building `server` serves the class of the own ground unit in `row`, hurt or not.
static func serves(snap: MatchSnapshot, row: int, server: int, player: int) -> bool:
	return (
		is_ground(snap, row, player)
		and (
			(
				(
					snap.type_repair_classes[snap.type_index[server]]
					>> snap.type_move_class[snap.type_index[row]]
				)
				& 1
			)
			== 1
		)
	)


## Whether the row `row` is a damaged own ground unit that building `server` serves.
static func is_served(snap: MatchSnapshot, row: int, server: int, player: int) -> bool:
	return is_hurt_ground(snap, row, player) and serves(snap, row, server, player)


## Whether some complete own repair building serves some own ground unit of `ids`, damaged or not:
## the bar's Repair shows (dimmed while `plan` finds nothing to send).
static func any_served(snap: MatchSnapshot, ids: PackedInt32Array, player: int) -> bool:
	if snap == null or snap.type_layer_bit.is_empty() or snap.type_move_class.is_empty():
		return false
	_collect_servers(snap, player)
	for id: int in ids:
		var row: int = snap.index_of(id)
		if row < 0:
			continue
		for server: int in _servers:
			if serves(snap, row, server, player):
				return true
	return false


static func _collect_servers(snap: MatchSnapshot, player: int) -> void:
	_servers.clear()
	for row: int in snap.unit_id.size():
		if is_server(snap, row, player):
			_servers.append(row)


## Replaces `out` with the ids of `ids` the nearest serving building takes and returns that
## building's id; 0 and an empty `out` when no building serves any of them. The nearest is by
## squared distance from the centre of the units some building serves, the lower id on a tie.
## One REPAIR goes to ONE building, so the units it does not serve are left for the next tap; that
## holds while the ground repair buildings of a side serve the same classes (a data test pins it:
## the Weld Shed and the Drone Dock both serve classes 6). If the masks ever differ, send one REPAIR
## per building, as `OrderRules.home_fields` and `Home` do, or a second tap would resend the first
## group (the centre covers every served unit).
static func plan(
	snap: MatchSnapshot, ids: PackedInt32Array, player: int, out: PackedInt32Array
) -> int:
	out.clear()
	if snap == null or snap.type_layer_bit.is_empty() or snap.type_move_class.is_empty():
		return 0
	var hurt: bool = false
	for id: int in ids:
		var at: int = snap.index_of(id)
		if at >= 0 and is_hurt_ground(snap, at, player):
			hurt = true
			break
	if not hurt:
		return 0  # Nothing to repair: the common case allocates and scans nothing more.
	_collect_servers(snap, player)
	var sum_x: int = 0
	var sum_y: int = 0
	for id: int in ids:  # `out` holds rows first, ids at the end.
		var row: int = snap.index_of(id)
		if row < 0 or is_server(snap, row, player):
			continue
		for server: int in _servers:
			if is_served(snap, row, server, player):
				out.append(row)
				sum_x += snap.pos_x[row]
				sum_y += snap.pos_y[row]
				break
	var count: int = out.size()
	if count == 0:
		return 0
	var best: int = -1
	var best_d2: int = 0
	for server: int in _servers:
		var served: bool = false
		for row: int in out:
			if is_served(snap, row, server, player):
				served = true
				break
		if not served:
			continue
		var dx: int = snap.pos_x[server] - sum_x / count
		var dy: int = snap.pos_y[server] - sum_y / count
		var d2: int = dx * dx + dy * dy
		if (
			best < 0
			or d2 < best_d2
			or (d2 == best_d2 and snap.unit_id[server] < snap.unit_id[best])
		):
			best = server
			best_d2 = d2
	var kept: int = 0
	for at: int in count:
		var row: int = out[at]
		if is_served(snap, row, best, player):
			out[kept] = snap.unit_id[row]
			kept += 1
	out.resize(kept)
	return snap.unit_id[best]
