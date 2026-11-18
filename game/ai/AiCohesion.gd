class_name AiCohesion
extends RefCounted
## Wave cohesion (plan row P250d), called by `AiArmy._fight` for a wave on the march. A wave that
## strings out arrives piecemeal and loses its fights one by one, so when its farthest member is
## more than `wave_spread_tiles` from the wave's centre the whole wave gets one `ATTACK_MOVE` to the
## centre (the front halts there, the rear closes up) and the squad's goal is that point. It marches
## on, with the `AiArmy` re-target sending it to the target again, when the farthest member is
## within half of the spread, when `wave_regroup_ticks` have passed (a slow straggler must not hold
## the wave for good; the wave then does not halt again for the same span), or when an enemy is near
## the wave's front (the fight is on: the rear comes on as it is). Squads and stances are not
## touched, so `AiHold`'s held artillery halts and walks with the rest. Not from the all-in tick:
## its joiners stream in one by one from the base, so the spread never closes (tried, P250d). Off
## (Easy, the frozen files) when the level's `wave_spread_tiles` is 0. Reads only the army's tally
## and the view.

## Over the match, for the suites: halts ordered and marches resumed.
var halts: int = 0
var resumes: int = 0
## Whether the wave is halted at its regroup point.
var halted: bool = false

## The spread in squared milli-tiles and the cap in ticks (0: off).
var _limit2: int = 0
var _cap: int = 0
var _since: int = -1
var _free_at: int = -1
## This think's measure (`_measure`).
var _far2: int = 0
var _front: Vector2i = Vector2i.ZERO


static func create(level: AiDifficultyDef) -> AiCohesion:
	var cohesion: AiCohesion = AiCohesion.new()
	var spread: int = maxi(level.wave_spread_tiles, 0) * PlayerView.MILLI_PER_TILE
	cohesion._limit2 = spread * spread
	cohesion._cap = maxi(level.wave_regroup_ticks, 0)
	return cohesion


## A new wave starts or the old one is over.
func reset() -> void:
	halted = false
	_since = -1
	_free_at = -1


## True while the wave is halted at its regroup point after this think (the caller sends it no
## other order). `army._wave_at` is this think's tally.
func run(army: AiArmy, view: PlayerView, memory: AiMemory, out: Array[Command]) -> bool:
	if _limit2 == 0:
		return false
	var ids: PackedInt32Array = army._members(memory, true, AiArmy.WAVE)
	if ids.size() < 2:
		halted = false
		return false
	_measure(army, view, memory, ids)
	if halted:
		var capped: bool = _cap > 0 and view.tick - _since >= _cap
		if _far2 * 4 > _limit2 and not capped and army._near(view, memory, _front) == 0:
			return true
		halted = false
		resumes += 1
		if capped:
			_free_at = view.tick + _cap
		return false
	if _far2 <= _limit2 or view.tick < _free_at or army._near(view, memory, _front) > 0:
		return false
	return _halt(army, view, memory, out, ids)


## Sets `_far2` (the squared distance of the farthest member from the centre) and `_front` (the
## member nearest the target).
func _measure(army: AiArmy, view: PlayerView, memory: AiMemory, ids: PackedInt32Array) -> void:
	var target: Vector2i = AiArmy._at(Vector2i(memory.base_x, memory.base_y))
	var near2: int = -1
	_far2 = 0
	_front = army._wave_at
	for id: int in ids:
		var at: Vector2i = view.row_pos(view.row_of(id))
		var from_centre: Vector2i = at - army._wave_at
		_far2 = maxi(_far2, from_centre.x * from_centre.x + from_centre.y * from_centre.y)
		var to_target: Vector2i = at - target
		var gap: int = to_target.x * to_target.x + to_target.y * to_target.y
		if near2 < 0 or gap < near2:
			near2 = gap
			_front = at


## The `ATTACK_MOVE` of the wave to its centre; false, nothing changed, when it is refused.
func _halt(
	army: AiArmy, view: PlayerView, memory: AiMemory, out: Array[Command], ids: PackedInt32Array
) -> bool:
	var tile: Vector2i = army._wave_at / PlayerView.MILLI_PER_TILE
	if not army._order(view, memory, out, ids, tile, AiMemory.Owner.ARMY, AiArmy._at(tile)):
		return false
	memory.squad_goal_x[AiArmy.WAVE] = tile.x
	memory.squad_goal_y[AiArmy.WAVE] = tile.y
	halted = true
	_since = view.tick
	halts += 1
	return true
