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
## - `kills_by_layer`: the credited kills by the layer of the dead row, `ground`, `air` and
##   `low_air` (`World.Layer`), from `type_layer_bit`; its sum is the sum of `kills` (ADR 0036
##   section 3, P254). Absent means 0.
## - `reveals`: the accepted sweeps, the STRIKE records of kind REVEAL, per player (P254).
## - `research` (read at the end, in player_counts): the upgrades the player owns, `{upgrade id: 1}`
##   from the bits of `world.upgrades` (the sim has no research event, and a bit is never cleared).
## - The strike keys (ADR 0047 section 12, P571; added keys, schema 2 unchanged), `STRIKE_KEYS`, per
##   player, all ints and 0 for a match with no strike. Firer side: `strike_fires_rupture` and
##   `strike_fires_blackout` (the STRIKE records of kind RUPTURE and BLACKOUT, counted at the fire);
##   `strike_damage_enemy` and `strike_damage_own` (hp that the player's strikes took from other and
##   neutral rows, and from the player's own); `strike_kills_buildings`, `strike_kills_units` (other
##   and neutral rows) and `strike_kills_own` (own rows of either kind). A strike's effect is read
##   in the step it happens: the blackout in the step of its STRIKE record, the rupture in the step
##   of its landing tick. The hit of a row is the weapon's damage by the armour percent and
##   `Upgrades.taken` (`Combat.damage`, at least 1, 0 when the percent is 0), on the hp before the
##   step (`before_step`; COMMANDS precedes the shots); a rupture takes only rows whose layer the
##   weapon hits, a blackout's overload only building rows of other owners, and a blackout whose
##   type has no `type_strike_weapon` (-1) does no damage. The taken hp is the hit capped at that
##   hp; a kill is a row with a hit at or above its hp that has a DIED record (not a cancel) in the
##   step,
##   so a rupture's is an upper bound when shots also landed (and a sale before an overload too).
##   Victim side (every other player is a victim of a fire): `blackout_building_ticks` (own
##   complete buildings with `offline_until` above the stamp, summed per step),
##   `sight_cut_building_ticks` (own
##   buildings with `fog_cell` -1 while offline), `sight_cells_lost` (per strike: cells visible
##   in the victim's block at the end of the step before the effect and not visible after the
##   victim's first fog turn at or after it) and `radar_dark_ticks` (steps in which `Radar.dark` is
##   true for the player at the step's stamp: a complete offline radar building and no complete
##   online one; 0 for a World whose types have no radar).
## - `first_drop_tick`: the tick of the first step after which `dropped_commands` was above 0, -1
##   while none was (a harness failure names it).
## - Free-unit edges: a refused `spawn_free` (unit cap, no exit) in the tick of its refinery
##   leaves the owed count in place for the rest of that tick, so a unit of that type produced in
##   the same tick counts as free; and on the dormant
##   place-first path (ADR 0026) the free harvester spawns when the site completes, ticks after
##   the refinery's SPAWNED, so it counts as produced. The AI never uses that path.

## The strike keys of a player entry, in the report's order.
const STRIKE_KEYS: Array[String] = [
	"strike_fires_rupture",
	"strike_fires_blackout",
	"strike_damage_enemy",
	"strike_damage_own",
	"strike_kills_buildings",
	"strike_kills_units",
	"strike_kills_own",
	"blackout_building_ticks",
	"sight_cut_building_ticks",
	"sight_cells_lost",
	"radar_dark_ticks",
]

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
var kills_by_layer: Array[Dictionary] = []
## Index p holds the sweeps player p started.
var reveals: Array[int] = []
## Index p holds player p's strike keys: `STRIKE_KEYS` entry -> count.
var strike: Array[Dictionary] = []
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
## The rows' hp and the fog counts as they stood before the step (`before_step`), empty when the
## step has no strike to read.
var _pre: Dictionary = {}
## The ids that died in the step being read (a cancelled site is not one).
var _died_now: Dictionary[int, bool] = {}
## The blackouts that were fired in the step being read: packed (player, type), point.
var _blackouts_now: Array[Dictionary] = []
## The steps below this tick may have an offline building (read at `start`, raised by a blackout).
var _watch_until: int = 0
## Strike effects whose cells lost wait for the victim's fog turn: `victim`, `from` (the tick the
## step started at) and `before` (the victim's visible counts then).
var _cells_pending: Array[Dictionary] = []
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
		kills_by_layer.append({})
		reveals.append(0)
		var keys: Dictionary = {}
		for key: String in STRIKE_KEYS:
			keys[key] = 0
		strike.append(keys)


## Reads the rows the World starts with: scenario rows are free.
func start(world: World) -> void:
	for row: int in world.unit_count():
		var player: int = world.owner[row]
		var type: int = world.type_index[row]
		_meta[world.unit_id[row]] = player * META + type
		if player < gifts.size():
			_bump(gifts[player], String(world.type_ids[type]))
		_watch_until = maxi(_watch_until, world.offline_until[row])


## Reads what the coming step needs from the World as it stands: when `commands` hold a SUPERWEAPON
## or a rupture lands in the step, the rows' hp and the fog counts before it. Call it before
## `MatchLoop.step`; without it the strike damage, kills and cells lost of that step read 0.
func before_step(world: World, commands: Array[Command]) -> void:
	_pre = {}
	var wanted: bool = false
	for command: Command in commands:
		if command.type == Command.Type.SUPERWEAPON:
			wanted = true
			break
	for landing: int in _strike_landing:
		wanted = wanted or landing <= world.tick + 1
	if not wanted:
		return
	_pre = {
		"tick": world.tick,
		"ids": world.unit_id.duplicate(),
		"owner": world.owner.duplicate(),
		"type": world.type_index.duplicate(),
		"x": world.pos_x.duplicate(),
		"y": world.pos_y.duplicate(),
		"hp": world.hp.duplicate(),
		"visible": world.fog.visible.duplicate(),
	}


## Reads the events and the flow cache of the step that just ran.
func after_step(world: World) -> void:
	_owed.clear()
	_died_now.clear()
	_blackouts_now.clear()
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
				_fired(world, events, at)
				if events[at + 4] == Strike.Kind.REVEAL and events[at + 5] < reveals.size():
					reveals[events[at + 5]] += 1
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
	_read_strikes(world)
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
	return (
		{
			"produced": produced[player],
			"free": gifts[player],
			"lost": lost[player],
			"kills": kills[player],
			"spent": spent,
			"structures": structures[player],
			"kills_by_layer": kills_by_layer[player],
			"reveals": reveals[player],
			"research": _research(world, player),
		}
		. merged(strike[player])
	)


## `{upgrade id: 1}` for each upgrade bit `player` holds (none for a player without a slot).
func _research(world: World, player: int) -> Dictionary[String, int]:
	var owned: Dictionary[String, int] = {}
	if player >= world.upgrades.size():
		return owned
	for index: int in world.upgrade_ids.size():
		if (world.upgrades[player] >> index) & 1 == 1:
			owned[String(world.upgrade_ids[index])] = 1
	return owned


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
	if not cancelled:
		_died_now[id] = true
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
			_bump(kills_by_layer[killer], _layer_name(world.type_layer_bit[type]))
	_meta.erase(id)
	_shooter.erase(id)
	_shot_tick.erase(id)


## Counts the fire of the STRIKE record at `at` and keeps a blackout for `_read_strikes`.
func _fired(world: World, events: PackedInt32Array, at: int) -> void:
	var kind: int = events[at + 4]
	var player: int = events[at + 5]
	if player >= strike.size():
		return
	if kind == Strike.Kind.RUPTURE:
		strike[player]["strike_fires_rupture"] += 1
	elif kind == Strike.Kind.BLACKOUT:
		strike[player]["strike_fires_blackout"] += 1
		var building: int = _meta.get(events[at + 1], -1)
		var type: int = -1 if building < 0 else building & (META - 1)
		_blackouts_now.append(
			{"player": player, "type": type, "x": events[at + 2], "y": events[at + 3]}
		)
		if type >= 0 and type < world.type_strike_ticks.size():
			_watch_until = maxi(_watch_until, world.tick + world.type_strike_ticks[type])


## The strike effects of the step just run (a blackout fired in it, a rupture landing in it), the
## cells lost that a victim's fog turn settles, and the victim-side ticks.
func _read_strikes(world: World) -> void:
	for blackout: Dictionary in _blackouts_now:
		var type: int = blackout["type"]
		var weapon: int = -1
		var radius: int = 0
		if type >= 0 and type < world.type_strike_weapon.size():
			weapon = world.type_strike_weapon[type]
			radius = world.type_strike_radius[type]
		_effect(
			world,
			Strike.Kind.BLACKOUT,
			blackout["player"],
			blackout["x"],
			blackout["y"],
			weapon,
			radius
		)
	for index: int in _strike_landing.size():
		if _strike_landing[index] > world.tick:
			continue
		var kind: int = Strike.rupture_type(world)
		var weapon: int = -1 if kind < 0 else world.type_strike_weapon[kind]
		_effect(
			world,
			Strike.Kind.RUPTURE,
			_strike_by[index] >> META_BITS,
			_strike_x[index],
			_strike_y[index],
			weapon,
			_strike_radius[index]
		)
	_settle_cells(world)
	if world.tick < _watch_until:
		_count_offline(world)


## One effect of `player`'s strike of `kind` at the point (x, y): the hp taken and the kills from
## the hp before the step, and the victims' cells waiting for their fog turn.
func _effect(
	world: World, kind: int, player: int, x: int, y: int, weapon: int, radius: int
) -> void:
	if _pre.is_empty():
		return
	var ids: PackedInt32Array = _pre["ids"]
	var owners: PackedInt32Array = _pre["owner"]
	var types: PackedInt32Array = _pre["type"]
	var hit_points: PackedInt32Array = _pre["hp"]
	var reach: int = radius * radius
	var armours: int = World.Armour.size()
	var valid: bool = weapon >= 0 and weapon < world.weapon_damage.size()
	for row: int in ids.size():
		if hit_points[row] <= 0 or not valid:
			continue
		var dx: int = int(_pre["x"][row]) - x
		var dy: int = int(_pre["y"][row]) - y
		if dx * dx + dy * dy > reach:
			continue
		var type: int = types[row]
		var building: bool = world.type_foot_w[type] > 0
		var owner: int = owners[row]
		if kind == Strike.Kind.BLACKOUT:
			if owner == player or not building:
				continue
		elif (world.weapon_targets[weapon] & world.type_layer_bit[type]) == 0:
			continue
		var percent: int = world.weapon_vs_armour[weapon * armours + world.type_armour[type]]
		var hit: int = Combat.damage(
			world.weapon_damage[weapon], percent, Combat.PERCENT, Upgrades.taken(world, owner, type)
		)
		if hit <= 0:
			continue
		var taken: int = mini(hit, hit_points[row])
		var killed: bool = hit >= hit_points[row] and _died_now.has(ids[row])
		var mine: Dictionary = strike[player]
		if owner == player:
			mine["strike_damage_own"] += taken
			mine["strike_kills_own"] += 1 if killed else 0
		else:
			mine["strike_damage_enemy"] += taken
			if killed:
				mine["strike_kills_buildings" if building else "strike_kills_units"] += 1
	var cells: int = world.fog.cells
	for victim: int in range(1, strike.size()):
		if victim == player or victim > world.fog.player_count:
			continue
		var block: PackedInt32Array = _pre["visible"].slice((victim - 1) * cells, victim * cells)
		_cells_pending.append({"victim": victim, "from": _pre["tick"], "before": block})


## Settles the cells lost of every waiting effect whose victim had its fog turn in the last step.
func _settle_cells(world: World) -> void:
	var period: int = maxi(world.fog_period_ticks, 1)
	var began: int = world.tick - 1
	var index: int = 0
	while index < _cells_pending.size():
		var entry: Dictionary = _cells_pending[index]
		var victim: int = entry["victim"]
		if began < int(entry["from"]) or (began - victim + 1) % period != 0:
			index += 1
			continue
		var before: PackedInt32Array = entry["before"]
		var now: PackedInt32Array = world.fog.visible
		var base: int = (victim - 1) * world.fog.cells
		var lost: int = 0
		for cell: int in before.size():
			if before[cell] > 0 and now[base + cell] == 0:
				lost += 1
		strike[victim]["sight_cells_lost"] += lost
		_cells_pending.remove_at(index)


## One step of the victim-side tick counts, read from the rows that stand after the step (the stamp
## of the step that ran is `world.tick`).
func _count_offline(world: World) -> void:
	var stamp: int = world.tick
	for row: int in world.unit_count():
		var player: int = world.owner[row]
		var type: int = world.type_index[row]
		if player < 1 or player >= strike.size() or world.type_foot_w[type] <= 0:
			continue
		var complete: bool = world.build_left[row] == 0
		if world.offline_until[row] > stamp:
			if complete:
				strike[player]["blackout_building_ticks"] += 1
			if world.fog_cell[row] == -1:
				strike[player]["sight_cut_building_ticks"] += 1
	for player: int in range(1, strike.size()):
		if Radar.dark(world, player, stamp):
			strike[player]["radar_dark_ticks"] += 1


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


## The report's name of a layer bit.
static func _layer_name(bit: int) -> String:
	if bit == World.Layer.AIR:
		return "air"
	return "low_air" if bit == World.Layer.LOW_AIR else "ground"


func _bump(counts: Dictionary, type_id: String) -> void:
	counts[type_id] = int(counts.get(type_id, 0)) + 1
