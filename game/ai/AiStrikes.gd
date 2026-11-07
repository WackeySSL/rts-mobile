class_name AiStrikes
extends RefCounted
## The opponent's superweapon manager (ADR 0030 sections 1, 4 and 6, plan row P181), slot INTEL
## after `AiIntel.run`. It sends at most one `SUPERWEAPON` a think, from the own strike building of
## the def's `strike_type`, and only when the sim would take it: the level uses strikes, no own
## rupture is pending (`own_strike_tick`; a blackout never sets it, and nothing may follow a
## rupture), the building is complete, charged and not blacked out, and the think has budget
## (`can_send` first, then `spent`; a Command that is not sent changes nothing in the memory).
##
## A Deep Bore (rupture) fires on the point of the most enemy value within its radius that holds no
## own row, once that value is not below `strike_min_value`. A Dusk Array (blackout) fires once per
## wave, on the enemy producers' densest cluster, while the wave is in the field. The two are told
## apart by the view's `type_strike_kind`, not by a name. Both read only what the AI may know: the
## seen enemy buildings and units that `AiIntel.refresh` listed, and the ghosts. A thing counts once
## its type's first sighting is `reaction_ticks` old. The sector map is read first (an enemy that
## totals under the minimum cannot make a shot); then at most `target_tests_max` (anchor, thing)
## tests a run, the anchors being the things of most value when they are too many to test all.
##
## No pass over the view's rows: the own buildings and units are the lists `refresh` filled in the
## ARMY slot (`site_*`, `unit_id`, `aux_id`), found again by id, so the INTEL slot's `work` stays 3.
## Those lists are one slot (5 ticks) old: a row made since is not in the own-row check. The ghosts
## are walked, as intel does, and are not a pass over rows. No random number is drawn.

## `type_strike_kind` values (`Strike.Kind`; a test pins them equal).
const RUPTURE: int = 1
const BLACKOUT: int = 2
const _NONE: Vector2i = Vector2i(-1, -1)

## Passes over the view's rows (always 0), the (anchor, thing) tests of the last run, and the
## shots sent over the match.
var passes: int = 0
var tests: int = 0
var strikes: int = 0

var _uses: bool = false
var _strike_id: StringName = &""
var _min_value: int = 0
var _tests_max: int = 0
var _reaction: int = 0
## The strike type as an index of the view's roster, found on the first run (-2: not yet).
var _type: int = -2
## Scratch kept between runs: the things of a search (milli-tiles, credits) and the anchors' marks.
var _x: PackedInt32Array = PackedInt32Array()
var _y: PackedInt32Array = PackedInt32Array()
var _value: PackedInt32Array = PackedInt32Array()
var _used: PackedByteArray = PackedByteArray()


## A manager that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef, _player_id: int) -> AiStrikes:
	var strike: AiStrikes = AiStrikes.new()
	strike._uses = level.uses_strike != 0
	strike._strike_id = def.strike_type
	strike._min_value = maxi(def.strike_min_value, 0)
	strike._tests_max = maxi(def.target_tests_max, 1)
	strike._reaction = maxi(level.reaction_ticks, 0)
	return strike


func run(view: PlayerView, memory: AiMemory, _rng: DetRandom, out: Array[Command]) -> void:
	passes = 0
	tests = 0
	if not _uses or view.own_strike_tick != 0 or not memory.can_send():
		return
	if _type == -2:
		_type = view.type_index_of(_strike_id)
	if _type < 0 or _type >= view.type_strike_kind.size():
		return
	var kind: int = view.type_strike_kind[_type]
	if kind == BLACKOUT and not _wave_in_field(memory):
		return
	var building: int = _ready(view, memory)
	if building == AiMemory.NONE:
		return
	var radius: int = view.type_strike_radius[_type]
	var at: Vector2i = _NONE
	if kind == RUPTURE:
		at = _bore_point(view, memory, radius)
	elif kind == BLACKOUT:
		at = _cluster_point(view, memory, radius)
	if at == _NONE:
		return
	out.append(Command.superweapon(view.player, building, at.x, at.y))
	memory.spent()
	strikes += 1
	if kind == BLACKOUT:
		memory.strike_wave = memory.wave_count


## Whether a wave is in the field that the Dusk Array has not yet answered.
func _wave_in_field(memory: AiMemory) -> bool:
	return (
		memory.squads_max > AiArmy.WAVE
		and memory.squad_state[AiArmy.WAVE] == AiMemory.SquadState.WAVE
		and memory.wave_count > memory.strike_wave
	)


## The id of the lowest own strike building that is complete, charged and online now (the sim's
## test, with the stamp `tick + 1`), NONE for none.
func _ready(view: PlayerView, memory: AiMemory) -> int:
	var stamp: int = view.tick + 1
	for id: int in memory.site_id:
		var row: int = view.row_of(id)
		if row < 0 or view.row_type(row) != _type or view.row_build_left(row) != 0:
			continue
		if stamp >= view.row_ready_tick(row) and view.row_offline_until(row) <= stamp:
			return id
	return AiMemory.NONE


## The Deep Bore's point: the thing whose radius holds the most enemy value, with no own row in it
## and not below the minimum; `_NONE` for none.
func _bore_point(view: PlayerView, memory: AiMemory, radius: int) -> Vector2i:
	var total: int = 0
	for value: int in memory.sector_enemy:
		total += value
	if total < _min_value:
		return _NONE
	_gather(view, memory, false)
	return _best(view, memory, radius, _min_value, true)


## The Dusk Array's point: the enemy producer whose radius holds the most producer value.
func _cluster_point(view: PlayerView, memory: AiMemory, radius: int) -> Vector2i:
	_gather(view, memory, true)
	return _best(view, memory, radius, 1, false)


## Fills the scratch with the enemy things the AI may act on: the seen buildings, then (unless
## `producers_only`) the seen combat units, then the remembered buildings, ids ascending inside each
## group, at most `_tests_max` of them.
func _gather(view: PlayerView, memory: AiMemory, producers_only: bool) -> void:
	_x.clear()
	_y.clear()
	_value.clear()
	for id: int in memory.seen_site_id:
		_take(view, memory, view.row_of(id), producers_only)
	if not producers_only:
		for id: int in memory.seen_unit_id:
			_take(view, memory, view.row_of(id), false)
	for record: int in view.ghost_count:
		if _x.size() >= _tests_max:
			return
		var type: int = view.ghost_type[record]
		if view.ghost_owner[record] <= 0 or view.ghost_owner[record] == view.player:
			continue
		if view.row_of(view.ghost_id[record]) >= 0 or not _known(view, memory, type):
			continue
		if producers_only and not _produces(view, type):
			continue
		var pos: Vector2i = view.ghost_pos(record)
		_add(pos.x, pos.y, view.type_cost[type])


func _take(view: PlayerView, memory: AiMemory, row: int, producers_only: bool) -> void:
	if row < 0 or _x.size() >= _tests_max:
		return
	var type: int = view.row_type(row)
	if view.row_owner(row) <= 0 or view.row_owner(row) == view.player:
		return
	if not _known(view, memory, type) or (producers_only and not _produces(view, type)):
		return
	var pos: Vector2i = view.row_pos(row)
	_add(pos.x, pos.y, AiIntel.value_of(view, row))


func _add(x: int, y: int, value: int) -> void:
	_x.append(x)
	_y.append(y)
	_value.append(value)


## The best anchor among the scratch: the thing whose `radius` holds the largest sum of value, not
## below `least` (at least 1) and, with `own_free`, with none of the own rows inside. The anchors
## are all the things when n * n fits the tests, else the `tests_max / n` of most value (an equal
## value goes to the earlier thing). A tie in the sum goes to the earlier anchor tested.
func _best(view: PlayerView, memory: AiMemory, radius: int, least: int, own_free: bool) -> Vector2i:
	var count: int = _x.size()
	if count == 0:
		return _NONE
	var anchors: int = clampi(_tests_max / count, 1, count)
	_used.resize(count)
	_used.fill(0)
	var reach: int = radius * radius
	var best_sum: int = maxi(least, 1) - 1
	var best: Vector2i = _NONE
	for _round: int in anchors:
		var anchor: int = _next_anchor(count)
		_used[anchor] = 1
		var sum: int = 0
		for other: int in count:
			tests += 1
			var dx: int = _x[other] - _x[anchor]
			var dy: int = _y[other] - _y[anchor]
			if dx * dx + dy * dy <= reach:
				sum += _value[other]
		if sum > best_sum and (not own_free or _clear(view, memory, anchor, reach)):
			best_sum = sum
			best = Vector2i(_x[anchor], _y[anchor])
	return best


## The unused thing of most value (the earliest on a tie).
func _next_anchor(count: int) -> int:
	var found: int = -1
	for thing: int in count:
		if _used[thing] == 0 and (found < 0 or _value[thing] > _value[found]):
			found = thing
	return found


## Whether no own building or unit lies within `reach` (squared milli-tiles) of the anchor.
func _clear(view: PlayerView, memory: AiMemory, anchor: int, reach: int) -> bool:
	for at: int in memory.site_x.size():
		if _near(memory.site_x[at], memory.site_y[at], anchor, reach):
			return false
	for list: PackedInt32Array in [memory.unit_id, memory.aux_id]:
		for id: int in list:
			var row: int = view.row_of(id)
			if row >= 0:
				var pos: Vector2i = view.row_pos(row)
				if _near(pos.x, pos.y, anchor, reach):
					return false
	return true


func _near(x: int, y: int, anchor: int, reach: int) -> bool:
	var dx: int = x - _x[anchor]
	var dy: int = y - _y[anchor]
	return dx * dx + dy * dy <= reach


## Whether the type's first sighting is `reaction_ticks` old (ADR 0030 section 2).
func _known(view: PlayerView, memory: AiMemory, type: int) -> bool:
	if type < 0 or type >= memory.seen_first_tick.size():
		return false
	var first: int = memory.seen_first_tick[type]
	return first != AiMemory.NONE and view.tick - first >= _reaction


## Whether the type is a building with a queue.
static func _produces(view: PlayerView, type: int) -> bool:
	var tab: int = (
		view.type_produces[type] if type >= 0 and type < view.type_produces.size() else -1
	)
	return tab >= 0 and tab < PlayerView.TABS
