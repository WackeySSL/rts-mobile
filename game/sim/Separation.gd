class_name Separation
extends RefCounted
## The SEPARATION phase (ADR 0007 section 4 step 7, ADR 0008 section 4): every unit is pushed
## away from the units it overlaps. `run` reads the positions, the type radii, the intents (a
## unit is "moving" when its intent is not 0) and `world.sep_grid`, which the caller has rebuilt
## from this tick's positions (the GRIDS phase, P39b): `run` never rebuilds a grid. It writes
## `push_x` and `push_y` of every row, 0 for a unit with no neighbour in reach, and adds the
## units it looked at to `stats[SEP_PAIRS]`. It moves nothing: `Movement.integrate` adds the
## push to the intent. The pushes are Jacobi style, all computed from the positions at the start
## of the tick, so the result does not depend on which unit comes first.
##
## This is the GDScript twin of the SEPARATION kernel P39n ports later: keep it portable
## (integers only, the World's arrays aliased into typed locals before the loop, no allocation,
## rows and grid lists in ascending id order). Every tuning number comes from the World's rule
## ints (data/rules.tres); the constants below are structure, not balance.

## The 3x3 block of cells around a unit's own, scanned row by row.
const BLOCK_CELLS: int = 9
const BLOCK_SIDE: int = 3
## Shares are percent of a pair push.
const PERCENT: int = 100
## Two units in the same state (both moving or both not) split a pair push 50/50.
const EQUAL_SHARE: int = 50

## For each unit in id order, scans the 3x3 cells around its own, row by row, each cell's list
## in ascending id order. It looks at most at `separation_scan` other units and uses the first
## `separation_neighbours` that overlap (`d2 < R * R`, `R` the sum of the two radii).
##
## The pair push is sqrt-free: `(dx, dy) * (R*R - d2) / (2 * R*R)`, truncated toward zero per
## axis, with (dx, dy) from the other unit to this one. It is weak when the units nearly
## coincide, so a pair closer than `C = R / separation_coincident_divisor`
## (`d2 * divisor^2 < R*R`) gets the fixed push `min(C, separation_push_max)` instead, on each
## axis where dx or dy is not 0, signed away from the other unit. A pair on exactly the same
## point gets it along x only, the lower id towards -x. At `d = C` the formula takes over, with
## a larger push.
##
## A pair push is split between the two units: each takes its own share of it while it scans
## the other. Units in the same state take 50% each; an idle unit next to a moving one takes
## `separation_idle_share` percent and the moving one the rest, so moving units shoulder through
## idle ones. Each share is truncated toward zero. A unit's summed push is clamped to
## `separation_push_max` per axis. Each unit sums its own neighbours, so the caps can leave the
## two sides of a pair unequal.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var types: PackedInt32Array = world.type_index
	var radii: PackedInt32Array = world.type_radius
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var intent_x: PackedInt32Array = world.intent_x
	var intent_y: PackedInt32Array = world.intent_y
	var push_x: PackedInt32Array = world.push_x
	var push_y: PackedInt32Array = world.push_y
	var grid: SpatialGrid = world.sep_grid
	var heads: PackedInt32Array = grid.head
	var links: PackedInt32Array = grid.next
	var cols: int = grid.cols
	var lines: int = grid.rows
	var side: int = grid.cell_milli
	var count: int = world.unit_id.size()
	var scan_cap: int = world.separation_scan
	var hit_cap: int = world.separation_neighbours
	var idle_share: int = clampi(world.separation_idle_share, 0, PERCENT)
	var divisor: int = maxi(world.separation_coincident_divisor, 1)
	var push_max: int = maxi(world.separation_push_max, 0)
	var pairs: int = 0
	push_x.fill(0)
	push_y.fill(0)
	if cols == 0:
		return
	for row: int in count:
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		var radius: int = radii[types[row]]
		var moving: bool = intent_x[row] != 0 or intent_y[row] != 0
		var column: int = clampi(x / side, 0, cols - 1)
		var line: int = clampi(y / side, 0, lines - 1)
		var sum_x: int = 0
		var sum_y: int = 0
		var looked: int = 0
		var hits: int = 0
		var block: int = 0
		# The inner loop enforces the caps; testing them here as well only skips the cells left.
		while block < BLOCK_CELLS and looked < scan_cap and hits < hit_cap:
			var scan_column: int = column + block % BLOCK_SIDE - 1
			var scan_line: int = line + block / BLOCK_SIDE - 1
			block += 1
			if scan_column < 0 or scan_column >= cols or scan_line < 0 or scan_line >= lines:
				continue
			var next: int = heads[scan_line * cols + scan_column]
			while next != -1 and looked < scan_cap and hits < hit_cap:
				var other: int = next
				next = links[other]
				if other == row:
					continue
				looked += 1
				var dx: int = x - pos_x[other]
				var dy: int = y - pos_y[other]
				var d2: int = dx * dx + dy * dy
				var reach: int = radius + radii[types[other]]
				var reach2: int = reach * reach
				if d2 >= reach2:
					continue
				hits += 1
				var pair_x: int = 0
				var pair_y: int = 0
				if d2 * divisor * divisor < reach2:
					var fixed_push: int = mini(reach / divisor, push_max)
					if d2 == 0:
						pair_x = -fixed_push if row < other else fixed_push
					else:
						pair_x = fixed_push * signi(dx)
						pair_y = fixed_push * signi(dy)
				else:
					var weight: int = reach2 - d2
					pair_x = dx * weight / (2 * reach2)
					pair_y = dy * weight / (2 * reach2)
				var share: int = EQUAL_SHARE
				var other_moving: bool = intent_x[other] != 0 or intent_y[other] != 0
				if moving != other_moving:
					share = PERCENT - idle_share if moving else idle_share
				sum_x += pair_x * share / PERCENT
				sum_y += pair_y * share / PERCENT
		pairs += looked
		push_x[row] = clampi(sum_x, -push_max, push_max)
		push_y[row] = clampi(sum_y, -push_max, push_max)
	world.stats[World.Stat.SEP_PAIRS] += pairs
