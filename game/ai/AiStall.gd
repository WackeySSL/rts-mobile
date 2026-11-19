class_name AiStall
extends RefCounted
## The wave's stall answer (plan row P555b). A wave whose units stand idle and get no closer to
## their target over a window is stalled: the target is cut off (a walled crossing on Heron Fords
## or Curlew Crags; the sim steers a unit with no route straight at its goal, and it stops at the
## first ridge or wall). The answer is Commands from the view alone: first an `ATTACK` on the
## nearest enemy building the view shows (a wall is a building in the way), then, once that is
## done and the units stand idle again, the old `ATTACK_MOVE` to the target, in turn. With no
## enemy building in view (P555c) a few units scout the nearest unexplored ground on the target's
## side first, so the wall comes into view. A wave that
## still fights keeps its order and is never touched; nor is one near its target. A def whose
## `stall_window_ticks` is 0 (the frozen files) turns it off, so a play from them is as before.
## The numbers are the def's. No randomness.

## The counters the suites read: orders on a building, scout orders and orders back to the target.
var attacks: int = 0
var scouts: int = 0
var retries: int = 0

## Copied from the def: the window (ticks), the progress that resets it, the distance from the
## target that counts as arrived (milli-tiles), and the idle share of the wave (percent).
var _window: int = 0
var _progress: int = 0
var _arrive: int = 0
var _idle_percent: int = 0
## How many units of the wave scout when no enemy building is in view (0 = none), and the cells a
## scout was sent to already (no cell twice, so a cell no one can enter is not tried again).
var _scout_units: int = 0
var _tried: PackedInt32Array = PackedInt32Array()
## The target the wave aims at (tiles), the nearest the wave has been to it since the last order,
## the tick that changed, the tick since which the idle share has held at every think (-1: not
## now), and whether the next answer sends the wave back to the target.
var _goal: Vector2i = Vector2i(-1, -1)
var _best: int = -1
var _since: int = 0
var _idle_from: int = -1
var _retry: bool = false


static func create(def: OpponentDef) -> AiStall:
	var stall: AiStall = AiStall.new()
	stall._window = maxi(def.stall_window_ticks, 0)
	stall._progress = maxi(def.stall_progress_tiles, 0) * PlayerView.MILLI_PER_TILE
	stall._arrive = maxi(def.stall_arrive_tiles, 0) * PlayerView.MILLI_PER_TILE
	stall._idle_percent = clampi(def.stall_idle_percent, 0, 100)
	stall._scout_units = maxi(def.stall_scout_units, 0)
	return stall


## The stall state starts over (a new wave, or one that ended).
func reset() -> void:
	_best = -1
	_idle_from = -1
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
	if goal != _goal:
		_goal = goal  # A new target starts a new window.
		_best = -1
	# The idle share must hold at every think of the window, so a pause in a fight is no stall.
	if idle * 100 < ids.size() * _idle_percent:
		_idle_from = -1
	elif _idle_from < 0:
		_idle_from = view.tick
	if _best < 0 or left + _progress <= _best or left <= _arrive:
		_best = left
		_since = view.tick
		return false
	if _idle_from < 0 or view.tick - _since < _window or view.tick - _idle_from < _window:
		return false
	if army.wave_engaged(view, memory):
		return false
	var sent: bool = false
	var wall: int = AiMemory.NONE if _retry else _nearest_building(view, memory, at)
	if wall != AiMemory.NONE:
		# The key books the target's cell, as the wave's goal does: the order is an ATTACK on the
		# building, and the army's key and goal stay one (`AiArmy._wave_holds_army`).
		sent = army._order(view, memory, out, ids, goal, AiMemory.Owner.ARMY, aim, wall)
		attacks += 1 if sent else 0
	elif not _retry and _scout(army, view, memory, out, ids, at, goal):
		sent = true
	else:
		sent = army._order(view, memory, out, ids, goal, AiMemory.Owner.ARMY, aim)
		retries += 1 if sent else 0
	if sent:
		_retry = wall != AiMemory.NONE
		_since = view.tick
		_idle_from = -1
	return sent


## No enemy building is in view: the first `_scout_units` units of the wave go to the nearest cell
## the player has not explored (the view's `is_explored`) on the target's side of the wave, and what
## they see ends the blindness; the next answer finds the building or goes on. The key books the
## target's cell, as the wave's goal does. True when sent.
func _scout(
	army: AiArmy,
	view: PlayerView,
	memory: AiMemory,
	out: Array[Command],
	ids: PackedInt32Array,
	at: Vector2i,
	goal: Vector2i
) -> bool:
	var cell: int = scout_cell(view, at, AiArmy._at(goal))
	if _scout_units <= 0 or cell < 0:
		return false
	var tile: Vector2i = Vector2i(cell % view.map_cols, cell / view.map_cols)
	var group: PackedInt32Array = PackedInt32Array()
	for at_id: int in mini(_scout_units, ids.size()):
		group.append(ids[at_id])
	if not army._order(view, memory, out, group, goal, AiMemory.Owner.ARMY, AiArmy._at(tile)):
		return false
	_tried.append(cell)
	scouts += 1
	return true


## The cell the view says is unexplored that lies nearest to `at` (milli-tiles) among those on the
## side of `aim` (the dot product with the way to it is above 0), the lowest cell on a tie, and not
## sent to before; -1 for none. Reads the view's `is_explored` only, never the map.
func scout_cell(view: PlayerView, at: Vector2i, aim: Vector2i) -> int:
	var cols: int = view.map_cols
	var way: Vector2i = aim - at
	var found: int = -1
	var least: int = 0
	for cell: int in cols * view.map_rows:
		if view.is_explored(cell) or _tried.has(cell):
			continue
		var gap: Vector2i = AiArmy._at(Vector2i(cell % cols, cell / cols)) - at
		if gap.x * way.x + gap.y * way.y <= 0:
			continue
		var near: int = gap.x * gap.x + gap.y * gap.y
		if found < 0 or near < least:
			found = cell
			least = near
	return found


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
