class_name RigLife
extends RefCounted
## The life state of the rigs of one layer (ADR 0027 section 3, plan P136). `UnitLayer` and
## `BuildingLayer` each carry one: the layer feeds it the `SHOT` records of a tick (`shot`), reads
## the offsets of the kicks that run now (`advance`, `turret_offset`, `hull_offset`) and writes them
## to its sprites. Nothing here reads the World, a node or a clock: an offset is a function of the
## shot's tick, the match time (`LifeClock`) and `LifeSettings`.
## A kick is the recoil of a turret (a defence's head): it kicks back along the aim, away from the
## target, peaks at `recoil_out_ms` and is on its mount again at `recoil_back_ms` (match time since
## the shot). A weapon with `rock_px` also rocks the hull, and the turret rides with it. The aim is
## the screen direction from shooter to target as the event holds them (the turret's eased angle
## depends on the frame rate), the size is quantised to 0.5 px so a sprite is written only when it
## changes, and a kick never runs backwards: its age is the furthest it has been (the clock can
## step back by a tick when WORKER mode restarts alpha after a pause).
## The kicks live in a fixed table of `kick_slots` keyed by unit id, sized in `setup`: a shot of a
## rig that kicks restarts its slot, and one that finds the table full kicks nothing.

const QUANT_PX: float = 0.5  ## Offsets are written in steps of this many world px.

var settings: LifeSettings = null
## Sprite writes the layers made for life since `setup` (ADR 0027 section 9's hook).
var writes: int = 0

var _serial: int = -1  ## match_serial the table holds kicks of.
var _count: int = 0  ## Slots in use; slot `i` below it is a kick.
var _id: PackedInt32Array = PackedInt32Array()
var _born: PackedInt32Array = PackedInt32Array()  ## Tick of the SHOT.
var _back: PackedVector2Array = PackedVector2Array()  ## Unit vector away from the target, screen.
var _recoil: PackedFloat32Array = PackedFloat32Array()  ## The turret's own kick at its peak, px.
var _rock: PackedFloat32Array = PackedFloat32Array()  ## The hull's, and the turret's with it.
var _age: PackedFloat32Array = PackedFloat32Array()  ## The furthest age shown, ms.
var _turret: PackedVector2Array = PackedVector2Array()  ## This frame's offsets, quantised.
var _hull: PackedVector2Array = PackedVector2Array()
var _done: PackedByteArray = PackedByteArray()  ## 1 once the kick is over or its rig is gone.


## Sizes the table from `new_settings.kick_slots` and empties it. Not on the frame path.
func setup(new_settings: LifeSettings) -> void:
	settings = new_settings
	var slots: int = maxi(new_settings.kick_slots, 1)
	_id.resize(slots)
	_born.resize(slots)
	_back.resize(slots)
	_recoil.resize(slots)
	_rock.resize(slots)
	_age.resize(slots)
	_turret.resize(slots)
	_hull.resize(slots)
	_done.resize(slots)
	_serial = -1
	_count = 0
	writes = 0


## Empties the table when `serial` is another match's: a new match starts with no kick.
func follow(serial: int) -> void:
	if serial != _serial:
		_serial = serial
		_count = 0


## The kicks in the table now (some may be over: `advance` marks them and `sweep` drops them).
func count() -> int:
	return _count


## The unit id of kick `slot`.
func id_at(slot: int) -> int:
	return _id[slot]


## The furthest age kick `slot` has been shown at, ms: never below 0, never going back.
func age_at(slot: int) -> float:
	return _age[slot]


## Where the turret stands off its mount now, world px, in the state `advance` left it. Zero when
## the kick is over.
func turret_offset(slot: int) -> Vector2:
	return _turret[slot]


## Where the hull stands off its rest, world px. Zero for a weapon with no `rock_px`.
func hull_offset(slot: int) -> Vector2:
	return _hull[slot]


## Starts the kick of the SHOT record at `snap.events[at]` ([SHOT, shooter id, shooter x, shooter y,
## target id, weapon, target x, target y]) for the shooter, born at `snap.tick`. The caller has
## decided that the player may see it (fog) and that the shooter has a turret or a head; `rock`
## says whether the hull rocks too (a vehicle: yes, a defence has no hull to rock). Nothing is
## started for a weapon without a row, a shot with no aim (both ends on one point) or a full table.
func shot(snap: MatchSnapshot, at: int, rock: bool) -> void:
	var events: PackedInt32Array = snap.events
	var weapon: int = events[at + 5]
	if weapon < 0 or weapon >= snap.weapon_ids.size():
		return
	var weapon_id: StringName = snap.weapon_ids[weapon]
	var recoil: float = settings.recoil_px.get(weapon_id, 0.0)
	var rocking: float = settings.rock_px.get(weapon_id, 0.0) if rock else 0.0
	if recoil <= 0.0 and rocking <= 0.0:
		return
	var aim: Vector2 = (
		IsoProjection.ground_to_px(events[at + 6], events[at + 7])
		- IsoProjection.ground_to_px(events[at + 2], events[at + 3])
	)
	if aim.length_squared() <= 0.0:
		return
	var slot: int = _slot_of(events[at + 1])
	if slot < 0:
		return
	_born[slot] = snap.tick
	_back[slot] = -aim.normalized()
	_recoil[slot] = maxf(recoil, 0.0)
	_rock[slot] = maxf(rocking, 0.0)
	_age[slot] = 0.0
	_turret[slot] = Vector2.ZERO
	_hull[slot] = Vector2.ZERO
	_done[slot] = 0


## Brings every kick to match time `now_ms` (`LifeClock.ms`) and returns how many there are. Each
## kick's offsets are then in `turret_offset` and `hull_offset`; one that has run its course reads
## zero and is marked, so the layer writes that last zero and `sweep` drops it.
func advance(now_ms: float) -> int:
	var out_ms: float = float(maxi(settings.recoil_out_ms, 1))
	var back_ms: float = maxf(float(settings.recoil_back_ms), out_ms + 1.0)
	for slot: int in _count:
		var age: float = maxf(_age[slot], LifeClock.age_ms(now_ms, LifeClock.tick_ms(_born[slot])))
		_age[slot] = age
		if age >= back_ms:
			_done[slot] = 1
		var curve: float = _curve(age, out_ms, back_ms)
		_turret[slot] = _quantised(_back[slot], (_recoil[slot] + _rock[slot]) * curve)
		_hull[slot] = _quantised(_back[slot], _rock[slot] * curve)
	return _count


## Marks kick `slot` over although its time is not: its rig is gone, or has nothing to move.
func end(slot: int) -> void:
	_done[slot] = 1


## Drops the kicks marked over. Call it after the layer has written the frame, so a kick's last
## zero reaches its sprite first. Moves the last kick into the freed slot, so slots change.
func sweep() -> void:
	var slot: int = 0
	while slot < _count:
		if _done[slot] == 0:
			slot += 1
			continue
		_count -= 1
		if slot != _count:
			_id[slot] = _id[_count]
			_born[slot] = _born[_count]
			_back[slot] = _back[_count]
			_recoil[slot] = _recoil[_count]
			_rock[slot] = _rock[_count]
			_age[slot] = _age[_count]
			_turret[slot] = _turret[_count]
			_hull[slot] = _hull[_count]
			_done[slot] = _done[_count]


## The slot of unit `id`'s kick, a free one when it has none, -1 when the table is full.
func _slot_of(id: int) -> int:
	for slot: int in _count:
		if _id[slot] == id:
			return slot
	if _count >= _id.size():
		return -1
	_id[_count] = id
	_count += 1
	return _count - 1


## The share of the peak at `age` ms: 0 at the shot, 1 at `out_ms`, then an ease-out back to 0 at
## `back_ms` (fast at first, so the turret snaps back and settles), 0 from there on.
static func _curve(age: float, out_ms: float, back_ms: float) -> float:
	if age >= back_ms:
		return 0.0
	if age <= out_ms:
		return age / out_ms
	var left: float = 1.0 - (age - out_ms) / (back_ms - out_ms)
	return left * left


## `size` px along `direction`, rounded to QUANT_PX steps.
static func _quantised(direction: Vector2, size: float) -> Vector2:
	return direction * (roundf(size / QUANT_PX) * QUANT_PX)
