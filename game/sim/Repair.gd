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
##   position (a building's is the footprint centre, a squad's its own). It keeps the best
##   `repair_slots` (at most 8) in the scratch columns `push_x` (rows) and `push_y` (hp shares),
##   most hurt share `hp * 1000 / max_hp` first, then lowest id.
## - Each kept row gains `repair_hp` (not above the maximum) for `ceil(cost * gained * percent /
##   (100 * max_hp))` of the owner's credits; a row it cannot pay for is skipped. `REPAIRED` is
##   written per repaired row, for the airfield's repair too (`Air._service`).
## - A building acts only complete and not blacked out (low power does not stop it); a defeated
##   owner's repairers act not at all (as `Mend.run`).
## - A medic (mobile, `repair_seek_milli` above 0) that is IDLE with no hurt row in reach takes a
##   MOVE to the most hurt candidate within the seek reach; a player's order wins.
## `stats[REPAIR_CHECKS]` counts the rows examined. No allocation but the one-row array of an order.

## The event type of ADR 0007 section 10 (World.Event holds 1-6; 7 is the mines').
const REPAIRED: int = 8
## The rows one repairer serves in one turn at most (ADR 0037 section 2: 1-8).
const MAX_SLOTS: int = 8

## ECONOMY, after `Carry.run` (which brought the derived lists up to date).
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var repairers: PackedInt32Array = world.repair_rows
	if repairers.is_empty() or world.push_x.size() < MAX_SLOTS:
		return  # No repairer, or a World that is not prepared (no scratch columns).
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
	var tops: PackedInt32Array = world.type_max_hp
	var costs: PackedInt32Array = world.type_cost
	var classes: PackedInt32Array = world.type_move_class
	var credits: PackedInt32Array = world.credits
	var defeated: PackedInt32Array = world.defeated_tick
	var slot_rows: PackedInt32Array = world.push_x
	var slot_shares: PackedInt32Array = world.push_y
	var one: PackedInt32Array = PackedInt32Array([0])  # The one-row array of a seek order.
	for rank: int in repairers.size():
		var row: int = repairers[rank]
		var kind: int = types[row]
		var period: int = maxi(1, world.type_repair_period[kind])
		var gain: int = world.type_repair_hp[kind]
		var slots: int = mini(world.type_repair_slots[kind], MAX_SLOTS)
		var player: int = owners[row]
		if (
			tick % period != rank % period
			or gain <= 0
			or slots <= 0
			or life[row] <= 0
			or pending[row] != 0
			or player >= credits.size()
			or (player < defeated.size() and defeated[player] != 0)
			or (world.type_foot_w[kind] > 0 and world.offline_until[row] > stamp)
		):
			continue
		var mask: int = world.type_repair_classes[kind]
		var reach: int = world.type_repair_reach[kind]
		var seek: int = world.type_repair_seek[kind] if world.type_speed[kind] > 0 else 0
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
				health <= 0
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
			var share: int = health * 1000 / top
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
		world.stats[World.Stat.REPAIR_CHECKS] += count
		var percent: int = world.type_repair_cost_percent[kind]
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
		if kept == 0 and seek_row >= 0 and world.order[row] == World.Order.IDLE:
			one[0] = row
			Formation.assign(world, one, xs[seek_row], ys[seek_row])
			world.order[row] = World.Order.MOVE
			Movement.reset_nav(world, one, World.NavMode.DIRECT)


## Appends `[REPAIRED, repairer id, x, y, repaired id, owner, hp gained, 0]` to `events`: the point
## is the repaired row's position (where the view draws the sparks or the glow), the owner its own.
static func announce(world: World, repairer: int, target: int, gained: int) -> void:
	var events: PackedInt32Array = world.events
	var at: int = events.size()
	events.resize(at + World.EVENT_STRIDE)  # The last int of the record stays 0.
	events[at] = REPAIRED
	events[at + 1] = world.unit_id[repairer]
	events[at + 2] = world.pos_x[target]
	events[at + 3] = world.pos_y[target]
	events[at + 4] = world.unit_id[target]
	events[at + 5] = world.owner[target]
	events[at + 6] = gained
