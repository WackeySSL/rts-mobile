extends SimProbe
## What a TARGETING lockstep run reached (plan P41n2): at the TARGETING mark it works the phase out
## again from the columns as the COMMANDS mark left them (the rows, their orders, targets and
## navigation, which FLOW and GRIDS do not touch) and from the positions, and adds what it meets to
## `tally`. The suites assert the counts, so that a run cannot pass by never meeting a tie, a
## fallback, a chase or a long line. It only reads: the targets and the modes are the phase's own.
## A probe of the game never reads the World (ADR 0007 section 4); this one is a test's, a recorded
## exception like SeparationTallyProbe. Not a test suite. It is a file of its own, not an inner
## class, because an inner class with a script base would name itself at run time.
##
## The probe scans the way the rule scans (the cells from `(pos - reach) / side` to `(pos + reach) /
## side` on each axis, clamped to the grid, each list in ascending row order), and the rig holds it
## to the phase after every tick, so a probe that works the rule out another way fails the case
## instead of vouching for it: its count of the rows looked at and of the line tests against the
## phase's own `stats[TARGET_CANDIDATES]` and `stats[LINE_CHECKS]`, and, row by row, the five
## columns that the acquisition pass writes (the target, the order, its target and the goal) against
## what the probe says the rule leaves in them (`last_mismatches`). The vision rule that P46b added
## to both Targeting versions (a unit acts only on an enemy that its player sees) is in count() too,
## worked out through FogGrid.is_visible and World.cell_of and not through Targeting.sees or the
## kernel's lookup; a probe that left it out would get a different pick wherever the rule changes
## one, and the mismatch names the row. The mismatch check does not see a rule that changes no pick
## in the cases that run, so the tallies `unseen`, `sight_lost` and `sight_drops` count the times
## the rule refused something, and the suites hold them above a floor.

## The names of the counts (each starts at 0); see count() for what each one holds.
const NAMES: Array[StringName] = [
	&"ticks",
	&"rows",
	&"locked",
	&"fallbacks",
	&"dropped",
	&"unarmed",
	&"due",
	&"kept",
	&"scans",
	&"found",
	&"empty",
	&"looks",
	&"cands",
	&"unseen",
	&"sight_lost",
	&"sight_drops",
	&"nearer_wins",
	&"farther_wins",
	&"ties",
	&"tie_swaps",
	&"window_edge",
	&"holding",
	&"chasing",
	&"hold_starts",
	&"hold_ends",
	&"chase_starts",
	&"chase_ends",
	&"chase_edge",
	&"line_checks",
	&"retests",
	&"clear",
	&"blocked",
	&"wide_lines",
	&"wide_d2"
]
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const IDLE: int = World.Order.IDLE
const ATTACK: int = World.Order.ATTACK
const NONE: int = World.NavMode.NONE
const DIRECT: int = World.NavMode.DIRECT
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE
## A line whose `ay * dx` is above this does not fit 32 bits (FixedMath.line_clear multiplies the
## left end's y by the width of the segment).
const INT32_MAX: int = 2147483647

var world: World
var tally: Dictionary[StringName, int] = {}
## The rows looked at and the line tests of the last count(), and the phase's own
## stats[TARGET_CANDIDATES] and stats[LINE_CHECKS] as they stood then: the two have to agree
## (INTENTS adds its own line tests to the second, later in the tick).
var last_looks: int = 0
var last_checks: int = 0
var phase_looks: int = 0
var phase_checks: int = 0
## How many cells of the five columns that the acquisition pass writes differ from what the probe
## says the rule leaves in them after the last count(), and the first of them in words ("" for
## none).
var last_mismatches: int = 0
var first_mismatch: String = ""
var _orders: PackedInt32Array = PackedInt32Array()
var _order_targets: PackedInt32Array = PackedInt32Array()
var _targets: PackedInt32Array = PackedInt32Array()
var _goal_x: PackedInt32Array = PackedInt32Array()
var _goal_y: PackedInt32Array = PackedInt32Array()
var _modes: PackedInt32Array = PackedInt32Array()
var _checked: PackedInt32Array = PackedInt32Array()


func _init(for_world: World = null) -> void:
	world = for_world
	for name: StringName in NAMES:
		tally[name] = 0


func mark(phase: int) -> void:
	if phase == SimProbe.Phase.COMMANDS:
		before()
	elif phase == SimProbe.Phase.TARGETING:
		count()


## Takes the columns that the phase reads and writes as they stand before it (after the commands).
func before() -> void:
	_orders = world.order.duplicate()
	_order_targets = world.order_target.duplicate()
	_targets = world.target.duplicate()
	_goal_x = world.goal_x.duplicate()
	_goal_y = world.goal_y.duplicate()
	_modes = world.nav_mode.duplicate()
	_checked = world.nav_cell.duplicate()


## Adds one TARGETING phase of `world` (before() taken, the phase run) to `tally`. ticks: phases;
## rows: rows in the table. Acquisition: locked: ATTACK rows that locked their target; fallbacks:
## ATTACK rows whose target is gone, no enemy or not seen, which fell back to ATTACK_MOVE; dropped:
## rows of
## another order (MOVE) that held a target; unarmed: rows on their turn whose weapon index is out of
## the tables; due: rows that scan or keep (an armed ATTACK_MOVE or IDLE row on its turn); kept: of
## those, rows that kept their target; scans: the others (on a grid with cells); found and empty:
## scans that took a target or none; looks: rows looked at (the phase's own count); cands: of those,
## enemies in range with a damage percent above 0 that the row's player sees; unseen: enemies in
## range with a damage percent that the player does not see (refused for that alone); sight_lost:
## of the fallbacks, ATTACK rows whose target is an enemy that exists but is not seen; sight_drops:
## due rows whose held target is an enemy in reach with a damage percent that is not seen (they
## scan instead of keeping it); nearer_wins: a candidate that beat the best so
## far by a smaller distance at the same percent; farther_wins: by a better percent from farther
## away; ties: a candidate at the same percent and the same squared distance as the best so far
## (the lower row wins; a candidate at a lower percent is no tie, whatever its distance); tie_swaps:
## of those, ones where the lower row was met after the higher one (the grid is not visited in row
## order); window_edge: candidates exactly at the far edge of the cells that the scan covers, on a
## cell boundary (a window one milli short loses them). nearer_wins, ties and tie_swaps count the
## same percent only.
## Engagement: holding and chasing: unit-ticks in HOLD and CHASE after the phase; hold_starts,
## hold_ends, chase_starts and chase_ends: changes of mode from before the phase; chase_edge: the
## chase line tests of an ATTACK_MOVE row whose target stands exactly at its acquire range (the test
## is `<=`); line_checks: the line tests (the phase's own count); retests: of those, the ATTACK
## re-tests of a DIRECT row with a clear line; clear and blocked: how they came out; wide_lines: of
## those, segments whose `ay * dx` is above 2^31; wide_d2: rows looked at by a scan whose squared
## distance is above 2^31. Then the rule's result is held against the phase's: last_mismatches and
## first_mismatch (see the top of this file).
@warning_ignore("integer_division")
func count() -> void:
	tally[&"ticks"] += 1
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var orders: PackedInt32Array = world.order
	var targets: PackedInt32Array = world.target
	var want_target: PackedInt32Array = _targets.duplicate()
	var want_order: PackedInt32Array = _orders.duplicate()
	var want_order_target: PackedInt32Array = _order_targets.duplicate()
	var want_goal_x: PackedInt32Array = _goal_x.duplicate()
	var want_goal_y: PackedInt32Array = _goal_y.duplicate()
	var type_armour: PackedInt32Array = world.type_armour
	var type_acquire: PackedInt32Array = world.type_acquire
	var type_weapon: PackedInt32Array = world.type_weapon
	var weapon_range: PackedInt32Array = world.weapon_range
	var weapon_min_range: PackedInt32Array = world.weapon_min_range
	var weapon_vs: PackedInt32Array = world.weapon_vs_armour
	var grid: SpatialGrid = world.target_grid
	var heads: PackedInt32Array = grid.head
	var links: PackedInt32Array = grid.next
	var cols: int = grid.cols
	var lines: int = grid.rows
	var side: int = grid.cell_milli
	var cells: bool = cols >= 1 and lines >= 1 and side >= 1
	var weapons: int = weapon_range.size()
	var armour_classes: int = World.Armour.size()
	var tick: int = world.tick
	var period: int = maxi(world.retarget_period_ticks, 1)
	var rows: int = ids.size()
	var looked: int = 0
	tally[&"rows"] += rows
	for row: int in rows:
		var order: int = _orders[row]
		var held: int = _targets[row]
		if order == ATTACK:
			var locked: int = _order_targets[row]
			var at: int = ids.bsearch(locked)
			var enemy: bool = (
				at < rows and ids[at] == locked and owners[at] != owners[row] and owners[at] != 0
			)
			if enemy and _sees(owners[row], pos_x[at], pos_y[at]):
				tally[&"locked"] += 1
				want_target[row] = locked
				want_goal_x[row] = pos_x[at]
				want_goal_y[row] = pos_y[at]
				continue
			tally[&"sight_lost"] += int(enemy)
			tally[&"fallbacks"] += 1
			order = ATTACK_MOVE
			held = 0
			want_order[row] = ATTACK_MOVE
			want_order_target[row] = 0
			want_target[row] = 0
		if order != ATTACK_MOVE and order != IDLE:
			tally[&"dropped"] += int(held != 0)
			want_target[row] = 0
			continue
		if (tick + ids[row]) % period != 0:
			continue
		var type: int = types[row]
		var weapon: int = type_weapon[type]
		if weapon < 0 or weapon >= weapons:
			tally[&"unarmed"] += 1
			continue
		tally[&"due"] += 1
		var reach: int = type_acquire[type] if order == ATTACK_MOVE else weapon_range[weapon]
		var reach2: int = reach * reach
		var min2: int = weapon_min_range[weapon] * weapon_min_range[weapon]
		var vs_base: int = weapon * armour_classes
		var own: int = owners[row]
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		if held != 0:
			var at: int = ids.bsearch(held)
			if at < rows and ids[at] == held and owners[at] != own and owners[at] != 0:
				var held_x: int = pos_x[at] - x
				var held_y: int = pos_y[at] - y
				var held_d2: int = held_x * held_x + held_y * held_y
				var held_percent: int = weapon_vs[vs_base + type_armour[types[at]]]
				if held_d2 <= reach2 and held_d2 >= min2 and held_percent > 0:
					if _sees(own, pos_x[at], pos_y[at]):
						tally[&"kept"] += 1
						continue
					tally[&"sight_drops"] += 1
		if not cells:
			want_target[row] = 0
			continue
		tally[&"scans"] += 1
		var best: int = -1
		var best_percent: int = 0
		var best_d2: int = 0
		var first_column: int = clampi((x - reach) / side, 0, cols - 1)
		var last_column: int = clampi((x + reach) / side, 0, cols - 1)
		var first_line: int = clampi((y - reach) / side, 0, lines - 1)
		var last_line: int = clampi((y + reach) / side, 0, lines - 1)
		for line: int in range(first_line, last_line + 1):
			for column: int in range(first_column, last_column + 1):
				var other: int = heads[line * cols + column]
				while other != -1:
					var next: int = links[other]
					if other != row:
						looked += 1
						var other_owner: int = owners[other]
						var other_x: int = pos_x[other]
						var other_y: int = pos_y[other]
						var dx: int = other_x - x
						var dy: int = other_y - y
						var d2: int = dx * dx + dy * dy
						tally[&"wide_d2"] += int(d2 > INT32_MAX)
						var percent: int = weapon_vs[vs_base + type_armour[types[other]]]
						var in_reach: bool = (
							other_owner != own
							and other_owner != 0
							and d2 <= reach2
							and d2 >= min2
							and percent > 0
						)
						if in_reach and not _sees(own, other_x, other_y):
							tally[&"unseen"] += 1
						elif in_reach:
							tally[&"cands"] += 1
							var on_edge: bool = (
								(other_x == x + reach and (x + reach) % side == 0)
								or (other_y == y + reach and (y + reach) % side == 0)
							)
							tally[&"window_edge"] += int(on_edge)
							if percent > best_percent:
								tally[&"farther_wins"] += int(best >= 0 and d2 > best_d2)
							elif percent == best_percent:
								if d2 < best_d2:
									tally[&"nearer_wins"] += 1
								elif d2 == best_d2:
									tally[&"ties"] += 1
									tally[&"tie_swaps"] += int(other < best)
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
					other = next
		tally[&"found" if best >= 0 else &"empty"] += 1
		want_target[row] = ids[best] if best >= 0 else 0
	tally[&"looks"] += looked
	last_looks = looked
	last_mismatches = 0
	first_mismatch = ""
	_compare(&"target", want_target, targets)
	_compare(&"order", want_order, orders)
	_compare(&"order_target", want_order_target, world.order_target)
	_compare(&"goal_x", want_goal_x, world.goal_x)
	_compare(&"goal_y", want_goal_y, world.goal_y)
	_count_engagement()


## Whether `player` sees the point (x, y): the cell of the map that holds it is visible in the
## player's block of the fog. A player with no grid (the neutral 0, one past the fog's player count)
## and a fog with no cells see every cell. Worked out through FogGrid.is_visible and World.cell_of,
## the other way round than Targeting.sees and the kernel's lookup.
func _sees(player: int, x: int, y: int) -> bool:
	var fog: FogGrid = world.fog
	if player < 1 or player > fog.player_count or fog.cells < 1:
		return true
	return fog.is_visible(player, world.cell_of(x, y))


## Counts the rows where the column `name` of the World is not what the probe worked out (`want`)
## into `last_mismatches`, and words the first one of the tick in `first_mismatch`.
func _compare(name: StringName, want: PackedInt32Array, have: PackedInt32Array) -> void:
	for row: int in want.size():
		if have[row] == want[row]:
			continue
		last_mismatches += 1
		if first_mismatch == "":
			first_mismatch = (
				"%s of unit %d is %d, the rule leaves %d"
				% [name, world.unit_id[row], have[row], want[row]]
			)


## The engagement half of count(): the modes after the phase against the modes before it, and the
## line tests the rule runs, worked out from the columns before the phase (acquisition does not
## write a navigation column).
@warning_ignore("integer_division")
func _count_engagement() -> void:
	var ids: PackedInt32Array = world.unit_id
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var orders: PackedInt32Array = world.order
	var targets: PackedInt32Array = world.target
	var modes: PackedInt32Array = world.nav_mode
	var classes: PackedInt32Array = world.type_move_class
	var type_acquire: PackedInt32Array = world.type_acquire
	var type_weapon: PackedInt32Array = world.type_weapon
	var weapon_range: PackedInt32Array = world.weapon_range
	var weapon_min_range: PackedInt32Array = world.weapon_min_range
	var weapons: int = weapon_range.size()
	var rows: int = ids.size()
	var tick: int = world.tick
	var line_period: int = maxi(world.line_check_period_ticks, 1)
	var max_x: int = world.map_cols * World.MILLI_PER_TILE
	var max_y: int = world.map_rows * World.MILLI_PER_TILE
	var checks: int = 0
	for row: int in rows:
		var mode: int = modes[row]
		var was: int = _modes[row]
		tally[&"holding"] += int(mode == HOLD)
		tally[&"chasing"] += int(mode == CHASE)
		tally[&"hold_starts"] += int(mode == HOLD and was != HOLD)
		tally[&"hold_ends"] += int(mode != HOLD and was == HOLD)
		tally[&"chase_starts"] += int(mode == CHASE and was != CHASE)
		tally[&"chase_ends"] += int(mode != CHASE and was == CHASE)
		var held: int = targets[row]
		var at: int = -1
		if held != 0:
			at = ids.bsearch(held)
			if at >= rows or ids[at] != held:
				at = -1
		if at < 0:
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
			continue
		var order: int = orders[row]
		if (order != ATTACK_MOVE and order != ATTACK) or (tick + ids[row]) % line_period != 0:
			continue
		if order == ATTACK:
			if was == DIRECT and _checked[row] >= 0:
				checks += 1
				tally[&"retests"] += 1
				_count_line(row, at, classes[type], max_x, max_y)
			continue
		var acquire: int = type_acquire[type]
		if d2 <= acquire * acquire:
			checks += 1
			tally[&"chase_edge"] += int(d2 == acquire * acquire)
			_count_line(row, at, classes[type], max_x, max_y)
	tally[&"line_checks"] += checks
	last_checks = checks
	phase_looks = world.stats[World.Stat.TARGET_CANDIDATES]
	phase_checks = world.stats[World.Stat.LINE_CHECKS]


## Adds one line test from `row` to `at` to the counts: how it came out, and whether its segment is
## wide (the left end's y, clamped to the map, times the width of the segment).
func _count_line(row: int, at: int, move_class: int, max_x: int, max_y: int) -> void:
	var x0: int = world.pos_x[row]
	var y0: int = world.pos_y[row]
	var x1: int = world.pos_x[at]
	var y1: int = world.pos_y[at]
	if FixedMath.line_clear(world, x0, y0, x1, y1, move_class):
		tally[&"clear"] += 1
	else:
		tally[&"blocked"] += 1
	var flip: bool = x0 > x1
	var left_x: int = clampi(x1 if flip else x0, 0, max_x)
	var left_y: int = clampi(y1 if flip else y0, 0, max_y)
	var right_x: int = clampi(x0 if flip else x1, 0, max_x)
	tally[&"wide_lines"] += int(left_y * (right_x - left_x) > INT32_MAX)
