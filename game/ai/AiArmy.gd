class_name AiArmy
extends RefCounted
## The opponent AI's army manager, part 1 (ADR 0030 sections 1, 4 and 6, plan row P179): the staging
## point and its `RALLY`, the home squad, defence after the level's reaction delay and the return
## to the staging point. Waves, targets and retreat are P180's, the response to a hit by something
## unseen P179b's. It reads the `PlayerView` and `AiMemory` only, sends `RALLY`, `ATTACK_MOVE` and
## `MOVE`, and writes the army's part of the memory.
##
## It makes no pass over the view's rows (the lead's pass budget, ADR 0030 section 4): `AiIntel`'s
## refresh, which runs first in the ARMY slot, fills `memory.site_*`, `unit_*` and `seen_unit_id`
## in its own two passes, and this manager walks those lists (and looks rows up by id).
##
## - The staging point is `staging_offset_tiles` from the Headquarters toward the base estimate (the
##   point mirror of the Headquarters while none is known). One `RALLY` per tab (infantry,
##   vehicles) whose view rally point is not there and that has a finished producer, all or none
##   within the think's budget; the memory's point moves with the last of them.
## - The home squad (squad 0) holds every own combat unit except those of the scout type, which
##   stay with intel (a fresh scout has no id yet: the type, not `scout_id`, is left out).
## - A threat is a seen enemy combat unit within `defend_radius_tiles` of an own building (the most
##   pressing is the nearest to its nearest building, ties to the lower id). It is acted on once it
##   has been at the base `reaction_ticks`: the home squad gets one `ATTACK_MOVE` at it, and again
##   only when it moves to another tile; a unit that joins meanwhile gets the same order.
## - With no threat the home squad gets one `MOVE` to the staging point (also the first order of
##   the match and the one after the staging point moves), no fire on the way (ADR 0009 section 2).
##
## Goal keys (ADR 0030 section 4): the defence is the army goal (owner ARMY, one cell, up to two
## classes, replaced), the return and the rally are the staging point's (owner STAGING, up to two
## classes at one cell). The army and the staging point have precedence over the scout: when the cap
## is full and the scout holds a key alone, the scout yields (its key is released; its order in
## flight finishes, its next one waits for room, `AiIntel._may_go`). An order is all or nothing:
## the budget for every Command of it and the keys are checked first, and a refused order changes
## nothing in the memory (the next ARMY slot asks again).

## The squad index of the home squad and its role code in `memory.squad_role`.
const HOME: int = 0
const ROLE_HOME: int = 0

## Copied from the defs when the manager is made: the radius in milli-tiles, the staging offset in
## tiles, the candidate tests per slot, the reaction delay in ticks.
var defend_radius: int = 0
var staging_offset: int = 0
var tests_max: int = 0
var reaction_ticks: int = 0

## Counted for the suites: passes over the view's rows (always 0), threat candidate tests of the
## last run, and over the match the RALLY, defence and return Commands sent and the orders turned
## down because the keys could not be had.
var passes: int = 0
var tests: int = 0
var rallies: int = 0
var defences: int = 0
var returns: int = 0
var starved: int = 0

## The ids that joined the home squad in this run, ascending.
var _fresh: PackedInt32Array = PackedInt32Array()


## A manager for `player_id` that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef, _player_id: int) -> AiArmy:
	var army: AiArmy = AiArmy.new()
	army.defend_radius = maxi(def.defend_radius_tiles, 0) * PlayerView.MILLI_PER_TILE
	army.staging_offset = maxi(def.staging_offset_tiles, 0)
	army.tests_max = maxi(def.target_tests_max, 1)
	army.reaction_ticks = maxi(level.reaction_ticks, 0)
	return army


func run(view: PlayerView, memory: AiMemory, _rng: DetRandom, out: Array[Command]) -> void:
	passes = 0
	tests = 0
	if memory.squads_max < 1:
		return
	_join(memory)
	_stage(view, memory, out)
	var threat: int = _threat(view, memory)
	if threat < 0:
		memory.threat_first_tick = AiMemory.NONE
		_return(view, memory, out)
		return
	if memory.threat_first_tick == AiMemory.NONE:
		memory.threat_first_tick = view.tick
	if view.tick - memory.threat_first_tick >= reaction_ticks:
		_defend(view, memory, out, view.row_pos(threat))


## Rebuilds the member lists from the combat units of this view: a unit keeps its squad, a new one
## joins the home squad (and is noted in `_fresh`), a dead one is gone.
func _join(memory: AiMemory) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	var squads: PackedInt32Array = PackedInt32Array()
	_fresh.clear()
	for id: int in memory.unit_id:
		var at: int = memory.member_id.bsearch(id)
		ids.append(id)
		if at < memory.member_id.size() and memory.member_id[at] == id:
			squads.append(memory.member_squad[at])
		else:
			squads.append(HOME)
			_fresh.append(id)
	memory.member_id = ids
	memory.member_squad = squads
	if memory.squad_role[HOME] == AiMemory.NONE:
		memory.squad_role[HOME] = ROLE_HOME
		memory.squad_state[HOME] = AiMemory.SquadState.HOME


## The staging point: the memory's, moved and sent as `RALLY` when the Headquarters, the base
## estimate or a producer asks for it. Nothing happens without a Headquarters.
@warning_ignore("integer_division")
func _stage(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if memory.home_x == AiMemory.NONE:
		return
	var home: Vector2i = Vector2i(memory.home_x, memory.home_y)
	var base: Vector2i = Vector2i(view.map_cols - 1 - home.x, view.map_rows - 1 - home.y)
	if memory.has_base_estimate():
		base = Vector2i(memory.base_x, memory.base_y)
	var along: Vector2i = base - home
	var length: int = FixedMath.isqrt(along.x * along.x + along.y * along.y)
	var point: Vector2i = home
	if length > 0:
		point += along * staging_offset / length
	point.x = clampi(point.x, 0, view.map_cols - 1)
	point.y = clampi(point.y, 0, view.map_rows - 1)
	var x: int = point.x * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
	var y: int = point.y * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
	var producers: PackedInt32Array = _producers(view, memory)
	var wanted: int = 0
	for tab: int in [PlayerView.Tab.INFANTRY, PlayerView.Tab.VEHICLES]:
		if producers[tab] != AiMemory.NONE and (view.rally_x[tab] != x or view.rally_y[tab] != y):
			wanted += 1
	if not memory.can_send(wanted):
		return
	var classes: int = 0
	for tab: int in [PlayerView.Tab.INFANTRY, PlayerView.Tab.VEHICLES]:
		if producers[tab] == AiMemory.NONE:
			continue
		classes |= 1 << (AiIntel.FOOT if tab == PlayerView.Tab.INFANTRY else AiIntel.TRACKED)
		if view.rally_x[tab] != x or view.rally_y[tab] != y:
			out.append(Command.rally(view.player, producers[tab], x, y))
			memory.spent()
			rallies += 1
	memory.staging_x = point.x
	memory.staging_y = point.y
	_hold(memory, AiMemory.Owner.STAGING, point, classes)


## The id of the lowest finished own building per production tab (NONE for a tab without one).
func _producers(view: PlayerView, memory: AiMemory) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	found.resize(PlayerView.TABS)
	found.fill(AiMemory.NONE)
	for id: int in memory.site_id:
		var row: int = view.row_of(id)
		if row < 0 or view.row_build_left(row) > 0:
			continue
		var tab: int = view.type_produces[view.row_type(row)]
		if tab >= 0 and tab < found.size() and found[tab] == AiMemory.NONE:
			found[tab] = id
	return found


## The most pressing threat's row, -1 for none: a seen enemy combat unit within the radius of an
## own building, at most `tests_max` unit-by-building tests a run.
func _threat(view: PlayerView, memory: AiMemory) -> int:
	var found: int = -1
	var least: int = defend_radius * defend_radius + 1
	for id: int in memory.seen_unit_id:
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var at: Vector2i = view.row_pos(row)
		for site: int in memory.site_id.size():
			if tests >= tests_max:
				return found
			tests += 1
			var dx: int = at.x - memory.site_x[site]
			var dy: int = at.y - memory.site_y[site]
			if dx * dx + dy * dy < least:
				least = dx * dx + dy * dy
				found = row
	return found


## The defence: `ATTACK_MOVE` at `at` (milli-tiles) for the home squad when the goal moved to
## another tile, else only for the units that joined since.
@warning_ignore("integer_division")
func _defend(view: PlayerView, memory: AiMemory, out: Array[Command], at: Vector2i) -> void:
	var goal: Vector2i = at / PlayerView.MILLI_PER_TILE
	var moved: bool = memory.squad_goal_x[HOME] != goal.x or memory.squad_goal_y[HOME] != goal.y
	var send: PackedInt32Array = _members(memory, moved)
	if not send.is_empty():
		if not _order(view, memory, out, send, goal, AiMemory.Owner.ARMY, at):
			return
		defences += 1
	memory.squad_goal_x[HOME] = goal.x
	memory.squad_goal_y[HOME] = goal.y


## The home squad goes back to the staging point with a `MOVE` after a defence, after the staging
## point moved and at the start of the match; once, until the goal changes again.
func _return(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if not memory.has_staging():
		return
	var goal: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
	if memory.squad_goal_x[HOME] == goal.x and memory.squad_goal_y[HOME] == goal.y:
		return
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	memory.release_owner(AiMemory.Owner.ARMY)
	var send: PackedInt32Array = _members(memory, true)
	if not send.is_empty():
		var at: Vector2i = goal * PlayerView.MILLI_PER_TILE + Vector2i.ONE * PlayerView.TILE_CENTRE
		if not _order(view, memory, out, send, goal, AiMemory.Owner.STAGING, at):
			memory.goal_restore(saved)
			return
		returns += 1
	memory.squad_goal_x[HOME] = goal.x
	memory.squad_goal_y[HOME] = goal.y


## The ids of the home squad to order: all of it, or only those that joined in this run.
func _members(memory: AiMemory, all: bool) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for at: int in memory.member_id.size():
		if memory.member_squad[at] == HOME and (all or _fresh.has(memory.member_id[at])):
			ids.append(memory.member_id[at])
	return ids


## Sends `ids` to `goal` (tile; `at` in milli-tiles) with an `ATTACK_MOVE` for the army owner and a
## `MOVE` for the staging owner, one Command per `Command.MAX_UNITS`. False, and nothing sent or
## changed, when the budget for all of them or the goal keys are missing.
func _order(
	view: PlayerView,
	memory: AiMemory,
	out: Array[Command],
	ids: PackedInt32Array,
	goal: Vector2i,
	owner: int,
	at: Vector2i
) -> bool:
	var chunks: int = (ids.size() + Command.MAX_UNITS - 1) / Command.MAX_UNITS
	if not memory.can_send(chunks):
		return false
	var classes: int = 0
	for id: int in ids:
		var type: int = view.row_type(view.row_of(id))
		classes |= 1 << AiIntel.class_of(view, type)
	if not _hold(memory, owner, goal, classes):
		starved += 1
		return false
	for first: int in range(0, ids.size(), Command.MAX_UNITS):
		var part: PackedInt32Array = ids.slice(first, first + Command.MAX_UNITS)
		if owner == AiMemory.Owner.ARMY:
			out.append(Command.attack_move(view.player, part, at.x, at.y))
		else:
			out.append(Command.move(view.player, part, at.x, at.y))
		memory.spent()
	return true


## Makes `owner`'s keys the cells of `goal` for the move classes in `classes` (a bit per class) and
## those it already holds there; every key of it elsewhere is released. A full cache makes the scout
## yield. False, with the keys as they were, when even that does not make room.
func _hold(memory: AiMemory, owner: int, goal: Vector2i, classes: int) -> bool:
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	var wanted: int = classes
	for at: int in memory.goal_keys():
		if memory.goal_owner[at] & (1 << owner) != 0 and memory.goal_x[at] == goal.x:
			if memory.goal_y[at] == goal.y:
				wanted |= 1 << memory.goal_class[at]
	memory.release_owner(owner)
	for move_class: int in [AiIntel.FOOT, AiIntel.TRACKED]:
		if (
			wanted & (1 << move_class) == 0
			or memory.add_goal_key(goal.x, goal.y, move_class, owner)
		):
			continue
		if memory.goal_room(AiMemory.Owner.SCOUT) > 0:
			memory.release_owner(AiMemory.Owner.SCOUT)
		if not memory.add_goal_key(goal.x, goal.y, move_class, owner):
			memory.goal_restore(saved)
			return false
	return true
