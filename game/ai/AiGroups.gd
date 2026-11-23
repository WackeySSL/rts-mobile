class_name AiGroups
extends RefCounted
## Grouped waves (plan row P250e). From the all-in tick every home unit used to join the wave one
## think after it left the factory, so the wave became a column that single units trickled into
## and that strung out over 30 tiles (the units were beaten one clump at a time, mid-map). Two
## answers, both off when their numbers are 0 (Easy and the frozen files play as before):
##
## Gather: the home units wait at the staging point and go to the wave together, when `group_min`
## of them are there or the first of them has waited `gather_ticks`. A wave that is dead is
## launched again the same way (a full group, not the one unit that happens to be home).
##
## Regroup: a wave in the all-in whose farthest member is over `spread` from the wave's centre, with
## no enemy near its front or its farthest member and its front still far from the target, gets one
## `ATTACK_MOVE` to the centre; the front waits there for the rear. It marches on (the army's
## re-target sends it to the target) when the farthest is within half of the spread, when
## `regroup_ticks` have passed (then it does not halt again for the same span: a slow straggler
## must not hold the wave for good), or when an enemy is near the front or the farthest member.
## Never before the all-in tick (P250d halted waves on the march and was not shipped). Reads only
## the army's tally and the view; no randomness.

## Counted for the suites: groups sent after a gather, gathers ended by the timeout, halts ordered.
var gathered: int = 0
var timeouts: int = 0
var halts: int = 0
var closings: int = 0
## Whether the wave is halted at its regroup point.
var regrouping: bool = false

## Copied from the level: the group size and gather time (ticks), the spread in squared milli-tiles
## (and the front's distance that counts as arrived, squared) and the regroup cap in ticks.
var _group_min: int = 0
var _gather: int = 0
var _spread2: int = 0
var _arrive2: int = 0
var _cap: int = 0
var _lead: int = 0
## The tick the first waiting home unit was seen (-1: none waits), the tick the regroup began, the
## first tick a new regroup may begin.
var _waiting_since: int = -1
var _since: int = -1
var _free_at: int = -1
## This think's measure of the wave (`_measure`): the squared distance of the farthest member from
## the centre, that member's place, and the place of the member nearest to the target.
var _far2: int = 0
var _far: Vector2i = Vector2i.ZERO
var _front: Vector2i = Vector2i.ZERO
var _front_gap2: int = -1


static func create(level: AiDifficultyDef) -> AiGroups:
	var groups: AiGroups = AiGroups.new()
	groups._group_min = maxi(level.group_min_size, 0)
	groups._gather = maxi(level.group_gather_ticks, 0)
	var spread: int = maxi(level.wave_regroup_spread_tiles, 0) * PlayerView.MILLI_PER_TILE
	groups._spread2 = spread * spread
	groups._arrive2 = 4 * spread * spread
	groups._cap = maxi(level.wave_regroup_ticks, 0)
	groups._lead = maxi(level.wave_lead_percent, 0)
	return groups


## A new wave starts or the old one is over.
func reset() -> void:
	regrouping = false
	_since = -1
	_free_at = -1
	_front_gap2 = -1


## True while the `home` units (the count of those at the staging point) keep waiting for a group:
## fewer than `group_min` and the first waited less than `gather_ticks`. Not holding (false) ends
## the gather, so the next unit starts a new one. Always false when the gather is off, and while
## the wave's front is at the target and the wave is worth `lead` percent of the seen enemy value
## near it or more (a won fight at the target is reinforced at once, the closing push).
func holding(army: AiArmy, view: PlayerView, memory: AiMemory, home: int) -> bool:
	if _group_min <= 0 or home == 0:
		_waiting_since = -1
		return false
	if _closing(army, view, memory):
		_waiting_since = -1
		closings += 1
		return false
	if _waiting_since < 0:
		_waiting_since = view.tick
	if home < _group_min and view.tick - _waiting_since < _gather:
		return true
	if home < _group_min:
		timeouts += 1
	gathered += 1
	_waiting_since = -1
	return false


## Whether the wave's front stands at the target with a clear lead over the enemy seen near it.
func _closing(army: AiArmy, view: PlayerView, memory: AiMemory) -> bool:
	if _lead <= 0 or _front_gap2 < 0 or _front_gap2 > _arrive2:
		return false
	return army._wave_value * 100 >= army._near(view, memory, _front) * _lead


## True while the wave is halted at its regroup point after this think (the caller sends it no
## other order). `army._wave_at` is this think's tally.
func run(army: AiArmy, view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	if _spread2 == 0:
		return false
	var ids: PackedInt32Array = army._members(memory, true, AiArmy.WAVE)
	if ids.size() < 2:
		regrouping = false
		_front_gap2 = -1
		return false
	_measure(army, view, memory, ids)
	if regrouping:
		return _keep(army, view, memory)
	var may: bool = _far2 > _spread2 and view.tick >= _free_at and _front_gap2 > _arrive2
	return may and not _engaged(army, view, memory) and _halt(army, view, memory, out, ids)


## Whether the standing halt goes on this think: the farthest member is not yet within half of the
## spread, the cap has not passed and no enemy is near. When it ends the next halt waits a cap.
func _keep(army: AiArmy, view: PlayerView, memory: AiMemory) -> bool:
	var capped: bool = _cap > 0 and view.tick - _since >= _cap
	if _far2 * 4 > _spread2 and not capped and not _engaged(army, view, memory):
		return true
	regrouping = false
	_free_at = view.tick + _cap
	return false


## Sets `_far2`, `_far` (the farthest member from the centre), `_front` and `_front_gap2` (the
## member nearest to the target and its squared distance from it).
func _measure(army: AiArmy, view: PlayerView, memory: AiMemory, ids: PackedInt32Array) -> void:
	var target: Vector2i = AiArmy._at(Vector2i(memory.base_x, memory.base_y))
	_far2 = 0
	_far = army._wave_at
	_front = army._wave_at
	_front_gap2 = -1
	for id: int in ids:
		var at: Vector2i = view.row_pos(view.row_of(id))
		var from_centre: Vector2i = at - army._wave_at
		var far2: int = from_centre.x * from_centre.x + from_centre.y * from_centre.y
		if far2 > _far2:
			_far2 = far2
			_far = at
		var to_target: Vector2i = at - target
		var gap2: int = to_target.x * to_target.x + to_target.y * to_target.y
		if _front_gap2 < 0 or gap2 < _front_gap2:
			_front_gap2 = gap2
			_front = at


## Whether a seen enemy is near the wave's front or its farthest member (the fight is on).
func _engaged(army: AiArmy, view: PlayerView, memory: AiMemory) -> bool:
	return army._near(view, memory, _front) > 0 or army._near(view, memory, _far) > 0


## The `ATTACK_MOVE` of the wave to its centre; false, nothing changed, when it is refused.
func _halt(
	army: AiArmy, view: PlayerView, memory: AiMemory, out: Array[Command], ids: PackedInt32Array
) -> bool:
	var tile: Vector2i = army._wave_at / PlayerView.MILLI_PER_TILE
	if not army._order(view, memory, out, ids, tile, AiMemory.Owner.ARMY, AiArmy._at(tile)):
		return false
	memory.squad_goal_x[AiArmy.WAVE] = tile.x
	memory.squad_goal_y[AiArmy.WAVE] = tile.y
	regrouping = true
	_since = view.tick
	halts += 1
	return true
