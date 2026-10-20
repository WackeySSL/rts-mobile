extends SimProbe
## What a SEPARATION lockstep run reached (plan P39n2): at the SEPARATION mark it re-scans the grid
## the phase has just used, the way the rule scans it (the 3x3 cells of a row's own, row by row,
## each list in ascending id order, stopped by the two caps), and adds what it meets to `tally`.
## The suites assert the counts, so that a run cannot pass by never meeting a cap, a
## near-coincident pair or a unit at the edge of the grid. It only reads: the pushes and the state
## are the phase's own. A probe of the game never reads the World (ADR 0007 section 4); this one is
## a test's, a recorded exception like HandPushProbe. Not a test suite. It is a file of its own, not
## an inner class, because an inner class with a script base would name itself at run time.

## The names of the counts (each starts at 0); see count() for what each one holds.
const NAMES: Array[StringName] = [
	&"ticks",
	&"rows",
	&"looks",
	&"hits",
	&"inside_by_one",
	&"touching",
	&"hit_capped",
	&"look_capped",
	&"fixed",
	&"same_point",
	&"mixed",
	&"edge_rows",
	&"pushed",
	&"at_cap"
]

var world: World
var tally: Dictionary[StringName, int] = {}
## The units looked at by the last mark: it has to equal stats[SEP_PAIRS], the phase's own count.
var last_looks: int = 0


func _init(for_world: World = null) -> void:
	world = for_world
	for name: StringName in NAMES:
		tally[name] = 0


func mark(phase: int) -> void:
	if phase == SimProbe.Phase.SEPARATION:
		last_looks = count(world, tally)


## Adds one SEPARATION phase of `world` (the grid rebuilt, the pushes written) to `into` and returns
## the units looked at. ticks: phases; rows: rows scanned; looks: units looked at; hits: overlaps
## used; inside_by_one: of those, pairs at d2 = reach * reach - 1 (a hit with a push of 0);
## touching: pairs looked at that stand at exactly d2 = reach * reach (no hit); hit_capped: rows
## that stopped at the cap on hits; look_capped: rows that stopped at the cap on looks; fixed: used
## pairs near enough to take the fixed push; same_point: of those, pairs on one point; mixed: used
## pairs of a moving and an idle unit; edge_rows: rows in the first or last column or line of the
## grid; pushed: rows with a push; at_cap: rows with an axis at the push cap.
@warning_ignore("integer_division")
static func count(world: World, into: Dictionary[StringName, int]) -> int:
	into[&"ticks"] += 1
	var grid: SpatialGrid = world.sep_grid
	var cols: int = grid.cols
	var lines: int = grid.rows
	var side: int = grid.cell_milli
	if cols == 0 or side < 1:
		return 0
	var radii: PackedInt32Array = world.type_radius
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var intent_x: PackedInt32Array = world.intent_x
	var intent_y: PackedInt32Array = world.intent_y
	var heads: PackedInt32Array = grid.head
	var links: PackedInt32Array = grid.next
	var scan_cap: int = world.separation_scan
	var hit_cap: int = world.separation_neighbours
	var divisor: int = maxi(world.separation_coincident_divisor, 1)
	var push_max: int = maxi(world.separation_push_max, 0)
	var total: int = 0
	for row: int in world.unit_count():
		var column: int = clampi(pos_x[row] / side, 0, cols - 1)
		var line: int = clampi(pos_y[row] / side, 0, lines - 1)
		var moving: bool = intent_x[row] != 0 or intent_y[row] != 0
		var looked: int = 0
		var hits: int = 0
		for block: int in 9:
			var scan_column: int = column + block % 3 - 1
			var scan_line: int = line + block / 3 - 1
			if scan_column < 0 or scan_column >= cols or scan_line < 0 or scan_line >= lines:
				continue
			var other: int = heads[scan_line * cols + scan_column]
			while other != -1 and looked < scan_cap and hits < hit_cap:
				var next: int = links[other]
				if other != row:
					looked += 1
					var dx: int = pos_x[row] - pos_x[other]
					var dy: int = pos_y[row] - pos_y[other]
					var d2: int = dx * dx + dy * dy
					var reach: int = radii[types[row]] + radii[types[other]]
					var reach2: int = reach * reach
					if d2 < reach2:
						hits += 1
						into[&"inside_by_one"] += int(d2 == reach2 - 1)
						if d2 * divisor * divisor < reach2:
							into[&"fixed"] += 1
							into[&"same_point"] += int(d2 == 0)
						var other_moving: bool = intent_x[other] != 0 or intent_y[other] != 0
						into[&"mixed"] += int(moving != other_moving)
					else:
						into[&"touching"] += int(d2 == reach2)
				other = next
		into[&"rows"] += 1
		into[&"looks"] += looked
		into[&"hits"] += hits
		into[&"hit_capped"] += int(hit_cap > 0 and hits == hit_cap)
		into[&"look_capped"] += int(scan_cap > 0 and looked == scan_cap)
		into[&"edge_rows"] += int(column in [0, cols - 1] or line in [0, lines - 1])
		into[&"pushed"] += int(world.push_x[row] != 0 or world.push_y[row] != 0)
		into[&"at_cap"] += int(
			(
				push_max > 0
				and (absi(world.push_x[row]) == push_max or absi(world.push_y[row]) == push_max)
			)
		)
		total += looked
	return total
