extends RefCounted
## fog.visible rebuilt from the rows (plan P65, ADR 0016). `visible` is derived state and is not in
## the state hash: every count is the number of a player's stamped rows whose sight disc covers the
## cell, and the rows (`owner`, `type_index`, `fog_cell`) and the sight table are in the hash or in
## defs_hash. This file is the rebuild, so that a test can hold a World to it.
##
## The rule, written from its definition and not from FogGrid, FogUpdate or the C++: a row with a
## stamped cell (`fog_cell` >= 0) of a player in 1..player_count adds 1 to the player's block on
## every in-map tile whose centre is within the sight of its type of the centre of the tile
## `fog_cell`, (dx * 1000)^2 + (dy * 1000)^2 <= sight^2, found by testing every tile of the square
## around the cell, so it shares no mask table with the code under test. The sight is the entry of
## World.type_sight for the row's type, and World.TYPE_PAD_SIGHT for a type with no entry (the pad
## mask). A row with no stamped cell, and a row of the neutral player or past player_count, has no
## disc. A grid whose sides do not make its cells has no fog (the phase does nothing there), so a
## caller keeps this out of such a World. Pure: it reads the World and writes nothing. Not a test
## suite.

const TILE: int = World.MILLI_PER_TILE

## The counts that the rows of `world` say, in the layout of fog.visible: (player - 1) * cells +
## cell.
@warning_ignore("integer_division")
static func rebuild(world: World) -> PackedInt32Array:
	var fog: FogGrid = world.fog
	var cols: int = fog.cols
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(fog.player_count * fog.cells)
	if cols < 1:
		return counts
	var sights: PackedInt32Array = world.type_sight
	for row: int in world.owner.size():
		var player: int = world.owner[row]
		var stamped: int = world.fog_cell[row]
		if stamped < 0 or player < 1 or player > fog.player_count:
			continue
		var kind: int = world.type_index[row]
		var sight: int = sights[kind] if kind < sights.size() else World.TYPE_PAD_SIGHT
		var squared: int = sight * sight
		var reach: int = sight / TILE
		var centre_x: int = stamped % cols
		var centre_y: int = stamped / cols
		var base: int = (player - 1) * fog.cells
		for y: int in range(maxi(centre_y - reach, 0), mini(centre_y + reach, fog.rows - 1) + 1):
			var dy: int = (y - centre_y) * TILE
			for x: int in range(maxi(centre_x - reach, 0), mini(centre_x + reach, cols - 1) + 1):
				var dx: int = (x - centre_x) * TILE
				if dx * dx + dy * dy <= squared:
					counts[base + y * cols + x] += 1
	return counts


## "" when fog.visible of `world` equals rebuild(world), else the first cell that differs (its
## player, tile and both counts) or the sizes.
@warning_ignore("integer_division")
static func mismatch(world: World) -> String:
	var fog: FogGrid = world.fog
	var want: PackedInt32Array = rebuild(world)
	if fog.visible == want:
		return ""
	if fog.visible.size() != want.size():
		return "visible holds %d counts, the rows say %d" % [fog.visible.size(), want.size()]
	for at: int in want.size():
		if fog.visible[at] != want[at]:
			return (
				"player %d, tile %d: visible %d, the rows say %d"
				% [at / fog.cells + 1, at % fog.cells, fog.visible[at], want[at]]
			)
	return ""
