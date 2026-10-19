class_name Targeting
extends RefCounted
## The TARGETING phase, acquisition (ADR 0007 section 4 step 4, ADR 0009 section 2): every unit
## that is due picks the enemy it will shoot at, and writes its id into `world.target` (0 = none).
## It reads `world.target_grid`, which the caller has rebuilt from this tick's positions (the GRIDS
## phase, P41): `run` never rebuilds a grid. It moves nothing, fires nothing and writes only
## `target` and `stats[TARGET_CANDIDATES]`. Chasing, holding and the `ATTACK` order are the
## engagement part (P41b); a shot needs the weapons PR (P42a).
##
## This is the GDScript twin of the TARGETING kernel P41n ports later: keep it portable (integers
## only, the World's arrays aliased into typed locals before the loop, no allocation, rows and grid
## lists visited in a fixed order). Every number comes from the World's rule ints and type tables
## (data/); the constants below are structure, not balance.
##
## Range for the C++ port: positions are below 2^16 and a reach below 2^14, so a squared distance
## stays below 2^33 in an int64 and `weapon * ARMOUR_CLASSES + armour` indexes `weapon_vs_armour`.

## The orders that acquire, as the World's ints (the ADR 0009 section 2 table, "By order").
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const IDLE: int = World.Order.IDLE

## One pass over the rows in ascending id order.
## - `MOVE` rows acquire nothing and drop a target they held, every tick (a moving unit does not
##   fire). So do `ATTACK` rows until P41b, which locks them to their `order_target` instead.
## - An `ATTACK_MOVE` or `IDLE` row with a weapon is due when `(tick + id) % retarget_period_ticks`
##   is 0 (a fifth of the rows each tick with the shipped 5). Its reach is the type's acquire
##   range when attack-moving and the weapon's range when idle.
## - A due row keeps its target while that unit still exists, is an enemy and is a candidate (below)
##   within reach: no switching for a nearer or better one. Otherwise it scans.
## - The scan looks at every row in the grid cells that cover the reach (the 4-tile cells, read
##   from `cell_milli`), itself excepted, and counts them in `stats[TARGET_CANDIDATES]`. A
##   candidate is an enemy (an owner that is neither the row's own nor 0) with
##   `min_range^2 <= d2 <= reach^2` and a damage percent above 0 against its armour. The best has
##   the highest percent, then the smallest `d2`, then the lowest row (rows ascend with the id). The
##   grid is visited cell by cell, not in id order, so the id tie-break is explicit. No candidate
##   writes 0.
## A type whose weapon index is negative or past the weapon tables is unarmed (a hand-built World
## may name a weapon it has no table for).
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var grid: SpatialGrid = world.target_grid
	var cols: int = grid.cols
	if cols == 0:
		return  # An empty map: no cells, so no candidate and no target.
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var orders: PackedInt32Array = world.order
	var targets: PackedInt32Array = world.target
	var type_armour: PackedInt32Array = world.type_armour
	var type_acquire: PackedInt32Array = world.type_acquire
	var type_weapon: PackedInt32Array = world.type_weapon
	var weapon_range: PackedInt32Array = world.weapon_range
	var weapon_min_range: PackedInt32Array = world.weapon_min_range
	var weapon_vs: PackedInt32Array = world.weapon_vs_armour
	var heads: PackedInt32Array = grid.head
	var links: PackedInt32Array = grid.next
	var lines: int = grid.rows
	var side: int = grid.cell_milli
	var weapons: int = weapon_range.size()
	var armour_classes: int = World.Armour.size()
	var tick: int = world.tick
	var period: int = maxi(world.retarget_period_ticks, 1)
	var count: int = ids.size()
	var looked: int = 0
	for row: int in count:
		var order: int = orders[row]
		if order != ATTACK_MOVE and order != IDLE:
			targets[row] = 0
			continue
		if (tick + ids[row]) % period != 0:
			continue
		var type: int = types[row]
		var weapon: int = type_weapon[type]
		if weapon < 0 or weapon >= weapons:
			continue
		var reach: int = type_acquire[type] if order == ATTACK_MOVE else weapon_range[weapon]
		var reach2: int = reach * reach
		var min2: int = weapon_min_range[weapon] * weapon_min_range[weapon]
		var vs_base: int = weapon * armour_classes
		var own: int = owners[row]
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		var held: int = targets[row]
		if held != 0:
			var at: int = ids.bsearch(held)
			if at < count and ids[at] == held and owners[at] != own and owners[at] != 0:
				var held_x: int = pos_x[at] - x
				var held_y: int = pos_y[at] - y
				var held_d2: int = held_x * held_x + held_y * held_y
				if (
					held_d2 <= reach2
					and held_d2 >= min2
					and weapon_vs[vs_base + type_armour[types[at]]] > 0
				):
					continue
		var best: int = -1
		var best_percent: int = 0
		var best_d2: int = 0
		# Clamped, so a point the grid put in an edge cell (outside the map) still finds that cell.
		var first_column: int = clampi((x - reach) / side, 0, cols - 1)
		var last_column: int = clampi((x + reach) / side, 0, cols - 1)
		var first_line: int = clampi((y - reach) / side, 0, lines - 1)
		var last_line: int = clampi((y + reach) / side, 0, lines - 1)
		for line: int in range(first_line, last_line + 1):
			for column: int in range(first_column, last_column + 1):
				var next: int = heads[line * cols + column]
				while next != -1:
					var other: int = next
					next = links[other]
					if other == row:
						continue
					looked += 1
					var other_owner: int = owners[other]
					if other_owner == own or other_owner == 0:
						continue
					var dx: int = pos_x[other] - x
					var dy: int = pos_y[other] - y
					var d2: int = dx * dx + dy * dy
					if d2 > reach2 or d2 < min2:
						continue
					var percent: int = weapon_vs[vs_base + type_armour[types[other]]]
					if percent <= 0:
						continue
					if (
						percent > best_percent
						or (
							percent == best_percent
							and (d2 < best_d2 or (d2 == best_d2 and other < best))
						)
					):
						best = other
						best_percent = percent
						best_d2 = d2
		targets[row] = ids[best] if best >= 0 else 0
	world.stats[World.Stat.TARGET_CANDIDATES] += looked
