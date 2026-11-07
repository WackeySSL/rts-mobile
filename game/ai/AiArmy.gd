class_name AiArmy
extends RefCounted
## The army manager (ADR 0030, plan rows P179 and P180): the staging point and its `RALLY`, the home
## squad (every own combat unit but the scout type), defence of a threat within
## `defend_radius_tiles` of a building after `reaction_ticks`, and the `MOVE` back; the waves (a
## second squad, WAVE, launched from the home squad, pulled back with a `MOVE` and rejoined); the
## unseen-hit response: P179b. It makes no pass over the view's rows: `AiIntel.refresh` fills
## the lists it walks. Goal keys: the defence and a wave are owner ARMY (one goal cell at a time,
## the last order's), the rally, return and retreat owner STAGING; both precede the scout, which
## yields at the cap (its order in flight keeps its cell until the leg ends). An order is all or
## nothing: budget and keys first, no memory change if refused.

## The home squad's index and role code.
const HOME: int = 0
const ROLE_HOME: int = 0
## The wave's squad index and role code.
const WAVE: int = 1
const ROLE_WAVE: int = 1

## Copied from the defs: the radius in milli-tiles, the staging offset in tiles, the tests per slot.
var defend_radius: int = 0
var staging_offset: int = 0
var tests_max: int = 0
var reaction_ticks: int = 0
## The waves, from the level: the first tick, the first strength (credits), the growth per wave and
## the start jitter (ticks), the all-in tick (0 = never) and the two retreat tests (0 = never).
var wave_first_tick: int = 0
var wave_first_strength: int = 0
var wave_growth: int = 0
var wave_jitter: int = 0
var all_in_tick: int = 0
var retreat_percent: int = 0
var retreat_ratio: int = 0

## Counted for the suites: threat tests of the last run; over the match RALLY Commands, defence and
## return orders sent, and orders refused for want of keys.
var tests: int = 0
var rallies: int = 0
var defences: int = 0
var returns: int = 0
var starved: int = 0
## Waves launched and retreats ordered over the match (`OpponentAi` copies them to its counters).
var waves: int = 0
var retreats: int = 0

## Joiners no order has named yet (ascending), and scratch lists kept between runs.
var _fresh: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _squads: PackedInt32Array = PackedInt32Array()
var _next: PackedInt32Array = PackedInt32Array()
var _send: PackedInt32Array = PackedInt32Array()
## The last tally of the squads (`_tally`): the home squad's value, the wave's value, units and
## idle units, and the wave's centre (milli-tiles). The box round the own buildings, grown by the
## defence radius (`_box`): a unit outside it is within the radius of none.
var _home_value: int = 0
var _wave_value: int = 0
var _wave_units: int = 0
var _wave_idle: int = 0
var _wave_at: Vector2i = Vector2i.ZERO
var _lo: Vector2i = Vector2i.ZERO
var _hi: Vector2i = Vector2i.ZERO


## A manager for `player_id` that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef, _player_id: int) -> AiArmy:
	var army: AiArmy = AiArmy.new()
	army.defend_radius = maxi(def.defend_radius_tiles, 0) * PlayerView.MILLI_PER_TILE
	army.staging_offset = maxi(def.staging_offset_tiles, 0)
	army.tests_max = maxi(def.target_tests_max, 1)
	army.reaction_ticks = maxi(level.reaction_ticks, 0)
	army.wave_first_tick = maxi(level.wave_first_tick, 0)
	army.wave_first_strength = maxi(level.wave_first_strength, 0)
	army.wave_growth = maxi(level.wave_growth_percent, 0)
	army.wave_jitter = maxi(level.wave_jitter_ticks, 0)
	army.all_in_tick = maxi(level.all_in_tick, 0)
	army.retreat_percent = maxi(level.retreat_percent, 0)
	army.retreat_ratio = maxi(level.retreat_ratio_percent, 0)
	return army


func run(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> void:
	tests = 0
	if memory.squads_max < 1:
		return
	_join(memory)
	_stage(view, memory, out)
	var threat: int = _threat(view, memory)
	if threat < 0:
		memory.threat_first_tick = AiMemory.NONE
		_return(view, memory, out)
	else:
		if memory.threat_first_tick == AiMemory.NONE:
			memory.threat_first_tick = view.tick
		if view.tick - memory.threat_first_tick >= reaction_ticks:
			_defend(view, memory, out, view.row_pos(threat))
	# After the threat and the return, so a launch reads this think's threat and the return cannot
	# replace the new wave's army key.
	_wave(view, memory, rng, out)


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
	if not _box(memory):
		return found
	for id: int in memory.seen_unit_id:
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var at: Vector2i = view.row_pos(row)
		if at.x < _lo.x or at.y < _lo.y or at.x > _hi.x or at.y > _hi.y:
			continue
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


## Sets `_lo` and `_hi` to the box round the own buildings grown by the defence radius, the
## pre-filter of the search above (no test: a few compares per unit); false without a building.
func _box(memory: AiMemory) -> bool:
	if memory.site_x.is_empty():
		return false
	_lo = Vector2i(memory.site_x[0], memory.site_y[0])
	_hi = _lo
	for site: int in memory.site_x.size():
		_lo = Vector2i(mini(_lo.x, memory.site_x[site]), mini(_lo.y, memory.site_y[site]))
		_hi = Vector2i(maxi(_hi.x, memory.site_x[site]), maxi(_hi.y, memory.site_y[site]))
	_lo -= Vector2i.ONE * defend_radius
	_hi += Vector2i.ONE * defend_radius
	return true


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


## The waves (plan row P180): the wave squad's turn, or its launch while there is none. Nothing
## without a second squad, a Headquarters or a staging point.
func _wave(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> void:
	if memory.squads_max <= WAVE or memory.home_x == AiMemory.NONE or not memory.has_staging():
		return
	var all_in: bool = all_in_tick > 0 and view.tick >= all_in_tick
	if memory.squad_role[WAVE] != AiMemory.NONE:
		_tally(view, memory)
		if _wave_units == 0:
			_disband(memory)
		elif memory.squad_state[WAVE] == AiMemory.SquadState.RETREAT:
			if all_in or _wave_idle == _wave_units:
				_disband(memory)
		else:
			_fight(view, memory, out, all_in)
			return
		if memory.squad_role[WAVE] != AiMemory.NONE:
			return
	_launch(view, memory, rng, out, all_in)


## A wave in the field: pulled back when beaten (never from the all-in tick), else sent to the
## target when that moved, and from the all-in tick joined by every unit of the home squad.
func _fight(view: PlayerView, memory: AiMemory, out: Array[Command], all_in: bool) -> void:
	if not all_in and _pull_back(view, memory, out):
		return
	if memory.has_base_estimate():
		var goal: Vector2i = Vector2i(memory.base_x, memory.base_y)
		if goal.x != memory.wave_target_x or goal.y != memory.wave_target_y:
			if _order(
				view, memory, out, _ids_of(memory, WAVE), goal, AiMemory.Owner.ARMY, _at(goal)
			):
				_aim(memory, goal)
	if all_in:
		var home: PackedInt32Array = _ids_of(memory, HOME)
		var held: Vector2i = Vector2i(memory.wave_target_x, memory.wave_target_y)
		if (
			not home.is_empty()
			and _order(view, memory, out, home, held, AiMemory.Owner.ARMY, _at(held))
		):
			_assign(memory, HOME, WAVE)
			_fresh.clear()


## Whether the wave is beaten (its value is under `retreat_percent` of its launch value, or the seen
## enemy value near it passes `retreat_ratio` percent of its own) and so wants to go home; sends
## the `MOVE` to the staging point when it can, else asks again next think.
func _pull_back(view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	var weak: bool = (
		retreat_percent > 0
		and _wave_value * 100 < memory.squad_launch_value[WAVE] * retreat_percent
	)
	if not weak and retreat_ratio > 0:
		weak = _enemy_near(view, memory) * 100 > _wave_value * retreat_ratio
	if not weak:
		return false
	var stage: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
	if _order(view, memory, out, _ids_of(memory, WAVE), stage, AiMemory.Owner.STAGING, _at(stage)):
		memory.squad_state[WAVE] = AiMemory.SquadState.RETREAT
		memory.squad_goal_x[WAVE] = stage.x
		memory.squad_goal_y[WAVE] = stage.y
		memory.wave_target_x = AiMemory.NONE
		memory.wave_target_y = AiMemory.NONE
		retreats += 1
		_free_army(memory)
	return true


## The value of the seen enemy units within the defence radius of the wave's centre; a unit outside
## the box round the centre costs no test, the others at most the search's tests (counted).
func _enemy_near(view: PlayerView, memory: AiMemory) -> int:
	var found: int = 0
	for id: int in memory.seen_unit_id:
		if tests >= tests_max:
			break
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var gap: Vector2i = view.row_pos(row) - _wave_at
		if absi(gap.x) > defend_radius or absi(gap.y) > defend_radius:
			continue
		tests += 1
		if gap.x * gap.x + gap.y * gap.y <= defend_radius * defend_radius:
			found += _worth(view, row)
	return found


## Launches the next wave when the draw is made, its tick has come (or it is the all-in tick), no
## threat stands at the base and the home squad's value reaches the strength: the whole home squad
## goes to the target (`base` of the memory: the nearest known producer, else the estimate). The
## start tick is drawn once per wave, after the first tick or after the last wave ended.
func _launch(
	view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command], all_in: bool
) -> void:
	if memory.threat_first_tick != AiMemory.NONE and not all_in:
		return
	if memory.wave_start_tick == AiMemory.NONE:
		var jitter: int = rng.next_int(wave_jitter + 1) if wave_jitter > 0 else 0
		memory.wave_start_tick = maxi(wave_first_tick, view.tick) + jitter
	if (not all_in and view.tick < memory.wave_start_tick) or not memory.has_base_estimate():
		return
	_tally(view, memory)
	var ids: PackedInt32Array = _ids_of(memory, HOME)
	if ids.is_empty() or (not all_in and _home_value < _strength(memory.wave_count)):
		return
	var goal: Vector2i = Vector2i(memory.base_x, memory.base_y)
	if not _order(view, memory, out, ids, goal, AiMemory.Owner.ARMY, _at(goal)):
		return
	_assign(memory, HOME, WAVE)
	memory.squad_role[WAVE] = ROLE_WAVE
	memory.squad_state[WAVE] = AiMemory.SquadState.WAVE
	memory.squad_launch_value[WAVE] = _home_value
	_aim(memory, goal)
	memory.wave_count += 1
	waves += 1
	_fresh.clear()


## The wave's goal and target are `goal` (a tile).
func _aim(memory: AiMemory, goal: Vector2i) -> void:
	memory.squad_goal_x[WAVE] = goal.x
	memory.squad_goal_y[WAVE] = goal.y
	memory.wave_target_x = goal.x
	memory.wave_target_y = goal.y


## The value a wave needs: the first strength, grown by the growth percent once per wave launched.
@warning_ignore("integer_division")
func _strength(launched: int) -> int:
	var strength: int = wave_first_strength
	for _wave_no: int in launched:
		strength = strength * (100 + wave_growth) / 100
	return strength


## The wave squad is over (all dead, or home and rejoined): its units join the home squad and the
## next start tick is drawn again.
func _disband(memory: AiMemory) -> void:
	_assign(memory, WAVE, HOME)
	memory.squad_role[WAVE] = AiMemory.NONE
	memory.squad_state[WAVE] = AiMemory.SquadState.HOME
	memory.squad_launch_value[WAVE] = 0
	memory.squad_goal_x[WAVE] = AiMemory.NONE
	memory.squad_goal_y[WAVE] = AiMemory.NONE
	memory.wave_target_x = AiMemory.NONE
	memory.wave_target_y = AiMemory.NONE
	memory.wave_start_tick = AiMemory.NONE
	_free_army(memory)


## Lets go of the army's goal keys unless the home squad's defence holds the goal.
func _free_army(memory: AiMemory) -> void:
	if (
		memory.squad_goal_x[HOME] == memory.staging_x
		and memory.squad_goal_y[HOME] == memory.staging_y
	):
		memory.release_owner(AiMemory.Owner.ARMY)


## Sums the home squad's and the wave's value, and the wave's centre, units and idle units, over
## the members (a loop over the memory's list, not the view's rows).
@warning_ignore("integer_division")
func _tally(view: PlayerView, memory: AiMemory) -> void:
	_home_value = 0
	_wave_value = 0
	_wave_units = 0
	_wave_idle = 0
	var sum: Vector2i = Vector2i.ZERO
	for at: int in memory.member_id.size():
		var row: int = view.row_of(memory.member_id[at])
		if row < 0:
			continue
		if memory.member_squad[at] == HOME:
			_home_value += _worth(view, row)
		elif memory.member_squad[at] == WAVE:
			_wave_value += _worth(view, row)
			_wave_units += 1
			sum += view.row_pos(row)
			if view.row_order(row) == PlayerView.Order.IDLE:
				_wave_idle += 1
	if _wave_units > 0:
		_wave_at = sum / _wave_units


## The ids of `squad`'s members (ascending, in the scratch list `_order` copies).
func _ids_of(memory: AiMemory, squad: int) -> PackedInt32Array:
	_send.clear()
	for at: int in memory.member_id.size():
		if memory.member_squad[at] == squad:
			_send.append(memory.member_id[at])
	return _send


## Moves every member of squad `from` to squad `to`.
func _assign(memory: AiMemory, from: int, to: int) -> void:
	for at: int in memory.member_squad.size():
		if memory.member_squad[at] == from:
			memory.member_squad[at] = to


## The centre of `tile` in milli-tiles.
static func _at(tile: Vector2i) -> Vector2i:
	return tile * PlayerView.MILLI_PER_TILE + Vector2i.ONE * PlayerView.TILE_CENTRE


## The row's value: its type's cost scaled by its hit points.
@warning_ignore("integer_division")
static func _worth(view: PlayerView, row: int) -> int:
	var type: int = view.row_type(row)
	if type < 0 or type >= view.type_cost.size():
		return 0
	var max_hp: int = view.type_max_hp[type]
	if max_hp <= 0:
		return view.type_cost[type]
	return view.type_cost[type] * clampi(view.row_hp(row), 0, max_hp) / max_hp
