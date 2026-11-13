class_name Air
extends RefCounted
## Airfields and the aircraft that live on them (ADR 0036 section 6, plan row P241). An aircraft is
## a row whose type's layer bit is AIR (drone squads, LOW_AIR, are not); `world.air_rows` lists them
## ascending (derived, rebuilt in `Buildings.rebuild_lists`). Its `home` is the id of its airfield
## (0 = none) and its pad is derived: its rank by row (ids ascend with rows) among the aircraft with
## that home, so no pad is stored. A FLIGHT QUEUE is valid while the player's aircraft and queued
## FLIGHT items are below the pads of its complete airfields (`cap_room`); a finished aircraft
## spawns over a free pad (`free_pad`, used by ProductionSpawn). `run` is ECONOMY after
## `Harvest.run`: it re-homes, seats an idle aircraft over its pad, sends an empty one to its pad
## and reloads one on its pad. GDScript only. Cost: two passes over `air_rows` plus one over
## `building_rows` (to clear the per-airfield counts), no allocation per tick but the one-row array
## of an order (event cadence); a re-home scans `building_rows` (event cadence, and a failed scan
## is not repeated for the owner in the same tick).


## Whether `type` is an aircraft type (AIR layer; a hand-built World may have no entry).
static func is_aircraft(world: World, type: int) -> bool:
	return type < world.type_layer_bit.size() and world.type_layer_bit[type] == World.Layer.AIR


## Whether the player has room for one more FLIGHT item: its aircraft plus its queued FLIGHT items
## are below the pads of its complete airfields. Drone squads are not aircraft for the cap.
static func cap_room(world: World, player: int) -> bool:
	Buildings.rebuild_lists(world)
	var cap: int = 0
	for row: int in world.building_rows:
		if world.owner[row] == player and _is_field(world, row):
			cap += world.type_pads[world.type_index[row]]
	var used: int = world.queue_count[player * World.TABS + World.Tab.FLIGHT]
	for row: int in world.air_rows:
		used += int(world.owner[row] == player)
	return used < cap


## Where a finished aircraft of `player` appears: the centre of the first free pad of the producer
## `producer` (a building row), else of the first free pad of another complete own airfield (lowest
## row first), as Vector3i(airfield row, x, y) in milli; (-1, 0, 0) when no pad is free. The new
## aircraft takes the rank after those that have the airfield as home, so that pad is the one with
## that index.
static func free_pad(world: World, player: int, producer: int) -> Vector3i:
	Buildings.rebuild_lists(world)
	var found: Vector3i = _free_pad_of(world, player, producer)
	for row: int in world.building_rows:
		if found.x >= 0:
			break
		if row != producer:
			found = _free_pad_of(world, player, row)
	return found


## The centre, in milli, of pad `pad` of airfield row `row`: the footprint origin plus the type's
## offset (turned to the building's facing for a square footprint, as a dock is: ADR 0036 section 3
## gives the offsets from the footprint origin), at a tile centre.
static func pad_point(world: World, row: int, pad: int) -> Vector2i:
	var type: int = world.type_index[row]
	var first: int = world.type_pad_first[type] + pad
	var offset: Vector2i = Vector2i(world.pad_offset_x[first], world.pad_offset_y[first])
	if world.type_foot_w[type] == world.type_foot_h[type]:
		offset = Buildings.turned_at(world, row, offset)
	var tile: Vector2i = world.footprint_origin(row) + offset
	return tile * World.MILLI_PER_TILE + Vector2i(World.TILE_CENTRE, World.TILE_CENTRE)


## ECONOMY, after `Harvest.run` (which came after `Power.run` brought `air_rows` up to date).
## Pass 1 counts the aircraft of each airfield; pass 2, ascending, per aircraft:
## - an aircraft whose airfield is gone (dead, not complete, not its owner's) or that has none is
##   re-homed to the lowest-row own complete airfield with a free pad, or to 0 (a homeless one is
##   tried again every tick, so a new airfield takes it; ADR 0036 section 6 says "when it dies");
## - its pad is its rank among the aircraft of that airfield (the ones before it in `air_rows`),
##   so a death or a re-home shifts the pads of the rows after it; an aircraft out of reach of its
##   pad (`repair_reach_milli`) gets MOVE to it (`Formation.assign`, the reset of
##   `Sim._apply_point`) when it is idle over its airfield's footprint (it was seated on the old
##   pad), or when its type has ammo, it has none and it is not already on a MOVE;
## - within reach, with its airfield not blacked out, a type with ammo gains 1 each `max(1,
##   rearm_ticks / ammo cap)` ticks up to the cap, the next gain due at the stamp `ready_tick`.
## The counts live in the scratch columns `push_x` and `push_y`, which SEPARATION clears before it
## reads them next tick (one count of the airfield's row each, no allocation).
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var air: PackedInt32Array = world.air_rows
	if air.is_empty():
		return
	var totals: PackedInt32Array = world.push_x
	var ranks: PackedInt32Array = world.push_y
	for field: int in world.building_rows:
		totals[field] = 0
		ranks[field] = 0
	for row: int in air:
		var field: int = _field_of(world, row)
		if field >= 0:
			totals[field] += 1
	var stamp: int = world.tick + 1  # Offline is judged at the stamp, as Production does.
	var no_room: int = 0  # Owners whose re-home found no free pad this tick (bit per owner).
	for row: int in air:
		var field: int = _field_of(world, row)
		if field < 0:
			var bit: int = 1 << mini(world.owner[row], 30)
			world.home[row] = 0
			if no_room & bit == 0:
				field = _rehome(world, row)
				if field < 0:
					no_room |= bit
		if field < 0:
			continue
		var kind: int = world.type_index[field]
		var pad: int = ranks[field]
		ranks[field] = pad + 1
		if pad >= world.type_pads[kind]:
			continue  # More aircraft than pads (a hand-built World): none for this one.
		var type: int = world.type_index[row]
		var cap: int = world.type_ammo[type]
		var point: Vector2i = pad_point(world, field, pad)
		var dx: int = world.pos_x[row] - point.x
		var dy: int = world.pos_y[row] - point.y
		var reach: int = world.type_repair_reach[kind]
		if dx * dx + dy * dy > reach * reach:
			var seated: bool = world.order[row] == World.Order.IDLE and _over(world, field, row)
			if (
				seated
				or (cap > 0 and world.ammo[row] <= 0 and world.order[row] != World.Order.MOVE)
			):
				var rows: PackedInt32Array = PackedInt32Array([row])
				Formation.assign(world, rows, point.x, point.y)
				world.order[row] = World.Order.MOVE
				Movement.reset_nav(world, rows, World.NavMode.DIRECT)
		elif (
			cap > 0
			and world.ammo[row] < cap
			and world.offline_until[field] <= stamp
			and stamp >= world.ready_tick[row]
		):
			world.ammo[row] += 1
			world.ready_tick[row] = stamp + maxi(1, world.type_rearm_ticks[type] / cap)


## Whether aircraft row `row` is over the footprint of building row `field`.
static func _over(world: World, field: int, row: int) -> bool:
	var type: int = world.type_index[field]
	var origin: Vector2i = world.footprint_origin(field) * World.MILLI_PER_TILE
	var at: Vector2i = Vector2i(world.pos_x[row], world.pos_y[row]) - origin
	return (
		at.x >= 0
		and at.y >= 0
		and at.x < world.type_foot_w[type] * World.MILLI_PER_TILE
		and at.y < world.type_foot_h[type] * World.MILLI_PER_TILE
	)


## The row of the airfield that aircraft row `row` is homed at, or -1: `home` names a living,
## complete building of the same owner that has pads.
static func _field_of(world: World, row: int) -> int:
	var home: int = world.home[row]
	if home == 0:
		return -1
	var field: int = world.index_of(home)
	if field < 0 or world.owner[field] != world.owner[row] or not _is_field(world, field):
		return -1
	return field


## A complete building with pads. (`hp > 0` guards a hand-built World: REMOVE takes a dead row out
## before ECONOMY.)
static func _is_field(world: World, row: int) -> bool:
	var type: int = world.type_index[row]
	return (
		world.build_left[row] == 0
		and world.hp[row] > 0
		and type < world.type_pads.size()
		and world.type_pads[type] > 0
	)


## The pad of airfield row `field` that the next aircraft of `player` takes, as in `free_pad`.
static func _free_pad_of(world: World, player: int, field: int) -> Vector3i:
	if field < 0 or world.owner[field] != player or not _is_field(world, field):
		return Vector3i(-1, 0, 0)
	var taken: int = 0
	var id: int = world.unit_id[field]
	for row: int in world.air_rows:
		taken += int(world.home[row] == id)
	if taken >= world.type_pads[world.type_index[field]]:
		return Vector3i(-1, 0, 0)
	var at: Vector2i = pad_point(world, field, taken)
	return Vector3i(field, at.x, at.y)


## Homes aircraft row `row` at the lowest-row own complete airfield with a free pad, using the
## counts of `run` (`push_x`), and returns that airfield's row, or -1 with `home` 0.
static func _rehome(world: World, row: int) -> int:
	for field: int in world.building_rows:
		if (
			world.owner[field] == world.owner[row]
			and _is_field(world, field)
			and world.push_x[field] < world.type_pads[world.type_index[field]]
		):
			world.push_x[field] += 1
			world.home[row] = world.unit_id[field]
			return field
	return -1
