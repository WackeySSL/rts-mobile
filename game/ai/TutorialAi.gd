class_name TutorialAi
extends AiController
## The scripted tutorial opponent (ADR 0044 section 2, plan row P540). It plays the steps of a
## `TutorialScriptDef` and nothing else: no economy, no defence of its own. It reads the match only
## through the `PlayerView` of the think (a trigger sees only own and seen rows), answers with
## Commands, draws no random number (`rng` is kept for the contract) and keeps no Resource: the
## steps are copied into ints and arrays when it is made.
##
## One think: each step that has not fired, in order, is tried. A step is due when the step it
## names in `after_step` has fired and its delay has passed (an `after_step` that names no step of
## the script is an error and the step never fires); it then fires when its trigger holds and its
## action could be sent. An order step (ATTACK_MOVE, MOVE) waits for a unit to send and a
## destination, a STOP for a unit. A QUEUE step sends its items as its queue has room, the credits
## last (one budget and one per-tab count are carried across all steps of a think, so no think
## sends a Command the sim refuses for room or credits) and fires only when the view shows its items
## queued or built: it counts the player's rows of the type plus its queued items, from the count at
## the think its trigger first held, and sends the rest again on each later think until they are
## seen. So two QUEUE steps of one type count the items of the steps before them in the script as
## their own baseline and the later ones' as theirs: put such steps in script order, or chain them
## with `after_step`. A fired step never fires again. Same views in, same Commands out.
##
## For the director (P541, P543): `step_count()`, `step_ids()`, `has_fired(id)`, `fired_tick_of(id)`
## and `fired_count()` tell which steps have played. A step's tick is the tick T of the view of the
## think that fired it; the Commands of that think are applied on T + 1 (a QUEUE step's tick is the
## think that SAW its items, a think after the one that sent them). The fields are plain ints
## written inside the think, which in WORKER mode runs on the tick job's thread: the main thread
## reads the controller only after `MatchRunner.wait_idle()` (ADR 0038 section 2), never while a
## job runs.

## The tick of a step that has not fired.
const NOT_FIRED: int = -1
## A type filter that names no type of the roster: nothing matches it.
const ABSENT: int = -2
## The `_after` of a step that waits for a step the script lacks: it never fires.
const NEVER: int = -2

## Items the player's rows and queues hold, per type, at the think where the step's trigger first
## held (-1 before): a QUEUE step's baseline.
var _base: PackedInt32Array = PackedInt32Array()
var _step_ids: Array[StringName] = []
var _step_count: int = 0

var _trigger: PackedInt32Array = PackedInt32Array()
var _trigger_type: Array[StringName] = []
## The beat each step's `BEAT` trigger waits for, the beats that were noted and the tick each was.
var _trigger_beat: Array[StringName] = []
var _noted_ids: Array[StringName] = []
var _noted_at: PackedInt32Array = PackedInt32Array()
var _threshold: PackedInt32Array = PackedInt32Array()
var _radius: PackedInt32Array = PackedInt32Array()
var _action: PackedInt32Array = PackedInt32Array()
var _action_type: Array[StringName] = []
var _count: PackedInt32Array = PackedInt32Array()
var _target: PackedInt32Array = PackedInt32Array()
var _tile: PackedInt32Array = PackedInt32Array()
## Index of the step each step waits for (-1 none) and its delay in ticks.
var _after: PackedInt32Array = PackedInt32Array()
var _delay: PackedInt32Array = PackedInt32Array()
## The tick each step fired at.
var _fired: PackedInt32Array = PackedInt32Array()
var _hq_id: StringName = &""

## Read off the view by one think and used only inside it: the player's rows per type, its
## complete producers per tab, rows plus queued items per type, the credits not yet spent by a
## QUEUE of this think and the items this think added per tab, the centres of its buildings
## (milli-tiles), the one orders go "home" to, and the first seen row that made the step being tried
## hold (-1 none).
var _owned: PackedInt32Array = PackedInt32Array()
var _producers: PackedInt32Array = PackedInt32Array()
var _complete: PackedInt32Array = PackedInt32Array()
var _have: PackedInt32Array = PackedInt32Array()
var _added: PackedInt32Array = PackedInt32Array()
var _budget: int = 0
var _xs: PackedInt32Array = PackedInt32Array()
var _ys: PackedInt32Array = PackedInt32Array()
var _home: Vector2i = Vector2i(-1, -1)
var _hit: int = -1

## A scripted opponent for `player_id` playing `def`, which it copies and does not keep. It thinks
## on the dummy's schedule: `think_period` and `think_tick` (player 2's, each later player one tick
## after it, ADR 0020 section 2).
@warning_ignore("shadowed_variable")
static func create(def: TutorialScriptDef, player_id: int, rng: DetRandom) -> TutorialAi:
	var ai: TutorialAi = TutorialAi.new()
	ai.player_id = player_id
	ai.rng = rng
	ai.think_period = maxi(def.think_period, 1)
	ai.think_offset = posmod(-(def.think_tick + player_id - 2), ai.think_period)
	ai._hq_id = def.hq_type
	for step: TutorialStepDef in def.steps:
		ai._step_ids.append(step.id)
		ai._trigger.append(step.trigger)
		ai._trigger_type.append(step.trigger_type)
		ai._trigger_beat.append(step.trigger_beat)
		ai._threshold.append(step.threshold)
		ai._radius.append(maxi(step.trigger_radius_tiles, 0) * PlayerView.MILLI_PER_TILE)
		ai._action.append(step.action)
		ai._action_type.append(step.action_type)
		ai._count.append(maxi(step.count, 0))
		ai._target.append(step.target)
		ai._tile.append(step.target_tile.x)
		ai._tile.append(step.target_tile.y)
		ai._delay.append(maxi(step.delay_ticks, 0))
	ai._step_count = ai._step_ids.size()
	for step: TutorialStepDef in def.steps:
		ai._after.append(ai._resolve_after(step))
	ai._fired.resize(ai._step_count)
	ai._fired.fill(NOT_FIRED)
	ai._base.resize(ai._step_count)
	ai._base.fill(-1)
	return ai


## The index of the step `step` waits for: -1 for none, NEVER for a name that no step of the script
## has (a push_warning, not an error: verify fails on any ERROR line).
func _resolve_after(step: TutorialStepDef) -> int:
	if step.after_step == &"":
		return -1
	var found: int = _step_ids.find(step.after_step)
	if found < 0:
		push_warning(
			"TutorialAi: step %s waits for %s, which is no step" % [step.id, step.after_step]
		)
		return NEVER
	return found


## How many steps the script has.
func step_count() -> int:
	return _step_count


## The step ids in script order (a copy).
func step_ids() -> Array[StringName]:
	return _step_ids.duplicate()


## Whether the step `id` has fired.
func has_fired(id: StringName) -> bool:
	return fired_tick_of(id) != NOT_FIRED


## The tick the step `id` fired at, NOT_FIRED for a step that has not (or that the script lacks).
func fired_tick_of(id: StringName) -> int:
	var index: int = _step_ids.find(id)
	return _fired[index] if index >= 0 else NOT_FIRED


## How many steps have fired.
func fired_count() -> int:
	var total: int = 0
	for tick: int in _fired:
		if tick != NOT_FIRED:
			total += 1
	return total


## The director's word that the lesson's beat `id` was done at match tick `tick` (the published
## tick it saw it on). The one way progress of the player's lesson reaches the script, and it is
## data, never the UI: a `BEAT` step fires `threshold` ticks after it, on the think that sees the
## view's tick that far on. Called only by the main thread after `MatchRunner.wait_idle()` (the
## same window in which it reads `has_fired`), so the AI thread is not thinking. A beat is noted
## once and only when a step waits for it. The firing tick is a function of `tick` and the
## think grid, so a run with the same beat ticks gives the same Commands.
func note_beat(id: StringName, tick: int) -> void:
	if _noted_ids.has(id) or not _trigger_beat.has(id):
		return
	_noted_ids.append(id)
	_noted_at.append(tick)


func think(view: PlayerView, out: Array[Command]) -> void:
	var before: int = out.size()
	work = 1
	if _take_census(view):
		for index: int in _step_count:
			if _fired[index] == NOT_FIRED and _due(index, view.tick):
				_try(index, view, out)
	commands += out.size() - before
	work_max = maxi(work_max, work)


## Reads the player's rows. False when the view has no queues (nothing to act with).
func _take_census(view: PlayerView) -> bool:
	if view.queue_count.size() < PlayerView.TABS:
		return false
	var hq_type: int = view.type_index_of(_hq_id)
	_owned = PackedInt32Array()
	_owned.resize(view.type_cost.size())
	_complete = PackedInt32Array()
	_complete.resize(view.type_cost.size())
	_producers = PackedInt32Array()
	_producers.resize(PlayerView.TABS)
	_added = PackedInt32Array()
	_added.resize(PlayerView.TABS)
	_budget = view.credits
	_xs = PackedInt32Array()
	_ys = PackedInt32Array()
	_home = Vector2i(-1, -1)
	var home_is_hq: bool = false
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		_owned[type] += 1
		var tab: int = view.type_produces[type]
		if view.row_build_left(row) == 0:
			_complete[type] += 1
			if tab >= 0 and tab < PlayerView.TABS:
				_producers[tab] += 1
		if view.type_foot_w[type] > 0:
			var at: Vector2i = view.row_pos(row)
			_xs.append(at.x)
			_ys.append(at.y)
			if not home_is_hq and (_home.x < 0 or type == hq_type):
				_home = at
				home_is_hq = type == hq_type
	_have = _owned.duplicate()
	for tab: int in PlayerView.TABS:
		for slot: int in view.queue_count[tab]:
			_have[view.queue_type[tab * view.queue_slots + slot]] += 1
	work += 1
	return true


## Whether the step's `after_step` has fired and its delay passed at `tick`.
func _due(index: int, tick: int) -> bool:
	var base: int = 0
	if _after[index] == NEVER:
		return false
	if _after[index] >= 0:
		base = _fired[_after[index]]
		if base == NOT_FIRED:
			return false
	return tick >= base + _delay[index]


## Tests the trigger of the step and, when it holds, sends its action; marks it fired once done.
func _try(index: int, view: PlayerView, out: Array[Command]) -> void:
	_hit = -1
	if not _holds(index, view):
		return
	if _action[index] == TutorialStepDef.Action.QUEUE:
		_try_queue(index, view, out)
		return
	var units: PackedInt32Array = _units(index, view)
	var dest: Vector2i = _destination(index, view)
	var stop: bool = _action[index] == TutorialStepDef.Action.STOP
	if units.is_empty() or (dest.x < 0 and not stop):
		return
	for first: int in range(0, units.size(), Command.MAX_UNITS):
		var ids: PackedInt32Array = units.slice(first, first + Command.MAX_UNITS)
		out.append(_order(index, ids, dest))
	_fired[index] = view.tick


func _order(index: int, ids: PackedInt32Array, dest: Vector2i) -> Command:
	match _action[index]:
		TutorialStepDef.Action.MOVE:
			return Command.move(player_id, ids, dest.x, dest.y)
		TutorialStepDef.Action.STOP:
			return Command.stop(player_id, ids)
		_:
			return Command.attack_move(player_id, ids, dest.x, dest.y)


## Whether the trigger of the step holds, on the player's own rows and the rows it sees only.
func _holds(index: int, view: PlayerView) -> bool:
	var need: int = _threshold[index]
	var type: int = _type_of(_trigger_type[index], view)
	var holds: bool = false
	match _trigger[index]:
		TutorialStepDef.Trigger.TICK:
			holds = view.tick >= need
		TutorialStepDef.Trigger.CREDITS:
			holds = view.credits >= need
		TutorialStepDef.Trigger.BEAT:
			var noted: int = _noted_ids.find(_trigger_beat[index])
			holds = noted >= 0 and view.tick >= _noted_at[noted] + need
		TutorialStepDef.Trigger.OWN_AT_LEAST:
			holds = _own_count(type) >= need
		TutorialStepDef.Trigger.OWN_AT_MOST:
			holds = _own_count(type) <= need
		TutorialStepDef.Trigger.ENEMY_SEEN:
			holds = _enemies(view, type, -1) >= need
		_:
			holds = _enemies(view, type, _radius[index]) >= need
	return holds


## The type index of `id`, MISSING (-1) for any type when `id` is empty, ABSENT when the roster
## lacks it.
func _type_of(id: StringName, view: PlayerView) -> int:
	if id == &"":
		return PlayerView.MISSING
	var type: int = view.type_index_of(id)
	return type if type != PlayerView.MISSING else ABSENT


## Rows the player owns of `type` (all when MISSING, none when ABSENT).
func _own_count(type: int) -> int:
	if type == ABSENT:
		return 0
	if type == PlayerView.MISSING:
		var total: int = 0
		for count: int in _owned:
			total += count
		return total
	return _owned[type]


## Seen rows of other, non-neutral owners of `type` (any when MISSING) within `radius` milli-tiles
## of one of the player's buildings (anywhere when `radius` is -1). Sets `_hit` to the first.
func _enemies(view: PlayerView, type: int, radius: int) -> int:
	if type == ABSENT:
		return 0
	var found: int = 0
	for row: int in view.seen_rows:
		if view.row_owner(row) < 1 or (type != PlayerView.MISSING and view.row_type(row) != type):
			continue
		if radius >= 0 and not _near(view.row_pos(row), radius):
			continue
		if found == 0:
			_hit = row
		found += 1
	work += 1
	return found


func _near(at: Vector2i, radius: int) -> bool:
	for building: int in _xs.size():
		var dx: int = at.x - _xs[building]
		var dy: int = at.y - _ys[building]
		if dx * dx + dy * dy <= radius * radius:
			return true
	return false


## A QUEUE step whose trigger holds: fires when the view shows `count` more items of the type (rows
## and queued) than at its first think, else sends the rest that can be queued now.
func _try_queue(index: int, view: PlayerView, out: Array[Command]) -> void:
	var type: int = _type_of(_action_type[index], view)
	if type < 0 or view.type_tab[type] < 0:
		return
	if _base[index] < 0:
		_base[index] = _have[type]
	var left: int = maxi(_count[index], 1) - (_have[type] - _base[index])
	if left <= 0:
		_fired[index] = view.tick
		return
	var tab: int = view.type_tab[type]
	while left > 0 and _can_queue(view, type, tab) and view.type_cost[type] <= _budget:
		_budget -= view.type_cost[type]
		_added[tab] += 1
		_have[type] += 1
		out.append(Command.queue(player_id, type))
		left -= 1


## Whether a QUEUE of `type` would be applied but for the credits: its tab has a producer of the
## player's (complete) and room for the items queued so far, this think's included, and a complete
## row of the type's requirement is owned. The sim also asks the producer's faction, the pad cap and
## research already owned or queued: a refused item is not seen next think and is sent again.
func _can_queue(view: PlayerView, type: int, tab: int) -> bool:
	if tab >= PlayerView.TABS or _producers[tab] == 0:
		return false
	if view.queue_count[tab] + _added[tab] >= view.queue_slots:
		return false
	var need: int = view.type_requires[type]
	return need < 0 or _complete[need] > 0


## The combat units (ids ascending) the step orders, the `count` lowest when `count` is set.
func _units(index: int, view: PlayerView) -> PackedInt32Array:
	var type: int = _type_of(_action_type[index], view)
	var ids: PackedInt32Array = PackedInt32Array()
	if type == ABSENT:
		return ids
	for row: int in view.own_rows:
		var kind: int = view.row_type(row)
		if view.type_foot_w[kind] > 0 or not DummyDefence.is_combat(view, kind):
			continue
		if type == PlayerView.MISSING or kind == type:
			ids.append(view.row_id(row))
	ids.sort()
	var cap: int = _count[index]
	return ids.slice(0, cap) if cap > 0 and ids.size() > cap else ids


## Where the step's order goes in milli-tiles, (-1, -1) when it has no place to go.
func _destination(index: int, view: PlayerView) -> Vector2i:
	var offset: Vector2i = Vector2i(_tile[index * 2], _tile[index * 2 + 1])
	offset *= PlayerView.MILLI_PER_TILE
	match _target[index]:
		TutorialStepDef.Target.TILE:
			return offset + Vector2i(PlayerView.TILE_CENTRE, PlayerView.TILE_CENTRE)
		TutorialStepDef.Target.TRIGGER:
			if _hit >= 0:
				return view.row_pos(_hit)
	return _home + offset if _home.x >= 0 else Vector2i(-1, -1)
