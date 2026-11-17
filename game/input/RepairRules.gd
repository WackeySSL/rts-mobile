class_name RepairRules
extends RefCounted
## What the command bar's Repair asks of a published snapshot (ADR 0037 sections 5 and 9, plan
## P282). Pure statics, no Node. Repair shows for damaged own ground units that a complete own
## repair building serves (its `repair_classes` holds the unit's move class), and one tap sends one
## REPAIR with those units to the nearest such building, by straight distance from their centre.
## Units that building does not serve are left out; aircraft (an airfield's Home) and rows that
## are buildings never count, and a building with pads is an airfield, never a Repair target.


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


## Whether the row `row` is a damaged own ground unit that building `server` serves.
static func is_served(snap: MatchSnapshot, row: int, server: int, player: int) -> bool:
	var type: int = snap.type_index[row]
	return (
		snap.owner[row] == player
		and snap.hp[row] > 0
		and snap.hp[row] < snap.type_max_hp[type]
		and snap.build_left[row] == 0
		and snap.type_speed[type] > 0
		and snap.type_foot_w[type] <= 0
		and (snap.type_layer_bit[type] & World.Layer.AIR) == 0
		and (
			(snap.type_repair_classes[snap.type_index[server]] >> snap.type_move_class[type]) & 1
			== 1
		)
	)


## Replaces `out` with the ids of `ids` the nearest serving building takes and returns that
## building's id; 0 and an empty `out` when no building serves any of them. The nearest is by
## squared distance from the centre of the units some building serves, the lower id on a tie.
static func plan(
	snap: MatchSnapshot, ids: PackedInt32Array, player: int, out: PackedInt32Array
) -> int:
	out.clear()
	if snap == null or snap.type_layer_bit.is_empty() or snap.type_move_class.is_empty():
		return 0
	var servers: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_id.size():
		if is_server(snap, row, player):
			servers.append(row)
	if servers.is_empty():
		return 0
	var sum_x: int = 0
	var sum_y: int = 0
	var count: int = 0
	var rows: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		var row: int = snap.index_of(id)
		if row < 0 or is_server(snap, row, player):
			continue
		for server: int in servers:
			if is_served(snap, row, server, player):
				rows.append(row)
				sum_x += snap.pos_x[row]
				sum_y += snap.pos_y[row]
				count += 1
				break
	if count == 0:
		return 0
	var best: int = -1
	var best_d2: int = 0
	for server: int in servers:
		var served: bool = false
		for row: int in rows:
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
	for row: int in rows:
		if is_served(snap, row, best, player):
			out.append(snap.unit_id[row])
	return snap.unit_id[best]
