class_name PuffFx
extends RefCounted
## The small short puffs of `AirFx` (ADR 0027 sections 3 and 8, plan P149): the muzzle smoke of a
## shot and the exhaust of a vehicle, into a ring of `life.puff_slots` (24) slots of their own, each
## puff living at most `MAX_LIFE_MS` of match time. Drawn in `AirFx`'s `_draw` with the clouds.
## A SHOT of a weapon that fires a projectile (`weapon_projectile_speed` above 0: a cannon,
## artillery or a rocket; the rifle is hitscan and has none) leaves a grey `puff` at the point where
## `EffectsLayer` draws the flash: `muzzle_reach_px` px from the shooter towards the target, at the
## weapon's muzzle height. Like the flash it needs the shooter's tile seen. A shown vehicle with an
## `exhaust` point puffs `exhaust` from it, at the place its rig is drawn, in the tick it starts to
## drive (at least half a step in this tick, and not in the last), and, standing, every
## `puff_idle_ms` of its own (`LifeClock.pick` of its id, a function of the tick alone, so every
## device agrees). A puff
## outside the view rect `AirFx` passes is not born. `reduced` drops all of it: nothing is born and
## the puffs of the ring are taken out at once. View only; allocates nothing after `read` and
## `build` (the table of the rows is made when the rows change).

enum Style { MUZZLE, EXHAUST }
const KINDS: Array[StringName] = [&"puff", &"exhaust"]
const K_PUFF: int = 0
const K_EXHAUST: int = 1
## The emitter of a vehicle's sheet that the exhaust leaves from.
const EXHAUST_POINT: StringName = &"exhaust"
## A puff lives no longer than this (ADR 0027 section 3: the quota's bound).
const MAX_LIFE_MS: int = 500
## Salts of `LifeClock`, far from the other life layers' (RigLife 0x1.. to 0x4.., animations 0x5..,
## AirFx 0x6.., DamageFx and VehicleDamage 0x70.., HitFx 0x73.. to 0x75.., CollapseFx 0x76.. to
## 0x78..).
const SALT_LOOK: int = 0x7A000000
const SALT_EVERY: int = 0x7B000000
const SALT_PHASE: int = 0x7C000000

var ring: FxRing = FxRing.new()
var _exhaust: PackedInt32Array = PackedInt32Array()  ## Per type: the sheet's exhaust emitter or -1.
var _sheets: Array[IsoSheetDef] = []
var _rows_version: int = -1
var _ids: PackedInt32Array = PackedInt32Array()  ## The unit ids of the rows `_moving` is for.
var _moving: PackedByteArray = PackedByteArray()  ## Per row: 1 when it walked in the last tick.
var _every: PackedInt32Array = PackedInt32Array()  ## Per row: ms between idle puffs, 0 for none.
var _phase: PackedInt32Array = PackedInt32Array()  ## Per row: ms before its first idle puff.
var _idle_key: Vector2i = Vector2i(-1, -1)  ## The `puff_idle_ms` the two tables were made for.
var _reduced: bool = false


func _init() -> void:
	ring.setup(KINDS, Style.size())
	for kind: int in KINDS.size():
		ring.set_pass(kind, FxRing.CLOUD)


## Forgets the rows and empties the ring: a new match.
func forget() -> void:
	ring.clear()
	_rows_version = -1
	_ids = PackedInt32Array()
	_moving = PackedByteArray()
	_every = PackedInt32Array()
	_phase = PackedInt32Array()


## The exhaust emitter of each type's sheet: a vehicle's (a sheet of 16 directions), -1 for a
## building, a squad and a type with no sheet.
func build(snap: MatchSnapshot, sort: WorldSort) -> void:
	_exhaust.clear()
	_sheets.clear()
	for type: int in snap.type_ids.size():
		var sheet: IsoSheetDef = sort.sheet(snap.type_ids[type])
		_sheets.append(sheet)
		var found: int = -1
		if (
			sheet != null
			and not WorldSort.is_building(snap, type)
			and not sheet.counts.is_empty()
			and sheet.counts[0] == UnitLayer.DIRECTIONS
		):
			found = sheet.emitters.find(String(EXHAUST_POINT))
		_exhaust.append(found)


## Takes the ring's size and the looks of the two styles from `life`.
func read(life: LifeSettings) -> void:
	ring.size_to(life.puff_slots)
	ring.set_style(
		Style.MUZZLE,
		K_PUFF,
		float(clampi(life.muzzle_smoke_ms, 0, MAX_LIFE_MS)),
		life.muzzle_smoke_rise_px,
		life.muzzle_smoke_drift_px,
		life.muzzle_smoke_grow,
		life.muzzle_smoke_alpha,
		0.0
	)
	ring.set_style(
		Style.EXHAUST,
		K_EXHAUST,
		float(clampi(life.exhaust_ms, 0, MAX_LIFE_MS)),
		life.exhaust_rise_px,
		life.exhaust_drift_px,
		life.exhaust_grow,
		life.exhaust_alpha,
		0.0
	)


## Takes the muzzle smoke and the exhaust out of the ring.
func drop_all() -> void:
	ring.compact(-1.0, K_PUFF)
	ring.compact(-1.0, K_EXHAUST)


## Tells whether reduced effects are on: at the switch to on the ring is emptied of what reduced
## drops, once. Nothing of it is born while it stays on, so there is nothing to drop again.
func follow_reduced(on: bool) -> void:
	if on and not _reduced:
		drop_all()
	_reduced = on


## One tick: the muzzle smoke of its SHOTs the player can see, and the exhaust of the vehicles that
## started to drive or stand and are due. The puffs that lived out give their slots back first.
func emit(
	snap: MatchSnapshot,
	life: LifeSettings,
	view: Rect2,
	buildings: BuildingLayer,
	units: UnitLayer,
	world_to_local: Transform2D,
	local: int,
	reveal: bool
) -> void:
	ring.compact(LifeClock.tick_ms(snap.tick))
	_sync_rows(snap, life)
	var reduced: bool = life.reduced
	follow_reduced(reduced)
	var events: PackedInt32Array = snap.events
	var speeds: PackedInt32Array = snap.weapon_projectile_speed
	if not reduced and life.muzzle_smoke_ms > 0:
		for at: int in range(0, events.size(), World.EVENT_STRIDE):
			if events[at] != World.Event.SHOT:
				continue
			var weapon: int = events[at + 5]
			if weapon >= 0 and weapon < speeds.size() and speeds[weapon] > 0:
				_muzzle(snap, at, life, view, buildings, local, reveal)
	_drive(snap, life, view, units, world_to_local, reduced)


# The smoke of the SHOT at `at`: at the flash's point, when the shooter's tile is seen.
func _muzzle(
	snap: MatchSnapshot,
	at: int,
	life: LifeSettings,
	view: Rect2,
	buildings: BuildingLayer,
	local: int,
	reveal: bool
) -> void:
	var events: PackedInt32Array = snap.events
	if not reveal and not FogLayer.is_seen(snap, local, events[at + 2], events[at + 3]):
		return
	var weapon: int = events[at + 5]
	var sheet_px: float = 0.0
	if buildings != null and buildings.world_sort != null:
		sheet_px = buildings.world_sort.muzzle_px(weapon)
	var lift: Vector2 = Vector2(0.0, SpriteLift.muzzle_lift_px(snap.weapon_ids, weapon, sheet_px))
	var shooter: Vector2 = IsoProjection.ground_to_px(events[at + 2], events[at + 3]) - lift
	var target: Vector2 = IsoProjection.ground_to_px(events[at + 6], events[at + 7]) - lift
	var reach: float = life.muzzle_reach_px.get(
		snap.weapon_ids[weapon], life.muzzle_reach_default_px
	)
	var span: float = shooter.distance_to(target)
	var spot: Vector2 = shooter.lerp(target, 1.0 if span <= reach else reach / span)
	if view.has_point(spot):
		ring.add(
			Style.MUZZLE,
			spot,
			LifeClock.tick_ms(snap.tick),
			LifeClock.mix(events[at + 1], SALT_LOOK + snap.tick)
		)


# The exhaust of every shown vehicle that started to drive in this tick or stands and is due. The
# rows' moving flags are kept up to date for every row with an exhaust point, whatever is shown.
func _drive(
	snap: MatchSnapshot,
	life: LifeSettings,
	view: Rect2,
	units: UnitLayer,
	world_to_local: Transform2D,
	reduced: bool
) -> void:
	if units != null:
		units.sync_rows()  # The rigs and headings below are of this tick's rows.
	var ids: PackedInt32Array = snap.unit_id
	var types: PackedInt32Array = snap.type_index
	var speeds: PackedInt32Array = snap.type_speed
	var tick: int = snap.tick
	var born: float = LifeClock.tick_ms(tick)
	for row: int in ids.size():
		var point: int = _exhaust[types[row]]
		if point < 0:
			continue
		# Driving is UnitLayer's `walking` (P140b): at least half a step in the last tick. A creep
		# under half a step is neither driving nor a start. (A separation push is up to half a step
		# a tick or more and is not told apart: UnitLayer also needs an order, which is not read.)
		var dx: int = snap.pos_x[row] - snap.prev_pos_x[row]
		var dy: int = snap.pos_y[row] - snap.prev_pos_y[row]
		var step: int = dx * dx + dy * dy
		var speed: int = speeds[types[row]]
		var walking: bool = step > 0 and 4 * step >= speed * speed
		var started: bool = walking and _moving[row] == 0
		_moving[row] = 1 if walking else 0
		if reduced or life.exhaust_ms <= 0 or units == null or (walking and not started):
			continue
		var id: int = ids[row]
		if not started:  # Standing: puffs when its own cycle turns over.
			var every: int = _every[row]
			if (
				every <= 0
				or (
					AirFx.cycle(tick, _phase[row], every)
					== AirFx.cycle(tick - 1, _phase[row], every)
				)
			):
				continue
		if not units.is_shown(row):
			continue
		var sheet: IsoSheetDef = _sheets[types[row]]
		var rig: Node2D = units.rig(row)
		var base: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
		if rig != null:
			base = world_to_local * rig.global_position
		var dir: int = UnitLayer.frame_of(units.heading(row), sheet.counts[0])
		var spot: Vector2 = base + sheet.emitter_point(point, dir) * WorldSort.ART_SCALE
		if view.has_point(spot):
			ring.add(Style.EXHAUST, spot, born, LifeClock.mix(id, SALT_LOOK + tick))


# Keeps the per-row tables aligned with the snapshot's rows: when the rows change (or the idle
# times do) each unit that is still there keeps its flag, a new one starts at 0, and every row gets
# its idle cycle, `puff_idle_ms.x` to `.y` ms and a phase of its own by `LifeClock.pick` of its id
# (an `x` of 0 or less: no idle puffs). Allocates only then.
func _sync_rows(snap: MatchSnapshot, life: LifeSettings) -> void:
	var ids: PackedInt32Array = snap.unit_id
	if (
		snap.rows_version == _rows_version
		and ids.size() == _moving.size()
		and life.puff_idle_ms == _idle_key
	):
		return
	var next: PackedByteArray = PackedByteArray()
	next.resize(ids.size())
	_every.resize(ids.size())
	_phase.resize(ids.size())
	var low: int = life.puff_idle_ms.x
	for row: int in ids.size():
		var old: int = _ids.bsearch(ids[row])
		if old < _ids.size() and _ids[old] == ids[row]:
			next[row] = _moving[old]
		var every: int = 0
		if low > 0:
			every = (
				low + LifeClock.pick(ids[row], SALT_EVERY, maxi(life.puff_idle_ms.y - low, 0) + 1)
			)
		_every[row] = every
		_phase[row] = LifeClock.pick(ids[row], SALT_PHASE, every)
	_idle_key = life.puff_idle_ms
	_moving = next
	_ids = ids  # An alias: published snapshots are never written, so it cannot change under us.
	_rows_version = snap.rows_version
