class_name PerfProbeTick
extends RefCounted
## Mock of the optimised Phase 2 tick (ADR 0008 Context) for the phone perf probe (plan P26s): 150
## units in the arena window of a 64x64 map. Per tick: two linked-list grids, separation and
## integration, targeting (a fifth of the units) and, for units that changed tile, a flow lookup
## and a fog stamp (one player per tick, a 13x13 square of row spans standing in for the disc). A
## cost model in the aliased, allocation-free style of ADR 0007 section 1, so phone and CI run the
## same code. `flow_slice()` is a Dial's-bucket Dijkstra (ADR 0008 section 3). Integers only,
## milli-tiles; a fixed LCG replaces randomness.

@warning_ignore_start("integer_division")

const UNITS: int = 150
const SIDE: int = UNITS / 2  ## Rows 0-74 are player 0's, 75-149 player 1's.
const COLS: int = 64
const PAD: int = 66  ## The flow grid carries a blocked ring.
const UNREACHED: int = 0x3FFFFFFF
const STEPS: Array[int] = [-67, -66, -65, -1, 1, 65, 66, 67]  ## Flow neighbours and their costs.
const COSTS: Array[int] = [14, 10, 14, 10, 10, 14, 10, 14]  ## Per 10 of terrain cost (x14 / 10).
## The two orthogonal cells a diagonal step passes between; both are the cell itself (always open)
## for an orthogonal step, so every step runs the same corner check.
const SIDE_X: Array[int] = [-1, 0, 1, 0, 0, -1, 0, 1]
const SIDE_Y: Array[int] = [-66, 0, -66, 0, 0, 66, 0, 66]

var tick: int = 0
var x: PackedInt32Array = _ints(UNITS, 0)
var y: PackedInt32Array = _ints(UNITS, 0)
var target: PackedInt32Array = _ints(UNITS, -1)  ## Nearest enemy row, -1 = none.
var seen: PackedInt32Array = _ints(2 * COLS * COLS, 0)  ## Sight squares on a cell, per player.
var dirty: PackedInt32Array = _ints(COLS * COLS, 0)  ## Player 0 cells that flipped 0 <-> 1.
var dirty_count: int = 0
var flow_cost: PackedInt32Array = _ints(PAD * PAD, UNREACHED)
var slice_cells: int = 0  ## Cells the last `flow_slice()` settled (short at a field's end).

var _goal_x: PackedInt32Array = _ints(UNITS, 0)
var _goal_y: PackedInt32Array = _ints(UNITS, 0)
var _stamped: PackedInt32Array = _ints(UNITS, -1)  ## Tile of the last fog stamp.
var _sep_head: PackedInt32Array = _ints(COLS * COLS, -1)
var _sep_next: PackedInt32Array = _ints(UNITS, -1)
var _tgt_head: PackedInt32Array = _ints(16 * 16, -1)  ## 4-tile cells.
var _tgt_next: PackedInt32Array = _ints(UNITS, -1)
var _terrain: PackedInt32Array = _ints(PAD * PAD, 0)  ## Move cost per padded cell, 0 = blocked.
var _bucket: PackedInt32Array = _ints(16 * PAD * PAD, 0)  ## 16 Dial buckets, one stack each.
var _bucket_n: PackedInt32Array = _ints(16, 0)
var _dist: int = 0
var _pending: int = 0
var _lcg: int = 42


func _init() -> void:
	for ty: int in COLS:  # A ridge at columns 31-32 with three gaps inside rows 25-39.
		for tx: int in COLS:
			var gap: bool = ty >= 25 and ty <= 39 and (ty - 25) % 5 < 2
			_terrain[(ty + 1) * PAD + tx + 1] = 0 if (tx == 31 or tx == 32) and not gap else 10
	for i: int in UNITS:
		x[i] = 19000 + (i / SIDE) * 14000 + _next(12000)
		y[i] = 24500 + _next(15000)
		_new_goal(i)
	for _warm: int in 3:  # Both players get their first stamp, as World.prepare() does.
		step()


## Plays one tick and returns its wall time in microseconds.
func step() -> int:
	var started: int = Time.get_ticks_usec()
	tick += 1
	_rebuild(_sep_head, _sep_next, 1000, COLS)
	_rebuild(_tgt_head, _tgt_next, 4000, 16)
	_move()
	_acquire()
	_tile_events()
	return Time.get_ticks_usec() - started


## Settles up to `budget` flow cells and returns the wall time in microseconds. A finished field
## is replaced by the next goal at the start of the following call. The steps follow ADR 0008
## section 3: the cost of the cell stepped onto (x14 / 10 on a diagonal), and no diagonal step
## past a blocked orthogonal neighbour.
func flow_slice(budget: int) -> int:
	var started: int = Time.get_ticks_usec()
	var cost: PackedInt32Array = flow_cost
	var terrain: PackedInt32Array = _terrain
	var count: PackedInt32Array = _bucket_n
	if _pending == 0:
		var goal: int = (1 + _next(COLS)) * PAD + 1 + _next(30)
		cost.fill(UNREACHED)
		count.fill(0)
		cost[goal] = 0
		_bucket[0] = goal
		count[0] = 1
		_dist = 0
		_pending = 1
	var settled: int = 0
	while settled < budget and _pending > 0:
		var ring: int = _dist % 16
		if count[ring] == 0:
			_dist += 1
			continue
		count[ring] -= 1
		var cell: int = _bucket[ring * PAD * PAD + count[ring]]
		_pending -= 1
		if cost[cell] != _dist:
			continue  # Stale: a shorter way came after this entry.
		settled += 1
		for k: int in 8:
			var next: int = cell + STEPS[k]
			var enter: int = terrain[next]  # Cost of the cell stepped onto.
			if enter == 0 or terrain[cell + SIDE_X[k]] == 0 or terrain[cell + SIDE_Y[k]] == 0:
				continue  # Blocked, or a diagonal that would cut a corner.
			var next_cost: int = _dist + enter * COSTS[k] / 10
			if next_cost < cost[next]:
				var next_ring: int = next_cost % 16
				cost[next] = next_cost
				_bucket[next_ring * PAD * PAD + count[next_ring]] = next
				count[next_ring] += 1
				_pending += 1
	slice_cells = settled
	return Time.get_ticks_usec() - started


## Nearest-rank percentile (`p` in 1..100) of `values`; 0 when there are none.
static func percentile(values: PackedFloat64Array, p: int) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return 0.0 if sorted.is_empty() else sorted[ceili(p * sorted.size() / 100.0) - 1]


static func mean(values: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return sum / maxi(values.size(), 1)


static func _ints(count: int, value: int) -> PackedInt32Array:
	var ints: PackedInt32Array = PackedInt32Array()
	ints.resize(count)
	ints.fill(value)
	return ints


func _next(n: int) -> int:
	_lcg = (_lcg * 1103515245 + 12345) & 0x7FFFFFFF
	return (_lcg >> 8) % n


## The other half of the arena, so the armies keep crossing and crowding in the middle.
func _new_goal(i: int) -> void:
	_goal_x[i] = (34000 if x[i] < 32000 else 20000) + _next(10000)
	_goal_y[i] = 25000 + _next(14000)


## Resets the grid, then inserts the rows in descending order (cells list ascending rows).
func _rebuild(head: PackedInt32Array, link: PackedInt32Array, size: int, cols: int) -> void:
	head.fill(-1)
	for i: int in range(UNITS - 1, -1, -1):
		var cell: int = (y[i] / size) * cols + x[i] / size
		link[i] = head[cell]
		head[cell] = i


## Sqrt-free pair pushes over the 3x3 cells (16 looked at, 8 used), one isqrt step to the goal.
func _move() -> void:
	var px: PackedInt32Array = x
	var py: PackedInt32Array = y
	var square: int = 800 * 800
	for i: int in UNITS:
		var push_x: int = 0
		var push_y: int = 0
		var looked: int = 0
		var hits: int = 0
		for gy: int in range(maxi(py[i] / 1000 - 1, 0), mini(py[i] / 1000 + 2, COLS)):
			for gx: int in range(maxi(px[i] / 1000 - 1, 0), mini(px[i] / 1000 + 2, COLS)):
				var j: int = _sep_head[gy * COLS + gx]
				while j != -1 and looked < 16 and hits < 8:
					var dx: int = px[i] - px[j]
					var dy: int = py[i] - py[j]
					var d2: int = dx * dx + dy * dy
					if j != i:
						looked += 1
						if d2 < square:
							hits += 1
							push_x += dx * (square - d2) / (2 * square)
							push_y += dy * (square - d2) / (2 * square)
					j = _sep_next[j]
		var to_x: int = _goal_x[i] - px[i]
		var to_y: int = _goal_y[i] - py[i]
		var to_d2: int = to_x * to_x + to_y * to_y
		if to_d2 > 120 * 120:
			var d: int = FixedMath.isqrt(to_d2)
			px[i] += to_x * 120 / d
			py[i] += to_y * 120 / d
		else:
			px[i] = _goal_x[i]
			py[i] = _goal_y[i]
			_new_goal(i)
		px[i] = clampi(px[i] + clampi(push_x, -60, 60), 0, COLS * 1000 - 1)
		py[i] = clampi(py[i] + clampi(push_y, -60, 60), 0, COLS * 1000 - 1)


## A fifth of the units scan the 5x5 targeting cells around them for the nearest enemy.
func _acquire() -> void:
	var px: PackedInt32Array = x
	var py: PackedInt32Array = y
	for i: int in range(tick % 5, UNITS, 5):
		var best: int = -1
		var best_d2: int = 5500 * 5500
		for gy: int in range(maxi(py[i] / 4000 - 2, 0), mini(py[i] / 4000 + 3, 16)):
			for gx: int in range(maxi(px[i] / 4000 - 2, 0), mini(px[i] / 4000 + 3, 16)):
				var j: int = _tgt_head[gy * 16 + gx]
				while j != -1:
					var dx: int = px[i] - px[j]
					var dy: int = py[i] - py[j]
					if j / SIDE != i / SIDE and dx * dx + dy * dy < best_d2:
						best = j
						best_d2 = dx * dx + dy * dy
					j = _tgt_next[j]
		target[i] = best


## Player 0 on ticks 0 and player 1 on ticks 1 of every 3 (ADR 0010): units that changed tile
## look up their lowest-cost flow neighbour and move their fog stamp.
func _tile_events() -> void:
	var player: int = tick % 3
	if player > 1:
		return
	for i: int in range(player * SIDE, (player + 1) * SIDE):
		var cell: int = (y[i] / 1000) * COLS + x[i] / 1000
		if cell == _stamped[i]:
			continue
		var at: int = cell + PAD + 1 + 2 * (y[i] / 1000)  # The same tile in the padded flow grid.
		var best: int = flow_cost[at]
		for k: int in 8:
			best = mini(best, flow_cost[at + STEPS[k]])
		_stamp(player, _stamped[i], -1)
		_stamp(player, cell, 1)
		_stamped[i] = cell


## Adds `delta` to the sight counts of the 13x13 square around `cell`, clipped to the map.
func _stamp(player: int, cell: int, delta: int) -> void:
	if cell < 0:
		return
	var counts: PackedInt32Array = seen
	for row: int in range(maxi(cell / COLS - 6, 0), mini(cell / COLS + 7, COLS)):
		for col: int in range(maxi(cell % COLS - 6, 0), mini(cell % COLS + 7, COLS)):
			var at: int = player * COLS * COLS + row * COLS + col
			counts[at] += delta
			if (counts[at] == 0 or counts[at] == delta) and player == 0 and dirty_count < 4096:
				dirty[dirty_count] = row * COLS + col
				dirty_count += 1
