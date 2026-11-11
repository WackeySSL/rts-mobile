class_name Mend
extends RefCounted
## Building repair (ADR 0037 section 4). The switch is the building row's `cargo` (0 or 1; buildings
## never carry cargo, so this is a documented reuse). `run` is ECONOMY after `Harvest.run`: each
## mending building acts on ticks with `(tick + id) % mend_period_ticks == 0`, so the work is
## staggered by id. A step gains `mend_hp` (not above the maximum) and costs the owner `ceil(price *
## gained * mend_cost_percent / (100 * max_hp))`; with too few credits nothing happens that period.
## At full health the switch goes back to 0. A defeated player's buildings do not mend, as its
## queues do not advance (`Production.run`; ADR 0037 is silent on it). It mends while blacked out,
## on low power and under fire, and a Headquarters (price 0) mends free. The rule ints are the
## World's; with `mend_hp` or `mend_period_ticks` at 0 (the inert defaults) nothing mends. One pass
## over the derived building list, aliased arrays, no allocation.


## MEND: `target_id` is an own complete building (a footprint, `build_left` 0) and the payload is
## `[1]` (on) or `[0]` (off). It writes the switch and nothing else, so a mend on a building at full
## health is accepted and drops back at its next step.
static func apply_mend(world: World, command: Command) -> bool:
	if command.payload.size() != 1 or (command.payload[0] != 0 and command.payload[0] != 1):
		return false
	var row: int = world.index_of(command.target_id)
	if row < 0 or world.owner[row] != command.player_id or world.build_left[row] != 0:
		return false
	var type: int = world.type_index[row]
	if type >= world.type_foot_w.size() or world.type_foot_w[type] <= 0 or world.hp[row] <= 0:
		return false
	world.cargo[row] = command.payload[0]
	return true


## ECONOMY, after `Power.run` (which brought the building list up to date).
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var period: int = world.mend_period_ticks
	var gain: int = world.mend_hp
	if period <= 0 or gain <= 0:
		return
	var percent: int = world.mend_cost_percent
	var tick: int = world.tick
	var ids: PackedInt32Array = world.unit_id
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var life: PackedInt32Array = world.hp
	var switches: PackedInt32Array = world.cargo
	var pending: PackedInt32Array = world.build_left
	var tops: PackedInt32Array = world.type_max_hp
	var costs: PackedInt32Array = world.type_cost
	var credits: PackedInt32Array = world.credits
	var defeated: PackedInt32Array = world.defeated_tick
	for row: int in world.building_rows:
		if switches[row] != 1 or pending[row] != 0 or (tick + ids[row]) % period != 0:
			continue
		var top: int = maxi(tops[types[row]], 1)
		var gained: int = mini(gain, top - life[row])
		if gained <= 0:
			switches[row] = 0
			continue
		var player: int = owners[row]
		if player < defeated.size() and defeated[player] > 0:
			continue
		var cost: int = (costs[types[row]] * gained * percent + 100 * top - 1) / (100 * top)
		if player < 1 or player >= credits.size() or credits[player] < cost:
			continue
		credits[player] -= cost
		life[row] += gained
		if life[row] >= top:
			switches[row] = 0
