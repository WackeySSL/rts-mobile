class_name Mines
extends RefCounted
## Mines, laying and blasting (ADR 0037 section 8; P287). Integers only, GDScript only.
##
## LAY_MINE (`apply_lay`): the own mobile rows whose type has a mine weapon (`type_mine_weapon`
## above -1) get MOVE to a formation slot round the point with `carry_mode` LAYING and a cleared
## `ready_tick`. Every order-giving Command zeroes `carry_mode`, so a new order cancels a pending
## lay, unpaid. `lay`, in ECONOMY after `Mend.run`, runs the rows of mode LAYING that have stopped
## (order IDLE), in ascending row order: with `ready_tick` 0 the start checks the layer's own cell
## (`_allowed`: FOOT-passable, so outside every footprint, no mine on it, a ground-layer type, the
## owner below `mine_cap`, credits for `type_mine_cost`) and sets `ready_tick` to the stamp plus
## `mine_lay_ticks`; at the stamp every check runs again, then the cost is paid and the mine joins
## the table (`_add`, armed `mine_arm_ticks` later). A failed check at either point sets the mode
## to 0, pays nothing and counts `stats[MINES_REFUSED]`. Pending lays do not count toward the cap.
## The stamp is `world.tick + 1`, as `Strike.run` and `Production` read it.
##
## `run`, in FIRE after `Strike.run`, only while an armed mine exists: the mark pass lets every
## mobile ground row of a non-neutral player other than the owner, of a type that is not
## mine-aware, trigger the armed mine on its cell (`mine_at`); the blast pass, mines ascending,
## hurts every such row within the weapon's `weapon_blast_milli` of the cell centre with
## `Strike._land`'s formula (`Combat.damage`), buildings take none, and writes one MINE_BLAST
## record `[7, mine id, x, y, weapon, owner, 0, 0]` per mine; then one stable compaction. The mark
## is the sentinel GONE in `mine_armed_tick`, which no live mine holds and no tick outlives (the
## compaction drops every one). `stats[MINE_CHECKS]` counts the rows the mark pass looked up.
## `clear_radius` (a rupture) and `clear_footprint` (a placed building) drop mines with no blast.
## `mine_at` holds the table index + 1 of a mine's cell and is written sparsely, never filled.

## The `carry_mode` of a layer that goes to its point and lays there (ADR 0036's UNLOAD is 1).
const LAYING: int = 2
## `mine_armed_tick` of a mine that is leaving the table in this call.
const GONE: int = -1


## LAY_MINE: `unit_ids` are own, living, complete mobile rows of a type with a mine weapon (others
## are skipped silently), `target_x`/`target_y` the point in milli-tiles. None valid: false, and
## the command is dropped and counted.
static func apply_lay(world: World, command: Command) -> bool:
	if command.unit_ids.size() > Command.MAX_UNITS:
		return false
	var ids: PackedInt32Array = command.unit_ids.duplicate()
	ids.sort()
	var rows: PackedInt32Array = PackedInt32Array()
	var previous: int = 0
	for id: int in ids:
		if id == previous:
			continue
		previous = id
		var row: int = world.index_of(id)
		if row >= 0 and _can_lay(world, row, command.player_id):
			rows.append(row)
	if rows.is_empty():
		return false
	Formation.assign(world, rows, command.target_x, command.target_y)
	for row: int in rows:
		world.order[row] = World.Order.MOVE
	Movement.reset_nav(world, rows, World.NavMode.DIRECT)
	Harvest.release(world, rows)
	Carry.release(world, rows)  # Zeroes `carry_mode`, then the mode is set.
	for row: int in rows:
		world.carry_mode[row] = LAYING
		world.ready_tick[row] = 0
	return true


## ECONOMY, after `Mend.run`: the start and the lay tick of every layer that has arrived.
static func lay(world: World) -> void:
	if world.mine_cap <= 0 or world.mine_at.is_empty():
		return
	var stamp: int = world.tick + 1
	var modes: PackedInt32Array = world.carry_mode
	var orders: PackedInt32Array = world.order
	var due: PackedInt32Array = world.ready_tick
	var life: PackedInt32Array = world.hp
	for row: int in world.unit_id.size():
		if modes[row] != LAYING or orders[row] != World.Order.IDLE or life[row] <= 0:
			continue
		if due[row] == 0:
			if _allowed(world, row):
				due[row] = stamp + world.mine_lay_ticks
			else:
				_refuse(world, row)
		elif stamp >= due[row]:
			if _allowed(world, row):
				_add(world, row, stamp)
			else:
				_refuse(world, row)


## FIRE, after `Strike.run`: trigger, blast and compact (see the header).
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var count: int = mini(world.mine_count, world.mine_id.size())
	var stamp: int = world.tick + 1
	var armed_at: PackedInt32Array = world.mine_armed_tick
	var any: bool = false
	for index: int in count:
		any = any or armed_at[index] <= stamp
	if not any:
		return
	var marked: int = _mark(world, count, stamp)
	if marked == 0:
		return
	for index: int in count:
		if armed_at[index] == GONE:
			_blast(world, index)
	_compact(world, count)


## A rupture: every mine of any owner whose cell centre is within `radius` milli-tiles of the
## point goes, with no blast.
static func clear_radius(world: World, point_x: int, point_y: int, radius: int) -> void:
	var count: int = mini(world.mine_count, world.mine_id.size())
	var reach: int = radius * radius
	var gone: int = 0
	for index: int in count:
		var dx: int = _centre_x(world, world.mine_cell[index]) - point_x
		var dy: int = _centre_y(world, world.mine_cell[index]) - point_y
		if dx * dx + dy * dy <= reach:
			world.mine_armed_tick[index] = GONE
			gone += 1
	if gone > 0:
		_compact(world, count)


## A building placed over the tiles `col`..`col + width - 1`, `line`..`line + height - 1`: the
## mines on them go silently, whoever owns them.
@warning_ignore("integer_division")
static func clear_footprint(world: World, col: int, line: int, width: int, height: int) -> void:
	var count: int = mini(world.mine_count, world.mine_id.size())
	if count <= 0:
		return
	var gone: int = 0
	for index: int in count:
		var cell: int = world.mine_cell[index]
		var x: int = cell % world.map_cols
		var y: int = cell / world.map_cols
		if x >= col and x < col + width and y >= line and y < line + height:
			world.mine_armed_tick[index] = GONE
			gone += 1
	if gone > 0:
		_compact(world, count)


## Whether row `row` may be sent to lay for `player`.
static func _can_lay(world: World, row: int, player: int) -> bool:
	var type: int = world.type_index[row]
	return (
		world.owner[row] == player
		and world.hp[row] > 0
		and world.build_left[row] == 0
		and type < world.type_mine_weapon.size()
		and world.type_mine_weapon[type] >= 0
		and world.type_speed[type] > 0
	)


## Every check of a lay, on the layer's own cell now.
static func _allowed(world: World, row: int) -> bool:
	var type: int = world.type_index[row]
	var weapon: int = world.type_mine_weapon[type]
	var owner: int = world.owner[row]
	var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
	if (
		weapon < 0
		or weapon >= world.weapon_damage.size()
		or world.mine_count >= world.mine_id.size()
		or cell >= world.mine_at.size()
		or world.mine_at[cell] != 0
		or (world.type_layer_bit[type] & World.Layer.GROUND) == 0
		or not world.is_passable(cell, World.MoveClass.FOOT)
		or owner >= world.credits.size()
		or world.credits[owner] < world.type_mine_cost[type]
	):
		return false
	var owned: int = 0
	for index: int in world.mine_count:
		owned += int(world.mine_owner[index] == owner)
	return owned < world.mine_cap


## Counts a refusal and ends the order.
static func _refuse(world: World, row: int) -> void:
	world.carry_mode[row] = 0
	world.ready_tick[row] = 0
	world.stats[World.Stat.MINES_REFUSED] += 1


## Pays and appends the mine of layer `row` on its cell; the order is over.
static func _add(world: World, row: int, stamp: int) -> void:
	var type: int = world.type_index[row]
	var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
	var at: int = world.mine_count
	world.credits[world.owner[row]] -= world.type_mine_cost[type]
	world.mine_id[at] = world.next_mine_id
	world.mine_owner[at] = world.owner[row]
	world.mine_cell[at] = cell
	world.mine_weapon[at] = world.type_mine_weapon[type]
	world.mine_armed_tick[at] = stamp + world.mine_arm_ticks
	world.mine_at[cell] = at + 1
	world.next_mine_id += 1
	world.mine_count += 1
	world.carry_mode[row] = 0
	world.ready_tick[row] = 0


## The mark pass: marks (GONE) each armed mine that a trigger stands on; returns the marked count.
static func _mark(world: World, count: int, stamp: int) -> int:
	var marked: int = 0
	var types: PackedInt32Array = world.type_index
	var owners: PackedInt32Array = world.owner
	var life: PackedInt32Array = world.hp
	var layer_bit: PackedInt32Array = world.type_layer_bit
	var speeds: PackedInt32Array = world.type_speed
	var aware: PackedInt32Array = world.type_mine_aware
	var grid: PackedInt32Array = world.mine_at
	var armed_at: PackedInt32Array = world.mine_armed_tick
	for row: int in world.unit_id.size():
		var type: int = types[row]
		if (
			owners[row] == 0
			or life[row] <= 0
			or speeds[type] <= 0
			or (layer_bit[type] & World.Layer.GROUND) == 0
			or aware[type] != 0
		):
			continue
		var index: int = grid[world.cell_of(world.pos_x[row], world.pos_y[row])] - 1
		world.stats[World.Stat.MINE_CHECKS] += 1
		if index < 0 or index >= count or owners[row] == world.mine_owner[index]:
			continue
		if armed_at[index] <= stamp and armed_at[index] != GONE:
			armed_at[index] = GONE
			marked += 1
	return marked


## One mine's blast: `Strike._land`'s formula on every ground mobile row of another player.
@warning_ignore("integer_division")
static func _blast(world: World, index: int) -> void:
	var weapon: int = world.mine_weapon[index]
	var cell: int = world.mine_cell[index]
	var point_x: int = _centre_x(world, cell)
	var point_y: int = _centre_y(world, cell)
	_push_event(world, index, point_x, point_y)
	if weapon < 0 or weapon >= mini(world.weapon_damage.size(), world.weapon_blast_milli.size()):
		return
	var radius: int = world.weapon_blast_milli[weapon]
	var reach: int = radius * radius
	var base: int = world.weapon_damage[weapon]
	var shares: int = weapon * World.Armour.size()
	var percent_of: PackedInt32Array = world.weapon_vs_armour
	var armour_of: PackedInt32Array = world.type_armour
	var types: PackedInt32Array = world.type_index
	var layer_bit: PackedInt32Array = world.type_layer_bit
	var speeds: PackedInt32Array = world.type_speed
	var owners: PackedInt32Array = world.owner
	var hit_points: PackedInt32Array = world.hp
	var xs: PackedInt32Array = world.pos_x
	var ys: PackedInt32Array = world.pos_y
	var owner: int = world.mine_owner[index]
	for row: int in hit_points.size():
		var type: int = types[row]
		if owners[row] == 0 or owners[row] == owner or speeds[type] <= 0:
			continue
		if (layer_bit[type] & World.Layer.GROUND) == 0:
			continue
		var dx: int = xs[row] - point_x
		var dy: int = ys[row] - point_y
		if dx * dx + dy * dy > reach:
			continue
		var percent: int = percent_of[shares + armour_of[type]]
		if percent > 0:
			var taken: int = Upgrades.taken(world, owners[row], type)
			hit_points[row] -= Combat.damage(base, percent, Combat.PERCENT, taken)


## Appends `[MINE_BLAST, mine id, x, y, weapon, owner, 0, 0]`.
static func _push_event(world: World, index: int, point_x: int, point_y: int) -> void:
	var events: PackedInt32Array = world.events
	var at: int = events.size()
	events.resize(at + World.EVENT_STRIDE)  # The last two ints of the record stay 0.
	events[at] = World.Event.MINE_BLAST
	events[at + 1] = world.mine_id[index]
	events[at + 2] = point_x
	events[at + 3] = point_y
	events[at + 4] = world.mine_weapon[index]
	events[at + 5] = world.mine_owner[index]


## The stable compaction of the entries marked GONE: their cells clear, each moved entry rewrites
## its own cell, and nothing else of `mine_at` is touched.
static func _compact(world: World, count: int) -> void:
	var armed_at: PackedInt32Array = world.mine_armed_tick
	var kept: int = 0
	for index: int in count:
		var cell: int = world.mine_cell[index]
		if armed_at[index] == GONE:
			world.mine_at[cell] = 0
			continue
		if kept != index:
			for column_name: StringName in World.MINE_ARRAYS:
				var column: PackedInt32Array = world.get(column_name)
				column[kept] = column[index]
			world.mine_at[cell] = kept + 1
		kept += 1
	for column_name: StringName in World.MINE_ARRAYS:  # The freed tail reads 0, as a new table does.
		var tail: PackedInt32Array = world.get(column_name)
		for index: int in range(kept, count):
			tail[index] = 0
	world.mine_count = kept


@warning_ignore("integer_division")
static func _centre_x(world: World, cell: int) -> int:
	return (cell % world.map_cols) * World.MILLI_PER_TILE + World.TILE_CENTRE


@warning_ignore("integer_division")
static func _centre_y(world: World, cell: int) -> int:
	return (cell / world.map_cols) * World.MILLI_PER_TILE + World.TILE_CENTRE
