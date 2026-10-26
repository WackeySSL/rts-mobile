class_name Harvest
extends RefCounted
## The harvest loop and the ore (ADR 0017 section 5, ADR 0018 sections 2 and 3). `run` is the
## second half of ECONOMY, after `Power.run` has rebuilt `harvester_rows` and `building_rows`: ore
## regrowth, then the SEEK, MINE, RETURN and UNLOAD of every harvester, ascending by row. IDLE rows
## are the player's: a unit-group order hands them over (`release`), HARVEST sends them back to work
## at a cell of the player's choice (`apply_harvest`) and the auto-resume does it on its own after
## `harvest_resume_ticks` (plan row P75b).
##
## The loop gives orders the way `Sim._apply_point` does after `Formation.assign`: `order` MOVE, the
## goal, `group_cell` -1 and `Movement.reset_nav` with DIRECT. It reads no input and draws no random
## number. A row takes one step per tick and a change of mode counts from the next tick, except the
## three that give an order at once (`_pick`, the end of UNLOAD, SEEK's full load by `_go_home`).
##
## No column says "the order was given", so SEEK reads it off the state: every way into SEEK with an
## ore cell that has ore gives the order in the same step, hence a SEEK harvester that has no order
## and stands farther than `harvest_reach_milli` from its cell is one whose order ended short. It
## takes another cell (ADR 0018 section 3 says "once more", which has no counter to run on; the
## cell it left is skipped, and a lone cell is tried again after the retry wait). HARVEST and the
## auto-resume therefore give their order in the same step that sets `harvest_slot` and SEEK
## (`_take`: `_order` and the cell's centre). A refinery is a building type with a dock other
## than (0, 0), a tile inside the footprint that no unit can walk to (`BuildingDef.dock` defaults
## to it, meaning none).

## ECONOMY: the ore grows back, then each harvester steps once. Ore: on a tick with
## `tick % ore_regrow_ticks == 0` every cell below `ore_cell_max` gains 1.
## - SEEK: a full load goes to RETURN with the order to the dock at once (`_go_home`), so a walk to
##   an ore cell does not run its course first. A cell with ore and an ended order: within
##   `harvest_reach_milli` of its centre the harvester turns to MINE, farther it picks another
##   cell. No cell, or one that ran empty: `_pick`. With no cell at all (`harvest_slot` -1) it looks
##   only on ticks with `(tick + id) % harvest_retry_ticks == 0`.
## - MINE: on ticks with `(tick + id) % harvest_ticks_per_ore == 0` one unit of ore from its cell
##   becomes `credits_per_ore` of cargo; a full load goes to RETURN, an empty cell to SEEK.
## - RETURN: its refinery (`home`, else `_choose`), the order to the dock; an ended order within
##   `dock_reach_milli` of the dock turns to UNLOAD, farther it is given again.
## - UNLOAD: on ticks with `(tick + id) % unload_ticks_per_ore == 0` it pays `credits_per_ore` of
##   its cargo to its owner and to `stat_harvested`; empty, it goes back to its cell. It needs no
##   refinery once it has docked: one destroyed meanwhile does not stop the unloading.
## - IDLE: on a tick with `(tick + id) % harvest_resume_ticks == 0` a harvester whose order has
##   ended goes back to work (`_resume`); 0 turns that off. A harvester still walking waits.
## The loop aliases what it reads once; the rest (a scan, an order, a refinery choice) is event
## cadence and reads the World itself.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	_regrow(world)
	var rows: PackedInt32Array = world.harvester_rows
	if rows.is_empty():
		return
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var orders: PackedInt32Array = world.order
	var modes: PackedInt32Array = world.harvest_mode
	var cargos: PackedInt32Array = world.cargo
	var slots: PackedInt32Array = world.harvest_slot
	var homes: PackedInt32Array = world.home
	var capacity: PackedInt32Array = world.type_harvest
	var dock_xs: PackedInt32Array = world.type_dock_x
	var dock_ys: PackedInt32Array = world.type_dock_y
	var ore_cells: PackedInt32Array = world.ore_cell
	var amounts: PackedInt32Array = world.ore_amount
	var credits: PackedInt32Array = world.credits
	var harvested: PackedInt32Array = world.stat_harvested
	var count: int = ids.size()
	var ore_count: int = ore_cells.size()
	var tick: int = world.tick
	var cols: int = world.map_cols
	var value: int = world.credits_per_ore
	var per_ore: int = maxi(world.harvest_ticks_per_ore, 1)
	var per_unload: int = maxi(world.unload_ticks_per_ore, 1)
	var retry: int = maxi(world.harvest_retry_ticks, 1)
	var reach: int = world.harvest_reach_milli
	var dock_reach: int = world.dock_reach_milli
	var resume: int = world.harvest_resume_ticks
	for row: int in rows:
		var mode: int = modes[row]
		var type: int = types[row]
		var slot: int = slots[row]
		var has_ore: bool = slot >= 0 and slot < ore_count and amounts[slot] > 0
		if mode == World.HarvestMode.SEEK:
			if cargos[row] >= capacity[type]:
				_go_home(world, row)  # A full load goes home before more ore.
			elif not has_ore:
				# A cell that ran empty (slot kept) is replaced at once; no cell waits for its turn.
				if slot >= 0 or (tick + ids[row]) % retry == 0:
					_pick(world, row, -1)
			elif orders[row] == World.Order.IDLE:
				var centre: Vector2i = _centre(ore_cells[slot], cols)
				var dx: int = centre.x - pos_x[row]
				var dy: int = centre.y - pos_y[row]
				if dx * dx + dy * dy <= reach * reach:
					modes[row] = World.HarvestMode.MINE
				else:
					_pick(world, row, slot)  # The order ended short of the cell.
		elif mode == World.HarvestMode.MINE:
			if (tick + ids[row]) % per_ore != 0:
				continue
			if not has_ore:
				modes[row] = World.HarvestMode.SEEK  # The cargo stays; SEEK scans next tick.
				continue
			amounts[slot] -= 1
			cargos[row] += value
			if cargos[row] >= capacity[type]:
				modes[row] = World.HarvestMode.RETURN
		elif mode == World.HarvestMode.RETURN:
			var home_id: int = homes[row]
			var at: int = ids.bsearch(home_id)
			var kept: bool = (
				at < count
				and ids[at] == home_id
				and owners[at] == owners[row]
				and (dock_xs[types[at]] != 0 or dock_ys[types[at]] != 0)
			)
			if not kept:
				# A refinery that is gone is replaced at once; with none at all it waits for its turn.
				if home_id != 0 or (tick + ids[row]) % retry == 0:
					_choose(world, row)
			elif orders[row] == World.Order.IDLE:
				var dock: Vector2i = _dock(world, at)
				var dx: int = dock.x - pos_x[row]
				var dy: int = dock.y - pos_y[row]
				if dx * dx + dy * dy <= dock_reach * dock_reach:
					modes[row] = World.HarvestMode.UNLOAD
				else:
					_order(world, row, dock)
		elif mode == World.HarvestMode.UNLOAD:
			if (tick + ids[row]) % per_unload != 0:
				continue
			var paid: int = mini(value, cargos[row])
			cargos[row] -= paid
			credits[owners[row]] += paid
			harvested[owners[row]] += paid
			if cargos[row] <= 0:
				modes[row] = World.HarvestMode.SEEK
				if has_ore:
					_order(world, row, _centre(ore_cells[slot], cols))  # Back to its last cell.
		elif (
			mode == World.HarvestMode.IDLE
			and resume > 0
			and orders[row] == World.Order.IDLE
			and (tick + ids[row]) % resume == 0
		):
			_resume(world, row)


## HARVEST: true when at least one harvester among the command's units took an ore cell near the
## point. The cell is the one with ore nearest to the point, within `harvest_pick_milli` of it (the
## smallest squared distance, then the lowest index; the scan counts in `Stat.ORE_SCANNED`), and
## every harvester of the player among `unit_ids` takes it (`_take`), the cargo and `home` as they
## are. No harvester among the ids, or no such cell: dropped. The ids go through `Sim._own_rows`,
## the helper the unit-group commands share.
static func apply_harvest(world: World, command: Command) -> bool:
	var rows: PackedInt32Array = _harvesters(world, command)
	if rows.is_empty():
		return false
	var slot: int = _scan(world, command.target_x, command.target_y, -1, world.harvest_pick_milli)
	if slot < 0:
		return false
	for row: int in rows:
		_take(world, row, slot)
	return true


## A unit-group order (MOVE, ATTACK_MOVE, STOP) on `rows` hands those harvesters back to the player
## (harvest mode IDLE; the cargo, the cell and `home` are kept). Sim calls it with the rows it
## accepted, after the order is given.
static func release(world: World, rows: PackedInt32Array) -> void:
	var capacity: PackedInt32Array = world.type_harvest
	var types: PackedInt32Array = world.type_index
	var modes: PackedInt32Array = world.harvest_mode
	for row: int in rows:
		if capacity[types[row]] > 0:
			modes[row] = World.HarvestMode.IDLE


## On a tick with `tick % ore_regrow_ticks == 0` every ore cell below `ore_cell_max` gains 1 unit.
static func _regrow(world: World) -> void:
	if world.tick % maxi(world.ore_regrow_ticks, 1) != 0:
		return
	var amounts: PackedInt32Array = world.ore_amount
	var most: int = world.ore_cell_max
	for index: int in amounts.size():
		if amounts[index] < most:
			amounts[index] += 1


## SEEK's full load: RETURN and, in the same step, the order to the dock of `home` while that
## refinery still stands, whatever order the row has (RETURN itself gives the order only to a row
## with none, so a MOVE to an ore cell would run its course first). A row with no order within
## `dock_reach_milli` of the dock keeps none and RETURN turns it to UNLOAD next tick. A `home` that
## is gone, is not a refinery of the owner or is 0 goes to `_choose`, as in RETURN.
static func _go_home(world: World, row: int) -> void:
	world.harvest_mode[row] = World.HarvestMode.RETURN
	var at: int = world.index_of(world.home[row])
	if at < 0 or world.owner[at] != world.owner[row]:
		_choose(world, row)
		return
	var type: int = world.type_index[at]
	if world.type_dock_x[type] == 0 and world.type_dock_y[type] == 0:
		_choose(world, row)
		return
	var dock: Vector2i = _dock(world, at)
	var dx: int = dock.x - world.pos_x[row]
	var dy: int = dock.y - world.pos_y[row]
	var reach: int = world.dock_reach_milli
	if world.order[row] != World.Order.IDLE or dx * dx + dy * dy > reach * reach:
		_order(world, row, dock)


## SEEK's scan: row `row` takes the ore cell with ore nearest to it (`_scan`, skipping index `skip`;
## -1 skips none), and gets the order to its centre unless it stands within reach of it with no
## order. No cell: `harvest_slot` -1, and the row waits.
static func _pick(world: World, row: int, skip: int) -> void:
	var best: int = _scan(world, world.pos_x[row], world.pos_y[row], skip, -1)
	world.harvest_slot[row] = best
	if best < 0:
		return
	var centre: Vector2i = _centre(world.ore_cell[best], world.map_cols)
	var dx: int = centre.x - world.pos_x[row]
	var dy: int = centre.y - world.pos_y[row]
	var reach: int = world.harvest_reach_milli
	if world.order[row] != World.Order.IDLE or dx * dx + dy * dy > reach * reach:
		_order(world, row, centre)


## The index of the ore cell with ore nearest to the milli point (x, y): the smallest squared
## distance to the cell's centre, then the lowest index; `skip` is an index to pass over (-1 none)
## and `reach` the greatest distance that counts (-1: any, for a point on the map). -1 when no cell
## qualifies. Every cell of the list is looked at and counted in `Stat.ORE_SCANNED`. A point far
## off the map is cut by the box test before anything is squared.
static func _scan(world: World, x: int, y: int, skip: int, reach: int) -> int:
	var cells: PackedInt32Array = world.ore_cell
	var amounts: PackedInt32Array = world.ore_amount
	var cols: int = world.map_cols
	var best: int = -1
	var best_d2: int = 0
	for index: int in cells.size():
		if amounts[index] <= 0 or index == skip:
			continue
		var centre: Vector2i = _centre(cells[index], cols)
		var dx: int = centre.x - x
		var dy: int = centre.y - y
		if reach >= 0 and (absi(dx) > reach or absi(dy) > reach):
			continue
		var d2: int = dx * dx + dy * dy
		if reach >= 0 and d2 > reach * reach:
			continue
		if best < 0 or d2 < best_d2:
			best = index
			best_d2 = d2
	world.stats[World.Stat.ORE_SCANNED] += cells.size()
	return best


## Hands harvester `row` the ore cell `slot` (-1: none): SEEK, the cell in `harvest_slot` and, with
## a cell, the order to its centre in the same step, so that SEEK reads the row as under way and
## not as one whose order ended short. The cargo and `home` stay.
static func _take(world: World, row: int, slot: int) -> void:
	world.harvest_mode[row] = World.HarvestMode.SEEK
	world.harvest_slot[row] = slot
	if slot >= 0:
		_order(world, row, _centre(world.ore_cell[slot], world.map_cols))


## The auto-resume of an IDLE harvester whose order has ended: back to SEEK with the cell it had
## while that has ore, else the cell nearest to where it stands (none: it waits, as SEEK does).
static func _resume(world: World, row: int) -> void:
	var slot: int = world.harvest_slot[row]
	if slot < 0 or slot >= world.ore_amount.size() or world.ore_amount[slot] <= 0:
		slot = _scan(world, world.pos_x[row], world.pos_y[row], -1, -1)
	_take(world, row, slot)


## The rows of the command's own harvesters (their type has `type_harvest` above 0), ascending.
static func _harvesters(world: World, command: Command) -> PackedInt32Array:
	var capacity: PackedInt32Array = world.type_harvest
	var types: PackedInt32Array = world.type_index
	var found: PackedInt32Array = PackedInt32Array()
	for row: int in Sim._own_rows(world, command, false):
		if capacity[types[row]] > 0:
			found.append(row)
	return found


## RETURN's refinery choice: the nearest own refinery (squared distance to its centre, then the
## lowest id) becomes `home` and the row gets the order to its dock. None: `home` is 0 and the row
## waits.
static func _choose(world: World, row: int) -> void:
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var dock_xs: PackedInt32Array = world.type_dock_x
	var dock_ys: PackedInt32Array = world.type_dock_y
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var best: int = -1
	var best_d2: int = 0
	for at: int in world.building_rows:
		var type: int = types[at]
		if owners[at] != owners[row] or (dock_xs[type] == 0 and dock_ys[type] == 0):
			continue
		var dx: int = pos_x[at] - pos_x[row]
		var dy: int = pos_y[at] - pos_y[row]
		if best < 0 or dx * dx + dy * dy < best_d2:
			best = at
			best_d2 = dx * dx + dy * dy
	if best < 0:
		world.home[row] = 0
		return
	world.home[row] = world.unit_id[best]
	_order(world, row, _dock(world, best))


## The point of row `at`'s dock: its footprint's origin plus the type's dock offset, a tile centre.
static func _dock(world: World, at: int) -> Vector2i:
	var origin: Vector2i = Buildings.footprint_origin(world, at)
	var type: int = world.type_index[at]
	return Vector2i(
		(origin.x + world.type_dock_x[type]) * World.MILLI_PER_TILE + World.TILE_CENTRE,
		(origin.y + world.type_dock_y[type]) * World.MILLI_PER_TILE + World.TILE_CENTRE
	)


## The centre of the map cell `cell` (`line * cols + column`) in milli-tiles.
@warning_ignore("integer_division")
static func _centre(cell: int, cols: int) -> Vector2i:
	return Vector2i(
		cell % cols * World.MILLI_PER_TILE + World.TILE_CENTRE,
		cell / cols * World.MILLI_PER_TILE + World.TILE_CENTRE
	)


## Gives `row` a MOVE to `goal` the way Sim._apply_point does: the order, the goal, no group cell (a
## blocked line keys the field on the goal's tile) and a fresh DIRECT navigation state.
static func _order(world: World, row: int, goal: Vector2i) -> void:
	world.order[row] = World.Order.MOVE
	world.goal_x[row] = goal.x
	world.goal_y[row] = goal.y
	world.group_cell[row] = -1
	Movement.reset_nav(world, PackedInt32Array([row]), World.NavMode.DIRECT)  # alloc-ok
