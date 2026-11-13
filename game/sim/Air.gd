class_name Air
extends RefCounted
## Airfields and the aircraft that live on them (ADR 0036 section 6, plan row P241). An aircraft is
## a row whose type's layer bit is AIR (drone squads, LOW_AIR, are not); `world.air_rows` lists them
## ascending (derived, rebuilt in `Buildings.rebuild_lists`). Its `home` is the id of its airfield
## (0 = none) and its pad is derived: its rank by row (ids ascend with rows) among the aircraft with
## that home, so no pad is stored. A FLIGHT QUEUE is valid while the player's aircraft and queued
## FLIGHT items are below the pads of its complete airfields (`cap_room`); a finished aircraft
## spawns over a free pad (`free_pad`, used by ProductionSpawn). `run` is ECONOMY after
## `Harvest.run`: it re-homes, sends an aircraft that is out of ammo to its pad and reloads one on
## its pad. GDScript only; one pass over `air_rows`, no allocation but a one-row array at an order.


## Whether `type` is an aircraft type (AIR layer; a hand-built World may have no entry).
static func is_aircraft(world: World, type: int) -> bool:
	return type < world.type_layer_bit.size() and world.type_layer_bit[type] == World.Layer.AIR


## Whether the player has room for one more FLIGHT item: its aircraft plus its queued FLIGHT items
## are below the pads of its complete airfields. Drone squads are not aircraft for the cap.
static func cap_room(world: World, player: int) -> bool:
	Buildings.rebuild_lists(world)
	var cap: int = 0
	for row: int in world.building_rows:
		if world.owner[row] == player and world.build_left[row] == 0:
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
	var fields: PackedInt32Array = PackedInt32Array([producer])
	fields.append_array(world.building_rows)
	for row: int in fields:
		if world.owner[row] != player or not _is_field(world, row):
			continue
		var taken: int = _homed(world, world.unit_id[row])
		if taken < world.type_pads[world.type_index[row]]:
			var at: Vector2i = pad_point(world, row, taken)
			return Vector3i(row, at.x, at.y)
	return Vector3i(-1, 0, 0)


## The centre, in milli, of pad `pad` of airfield row `row`: the footprint origin plus the type's
## offset (turned to the building's facing for a square footprint, as a dock is), at a tile centre.
static func pad_point(world: World, row: int, pad: int) -> Vector2i:
	var type: int = world.type_index[row]
	var first: int = world.type_pad_first[type] + pad
	var offset: Vector2i = Vector2i(world.pad_offset_x[first], world.pad_offset_y[first])
	if world.type_foot_w[type] == world.type_foot_h[type]:
		offset = Buildings.turned_at(world, row, offset)
	var tile: Vector2i = world.footprint_origin(row) + offset
	return tile * World.MILLI_PER_TILE + Vector2i(World.TILE_CENTRE, World.TILE_CENTRE)


## ECONOMY, after `Harvest.run` (which came after `Power.run` brought `air_rows` up to date).
## Every aircraft whose airfield is gone (dead, not complete, not its owner's) or that has none is
## re-homed to the lowest-row own complete airfield with a free pad, or to 0 (the rule of ADR 0036
## section 6 also tries a homeless aircraft again, so a new airfield takes it). A homed aircraft of
## a type with ammo that is not within `repair_reach_milli` of its pad and has ammo 0 and no MOVE
## order gets a MOVE to the pad (`Formation.assign`, the reset of `Sim._apply_point`); one within
## reach of its pad, with its airfield online, gains 1 ammo each `max(1, rearm_ticks / ammo cap)`
## ticks up to the cap, the next gain stamped in `ready_tick`.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var air: PackedInt32Array = world.air_rows
	var stamp: int = world.tick + 1  # Offline is judged at the stamp, as Production does.
	for at: int in air.size():
		var row: int = air[at]
		var field: int = _field_of(world, row)
		if field < 0:
			_rehome(world, row)
			field = _field_of(world, row)
		var type: int = world.type_index[row]
		var cap: int = world.type_ammo[type]
		if field < 0 or cap <= 0:
			continue
		var pad: int = _rank(world, air, at)
		if pad >= world.type_pads[world.type_index[field]]:
			continue  # More aircraft than pads (a hand-built World): none for this one.
		var point: Vector2i = pad_point(world, field, pad)
		var dx: int = world.pos_x[row] - point.x
		var dy: int = world.pos_y[row] - point.y
		var reach: int = world.type_repair_reach[world.type_index[field]]
		if dx * dx + dy * dy > reach * reach:
			if world.ammo[row] <= 0 and world.order[row] != World.Order.MOVE:
				var rows: PackedInt32Array = PackedInt32Array([row])
				Formation.assign(world, rows, point.x, point.y)
				world.order[row] = World.Order.MOVE
				Movement.reset_nav(world, rows, World.NavMode.DIRECT)
		elif (
			world.ammo[row] < cap
			and world.offline_until[field] <= stamp
			and world.tick >= world.ready_tick[row]
		):
			world.ammo[row] += 1
			world.ready_tick[row] = world.tick + maxi(1, world.type_rearm_ticks[type] / cap)


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


static func _is_field(world: World, row: int) -> bool:
	var type: int = world.type_index[row]
	return (
		world.build_left[row] == 0
		and world.hp[row] > 0
		and type < world.type_pads.size()
		and world.type_pads[type] > 0
	)


## The aircraft with `home`, the id of an airfield.
static func _homed(world: World, home: int) -> int:
	var count: int = 0
	for row: int in world.air_rows:
		count += int(world.home[row] == home)
	return count


## The rank of `air[at]` among the aircraft with the same home (the ones before it in `air`).
static func _rank(world: World, air: PackedInt32Array, at: int) -> int:
	var home: int = world.home[air[at]]
	var rank: int = 0
	for before: int in at:
		rank += int(world.home[air[before]] == home)
	return rank


## Sets `home` of aircraft row `row` to the lowest-row own complete airfield with a free pad, or 0.
static func _rehome(world: World, row: int) -> void:
	world.home[row] = 0
	for field: int in world.building_rows:
		if (
			world.owner[field] == world.owner[row]
			and _is_field(world, field)
			and _homed(world, world.unit_id[field]) < world.type_pads[world.type_index[field]]
		):
			world.home[row] = world.unit_id[field]
			return
