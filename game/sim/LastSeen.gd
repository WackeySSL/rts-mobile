class_name LastSeen
extends RefCounted
## The last-seen building records (ADR 0017 sections 3 and 5, plan row P77): MEMORY, the last phase
## of a tick, updates the records of the players whose fog turn FOG ran this tick (`FogUpdate`'s
## rule: player p on the ticks with `(tick - p + 1) % fog_period_ticks == 0`), so a player's memory
## moves exactly when its sight does. A record is a building a player saw and has not seen gone:
## its id, type, owner and cell (the tile that holds the building, the tile of its footprint
## centre, which is the cell `Targeting.sees` asks and the row's `fog_cell`). Record `i` of player
## `p` is entry `p * ghost_cap + i` of the four record arrays of `World.GHOST_ARRAYS`, live below
## `ghost_count[p]`. The records are history: hashed, live entries only (`WorldHash`), and nothing
## in the sim reads them; `PlayerView` copies a player's block, and the view draws them (plan row
## P115c). The phase is GDScript only (ADR 0017 section 8).
##
## One fog turn of a player, in this order:
## - Forget. A record whose cell the player sees now and whose building has no row any more is
##   dropped: the player looked at the spot and the building is not there. A building that dies in
##   sight is dropped on the player's next turn, one that dies out of sight stays remembered until
##   the cell is seen again, and a building that is still there is never dropped, seen or not.
## - Remember. Each enemy building (a row of a type with a footprint, owned by a player other than
##   this one and not by the neutral 0, the enemy rule of `Targeting`) whose cell the player sees
##   now and that has no record yet gets one, in ascending row order. A player whose block is full
##   (`ghost_cap`) remembers no more until a record goes, so which buildings are left out is the
##   same in every run. A building the player sees stays recorded while it stands, so a record is
##   already there when it leaves the player's sight or dies out of it.
##
## Order. Records keep their places (a stable compaction, no swap-remove), the slots the compaction
## frees are zeroed so that the arrays hold nothing past the count, and new records append in
## ascending building id. A World whose fog has no cells, or sides that do not make them (nothing
## is hidden there, as in `FogUpdate.run`), keeps no records.
##
## Cost. One pass over a player's records and one over the building rows, with a scan of the
## player's records for each building it sees (at most `ghost_cap`), on the player's turn only, so
## it costs nothing on the others and a World with no buildings pays for the player loop. Each
## record and each building row looked at counts one `Stat.MEMORY_CHECKS`. No allocation.

## One MEMORY phase: every player whose fog turn this is forgets, then remembers (see the header).
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var fog: FogGrid = world.fog
	var counts: PackedInt32Array = world.ghost_count
	var cap: int = world.ghost_cap
	var cols: int = fog.cols
	if (
		cols < 1
		or fog.rows < 1
		or fog.cells % cols != 0
		or fog.cells / cols != fog.rows
		or cap < 1
		or world.ghost_id.size() < counts.size() * cap
	):
		return
	var period: int = maxi(world.fog_period_ticks, 1)
	var tick: int = world.tick
	var checks: int = 0
	for player: int in range(1, mini(fog.player_count, counts.size() - 1) + 1):
		if (tick - player + 1) % period == 0:
			checks += _forget(world, player) + _remember(world, player)
	world.stats[World.Stat.MEMORY_CHECKS] += checks


## Drops the records of `player` whose cell is visible to it and whose building has no row, keeps
## the others in place, zeroes the freed slots and returns how many records it looked at.
static func _forget(world: World, player: int) -> int:
	var counts: PackedInt32Array = world.ghost_count
	var ids: PackedInt32Array = world.ghost_id
	var types: PackedInt32Array = world.ghost_type
	var owners: PackedInt32Array = world.ghost_owner
	var cells: PackedInt32Array = world.ghost_cell
	var rows: PackedInt32Array = world.unit_id
	var visible: PackedInt32Array = world.fog.visible
	var block: int = (player - 1) * world.fog.cells
	var first: int = player * world.ghost_cap
	var count: int = counts[player]
	var kept: int = 0
	for record: int in count:
		var entry: int = first + record
		var cell: int = cells[entry]
		if visible[block + cell] > 0:
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


## Gives `player` a record for each enemy building it sees now that it has none for, in ascending
## row order, until its block is full; returns how many building rows it looked at. The derived
## building list is brought up to date first (a no-op when `rows_version` has not moved since
## ECONOMY rebuilt it).
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
		if visible[block + cell] <= 0:
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
		types[first + count] = row_types[row]
		owners[first + count] = owner
		cells[first + count] = cell
		count += 1
	counts[player] = count
	return looked
