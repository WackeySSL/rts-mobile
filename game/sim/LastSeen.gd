class_name LastSeen
extends RefCounted
## The last-seen building records (ADR 0017 sections 3 and 5, plan rows P77 and P77b): MEMORY, the
## last phase of a tick, updates the records of the players whose fog turn FOG ran this tick
## (`FogUpdate`'s rule: player p on the ticks with `(tick - p + 1) % fog_period_ticks == 0`), so a
## player's memory moves when its sight does. A record is a building a player saw and has not seen
## gone: its id, type, owner and cell (the tile of its footprint centre, the row's `fog_cell`; the
## footprint follows from the cell and the type's size, as the view draws it). Record `i` of player
## `p` is entry `p * ghost_cap + i` of the four record arrays of `World.GHOST_ARRAYS`, live below
## `ghost_count[p]`. The records are history: hashed, live entries only (`WorldHash`), and nothing
## in the sim reads them; `PlayerView` copies a player's block, and the view draws them (plan row
## P115c). The phase is GDScript only (ADR 0017 section 8).
##
## A building is seen when any cell of its footprint is visible to the player (P77b), the rule of
## `BuildingLayer.is_seen` and `any_cell_seen`: a building seen at a corner is remembered, and a
## record is forgotten when a corner of the spot is seen empty. A footprint is at most 3 x 3 tiles.
##
## One fog turn of a player, in this order:
## - Forget. A record with a cell of its footprint visible to the player now and whose building has
##   no row any more is dropped: the player looked at the spot and the building is not there. One
##   that dies out of sight stays remembered until the spot is seen again, and a building that is
##   still there is never dropped, seen or not.
## - Remember. Each enemy building (a row of a type with a footprint, owned by a player other than
##   this one and not by the neutral 0, the enemy rule of `Targeting`) with a cell visible to the
##   player now and that has no record yet gets one, in ascending row order. A player whose block is
##   full (`ghost_cap`) remembers no more until a record goes, so which buildings are left out is
##   the same in every run. A building the player sees stays recorded while it stands, so a record
##   is already there when it leaves the player's sight or dies out of it.
##
## A building that dies in sight is dropped when it dies, not on the player's next turn
## (`forget_dead`, called by `World.remove_dead` before its compaction, P77b): the sight the player
## has at that moment is the fog as it stands, and the next turn may already show another one, so
## the turn could not tell a spot watched falling from one never seen. No ghost stands on the crater
## of a building the player watched fall, whatever it sees at its next turn.
##
## Order. Records keep their places (a stable compaction, no swap-remove), the slots the compaction
## frees are zeroed so that the arrays hold nothing past the count, and new records append in
## ascending building id. A World whose fog has no cells, or sides that do not make them (nothing
## is hidden there, as in `FogUpdate.run`), keeps no records.
##
## Cost. One pass over a player's records and one over the building rows, with a scan of the
## player's records for each building it sees (at most `ghost_cap`), on the player's turn only, so
## it costs nothing on the others and a World with no buildings pays for the player loop; a
## footprint scan (9 cells at most) comes with each record and building row looked at. A tick in
## which a building dies adds, for each other player, a pass over its records. Each record and each
## building row looked at counts one `Stat.MEMORY_CHECKS`. No allocation.


## One MEMORY phase: every player whose fog turn this is forgets, then remembers (see the header).
static func run(world: World) -> void:
	if not _can_keep(world):
		return
	var counts: PackedInt32Array = world.ghost_count
	var period: int = maxi(world.fog_period_ticks, 1)
	var tick: int = world.tick
	var checks: int = 0
	for player: int in range(1, mini(world.fog.player_count, counts.size() - 1) + 1):
		if (tick - player + 1) % period == 0:
			checks += _forget(world, player) + _remember(world, player)
	world.stats[World.Stat.MEMORY_CHECKS] += checks


## The in-sight drop (plan row P77b): called by `World.remove_dead` before its compaction, for the
## rows from `first` on. For each building among them that has hp of 0 or less, the records of it in
## the blocks of the other players are dropped where the player sees a cell of its footprint in the
## fog as it stands (the sight the player has when the building falls, see the header). A record
## whose spot is dark is left, and a unit's death changes nothing. The block closes up in order.
static func forget_dead(world: World, first: int) -> void:
	if not _can_keep(world):
		return
	var alive: PackedInt32Array = world.hp
	var types: PackedInt32Array = world.type_index
	var owners: PackedInt32Array = world.owner
	var widths: PackedInt32Array = world.type_foot_w
	var players: int = mini(world.fog.player_count, world.ghost_count.size() - 1)
	var checks: int = 0
	for row: int in range(first, alive.size()):
		if alive[row] > 0 or types[row] >= widths.size() or widths[types[row]] <= 0:
			continue
		for player: int in range(1, players + 1):
			if player != owners[row]:
				checks += _drop_seen(world, player, world.unit_id[row])
	world.stats[World.Stat.MEMORY_CHECKS] += checks


## Drops the records of `player` with a cell of their footprint visible to it and whose building has
## no row, keeps the others in place, zeroes the freed slots and returns how many records it looked
## at.
static func _forget(world: World, player: int) -> int:
	var counts: PackedInt32Array = world.ghost_count
	var ids: PackedInt32Array = world.ghost_id
	var types: PackedInt32Array = world.ghost_type
	var owners: PackedInt32Array = world.ghost_owner
	var cells: PackedInt32Array = world.ghost_cell
	var rows: PackedInt32Array = world.unit_id
	var widths: PackedInt32Array = world.type_foot_w
	var heights: PackedInt32Array = world.type_foot_h
	var fog: FogGrid = world.fog
	var visible: PackedInt32Array = fog.visible
	var block: int = (player - 1) * fog.cells
	var first: int = player * world.ghost_cap
	var count: int = counts[player]
	var kept: int = 0
	for record: int in count:
		var entry: int = first + record
		var cell: int = cells[entry]
		var type: int = types[entry]
		if _any_seen(visible, block, fog.cols, fog.rows, cell, widths[type], heights[type]):
			var at: int = rows.bsearch(ids[entry])
			if at >= rows.size() or rows[at] != ids[entry]:
				continue
		if kept != record:
			ids[first + kept] = ids[entry]
			types[first + kept] = types[entry]
			owners[first + kept] = owners[entry]
			cells[first + kept] = cell
		kept += 1
	for entry: int in range(first + kept, first + count):
		ids[entry] = 0
		types[entry] = 0
		owners[entry] = 0
		cells[entry] = 0
	counts[player] = kept
	return count


## Gives `player` a record for each enemy building it sees now (a cell of its footprint is visible)
## that it has none for, in ascending row order, until its block is full; returns how many building
## rows it looked at. The derived building list is brought up to date first (a no-op when
## `rows_version` has not moved since ECONOMY rebuilt it).
@warning_ignore("integer_division")
static func _remember(world: World, player: int) -> int:
	Buildings.rebuild_lists(world)
	var counts: PackedInt32Array = world.ghost_count
	var ids: PackedInt32Array = world.ghost_id
	var types: PackedInt32Array = world.ghost_type
	var owners: PackedInt32Array = world.ghost_owner
	var cells: PackedInt32Array = world.ghost_cell
	var unit_ids: PackedInt32Array = world.unit_id
	var row_owners: PackedInt32Array = world.owner
	var row_types: PackedInt32Array = world.type_index
	var widths: PackedInt32Array = world.type_foot_w
	var heights: PackedInt32Array = world.type_foot_h
	var xs: PackedInt32Array = world.pos_x
	var ys: PackedInt32Array = world.pos_y
	var fog: FogGrid = world.fog
	var visible: PackedInt32Array = fog.visible
	var cols: int = fog.cols
	var lines: int = fog.rows
	var block: int = (player - 1) * fog.cells
	var cap: int = world.ghost_cap
	var first: int = player * cap
	var count: int = counts[player]
	var looked: int = 0
	for row: int in world.building_rows:
		if count >= cap:
			break
		looked += 1
		var owner: int = row_owners[row]
		if owner == player or owner < 1:
			continue
		var cell: int = (
			clampi(ys[row] / World.MILLI_PER_TILE, 0, lines - 1) * cols
			+ clampi(xs[row] / World.MILLI_PER_TILE, 0, cols - 1)
		)
		var type: int = row_types[row]
		if not _any_seen(visible, block, cols, lines, cell, widths[type], heights[type]):
			continue
		var id: int = unit_ids[row]
		var known: bool = false
		for record: int in count:
			if ids[first + record] == id:
				known = true
				break
		if known:
			continue
		ids[first + count] = id
		types[first + count] = type
		owners[first + count] = owner
		cells[first + count] = cell
		count += 1
	counts[player] = count
	return looked


## Drops the record of building `id` from the block of `player` when the player sees a cell of its
## footprint now, closing the block up in order and zeroing the freed place; returns how many
## records it looked at (all of them when there is none).
static func _drop_seen(world: World, player: int, id: int) -> int:
	var ids: PackedInt32Array = world.ghost_id
	var types: PackedInt32Array = world.ghost_type
	var owners: PackedInt32Array = world.ghost_owner
	var cells: PackedInt32Array = world.ghost_cell
	var fog: FogGrid = world.fog
	var first: int = player * world.ghost_cap
	var count: int = world.ghost_count[player]
	for record: int in count:
		var entry: int = first + record
		if ids[entry] != id:
			continue
		var type: int = types[entry]
		var width: int = world.type_foot_w[type]
		var height: int = world.type_foot_h[type]
		if _any_seen(
			fog.visible, (player - 1) * fog.cells, fog.cols, fog.rows, cells[entry], width, height
		):
			for at: int in range(entry, first + count - 1):
				ids[at] = ids[at + 1]
				types[at] = types[at + 1]
				owners[at] = owners[at + 1]
				cells[at] = cells[at + 1]
			ids[first + count - 1] = 0
			types[first + count - 1] = 0
			owners[first + count - 1] = 0
			cells[first + count - 1] = 0
			world.ghost_count[player] = count - 1
		return record + 1
	return count


## Whether the fog has `visible` above 0 on a cell of the `width` x `height` footprint whose centre
## tile is `cell`, in the block that starts at `base` of a grid `cols` cells wide and `lines` lines
## tall: `BuildingLayer.any_cell_seen` on the footprint `footprint_at` gives, clipped to the map. A
## footprint of 1 x 1 is the cell itself.
@warning_ignore("integer_division")
static func _any_seen(
	visible: PackedInt32Array, base: int, cols: int, lines: int, cell: int, width: int, height: int
) -> bool:
	var col0: int = cell % cols - width / 2
	var line0: int = cell / cols - height / 2
	for line: int in range(maxi(line0, 0), mini(line0 + height, lines)):
		for col: int in range(maxi(col0, 0), mini(col0 + width, cols)):
			if visible[base + line * cols + col] > 0:
				return true
	return false


## Whether the World can keep records: a fog whose cells make `rows` lines of `cols` (as in
## `FogUpdate.run`), and a block of at least one record for every player.
@warning_ignore("integer_division")
static func _can_keep(world: World) -> bool:
	var fog: FogGrid = world.fog
	return (
		fog.cols >= 1
		and fog.rows >= 1
		and fog.cells % fog.cols == 0
		and fog.cells / fog.cols == fog.rows
		and world.ghost_cap >= 1
		and world.ghost_id.size() >= world.ghost_count.size() * world.ghost_cap
	)
