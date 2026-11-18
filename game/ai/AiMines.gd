class_name AiMines
extends RefCounted
## The opponent's mine manager (ADR 0037 section 8, plan row P295), slot INTEL after `AiStrikes`,
## on the same view and memory. It sends `QUEUE`, `LAY_MINE` and `MOVE` only, to the minelayer type
## of the def (`mine_layer_type`; a roster without it, or a type with no mine weapon, leaves every
## duty off). One order a think, in this order:
## - Sweep: while no wave is in the field, a known enemy mine (`known_mines`, the player's own
##   records) within `mine_sweep_reach_tiles` of the route is cleared: a free layer `MOVE`s onto its
##   cell and the sim sweeps it (a layer never sets a mine off).
## - Lay: while the own mines (and the lays on their way) are under `mine_target` and the rules' cap
##   and the credits pay a mine, a free layer `LAY_MINE`s on the next cell of the own half of the
##   route, `mine_spacing_tiles` apart, counted from the Headquarters. A cell that holds no mine
##   once the lay is over (refused: blocked) is not tried again.
## - Scout (`mine_scout_ahead`, Hard): else a free layer walks the route past the own half in
##   legs of `mine_scout_leg_tiles`, finding mines for the sweep.
## The route is the straight line from the own Headquarters to the enemy base estimate (else its
## point mirror), as the army's wave takes it. A layer is queued when fewer than `mine_layers` live
## or wait. Everything comes from the player's own state: own rows, own mines, its records and the
## memory. A layer is busy from its order until it has stood idle for a lay or a sweep (a new order
## would cancel it). No pass over the view's rows, no random number is drawn.

enum Duty { LAY, SWEEP, SCOUT }
const _NONE: int = PlayerView.MISSING

## Counters for the suites: lays, sweeps and scout legs ordered, over the match.
var lays: int = 0
var sweeps: int = 0
var legs: int = 0

var _target: int = 0
var _layers_wanted: int = 0
var _scout: bool = false
var _type_id: StringName = &""
var _spacing: int = 1
var _reach: int = 0
var _leg: int = 1
var _reach_percent: int = 0
## The layer type as an index of the view's roster, found on the first run (-2: not yet; MISSING:
## none, which turns the manager off).
var _type: int = -2
## The layers on a duty, in parallel: id, `Duty`, goal cell, and the tick it may be ordered again
## (-1 while it still moves).
var _job_id: PackedInt32Array = PackedInt32Array()
var _job_duty: PackedInt32Array = PackedInt32Array()
var _job_cell: PackedInt32Array = PackedInt32Array()
var _job_until: PackedInt32Array = PackedInt32Array()
## The cells a lay left no mine on (the list is as long as the route has cells: it is cleared when
## the route moves) and the scout legs ordered since the last wave.
var _blocked: PackedInt32Array = PackedInt32Array()
var _leg_count: int = 0
## The route of this run: the Headquarters tile, the step to the enemy base and its length (the
## larger of the two distances in tiles; under 2: no route).
var _hx: int = 0
var _hy: int = 0
var _dx: int = 0
var _dy: int = 0
var _len: int = 0
var _route_was: Vector4i = Vector4i.ZERO


## A manager that copies what it reads of `def` and `level`.
static func create(def: OpponentDef, level: AiDifficultyDef) -> AiMines:
	var mines: AiMines = AiMines.new()
	mines._type_id = def.mine_layer_type
	mines._target = maxi(level.mine_target, 0) if def.mine_layer_type != &"" else 0
	mines._layers_wanted = maxi(level.mine_layers, 0)
	mines._reach_percent = maxi(def.mine_scout_reach_percent, 0)
	mines._scout = level.mine_scout_ahead > 0 and mines._reach_percent > 0
	mines._spacing = maxi(def.mine_spacing_tiles, 1)
	mines._reach = maxi(def.mine_sweep_reach_tiles, 0)
	mines._leg = maxi(def.mine_scout_leg_tiles, 1)
	return mines


func run(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if _target <= 0 or _layers_wanted <= 0 or not _resolve(view):
		return
	var layers: PackedInt32Array = _alive(view, memory)
	_tend(view, memory)
	var free: int = _free_layer(view, layers)
	if free == _NONE or not memory.can_send() or not _route(view, memory):
		return
	var lull: bool = not _wave_out(memory)
	if not lull:
		_leg_count = 0
	if lull and _sweep(view, memory, out, free):
		return
	if _lay(view, memory, out, free):
		return
	if _scout and lull:
		_walk(view, memory, out, free)


## The layer type of the view's roster, once; MISSING without a mine weapon or a move speed.
func _resolve(view: PlayerView) -> bool:
	if _type == -2:
		_type = layer_type(view, _type_id)
	return _type != _NONE and view.mine_cap > 0


## The index of the unarmed mobile type `id` with a mine weapon (MISSING for any other, so an armed
## type, which `AiArmy` would also order, is never a layer). `AiProduction` uses it too.
static func layer_type(view: PlayerView, id: StringName) -> int:
	var type: int = view.type_index_of(id)
	var fit: bool = (
		type != _NONE
		and type < view.type_mine_weapon.size()
		and view.type_mine_weapon[type] >= 0
		and view.type_weapon[type] < 0
		and view.type_speed[type] > 0
	)
	return type if fit else _NONE


## The own live layers, ids ascending (the mobile ids `AiIntel` listed).
func _alive(view: PlayerView, memory: AiMemory) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for id: int in memory.own_mobile_id:
		var row: int = view.row_of(id)
		if row >= 0 and view.row_type(row) == _type:
			found.append(id)
	return found


## Moves the jobs on: a layer that stands idle starts its wait (a lay or a sweep takes ticks), one
## whose wait is over is free again (a lay that left no mine marks its cell blocked), a dead one
## goes.
@warning_ignore("integer_division")
func _tend(view: PlayerView, memory: AiMemory) -> void:
	for at: int in range(_job_id.size() - 1, -1, -1):
		var row: int = view.row_of(_job_id[at])
		var done: bool = row < 0
		if not done and _job_until[at] < 0:
			if view.row_order(row) == PlayerView.Order.IDLE:
				_job_until[at] = view.tick + _wait(view, _job_duty[at])
		if not done and _job_until[at] >= 0 and view.tick >= _job_until[at]:
			done = true
			# A real refusal only (cell or occupancy): not for want of credits or under the cap.
			if (
				_job_duty[at] == Duty.LAY
				and not view.own_mines.has(_job_cell[at])
				and view.credits >= view.type_mine_cost[_type]
				and view.own_mines.size() < view.mine_cap
			):
				_blocked.append(_job_cell[at])
		if done:
			_job_id.remove_at(at)
			_job_duty.remove_at(at)
			_job_cell.remove_at(at)
			_job_until.remove_at(at)
	# One key per moving layer, made again each think (the army's full cache may have taken them).
	memory.release_owner(AiMemory.Owner.MINE)
	for at: int in _job_id.size():
		if _job_until[at] < 0:
			memory.add_goal_key(
				_job_cell[at] % view.map_cols,
				_job_cell[at] / view.map_cols,
				AiMemory.class_of(view, _type),
				AiMemory.Owner.MINE
			)


## Ticks a layer must stand on its goal before it is free: a lay or a sweep, none for a leg.
func _wait(view: PlayerView, duty: int) -> int:
	match duty:
		Duty.LAY:
			return view.mine_lay_ticks + 1
		Duty.SWEEP:
			return view.sweep_ticks + 1
	return 0


## The lowest id of a layer that is idle and on no duty (MISSING: none).
func _free_layer(view: PlayerView, layers: PackedInt32Array) -> int:
	for id: int in layers:
		if not _job_id.has(id) and view.row_order(view.row_of(id)) == PlayerView.Order.IDLE:
			return id
	return _NONE


## Whether a wave is in the field (the sweeps and the legs wait for the lull before one).
## TODO: the fifth copy of "a wave is marching" (`AiArmy`, `AiHold`, `AiStrikes`, `AiSearch`): a
## follow-up shares one `AiMemory` function.
func _wave_out(memory: AiMemory) -> bool:
	return (
		memory.squads_max > AiArmy.WAVE
		and memory.squad_state[AiArmy.WAVE] == AiMemory.SquadState.WAVE
	)


## The route of this run from the memory: the own Headquarters tile to the base estimate, else its
## mirror. False without a Headquarters or a route of two tiles.
func _route(view: PlayerView, memory: AiMemory) -> bool:
	if memory.home_x == AiMemory.NONE or memory.home_y == AiMemory.NONE:
		return false
	var home: Vector2i = Vector2i(memory.home_x, memory.home_y)
	var base: Vector2i = AiMemory.mirror(home, view.map_cols, view.map_rows)
	if memory.has_base_estimate():
		base = Vector2i(memory.base_x, memory.base_y)
	_hx = home.x
	_hy = home.y
	_dx = base.x - home.x
	_dy = base.y - home.y
	_len = maxi(absi(_dx), absi(_dy))
	var now: Vector4i = Vector4i(_hx, _hy, base.x, base.y)
	if now != _route_was:
		_route_was = now
		_blocked.clear()
	return _len >= 2


## The tile `along` tiles from the Headquarters on the route.
@warning_ignore("integer_division")
func _at(along: int) -> Vector2i:
	return Vector2i(_hx + _dx * along / _len, _hy + _dy * along / _len)


## Whether the tile is within the sweep reach of the route (the segment from the Headquarters to the
## base): its projection lies on it and its distance, by the cross product, is within the reach.
func _near(tile: Vector2i) -> bool:
	var px: int = tile.x - _hx
	var py: int = tile.y - _hy
	var along: int = px * _dx + py * _dy
	var length2: int = _dx * _dx + _dy * _dy
	var cross: int = px * _dy - py * _dx
	return along >= 0 and along <= length2 and cross * cross <= _reach * _reach * length2


## One known enemy mine near the route that no layer is on: a free layer moves onto it.
@warning_ignore("integer_division")
func _sweep(view: PlayerView, memory: AiMemory, out: Array[Command], id: int) -> bool:
	for at: int in view.known_mines.size():
		var cell: int = view.known_mines[at]
		var tile: Vector2i = Vector2i(cell % view.map_cols, cell / view.map_cols)
		if view.known_mine_owner[at] == view.player or _job_cell.has(cell) or not _near(tile):
			continue
		if not _go(view, memory, out, id, tile, false):
			return false
		_job(id, Duty.SWEEP, cell)
		sweeps += 1
		return true
	return false


## One mine laid on the next free cell of the own half of the route, while the own mines and the
## lays on their way are under the target and the cap and a mine is paid.
@warning_ignore("integer_division")
func _lay(view: PlayerView, memory: AiMemory, out: Array[Command], id: int) -> bool:
	var pending: int = 0
	for duty: int in _job_duty:
		pending += 1 if duty == Duty.LAY else 0
	var room: int = mini(_target, view.mine_cap) - view.own_mines.size() - pending
	if room <= 0 or view.credits < view.type_mine_cost[_type]:
		return false
	for step: int in range(1, _len / (2 * _spacing) + 1):
		var tile: Vector2i = _at(step * _spacing)
		var cell: int = tile.y * view.map_cols + tile.x
		if view.own_mines.has(cell) or _blocked.has(cell) or _job_cell.has(cell):
			continue
		if not _go(view, memory, out, id, tile, true):
			return false
		_job(id, Duty.LAY, cell)
		lays += 1
		return true
	return false


## The scout layer's next leg: the route's point past the own half, a leg further each time, as far
## as `mine_scout_reach_percent` of the route. Once the legs are done (they start again after the
## next wave) the layer goes back to the edge of the own half.
@warning_ignore("integer_division")
func _walk(view: PlayerView, memory: AiMemory, out: Array[Command], id: int) -> void:
	var along: int = _len / 2 + (_leg_count + 1) * _leg
	var back: bool = along > _len * _reach_percent / 100
	var tile: Vector2i = _at(_len / 2 if back else along)
	var here: Vector2i = view.row_pos(view.row_of(id)) / PlayerView.MILLI_PER_TILE
	if back and here == tile:
		return
	if _go(view, memory, out, id, tile, false):
		_job(id, Duty.SCOUT, tile.y * view.map_cols + tile.x)
		if not back:
			_leg_count += 1
			legs += 1


## `LAY_MINE` (`lay`) or `MOVE` of the layer to the tile's centre, after the goal key. False,
## nothing sent, when the cache has no room for it.
func _go(
	view: PlayerView, memory: AiMemory, out: Array[Command], id: int, tile: Vector2i, lay: bool
) -> bool:
	if not memory.add_goal_key(tile.x, tile.y, AiMemory.class_of(view, _type), AiMemory.Owner.MINE):
		return false
	var x: int = tile.x * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
	var y: int = tile.y * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
	var ids: PackedInt32Array = PackedInt32Array([id])
	if lay:
		out.append(Command.lay_mine(view.player, ids, x, y))
	else:
		out.append(Command.move(view.player, ids, x, y))
	memory.spent()
	return true


func _job(id: int, duty: int, cell: int) -> void:
	_job_id.append(id)
	_job_duty.append(duty)
	_job_cell.append(cell)
	_job_until.append(-1)
