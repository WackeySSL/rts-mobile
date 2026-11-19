class_name AiStall
extends RefCounted
## The wave's stall answer (plan row P555b). A wave whose units stand idle and get no closer to
## their target over a window is stalled: the target is cut off (a walled crossing on Heron Fords
## or Curlew Crags; the sim steers a unit with no route straight at its goal, and it stops at the
## first ridge or wall). The answer is Commands from the view alone: first an `ATTACK` on the
## nearest enemy building the view shows (a wall is a building in the way), then, once that is
## done and the units stand idle again, the old `ATTACK_MOVE` to the target, in turn. A wave that
## still fights keeps its order and is never touched; nor is one near its target. A def whose
## `stall_window_ticks` is 0 (the frozen files) turns it off, so a play from them is as before.
## The numbers are the def's. No randomness, no World.

## The counters the suites read: orders on a building and orders back to the target.
var attacks: int = 0
var retries: int = 0

## Copied from the def: the window (ticks), the progress that resets it, the distance from the
## target that counts as arrived (milli-tiles), and the idle share of the wave (percent).
var _window: int = 0
var _progress: int = 0
var _arrive: int = 0
var _idle_percent: int = 0
## The nearest the wave has been to its target since the last order, the tick that changed, and
## whether the next answer sends the wave back to the target.
var _best: int = -1
var _since: int = 0
var _retry: bool = false


static func create(def: OpponentDef) -> AiStall:
	var stall: AiStall = AiStall.new()
	stall._window = maxi(def.stall_window_ticks, 0)
	stall._progress = maxi(def.stall_progress_tiles, 0) * PlayerView.MILLI_PER_TILE
	stall._arrive = maxi(def.stall_arrive_tiles, 0) * PlayerView.MILLI_PER_TILE
	stall._idle_percent = clampi(def.stall_idle_percent, 0, 100)
	return stall


## The stall state starts over (a new wave, or one that ended).
func reset() -> void:
	_best = -1
	_retry = false


## One look at the wave `ids` (`units` of them, `idle` of those without an order, centred on `at`
## in milli-tiles) on its way to the memory's base estimate. True when an order was sent, which the
## army then counts as the wave's turn.
func run(
	army: AiArmy,
	view: PlayerView,
	memory: AiMemory,
	out: Array[Command],
	ids: PackedInt32Array,
	at: Vector2i,
	idle: int
) -> bool:
	if _window <= 0 or ids.is_empty() or not memory.has_base_estimate():
		return false
	var goal: Vector2i = Vector2i(memory.base_x, memory.base_y)
	var aim: Vector2i = AiArmy._at(goal)
	var gap: Vector2i = aim - at
	var left: int = FixedMath.isqrt(gap.x * gap.x + gap.y * gap.y)
	if _best < 0 or left + _progress <= _best or left <= _arrive:
		_best = left
		_since = view.tick
		return false
	if view.tick - _since < _window or idle * 100 < ids.size() * _idle_percent:
		return false
	var sent: bool = false
	var wall: int = AiMemory.NONE if _retry else _nearest_building(view, memory, at)
	if wall != AiMemory.NONE:
		var tile: Vector2i = view.row_pos(view.row_of(wall)) / PlayerView.MILLI_PER_TILE
		sent = army._order(
			view, memory, out, ids, tile, AiMemory.Owner.ARMY, AiArmy._at(tile), wall
		)
		attacks += 1 if sent else 0
	else:
		sent = army._order(view, memory, out, ids, goal, AiMemory.Owner.ARMY, aim)
		retries += 1 if sent else 0
	if sent:
		_retry = wall != AiMemory.NONE
		_since = view.tick
	return sent


## The id of the seen enemy building nearest to `at` that the view shows now, NONE for none.
func _nearest_building(view: PlayerView, memory: AiMemory, at: Vector2i) -> int:
	var found: int = AiMemory.NONE
	var least: int = 0
	for id: int in memory.seen_site_id:
		var row: int = view.row_of(id)
		if row < 0:
			continue
		var gap: Vector2i = view.row_pos(row) - at
		var near: int = gap.x * gap.x + gap.y * gap.y
		if found == AiMemory.NONE or near < least:
			found = id
			least = near
	return found
