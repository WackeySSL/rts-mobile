class_name AiArmy
extends RefCounted
## The army manager (ADR 0030, plan rows P179, P180 and P180b): the staging point and its `RALLY`,
## the home squad (every own combat unit but the scout type), defence of a threat within
## `defend_radius_tiles` of a building after `reaction_ticks`, and the `MOVE` back; the waves (a
## second squad, WAVE, launched from the home squad, pulled back with a `MOVE` and rejoined, or
## recalled into the home squad when a threat at the base outweighs it); the unseen-hit response
## (`_unseen_hit`, P179b); Hard's unit control (`_step_back`, `_focus`). It makes no pass over the
## view's rows: `AiIntel.refresh` fills the lists it walks. Goal keys: the defence, the shift, a
## wave and a focus `ATTACK` are owner ARMY (one goal cell at a time, the last order's), the rally,
## return, retreat and step-back owner STAGING; both precede the scout, which yields at the cap (its
## order in flight keeps its cell until the leg ends). An order is all or nothing: budget and keys
## first, no memory change if refused. From `all_in_tick` the all-in overrides the defence
## (`_all_in_wave`).

## The home squad's index and role code.
const HOME: int = 0
const ROLE_HOME: int = 0
## The wave's squad index and role code.
const WAVE: int = 1
const ROLE_WAVE: int = 1
## P196 experiment: the all-in sends the home squad to the wave only once this many units wait.
const REINFORCE_MIN: int = 6

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
## How far a unit hit by the unseen moves its squad's goal, in tiles.
var shift_tiles: int = 0
## Hard's unit control, from the level: the hp percent a unit steps back under (0 = never) and
## whether groups focus the weakest enemy in reach.
var unit_retreat_hp: int = 0
var focus_fire: bool = false

## Counted for the suites: tests of the last run: the threat search's, the home focus search's, the
## wave's ratio read, the recall's read and the wave focus search's (they all share the cap of
## `tests_max`, in that order, so an earlier one that uses it up leaves the later ones blind that
## think); over the match RALLY Commands, defence and return orders sent, and orders refused for
## want of keys.
var tests: int = 0
var rallies: int = 0
var defences: int = 0
var returns: int = 0
var starved: int = 0
## Waves launched and retreats ordered over the match (`OpponentAi` copies them to its counters).
var waves: int = 0
var retreats: int = 0
## Waves recalled to defend the base over the match (disbanded into the home squad at once).
var recalls: int = 0
## The unseen-hit tests of the last run (at most `tests_max`) and the shifts sent over the match.
var hit_tests: int = 0
var shifts: int = 0
## Over the match: units stepped back on their own and focus-fire `ATTACK` orders sent.
var stepbacks: int = 0
var focuses: int = 0

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
var _ready_value: int = 0
var _capped: bool = false
var _wave_value: int = 0
var _wave_units: int = 0
var _wave_idle: int = 0
var _wave_at: Vector2i = Vector2i.ZERO
var _lo: Vector2i = Vector2i.ZERO
var _hi: Vector2i = Vector2i.ZERO
## The tick of the last unseen-hit shift (-1: none yet).
var _shifted_at: int = -1
## Scratch for two swaps: the hp list of `_unseen_hit` and the withdrawn list of `_step_back`.
var _kept: PackedInt32Array = PackedInt32Array()
## The ids under the step-back percent that have not stepped back yet (`_step_back`).
var _low: PackedInt32Array = PackedInt32Array()
## This think's standing threat after `reaction_ticks` (before the all-in), for the wave's recall.
var _threat_on: bool = false
var _threat_at: Vector2i = Vector2i.ZERO


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
	army.shift_tiles = maxi(def.unseen_hit_shift_tiles, 0)
	army.unit_retreat_hp = clampi(level.unit_retreat_hp_percent, 0, 100)
	army.focus_fire = level.focus_fire > 0
	return army


func run(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> void:
	tests = 0
	_threat_on = false
	if memory.squads_max < 1:
		return
	_join(memory)
	_stage(view, memory, out)
	_step_back(view, memory, out)
	var threat: int = _threat(view, memory)
	_unseen_hit(view, memory, out, threat < 0 and memory.threat_first_tick == AiMemory.NONE)
	if threat < 0:
		memory.threat_first_tick = AiMemory.NONE
		memory.squad_focus[HOME] = AiMemory.NONE
		_return(view, memory, out)
	else:
		if memory.threat_first_tick == AiMemory.NONE:
			memory.threat_first_tick = view.tick
		if (
			view.tick - memory.threat_first_tick >= reaction_ticks
			and not _all_in_wave(view, memory)
		):
			_threat_on = true
			_threat_at = view.row_pos(threat)
			if not focus_fire or not _focus(view, memory, out, HOME):
				_defend(view, memory, out, _threat_at)
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
	var x: int = _at(point).x
	var y: int = _at(point).y
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
func _defend(view: PlayerView, memory: AiMemory, out: Array[Command], at: Vector2i) -> void:
	var goal: Vector2i = at / PlayerView.MILLI_PER_TILE
	var moved: bool = memory.squad_goal_x[HOME] != goal.x or memory.squad_goal_y[HOME] != goal.y
	var send: PackedInt32Array = _members(memory, moved)
	if not send.is_empty():
		if not _order(view, memory, out, send, goal, AiMemory.Owner.ARMY, at):
			return
		defences += 1
	elif _members(memory, true).is_empty() and not _wave_holds_army(memory):
		memory.release_owner(AiMemory.Owner.ARMY)
	_fresh.clear()
	memory.squad_goal_x[HOME] = goal.x
	memory.squad_goal_y[HOME] = goal.y
	memory.home_shifted = 0


## The home squad goes back to the staging point with a `MOVE` after a defence, after the staging
## point moved, at the start of the match and when an unseen-hit probe is over (`_probing`); once,
## until the goal changes again.
func _return(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if not memory.has_staging() or (memory.home_shifted != 0 and _probing(view, memory)):
		return
	var goal: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
	var at_goal: bool = memory.squad_goal_x[HOME] == goal.x and memory.squad_goal_y[HOME] == goal.y
	if at_goal and memory.home_shifted == 0:
		_fresh.clear()
		return
	var saved: Array[PackedInt32Array] = memory.goal_snapshot()
	if not _wave_holds_army(memory):
		memory.release_owner(AiMemory.Owner.ARMY)
	var send: PackedInt32Array = _members(memory, true)
	if not send.is_empty():
		var at: Vector2i = _at(goal)
		if not _order(view, memory, out, send, goal, AiMemory.Owner.STAGING, at):
			memory.goal_restore(saved)
			return
		returns += 1
	_fresh.clear()
	memory.squad_goal_x[HOME] = goal.x
	memory.squad_goal_y[HOME] = goal.y
	memory.home_shifted = 0


## The unseen-hit response (P179b), for the home squad only (a wave's goal is the waves' own). A
## home unit (not one that stepped back) that lost hp since the last run, while no seen enemy
## combat unit or building was within its weapon range, makes the squad's goal move `shift_tiles`
## toward the base estimate (the point mirror of the Headquarters without one): an army order, all
## or nothing. The shifted goal
## is a probe, held while `home_shifted` is set (see `_probing`); further hits do not move it, but
## after the return to the staging point a new hit shifts again, out and back, never creeping. Only
## while no threat stands and none stood at the last run (`calm`; the squad fought it, and a foe
## it killed is gone from the view). The hp of the home units is kept for the next run when no
## order went (no budget, no keys), so the hit is found again; a unit whose range test ran into
## the test cap counts as covered. `unit_id` and `member_id` are the same list after `_join`, so
## an index of one is the other's.
func _unseen_hit(view: PlayerView, memory: AiMemory, out: Array[Command], calm: bool) -> void:
	hit_tests = 0
	var refused: bool = false
	if calm and memory.home_shifted == 0:
		for at: int in memory.unit_id.size():
			if memory.member_squad[at] != HOME or _withdrawn(memory, memory.unit_id[at]):
				continue
			if _hp_was(memory, memory.unit_id[at]) <= memory.unit_hp[at]:
				continue
			if not _covered(view, memory, view.row_of(memory.unit_id[at])):
				refused = not _shift(view, memory, out)
				break
	_kept.clear()
	for at: int in memory.unit_id.size():
		var was: int = AiMemory.NONE
		if refused and memory.member_squad[at] == HOME:
			was = _hp_was(memory, memory.unit_id[at])
		_kept.append(was if was != AiMemory.NONE else memory.unit_hp[at])
	memory.hp_id.clear()
	memory.hp_id.append_array(memory.unit_id)
	var old: PackedInt32Array = memory.hp_value
	memory.hp_value = _kept
	_kept = old


## The hp unit `id` had at the last run, NONE when it was not listed.
func _hp_was(memory: AiMemory, id: int) -> int:
	var at: int = memory.hp_id.bsearch(id)
	if at < memory.hp_id.size() and memory.hp_id[at] == id:
		return memory.hp_value[at]
	return AiMemory.NONE


## Whether a seen enemy combat unit or building stands within the weapon range of the own unit at
## `row`, or the test cap (`tests_max` a run, shared by all units) ran out first.
func _covered(view: PlayerView, memory: AiMemory, row: int) -> bool:
	if row < 0:
		return true
	var at: Vector2i = view.row_pos(row)
	var reach: int = view.type_range[view.row_type(row)]
	return (
		_reaches(view, memory.seen_unit_id, at, reach)
		or _reaches(view, memory.seen_site_id, at, reach)
	)


## Whether a row of `list` is within `reach` of `at`, or the test cap ran out (one test a row).
func _reaches(view: PlayerView, list: PackedInt32Array, at: Vector2i, reach: int) -> bool:
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


## The shift of the home squad's goal by `shift_tiles` toward the base estimate, ordered to the
## whole squad (so no joiner is pending after it). False, nothing changed, when the order was
## refused; true when sent or nothing is to be done. Without a Headquarters only the mirror
## fallback is lost: a known base estimate still serves.
func _shift(view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	var goal: Vector2i = Vector2i(memory.squad_goal_x[HOME], memory.squad_goal_y[HOME])
	var base: Vector2i = Vector2i(memory.base_x, memory.base_y)
	if not memory.has_base_estimate():
		if memory.home_x == AiMemory.NONE:
			return true
		base = AiMemory.mirror(Vector2i(memory.home_x, memory.home_y), view.map_cols, view.map_rows)
	if goal.x == AiMemory.NONE or shift_tiles == 0:
		return true
	var along: Vector2i = base - goal
	var length: int = FixedMath.isqrt(along.x * along.x + along.y * along.y)
	var to: Vector2i = base
	if length > shift_tiles:
		to = goal + _scaled(along, length)
	var send: PackedInt32Array = _members(memory, true)
	if to == goal or send.is_empty():
		return true
	if not _order(view, memory, out, send, to, AiMemory.Owner.ARMY, _at(to)):
		return false
	_fresh.clear()
	memory.squad_goal_x[HOME] = to.x
	memory.squad_goal_y[HOME] = to.y
	memory.home_shifted = 1
	_shifted_at = view.tick
	shifts += 1
	return true


## `along` scaled to `shift_tiles` tiles (`length` is its length), each part rounded to the nearest
## tile, halves away from zero.
func _scaled(along: Vector2i, length: int) -> Vector2i:
	@warning_ignore("integer_division")
	return (along * (2 * shift_tiles) + along.sign() * length) / (2 * length)


## Whether the shifted home goal is still held: in the slot of the shift (its order is not in the
## view yet), and while a home member the shift named is alive and still on its way or fighting: not
## idle, or idle with a seen enemy combat unit or building in its weapon range (it fires from where
## it stands). A range test cut off by the test cap counts as not fighting, so a long seen list
## cannot hold the probe for good. When every one has arrived, quiet, or died the probe is over.
func _probing(view: PlayerView, memory: AiMemory) -> bool:
	if view.tick == _shifted_at:
		return true
	for at: int in memory.member_id.size():
		var id: int = memory.member_id[at]
		if memory.member_squad[at] != HOME or _is_pending(id):
			continue
		var row: int = view.row_of(id)
		if row < 0:
			continue
		if view.row_order(row) != PlayerView.Order.IDLE:
			return true
		if _covered(view, memory, row) and hit_tests < tests_max:
			return true
	return false


## Whether `id` joined and no order has named it yet (`_fresh` is ascending).
func _is_pending(id: int) -> bool:
	var at: int = _fresh.bsearch(id)
	return at < _fresh.size() and _fresh[at] == id


## The ids of `squad` (the home squad) to order: all of it, or only those still pending. A unit that
## stepped back is left out when `launch` is set (a wave's launch), and only then: it still defends
## the base and joins the all-in. The sim has no healing, so it stays withdrawn until it dies (the
## list would let it go if its hp came back to the percent or over).
func _members(
	memory: AiMemory, all: bool, squad: int = HOME, launch: bool = false
) -> PackedInt32Array:
	_send.clear()
	for at: int in memory.member_id.size():
		var id: int = memory.member_id[at]
		if (
			memory.member_squad[at] == squad
			and (all or _is_pending(id))
			and not (launch and _withdrawn(memory, id))
		):
			_send.append(id)
	return _send


## One `ATTACK_MOVE` (army owner; an `ATTACK` on `target` when that is set) or `MOVE` (staging
## owner) of `ids` to `goal` (`at` in milli-tiles; `unit_cap` is under `Command.MAX_UNITS`). False,
## nothing changed, without budget or keys.
func _order(
	view: PlayerView,
	memory: AiMemory,
	out: Array[Command],
	ids: PackedInt32Array,
	goal: Vector2i,
	owner: int,
	at: Vector2i,
	target: int = AiMemory.NONE
) -> bool:
	if not memory.can_send():
		return false
	var classes: int = 0
	for id: int in ids:
		classes |= 1 << AiMemory.class_of(view, view.row_type(view.row_of(id)))
	if not _hold(memory, owner, goal, classes):
		starved += 1
		return false
	if owner == AiMemory.Owner.ARMY and target != AiMemory.NONE:
		out.append(Command.attack(view.player, ids.duplicate(), target))
	elif owner == AiMemory.Owner.ARMY:
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
## without a second squad or a staging point; a wave in the field goes on (retreat, re-target,
## disband) after the Headquarters is gone.
func _wave(view: PlayerView, memory: AiMemory, rng: DetRandom, out: Array[Command]) -> void:
	if memory.squads_max <= WAVE or not memory.has_staging():
		return
	var all_in: bool = _all_in(view)
	if memory.squad_role[WAVE] != AiMemory.NONE:
		_tally(view, memory)
		var retreating: bool = memory.squad_state[WAVE] == AiMemory.SquadState.RETREAT
		if _wave_units > 0 and not retreating:
			_fight(view, memory, out, all_in)
			return
		if _wave_units > 0 and retreating and not all_in and _restage(view, memory, out):
			return
		if _wave_units > 0 and not all_in and _wave_idle < _wave_units:
			return
		_disband(memory)
	_launch(view, memory, rng, out, all_in)


## Whether the all-in tick has come (0: never).
func _all_in(view: PlayerView) -> bool:
	return all_in_tick > 0 and view.tick >= all_in_tick


## Whether the all-in overrides the defence this think: it has come and the wave logic can run (a
## staging point, a base estimate and a second squad), so every combat unit goes to the wave and the
## home squad is not sent to the threat as well.
func _all_in_wave(view: PlayerView, memory: AiMemory) -> bool:
	return (
		_all_in(view)
		and memory.squads_max > WAVE
		and memory.has_staging()
		and memory.has_base_estimate()
	)


## Whether the wave in the field holds the army's goal keys: it marches (not in retreat) and a key
## of the army sits at its goal. The home squad's return and an empty defence must not release them.
func _wave_holds_army(memory: AiMemory) -> bool:
	if (
		memory.squad_role[WAVE] == AiMemory.NONE
		or memory.squad_state[WAVE] != AiMemory.SquadState.WAVE
	):
		return false
	for at: int in memory.goal_keys():
		if (
			memory.goal_owner[at] & (1 << AiMemory.Owner.ARMY) != 0
			and memory.goal_x[at] == memory.squad_goal_x[WAVE]
			and memory.goal_y[at] == memory.squad_goal_y[WAVE]
		):
			return true
	return false


## A wave in the field: pulled back when beaten (never from the all-in tick), else sent to the
## target when that moved, and from the all-in tick joined by every unit of the home squad.
func _fight(view: PlayerView, memory: AiMemory, out: Array[Command], all_in: bool) -> void:
	if not all_in and _pull_back(view, memory, out):
		return
	var focused: bool = focus_fire and _focus(view, memory, out, WAVE)
	var goal: Vector2i = Vector2i(memory.squad_goal_x[WAVE], memory.squad_goal_y[WAVE])
	var target: Vector2i = Vector2i(memory.base_x, memory.base_y)
	var wave: PackedInt32Array = _members(memory, true, WAVE)
	if (
		not focused
		and memory.has_base_estimate()
		and target != goal
		and _order(view, memory, out, wave, target, AiMemory.Owner.ARMY, _at(target))
	):
		goal = target
		memory.squad_goal_x[WAVE] = goal.x
		memory.squad_goal_y[WAVE] = goal.y
	if not all_in:
		return
	var home: PackedInt32Array = _members(memory, true)
	# P196 experiment: reinforcements go in groups, not one by one as each unit spawns.
	if home.size() < REINFORCE_MIN:
		return
	if (
		not home.is_empty()
		and _order(view, memory, out, home, goal, AiMemory.Owner.ARMY, _at(goal))
	):
		_join_wave(memory, true)


## Whether the wave is beaten (its value is under `retreat_percent` of its launch value, or the
## seen enemy value near it passes `retreat_ratio` percent of its own) and so goes home with a
## `MOVE`, asking again next think when that is refused. Or recalled: the seen enemy value near the
## threat at the base passes `retreat_ratio` percent of the home squad's, and the wave disbands
## into the home squad at once (`recalls`, not `retreats`), so the standing defence sends it to the
## threat. True when either happened. The army keys go when the wave held them (judged before the
## state changes).
func _pull_back(view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	var weak: bool = (
		retreat_percent > 0
		and _wave_value * 100 < memory.squad_launch_value[WAVE] * retreat_percent
	)
	if not weak and retreat_ratio > 0:
		weak = _near(view, memory, _wave_at) * 100 > _wave_value * retreat_ratio
		# The recall: a threat at the base that outweighs the home squad calls the wave home, to
		# defend (not a retreat).
		if (
			not weak
			and _threat_on
			and _near(view, memory, _threat_at) * 100 > _home_value * retreat_ratio
		):
			_disband(memory)
			recalls += 1
			# The home goal left at the staging point would make the next slot's defence or return
			# order nothing: the recalled units must get an order.
			if (
				memory.squad_goal_x[HOME] == memory.staging_x
				and memory.squad_goal_y[HOME] == memory.staging_y
			):
				memory.squad_goal_x[HOME] = AiMemory.NONE
				memory.squad_goal_y[HOME] = AiMemory.NONE
			return true
	if not weak:
		return false
	var held: bool = _wave_holds_army(memory)
	var stage: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
	var ids: PackedInt32Array = _members(memory, true, WAVE)
	if _order(view, memory, out, ids, stage, AiMemory.Owner.STAGING, _at(stage)):
		memory.squad_state[WAVE] = AiMemory.SquadState.RETREAT
		memory.squad_goal_x[WAVE] = stage.x
		memory.squad_goal_y[WAVE] = stage.y
		memory.squad_focus[WAVE] = AiMemory.NONE
		retreats += 1
		if held:
			memory.release_owner(AiMemory.Owner.ARMY)
	return true


## The value of the seen enemy combat units and armed, finished buildings within the defence radius
## of `centre`; a row outside the box round the centre costs no test, the others one test each in
## `tests`, which the threat search shares: a fight at the base that used up the cap leaves the
## ratio blind that think.
func _near(view: PlayerView, memory: AiMemory, centre: Vector2i) -> int:
	return (
		_value_in(view, memory.seen_unit_id, centre, false)
		+ _value_in(view, memory.seen_site_id, centre, true)
	)


## The value of the rows of `list` within the defence radius of `centre` (only armed, finished
## buildings when `sites`), one test each past the box, until the cap.
func _value_in(view: PlayerView, list: PackedInt32Array, centre: Vector2i, sites: bool) -> int:
	var found: int = 0
	for id: int in list:
		if tests >= tests_max:
			break
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var gap: Vector2i = view.row_pos(row) - centre
		if absi(gap.x) > defend_radius or absi(gap.y) > defend_radius:
			continue
		if sites and not _armed(view, row):
			continue
		tests += 1
		if gap.x * gap.x + gap.y * gap.y <= defend_radius * defend_radius:
			found += AiIntel.value_of(view, row)
	return found


## Whether the building at `row` is finished (`build_left` 0) and has a weapon.
static func _armed(view: PlayerView, row: int) -> bool:
	var type: int = view.row_type(row)
	return (
		view.row_build_left(row) == 0
		and type >= 0
		and type < view.type_weapon.size()
		and view.type_weapon[type] >= 0
	)


## Launches the next wave when the draw is made, its tick has come, no threat stands at the base
## (this think's: the threat search ran first) and the value of the units that march reaches the
## strength: the home squad but for its withdrawn units goes to the target (`base` of the memory:
## the nearest known producer, else the estimate). The all-in counts and sends every unit. The start
## tick is drawn once per wave, after the first tick or after the last wave ended. From the all-in
## tick the launch ignores the strength, the tick and a standing threat (the all-in overrides the
## defence, `_all_in_wave`).
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
	var ids: PackedInt32Array = _members(memory, true, HOME, not all_in)
	# What marches: the value of the units that go (a withdrawn one goes only in the all-in).
	var value: int = _home_value if all_in else _ready_value
	if ids.is_empty() or (not all_in and value < _strength(memory.wave_count)):
		return
	var goal: Vector2i = Vector2i(memory.base_x, memory.base_y)
	if not _order(view, memory, out, ids, goal, AiMemory.Owner.ARMY, _at(goal)):
		return
	_join_wave(memory, all_in)
	memory.squad_role[WAVE] = ROLE_WAVE
	memory.squad_state[WAVE] = AiMemory.SquadState.WAVE
	memory.squad_launch_value[WAVE] = value
	memory.squad_goal_x[WAVE] = goal.x
	memory.squad_goal_y[WAVE] = goal.y
	memory.squad_focus[WAVE] = AiMemory.NONE
	memory.wave_count += 1
	waves += 1


## The home squad went into the wave, but for a withdrawn unit unless it is the all-in (the units
## that were ordered): the home goal is the staging point (new units gather there by the `RALLY`; a
## shifted or defending goal left behind would make `_return` release the wave's keys), the shift
## is over, the focus is forgotten and no joiner is pending.
func _join_wave(memory: AiMemory, all_in: bool) -> void:
	for at: int in memory.member_squad.size():
		if (
			memory.member_squad[at] == HOME
			and (all_in or not _withdrawn(memory, memory.member_id[at]))
		):
			memory.member_squad[at] = WAVE
	memory.squad_goal_x[HOME] = memory.staging_x
	memory.squad_goal_y[HOME] = memory.staging_y
	memory.home_shifted = 0
	memory.squad_focus[HOME] = AiMemory.NONE
	_fresh.clear()


## The value a wave needs: the first strength, grown by the growth percent once per wave launched.
func _strength(launched: int) -> int:
	var strength: int = wave_first_strength
	for _wave_no: int in launched:
		@warning_ignore("integer_division")
		strength = strength * (100 + wave_growth) / 100
	return strength


## The wave squad is over (all dead, or home and rejoined): its units join the home squad, as
## pending joiners (a standing defence sends them), and the next start tick is drawn again. The
## army keys go when the wave held them (judged before the state changes).
func _disband(memory: AiMemory) -> void:
	var held: bool = _wave_holds_army(memory)
	for at: int in memory.member_squad.size():
		if memory.member_squad[at] == WAVE:
			_fresh.append(memory.member_id[at])
	_fresh.sort()
	_assign(memory, WAVE, HOME)
	memory.squad_role[WAVE] = AiMemory.NONE
	memory.squad_state[WAVE] = AiMemory.SquadState.HOME
	memory.squad_launch_value[WAVE] = 0
	memory.squad_goal_x[WAVE] = AiMemory.NONE
	memory.squad_goal_y[WAVE] = AiMemory.NONE
	memory.squad_focus[WAVE] = AiMemory.NONE
	memory.wave_start_tick = AiMemory.NONE
	if held:
		memory.release_owner(AiMemory.Owner.ARMY)


## While the wave walks home the staging point may move: the `MOVE` goes to the new point (again
## next think when refused). True while the wave's goal is not the staging point.
func _restage(view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	var stage: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
	if memory.squad_goal_x[WAVE] == stage.x and memory.squad_goal_y[WAVE] == stage.y:
		return false
	var ids: PackedInt32Array = _members(memory, true, WAVE)
	if _order(view, memory, out, ids, stage, AiMemory.Owner.STAGING, _at(stage)):
		memory.squad_goal_x[WAVE] = stage.x
		memory.squad_goal_y[WAVE] = stage.y
	return true


## Sums the home squad's value (`_home_value`, and `_ready_value` without the withdrawn units) and
## the wave's value, and the wave's centre, units and idle units, over
## the members (a loop over the memory's list, not the view's rows).
func _tally(view: PlayerView, memory: AiMemory) -> void:
	_home_value = 0
	_ready_value = 0
	_wave_value = 0
	_wave_units = 0
	_wave_idle = 0
	var sum: Vector2i = Vector2i.ZERO
	for at: int in memory.member_id.size():
		var row: int = view.row_of(memory.member_id[at])
		if row < 0:
			continue
		if memory.member_squad[at] == HOME:
			var value: int = AiIntel.value_of(view, row)
			_home_value += value
			if not _withdrawn(memory, memory.member_id[at]):
				_ready_value += value
		elif memory.member_squad[at] == WAVE:
			_wave_value += AiIntel.value_of(view, row)
			_wave_units += 1
			sum += view.row_pos(row)
			if view.row_order(row) == PlayerView.Order.IDLE:
				_wave_idle += 1
	if _wave_units > 0:
		@warning_ignore("integer_division")
		_wave_at = sum / _wave_units


## Moves every member of squad `from` to squad `to`.
func _assign(memory: AiMemory, from: int, to: int) -> void:
	for at: int in memory.member_squad.size():
		if memory.member_squad[at] == from:
			memory.member_squad[at] = to


## The centre of `tile` in milli-tiles.
static func _at(tile: Vector2i) -> Vector2i:
	return tile * PlayerView.MILLI_PER_TILE + Vector2i.ONE * PlayerView.TILE_CENTRE


## Hard's step-back: an own combat unit under `unit_retreat_hp` percent of its type's hp that has
## not stepped back yet goes to the staging point with one `MOVE` (no fire on the way) and leaves
## its squad for the home squad. It is then left out of wave launches and joins only: it still takes
## the defence, the focus, the return, the shift order and the all-in. The sim has no healing, so it
## stays withdrawn until it dies. All or nothing: when the order is refused the units are asked
## again next think. No order from the all-in tick (no retreat then; the all-in takes the unit
## anyway). Walks the memory's unit list, no pass.
func _step_back(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if unit_retreat_hp == 0:
		return
	_low.clear()
	_kept.clear()
	for at: int in memory.unit_id.size():
		var id: int = memory.unit_id[at]
		var max_hp: int = view.type_max_hp[view.row_type(view.row_of(id))]
		if max_hp <= 0 or memory.unit_hp[at] * 100 >= max_hp * unit_retreat_hp:
			continue
		if _withdrawn(memory, id):
			_kept.append(id)
		else:
			_low.append(id)
	if not _low.is_empty() and memory.has_staging() and not _all_in_wave(view, memory):
		var stage: Vector2i = Vector2i(memory.staging_x, memory.staging_y)
		if _order(view, memory, out, _low, stage, AiMemory.Owner.STAGING, _at(stage)):
			for id: int in _low:
				memory.member_squad[memory.member_id.bsearch(id)] = HOME
			_kept.append_array(_low)
			_kept.sort()
			stepbacks += _low.size()
	var old: PackedInt32Array = memory.withdrawn_id
	memory.withdrawn_id = _kept
	_kept = old


## Whether unit `id` stepped back and is still under the percent (the memory's list).
func _withdrawn(memory: AiMemory, id: int) -> bool:
	var at: int = memory.withdrawn_id.bsearch(id)
	return at < memory.withdrawn_id.size() and memory.withdrawn_id[at] == id


## Hard's focus fire for `squad`: the weakest seen enemy combat unit (fewest hp, the lowest id on a
## tie) within the defence radius of the group's centre, at most `tests_max` tests a run (shared
## with the threat search). The group gets one `ATTACK` on it when it is a new target (the home
## squad also when a unit joined since); the target's tile is the squad's goal and the army goal.
## The key books the target's tile at order time: the sim re-keys each unit's `ATTACK` field toward
## the moving target, so for a few ticks two cells may be live while the books hold the order-time
## tile. The tests share the cap with the reads that ran first (see `tests`); a search the cap cut
## off before any candidate keeps a living target as the candidate (a joiner still gets the order).
## True while a target is in reach (sent, held or refused: the group's own order waits), false when
## none is, which also forgets the old target.
func _focus(view: PlayerView, memory: AiMemory, out: Array[Command], squad: int) -> bool:
	_capped = false
	var sum: Vector2i = Vector2i.ZERO
	var members: PackedInt32Array = _members(memory, true, squad)
	for id: int in members:
		sum += view.row_pos(view.row_of(id))
	var best: int = -1
	if not members.is_empty():
		@warning_ignore("integer_division")
		best = _weakest(view, memory, sum / members.size())
	var kept: int = memory.squad_focus[squad]
	if best < 0 and _capped and kept != AiMemory.NONE:
		best = view.row_of(kept)
	if best < 0:
		memory.squad_focus[squad] = AiMemory.NONE
		return false
	var target: int = view.row_id(best)
	# `_fresh` holds home joiners only.
	var pending: bool = squad == HOME and not _fresh.is_empty()
	if target == memory.squad_focus[squad] and not pending:
		return true
	var tile: Vector2i = view.row_pos(best) / PlayerView.MILLI_PER_TILE
	if not _order(view, memory, out, members, tile, AiMemory.Owner.ARMY, _at(tile), target):
		return true
	memory.squad_focus[squad] = target
	memory.squad_goal_x[squad] = tile.x
	memory.squad_goal_y[squad] = tile.y
	if squad == HOME:
		memory.home_shifted = 0
		_fresh.clear()
	focuses += 1
	return true


## The row of the weakest seen enemy combat unit within the defence radius of `centre`, -1 for none.
func _weakest(view: PlayerView, memory: AiMemory, centre: Vector2i) -> int:
	var found: int = -1
	var least: int = 0
	for id: int in memory.seen_unit_id:
		if tests >= tests_max:
			_capped = true
			break
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var gap: Vector2i = view.row_pos(row) - centre
		if absi(gap.x) > defend_radius or absi(gap.y) > defend_radius:
			continue
		tests += 1
		if gap.x * gap.x + gap.y * gap.y > defend_radius * defend_radius:
			continue
		if found < 0 or view.row_hp(row) < least:
			found = row
			least = view.row_hp(row)
	return found
