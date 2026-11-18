class_name AiUnseen
extends RefCounted
## The unseen-hit response of the army manager (P179b), moved out of `AiArmy` (P250d, no behaviour
## change): a hurt home unit that no seen enemy could have hit shifts the home squad's goal, a probe
## that `probing` holds. The counters (`shifts`, `hit_tests`) and the order helpers stay on the
## `AiArmy` passed in; this object keeps the shift distance, the tick of the last shift and its
## scratch list, and holds no reference to the army.

## How far a unit hit by the unseen moves its squad's goal, in tiles.
var shift_tiles: int = 0
## The tick of the last unseen-hit shift (-1: none yet).
var shifted_at: int = -1
## Scratch for the swap of the hp list of `run`.
var _kept: PackedInt32Array = PackedInt32Array()


## The unseen-hit response (P179b), for the home squad only (a wave's goal is the waves' own). A
## home unit (not one that stepped back) that lost hp since the last run, while no seen enemy
## combat unit or building was within its weapon range, makes the squad's goal move `shift_tiles`
## toward the base estimate (the point mirror of the Headquarters without one): an army order, all
## or nothing. The shifted goal
## is a probe, held while `home_shifted` is set (see `probing`); further hits do not move it, but
## after the return to the staging point a new hit shifts again, out and back, never creeping. Only
## while no threat stands and none stood at the last run (`calm`; the squad fought it, and a foe
## it killed is gone from the view). The hp of the home units is kept for the next run when no
## order went (no budget, no keys), so the hit is found again; a unit whose range test ran into
## the test cap counts as covered. `unit_id` and `member_id` are the same list after `_join`, so
## an index of one is the other's.
func run(army: AiArmy, view: PlayerView, memory: AiMemory, out: Array[Command], calm: bool) -> void:
	army.hit_tests = 0
	var refused: bool = false
	if calm and memory.home_shifted == 0:
		# `unit_id` and `hp_id` ascend: one walk down `hp_id` replaces a bsearch a unit.
		var units: PackedInt32Array = memory.unit_id
		var hp_ids: PackedInt32Array = memory.hp_id
		var hps: PackedInt32Array = memory.unit_hp
		var listed: int = hp_ids.size()
		var withdrawn: bool = not memory.withdrawn_id.is_empty()
		var walk: int = 0
		for at: int in units.size():
			if memory.member_squad[at] != AiArmy.HOME:
				continue
			var id: int = units[at]
			if withdrawn and army._withdrawn(memory, id):
				continue
			while walk < listed and hp_ids[walk] < id:
				walk += 1
			var was: int = AiMemory.NONE
			if walk < listed and hp_ids[walk] == id:
				was = memory.hp_value[walk]
			if was <= hps[at]:
				continue
			if not _covered(army, view, memory, view.row_of(id)):
				refused = not _shift(army, view, memory, out)
				break
	_kept.clear()
	if refused:
		for at: int in memory.unit_id.size():
			var was: int = AiMemory.NONE
			if memory.member_squad[at] == AiArmy.HOME:
				was = hp_was(memory, memory.unit_id[at])
			_kept.append(was if was != AiMemory.NONE else memory.unit_hp[at])
	else:
		_kept.append_array(memory.unit_hp)
	memory.hp_id.clear()
	memory.hp_id.append_array(memory.unit_id)
	var old: PackedInt32Array = memory.hp_value
	memory.hp_value = _kept
	_kept = old


## The hp unit `id` had at the last run, NONE when it was not listed.
static func hp_was(memory: AiMemory, id: int) -> int:
	var at: int = memory.hp_id.bsearch(id)
	if at < memory.hp_id.size() and memory.hp_id[at] == id:
		return memory.hp_value[at]
	return AiMemory.NONE


## Whether a seen enemy combat unit or building stands within the weapon range of the own unit at
## `row`, or the test cap (`army.tests_max` a run, shared by all units) ran out first.
func _covered(army: AiArmy, view: PlayerView, memory: AiMemory, row: int) -> bool:
	if row < 0:
		return true
	var at: Vector2i = view.row_pos(row)
	var reach: int = view.type_range[view.row_type(row)]
	return (
		_reaches(army, view, memory.seen_unit_id, at, reach)
		or _reaches(army, view, memory.seen_site_id, at, reach)
	)


## Whether a row of `list` is within `reach` of `at`, or the test cap ran out (one test a row).
func _reaches(
	army: AiArmy, view: PlayerView, list: PackedInt32Array, at: Vector2i, reach: int
) -> bool:
	for foe: int in list:
		if army.hit_tests >= army.tests_max:
			return true
		army.hit_tests += 1
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
func _shift(army: AiArmy, view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	var goal: Vector2i = Vector2i(
		memory.squad_goal_x[AiArmy.HOME], memory.squad_goal_y[AiArmy.HOME]
	)
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
	var send: PackedInt32Array = army._members(memory, true)
	if to == goal or send.is_empty():
		return true
	if not army._order(view, memory, out, send, to, AiMemory.Owner.ARMY, AiArmy._at(to)):
		return false
	army._fresh.clear()
	memory.squad_goal_x[AiArmy.HOME] = to.x
	memory.squad_goal_y[AiArmy.HOME] = to.y
	memory.home_shifted = 1
	shifted_at = view.tick
	army.shifts += 1
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
func probing(army: AiArmy, view: PlayerView, memory: AiMemory) -> bool:
	if view.tick == shifted_at:
		return true
	for at: int in memory.member_id.size():
		var id: int = memory.member_id[at]
		if memory.member_squad[at] != AiArmy.HOME or army._is_pending(id):
			continue
		var row: int = view.row_of(id)
		if row < 0:
			continue
		if view.row_order(row) != PlayerView.Order.IDLE:
			return true
		if _covered(army, view, memory, row) and army.hit_tests < army.tests_max:
			return true
	return false
