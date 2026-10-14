class_name Movement
extends RefCounted
## Movement v2, the intent and integrate phases (ADR 0007 section 4 steps 6 and 8, ADR 0008
## sections 2 and 4). `run` turns every unit's order into one step of intent per axis; between the
## two phases separation writes its pushes (P39b); `integrate` adds intent and push, clamps the
## result to the map, slides along blocked ground and ends an order on arrival. Integers only: a
## step is truncated division by the floor of the distance, as ADR 0003 section 5 wrote it, so on
## an open map every position equals Phase 1's tick by tick, for goals inside 0..map-1 (what
## Formation gives for any type with a radius of 1 or more; a goal on the far edge itself, which a
## radius of 0 allows, ends one milli short, as the clamp keeps every position in 0..map-1).
##
## Every number comes from the World: speed, move class and the tile grid from the type tables and
## the map (data/units, data/terrain), the line-check period from `line_check_period_ticks`
## (data/rules.tres). The only constant here is the upper clamp bound of a world with no map.
##
## Navigation modes (`nav_mode`): DIRECT steers straight at the goal; NONE on a unit with an order
## is a DIRECT unit that has not started (a hand-set order); FIELD follows the flow field in
## `field` (the slot) and steers DIRECT while that field is pending; HOLD gives no intent; CHASE
## steers straight at the unit in `target` (combat sets both, P41). This is the GDScript twin of
## the INTENTS and INTEGRATE kernels P37n and P37n2 port later: keep it portable (typed locals, the
## World's arrays aliased before each loop, no allocation, helper calls only at event cadence).

## The upper clamp bound of a world with no map (nothing to clamp to above): the largest int32. The
## lower bound stays 0 on every world, so a position never goes negative.
const NO_BOUND: int = 0x7FFFFFFF


## The navigation state a new order or a STOP gives `rows`: `mode` (DIRECT for an order, NONE for a
## stop), a line to the goal that is not checked yet (`nav_cell` -1), no field (nothing releases a
## slot by hand: the cache recounts its references from the `field` column), no next tile and a
## fresh stall count. Command cadence only.
static func reset_nav(world: World, rows: PackedInt32Array, mode: int) -> void:
	var modes: PackedInt32Array = world.nav_mode
	var checked: PackedInt32Array = world.nav_cell
	var slot_of: PackedInt32Array = world.field
	var next_of: PackedInt32Array = world.nav_next
	var best_of: PackedInt32Array = world.best_dist
	var stall_of: PackedInt32Array = world.stall
	for row: int in rows:
		modes[row] = mode
		checked[row] = -1
		slot_of[row] = -1
		next_of[row] = -1
		best_of[row] = FlowField.UNREACHED
		stall_of[row] = 0


## The INTENTS phase: writes `intent_x` and `intent_y` of every row (the scratch arrays are not
## compacted with the rows, so all of them are cleared first): 0 for a unit with no order or in
## HOLD. A moving unit steps towards its aim by at most its speed and reaches a point within one
## step exactly. The aim is the goal; in CHASE the unit in `target`, as it stood at the start of
## the tick, so the row order cannot matter (a target that is gone leaves it on the goal); in FIELD
## the centre of the tile in `nav_next`, once there is one.
##
## Line checks (ADR 0008 section 2): a DIRECT unit whose `nav_cell` is -1 tests the line to its goal
## on its first tick where `(tick + id) % line_check_period_ticks == 0`, so a group order spreads
## its checks over the period. A clear line stays clear on a static map: the unit's cell goes into
## `nav_cell`, which ends the checking. A blocked line asks the cache for a field of the unit's
## class that serves the goal (_field_for: one that a group already holds, else the goal's own
## tile): the unit is FIELD with that slot, or stays DIRECT and unchecked (it asks again on its
## next turn) when every slot is referenced. A FIELD unit checks the line again each time it enters
## a tile, and a clear line makes it DIRECT with no field. Every check counts in
## `stats[LINE_CHECKS]`.
##
## A FIELD unit steers DIRECT while its field is pending. `nav_next`, the neighbour tile that
## `best_neighbour` names (-1 for none), is set at event cadence: when the unit enters a tile, on
## the first tick its field is complete, and on the unit's line-check turn, so that a field the
## cache re-integrated after a map change (it serves the old costs until the swap, and stays
## `complete`) sends the unit on within a period. At the goal tile and on ground the field does not
## reach there is no next tile and the unit steers at its goal; `best_neighbour` then runs on every
## tick of that unit, a lookup that gives -1 (the price of keeping no "done" column).
## An ATTACK unit takes the field of its goal's tile when the goal has moved more than
## `attack_rekey_milli` from the tile its field is keyed on (checked at those events).
##
## Stall (ADR 0008 section 2): a unit that steers at its goal for good (DIRECT after a clear line,
## or FIELD on a complete field with no next tile) tracks `best_dist`, its smallest distance to the
## goal while it is within `stall_range_spacings` of its type's formation spacing. When that has not
## improved for `stall_ticks` ticks the unit goes IDLE where it stands. ATTACK units (their goal
## walks away) and units of speed 0 do not stall, and neither do units that wait for a field or for
## a free slot: they are not the crowd the rule ends.
##
## A CHASE unit whose target is gone steers at its goal, but `integrate` never ends a CHASE unit's
## order, so it would stand on the goal with its order and mode for good: combat (P41) takes a unit
## out of CHASE when it loses its target (ADR 0009 section 3), so this is a fallback no order relies
## on. A test pins it.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var ids: PackedInt32Array = world.unit_id
	var orders: PackedInt32Array = world.order
	var modes: PackedInt32Array = world.nav_mode
	var checked: PackedInt32Array = world.nav_cell
	var slot_of: PackedInt32Array = world.field
	var next_of: PackedInt32Array = world.nav_next
	var best_of: PackedInt32Array = world.best_dist
	var stall_of: PackedInt32Array = world.stall
	var targets: PackedInt32Array = world.target
	var types: PackedInt32Array = world.type_index
	var speeds: PackedInt32Array = world.type_speed
	var spacings: PackedInt32Array = world.type_spacing
	var classes: PackedInt32Array = world.type_move_class
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	var intent_x: PackedInt32Array = world.intent_x
	var intent_y: PackedInt32Array = world.intent_y
	var slots: Array[FlowField] = world.flow.fields
	var count: int = ids.size()
	var period: int = maxi(world.line_check_period_ticks, 1)
	var tick: int = world.tick
	var tile: int = World.MILLI_PER_TILE
	var cols: int = world.map_cols
	var last_row: int = world.map_rows - 1
	var stall_ticks: int = world.stall_ticks
	var reach: int = world.stall_range_spacings
	intent_x.fill(0)
	intent_y.fill(0)
	for row: int in count:
		var order: int = orders[row]
		if order == World.Order.IDLE:
			continue
		var mode: int = modes[row]
		if mode == World.NavMode.HOLD:
			continue
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		var aim_x: int = goal_x[row]
		var aim_y: int = goal_y[row]
		var type: int = types[row]
		var speed: int = speeds[type]
		if mode == World.NavMode.CHASE:
			var at: int = ids.bsearch(targets[row])
			if at < count and ids[at] == targets[row]:
				aim_x = pos_x[at]
				aim_y = pos_y[at]
		else:
			if mode == World.NavMode.NONE:
				mode = World.NavMode.DIRECT
				modes[row] = mode
			elif mode == World.NavMode.FIELD and (slot_of[row] < 0 or slot_of[row] >= slots.size()):
				# A FIELD unit with no slot (a hand-set mode) is a DIRECT unit that has not checked.
				mode = World.NavMode.DIRECT
				modes[row] = mode
				checked[row] = -1
			if (
				mode == World.NavMode.DIRECT
				and checked[row] == -1
				and (tick + ids[row]) % period == 0
			):
				mode = _check_line(world, row, x, y, aim_x, aim_y, classes[type])
			var steady: bool = false
			if mode == World.NavMode.FIELD:
				var cell: int = clampi(y / tile, 0, last_row) * cols + clampi(x / tile, 0, cols - 1)
				var entered: bool = cell != checked[row]
				if entered:
					mode = _check_line(world, row, x, y, aim_x, aim_y, classes[type])
				if mode == World.NavMode.FIELD:
					var next: int = next_of[row]
					var turn: bool = next == -1 or (tick + ids[row]) % period == 0
					if entered or (turn and slots[slot_of[row]].complete):
						_refresh_next(world, row, cell, classes[type])
						next = next_of[row]
					if next >= 0:
						aim_x = next % cols * tile + World.TILE_CENTRE
						aim_y = next / cols * tile + World.TILE_CENTRE
					else:
						steady = slots[slot_of[row]].complete
			if mode == World.NavMode.DIRECT:
				steady = checked[row] >= 0
			if steady and speed > 0 and order != World.Order.ATTACK:
				var gx: int = goal_x[row] - x
				var gy: int = goal_y[row] - y
				var to_goal: int = gx * gx + gy * gy
				var span: int = spacings[type] * reach
				if to_goal <= span * span:
					var near: int = FixedMath.isqrt(to_goal)
					if near < best_of[row]:
						best_of[row] = near
						stall_of[row] = 0
					else:
						stall_of[row] += 1
						if stall_of[row] >= stall_ticks:
							goal_x[row] = x
							goal_y[row] = y
							_end_order(world, row)
							continue
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


## One line check of unit `row` from (x, y) to its aim, counted in `stats[LINE_CHECKS]`. The unit's
## cell goes into `nav_cell`. A clear line makes it DIRECT with no field. A blocked line keeps the
## field it follows, or takes the slot _field_for finds: FIELD with that slot, or DIRECT with the
## line marked unchecked when every slot is referenced. Returns the unit's mode.
static func _check_line(
	world: World, row: int, x: int, y: int, aim_x: int, aim_y: int, move_class: int
) -> int:
	world.stats[World.Stat.LINE_CHECKS] += 1
	world.nav_cell[row] = world.cell_of(x, y)
	if FixedMath.line_clear(world, x, y, aim_x, aim_y, move_class):
		world.nav_mode[row] = World.NavMode.DIRECT
		world.field[row] = -1
		world.nav_next[row] = -1
		return World.NavMode.DIRECT
	if world.field[row] >= 0:
		return World.NavMode.FIELD
	var slot: int = _field_for(world, aim_x, aim_y, move_class)
	if slot < 0:
		world.nav_cell[row] = -1
		return World.NavMode.DIRECT
	world.field[row] = slot
	world.nav_mode[row] = World.NavMode.FIELD
	return World.NavMode.FIELD


## Sets `nav_next` of FIELD unit `row`, standing in `cell`: the neighbour tile its field names, -1
## while the field is pending. An ATTACK unit takes the right field first (_rekey).
static func _refresh_next(world: World, row: int, cell: int, move_class: int) -> void:
	var slot: int = world.field[row]
	if world.order[row] == World.Order.ATTACK:
		slot = _rekey(world, row, slot, move_class)
	var field: FlowField = world.flow.fields[slot]
	world.nav_next[row] = field.best_neighbour(cell) if field.complete else -1


## The slot of an ATTACK unit's field (ADR 0008 section 3). Its goal follows the target, so the
## field stays keyed on the tile the goal was in; once the goal is more than `attack_rekey_milli`
## from the centre of that tile, the unit takes the field of its goal's tile. With no free slot it
## keeps the old one and asks again at its next event.
@warning_ignore("integer_division")
static func _rekey(world: World, row: int, slot: int, move_class: int) -> int:
	var cols: int = world.map_cols
	var key: int = world.flow.key_goal[slot]
	var dx: int = world.goal_x[row] - (key % cols * World.MILLI_PER_TILE + World.TILE_CENTRE)
	var dy: int = world.goal_y[row] - (key / cols * World.MILLI_PER_TILE + World.TILE_CENTRE)
	var limit: int = world.attack_rekey_milli
	if dx * dx + dy * dy <= limit * limit:
		return slot
	var fresh: int = _field_for(world, world.goal_x[row], world.goal_y[row], move_class)
	if fresh < 0:
		return slot
	world.field[row] = fresh
	return fresh


## The slot of the field for a unit of `move_class` whose goal is (goal_x, goal_y), -1 when every
## slot is referenced. ADR 0008 section 3 keys it on "the goal tile of the group target", but the
## World keeps no group target, only each unit's own slot, and the slots of a formation lie on
## different tiles (a spacing of 1000 or more), so the goal's own tile would give a group of 12 a
## field each. A field of the unit's class that the cache holds under this map version already
## serves it when it is keyed within `attack_rekey_milli` (the distance ADR 0008 accepts for an
## ATTACK field) and its tile centre is in sight of the goal: the unit follows it until its own
## line to the goal is clear. The lowest such slot wins; else the field of the goal's own tile.
@warning_ignore("integer_division")
static func _field_for(world: World, goal_x: int, goal_y: int, move_class: int) -> int:
	var cache: FlowCache = world.flow
	var status: PackedInt32Array = cache.status
	var key_goal: PackedInt32Array = cache.key_goal
	var key_class: PackedInt32Array = cache.key_class
	var key_version: PackedInt32Array = cache.key_version
	var cols: int = world.map_cols
	var tile: int = World.MILLI_PER_TILE
	var limit: int = world.attack_rekey_milli
	for slot: int in status.size():
		if (
			status[slot] == FlowCache.Status.FREE
			or key_class[slot] != move_class
			or key_version[slot] != world.map_version
		):
			continue
		var key_x: int = key_goal[slot] % cols * tile + World.TILE_CENTRE
		var key_y: int = key_goal[slot] / cols * tile + World.TILE_CENTRE
		var dx: int = key_x - goal_x
		var dy: int = key_y - goal_y
		if (
			dx * dx + dy * dy <= limit * limit
			and FixedMath.line_clear(world, goal_x, goal_y, key_x, key_y, move_class)
		):
			return cache.acquire(key_goal[slot], move_class, world.map_version, world.tick)
	return cache.acquire(world.cell_of(goal_x, goal_y), move_class, world.map_version, world.tick)


## Ends the order of unit `row`: IDLE where it stands, with its navigation state cleared. The field
## goes too (nothing releases a slot by hand: the cache recounts from the `field` column).
static func _end_order(world: World, row: int) -> void:
	world.order[row] = World.Order.IDLE
	world.nav_mode[row] = World.NavMode.NONE
	world.nav_cell[row] = -1
	world.field[row] = -1
	world.nav_next[row] = -1
	world.best_dist[row] = FlowField.UNREACHED
	world.stall[row] = 0


## The INTEGRATE phase: every unit moves by its intent plus its push, clamped to the map. When the
## new point is on a tile its class cannot enter (cost 0), the x move alone is tried, then the y
## move alone, else the unit stays: a unit that steers into rock slides along it, and its centre
## never enters a blocked tile. Only the destination is tested (ADR 0008 section 4), so a unit that
## started on a blocked tile (a changed map) may still move to a passable one, and a diagonal step
## may pass between two blocked orthogonal neighbours, which the flow field and `line_clear` forbid
## (no corner cutting). A test pins that approximation, as ADR 0008 asks. Arrival is Phase 1's: a
## unit that steered at its goal (not in HOLD or CHASE) with an order other than ATTACK arrives on
## the tick its goal is within one step at the start of the tick (d2 <= speed^2, the snap of
## `run`), so its order goes IDLE and its navigation state is cleared, also when a push or the slide
## kept it off the goal itself. An ATTACK unit keeps its order and its target until combat ends it
## (P41). Rows are independent here, as the pushes were all written before this phase.
@warning_ignore("integer_division")
static func integrate(world: World) -> void:
	var orders: PackedInt32Array = world.order
	var modes: PackedInt32Array = world.nav_mode
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
					_end_order(world, row)
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
