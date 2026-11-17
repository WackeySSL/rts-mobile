class_name AiRepair
extends RefCounted
## The opponent's ground support manager (ADR 0037 sections 5, 6 and 10, plan row P283), slot ARMY
## after `AiArmy`, on the same view and memory. It sends `REPAIR`, `MOVE` and `ATTACK_MOVE` only and
## reads the match through the `PlayerView` and the memory's lists (no pass over the rows). It is a
## manager of its own so that `AiArmy` stays small; it keeps no Resource. It finds the repair
## building and the medic of its faction by their role in the roster (`repair_building_of`,
## `medic_of`), not
## by id. Each duty is off unless the level asks for it and the roster has the type, so a faction
## without the repair types plays as before:
## - Repair (`repair_retreat_percent` above 0, the repair building in the roster): an own ground
##   vehicle (a unit of the vehicle tab that the army counts: the tankers are none) under that
##   percent of its hp, that is not in a wave in the field, goes `REPAIR` to the finished repair
##   building (the one already in use, else the nearest to the group's centre, the lower id among
##   equals). One Command a think for the group. A vehicle at full hp, or whose building is gone,
##   goes back to the staging point with a `MOVE` (the army's key holds it). The wave's own units
##   fight on: a damaged wave member is never sent.
## - Medics (`medic_per_squads` above 0, the medic in roster): the medic squads follow the wave with
##   an `ATTACK_MOVE` to its goal (unarmed, so a move) when it launches, its goal moves or a medic
##   joined, and go home with a `MOVE` to the staging point when the wave is over or retreating.
##   Medics never get `ATTACK` or `REPAIR`; at home they find hurt squads alone (`Repair.run`).
## The flow-cache keys the orders need (the repair building's tile for the vehicle class, the wave
## goal for the foot class) are the memory's `Owner.REPAIR` keys; an order that finds no room is
## not sent and tried again next think.

const _NONE: int = PlayerView.MISSING
const _WAVE: int = 1
## The move-class bits of a repair role's mask (ADR 0037 section 5: foot 1, wheeled 2, tracked 4,
## air 8; a test pins them against `World.MoveClass`): the vehicles a repair building serves, and
## the
## foot class a medic serves.
const VEHICLE_CLASSES: int = 6
const FOOT_CLASS: int = 1

## Counters for the suites: vehicles sent to repair, vehicles sent home, medic orders.
var repairs: int = 0
var returns: int = 0
var medic_orders: int = 0

var _hq_id: StringName = &""
var _retreat: int = 0
var _medics_on: bool = false
var _resolved: bool = false
var _building_type: int = _NONE
var _medic_type: int = _NONE
## The vehicles ordered to repair (ids, in the order sent) and the building they were sent to
## (`_site`, a row id, NONE for none) with its tile.
var _sent: PackedInt32Array = PackedInt32Array()
var _site: int = AiMemory.NONE
var _site_x: int = AiMemory.NONE
var _site_y: int = AiMemory.NONE
## The medics ordered to the wave goal (ids) and that goal in tiles (NONE: they are at home).
var _medic_known: PackedInt32Array = PackedInt32Array()
var _medic_x: int = AiMemory.NONE
var _medic_y: int = AiMemory.NONE
var _scratch: PackedInt32Array = PackedInt32Array()


## A manager that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef) -> AiRepair:
	var repair: AiRepair = AiRepair.new()
	repair._hq_id = def.hq_type
	repair._retreat = clampi(level.repair_retreat_percent, 0, 100)
	repair._medics_on = level.medic_per_squads > 0
	return repair


func run(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if _retreat <= 0 and not _medics_on:
		return
	_resolve(view)
	if _building_type != _NONE and _retreat > 0:
		_vehicles(view, memory, out)
	if _medic_type != _NONE and _medics_on:
		_medics(view, memory, out)


## The types as indexes of the view's roster, once (MISSING: the roster lacks it).
func _resolve(view: PlayerView) -> void:
	if _resolved:
		return
	_resolved = true
	var hq: int = view.type_index_of(_hq_id)
	var faction: int = view.type_faction[hq] if hq != _NONE else _NONE
	_building_type = repair_building_of(view, faction)
	_medic_type = medic_of(view, faction)


# --- Vehicles ----------------------------------------------------------------------------------


func _vehicles(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	_release_done(view, memory, out)
	if not memory.can_send():
		return
	var hurt: PackedInt32Array = _hurt(view, memory)
	if hurt.is_empty():
		return
	var site: int = _site_row(view, memory, hurt)
	if site < 0:
		return
	var tile: Vector2i = view.row_pos(site) / PlayerView.MILLI_PER_TILE
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	var site_id: int = view.row_id(site)
	if not _keys(memory, tile.x, tile.y, _medic_x, _medic_y):
		memory.goal_restore(saved)
		return
	out.append(Command.repair(view.player, hurt, site_id))
	memory.spent()
	_site = site_id
	_site_x = tile.x
	_site_y = tile.y
	_sent.append_array(hurt)
	repairs += hurt.size()


## Forgets the vehicles that died or are whole, and sends the whole ones (or all of them, when the
## building is gone) back to the staging point with one `MOVE`. The keys follow what is left.
func _release_done(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if _sent.is_empty():
		return
	var alive: bool = _site_alive(view)
	_scratch.clear()
	var kept: PackedInt32Array = PackedInt32Array()
	for id: int in _sent:
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var max_hp: int = view.type_max_hp[view.row_type(row)]
		if alive and view.row_hp(row) < max_hp:
			kept.append(id)
		else:
			_scratch.append(id)
	if not _scratch.is_empty():
		if not _go_home(view, memory, out, _scratch):
			return
		returns += _scratch.size()
	_sent = kept
	if _sent.is_empty():
		_site = AiMemory.NONE
		_site_x = AiMemory.NONE
		_site_y = AiMemory.NONE
		var saved: Array[PackedInt32Array] = memory.goal_snapshot()
		if not _keys(memory, _site_x, _site_y, _medic_x, _medic_y):
			memory.goal_restore(saved)


## Whether the building the vehicles were sent to still stands.
func _site_alive(view: PlayerView) -> bool:
	if _site == AiMemory.NONE:
		return false
	var row: int = view.row_of(_site)
	return row >= 0 and view.row_build_left(row) == 0


## The row of the building the vehicles use: the one in use while it stands, else the nearest
## finished one to the centre of the `hurt` vehicles, -1 for none.
func _site_row(view: PlayerView, memory: AiMemory, hurt: PackedInt32Array) -> int:
	if _site_alive(view):
		return view.row_of(_site)
	var centre: Vector2i = _centre(view, hurt)
	var best: int = -1
	var best_gap: int = 0
	for id: int in memory.site_id:
		var row: int = view.row_of(id)
		if row < 0 or view.row_type(row) != _building_type or view.row_build_left(row) != 0:
			continue
		var gap: Vector2i = view.row_pos(row) - centre
		var squared: int = gap.x * gap.x + gap.y * gap.y
		if best < 0 or squared < best_gap:
			best = row
			best_gap = squared
	return best


## The own combat vehicles under the percent that no wave in the field holds and that are not
## already sent, ids ascending.
func _hurt(view: PlayerView, memory: AiMemory) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	var wave_on: bool = _wave_on(memory)
	for id: int in memory.unit_id:
		var row: int = view.row_of(id)
		if row < 0 or _sent.has(id):
			continue
		var type: int = view.row_type(row)
		if view.type_tab[type] != PlayerView.Tab.VEHICLES or view.type_max_hp[type] <= 0:
			continue
		if view.row_hp(row) * 100 >= view.type_max_hp[type] * _retreat:
			continue
		var at: int = memory.member_id.bsearch(id)
		if wave_on and at < memory.member_id.size() and memory.member_id[at] == id:
			if memory.member_squad[at] == _WAVE:
				continue
		found.append(id)
	return found


## The centre of the rows of `ids` (the zero point for none).
func _centre(view: PlayerView, ids: PackedInt32Array) -> Vector2i:
	var sum: Vector2i = Vector2i.ZERO
	var counted: int = 0
	for id: int in ids:
		var row: int = view.row_of(id)
		if row >= 0:
			sum += view.row_pos(row)
			counted += 1
	if counted == 0:
		return Vector2i.ZERO
	@warning_ignore("integer_division")
	return sum / counted


## One `MOVE` of `ids` to the staging point (the army holds its key). False, nothing sent, when
## there is no staging point or no budget.
func _go_home(
	view: PlayerView, memory: AiMemory, out: Array[Command], ids: PackedInt32Array
) -> bool:
	if not memory.has_staging() or not memory.can_send():
		return false
	var at: Vector2i = _at(Vector2i(memory.staging_x, memory.staging_y))
	out.append(Command.move(view.player, ids.duplicate(), at.x, at.y))
	memory.spent()
	return true


# --- Medics ------------------------------------------------------------------------------------


func _medics(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	var medics: PackedInt32Array = PackedInt32Array()
	for id: int in memory.own_mobile_id:
		var row: int = view.row_of(id)
		if row >= 0 and view.row_type(row) == _medic_type:
			medics.append(id)
	if medics.is_empty():
		_medic_known = medics
		return
	if not memory.can_send():
		return
	if _wave_on(memory):
		_follow(view, memory, out, medics)
	elif _medic_x != AiMemory.NONE:
		_return_medics(view, memory, out, medics)
	_medic_known = medics


## The medics go to the wave's goal with an `ATTACK_MOVE`, when it is a new goal or a medic is new.
func _follow(
	view: PlayerView, memory: AiMemory, out: Array[Command], medics: PackedInt32Array
) -> void:
	var goal: Vector2i = Vector2i(memory.squad_goal_x[_WAVE], memory.squad_goal_y[_WAVE])
	if goal.x == AiMemory.NONE or goal.y == AiMemory.NONE:
		return
	if goal == Vector2i(_medic_x, _medic_y) and medics == _medic_known:
		return
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	if not _keys(memory, _site_x, _site_y, goal.x, goal.y):
		memory.goal_restore(saved)
		return
	var at: Vector2i = _at(goal)
	out.append(Command.attack_move(view.player, medics.duplicate(), at.x, at.y))
	memory.spent()
	_medic_x = goal.x
	_medic_y = goal.y
	medic_orders += 1


## The wave is over: the medics go back to the staging point, where they find hurt squads.
func _return_medics(
	view: PlayerView, memory: AiMemory, out: Array[Command], medics: PackedInt32Array
) -> void:
	if not _go_home(view, memory, out, medics):
		return
	_medic_x = AiMemory.NONE
	_medic_y = AiMemory.NONE
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	if not _keys(memory, _site_x, _site_y, _medic_x, _medic_y):
		memory.goal_restore(saved)
	medic_orders += 1


# --- Shared ------------------------------------------------------------------------------------


## Whether a wave marches (not in retreat): its goal is where the medics follow.
func _wave_on(memory: AiMemory) -> bool:
	return (
		memory.squads_max > _WAVE
		and memory.squad_role[_WAVE] != AiMemory.NONE
		and memory.squad_state[_WAVE] == AiMemory.SquadState.WAVE
	)


## Makes this manager's keys the vehicle class at (`site_x`, `site_y`) and the foot class at
## (`wave_x`, `wave_y`); a coordinate of NONE has no key. False when a new key finds no room (the
## caller restores the snapshot it took).
func _keys(memory: AiMemory, site_x: int, site_y: int, wave_x: int, wave_y: int) -> bool:
	memory.release_owner(AiMemory.Owner.REPAIR)
	if site_x != AiMemory.NONE:
		if not memory.add_goal_key(site_x, site_y, AiMemory.TRACKED, AiMemory.Owner.REPAIR):
			return false
	if wave_x != AiMemory.NONE:
		if not memory.add_goal_key(wave_x, wave_y, AiMemory.FOOT, AiMemory.Owner.REPAIR):
			return false
	return true


## The repair building of `faction` (its index in the roster), MISSING for none: the first building
## of the faction whose repair role serves the vehicle classes with slots. The role is data, so a
## roster without such a type (before its art) leaves every duty off.
static func repair_building_of(view: PlayerView, faction: int) -> int:
	if view.type_repair_classes.size() != view.type_cost.size():
		return _NONE
	for type: int in view.type_cost.size():
		if (
			view.type_foot_w[type] > 0
			and view.type_faction[type] == faction
			and view.type_repair_slots[type] > 0
			and view.type_repair_classes[type] & VEHICLE_CLASSES != 0
		):
			return type
	return _NONE


## The medic of `faction`, MISSING for none: the first unarmed unit of the faction whose repair role
## serves the foot class with slots.
static func medic_of(view: PlayerView, faction: int) -> int:
	if view.type_repair_classes.size() != view.type_cost.size():
		return _NONE
	for type: int in view.type_cost.size():
		if (
			view.type_foot_w[type] <= 0
			and view.type_weapon[type] < 0
			and view.type_faction[type] == faction
			and view.type_repair_slots[type] > 0
			and view.type_repair_classes[type] & FOOT_CLASS != 0
		):
			return type
	return _NONE


## The centre of `tile` in milli-tiles.
static func _at(tile: Vector2i) -> Vector2i:
	return tile * PlayerView.MILLI_PER_TILE + Vector2i.ONE * PlayerView.TILE_CENTRE
