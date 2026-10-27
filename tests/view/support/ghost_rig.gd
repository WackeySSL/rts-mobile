extends RefCounted
## Fixtures of the ghost suites (plan P115c). Not a test suite. They write the last-seen records of
## the published snapshot the way the sim leaves them (`LastSeen`: record i of player p is entry
## `p * ghost_cap + i` of the four record arrays, live below `ghost_count[p]`), so a case can set up
## what a player remembers without playing the match that led to it.

## The records a player's block holds: `ghost_cap`, as the layer derives it.
@warning_ignore("integer_division")
static func cap_of(snap: MatchSnapshot) -> int:
	return snap.ghost_id.size() / snap.ghost_count.size()


## The type index of the roster entry `type_id` in `snap`, -1 for none.
static func type_of(snap: MatchSnapshot, type_id: StringName) -> int:
	return snap.type_ids.find(type_id)


## The tile that holds the centre of a footprint of `w` x `h` tiles whose top-left tile is `origin`:
## the cell the sim records for the building.
@warning_ignore("integer_division")
static func centre_cell(snap: MatchSnapshot, origin: Vector2i, w: int, h: int) -> int:
	return (origin.y + h / 2) * snap.fog.cols + origin.x + w / 2


## One record: the building's id, its roster entry, its owner and the tile of its footprint centre.
static func record(id: int, type_id: StringName, owner_id: int, cell: int) -> Array:
	return [id, type_id, owner_id, cell]


## Makes `records` (from `record`) the whole block of `player` in `snap`: the records first, in
## order, zeros after them, and the count. Another player's block is not touched. It does not move
## the fog version, which the layer reads, so a case calls `Rig.see` after it.
static func remember(snap: MatchSnapshot, player: int, records: Array) -> void:
	var cap: int = cap_of(snap)
	assert(records.size() <= cap)
	for at: int in cap:
		var entry: int = player * cap + at
		var made: Array = records[at] if at < records.size() else [0, &"", 0, 0]
		snap.ghost_id[entry] = made[0]
		snap.ghost_type[entry] = type_of(snap, made[1]) if at < records.size() else 0
		snap.ghost_owner[entry] = made[2]
		snap.ghost_cell[entry] = made[3]
	snap.ghost_count[player] = records.size()
