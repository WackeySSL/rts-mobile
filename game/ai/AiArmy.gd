class_name AiArmy
extends RefCounted
## The army manager, part 1 (ADR 0030, plan row P179): the staging point and its `RALLY`, the home
## squad (every own combat unit but the scout type), defence of a threat within
## `defend_radius_tiles` of a building after `reaction_ticks`, and the `MOVE` back. Waves: P180;
## the unseen-hit response: P179b. It makes no pass over the view's rows: `AiIntel.refresh` fills
## the lists it walks. Goal keys: the defence is owner ARMY, the rally and return owner STAGING;
## both precede the scout, which yields at the cap (its order in flight keeps its cell until the
## leg ends). An order is all or nothing: budget and keys first, no memory change if refused.

## The home squad's index and role code.
const HOME: int = 0
const ROLE_HOME: int = 0

## Copied from the defs: the radius in milli-tiles, the staging offset in tiles, the tests per slot.
var defend_radius: int = 0
var staging_offset: int = 0
var tests_max: int = 0
var reaction_ticks: int = 0

## Counted for the suites: threat tests of the last run; over the match RALLY Commands, defence and
## return orders sent, and orders refused for want of keys.
var tests: int = 0
var rallies: int = 0
var defences: int = 0
var returns: int = 0
var starved: int = 0

## Joiners no order has named yet (ascending), and scratch lists kept between runs.
var _fresh: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _squads: PackedInt32Array = PackedInt32Array()
var _next: PackedInt32Array = PackedInt32Array()
var _send: PackedInt32Array = PackedInt32Array()


## A manager for `player_id` that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef, _player_id: int) -> AiArmy:
	var army: AiArmy = AiArmy.new()
	army.defend_radius = maxi(def.defend_radius_tiles, 0) * PlayerView.MILLI_PER_TILE
	army.staging_offset = maxi(def.staging_offset_tiles, 0)
	army.tests_max = maxi(def.target_tests_max, 1)
	army.reaction_ticks = maxi(level.reaction_ticks, 0)
	return army


func run(view: PlayerView, memory: AiMemory, _rng: DetRandom, out: Array[Command]) -> void:
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


## A unit keeps its squad, a new one joins the home squad (pending in `_fresh`), a dead one goes.
func _join(memory: AiMemory) -> void:
	_ids.clear()
	_squads.clear()
	_next.clear()
	for id: int in memory.unit_id:
		var at: int = memory.member_id.bsearch(id)
		_ids.append(id)
		if at < memory.member_id.size() and memory.member_id[at] == id:
			_squads.append(memory.member_squad[at])
			if _is_pending(id):
				_next.append(id)
		else:
			_squads.append(HOME)
			_next.append(id)
	var old: PackedInt32Array = memory.member_id
	memory.member_id = _ids
	_ids = old
	old = memory.member_squad
	memory.member_squad = _squads
	_squads = old
	old = _fresh
	_fresh = _next
	_next = old
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
	var base: Vector2i = AiMemory.mirror(home, view.map_cols, view.map_rows)
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
	var classes: int = 0
	for tab: int in [PlayerView.Tab.INFANTRY, PlayerView.Tab.VEHICLES]:
		if producers[tab] == AiMemory.NONE:
			continue
		var tracked: bool = tab == PlayerView.Tab.VEHICLES
		classes |= 1 << (AiMemory.TRACKED if tracked else AiMemory.FOOT)
		if view.rally_x[tab] != x or view.rally_y[tab] != y:
			wanted += 1
	if not memory.can_send(wanted) or not _hold(memory, AiMemory.Owner.STAGING, point, classes):
		return
	for tab: int in [PlayerView.Tab.INFANTRY, PlayerView.Tab.VEHICLES]:
		if producers[tab] != AiMemory.NONE and (view.rally_x[tab] != x or view.rally_y[tab] != y):
			out.append(Command.rally(view.player, producers[tab], x, y))
			memory.spent()
			rallies += 1
	memory.staging_x = point.x
	memory.staging_y = point.y


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
	elif moved:
		memory.release_owner(AiMemory.Owner.ARMY)
	_fresh.clear()
	memory.squad_goal_x[HOME] = goal.x
	memory.squad_goal_y[HOME] = goal.y


## The home squad goes back to the staging point with a `MOVE` after a defence, after the staging
## point moved and at the start of the match; once, until the goal changes again.
func _return(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if not memory.has_staging():
		return
	var goal: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
	if memory.squad_goal_x[HOME] == goal.x and memory.squad_goal_y[HOME] == goal.y:
		_fresh.clear()
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
	_fresh.clear()
	memory.squad_goal_x[HOME] = goal.x
	memory.squad_goal_y[HOME] = goal.y


## Whether `id` joined and no order has named it yet (`_fresh` is ascending).
func _is_pending(id: int) -> bool:
	var at: int = _fresh.bsearch(id)
	return at < _fresh.size() and _fresh[at] == id


## The ids of the home squad to order: all of it, or only those still pending.
func _members(memory: AiMemory, all: bool) -> PackedInt32Array:
	_send.clear()
	for at: int in memory.member_id.size():
		if memory.member_squad[at] == HOME and (all or _is_pending(memory.member_id[at])):
			_send.append(memory.member_id[at])
	return _send


## One `ATTACK_MOVE` (army owner) or `MOVE` (staging owner) of `ids` to `goal` (`at` in milli-tiles;
## `unit_cap` is under `Command.MAX_UNITS`). False, nothing changed, without budget or keys.
func _order(
	view: PlayerView,
	memory: AiMemory,
	out: Array[Command],
	ids: PackedInt32Array,
	goal: Vector2i,
	owner: int,
	at: Vector2i
) -> bool:
	if not memory.can_send():
		return false
	var classes: int = 0
	for id: int in ids:
		classes |= 1 << AiMemory.class_of(view, view.row_type(view.row_of(id)))
	if not _hold(memory, owner, goal, classes):
		starved += 1
		return false
	if owner == AiMemory.Owner.ARMY:
		out.append(Command.attack_move(view.player, ids.duplicate(), at.x, at.y))
	else:
		out.append(Command.move(view.player, ids.duplicate(), at.x, at.y))
	memory.spent()
	return true


## Makes `owner`'s keys the cells of `goal` for `classes` (a bit per move class) and those it holds
## there; its other keys go. A full cache makes the scout yield. False, keys kept, if no room.
func _hold(memory: AiMemory, owner: int, goal: Vector2i, classes: int) -> bool:
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	var wanted: int = classes
	for at: int in memory.goal_keys():
		if (
			memory.goal_owner[at] & (1 << owner) != 0
			and memory.goal_x[at] == goal.x
			and memory.goal_y[at] == goal.y
		):
			wanted |= 1 << memory.goal_class[at]
	memory.release_owner(owner)
	for move_class: int in [AiMemory.FOOT, AiMemory.TRACKED]:
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
