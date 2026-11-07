class_name AiArmy
extends RefCounted
## The army manager, part 1 (ADR 0030, plan row P179): the staging point and its `RALLY`, the home
## squad (every own combat unit but the scout type), defence of a threat within
## `defend_radius_tiles` of a building after `reaction_ticks`, and the `MOVE` back. Waves: P180;
## the unseen-hit response: `_unseen_hit` (P179b). It makes no pass over the view's rows:
## `AiIntel.refresh` fills the lists it walks. Goal keys: the defence is owner ARMY, the rally and
## return owner STAGING; both precede the scout, which yields at the cap (its order in flight keeps
## its cell until the leg ends). An order is all or nothing: budget and keys first, no memory
## change if refused.

## The home squad's index and role code.
const HOME: int = 0
const ROLE_HOME: int = 0

## Copied from the defs: the radius in milli-tiles, the staging offset in tiles, the tests per slot.
var defend_radius: int = 0
var staging_offset: int = 0
var tests_max: int = 0
var reaction_ticks: int = 0
## How far a unit hit by the unseen moves its squad's goal, in tiles.
var shift_tiles: int = 0

## Counted for the suites: threat tests of the last run; over the match RALLY Commands, defence and
## return orders sent, and orders refused for want of keys.
var tests: int = 0
var rallies: int = 0
var defences: int = 0
var returns: int = 0
var starved: int = 0
## The unseen-hit tests of the last run (at most `tests_max`) and the shifts sent over the match.
var hit_tests: int = 0
var shifts: int = 0

## Joiners no order has named yet (ascending), and scratch lists kept between runs.
var _fresh: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _squads: PackedInt32Array = PackedInt32Array()
var _next: PackedInt32Array = PackedInt32Array()
var _send: PackedInt32Array = PackedInt32Array()
var _hit: PackedInt32Array = PackedInt32Array()
var _kept: PackedInt32Array = PackedInt32Array()


## A manager for `player_id` that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef, _player_id: int) -> AiArmy:
	var army: AiArmy = AiArmy.new()
	army.defend_radius = maxi(def.defend_radius_tiles, 0) * PlayerView.MILLI_PER_TILE
	army.staging_offset = maxi(def.staging_offset_tiles, 0)
	army.tests_max = maxi(def.target_tests_max, 1)
	army.reaction_ticks = maxi(level.reaction_ticks, 0)
	army.shift_tiles = maxi(def.unseen_hit_shift_tiles, 0)
	return army


func run(view: PlayerView, memory: AiMemory, _rng: DetRandom, out: Array[Command]) -> void:
	tests = 0
	if memory.squads_max < 1:
		return
	_join(memory)
	_stage(view, memory, out)
	var threat: int = _threat(view, memory)
	_unseen_hit(view, memory, out, threat < 0)
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
func _defend(view: PlayerView, memory: AiMemory, out: Array[Command], at: Vector2i) -> void:
	var goal: Vector2i = at / PlayerView.MILLI_PER_TILE
	var moved: bool = memory.squad_goal_x[HOME] != goal.x or memory.squad_goal_y[HOME] != goal.y
	var send: PackedInt32Array = _members(memory, moved)
	if not send.is_empty():
		if not _order(view, memory, out, send, goal, AiMemory.Owner.ARMY, at):
			return
		defences += 1
	elif _members(memory, true).is_empty():
		memory.release_owner(AiMemory.Owner.ARMY)
	_fresh.clear()
	memory.squad_goal_x[HOME] = goal.x
	memory.squad_goal_y[HOME] = goal.y
	memory.squad_shifted[HOME] = 0


## The home squad goes back to the staging point with a `MOVE` after a defence, after the staging
## point moved and at the start of the match; once, until the goal changes again.
func _return(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if not memory.has_staging() or memory.squad_shifted[HOME] != 0:
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


## The unseen-hit response (P179b). A unit that lost hp since the last run, while no seen enemy unit
## or building was within its weapon range, makes its squad's goal move `shift_tiles` toward the
## base estimate (the point mirror of the Headquarters without one): an army order, all or nothing.
## Only while no threat stands (`calm`; the squad already fights one), one squad a run (the army
## goal is one cell), the lowest index first. The hp of a hit squad's units is kept for the next run
## when no order went (no budget, no keys), so the hit is found again; a unit whose range test ran
## into the test cap counts as covered.
func _unseen_hit(view: PlayerView, memory: AiMemory, out: Array[Command], calm: bool) -> void:
	hit_tests = 0
	_hit.resize(memory.squads_max)
	_hit.fill(0)
	var first: int = -1
	if calm:
		for at: int in memory.unit_id.size():
			var was: int = _hp_was(memory, memory.unit_id[at])
			var squad: int = memory.member_squad[at]
			if was <= memory.unit_hp[at] or squad >= _hit.size() or _hit[squad] != 0:
				continue
			if not _covered(view, memory, view.row_of(memory.unit_id[at])):
				_hit[squad] = 1
				first = squad if first < 0 else mini(first, squad)
	var done: bool = first >= 0 and _shift(view, memory, out, first)
	_kept.clear()
	for at: int in memory.unit_id.size():
		var squad: int = memory.member_squad[at]
		var keep: bool = squad < _hit.size() and _hit[squad] != 0 and not (done and squad == first)
		var was: int = _hp_was(memory, memory.unit_id[at]) if keep else AiMemory.NONE
		_kept.append(was if was != AiMemory.NONE else memory.unit_hp[at])
	memory.hp_id = memory.unit_id.duplicate()
	memory.hp_value = _kept.duplicate()


## The hp unit `id` had at the last run, NONE when it was not listed.
func _hp_was(memory: AiMemory, id: int) -> int:
	var at: int = memory.hp_id.bsearch(id)
	if at < memory.hp_id.size() and memory.hp_id[at] == id:
		return memory.hp_value[at]
	return AiMemory.NONE


## Whether a seen enemy unit or building stands within the weapon range of the own unit at `row`,
## or the test cap (`tests_max` a run, shared by all units) ran out first.
func _covered(view: PlayerView, memory: AiMemory, row: int) -> bool:
	if row < 0:
		return true
	var at: Vector2i = view.row_pos(row)
	var reach: int = view.type_range[view.row_type(row)]
	for list: PackedInt32Array in [memory.seen_unit_id, memory.seen_site_id]:
		for foe: int in list:
			if hit_tests >= tests_max:
				return true
			hit_tests += 1
			var other: int = view.row_of(foe)
			if other < 0:
				continue
			var gap: Vector2i = view.row_pos(other) - at
			if gap.x * gap.x + gap.y * gap.y <= reach * reach:
				return true
	return false


## The shift of `squad`'s goal by `shift_tiles` toward the base estimate, ordered to its members.
## False, nothing changed, when the order was refused; true when sent or nothing is to be done.
func _shift(view: PlayerView, memory: AiMemory, out: Array[Command], squad: int) -> bool:
	var goal: Vector2i = Vector2i(memory.squad_goal_x[squad], memory.squad_goal_y[squad])
	if goal.x == AiMemory.NONE or memory.home_x == AiMemory.NONE or shift_tiles == 0:
		return true
	var base: Vector2i = Vector2i(memory.base_x, memory.base_y)
	if not memory.has_base_estimate():
		base = AiMemory.mirror(Vector2i(memory.home_x, memory.home_y), view.map_cols, view.map_rows)
	var along: Vector2i = base - goal
	var length: int = FixedMath.isqrt(along.x * along.x + along.y * along.y)
	var to: Vector2i = base
	if length > shift_tiles:
		to = goal + Vector2i(_scaled(along.x, length), _scaled(along.y, length))
	to.x = clampi(to.x, 0, view.map_cols - 1)
	to.y = clampi(to.y, 0, view.map_rows - 1)
	_send.clear()
	for at: int in memory.member_id.size():
		if memory.member_squad[at] == squad:
			_send.append(memory.member_id[at])
	if to == goal or _send.is_empty():
		return true
	var centre: Vector2i = to * PlayerView.MILLI_PER_TILE + Vector2i.ONE * PlayerView.TILE_CENTRE
	if not _order(view, memory, out, _send, to, AiMemory.Owner.ARMY, centre):
		return false
	memory.squad_goal_x[squad] = to.x
	memory.squad_goal_y[squad] = to.y
	memory.squad_shifted[squad] = 1
	shifts += 1
	return true


## `part` of a vector of `length` scaled to `shift_tiles`, rounded to the nearest tile.
func _scaled(part: int, length: int) -> int:
	@warning_ignore("integer_division")
	return (2 * part * shift_tiles + signi(part) * length) / (2 * length)


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
