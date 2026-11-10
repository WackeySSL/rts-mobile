class_name AiStrikes
extends RefCounted
## The opponent's superweapon manager (ADR 0030 sections 1, 4 and 6, plan row P181), slot INTEL
## after `AiIntel.run`. It sends at most one `SUPERWEAPON` a think, from the own strike building of
## the def's `strike_type`, and only when the sim would take it: the level uses strikes, no own
## rupture is pending (`own_strike_tick`; the sim drops a second SUPERWEAPON while the player's
## rupture is pending), the building is complete, charged and not blacked out, and the think has
## budget (`can_send` first, then `spent`; a Command not sent changes nothing in the memory).
##
## A Deep Bore (rupture) fires on the point of the most enemy value within its radius that holds no
## own row and no live army goal (the wave's goal while a wave is in the field, the home goal while
## a threat stands, or the staging point when a recall has just cleared that goal: the army is
## walking there and the shot lands 45 ticks later), once that value is not below
## `strike_min_value`. A Dusk Array (blackout) fires once per wave, while the wave has a live
## member, on the producer cluster of most value, preferring the producers within reach of
## the wave's goal. The two are told apart by the view's `type_strike_kind`, not by a name. Both
## read only what the AI may know: the seen enemy buildings, combat units and other units (tankers)
## that `AiIntel` listed, and the ghosts. A thing counts once its type's first sighting is
## `reaction_ticks` old.
##
## The search (ADR 0030 section 4: sectors first, then rows). The Deep Bore reads the sector map
## first: an enemy that totals under the minimum cannot make a shot. The things are the first
## `target_tests_max` of the lists in id order (seen buildings, units, other units, ghosts); the
## anchors are ranked by their sector's enemy value, then by their own value, the earlier thing
## first. Each anchor in turn is skipped when an own row or army goal holds its radius (one counted
## test per such row, taken from the own rows inside the things' box grown by the radius, which is
## a pre-filter and not counted), else its radius is summed (one counted test per thing). The run
## stops when the next step would pass `target_tests_max`: a check cut off by the cap is not clear.
##
## No pass over the view's rows: the own buildings, the seen buildings and the seen combat units
## are lists `refresh` filled in the ARMY slot (one slot old), the own units and the seen tankers
## lists `AiIntel.run` filled in this very slot, all found again by id. The ghosts are walked,
## as intel does, and are not a pass over rows. No random number is drawn.

## `type_strike_kind` values (`Strike.Kind`; a test pins them equal).
const RUPTURE: int = 1
const BLACKOUT: int = 2
const _NONE: Vector2i = Vector2i(-1, -1)
## The anchor sort key: the thing's index in the low bits (inverted, so the earlier thing sorts
## higher), its value above them and its sector's value on top; at most 4,095 things.
const _THING_BITS: int = 12
const _THING_MASK: int = (1 << _THING_BITS) - 1
const _THINGS_MAX: int = _THING_MASK
const _VALUE_BITS: int = 16
const _VALUE_MASK: int = (1 << _VALUE_BITS) - 1
const _SECTOR_SHIFT: int = _THING_BITS + _VALUE_BITS
const _SECTOR_MASK: int = (1 << 24) - 1

## Passes over the view's rows (always 0), the counted tests of the last run, and the shots sent
## over the match.
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
## Scratch kept between runs: the things of a search (milli-tiles, credits), the anchors' sort keys
## and the own rows and goals that could hold an anchor's radius.
var _x: PackedInt32Array = PackedInt32Array()
var _y: PackedInt32Array = PackedInt32Array()
var _value: PackedInt32Array = PackedInt32Array()
var _keys: PackedInt64Array = PackedInt64Array()
var _bx: PackedInt32Array = PackedInt32Array()
var _by: PackedInt32Array = PackedInt32Array()


## A manager that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef, _player_id: int) -> AiStrikes:
	var strike: AiStrikes = AiStrikes.new()
	strike._uses = level.uses_strike != 0
	strike._strike_id = def.strike_type
	strike._min_value = maxi(def.strike_min_value, 0)
	strike._tests_max = clampi(def.target_tests_max, 1, _THINGS_MAX)
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
	if kind == BLACKOUT and not _wave_in_field(view, memory):
		return
	var building: int = _charged_building(view, memory)
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


## Whether a wave with a live member is in the field that the Dusk Array has not yet answered.
func _wave_in_field(view: PlayerView, memory: AiMemory) -> bool:
	if (
		memory.squads_max <= AiArmy.WAVE
		or memory.squad_state[AiArmy.WAVE] != AiMemory.SquadState.WAVE
		or memory.wave_count <= memory.strike_wave
	):
		return false
	for at: int in memory.member_id.size():
		if memory.member_squad[at] == AiArmy.WAVE and view.row_of(memory.member_id[at]) >= 0:
			return true
	return false


## The id of the lowest own strike building that is complete, charged and online now (the sim's
## test, with the stamp `tick + 1`), NONE for none.
func _charged_building(view: PlayerView, memory: AiMemory) -> int:
	var stamp: int = view.tick + 1
	for id: int in memory.site_id:
		var row: int = view.row_of(id)
		if row < 0 or view.row_type(row) != _type or view.row_build_left(row) != 0:
			continue
		if stamp >= view.row_ready_tick(row) and view.row_offline_until(row) <= stamp:
			return id
	return AiMemory.NONE


## The Deep Bore's point: the thing whose radius holds the most enemy value, with no own row or army
## goal in it and not below the minimum; `_NONE` for none.
func _bore_point(view: PlayerView, memory: AiMemory, radius: int) -> Vector2i:
	var total: int = 0
	for value: int in memory.sector_enemy:
		total += value
	if total < _min_value:
		return _NONE
	_gather(view, memory, false)
	_block(view, memory, radius)
	return _best(view, memory, radius, _min_value, _NONE)


## The Dusk Array's point: the producer whose radius holds the most producer value, among those in
## reach of the wave's goal when there are any, else among all.
func _cluster_point(view: PlayerView, memory: AiMemory, radius: int) -> Vector2i:
	_gather(view, memory, true)
	_bx.clear()  # A blackout hits no own building: nothing keeps a point clear.
	_by.clear()
	var goal: Vector2i = Vector2i(
		memory.squad_goal_x[AiArmy.WAVE], memory.squad_goal_y[AiArmy.WAVE]
	)
	if goal.x >= 0 and goal.y >= 0:
		var near: Vector2i = _best(view, memory, radius, 1, _centre(goal))
		if near != _NONE:
			return near
	return _best(view, memory, radius, 1, _NONE)


## Fills the scratch with the enemy things the AI may act on, at most `_tests_max` of them: the
## seen buildings, then (unless `producers_only`) the seen combat units and other units, then the
## remembered buildings, ids ascending inside each group.
func _gather(view: PlayerView, memory: AiMemory, producers_only: bool) -> void:
	_x.clear()
	_y.clear()
	_value.clear()
	_take_list(view, memory, memory.seen_site_id, producers_only)
	if not producers_only:
		_take_list(view, memory, memory.seen_unit_id, false)
		_take_list(view, memory, memory.seen_mobile_id, false)
	for record: int in view.ghost_count:
		if _x.size() >= _tests_max:
			return
		var type: int = view.ghost_type[record]
		if view.ghost_owner[record] <= 0 or not AiIntel.remembered(view, record):
			continue
		if not _known(view, memory, type):
			continue
		if producers_only and not AiIntel.is_producer(view, type):
			continue
		var pos: Vector2i = view.ghost_pos(record)
		_add(pos.x, pos.y, view.type_cost[type])


## Adds the seen rows of `list` (ids) that the AI may act on, until `_tests_max` things are held:
## an enemy row of a type whose first sighting is `reaction_ticks` old, a producer when
## `producers_only`. The columns are read once a row, `value_of` written out (plan row P198).
@warning_ignore("integer_division")
func _take_list(
	view: PlayerView, memory: AiMemory, list: PackedInt32Array, producers_only: bool
) -> void:
	var owners: PackedInt32Array = view.column_owner()
	var types: PackedInt32Array = view.column_type()
	var xs: PackedInt32Array = view.column_x()
	var ys: PackedInt32Array = view.column_y()
	var hps: PackedInt32Array = view.column_hp()
	var costs: PackedInt32Array = view.type_cost
	var max_hps: PackedInt32Array = view.type_max_hp
	var produces: PackedInt32Array = view.type_produces
	var first: PackedInt32Array = memory.seen_first_tick
	for id: int in list:
		if _x.size() >= _tests_max:
			return
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var owner: int = owners[row]
		if owner <= 0 or owner == view.player:
			continue
		var type: int = types[row]
		if type < 0 or type >= first.size():
			continue
		var seen_tick: int = first[type]
		if seen_tick == AiMemory.NONE or view.tick - seen_tick < _reaction:
			continue
		if producers_only:
			var tab: int = produces[type] if type < produces.size() else -1
			if tab < 0 or tab >= PlayerView.TABS:
				continue
		var cost: int = costs[type] if type < costs.size() else 0
		var max_hp: int = max_hps[type] if type < max_hps.size() else 0
		var value: int = cost
		if max_hp > 0:
			value = cost * clampi(hps[row], 0, max_hp) / max_hp
		_x.append(xs[row])
		_y.append(ys[row])
		_value.append(value)


func _add(x: int, y: int, value: int) -> void:
	_x.append(x)
	_y.append(y)
	_value.append(value)


## Fills `_bx`, `_by` with the own rows (buildings from `site_*`, units from `own_mobile_id`) and
## the live army goals that lie within `radius` of the things' bounding box. Not counted: it is
## the pre-filter of the own check. While a threat stands and the home goal is NONE, the staging
## point stands in for the home goal.
func _block(view: PlayerView, memory: AiMemory, radius: int) -> void:
	_bx.clear()
	_by.clear()
	if _x.is_empty():
		return
	var lo: Vector2i = Vector2i(_x[0] - radius, _y[0] - radius)
	var hi: Vector2i = Vector2i(_x[0] + radius, _y[0] + radius)
	for at: int in _x.size():
		lo = Vector2i(mini(lo.x, _x[at] - radius), mini(lo.y, _y[at] - radius))
		hi = Vector2i(maxi(hi.x, _x[at] + radius), maxi(hi.y, _y[at] + radius))
	for at: int in memory.site_x.size():
		_keep(memory.site_x[at], memory.site_y[at], lo, hi)
	for id: int in memory.own_mobile_id:
		var row: int = view.row_of(id)
		if row >= 0:
			var pos: Vector2i = view.row_pos(row)
			_keep(pos.x, pos.y, lo, hi)
	var wave: int = AiArmy.WAVE
	if (
		memory.squads_max > wave
		and memory.squad_role[wave] != AiMemory.NONE
		and memory.squad_state[wave] == AiMemory.SquadState.WAVE
	):
		_keep_goal(memory.squad_goal_x[wave], memory.squad_goal_y[wave], lo, hi)
	if memory.squads_max > AiArmy.HOME and memory.threat_first_tick != AiMemory.NONE:
		var goal_x: int = memory.squad_goal_x[AiArmy.HOME]
		var goal_y: int = memory.squad_goal_y[AiArmy.HOME]
		if goal_x < 0 or goal_y < 0:
			# A recall clears the home goal only when it was the staging point, so the staging
			# point stands in for the cleared goal until an order sets the home goal again (the
			# home squad's last order still leads there; the next defence or focus may not).
			goal_x = memory.staging_x
			goal_y = memory.staging_y
		_keep_goal(goal_x, goal_y, lo, hi)


func _keep_goal(col: int, line: int, lo: Vector2i, hi: Vector2i) -> void:
	if col >= 0 and line >= 0:
		var at: Vector2i = _centre(Vector2i(col, line))
		_keep(at.x, at.y, lo, hi)


func _keep(x: int, y: int, lo: Vector2i, hi: Vector2i) -> void:
	if x >= lo.x and x <= hi.x and y >= lo.y and y <= hi.y:
		_bx.append(x)
		_by.append(y)


## The best anchor among the scratch (see the header): the thing whose `radius` holds the largest
## sum of value, not below `least` (at least 1). With a `goal` (not `_NONE`) only anchors within
## `radius` of it count. A tie in the sum goes to the earlier anchor tried.
func _best(view: PlayerView, memory: AiMemory, radius: int, least: int, goal: Vector2i) -> Vector2i:
	var count: int = _x.size()
	var reach: int = radius * radius
	_rank(view, memory)
	var best_sum: int = maxi(least, 1) - 1
	var best: Vector2i = _NONE
	for step: int in count:
		var anchor: int = _THING_MASK - (_keys[count - 1 - step] & _THING_MASK)
		if goal != _NONE and _far(_x[anchor], _y[anchor], goal.x, goal.y, reach):
			continue
		var clear: int = _clear(anchor, reach)
		if clear < 0:
			break
		if clear == 0:
			continue
		if tests + count > _tests_max:
			break
		# The `count` tests of this anchor, counted at once (the cap check above holds for all).
		var sum: int = 0
		var anchor_x: int = _x[anchor]
		var anchor_y: int = _y[anchor]
		for other: int in count:
			var dx: int = _x[other] - anchor_x
			var dy: int = _y[other] - anchor_y
			if dx * dx + dy * dy <= reach:
				sum += _value[other]
		tests += count
		if sum > best_sum:
			best_sum = sum
			best = Vector2i(_x[anchor], _y[anchor])
	return best


## Sorts the anchors: `_keys` ascending, so the last is the best: the sector's enemy value, then the
## thing's value, then the earlier thing (the sort is native, an uncounted sort of at most
## `_tests_max` ints).
func _rank(view: PlayerView, memory: AiMemory) -> void:
	_keys.resize(_x.size())
	for at: int in _x.size():
		var sector: int = clampi(_sector_value(view, memory, _x[at], _y[at]), 0, _SECTOR_MASK)
		var value: int = clampi(_value[at], 0, _VALUE_MASK)
		_keys[at] = (sector << _SECTOR_SHIFT) | (value << _THING_BITS) | (_THING_MASK - at)
	_keys.sort()


## The enemy value of the sector that holds the point (0 before intel has made the grid).
func _sector_value(view: PlayerView, memory: AiMemory, x: int, y: int) -> int:
	if memory.sector_side <= 0:
		return 0
	@warning_ignore("integer_division")
	var col: int = clampi(x / PlayerView.MILLI_PER_TILE, 0, maxi(view.map_cols - 1, 0))
	@warning_ignore("integer_division")
	var line: int = clampi(y / PlayerView.MILLI_PER_TILE, 0, maxi(view.map_rows - 1, 0))
	@warning_ignore("integer_division")
	var at: int = line / memory.sector_side * memory.sector_cols + col / memory.sector_side
	return memory.sector_enemy[at] if at < memory.sector_enemy.size() else 0


## 1 when no own row or goal of the pre-filter is within `reach` of the anchor, 0 when one is, and
## -1 when the cap on counted tests ends the check first.
func _clear(anchor: int, reach: int) -> int:
	var anchor_x: int = _x[anchor]
	var anchor_y: int = _y[anchor]
	var room: int = _tests_max - tests
	for at: int in _bx.size():
		if at >= room:
			tests += at
			return -1
		var dx: int = _bx[at] - anchor_x
		var dy: int = _by[at] - anchor_y
		if dx * dx + dy * dy <= reach:
			tests += at + 1
			return 0
	tests += _bx.size()
	return 1


## Whether (x, y) is farther than `reach` (squared milli-tiles) from (px, py): a row exactly on the
## radius is hit by the sim, so it is not far.
static func _far(x: int, y: int, px: int, py: int, reach: int) -> bool:
	var dx: int = x - px
	var dy: int = y - py
	return dx * dx + dy * dy > reach


## The centre of a tile in milli-tiles.
static func _centre(tile: Vector2i) -> Vector2i:
	return (
		tile * PlayerView.MILLI_PER_TILE + Vector2i(PlayerView.TILE_CENTRE, PlayerView.TILE_CENTRE)
	)


## Whether the type's first sighting is `reaction_ticks` old (ADR 0030 section 2).
func _known(view: PlayerView, memory: AiMemory, type: int) -> bool:
	if type < 0 or type >= memory.seen_first_tick.size():
		return false
	var first: int = memory.seen_first_tick[type]
	return first != AiMemory.NONE and view.tick - first >= _reaction
