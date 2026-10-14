class_name Movement
extends RefCounted
## Movement v2, the intent and integrate phases (ADR 0007 section 4 steps 6 and 8, ADR 0008
## sections 2 and 4). `run` turns every unit's order into one step of intent per axis; between the
## two phases separation writes its pushes (P39b); `integrate` adds intent and push, clamps the
## result to the map, slides along blocked ground and ends an order on arrival. Integers only: a
## step is truncated division by the floor of the distance, as ADR 0003 section 5 wrote it, so on
## an open map every position equals Phase 1's tick by tick.
##
## Every number comes from the World: speed, move class and the tile grid from the type tables and
## the map (data/units, data/terrain), the line-check period from `line_check_period_ticks`
## (data/rules.tres). The only constant here is the clamp bound of a world with no map.
##
## Navigation modes (`nav_mode`): DIRECT steers straight at the goal; NONE on a unit with an order
## is a DIRECT unit that has not started (a hand-set order), and FIELD steers DIRECT too until P37b
## gives it a field; HOLD gives no intent; CHASE steers straight at the unit in `target` (combat
## sets both, P41). This is the GDScript twin of the INTENTS and INTEGRATE kernels P37n and P37n2
## port later: keep it portable (typed locals, the World's arrays aliased before each loop, no
## allocation, helper calls only at event cadence).

## The clamp bound of a world with no map (nothing to clamp to): the largest int32.
const NO_BOUND: int = 0x7FFFFFFF


## The navigation state a new order or a STOP gives `rows`: `mode` (DIRECT for an order, NONE for a
## stop) and a line to the goal that is not checked yet (`nav_cell` -1). Command cadence only.
static func reset_nav(world: World, rows: PackedInt32Array, mode: int) -> void:
	var modes: PackedInt32Array = world.nav_mode
	var checked: PackedInt32Array = world.nav_cell
	for row: int in rows:
		modes[row] = mode
		checked[row] = -1


## The INTENTS phase: writes `intent_x` and `intent_y` of every row (the scratch arrays are not
## compacted with the rows, so all of them are cleared first): 0 for a unit with no order or in
## HOLD. A moving unit steps towards its goal (or, in CHASE, towards the unit in `target`, as it
## stood at the start of the tick, so the row order cannot matter; a target that is gone leaves it
## on the goal) by at most its speed, and reaches a point within one step exactly.
##
## Line checks: a DIRECT unit whose `nav_cell` is -1 tests the line to its goal on its first tick
## where `(tick + id) % line_check_period_ticks == 0`, so a group order spreads its checks over the
## period instead of one tick. The check counts in `stats[LINE_CHECKS]` and writes the unit's cell
## into `nav_cell`, which ends the checking: a clear line stays clear on a static map. A blocked
## line also keeps the unit DIRECT, with the slide of `integrate`, until P37b gives it a field, so
## the result is not used yet.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var ids: PackedInt32Array = world.unit_id
	var orders: PackedInt32Array = world.order
	var modes: PackedInt32Array = world.nav_mode
	var checked: PackedInt32Array = world.nav_cell
	var targets: PackedInt32Array = world.target
	var types: PackedInt32Array = world.type_index
	var speeds: PackedInt32Array = world.type_speed
	var classes: PackedInt32Array = world.type_move_class
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	var intent_x: PackedInt32Array = world.intent_x
	var intent_y: PackedInt32Array = world.intent_y
	var count: int = ids.size()
	var period: int = maxi(world.line_check_period_ticks, 1)
	var tick: int = world.tick
	var checks: int = 0
	intent_x.fill(0)
	intent_y.fill(0)
	for row: int in count:
		if orders[row] == World.Order.IDLE:
			continue
		var mode: int = modes[row]
		if mode == World.NavMode.HOLD:
			continue
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		var aim_x: int = goal_x[row]
		var aim_y: int = goal_y[row]
		var type: int = types[row]
		if mode == World.NavMode.CHASE:
			var at: int = ids.bsearch(targets[row])
			if at < count and ids[at] == targets[row]:
				aim_x = pos_x[at]
				aim_y = pos_y[at]
		else:
			if mode == World.NavMode.NONE:
				modes[row] = World.NavMode.DIRECT
			if checked[row] == -1 and (tick + ids[row]) % period == 0:
				checks += 1
				FixedMath.line_clear(world, x, y, aim_x, aim_y, classes[type])
				checked[row] = world.cell_of(x, y)
		var speed: int = speeds[type]
		var dx: int = aim_x - x
		var dy: int = aim_y - y
		var d2: int = dx * dx + dy * dy
		if d2 <= speed * speed:
			intent_x[row] = dx
			intent_y[row] = dy
		else:
			var distance: int = FixedMath.isqrt(d2)
			intent_x[row] = dx * speed / distance
			intent_y[row] = dy * speed / distance
	world.stats[World.Stat.LINE_CHECKS] += checks


## The INTEGRATE phase: every unit moves by its intent plus its push, clamped to the map. When the
## new point is on a tile its class cannot enter (cost 0), the x move alone is tried, then the y
## move alone, else the unit stays: a unit that steers into rock slides along it, and its centre
## never enters a blocked tile. Only the destination is tested, so a unit that started on a
## blocked tile (a changed map) may still move to a passable one. Arrival is Phase 1's: a unit
## that steered at its goal (not in HOLD or CHASE) with an order other than ATTACK arrives on the
## tick its goal is within one step at the start of the tick (d2 <= speed^2, the snap of `run`), so
## its order goes IDLE and its navigation state is cleared, also when a push or the slide kept it
## off the goal itself. An ATTACK unit keeps its order and its target until combat ends it (P41).
## Rows are independent here, as the pushes were all written before this phase.
@warning_ignore("integer_division")
static func integrate(world: World) -> void:
	var orders: PackedInt32Array = world.order
	var modes: PackedInt32Array = world.nav_mode
	var checked: PackedInt32Array = world.nav_cell
	var types: PackedInt32Array = world.type_index
	var speeds: PackedInt32Array = world.type_speed
	var classes: PackedInt32Array = world.type_move_class
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	var intent_x: PackedInt32Array = world.intent_x
	var intent_y: PackedInt32Array = world.intent_y
	var push_x: PackedInt32Array = world.push_x
	var push_y: PackedInt32Array = world.push_y
	var cost: PackedByteArray = world.move_cost
	var cols: int = world.map_cols
	var cells: int = cols * world.map_rows
	var tile: int = World.MILLI_PER_TILE
	var max_x: int = NO_BOUND
	var max_y: int = NO_BOUND
	if cells > 0:
		max_x = mini(world.map_w, cols * tile) - 1
		max_y = mini(world.map_h, world.map_rows * tile) - 1
	for row: int in world.unit_id.size():
		var order: int = orders[row]
		var step_x: int = intent_x[row] + push_x[row]
		var step_y: int = intent_y[row] + push_y[row]
		if order == World.Order.IDLE and step_x == 0 and step_y == 0:
			continue
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		if order != World.Order.IDLE and order != World.Order.ATTACK:
			var mode: int = modes[row]
			if mode != World.NavMode.HOLD and mode != World.NavMode.CHASE:
				var speed: int = speeds[types[row]]
				var dx: int = goal_x[row] - x
				var dy: int = goal_y[row] - y
				if dx * dx + dy * dy <= speed * speed:
					orders[row] = World.Order.IDLE
					modes[row] = World.NavMode.NONE
					checked[row] = -1
		if step_x == 0 and step_y == 0:
			continue
		var new_x: int = clampi(x + step_x, 0, max_x)
		var new_y: int = clampi(y + step_y, 0, max_y)
		if cells > 0:
			var base: int = classes[types[row]] * cells
			if cost[base + (new_y / tile) * cols + new_x / tile] == 0:
				var own_column: int = clampi(x, 0, max_x) / tile
				var own_line: int = clampi(y, 0, max_y) / tile
				if cost[base + own_line * cols + new_x / tile] != 0:
					new_y = y
				elif cost[base + (new_y / tile) * cols + own_column] != 0:
					new_x = x
				else:
					new_x = x
					new_y = y
		pos_x[row] = new_x
		pos_y[row] = new_y
