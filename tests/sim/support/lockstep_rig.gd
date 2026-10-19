extends RefCounted
## The rig of the INTEGRATE lockstep suites (ADR 0013 section 4, plan P37n3): two Worlds built by
## one function, the first running the GDScript phases (the twin) and the second the C++ kernels,
## each stepped by its own MatchLoop with the same orders, and compared after every tick: the
## state hash and the full state of StateDiff (every shape list, every scalar, the flow cache and
## its slots). While it steps, the rig counts on the twin's side what the run reached (a unit
## following a field, a field with no next tile, an ATTACK re-key, a unit's own field, an order
## that ended, every slot referenced, and what the slot tables did: a key taken by a free slot, a
## key found in its slot, a slot recycled for another key), so that a case can assert that it did
## not pass by never reaching a rule. Not a test suite.

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const INTEGRATE: int = SimProbe.Phase.INTEGRATE
const FIELD: int = World.NavMode.FIELD
const ATTACK: int = World.Order.ATTACK
const IDLE: int = World.Order.IDLE
## The names of the counts (each starts at 0).
const TALLY: Array[StringName] = [
	&"ticks",
	&"field",
	&"named",
	&"no_next",
	&"rekeys",
	&"own_fields",
	&"ended",
	&"contended",
	&"fresh",
	&"holds",
	&"recycles"
]

## [the twin's World, the kernels' World].
var worlds: Array[World] = []
var loops: Array[MatchLoop] = []
## What SimImpls.attach found wrong on either World: the test asserts it is empty.
var problems: Array[String] = []
## The counts of the twin's side, by TALLY name.
var tally: Dictionary[StringName, int] = {}


## The pair of `build` (a Callable that returns the same World each call): the twin, and a World
## with the kernels attached. With `integrate_only` the kernels' World runs INTEGRATE in C++ and
## FLOW in GDScript, so that a difference can only be the INTEGRATE kernel's. What SimImpls.attach
## found wrong is added to `found_problems`.
static func pair(
	build: Callable, integrate_only: bool = false, found_problems: Array[String] = []
) -> Array[World]:
	var found: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		found_problems.append_array(SimImpls.attach(world, impl, INTEGRATE))
		if impl == SimImpls.Impl.NATIVE and integrate_only:
			world.native_phases = 1 << INTEGRATE
		found.append(world)
	return found


## "" when the two Worlds agree: the same state hash and the same full state.
static func difference(a: World, b: World) -> String:
	var member: String = StateDiff.first(a, b)
	var same_hash: bool = a.state_hash() == b.state_hash()
	if member == "" and same_hash:
		return ""
	var named: String = member if member != "" else "no member"
	return "%s (state hash %s)" % [named, "equal" if same_hash else "differs"]


## The ids of the units of `player`, ascending.
static func ids_of(world: World, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		if world.owner[row] == player:
			ids.append(world.unit_id[row])
	return ids


## A rig over the pair of `build`; see pair(). Returns self.
func setup(build: Callable, integrate_only: bool = false) -> RefCounted:
	worlds = pair(build, integrate_only, problems)
	for world: World in worlds:
		loops.append(MatchLoop.create(null, "", 0, world))
	for name: StringName in TALLY:
		tally[name] = 0
	return self


## Steps both Worlds one tick. `orders` is a Callable (world, tick) -> Array[Command] that makes
## the commands of that tick (it may change the World too, which it does the same way for both):
## it runs once per World, so each gets its own Command objects. Returns "" or the difference.
func step(orders: Callable = Callable()) -> String:
	var before: Dictionary[StringName, PackedInt32Array] = _snapshot(worlds[0])
	for index: int in worlds.size():
		var world: World = worlds[index]
		var queued: Array[Command] = []
		if orders.is_valid():
			queued = orders.call(world, world.tick)
		loops[index].step(world, queued)
	_count(before)
	var found: String = difference(worlds[0], worlds[1])
	if found != "":
		return "tick %d: %s" % [worlds[0].tick, found]
	return ""


## Steps `ticks` ticks (see step()); stops at the first difference and returns it, else "".
func run(ticks: int, orders: Callable = Callable()) -> String:
	for _tick: int in ticks:
		var found: String = step(orders)
		if found != "":
			return found
	return ""


func _snapshot(world: World) -> Dictionary[StringName, PackedInt32Array]:
	var rows: Dictionary[StringName, PackedInt32Array] = {}
	rows[&"ids"] = world.unit_id.duplicate()
	rows[&"order"] = world.order.duplicate()
	rows[&"field"] = world.field.duplicate()
	rows[&"key_goal"] = world.flow.key_goal.duplicate()
	rows[&"key_class"] = world.flow.key_class.duplicate()
	rows[&"last_used"] = world.flow.last_used.duplicate()
	rows[&"status"] = world.flow.status.duplicate()
	return rows


## The counts of one tick of the twin's World, from the columns before it and after it.
func _count(before: Dictionary[StringName, PackedInt32Array]) -> void:
	var world: World = worlds[0]
	tally[&"ticks"] += 1
	_count_slots(before)
	var rows: int = world.unit_count()
	if rows != before[&"ids"].size():
		return  # Rows left or joined: the rows no longer line up with the snapshot.
	var old_order: PackedInt32Array = before[&"order"]
	var old_field: PackedInt32Array = before[&"field"]
	var orders: PackedInt32Array = world.order
	var fields: PackedInt32Array = world.field
	var modes: PackedInt32Array = world.nav_mode
	var next_of: PackedInt32Array = world.nav_next
	for row: int in rows:
		if modes[row] == FIELD:
			tally[&"field"] += 1
			if next_of[row] >= 0:
				tally[&"named"] += 1
			elif next_of[row] == Movement.NO_NEXT:
				tally[&"no_next"] += 1
		# Movement.run asks only for a field a unit lacks, so a unit that changed from one slot
		# to another did it in INTEGRATE: an ATTACK re-key, or the unit's own field.
		if old_field[row] >= 0 and fields[row] >= 0 and fields[row] != old_field[row]:
			tally[&"rekeys" if orders[row] == ATTACK else &"own_fields"] += 1
		if old_order[row] != IDLE and orders[row] == IDLE:
			tally[&"ended"] += 1
	if world.flow.status.count(FlowCache.Status.FREE) == 0 and world.flow.ref_count.count(0) == 0:
		tally[&"contended"] += 1


## What the slot tables did in one tick: acquire() gave a free slot a key (`fresh`), found a key in
## its slot (`holds`: the last use moved on) or gave another key to a slot in use (`recycles`).
func _count_slots(before: Dictionary[StringName, PackedInt32Array]) -> void:
	var flow: FlowCache = worlds[0].flow
	for slot: int in flow.status.size():
		var was: int = before[&"status"][slot]
		var same_key: bool = (
			before[&"key_goal"][slot] == flow.key_goal[slot]
			and before[&"key_class"][slot] == flow.key_class[slot]
		)
		if was == FlowCache.Status.FREE and flow.status[slot] != FlowCache.Status.FREE:
			tally[&"fresh"] += 1
		elif was != FlowCache.Status.FREE and not same_key:
			tally[&"recycles"] += 1
		elif same_key and before[&"last_used"][slot] != flow.last_used[slot]:
			tally[&"holds"] += 1
