class_name MineMemory
extends RefCounted
## What a player knows of the other players' mines (ADR 0037 section 8; P288). MEMORY, after
## `LastSeen.run`, on the player's fog turn (`FogUpdate`'s rule: player p on the ticks with
## `(tick - p + 1) % fog_period_ticks == 0`). A record is one mine a player found and has not seen
## gone: its id, owner and cell, entry `p * mine_known_cap + i` of the `mine_seen_*` arrays, live
## below `mine_seen_count[p]`, in the order the mines were found. The owner of a mine knows it
## without a record. Integers only, GDScript only, no allocation.
##
## One fog turn of a player, in this order:
## - Forget. A record whose cell the player sees now and whose mine is gone (no mine on the cell,
##   or one of another id) is dropped: it looked at the spot and the mine is not there. A mine
##   that goes out of sight stays remembered until the spot is seen again. The block closes up in
##   order and the freed place reads 0.
## - Remember. Each mine of another player (ascending mine id) whose cell the player sees now, with
##   no record of it yet, and that lies within `type_detect_milli` of a living row of the player
##   (a detector: a type with a detect range above 0) gets a record, until the block is full
##   (`mine_known_cap`), so which mines are left out is the same in every run. A blast makes no
##   record. One pass over the rows lists the player's living detectors (scratch column `push_x`),
##   none: stop. Each distance test of a listed detector against a mine counts one
##   `Stat.MINE_CHECKS`, so the cost is rows + detectors x mines on the player's turn, counted as
##   detectors x mines, and nothing on the others.
## `knows` is the question the sweep asks; `drop_seen` is the in-sight drop of a mine that leaves.


## One MEMORY phase for `world` (after `LastSeen.run`).
static func run(world: World) -> void:
	if not _can_keep(world):
		return
	var period: int = maxi(world.fog_period_ticks, 1)
	var tick: int = world.tick
	var checks: int = 0
	for player: int in range(1, mini(world.fog.player_count, world.mine_seen_count.size() - 1) + 1):
		if (tick - player + 1) % period == 0:
			_forget(world, player)
			checks += _remember(world, player)
	world.stats[World.Stat.MINE_CHECKS] += checks


## Whether `player` has a record of the mine `id`.
static func knows(world: World, player: int, id: int) -> bool:
	var cap: int = world.mine_known_cap
	var ids: PackedInt32Array = world.mine_seen_id
	if player < 1 or player >= world.mine_seen_count.size() or cap < 1:
		return false
	var first: int = player * cap
	var count: int = mini(world.mine_seen_count[player], cap)
	if first + count > ids.size():
		return false
	for record: int in count:
		if ids[first + record] == id:
			return true
	return false


## The in-sight drop, called by `Mines._compact` for each mine leaving the table (blast, sweep,
## rupture, building): the record of mine `id` goes from every player's block that sees `cell` in
## the fog as it stands, so a spot watched while its mine blew is not remembered as mined, whatever
## the next fog turn shows (`LastSeen.forget_dead`'s rule). Event cadence.
static func drop_seen(world: World, id: int, cell: int) -> void:
	if not _can_keep(world):
		return
	var cap: int = world.mine_known_cap
	var visible: PackedInt32Array = world.fog.visible
	var ids: PackedInt32Array = world.mine_seen_id
	var owners: PackedInt32Array = world.mine_seen_owner
	var cells: PackedInt32Array = world.mine_seen_cell
	for player: int in range(1, mini(world.fog.player_count, world.mine_seen_count.size() - 1) + 1):
		if visible[(player - 1) * world.fog.cells + cell] <= 0:
			continue
		var first: int = player * cap
		var count: int = mini(world.mine_seen_count[player], cap)
		for record: int in count:
			if ids[first + record] != id:
				continue
			for at: int in range(first + record, first + count - 1):
				ids[at] = ids[at + 1]
				owners[at] = owners[at + 1]
				cells[at] = cells[at + 1]
			ids[first + count - 1] = 0
			owners[first + count - 1] = 0
			cells[first + count - 1] = 0
			world.mine_seen_count[player] = count - 1
			break


## Drops the records of `player` that it sees empty, closing the block up in order.
static func _forget(world: World, player: int) -> void:
	var counts: PackedInt32Array = world.mine_seen_count
	var ids: PackedInt32Array = world.mine_seen_id
	var owners: PackedInt32Array = world.mine_seen_owner
	var cells: PackedInt32Array = world.mine_seen_cell
	var at: PackedInt32Array = world.mine_at
	var table: PackedInt32Array = world.mine_id
	var visible: PackedInt32Array = world.fog.visible
	var block: int = (player - 1) * world.fog.cells
	var first: int = player * world.mine_known_cap
	var count: int = counts[player]
	var kept: int = 0
	var mines: int = world.mine_count
	for record: int in count:
		var entry: int = first + record
		var cell: int = cells[entry]
		if visible[block + cell] > 0:
			var index: int = at[cell] - 1
			if index < 0 or index >= mines or table[index] != ids[entry]:
				continue
		if kept != record:
			ids[first + kept] = ids[entry]
			owners[first + kept] = owners[entry]
			cells[first + kept] = cell
		kept += 1
	for entry: int in range(first + kept, first + count):
		ids[entry] = 0
		owners[entry] = 0
		cells[entry] = 0
	counts[player] = kept


## Gives `player` a record for each mine of another player that a detector of it reaches (see the
## header); returns the distance tests made. One pass over the rows lists the living detectors in
## the scratch column `push_x` (free in MEMORY; SEPARATION clears it), then the mines ascending
## test only those, so the cost is rows + detectors x mines and the count is detectors x mines.
@warning_ignore("integer_division")
static func _remember(world: World, player: int) -> int:
	var cap: int = world.mine_known_cap
	var count: int = world.mine_seen_count[player]
	var total: int = mini(world.mine_count, world.mine_id.size())
	var listed: PackedInt32Array = world.push_x
	var rows_owner: PackedInt32Array = world.owner
	if count >= cap or total <= 0 or listed.size() < rows_owner.size():
		return 0
	var rows_hp: PackedInt32Array = world.hp
	var rows_type: PackedInt32Array = world.type_index
	var detect: PackedInt32Array = world.type_detect_milli
	var xs: PackedInt32Array = world.pos_x
	var ys: PackedInt32Array = world.pos_y
	var detectors: int = 0
	for row: int in rows_owner.size():
		if rows_owner[row] == player and rows_hp[row] > 0 and detect[rows_type[row]] > 0:
			listed[detectors] = row
			detectors += 1
	if detectors == 0:
		return 0
	var ids: PackedInt32Array = world.mine_seen_id
	var owners: PackedInt32Array = world.mine_seen_owner
	var cells: PackedInt32Array = world.mine_seen_cell
	var visible: PackedInt32Array = world.fog.visible
	var block: int = (player - 1) * world.fog.cells
	var first: int = player * cap
	var mine_cells: PackedInt32Array = world.mine_cell
	var mine_ids: PackedInt32Array = world.mine_id
	var mine_owners: PackedInt32Array = world.mine_owner
	var cols: int = world.map_cols
	var checks: int = 0
	for index: int in total:
		if count >= cap:
			break
		var cell: int = mine_cells[index]
		var id: int = mine_ids[index]
		if mine_owners[index] == player or visible[block + cell] <= 0:
			continue
		var known: bool = false
		for record: int in count:
			if ids[first + record] == id:
				known = true
				break
		if known:
			continue
		var point_x: int = (cell % cols) * World.MILLI_PER_TILE + World.TILE_CENTRE
		var point_y: int = (cell / cols) * World.MILLI_PER_TILE + World.TILE_CENTRE
		for at: int in detectors:
			var row: int = listed[at]
			var reach: int = detect[rows_type[row]]
			checks += 1
			var dx: int = xs[row] - point_x
			var dy: int = ys[row] - point_y
			if dx * dx + dy * dy <= reach * reach:
				ids[first + count] = id
				owners[first + count] = mine_owners[index]
				cells[first + count] = cell
				count += 1
				break
	world.mine_seen_count[player] = count
	return checks


## Whether the World can keep records: a fog on the map's grid, a block of at least one record
## for every player, and a mine table.
@warning_ignore("integer_division")
static func _can_keep(world: World) -> bool:
	var fog: FogGrid = world.fog
	return (
		world.mine_cap > 0
		and world.mine_known_cap >= 1
		and fog.cols >= 1
		and fog.cols == world.map_cols
		and fog.cells % fog.cols == 0
		and fog.cells / fog.cols == fog.rows
		and fog.rows == world.map_rows
		and world.mine_seen_id.size() >= world.mine_seen_count.size() * world.mine_known_cap
		and world.mine_seen_owner.size() >= world.mine_seen_id.size()
		and world.mine_seen_cell.size() >= world.mine_seen_id.size()
		and world.mine_at.size() == fog.cells
		and world.mine_id.size() >= world.mine_count
	)
