class_name CarryRules
extends RefCounted
## What the Board and Unload orders may do, read from the published snapshot (ADR 0036 section 8,
## `Carry.apply_load` and `Carry.apply_unload` are the sim's side of the same rules). Pure: no Node,
## no clock. A carrier is a mobile row of a type with `type_carry_slots` above 0; a squad is an own,
## complete, living FOOT row that is no carrier. Boarded squads are not rows: the passenger table
## (`pass_carrier`) holds a carrier's id once per squad aboard.


## Whether type `type` is a carrier.
static func is_carrier_type(snap: MatchSnapshot, type: int) -> bool:
	return (
		type < snap.type_carry_slots.size()
		and snap.type_carry_slots[type] > 0
		and snap.type_speed[type] > 0
	)


## How many squads are aboard the carrier `id`.
static func aboard(snap: MatchSnapshot, id: int) -> int:
	var count: int = 0
	for at: int in mini(snap.pass_count, snap.pass_carrier.size()):
		if snap.pass_carrier[at] == id:
			count += 1
	return count


## Whether row `row` is a carrier of `player`'s that squads may board now: complete, alive, a free
## seat and its classes take FOOT squads.
static func can_take_squads(snap: MatchSnapshot, row: int, player: int) -> bool:
	var type: int = snap.type_index[row]
	return (
		snap.owner[row] == player
		and snap.hp[row] > 0
		and snap.build_left[row] == 0
		and is_carrier_type(snap, type)
		and ((snap.type_carry_classes[type] >> World.MoveClass.FOOT) & 1) == 1
		and snap.type_carry_slots[type] > aboard(snap, snap.unit_id[row])
	)


## Whether row `row` is a squad of `player`'s that a carrier takes.
static func is_squad(snap: MatchSnapshot, row: int, player: int) -> bool:
	var type: int = snap.type_index[row]
	return (
		snap.owner[row] == player
		and snap.hp[row] > 0
		and snap.build_left[row] == 0
		and snap.type_speed[type] > 0
		and snap.type_move_class[type] == World.MoveClass.FOOT
		and not is_carrier_type(snap, type)
	)


## The ids of `ids` that are squads of `player`'s.
static func squads_in(snap: MatchSnapshot, ids: PackedInt32Array, player: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		var row: int = snap.index_of(id)
		if row >= 0 and is_squad(snap, row, player):
			out.append(id)
	return out


## The ids of `ids` that are carriers of `player`'s with a squad aboard (what UNLOAD serves).
static func loaded_in(snap: MatchSnapshot, ids: PackedInt32Array, player: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		var row: int = snap.index_of(id)
		if (
			row >= 0
			and snap.owner[row] == player
			and snap.hp[row] > 0
			and snap.build_left[row] == 0
			and is_carrier_type(snap, snap.type_index[row])
			and aboard(snap, id) > 0
		):
			out.append(id)
	return out


## Whether `player` has a carrier on the map that squads could board (Board shows only then).
static func has_carrier(snap: MatchSnapshot, player: int) -> bool:
	for row: int in snap.unit_count():
		if can_take_squads(snap, row, player):
			return true
	return false
