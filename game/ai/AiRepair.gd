class_name AiRepair
extends RefCounted
## The opponent's ground support manager (ADR 0037 sections 5, 6 and 10, plan row P283; the as-built
## note of the ADR explains why it is a manager of its own), slot ARMY after `AiArmy`, on the same
## view and memory. It finds the repair building and the medic of its faction by their repair role
## in the roster, so a roster without them leaves every duty off, and sends `REPAIR`, `MOVE` and
## `ATTACK_MOVE` only:
## - Vehicles (`repair_retreat_percent`): a damaged own ground combat vehicle goes `REPAIR` to the
##   finished repair building (the one in use, else the lowest id), at most the building's repair
##   slots in flight. Wave members are left alone, but for those of a retreating wave when
##   `repair_wave_retreat` is set. A vehicle that `AiArmy` re-ordered since (the home goal moved, or
##   it joined a wave) is forgotten without an order. A whole one goes back to the home goal.
## - Medics (`medic_per_squads`): all follow a marching wave with `ATTACK_MOVE`, home with `MOVE` at
##   its end or retreat; they get no key (the army's holds the wave goal), never `ATTACK`.
## The building's key (`Owner.REPAIR`) is held only while a sent vehicle still moves, and yields to
## the army at the cap (`AiMemory.yield_keys`).

const NO_FACTION: int = -2
const _NONE: int = PlayerView.MISSING
## The move-class bits of a repair role's mask (ADR 0037 section 5; a test pins them against
## `World.MoveClass`): the vehicles a repair building serves and the foot class a medic serves.
const VEHICLE_CLASSES: int = 6
const FOOT_CLASS: int = 1

## Counters for the suites: vehicles sent to repair, vehicles sent back, medic orders.
var repairs: int = 0
var returns: int = 0
var medic_orders: int = 0

var _hq_id: StringName = &""
var _retreat: int = 0
var _in_retreat: bool = false
var _medics_on: bool = false
var _resolved: bool = false
var _building_type: int = _NONE
var _medic_type: int = _NONE
## The vehicles sent to repair, their hp at the last think (-1 before the first) and whether each
## stood withdrawn when it was sent, then their building (a row id) and the home goal then.
var _sent: PackedInt32Array = PackedInt32Array()
var _sent_hp: PackedInt32Array = PackedInt32Array()
var _sent_out: PackedInt32Array = PackedInt32Array()
var _site: int = AiMemory.NONE
var _home: Vector2i = Vector2i(AiMemory.NONE, AiMemory.NONE)
## The medics last ordered to the wave goal and that goal in tiles (NONE: they are home).
var _medic_known: PackedInt32Array = PackedInt32Array()
var _medic_goal: Vector2i = Vector2i(AiMemory.NONE, AiMemory.NONE)


static func create(def: OpponentDef, level: AiDifficultyDef) -> AiRepair:
	var repair: AiRepair = AiRepair.new()
	repair._hq_id = def.hq_type
	repair._retreat = clampi(level.repair_retreat_percent, 0, 100)
	repair._in_retreat = level.repair_wave_retreat > 0
	repair._medics_on = level.medic_per_squads > 0
	return repair


func run(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if _retreat <= 0 and not _medics_on:
		return
	if not _resolved:
		_resolved = true
		var hq: int = view.type_index_of(_hq_id)
		var faction: int = view.type_faction[hq] if hq != _NONE else NO_FACTION
		_building_type = role_type_of(view, faction, true)
		_medic_type = role_type_of(view, faction, false)
	if _building_type != _NONE and _retreat > 0:
		_vehicles(view, memory, out)
	if _medic_type != _NONE and _medics_on:
		_medics(view, memory, out)


## The first type of `faction` with a repair role: a building that serves the vehicle classes with
## slots (`building`), else an unarmed unit that serves the foot class with slots (the medic).
## MISSING for none: the role is data, so a roster without such a type changes nothing.
static func role_type_of(view: PlayerView, faction: int, building: bool) -> int:
	if view.type_repair_classes.size() != view.type_cost.size():
		return _NONE
	var need: int = VEHICLE_CLASSES if building else FOOT_CLASS
	for type: int in view.type_cost.size():
		var is_building: bool = view.type_foot_w[type] > 0
		if (
			is_building == building
			and view.type_faction[type] == faction
			and view.type_repair_slots[type] > 0
			and view.type_repair_classes[type] & need != 0
			and (building or view.type_weapon[type] < 0)
		):
			return type
	return _NONE


# --- Vehicles ----------------------------------------------------------------------------------


func _vehicles(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	var site: int = _site_row(view, memory)
	if not _tend(view, memory, out, site):
		return
	if site < 0 or not memory.can_send():
		return
	var room: int = view.type_repair_slots[_building_type] - _sent.size()
	var hurt: PackedInt32Array = _hurt(view, memory)
	if room <= 0 or hurt.is_empty():
		return
	if room < hurt.size():
		hurt.resize(room)
	if not _keys(memory, view.row_pos(site) / PlayerView.MILLI_PER_TILE):
		return
	out.append(Command.repair(view.player, hurt, view.row_id(site)))
	memory.spent()
	_site = view.row_id(site)
	_home = Vector2i(memory.squad_goal_x[AiArmy.HOME], memory.squad_goal_y[AiArmy.HOME])
	for id: int in hurt:
		_sent.append(id)
		_sent_hp.append(-1)
		_sent_out.append(1 if _withdrawn(memory, id) else 0)
	repairs += hurt.size()


## Tends the sent vehicles. It forgets, with no order, those `AiArmy` has taken over or that stand
## idle without a gain since the last think, so `_hurt` sends them again: the home goal moved (every
## home member was re-ordered), a wave holds them, they were stepped back after they were sent, the
## building they went to is gone while another stands, or they are stalled. A whole vehicle (all of
## them without a building) goes back to the home goal with one order, and the building's key goes
## once none moves. False, nothing changed, when that order finds no budget.
func _tend(view: PlayerView, memory: AiMemory, out: Array[Command], site: int) -> bool:
	if _sent.is_empty():
		return true
	var home: Vector2i = Vector2i(
		memory.squad_goal_x[AiArmy.HOME], memory.squad_goal_y[AiArmy.HOME]
	)
	var swapped: bool = site >= 0 and view.row_id(site) != _site
	var done: PackedInt32Array = PackedInt32Array()
	var kept: PackedInt32Array = PackedInt32Array()
	var kept_hp: PackedInt32Array = PackedInt32Array()
	var kept_out: PackedInt32Array = PackedInt32Array()
	var moving: bool = false
	for at: int in _sent.size():
		var id: int = _sent[at]
		var row: int = view.row_of(id)
		if row < 0 or home != _home or swapped or _held_by_wave(memory, id):
			continue
		if _sent_out[at] == 0 and _withdrawn(memory, id):
			continue
		var hp: int = view.row_hp(row)
		var idle: bool = view.row_order(row) == PlayerView.Order.IDLE
		if site < 0 or hp >= view.type_max_hp[view.row_type(row)]:
			done.append(id)
		elif not (idle and hp <= _sent_hp[at]):
			kept.append(id)
			kept_hp.append(hp)
			kept_out.append(_sent_out[at])
			moving = moving or not idle
	if not done.is_empty() and not _go_home(view, memory, out, done):
		return false
	returns += done.size()
	_sent = kept
	_sent_hp = kept_hp
	_sent_out = kept_out
	if not moving and memory.goal_keys_of(AiMemory.Owner.REPAIR) > 0:
		memory.release_owner(AiMemory.Owner.REPAIR)
	if _sent.is_empty():
		_site = AiMemory.NONE
	return true


## Whether unit `id` stepped back (`AiArmy._step_back`) and is still under its percent.
func _withdrawn(memory: AiMemory, id: int) -> bool:
	var at: int = memory.withdrawn_id.bsearch(id)
	return at < memory.withdrawn_id.size() and memory.withdrawn_id[at] == id


## Whether the wave in the field holds unit `id`: it is a member and the wave marches, or retreats
## on a level that does not repair its members.
func _held_by_wave(memory: AiMemory, id: int) -> bool:
	var at: int = memory.member_id.bsearch(id)
	if memory.squads_max <= AiArmy.WAVE or at >= memory.member_id.size():
		return false
	if memory.member_id[at] != id or memory.member_squad[at] != AiArmy.WAVE:
		return false
	if memory.squad_role[AiArmy.WAVE] == AiMemory.NONE:
		return false
	return not (_in_retreat and memory.squad_state[AiArmy.WAVE] == AiMemory.SquadState.RETREAT)


## The building the vehicles use: the one in use while it stands, else the finished one of the
## lowest id; -1 for none.
func _site_row(view: PlayerView, memory: AiMemory) -> int:
	var row: int = view.row_of(_site) if _site != AiMemory.NONE else -1
	if row >= 0 and view.row_build_left(row) == 0:
		return row
	for id: int in memory.site_id:
		row = view.row_of(id)
		if row >= 0 and view.row_type(row) == _building_type and view.row_build_left(row) == 0:
			return row
	return -1


## The own combat vehicles under the percent that no wave holds and that are not sent, ascending.
func _hurt(view: PlayerView, memory: AiMemory) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for id: int in memory.unit_id:
		var row: int = view.row_of(id)
		if row < 0 or _sent.has(id) or _held_by_wave(memory, id):
			continue
		var type: int = view.row_type(row)
		if view.type_tab[type] == PlayerView.Tab.VEHICLES and view.type_max_hp[type] > 0:
			if view.row_hp(row) * 100 < view.type_max_hp[type] * _retreat:
				found.append(id)
	return found


## One order of `ids` to the home squad's goal (`MOVE` to the staging point, `ATTACK_MOVE` to a
## goal that moved off it). False, nothing sent, without a goal or budget.
func _go_home(
	view: PlayerView, memory: AiMemory, out: Array[Command], ids: PackedInt32Array
) -> bool:
	var goal: Vector2i = Vector2i(
		memory.squad_goal_x[AiArmy.HOME], memory.squad_goal_y[AiArmy.HOME]
	)
	var staging: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
	if goal.x == AiMemory.NONE:
		goal = staging
	if not memory.has_staging() or not memory.can_send():
		return false
	var at: Vector2i = AiArmy._at(goal)
	if goal == staging:
		out.append(Command.move(view.player, ids, at.x, at.y))
	else:
		out.append(Command.attack_move(view.player, ids, at.x, at.y))
	memory.spent()
	return true


## The building's key for the vehicle class; false, nothing changed, when it finds no room.
func _keys(memory: AiMemory, tile: Vector2i) -> bool:
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	memory.release_owner(AiMemory.Owner.REPAIR)
	if memory.add_goal_key(tile.x, tile.y, AiMemory.TRACKED, AiMemory.Owner.REPAIR):
		return true
	memory.goal_restore(saved)
	return false


# --- Medics ------------------------------------------------------------------------------------


func _medics(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	var medics: PackedInt32Array = PackedInt32Array()
	for id: int in memory.own_mobile_id:
		var row: int = view.row_of(id)
		if row >= 0 and view.row_type(row) == _medic_type:
			medics.append(id)
	if medics.is_empty():
		_medic_known = medics
	if medics.is_empty() or not memory.can_send():
		return
	var wave: bool = (
		memory.squads_max > AiArmy.WAVE
		and memory.squad_role[AiArmy.WAVE] != AiMemory.NONE
		and memory.squad_state[AiArmy.WAVE] == AiMemory.SquadState.WAVE
	)
	var goal: Vector2i = Vector2i(AiMemory.NONE, AiMemory.NONE)
	if wave:
		goal = Vector2i(memory.squad_goal_x[AiArmy.WAVE], memory.squad_goal_y[AiArmy.WAVE])
	if wave and goal.x != AiMemory.NONE:
		_follow(view, memory, out, medics, goal)
	elif not wave and _medic_goal.x != AiMemory.NONE and memory.has_staging():
		var at: Vector2i = AiArmy._at(Vector2i(memory.staging_x, memory.staging_y))
		out.append(Command.move(view.player, medics, at.x, at.y))
		memory.spent()
		_medic_goal = Vector2i(AiMemory.NONE, AiMemory.NONE)
		_medic_known = medics
		medic_orders += 1


## The medics go to the wave's goal with `ATTACK_MOVE` (a move, they are unarmed) when the goal is
## new or a medic that was not ordered yet is there; a medic that died changes nothing.
func _follow(
	view: PlayerView,
	memory: AiMemory,
	out: Array[Command],
	medics: PackedInt32Array,
	goal: Vector2i
) -> void:
	var fresh: bool = goal != _medic_goal
	for id: int in medics:
		fresh = fresh or not _medic_known.has(id)
	if not fresh:
		return
	var at: Vector2i = AiArmy._at(goal)
	out.append(Command.attack_move(view.player, medics, at.x, at.y))
	memory.spent()
	_medic_goal = goal
	_medic_known = medics
	medic_orders += 1
