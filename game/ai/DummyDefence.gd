class_name DummyDefence
extends RefCounted
## The dummy's defence (ADR 0020 section 4 "Defend", plan row P83b): it keeps its combat units at a
## guard point beside its Headquarters and sends them to an enemy that comes within
## `defend_radius_tiles` of one of its buildings, with ATTACK_MOVE and nothing else. It never
## attacks: a destination is always within the radius of one of its buildings. It reads the match
## only through the `PlayerView` of the think, uses no random number, and remembers only which of
## its own units it ordered to its current destination (ids, never a row).
##
## One run (`run`), after the economy of the same think:
## - A combat unit is a unit (no footprint) that moves, carries a weapon and does not harvest
##   (`is_combat`, read off the view's type tables): rifle squads and tanks, no harvester, no
##   building. A unit still in a queue is no row and gets its order the think after it spawns.
## - A threat is a seen row of another, non-neutral owner (a building too) whose centre is within
##   the radius of the centre of one of the player's buildings (the squared distance in
##   milli-tiles, the edge included). Of all threats the most pressing is the one nearest to its
##   nearest building, ties to the lower row. A ghost (last-seen memory) is not a row and never a
##   threat, and a fogged enemy is not seen.
## - The destination is that threat's position, else the guard point: the Headquarters' centre (the
##   first building's when there is no Headquarters) moved by `guard_offset_tiles`. With no
##   building at all there is no destination and nothing is sent.
## - A combat unit is the defence's to order when it is IDLE, or ATTACK_MOVE and was sent by the
##   defence (an id it remembers). Any other unit (a MOVE or ATTACK that a player gave, a walk to
##   a rally point) keeps its order and is forgotten. A unit the defence ordered to the current
##   destination keeps that order, on its way or arrived, until the destination changes: the
##   situation changed when a threat appears, moves to another point, dies or leaves the radius.
##   Every other unit it may order gets ATTACK_MOVE to the destination, in one Command (a further
##   one per `Command.MAX_UNITS` ids), so a still enemy costs one order, not one per think.

## Enemy-row-by-building distance tests of the last run (tests count the work, ADR 0020 section 4):
## at most the seen rows times the player's buildings.
var tests: int = 0

var _player: int = 0
## The radius and the guard offset, in milli-tiles.
var _radius: int = 0
var _guard: Vector2i = Vector2i.ZERO
## The destination the units in `_held` were last ordered to, and their ids, ascending.
var _dest: Vector2i = Vector2i.ZERO
var _held: PackedInt32Array = PackedInt32Array()


## A defence for `player_id` driven by `def`, which it copies and does not keep. Each axis of the
## offset is cut to half the radius, so the guard point (at most that far along each axis) is
## within the radius of the Headquarters whatever the def says.
static func create(def: AiDef, player_id: int) -> DummyDefence:
	var defence: DummyDefence = DummyDefence.new()
	var radius: int = maxi(def.defend_radius_tiles, 0)
	defence._player = player_id
	defence._radius = radius * PlayerView.MILLI_PER_TILE
	var half: int = radius >> 1
	var offset: Vector2i = def.guard_offset_tiles
	defence._guard = Vector2i(clampi(offset.x, -half, half), clampi(offset.y, -half, half))
	defence._guard *= PlayerView.MILLI_PER_TILE
	return defence


## Whether units of `type` are combat units: they move, carry a weapon and do not harvest. A
## building (no speed) and a harvester are not.
static func is_combat(view: PlayerView, type: int) -> bool:
	return (
		view.type_speed[type] > 0 and view.type_weapon[type] >= 0 and view.type_harvest[type] == 0
	)


## One run on `view`: appends the ATTACK_MOVE Commands of this think to `out`. `hq_type` is the type
## index of the Headquarters (-1 for none).
func run(view: PlayerView, hq_type: int, out: Array[Command]) -> void:
	tests = 0
	var xs: PackedInt32Array = PackedInt32Array()
	var ys: PackedInt32Array = PackedInt32Array()
	var units: PackedInt32Array = PackedInt32Array()
	# 1 plus the index of the Headquarters among the buildings, 0 for none.
	var hq: int = 0
	for row: int in view.own_rows:
		var type: int = view.row_type(row)
		if view.type_foot_w[type] > 0:
			var at: Vector2i = view.row_pos(row)
			if type == hq_type and hq == 0:
				hq = xs.size() + 1
			xs.append(at.x)
			ys.append(at.y)
		elif is_combat(view, type):
			units.append(row)
	if xs.is_empty():
		_held = PackedInt32Array()
		return
	var threat: int = _threat(view, xs, ys)
	var anchor: int = maxi(hq - 1, 0)
	var dest: Vector2i = Vector2i(xs[anchor], ys[anchor]) + _guard
	if threat >= 0:
		dest = view.row_pos(threat)
	_order(view, units, dest, out)


## The row of the most pressing threat (see the header), -1 when no seen enemy row is within the
## radius of a building at (`xs`, `ys`).
func _threat(view: PlayerView, xs: PackedInt32Array, ys: PackedInt32Array) -> int:
	var found: int = -1
	var least: int = _radius * _radius + 1
	for row: int in view.seen_rows:
		if view.row_owner(row) < 1:
			continue
		var at: Vector2i = view.row_pos(row)
		for building: int in xs.size():
			tests += 1
			var dx: int = at.x - xs[building]
			var dy: int = at.y - ys[building]
			var distance: int = dx * dx + dy * dy
			if distance < least:
				least = distance
				found = row
	return found


## Orders the combat units `units` (rows) to `dest` as the header says, and remembers them.
func _order(view: PlayerView, units: PackedInt32Array, dest: Vector2i, out: Array[Command]) -> void:
	var send: PackedInt32Array = PackedInt32Array()
	var held: PackedInt32Array = PackedInt32Array()
	for row: int in units:
		var id: int = view.row_id(row)
		var order: int = view.row_order(row)
		var known: bool = _is_held(id)
		if order != PlayerView.Order.IDLE and not (known and order == PlayerView.Order.ATTACK_MOVE):
			continue
		held.append(id)
		if not known or _dest != dest:
			send.append(id)
	for first: int in range(0, send.size(), Command.MAX_UNITS):
		var ids: PackedInt32Array = send.slice(first, first + Command.MAX_UNITS)
		out.append(Command.attack_move(_player, ids, dest.x, dest.y))
	_dest = dest
	_held = held


## Whether the defence ordered unit `id` to its current destination (`_held` is ascending).
func _is_held(id: int) -> bool:
	var at: int = _held.bsearch(id)
	return at < _held.size() and _held[at] == id
