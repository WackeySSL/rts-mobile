class_name Repair
extends RefCounted
## Repair by ground buildings and medics (ADR 0037 sections 5 and 6), ECONOMY after `Carry.run`.
## It serves every type with a repair role and no pads (`world.repair_rows`, rebuilt with the other
## derived lists); `Air.run` keeps the types with pads, and the two never serve one row.
## - Staggered: the repairer at index `k` of `repair_rows` acts on ticks with `tick % period ==
##   k % period` (its type's `repair_period_ticks`), so at most `ceil(R / period)` act per tick.
## - An acting repairer makes one pass over the rows and never reads `target_grid` (stale by
##   ECONOMY). Candidates are own rows, not itself, complete, hurt, whose move class bit is in
##   `repair_classes` and that lie within `repair_reach_milli` of its service point: its row
##   position (a building's is the footprint centre, a squad's its own). Rows with a footprint are
##   never candidates: buildings are `Mend`'s (a medic's FOOT bit would match their move class 0).
##   It keeps the best `repair_slots` (at most 8) in the scratch columns `push_x` (rows) and
##   `push_y` (hp shares),
##   most hurt share `hp * 1000 / max_hp` first, then lowest id.
## - Each kept row gains `repair_hp` (not above the maximum) for `ceil(cost * gained * percent /
##   (100 * max_hp))` of the owner's credits; a row it cannot pay for is skipped. `REPAIRED` is
##   written per repaired row, for the airfield's repair too (`Air._service`).
## - A building acts only complete and not blacked out (low power does not stop it); a defeated
##   owner's repairers act not at all (as `Mend.run`).
## - A medic (mobile, `repair_seek_milli` above 0) that is IDLE, has no order target (or one whose
##   unit is gone: a pending LOAD keeps its mark until the carrier dies) and no hurt row in reach
##   takes a MOVE to the most hurt candidate within the seek reach; a player's order wins.
## `stats[REPAIR_CHECKS]` counts the rows examined. No allocation but the one-row array of an order.

## The rows one repairer serves in one turn at most (ADR 0037 section 2: 1-8).
const MAX_SLOTS: int = 8
## The hp share of a full row, in per mille.
const FULL_SHARE: int = 1000

## ECONOMY, after `Carry.run` (which brought the derived lists up to date).
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var repairers: PackedInt32Array = world.repair_rows
	var slot_rows: PackedInt32Array = world.push_x
	var slot_shares: PackedInt32Array = world.push_y
	if repairers.is_empty() or slot_rows.is_empty() or slot_shares.is_empty():
		return  # No repairer, or a World that is not prepared (no scratch columns).
	var scratch: int = mini(MAX_SLOTS, mini(slot_rows.size(), slot_shares.size()))
	var tick: int = world.tick
	var stamp: int = tick + 1  # Offline is judged at the stamp, as Production does.
	var count: int = world.unit_count()
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var life: PackedInt32Array = world.hp
	var pending: PackedInt32Array = world.build_left
	var xs: PackedInt32Array = world.pos_x
	var ys: PackedInt32Array = world.pos_y
	var orders: PackedInt32Array = world.order
	var order_target: PackedInt32Array = world.order_target
	var offline: PackedInt32Array = world.offline_until
	var tops: PackedInt32Array = world.type_max_hp
	var costs: PackedInt32Array = world.type_cost
	var classes: PackedInt32Array = world.type_move_class
	var feet: PackedInt32Array = world.type_foot_w
	var speeds: PackedInt32Array = world.type_speed
	var roles: PackedInt32Array = world.type_repair_classes
	var periods: PackedInt32Array = world.type_repair_period
	var gains: PackedInt32Array = world.type_repair_hp
	var slot_caps: PackedInt32Array = world.type_repair_slots
	var reaches: PackedInt32Array = world.type_repair_reach
	var seeks: PackedInt32Array = world.type_repair_seek
	var prices: PackedInt32Array = world.type_repair_cost_percent
	var credits: PackedInt32Array = world.credits
	var defeated: PackedInt32Array = world.defeated_tick
	var checks: int = 0
	for rank: int in repairers.size():
		var row: int = repairers[rank]
		var kind: int = types[row]
		if tick % maxi(1, periods[kind]) != rank % maxi(1, periods[kind]):
			continue
		var gain: int = gains[kind]
		var slots: int = mini(slot_caps[kind], scratch)
		var player: int = owners[row]
		if (
			gain <= 0
			or slots <= 0
			or life[row] <= 0
			or pending[row] != 0
			or player < 1
			or player >= credits.size()
			or (player < defeated.size() and defeated[player] != 0)
			or (feet[kind] > 0 and offline[row] > stamp)
		):
			continue
		var mask: int = roles[kind]
		var reach: int = reaches[kind]
		var seek: int = seeks[kind] if speeds[kind] > 0 else 0
		var scan: int = maxi(reach, seek)
		var kept: int = 0
		var seek_row: int = -1
		var seek_share: int = 0
		for other: int in count:
			if owners[other] != player or other == row:
				continue
			var type: int = types[other]
			var top: int = maxi(tops[type], 1)
			var health: int = life[other]
			if (
				feet[type] > 0
				or health <= 0
				or health >= top
				or pending[other] != 0
				or (mask >> classes[type]) & 1 == 0
			):
				continue
			var dx: int = xs[other] - xs[row]
			var dy: int = ys[other] - ys[row]
			var gap: int = dx * dx + dy * dy
			if gap > scan * scan:
				continue
			var share: int = health * FULL_SHARE / top
			if (
				gap <= seek * seek
				and (
					seek_row < 0
					or share < seek_share
					or (share == seek_share and ids[other] < ids[seek_row])
				)
			):
				seek_row = other
				seek_share = share
			if gap > reach * reach:
				continue
			var at: int = kept
			while at > 0:
				var before: int = slot_rows[at - 1]
				if (
					slot_shares[at - 1] < share
					or (slot_shares[at - 1] == share and ids[before] < ids[other])
				):
					break
				at -= 1
			if at >= slots:
				continue
			var last: int = mini(kept, slots - 1)
			for slot: int in range(last, at, -1):
				slot_rows[slot] = slot_rows[slot - 1]
				slot_shares[slot] = slot_shares[slot - 1]
			slot_rows[at] = other
			slot_shares[at] = share
			kept = last + 1
		checks += count
		var percent: int = prices[kind]
		for slot: int in kept:
			var target: int = slot_rows[slot]
			var target_type: int = types[target]
			var top: int = maxi(tops[target_type], 1)
			var gained: int = mini(gain, top - life[target])
			var cost: int = (costs[target_type] * gained * percent + 100 * top - 1) / (100 * top)
			if credits[player] < cost:
				continue
			credits[player] -= cost
			life[target] += gained
			announce(world, row, target, gained)
		if (
			kept == 0
			and seek_row >= 0
			and orders[row] == World.Order.IDLE
			and (order_target[row] == 0 or world.index_of(order_target[row]) < 0)
		):
			var one: PackedInt32Array = PackedInt32Array([row])  # alloc-ok
			Formation.assign(world, one, xs[seek_row], ys[seek_row])
			orders[row] = World.Order.MOVE
			Movement.reset_nav(world, one, World.NavMode.DIRECT)
	world.stats[World.Stat.REPAIR_CHECKS] += checks


## Appends `[REPAIRED, repairer id, x, y, repaired id, owner, hp gained, 0]` to `events`: the point
## is the repaired row's position (where the view draws the sparks or the glow), the owner its own.
static func announce(world: World, repairer: int, target: int, gained: int) -> void:
	var events: PackedInt32Array = world.events
	var at: int = events.size()
	events.resize(at + World.EVENT_STRIDE)  # The last int of the record stays 0.
	events[at] = World.Event.REPAIRED
	events[at + 1] = world.unit_id[repairer]
	events[at + 2] = world.pos_x[target]
	events[at + 3] = world.pos_y[target]
	events[at + 4] = world.unit_id[target]
	events[at + 5] = world.owner[target]
	events[at + 6] = gained


## REPAIR for a ground repair building (ADR 0037 section 5, P277; the one REPAIR command, reached
## from `Air.apply_repair` when the target has no pads): `target_id` is an own, complete, living
## building with a footprint, no pads and a repair role. The valid units are own, living, complete,
## mobile rows with no footprint whose move class bit is in the building's `repair_classes`; each
## gets MOVE to a ring tile next to the footprint (`Buildings.aim` leaves out a unit with no
## passable ring tile, and `_spread` then gives each row, lowest id first, the nearest ring tile
## that no earlier row of the command took, so a group never piles onto one corner tile and every
## row ends in reach). Arrived rows stand idle and `run` repairs them while in reach, ordered or
## not. A blacked-out building still takes the order (the blackout is transient); `run` repairs
## nothing until it is back online. With no unit taken the command is dropped and counted.
static func apply_ground(world: World, command: Command, building: int) -> bool:
	var kind: int = world.type_index[building]
	if (
		command.unit_ids.size() > Command.MAX_UNITS
		or kind >= world.type_repair_classes.size()
		or kind >= world.type_pads.size()
		or world.type_repair_classes[kind] == 0
		or world.type_pads[kind] != 0
		or world.type_foot_w[kind] <= 0
		or world.build_left[building] != 0
		or world.hp[building] <= 0
	):
		return false
	var mask: int = world.type_repair_classes[kind]
	var ids: PackedInt32Array = command.unit_ids.duplicate()
	ids.sort()
	var rows: PackedInt32Array = PackedInt32Array()
	var previous: int = 0
	for id: int in ids:
		if id == previous:
			continue
		previous = id
		var row: int = world.index_of(id)
		if row < 0 or world.owner[row] != command.player_id:
			continue
		var type: int = world.type_index[row]
		if (
			world.hp[row] > 0
			and world.build_left[row] == 0
			and world.type_speed[type] > 0
			and world.type_foot_w[type] <= 0
			and (mask >> world.type_move_class[type]) & 1 == 1
		):
			rows.append(row)
	rows = Buildings.aim(world, rows, building)
	if rows.is_empty():
		return false
	_spread(world, rows, building)
	for row: int in rows:
		world.order[row] = World.Order.MOVE
		world.order_target[row] = 0
		world.group_cell[row] = -1
	Movement.reset_nav(world, rows, World.NavMode.DIRECT)
	Harvest.release(world, rows)
	Carry.release(world, rows)
	return true


## Re-aims `rows` (ascending, each already given `Buildings.aim`'s point) one by one: row `i` takes
## the passable ring tile of its move class nearest to its position, by squared distance and then
## by the ring walk's order (ADR 0033: `ProductionSpawn.ring_tile` clockwise from the top-left,
## shifted a quarter of the ring per quarter turn of `Buildings.facing`, so a half turn of the map
## mirrors the walk), that no row `j < i` took. When every tile is taken the row keeps `aim`'s
## point. Command cadence; no allocation (a taken tile is read back from the goals of earlier rows).
@warning_ignore("integer_division")
static func _spread(world: World, rows: PackedInt32Array, building: int) -> void:
	var kind: int = world.type_index[building]
	var size: Vector2i = Vector2i(world.type_foot_w[kind], world.type_foot_h[kind])
	var origin: Vector2i = world.footprint_origin(building)
	var length: int = ProductionSpawn.ring_length(size)
	var shift: int = (
		Buildings.facing(
			world.map_cols, world.map_rows, world.pos_x[building], world.pos_y[building]
		)
		* length
		/ 4
	)
	var cols: int = world.map_cols
	var cells: int = cols * world.map_rows
	var goal_x: PackedInt32Array = world.goal_x
	var goal_y: PackedInt32Array = world.goal_y
	for index: int in rows.size():
		var row: int = rows[index]
		var base: int = world.type_move_class[world.type_index[row]] * cells
		var best_x: int = -1
		var best_y: int = -1
		var best_gap: int = 0
		for step: int in length:
			var tile: Vector2i = ProductionSpawn.ring_tile(origin, size, (shift + step) % length)
			if tile.x < 0 or tile.y < 0 or tile.x >= cols or tile.y >= world.map_rows:
				continue
			if world.move_cost[base + tile.y * cols + tile.x] == 0:
				continue
			var at_x: int = tile.x * World.MILLI_PER_TILE + World.TILE_CENTRE
			var at_y: int = tile.y * World.MILLI_PER_TILE + World.TILE_CENTRE
			var free: bool = true
			for earlier: int in index:
				if goal_x[rows[earlier]] == at_x and goal_y[rows[earlier]] == at_y:
					free = false
					break
			if not free:
				continue
			var dx: int = at_x - world.pos_x[row]
			var dy: int = at_y - world.pos_y[row]
			if best_x < 0 or dx * dx + dy * dy < best_gap:
				best_x = at_x
				best_y = at_y
				best_gap = dx * dx + dy * dy
		if best_x >= 0:
			goal_x[row] = best_x
			goal_y[row] = best_y
