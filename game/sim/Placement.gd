class_name Placement
extends RefCounted
## Whether a building fits (ADR 0017 section 2): one pure function over a PlacementInput, so the
## sim (applying PLACE, plan row P73b) and the view (the ghost's tint, ADR 0019) judge by the same
## code, once per PLACE or per redraw of the ghost and never in a per-tick loop. Integers only.
## Every array is read through a size guard, because a hand-built World need not size all of them
## (prepare() sizes `terrain_buildable` for the one terrain it derives, while a test may paint more
## over it): a tile whose terrain has no flag is not buildable.

## The first rule that fails, in this order: a tile outside the map (or a type with no footprint);
## a tile that is not buildable or costs 0 for foot (rock, water, another building); a mobile row
## whose disc touches the footprint; a tile the player never explored; no own building within
## `build_reach_tiles`; `building_cap` buildings already.
enum Reason {
	OK = 0,
	OUTSIDE = 1,
	GROUND = 2,
	OCCUPIED = 3,
	UNEXPLORED = 4,
	TOO_FAR = 5,
	CAP = 6,
}

## The foot class's list in `move_cost` starts at FOOT * cells.
const FOOT: int = World.MoveClass.FOOT


## The Reason `player` gets for a building of `type_index` with its top-left tile at (origin_col,
## origin_row). OCCUPIED counts a mobile row of any owner whose disc (centre and `type_radius`)
## touches the footprint rectangle, the edge included. A player who owns no building is TOO_FAR
## from every tile, and a player the fog has no block for (the neutral 0) has explored everything.
static func reason(
	input: PlacementInput, player: int, type_index: int, origin_col: int, origin_row: int
) -> int:
	var width: int = _entry(input.type_foot_w, type_index)
	var height: int = _entry(input.type_foot_h, type_index)
	if (
		width <= 0
		or height <= 0
		or origin_col < 0
		or origin_row < 0
		or origin_col + width > input.map_cols
		or origin_row + height > input.map_rows
	):
		return Reason.OUTSIDE
	if _bad_ground(input, origin_col, origin_row, width, height):
		return Reason.GROUND
	if _occupied(input, origin_col, origin_row, width, height):
		return Reason.OCCUPIED
	if _unexplored(input, player, origin_col, origin_row, width, height):
		return Reason.UNEXPLORED
	return _reach_and_cap(input, player, origin_col, origin_row, width, height)


## Whether a footprint tile is not buildable or costs 0 for foot.
static func _bad_ground(
	input: PlacementInput, col: int, line: int, width: int, height: int
) -> bool:
	var kinds: PackedByteArray = input.terrain
	var flags: PackedByteArray = input.terrain_buildable
	var cost: PackedByteArray = input.move_cost
	var cols: int = input.map_cols
	var foot_base: int = FOOT * cols * input.map_rows
	for y: int in range(line, line + height):
		for x: int in range(col, col + width):
			var cell: int = y * cols + x
			if (
				cell >= kinds.size()
				or foot_base + cell >= cost.size()
				or cost[foot_base + cell] == 0
			):
				return true
			var kind: int = kinds[cell]
			if kind >= flags.size() or flags[kind] == 0:
				return true
	return false


## Whether the disc of a mobile row touches the footprint rectangle: the squared distance from its
## centre to the nearest point of the rectangle is at most the squared radius.
static func _occupied(input: PlacementInput, col: int, line: int, width: int, height: int) -> bool:
	var tile: int = World.MILLI_PER_TILE
	var left: int = col * tile
	var right: int = (col + width) * tile
	var top: int = line * tile
	var bottom: int = (line + height) * tile
	var types: PackedInt32Array = input.type_index
	var pos_x: PackedInt32Array = input.pos_x
	var pos_y: PackedInt32Array = input.pos_y
	var speeds: PackedInt32Array = input.type_speed
	var radii: PackedInt32Array = input.type_radius
	for row: int in mini(types.size(), mini(pos_x.size(), pos_y.size())):
		var type: int = types[row]
		if _entry(speeds, type) <= 0:
			continue
		var dx: int = maxi(maxi(left - pos_x[row], pos_x[row] - right), 0)
		var dy: int = maxi(maxi(top - pos_y[row], pos_y[row] - bottom), 0)
		var radius: int = _entry(radii, type)
		if dx * dx + dy * dy <= radius * radius:
			return true
	return false


## Whether a footprint tile is unexplored in the player's block of `explored`. A player with no
## block, or a fog whose block is not the map's, has hidden nothing.
static func _unexplored(
	input: PlacementInput, player: int, col: int, line: int, width: int, height: int
) -> bool:
	if (
		player < 1
		or player > input.fog_player_count
		or input.fog_cells != input.map_cols * input.map_rows
	):
		return false
	var base: int = (player - 1) * input.fog_cells
	var seen: PackedByteArray = input.explored
	var cols: int = input.map_cols
	for y: int in range(line, line + height):
		for x: int in range(col, col + width):
			var at: int = base + y * cols + x
			if at >= seen.size() or seen[at] == 0:
				return true
	return false


## TOO_FAR when no own building is within `build_reach_tiles` of the footprint (the Chebyshev gap:
## the larger of the empty tiles between the two rectangles on either axis, 0 when they touch),
## else CAP when the player has `building_cap` buildings or more, else OK.
@warning_ignore("integer_division")
static func _reach_and_cap(
	input: PlacementInput, player: int, col: int, line: int, width: int, height: int
) -> int:
	var owners: PackedInt32Array = input.owner
	var types: PackedInt32Array = input.type_index
	var pos_x: PackedInt32Array = input.pos_x
	var pos_y: PackedInt32Array = input.pos_y
	var foot_w: PackedInt32Array = input.type_foot_w
	var foot_h: PackedInt32Array = input.type_foot_h
	var reach: int = input.build_reach_tiles
	var count: int = 0
	var near: bool = false
	for row: int in mini(owners.size(), mini(types.size(), mini(pos_x.size(), pos_y.size()))):
		var wide: int = _entry(foot_w, types[row])
		var tall: int = _entry(foot_h, types[row])
		if owners[row] != player or wide <= 0 or tall <= 0:
			continue
		count += 1
		var origin_x: int = (pos_x[row] - wide * World.TILE_CENTRE) / World.MILLI_PER_TILE
		var origin_y: int = (pos_y[row] - tall * World.TILE_CENTRE) / World.MILLI_PER_TILE
		var gap_x: int = maxi(maxi(origin_x - (col + width), col - (origin_x + wide)), 0)
		var gap_y: int = maxi(maxi(origin_y - (line + height), line - (origin_y + tall)), 0)
		near = near or maxi(gap_x, gap_y) <= reach
	if not near:
		return Reason.TOO_FAR
	return Reason.CAP if count >= input.building_cap else Reason.OK


## `table[index]`, or 0 past the table.
static func _entry(table: PackedInt32Array, index: int) -> int:
	return table[index] if index >= 0 and index < table.size() else 0
