class_name FlowCache
extends RefCounted
## The flow fields of a match (ADR 0008 section 3): FlowField slots keyed by (goal cell, move
## class, map version) and shared by every unit with that key. References are derived: recount()
## counts the slots a `field` column points at, so nothing releases a slot; acquire() adds a
## provisional reference that the next recount() overwrites. Derived state, never hashed (ADR
## 0007 section 8). configure() allocates every slot's arrays; nothing allocates after it, and
## all state advance() changes is Packed arrays, ints and FlowField members (ADR 0013 section 2).
## run() is the FLOW phase's entry: it hands the phase to the native kernel when the World's mask
## has its bit. recount() and advance() have the same C++ twin as FlowField (core/flow.cpp), and so
## has acquire(), which the INTEGRATE kernel calls for the ATTACK re-key and a unit's own field (the
## GDScript callers in Movement.run keep calling this one): a change to it edits both twins.

## WAITING: the key is set and integration starts at the slot's turn in advance(), the only call
## that has the costs. ACTIVE: begun, done once its field has no pending cells.
enum Status { FREE = 0, WAITING = 1, ACTIVE = 2 }

## Every Packed array of the cache, one entry per slot.
const STATE_ARRAYS: Array[StringName] = [
	&"key_goal", &"key_class", &"key_version", &"last_used", &"ref_count", &"requested", &"status"
]
## Nothing here is in the state hash; UNHASHED names every int and Packed array member once (ADR
## 0007 section 8); a literal that repeats STATE_ARRAYS, because `+` on typed constants gives an
## untyped Array. `fields` and the Status enum need no list; the walk reaches the slots through
## `fields` and each FlowField lists its own members.
const HASHED: Array[StringName] = []
const UNHASHED: Array[StringName] = [
	&"key_goal",
	&"key_class",
	&"key_version",
	&"last_used",
	&"ref_count",
	&"requested",
	&"status",
	&"cols",
	&"rows",
	&"classes",
	&"requests"
]
var cols: int = 0
var rows: int = 0
## A key's move class is 0..classes - 1.
var classes: int = 0
## Requests so far: a new key and a re-integration each take the next number.
var requests: int = 0
## The key of a slot that is not FREE.
var key_goal: PackedInt32Array = PackedInt32Array()
var key_class: PackedInt32Array = PackedInt32Array()
var key_version: PackedInt32Array = PackedInt32Array()
## The tick of the slot's last acquire().
var last_used: PackedInt32Array = PackedInt32Array()
## Rows pointing at the slot at the last recount(), plus one per acquire() of the slot since.
var ref_count: PackedInt32Array = PackedInt32Array()
## The number of the slot's request; advance() serves the lowest first.
var requested: PackedInt32Array = PackedInt32Array()
var status: PackedInt32Array = PackedInt32Array()
var fields: Array[FlowField] = []

## Creates `slots` fields for a cols x rows map and `classes` move classes, all FREE. The only
## place that allocates. The parameters keep the contract's names, so they shadow the members.
@warning_ignore("shadowed_variable")
func configure(cols: int, rows: int, classes: int, slots: int) -> void:
	self.cols = maxi(cols, 0)
	self.rows = maxi(rows, 0)
	self.classes = maxi(classes, 0)
	requests = 0
	fields.clear()
	for i: int in maxi(slots, 0):
		var created: FlowField = FlowField.new()
		created.reserve(self.cols, self.rows)
		fields.append(created)
	for array_name: StringName in STATE_ARRAYS:
		var zeros: PackedInt32Array = PackedInt32Array()  # alloc-ok
		zeros.resize(fields.size())
		set(array_name, zeros)


## The slot of the key: the one holding it (its last use becomes `tick`), else a free slot, else
## the least recently used slot with no references, ties to the lower slot. -1 when the goal is
## no cell of the map or the class is none of `classes`, or when every slot is referenced. A new
## key serves nothing (cost UNREACHED, `complete` false, also for the same key on another map
## version) until advance() has integrated it. The slot returned counts as referenced until the
## next recount(), because the unit stores it in the column only after this call: no new key in
## the same gap takes it. Call invalidate() with a new map version before the first acquire()
## under it, or two slots can end up holding the same key.
func acquire(goal_cell: int, move_class: int, map_version: int, tick: int) -> int:
	if goal_cell < 0 or goal_cell >= cols * rows or move_class < 0 or move_class >= classes:
		return -1
	var free: int = -1
	var oldest: int = -1
	for slot: int in status.size():
		if status[slot] == Status.FREE:
			if free == -1:
				free = slot
		elif (
			key_goal[slot] == goal_cell
			and key_class[slot] == move_class
			and key_version[slot] == map_version
		):
			last_used[slot] = tick
			ref_count[slot] += 1
			return slot
		elif ref_count[slot] == 0 and (oldest == -1 or last_used[slot] < last_used[oldest]):
			oldest = slot
	var pick: int = free if free != -1 else oldest
	if pick == -1:
		return -1
	key_goal[pick] = goal_cell
	key_class[pick] = move_class
	key_version[pick] = map_version
	last_used[pick] = tick
	ref_count[pick] += 1
	_request(pick)
	fields[pick].complete = false
	fields[pick].cost.fill(FlowField.UNREACHED)
	return pick


## Recounts every slot's references from the first `count` entries of the World's `field`
## column; -1 and a number that is no slot count for nobody.
func recount(field_column: PackedInt32Array, count: int) -> void:
	var counts: PackedInt32Array = ref_count
	counts.fill(0)
	var slots: int = counts.size()
	for row: int in mini(count, field_column.size()):
		var slot: int = field_column[row]
		if slot >= 0 and slot < slots:
			counts[slot] += 1


## The references counted at the last recount() and the acquire() calls since; 0 for a number
## that is no slot.
func refs(slot: int) -> int:
	return ref_count[slot] if slot >= 0 and slot < ref_count.size() else 0


## The field of a slot, null for a number that is no slot.
func field(slot: int) -> FlowField:
	return fields[slot] if slot >= 0 and slot < fields.size() else null


## The FLOW phase (ADR 0013 section 3): recounts the references from the World's `field` column,
## then settles at most `budget` cells and adds them to `stats[FLOW_CELLS]`. `Sim.step` passes
## `flow_cells_per_tick`, and 0 on the ticks `MatchLoop` hashes. The kernel does the same when its
## bit is set. No invalidate(): World.set_terrain() made it with the change.
static func run(world: World, budget: int) -> void:
	if ((world.native_phases >> SimProbe.Phase.FLOW) & 1) == 1:
		world.kernels.flow(world, budget)
		return
	world.flow.recount(world.field, world.unit_count())
	world.stats[World.Stat.FLOW_CELLS] += world.flow.advance(world.move_cost, budget)


## Settles at most `budget_cells` cells and returns how many it settled. The field with the
## lowest request number keeps the whole budget until it completes; a field that completes at
## once (a key `costs` cannot integrate) settles nothing, so the next one is served in the same
## call. `costs` is the World's `move_cost`.
func advance(costs: PackedByteArray, budget_cells: int) -> int:
	var settled: int = 0
	while settled < budget_cells:
		var slot: int = _oldest_request()
		if slot == -1:
			break
		if status[slot] == Status.WAITING:
			fields[slot].begin(key_goal[slot], key_class[slot], costs, cols, rows)
			status[slot] = Status.ACTIVE
		settled += fields[slot].advance(budget_cells - settled)
	return settled


## The map is now `map_version`: a referenced slot of another version re-integrates under the new
## one (its field serves the old costs until the swap); one nobody references is dropped, which
## spares a slot acquire() handed out since the last recount(). Call it as soon as the version
## changes, before any acquire() under the new one (see acquire()).
func invalidate(map_version: int) -> void:
	for slot: int in status.size():
		if status[slot] == Status.FREE or key_version[slot] == map_version:
			continue
		if ref_count[slot] > 0:
			key_version[slot] = map_version
			_request(slot)
		else:
			status[slot] = Status.FREE


## Gives the slot the next request number and its integration a (re)start.
func _request(slot: int) -> void:
	requests += 1
	requested[slot] = requests
	status[slot] = Status.WAITING


## The slot with an integration to start or finish and the lowest request number, or -1.
func _oldest_request() -> int:
	var best: int = -1
	for slot: int in status.size():
		var work: bool = status[slot] == Status.WAITING
		if status[slot] == Status.ACTIVE:
			work = fields[slot].pending > 0
		if work and (best == -1 or requested[slot] < requested[best]):
			best = slot
	return best
