extends RefCounted
## What the AI-vs-AI harness counts outside the sim (ADR 0031 section 1, plan row P186): per player
## and per unit type what was produced, given free, lost, killed and spent, the structures placed,
## and `flow_full_ticks`. It only reads the World (`events`, `flow`, the type tables), so a match
## has the same state hash with it and without it (a test pins that). Not a rule: the kills are an
## attribution for balance reading.
##
## Call `start(world)` once before the first step and `after_step(world)` after each step. All
## counts are ints keyed by the type id as a String, so they survive JSON.
##
## - `produced`: a unit type with a queue tab (`type_tab` of 1 or 2) that SPAWNED after tick 0.
##   A spent figure is `produced` times `type_cost`; structures are not in it.
## - `free`: the rows the scenario starts with, a refinery's free harvester (the unit of
##   `type_free_unit` that SPAWNED in the tick its building did, one per building) and any other
##   unit without a queue tab that appears later.
## - `structures`: a building type that SPAWNED after tick 0.
## - `lost`: DIED, for the dead row's owner and type; a cancelled site (the record's cancel flag)
##   is a refund and not a loss.
## - `kills`: a DIED credits the player and type of the last shooter of that row (a SHOT record
##   names shooter and target). A row that dies in the tick a rupture lands, with no SHOT at it in
##   that tick and inside the rupture radius of the STRIKE record's point (`type_strike_radius` of
##   `Strike.rupture_type`), is credited to the strike building's type and player. The order is: a
##   shot at the row in its dying tick, then such a rupture, then the row's last shooter. A death
##   with none of them is credited to nobody.
## - `first_drop_tick`: the tick of the first step after which `dropped_commands` was above 0, -1
##   while none was (a harness failure names it).
## - Free-unit edges: a refused `spawn_free` (unit cap, no exit) in the tick of its refinery leaves
##   the owed unit unused, and a later unit of that type counts as produced; and on the dormant
##   place-first path (ADR 0026) the free harvester spawns when the site completes, ticks after
##   the refinery's SPAWNED, so it counts as produced. The AI never uses that path.

## One packed value is `player * META + type index`.
const META_BITS: int = 16
const META: int = 1 << META_BITS

## Index p holds player p's counts (index 0 is unused): type id -> count. `gifts` is the report's
## `free`.
var produced: Array[Dictionary] = []
var gifts: Array[Dictionary] = []
var lost: Array[Dictionary] = []
var kills: Array[Dictionary] = []
var structures: Array[Dictionary] = []
## The ticks after which every slot of the World's flow cache was referenced (ADR 0030 section 4).
var flow_full_ticks: int = 0
var first_drop_tick: int = -1

## Row id -> packed (player, type) of every row seen alive.
var _meta: Dictionary[int, int] = {}
## Target id -> packed (player, type) of its last shooter, and the tick of that shot.
var _shooter: Dictionary[int, int] = {}
var _shot_tick: Dictionary[int, int] = {}
## Landing tick, packed (player, type), point and radius of every strike that has not landed yet,
## in order.
var _strike_landing: Array[int] = []
var _strike_by: Array[int] = []
var _strike_x: Array[int] = []
var _strike_y: Array[int] = []
var _strike_radius: Array[int] = []
## Free units owed in the tick being read: packed (player, unit type) -> count.
var _owed: Dictionary[int, int] = {}


## A counter for `players` players (1..players).
func _init(players: int = 0) -> void:
	for _index: int in players + 1:
		produced.append({})
		gifts.append({})
		lost.append({})
		kills.append({})
		structures.append({})


## Reads the rows the World starts with: scenario rows are free.
func start(world: World) -> void:
	for row: int in world.unit_count():
		var player: int = world.owner[row]
		var type: int = world.type_index[row]
		_meta[world.unit_id[row]] = player * META + type
		if player < gifts.size():
			_bump(gifts[player], String(world.type_ids[type]))


## Reads the events and the flow cache of the step that just ran.
func after_step(world: World) -> void:
	_owed.clear()
	var events: PackedInt32Array = world.events
	var tick: int = world.tick
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		match events[at]:
			World.Event.SPAWNED:
				_spawned(world, events, at)
			World.Event.SHOT:
				var by: int = _meta.get(events[at + 1], -1)
				if by >= 0:
					_shooter[events[at + 4]] = by
					_shot_tick[events[at + 4]] = tick
			World.Event.STRIKE:
				var building: int = _meta.get(events[at + 1], -1)
				if events[at + 6] > 0 and building >= 0:
					_strike_landing.append(events[at + 6])
					_strike_by.append(building)
					_strike_x.append(events[at + 2])
					_strike_y.append(events[at + 3])
					var kind: int = Strike.rupture_type(world)
					_strike_radius.append(world.type_strike_radius[kind] if kind >= 0 else 0)
			World.Event.DIED:
				_died(world, events, at)
	_drop_landed_strikes(tick)
	if first_drop_tick < 0 and world.dropped_commands > 0:
		first_drop_tick = tick - 1
	if _flow_full(world.flow):
		flow_full_ticks += 1


## The counts of `player` as the report holds them: the five maps and `spent` (produced times the
## type's cost, from `world`'s tables).
func player_counts(world: World, player: int) -> Dictionary:
	var spent: Dictionary[String, int] = {}
	var cost_of: Dictionary[String, int] = {}
	for index: int in world.type_ids.size():
		cost_of[String(world.type_ids[index])] = world.type_cost[index]
	for type_id: String in produced[player]:
		spent[type_id] = int(produced[player][type_id]) * int(cost_of.get(type_id, 0))
	return {
		"produced": produced[player],
		"free": gifts[player],
		"lost": lost[player],
		"kills": kills[player],
		"spent": spent,
		"structures": structures[player],
	}


func _spawned(world: World, events: PackedInt32Array, at: int) -> void:
	var type: int = events[at + 4]
	var player: int = events[at + 5]
	_meta[events[at + 1]] = player * META + type
	if player >= produced.size():
		return
	var type_id: String = world.type_ids[type]
	if world.type_foot_w[type] > 0:
		_bump(structures[player], type_id)
		var gift: int = world.type_free_unit[type]
		if gift >= 0:
			var key: int = player * META + gift
			_owed[key] = _owed.get(key, 0) + 1
		return
	var owed_key: int = player * META + type
	if _owed.get(owed_key, 0) > 0:
		_owed[owed_key] -= 1
		_bump(gifts[player], type_id)
	elif world.type_tab[type] >= 0:
		_bump(produced[player], type_id)
	else:
		_bump(gifts[player], type_id)


func _died(world: World, events: PackedInt32Array, at: int) -> void:
	var id: int = events[at + 1]
	var type: int = events[at + 4]
	var player: int = events[at + 5]
	var cancelled: bool = events[at + Production.DIED_CANCEL_FLAG_AT] == 1
	var credit: int = -1
	if not cancelled and player < lost.size():
		_bump(lost[player], String(world.type_ids[type]))
		if _shot_tick.get(id, -1) == world.tick:
			credit = _shooter[id]
		else:
			credit = _striker_at(world.tick, player, events[at + 2], events[at + 3])
			if credit < 0:
				credit = _shooter.get(id, -1)
	if credit >= 0:
		var killer: int = credit >> META_BITS
		if killer < kills.size():
			_bump(kills[killer], String(world.type_ids[credit & (META - 1)]))
	_meta.erase(id)
	_shooter.erase(id)
	_shot_tick.erase(id)


## The packed (player, type) of the strike building whose rupture lands in `tick`, within its
## radius of the point (`x`, `y`), against a row of `victim`'s, -1 when none does.
func _striker_at(tick: int, victim: int, x: int, y: int) -> int:
	for index: int in _strike_landing.size():
		if _strike_landing[index] != tick or _strike_by[index] >> META_BITS == victim:
			continue
		var dx: int = x - _strike_x[index]
		var dy: int = y - _strike_y[index]
		if dx * dx + dy * dy <= _strike_radius[index] * _strike_radius[index]:
			return _strike_by[index]
	return -1


func _drop_landed_strikes(tick: int) -> void:
	var index: int = 0
	while index < _strike_landing.size():
		if _strike_landing[index] <= tick:
			_strike_landing.remove_at(index)
			_strike_by.remove_at(index)
			_strike_x.remove_at(index)
			_strike_y.remove_at(index)
			_strike_radius.remove_at(index)
		else:
			index += 1


## Whether the cache has slots and every one is referenced (a FREE slot has no references).
func _flow_full(flow: FlowCache) -> bool:
	var references: PackedInt32Array = flow.ref_count
	var count: int = references.size()
	if count == 0:
		return false
	for slot: int in count:
		if references[slot] <= 0:
			return false
	return true


func _bump(counts: Dictionary, type_id: String) -> void:
	counts[type_id] = int(counts.get(type_id, 0)) + 1
