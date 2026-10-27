class_name StrikeLandings
extends RefCounted
## Finds the ruptures that land between one published snapshot and the next (plan P112b, ADR 0023
## section 10), from the snapshot alone. A player's `strike_tick` is the tick its rupture lands on,
## 0 while none is in the air; the sim clears it in the landing step and leaves the point in
## `strike_x` and `strike_y`. So a player whose `strike_tick` is not what the last `update` saw has
## landed what it saw pending, at the point it was fired at. The point is kept from the sight of
## the pending strike, not read at the landing: a rupture fired again at once changes it.
## `update` is called once per tick (the runner's `ticked`), as the effects read the events: a
## frame that plays several catch-up ticks still shows each tick's snapshot to its handler. A new
## match starts the memory afresh, and a rupture already in the air at the first sight is
## remembered and lands later like any other. Nothing here allocates after the first call.

var _tick: PackedInt32Array = PackedInt32Array()  ## Per player: the landing tick last seen, or 0.
var _x: PackedInt32Array = PackedInt32Array()  ## Per player: the point of that landing, milli.
var _y: PackedInt32Array = PackedInt32Array()
var _sight: PackedByteArray = PackedByteArray()  ## Per player: 1 when the viewer saw that point.
var _found: PackedInt32Array = PackedInt32Array()  ## The last update's landings: x, y each.
var _found_sight: PackedByteArray = PackedByteArray()  ## The last update's, 1 for each seen.
var _count: int = 0
var _serial: int = -1


## Reads `snap` and returns how many ruptures landed since the snapshot `update` saw before it;
## `point(index)` gives each one's ground point, players ascending. `viewer` is the player whose
## sight `was_seen` tells; a player the fog does not cover (0) sees every point.
func update(snap: MatchSnapshot, viewer: int) -> int:
	var now: PackedInt32Array = snap.strike_tick
	if snap.match_serial != _serial or _tick.size() != now.size():
		_serial = snap.match_serial
		_tick = _zeros(now.size())
		_x = _zeros(now.size())
		_y = _zeros(now.size())
		_found = _zeros(now.size() * 2)
		_sight.resize(now.size())
		_sight.fill(0)
		_found_sight.resize(now.size())
		_found_sight.fill(0)
	_count = 0
	for player: int in now.size():
		var landing: int = now[player]
		if landing == _tick[player]:
			if landing != 0:  # Still in the air: this snapshot's fog is the latest ground seen.
				_sight[player] = _saw(snap, viewer, _x[player], _y[player])
			continue
		if _tick[player] != 0:
			_found[_count * 2] = _x[player]
			_found[_count * 2 + 1] = _y[player]
			_found_sight[_count] = _sight[player]
			_count += 1
		if landing != 0:
			_x[player] = snap.strike_x[player]
			_y[player] = snap.strike_y[player]
			_sight[player] = _saw(snap, viewer, _x[player], _y[player])
		_tick[player] = landing
	return _count


## The ground point of landing `index` of the last `update`, milli-tiles.
func point(index: int) -> Vector2i:
	return Vector2i(_found[index * 2], _found[index * 2 + 1])


## Whether the viewer saw the point of landing `index` of the last `update` in the last snapshot the
## rupture was still in the air in, before the landing step took any sight with it.
func was_seen(index: int) -> bool:
	return _found_sight[index] == 1


## The radius, milli-tiles, of the first strike type of kind RUPTURE in the tables of `snap`: the
## type `Strike.rupture_type` reads in the sim, whose radius a landing and its warning have. 0 for
## a roster with none.
static func rupture_radius(snap: MatchSnapshot) -> int:
	var kinds: PackedInt32Array = snap.type_strike_kind
	for type: int in kinds.size():
		if kinds[type] == Strike.Kind.RUPTURE:
			return snap.type_strike_radius[type]
	return 0


static func _saw(snap: MatchSnapshot, viewer: int, x: int, y: int) -> int:
	return 1 if FogLayer.is_seen(snap, viewer, x, y) else 0


static func _zeros(size: int) -> PackedInt32Array:
	var made: PackedInt32Array = PackedInt32Array()
	made.resize(size)
	return made
