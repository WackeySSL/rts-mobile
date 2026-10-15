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
## (data/rules.tres). The only constants here are the upper clamp bound of a world with no map and
## the `nav_next` mark "looked up, none".
##
## Navigation modes (`nav_mode`): DIRECT steers straight at the goal; NONE on a unit with an order
## is a DIRECT unit that has not started (a hand-set order); FIELD follows the flow field in
## `field` (the slot) and steers DIRECT while that field is pending; HOLD gives no intent; CHASE
## steers straight at the unit in `target` (combat sets both, P41). This is the GDScript twin of
## the INTENTS and INTEGRATE kernels P37n and P37n2 port later: keep it portable (typed locals, the
## World's arrays aliased before each loop, no allocation, helper calls only at event cadence).
## The split follows ADR 0013 section 1: `run` holds the steering and the line checks, with the
## first acquire of a field (a GDScript caller of the cache); `integrate` holds the rest of what
## follows a field: `nav_next` with `best_neighbour`, the stall and the ATTACK re-key.

## The upper clamp bound of a world with no map (nothing to clamp to above): the largest int32. The
## lower bound stays 0 on every world, so a position never goes negative.
const NO_BOUND: int = 0x7FFFFFFF

## `nav_next` of a FIELD unit whose field is complete and names no next tile for its cell: it stands
## on the goal tile, or on ground the field does not reach. -1 is the other "none": no lookup made
## yet (the field is pending, or the order is new). The mark keeps `best_neighbour` from running on
## every tick of such a unit (ADR 0008 section 2: no per-tick call).
const NO_NEXT: int = -2


## The navigation state a new order or a STOP gives `rows`: `mode` (DIRECT for an order, NONE for a
## stop), a line to the goal that is not checked yet (`nav_cell` -1), no field (nothing releases a
## slot by hand: the cache recounts its references from the `field` column), no next tile and a
## fresh stall count. Command cadence only. `group_cell` is the order's, not navigation state, so it
## stays (a caller that resumes an order through here keeps its group target).
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
## `nav_cell`, which ends the checking (`integrate` clears it again for a unit that the rock stops
## dead, see there). A blocked line asks the cache for a field of the unit's class keyed on the
## order's group target (`group_cell`, Formation's centre: the whole group shares it), else on the
## tile of the unit's goal (an ATTACK unit, or a hand-set order): the unit is FIELD with that slot,
## or stays DIRECT and unchecked (it asks again on its next turn) when every slot is referenced. A
## FIELD unit checks the line again each time it enters a tile, and a clear line makes it DIRECT
## with no field. Every check counts in `stats[LINE_CHECKS]`.
##
## A FIELD unit steers at the centre of its `nav_next` tile; with none (the field is pending, or
## the unit stands where the field names no next tile) it steers DIRECT at its goal. `integrate`
## sets `nav_next`.
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
	var slot_count: int = world.flow.fields.size()
	var count: int = ids.size()
	var period: int = maxi(world.line_check_period_ticks, 1)
	var tick: int = world.tick
	var tile: int = World.MILLI_PER_TILE
	var cols: int = world.map_cols
	var last_row: int = world.map_rows - 1
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
			elif mode == World.NavMode.FIELD and (slot_of[row] < 0 or slot_of[row] >= slot_count):
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
			if mode == World.NavMode.FIELD:
				var cell: int = clampi(y / tile, 0, last_row) * cols + clampi(x / tile, 0, cols - 1)
				if cell != checked[row]:
					mode = _check_line(world, row, x, y, aim_x, aim_y, classes[type])
				if mode == World.NavMode.FIELD and next_of[row] >= 0:
					aim_x = next_of[row] % cols * tile + World.TILE_CENTRE
					aim_y = next_of[row] / cols * tile + World.TILE_CENTRE
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
## field it follows, or takes one keyed on its `group_cell`, else on its goal's tile (ADR 0008
## section 3). The unit is then FIELD with that slot, or DIRECT with the line marked unchecked when
## every slot is referenced. Returns the unit's mode.
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
	if world.field[row] < 0:
		var key: int = world.group_cell[row]
		if key < 0:
			key = world.cell_of(aim_x, aim_y)
		var slot: int = world.flow.acquire(key, move_class, world.map_version, world.tick)
		if slot < 0:
			world.nav_cell[row] = -1
			return World.NavMode.DIRECT
		world.field[row] = slot
	world.nav_mode[row] = World.NavMode.FIELD
	return World.NavMode.FIELD


## Sets `nav_next` of FIELD unit `row`, standing in `cell`, from its field: the neighbour tile the
## field names, NO_NEXT when the field is complete and names none, -1 while it is pending. An ATTACK
## unit takes the right field first (_rekey). The field's own key counts as none when its tile is
## blocked for the unit's class now: the field seeds the key at cost 0 whatever the terrain, so
## `best_neighbour` keeps naming a key that turned to rock (`set_terrain`, later a building) and
## the unit would press on it for good. Only the key: any other blocked tile keeps the old field
## until the cache swaps the new one in. `slots`, `slot_of` and `next_of` are the World's
## `flow.fields`, `field` and `nav_next`, aliased by the caller.
static func _refresh_next(
	world: World,
	slots: Array[FlowField],
	slot_of: PackedInt32Array,
	next_of: PackedInt32Array,
	row: int,
	cell: int,
	move_class: int
) -> void:
	var slot: int = slot_of[row]
	if world.order[row] == World.Order.ATTACK:
		slot = _rekey(world, row, slot, move_class)
	var field: FlowField = slots[slot]
	var next: int = -1
	if field.complete:
		next = field.best_neighbour(cell)
		if next == world.flow.key_goal[slot] and not world.is_passable(next, move_class):
			next = -1
		if next < 0:
			next = NO_NEXT
			if _take_own_field(world, row, slot, move_class):
				next = -1
	next_of[row] = next


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
	var goal: int = world.cell_of(world.goal_x[row], world.goal_y[row])
	var fresh: int = world.flow.acquire(goal, move_class, world.map_version, world.tick)
	if fresh < 0:
		return slot
	world.field[row] = fresh
	return fresh


## A FIELD unit whose complete field names no next tile, on a field keyed on a tile other than its
## goal's (a group's field, or an ATTACK field it has outrun), takes the field of its goal's tile
## and returns true; with every slot referenced it keeps the old one and asks again at its next
## event. The unit starts over on the new field, as `reset_nav` does for a new one: no best distance
## and no stall count, because what it counted while it waited for a slot was not progress on this
## field, and a stale count would end the order of a unit that has just started to gain.
static func _take_own_field(world: World, row: int, slot: int, move_class: int) -> bool:
	var own: int = world.cell_of(world.goal_x[row], world.goal_y[row])
	if world.flow.key_goal[slot] == own:
		return false
	var fresh: int = world.flow.acquire(own, move_class, world.map_version, world.tick)
	if fresh < 0:
		return false
	world.field[row] = fresh
	world.best_dist[row] = FlowField.UNREACHED
	world.stall[row] = 0
	return true


## Ends the order of unit `row`: IDLE where it stands, with its navigation state cleared. The field
## goes too (nothing releases a slot by hand: the cache recounts from the `field` column).
static func _end_order(world: World, row: int) -> void:
	world.order[row] = World.Order.IDLE
	world.group_cell[row] = -1
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
##
## The rest of what follows a field is here too (ADR 0013 section 1), all at event cadence:
## - `nav_next` of a FIELD unit is set (_refresh_next) on the tick its field completes (`nav_next`
##   is -1 and the field is complete, before the step), on the tick the step takes the unit into a
##   new tile, and on the unit's line-check turn ((tick + id) % period), so that a field the cache
##   re-integrated after a map change (it serves the old costs until the swap, and stays
##   `complete`) sends the unit on within a period. All of it waits for a complete field: while it
##   is pending there is nothing to look up and nothing to re-key. A lookup that names no tile
##   (or only the field's key, when that tile is blocked now) leaves NO_NEXT, which ends the asking
##   until the next tile or turn; if the field is keyed on a tile other than the unit's goal's (a
##   group's field), the unit then takes the field of its goal's tile (_take_own_field), with a
##   fresh best distance and stall count. The unit steers on it from the next tick's `run`.
## - An ATTACK unit takes the field of its goal's tile when the goal has moved more than
##   `attack_rekey_milli` from the tile its field is keyed on (checked at those events, so a field
##   that is pending finishes first, and then the unit re-keys).
## - Stall (ADR 0008 section 2): a unit that steers at its goal for good (DIRECT after a clear
##   line, or FIELD on a complete field that names no next tile) tracks `best_dist`, its smallest
##   distance to the goal while it is within `stall_range_spacings` of its type's formation
##   spacing, or at any distance on a field that names no next tile (the goal is out of its reach,
##   and a slot should not be held for it for good). When that has not improved for `stall_ticks`
##   ticks the unit goes IDLE where it stands, without its intent. ATTACK units (their goal walks
##   away) and units of speed 0 do not stall, and neither do units that wait for a field or for a
##   free slot: they are not the crowd the rule ends.
## - A DIRECT unit that the rock stops dead (no x move, no y move) gets its line checked again on
##   its next turn: the line was clear when `run` checked it, but the truncated steps do not follow
##   it (a shallow line moves no whole milli across), so the unit can press on a tile the check
##   never saw. The new check finds the line blocked and gives the unit a field.
@warning_ignore("integer_division")
static func integrate(world: World) -> void:
	var ids: PackedInt32Array = world.unit_id
	var orders: PackedInt32Array = world.order
	var modes: PackedInt32Array = world.nav_mode
	var checked: PackedInt32Array = world.nav_cell
	var slot_of: PackedInt32Array = world.field
	var next_of: PackedInt32Array = world.nav_next
	var best_of: PackedInt32Array = world.best_dist
	var stall_of: PackedInt32Array = world.stall
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
	var push_x: PackedInt32Array = world.push_x
	var push_y: PackedInt32Array = world.push_y
	var cost: PackedByteArray = world.move_cost
	var slots: Array[FlowField] = world.flow.fields
	var slot_count: int = slots.size()
	var cols: int = world.map_cols
	var cells: int = cols * world.map_rows
	var tile: int = World.MILLI_PER_TILE
	var period: int = maxi(world.line_check_period_ticks, 1)
	var tick: int = world.tick
	var stall_ticks: int = world.stall_ticks
	var reach: int = world.stall_range_spacings
	var max_x: int = NO_BOUND
	var max_y: int = NO_BOUND
	if cells > 0:
		max_x = mini(world.map_w, cols * tile) - 1
		max_y = mini(world.map_h, world.map_rows * tile) - 1
	for row: int in ids.size():
		var order: int = orders[row]
		var step_x: int = intent_x[row] + push_x[row]
		var step_y: int = intent_y[row] + push_y[row]
		if order == World.Order.IDLE and step_x == 0 and step_y == 0:
			continue
		var x: int = pos_x[row]
		var y: int = pos_y[row]
		var mode: int = modes[row]
		var type: int = types[row]
		# The cell of a FIELD unit with a slot; -1 for any other unit.
		var cell: int = -1
		if (
			mode == World.NavMode.FIELD
			and order != World.Order.IDLE
			and cells > 0
			and slot_of[row] >= 0
			and slot_of[row] < slot_count
		):
			cell = clampi(y, 0, max_y) / tile * cols + clampi(x, 0, max_x) / tile
			if (
				(next_of[row] == -1 or (tick + ids[row]) % period == 0)
				and slots[slot_of[row]].complete
			):
				_refresh_next(world, slots, slot_of, next_of, row, cell, classes[type])
		if (
			order != World.Order.IDLE
			and order != World.Order.ATTACK
			and mode != World.NavMode.HOLD
			and mode != World.NavMode.CHASE
		):
			var speed: int = speeds[type]
			var dx: int = goal_x[row] - x
			var dy: int = goal_y[row] - y
			var to_goal: int = dx * dx + dy * dy
			if to_goal <= speed * speed:
				_end_order(world, row)
				mode = World.NavMode.NONE
			elif (
				speed > 0
				and (
					(mode == World.NavMode.DIRECT and checked[row] >= 0)
					or (cell >= 0 and next_of[row] == NO_NEXT)
				)
			):
				var span: int = spacings[type] * reach
				if mode == World.NavMode.FIELD or to_goal <= span * span:
					var near: int = FixedMath.isqrt(to_goal)
					if near < best_of[row]:
						best_of[row] = near
						stall_of[row] = 0
					else:
						stall_of[row] += 1
						if stall_of[row] >= stall_ticks:
							goal_x[row] = x
							goal_y[row] = y
							intent_x[row] = 0
							intent_y[row] = 0
							step_x = push_x[row]
							step_y = push_y[row]
							_end_order(world, row)
							mode = World.NavMode.NONE
		if step_x == 0 and step_y == 0:
			continue
		var new_x: int = clampi(x + step_x, 0, max_x)
		var new_y: int = clampi(y + step_y, 0, max_y)
		if cells > 0:
			var base: int = classes[type] * cells
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
				if new_x == x and new_y == y and mode == World.NavMode.DIRECT:
					checked[row] = -1
		pos_x[row] = new_x
		pos_y[row] = new_y
		if cell >= 0 and mode == World.NavMode.FIELD:
			var entered: int = new_y / tile * cols + new_x / tile
			if entered != cell and slots[slot_of[row]].complete:
				_refresh_next(world, slots, slot_of, next_of, row, entered, classes[type])
