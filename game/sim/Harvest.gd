class_name Harvest
extends RefCounted
## The harvest loop and the ore (ADR 0017 section 5, ADR 0018 sections 2 and 3). `run` is the
## second half of ECONOMY, after `Power.run` has rebuilt `harvester_rows` and `building_rows`: ore
## regrowth, then the SEEK, MINE, RETURN and UNLOAD of every harvester, ascending by row. IDLE rows
## are the player's. Plan row P75b adds `release`, `apply_harvest` and the auto-resume; until then
## `apply_harvest` refuses, so a HARVEST is dropped and counted.
##
## The loop gives orders the way `Sim._apply_point` does after `Formation.assign`: `order` MOVE, the
## goal, `group_cell` -1 and `Movement.reset_nav` with DIRECT. It reads no input and draws no random
## number. A row takes one step per tick and a change of mode counts from the next tick, except the
## two that give an order at once (`_pick`, the end of UNLOAD).
##
## No column says "the order was given", so SEEK reads it off the state: every way into SEEK with an
## ore cell that has ore gives the order in the same step, hence a SEEK harvester that has no order
## and stands farther than `harvest_reach_milli` from its cell is one whose order ended short. It
## takes another cell (ADR 0018 section 3 says "once more", which has no counter to run on; the
## cell it left is skipped, and a lone cell is tried again after the retry wait). P75b's HARVEST
## and auto-resume give their order the same way. A refinery is a building type with a dock other
## than (0, 0), a tile inside the footprint that no unit can walk to (`BuildingDef.dock` defaults
## to it, meaning none).

## ECONOMY: the ore grows back, then each harvester steps once. Ore: on a tick with
## `tick % ore_regrow_ticks == 0` every cell below `ore_cell_max` gains 1.
## - SEEK: a full load goes to RETURN. A cell with ore and an ended order: within
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
	for row: int in rows:
		var mode: int = modes[row]
		var type: int = types[row]
		var slot: int = slots[row]
		var has_ore: bool = slot >= 0 and slot < ore_count and amounts[slot] > 0
		if mode == World.HarvestMode.SEEK:
			if cargos[row] >= capacity[type]:
				modes[row] = World.HarvestMode.RETURN  # A full load goes home before more ore.
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


## HARVEST: true when a harvester among the command's units took an ore cell near the point.
static func apply_harvest(_world: World, _command: Command) -> bool:
	return false


## A unit-group order (MOVE, ATTACK_MOVE, STOP) on `rows` hands those harvesters back to the player
## (harvest mode IDLE, the cargo kept). Sim calls it with the rows it accepted.
static func release(_world: World, _rows: PackedInt32Array) -> void:
	pass


## On a tick with `tick % ore_regrow_ticks == 0` every ore cell below `ore_cell_max` gains 1 unit.
static func _regrow(world: World) -> void:
	if world.tick % maxi(world.ore_regrow_ticks, 1) != 0:
		return
	var amounts: PackedInt32Array = world.ore_amount
	var most: int = world.ore_cell_max
	for index: int in amounts.size():
		if amounts[index] < most:
			amounts[index] += 1


## SEEK's scan: row `row` takes the ore cell with ore nearest to it (smallest squared distance, then
## the lowest index, skipping index `skip`; -1 skips none), and gets the order to its centre unless
## it stands within reach of it with no order. No cell: `harvest_slot` -1, and the row waits.
## Every cell of the list is looked at and counted in `Stat.ORE_SCANNED`.
static func _pick(world: World, row: int, skip: int) -> void:
	var cells: PackedInt32Array = world.ore_cell
	var amounts: PackedInt32Array = world.ore_amount
	var cols: int = world.map_cols
	var x: int = world.pos_x[row]
	var y: int = world.pos_y[row]
	var best: int = -1
	var best_d2: int = 0
	for index: int in cells.size():
		if amounts[index] <= 0 or index == skip:
			continue
		var centre: Vector2i = _centre(cells[index], cols)
		var d2: int = (centre.x - x) * (centre.x - x) + (centre.y - y) * (centre.y - y)
		if best < 0 or d2 < best_d2:
			best = index
			best_d2 = d2
	world.stats[World.Stat.ORE_SCANNED] += cells.size()
	world.harvest_slot[row] = best
	var reach: int = world.harvest_reach_milli
	if best >= 0 and (world.order[row] != World.Order.IDLE or best_d2 > reach * reach):
		_order(world, row, _centre(cells[best], cols))


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
