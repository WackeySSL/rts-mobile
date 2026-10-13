class_name FlowField
extends RefCounted
## One integer flow field (ADR 0008 section 3): Dijkstra from a goal cell with Dial's buckets over
## the map padded by one blocked ring, settled in slices by advance(). `next` integrates while
## `cost` is served; completion swaps them. ADR 0013 section 2: all state advance() changes is in
## Packed arrays and int members, sized once by reserve(). Padded cell = (ty + 1) * (cols + 2) +
## tx + 1; every method argument and result is a plain cell ty * cols + tx.

## The cost of a cell no integration reached: rock, the padding ring, enclosed ground.
const UNREACHED: int = 0x3FFFFFFF
## Dial's ring: a power of two above the largest step, 255 * 14 / 10 = 357.
const BUCKETS: int = 512
const BUCKET_MASK: int = BUCKETS - 1
## The 8 neighbours in ascending padded-index order: NW, N, NE, W, E, SW, S, SE. A tie in
## best_neighbour goes to the first of them (the lower cell index).
const DX: Array[int] = [-1, 0, 1, -1, 1, -1, 0, 1]
const DY: Array[int] = [-1, -1, -1, 0, 0, 1, 1, 1]
## A step costs the terrain cost of the cell it labels (the cell a unit leaves) times
## STEP_PERCENT / STEP_BASE: 10 / 10 orthogonal, 14 / 10 diagonal.
const STEP_PERCENT: Array[int] = [14, 10, 14, 10, 10, 14, 10, 14]
const STEP_BASE: int = 10
## Every array advance() reads or writes.
const STATE_ARRAYS: Array[StringName] = [
	&"cost", &"next", &"pad_cost", &"bucket_head", &"link_next", &"link_prev"
]
## Derived state, never in the state hash (ADR 0007 section 8): HASHED is empty, and UNHASHED names
## every int, bool and Packed array member once, so the coverage walk finds nothing unlisted.
const HASHED: Array[StringName] = []
const UNHASHED: Array[StringName] = (
	STATE_ARRAYS
	+ [&"goal_cell", &"move_class", &"complete", &"grid_cols", &"cell_count"]
	+ [&"stride", &"level", &"pending"]
)

var goal_cell: int = -1
var move_class: int = 0
## True while `cost` is a finished field; a re-integration of the same key keeps it true.
var complete: bool = false
## Served to units; all UNREACHED whenever `complete` is false.
var cost: PackedInt32Array = PackedInt32Array()
## Being integrated: the distance of every cell queued or settled so far.
var next: PackedInt32Array = PackedInt32Array()
## The terrain cost of `move_class` per padded cell, 0 = blocked (the ring too).
var pad_cost: PackedByteArray = PackedByteArray()
## The first cell of each bucket (-1 = empty); a bucket is a doubly linked list through
## link_next and link_prev, so a cheaper path moves a cell between buckets in place.
var bucket_head: PackedInt32Array = PackedInt32Array()
var link_next: PackedInt32Array = PackedInt32Array()
var link_prev: PackedInt32Array = PackedInt32Array()
var grid_cols: int = 0
var cell_count: int = 0
var stride: int = 0
## The distance of the bucket being drained, and the cells waiting in the buckets.
var level: int = 0
var pending: int = 0


## Sizes every array for a cols x rows map; a no-op while the padded size is unchanged. A resize
## ends `complete`: the old cost no longer fits the map, whatever key comes next.
func reserve(cols: int, rows: int) -> void:
	var padded: int = (maxi(cols, 0) + 2) * (maxi(rows, 0) + 2)
	if cost.size() == padded:
		return
	complete = false
	cost.resize(padded)
	next.resize(padded)
	pad_cost.resize(padded)
	link_next.resize(padded)
	link_prev.resize(padded)
	bucket_head.resize(BUCKETS)


## Starts integrating from `goal_cell` for `move_class`; `costs` is the World's `move_cost`
## (entry `class * cells + cell`, 0 = blocked). The goal is seeded at 0 whatever its terrain
## (an attack field may be keyed on ground the class cannot enter). A goal outside the map or a
## class `costs` lacks completes at once, all UNREACHED, so a cache never waits on it. The old
## `cost` keeps serving only for the same key (a re-integration); a new key serves nothing, so a
## caller that recycles a slot for the same key on another map clears `complete` first.
@warning_ignore("shadowed_variable", "integer_division")
func begin(goal_cell: int, move_class: int, costs: PackedByteArray, cols: int, rows: int) -> void:
	reserve(cols, rows)
	complete = complete and goal_cell == self.goal_cell and move_class == self.move_class
	self.goal_cell = goal_cell
	self.move_class = move_class
	grid_cols = maxi(cols, 0)
	cell_count = grid_cols * maxi(rows, 0)
	stride = grid_cols + 2
	if not complete:
		cost.fill(UNREACHED)
	next.fill(UNREACHED)
	bucket_head.fill(-1)
	level = 0
	pending = 0
	var base: int = move_class * cell_count
	var usable: bool = goal_cell >= 0 and goal_cell < cell_count and move_class >= 0
	if not usable or base + cell_count > costs.size():
		_swap()
		return
	var padded: PackedByteArray = pad_cost
	padded.fill(0)
	for y: int in rows:
		var src: int = base + y * cols
		var dst: int = (y + 1) * stride + 1
		for x: int in cols:
			padded[dst + x] = costs[src + x]
	var goal: int = (goal_cell / cols + 1) * stride + goal_cell % cols + 1
	next[goal] = 0
	link_next[goal] = -1
	bucket_head[0] = goal
	pending = 1


## Settles at most `budget_cells` cells in order of distance and returns how many it settled.
## The call that settles the last queued cell swaps `next` into `cost` and sets `complete`.
@warning_ignore("integer_division")
func advance(budget_cells: int) -> int:
	if pending == 0 or budget_cells <= 0:
		return 0
	var dist_of: PackedInt32Array = next
	var head: PackedInt32Array = bucket_head
	var after: PackedInt32Array = link_next
	var before: PackedInt32Array = link_prev
	var terrain: PackedByteArray = pad_cost
	var width: int = stride
	var queued: int = pending
	var dist: int = level
	var settled: int = 0
	while settled < budget_cells and queued > 0:
		var cell: int = head[dist & BUCKET_MASK]
		if cell == -1:
			dist += 1
			continue
		# A pop moves only the head: the new head keeps a stale link_prev, never read because a
		# cell of the bucket being drained is never relaxed (old <= dist).
		head[dist & BUCKET_MASK] = after[cell]
		queued -= 1
		settled += 1
		for k: int in 8:
			var other: int = cell + DY[k] * width + DX[k]
			var old: int = dist_of[other]
			if old <= dist or terrain[other] == 0:
				continue
			var through: int = dist + terrain[other] * STEP_PERCENT[k] / STEP_BASE
			if through >= old:
				continue
			# A diagonal step needs both orthogonal cells open (no corner cutting).
			if STEP_PERCENT[k] != STEP_BASE:
				if terrain[cell + DX[k]] == 0 or terrain[cell + DY[k] * width] == 0:
					continue
			if old == UNREACHED:
				queued += 1
			else:
				var older: int = before[other]
				var newer: int = after[other]
				if older == -1:
					head[old & BUCKET_MASK] = newer
				else:
					after[older] = newer
				if newer != -1:
					before[newer] = older
			var first: int = head[through & BUCKET_MASK]
			after[other] = first
			before[other] = -1
			if first != -1:
				before[first] = other
			head[through & BUCKET_MASK] = other
			dist_of[other] = through
	pending = queued
	level = dist
	if queued == 0:
		_swap()
	return settled


## The neighbour with the lowest served cost strictly below this cell's, a diagonal only past
## two reached orthogonal cells (the corner rule, read from `cost`). -1 at the goal and at an
## unreached or outside cell, so also while `cost` has not completed.
@warning_ignore("integer_division")
func best_neighbour(cell: int) -> int:
	if cell < 0 or cell >= cell_count:
		return -1
	var served: PackedInt32Array = cost
	var here: int = (cell / grid_cols + 1) * stride + cell % grid_cols + 1
	var best: int = served[here]
	if best == UNREACHED:
		return -1
	var pick: int = -1
	for k: int in 8:
		var other: int = here + DY[k] * stride + DX[k]
		if served[other] >= best:
			continue
		if STEP_PERCENT[k] != STEP_BASE:
			if served[here + DX[k]] == UNREACHED or served[here + DY[k] * stride] == UNREACHED:
				continue
		best = served[other]
		pick = other
	if pick == -1:
		return -1
	return (pick / stride - 1) * grid_cols + pick % stride - 1


func _swap() -> void:
	var served: PackedInt32Array = cost
	cost = next
	next = served
	complete = true
