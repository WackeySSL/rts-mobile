class_name Targeting
extends RefCounted
## The TARGETING phase (ADR 0007 section 4 step 5, ADR 0009 sections 2 and 3). Two passes over the
## rows, in ascending id order: acquisition (and the `ATTACK` lock), then engagement. Together they
## write `target`, and for the rows that fight the order, its target, the goal and the navigation
## columns (below); they move nothing, fire nothing and write no other column. A shot needs the
## weapons PR (P42a).
##
## Acquisition (P41): every unit that is due picks the enemy it will shoot at and writes its id into
## `world.target` (0 = none). It reads `world.target_grid`, which the caller has rebuilt from this
## tick's positions (the GRIDS phase): `run` never rebuilds a grid.
##
## Engagement (P41b): a unit with a target in weapon range holds (`HOLD`, no movement intent); an
## attack-moving unit with a target out of range chases it (`CHASE`) while the line to it is clear,
## else it keeps the path of its order, so units use the gaps in the rock and never press into it;
## an `ATTACK` unit steers at its target by the order's own navigation (the goal is the target's
## position) and holds at range. A unit that loses its target (or its target steps out of range)
## resumes its path. See `_engage`.
##
## This is the GDScript twin of the TARGETING kernel P41n ports later: keep it portable (integers
## only, the World's arrays aliased into typed locals before the loop, no allocation, rows and grid
## lists visited in a fixed order). Every number comes from the World's rule ints and type tables
## (data/); the constants below are structure, not balance.
##
## Range for the C++ port: positions are below 2^16 and a reach below 2^14, so a squared distance
## stays below 2^33 in an int64 and `weapon * World.Armour.size() + armour` (4 armour classes per
## weapon) indexes `weapon_vs_armour`.

## The orders and navigation modes the phase reads and writes, as the World's ints.
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const IDLE: int = World.Order.IDLE
const ATTACK: int = World.Order.ATTACK
const NONE: int = World.NavMode.NONE
const DIRECT: int = World.NavMode.DIRECT
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE

## The acquisition pass: one pass over the rows in ascending id order, then `_engage`.
## - An `ATTACK` row locks its target (P41b): `target` is its `order_target` for as long as that
##   unit exists and is an enemy, wherever it stands, and the row's goal is the target's position as
##   it stands at the start of the tick (read before anyone moves, so the row order cannot matter).
##   When the target is gone the order becomes `ATTACK_MOVE` to the goal it left, which is where
##   the target last stood: the row's `order_target` is cleared, and the row goes on as an
##   attack-moving row from this tick (it scans on its next due tick). ADR 0009 section 2.
## - `MOVE` rows acquire nothing and drop a target they held, every tick (a moving unit does not
##   fire).
## - An `ATTACK_MOVE` or `IDLE` row with a weapon is due when `(tick + id) % retarget_period_ticks`
##   is 0 (a fifth of the rows each tick with the shipped 5). Its reach is the type's acquire
##   range when attack-moving and the weapon's range when idle.
## - A due row keeps its target while that unit still exists, is an enemy and is a candidate (below)
##   within reach: no switching for a nearer or better one. Otherwise it scans.
## - The scan looks at every row in the grid cells from `(pos - reach) / cell_milli` to
##   `(pos + reach) / cell_milli` on each axis (integer division truncating toward zero, clamped to
##   the grid, as the grid's own rebuild puts a point in a cell), itself excepted, and counts them
##   in `stats[TARGET_CANDIDATES]` (3 x 3 to 4 x 4 cells with the shipped ranges, fewer at an
##   edge). A candidate is an enemy (an owner that is neither the row's own nor 0) with
##   `min_range^2 <= d2 <= reach^2` and a damage percent above 0 against its armour. The best has
##   the highest percent, then the smallest `d2`, then the lowest row (rows ascend with the id). The
##   grid is visited cell by cell, not in id order, so the id tie-break is explicit. No candidate
##   writes 0.
## - An empty map has no cells: the clear above still runs, and a due row that keeps no target
##   writes 0 without a scan.
## A type whose weapon index is negative or past the weapon tables is unarmed (a hand-built World
## may name a weapon it has no table for): it acquires nothing and never holds or chases, while an
## `ATTACK` command still accepts it (`Sim._own_rows` asks only for a weapon index of 0 or more), so
## such an `ATTACK` row locks its target and steers at it for good.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var grid: SpatialGrid = world.target_grid
	var cols: int = grid.cols
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	var orders: PackedInt32Array = world.order
	var order_targets: PackedInt32Array = world.order_target
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
		if order == ATTACK:
			var locked: int = order_targets[row]
			var at: int = ids.bsearch(locked)
			if at < count and ids[at] == locked and owners[at] != owners[row] and owners[at] != 0:
				targets[row] = locked
				goal_x[row] = pos_x[at]
				goal_y[row] = pos_y[at]
				continue
			orders[row] = ATTACK_MOVE
			order_targets[row] = 0
			targets[row] = 0
			order = ATTACK_MOVE
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
		if cols == 0:
			targets[row] = 0  # An empty map: no cells, so no candidate and no target.
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
	_engage(world)


## The engagement pass (ADR 0009 section 3), after acquisition and on every tick: each row that has
## a target decides between holding, chasing and following the path of its order, from the positions
## at the start of the tick. It writes only through `Movement.reset_row`, at the moment a mode
## changes, and adds its line checks to `stats[LINE_CHECKS]` (one per `FixedMath.line_clear` call,
## after the loop, as `Movement._check_line` counts its own).
## - A target that is gone (the row held it from an earlier scan) counts as none: a unit that held
##   or chased resumes its path (`DIRECT`, line unchecked, no field; an idle unit goes back to
##   `NONE`). `target` itself is left for the next scan to replace.
## - A target in weapon range (`min_range^2 <= d2 <= range^2`) puts the unit in `HOLD`, whatever its
##   order: no intent, though separation still pushes it. An idle unit holds too. A target that is
##   out of range (it moved, or the unit was pushed) takes the unit out of `HOLD` again.
## - Out of range, an `ATTACK_MOVE` unit chases while the target is inside its acquire range (the
##   reach of ADR 0009 section 3) and the straight line to it is clear for its class: `CHASE`. With
##   a blocked line, or a target beyond reach, it keeps the path of its order (`DIRECT` or `FIELD`
##   to its goal) and holds when the target comes into range, so it uses the gaps in the rock and
##   never presses into it. The line is checked on the unit's line-check turn ((tick + id) %
##   `line_check_period_ticks`, so a crowd spreads its checks), which is the tick it acquires a
##   target when the two periods are equal (5); the first clear line starts the chase and the first
##   blocked one ends it (up to `line_check_period_ticks` ticks of `CHASE` with a blocked line).
## - An `ATTACK` unit never chases: its goal is its target's position, and the navigation of the
##   order takes it to weapon range (`DIRECT` while the line is clear, else a field keyed on the
##   target's tile, `Movement._rekey`). `Movement` checks a `DIRECT` unit's line once, because a
##   clear line stays clear on a static map, but this goal walks, so on the unit's line-check turn
##   a `DIRECT` unit whose line was marked clear tests it again, and a blocked line sends it back
##   through `Movement.run`'s check (unchecked `DIRECT`, so the same tick takes the field) instead
##   of steering into the rock for as long as the target stays behind it. A `FIELD` unit already
##   checks its line each time it enters a tile.
## An idle unit never moves. A target inside `min_range` is not in range, and no unit backs away
## from it (no Phase 2 weapon has a minimum range). A type without a weapon table row is unarmed
## here as in `run`.
static func _engage(world: World) -> void:
	var ids: PackedInt32Array = world.unit_id
	var orders: PackedInt32Array = world.order
	var modes: PackedInt32Array = world.nav_mode
	var targets: PackedInt32Array = world.target
	var checked: PackedInt32Array = world.nav_cell
	var types: PackedInt32Array = world.type_index
	var classes: PackedInt32Array = world.type_move_class
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var type_acquire: PackedInt32Array = world.type_acquire
	var type_weapon: PackedInt32Array = world.type_weapon
	var weapon_range: PackedInt32Array = world.weapon_range
	var weapon_min_range: PackedInt32Array = world.weapon_min_range
	var weapons: int = weapon_range.size()
	var count: int = ids.size()
	var tick: int = world.tick
	var period: int = maxi(world.line_check_period_ticks, 1)
	var checks: int = 0
	for row: int in count:
		var mode: int = modes[row]
		var order: int = orders[row]
		var held: int = targets[row]
		var at: int = -1
		if held != 0:
			at = ids.bsearch(held)
			if at >= count or ids[at] != held:
				at = -1
		if at < 0:
			if mode == HOLD or mode == CHASE:
				Movement.reset_row(world, row, NONE if order == IDLE else DIRECT)
			continue
		var type: int = types[row]
		var weapon: int = type_weapon[type]
		if weapon < 0 or weapon >= weapons:
			continue
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		var dx: int = pos_x[at] - x
		var dy: int = pos_y[at] - y
		var d2: int = dx * dx + dy * dy
		var reach: int = weapon_range[weapon]
		var min_range: int = weapon_min_range[weapon]
		if d2 <= reach * reach and d2 >= min_range * min_range:
			if mode != HOLD:
				Movement.reset_row(world, row, HOLD)
			continue
		if mode == HOLD:
			mode = NONE if order == IDLE else DIRECT
			Movement.reset_row(world, row, mode)
		if (order != ATTACK_MOVE and order != ATTACK) or (tick + ids[row]) % period != 0:
			continue
		if order == ATTACK:
			if mode == DIRECT and checked[row] >= 0:
				checks += 1
				if not FixedMath.line_clear(world, x, y, pos_x[at], pos_y[at], classes[type]):
					Movement.reset_row(world, row, DIRECT)
			continue
		var clear: bool = false
		var acquire: int = type_acquire[type]
		if d2 <= acquire * acquire:
			checks += 1
			clear = FixedMath.line_clear(world, x, y, pos_x[at], pos_y[at], classes[type])
		if clear and mode != CHASE:
			Movement.reset_row(world, row, CHASE)
		elif not clear and mode == CHASE:
			Movement.reset_row(world, row, DIRECT)
	world.stats[World.Stat.LINE_CHECKS] += checks
