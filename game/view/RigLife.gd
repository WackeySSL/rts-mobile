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
## Idle life (P140, P140b): `shake_offset`, `look_side` and `sweep_offset` are functions of the unit
## id and the match time alone, drawn with `LifeClock.mix`, so two runs, a replay and a second
## viewer see the same pose at the same tick. The layer says who stands (a vehicle that stands with
## no target looks around, a complete, online defence with none sweeps) and who drives (a vehicle
## that drove half a step or more in the last tick on an order rumbles; a standing one never shakes;
## a creep under half a step, or a push on a unit with no order, does neither), and `idle_step` and
## `sweep_step` bring the `Idle` record of one rig up to the layer's idle clock and say what
## changed, for the layer to write. The idle clock (`idle_clock`) is the match time that never goes
## back, so a WORKER resume, whose alpha restarts at 0, does not play a pose backwards. A record
## holds the answer and the stretch of match time it holds for, so a rig is asked again only outside
## it: two compares, not a hash.
## Squad poses (P142, ADR 0027 section 5): `travel_step` and `walk_frame` turn the ground a squad
## covered into a walk frame (the cadence follows the speed and stops with the squad), `pose_step`
## and `pose_idle` give the idle frame of a squad that has stood a while, and `Pose` is the record
## of the pose a rig's Hull shows. `note_shots` is the loop over a tick's `SHOT` records that both
## layers share.

const QUANT_PX: float = 0.5  ## Offsets are written in steps of this many world px.
## Salts of `LifeClock.mix` for the idle life: one base for each effect, the draws of an id at the
## base and just above it, those of step or cycle `n` after them. The bases are far apart.
const SALT_SHAKE: int = 0x10000000
const SALT_LOOK: int = 0x20000000
const SALT_SWEEP: int = 0x30000000
## What `idle_step` says changed: the rumble offset (the layer writes the Hull and the Turret) and
## the look (it writes the turret's region).
const CHANGED_SHAKE: int = 1
const CHANGED_LOOK: int = 2
const SALT_POSE: int = 0x40000000  ## The idle pose of a squad (P142).
## The poses a squad's Hull can show, and the sheet part each one draws.
const POSE_HULL: int = 0
const POSE_WALK: int = 1
const POSE_IDLE: int = 2
const POSE_PARTS: Array[StringName] = [&"hull", &"walk", &"idle"]
## A row of the layer's walk table (`travel_step`): the sum of the ground covered, in milli, kept
## below the stride; the length of the last tick's step; the tick the row was last brought to; and
## the phase of the id's walk, so a squad does not step in lockstep with its neighbours; and the
## share of the last step already shown in this tick, so a frame never steps back (`walk_frame`).
const WALK_INTS: int = 5
const W_SUM: int = 0
const W_STEP: int = 1
const W_TICK: int = 2
const W_PHASE: int = 3
const W_SHOWN: int = 4

var life: LifeSettings = null  ## The numbers (`@export var life` of the layer that carries it).
## Sprite writes the layers made for life since `setup` (ADR 0027 section 9's hook).
var writes: int = 0
## The match times, ms, between which the answer of the last `shake_offset`, `look_side` or
## `sweep_offset` holds: [span_from, span_to). A layer keeps them beside the answer and asks again
## only outside them, so an idle rig costs two compares a frame, not a hash.
var span_from: float = 0.0
var span_to: float = 0.0

var _serial: int = -1  ## match_serial the table holds kicks of.
var _idle_ms: float = 0.0  ## The idle clock: the furthest match time `idle_clock` has been asked.
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


## The idle state of one rig or head, held by its layer and made with it: what is shown now
## (`shake`, `look`, `sweep`) and, for each, the stretch of match time [from, to) its last answer
## holds for. A `to` below 0 means "never asked": the rig has not stood or driven yet.
class Idle:
	extends RefCounted

	var shake: Vector2 = Vector2.ZERO  ## World px, Hull and Turret together.
	var look: int = 0  ## Frames the turret shows aside of its aim: -1, 0 or 1.
	var sweep: int = 0  ## Frames a head shows off its aim.
	var sweep_want: int = 0  ## What `sweep_offset` last said for the stretch of `sweep_from`/`to`.
	var turns: bool = false  ## Whether the rig has a turret of 16 frames to look with.
	## Whether the record may differ from rest: `idle_step` has settled a standing or driving
	## vehicle since the last `reset` or calm. A layer calls `idle_step` for a rig that neither
	## stands nor drives only while this is set, so a firing rig costs one flag.
	var live: bool = false
	var shake_from: float = 0.0
	var shake_to: float = -1.0
	var look_from: float = 0.0
	var look_to: float = -1.0
	var sweep_from: float = 0.0
	var sweep_to: float = -1.0
	## A squad's idle pose (P142): the idle-clock time it began to stand (-1 while it walks, fights
	## or is new), the idle frame it shows (-1 none) and the stretch [pose_from, pose_to) that
	## answer holds for.
	var still_ms: float = -1.0
	var pose: int = -1
	var pose_from: float = 0.0
	var pose_to: float = -1.0

	## Back to a rig at rest that has never been idle (a rig out of the pool, a new head).
	func reset() -> void:
		live = false
		shake = Vector2.ZERO
		look = 0
		sweep = 0
		shake_to = -1.0
		look_to = -1.0
		sweep_to = -1.0
		still_ms = -1.0
		pose = -1
		pose_to = -1.0


## The pose a squad rig's Hull shows (P142): one of the POSE_ constants, the base of the sheet part
## for the hull's direction (`WorldSort.base_of`) and the frame within it, so a frame change is a
## table read. `dress` fills what the sheet says, once per dressing: the Hull's offset in each pose
## (the poses' anchors differ by a pixel or two, and `show_base` writes only the region), the frames
## of each and the travel that one walk frame takes. `quarter` 0 means a rig with no poses.
class Pose:
	extends RefCounted

	var shown: int = POSE_HULL
	## The atlas base of each pose for the hull's direction.
	var bases: PackedInt32Array = PackedInt32Array([-1, -1, -1])
	var frame: int = 0
	var stride: int = 0  ## `stride_milli` of the sheet: the walk table's sum stays below it.
	var quarter: int = 0  ## Milli of travel per walk frame: `stride_milli` over the walk frames.
	var offsets: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var frames: PackedInt32Array = PackedInt32Array([1, 1, 1])

	## The hull standing, at `hull_base`, with no poses until `dress`.
	func reset(hull_base: int) -> void:
		shown = POSE_HULL
		bases[POSE_HULL] = hull_base
		bases[POSE_WALK] = -1
		bases[POSE_IDLE] = -1
		frame = 0
		stride = 0
		quarter = 0

	## Reads the three parts of `sheet`, an atlas at `bake_scale`. False (and no poses) for a sheet
	## without a `walk` and an `idle` part, a stride, or a stride that the walk frames do not divide.
	@warning_ignore("integer_division")
	func dress(sheet: IsoSheetDef, bake_scale: float) -> bool:
		quarter = 0
		stride = 0
		for pose: int in POSE_PARTS.size():
			var part: StringName = POSE_PARTS[pose]
			if not sheet.has_part(part):
				return false
			var texels: Vector2 = IsoAtlas.texels_per_px(
				sheet.frame_size(part), bake_scale * IsoAtlas.part_factor(part)
			)
			offsets[pose] = -Vector2(sheet.origin(part)) * texels
			frames[pose] = sheet.frame_count(part)
		var walk: int = frames[POSE_WALK]
		if sheet.stride_milli <= 0 or walk < 2 or sheet.stride_milli % walk != 0:
			return false
		stride = sheet.stride_milli
		quarter = stride / walk
		return true


## Takes the numbers `new_life` and sizes the table from its `kick_slots`, empty. Not on the frame
## path.
func setup(new_life: LifeSettings) -> void:
	life = new_life
	var slots: int = maxi(new_life.kick_slots, 1)
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
	_idle_ms = 0.0
	writes = 0


## Empties the table when `serial` is another match's: a new match starts with no kick, and the
## idle clock starts again.
func follow(serial: int) -> void:
	if serial != _serial:
		_serial = serial
		_count = 0
		_idle_ms = 0.0


## Notes the kicks of one tick's SHOT records, once per tick (the layer's `ticked`): for each SHOT
## that `accepts.call(snap, at)` lets through (the layer's fog and part rules), `shot` starts a
## kick. `rock` says whether the hull rocks too. `accepts` is made once by the layer.
func note_shots(snap: MatchSnapshot, rock: bool, accepts: Callable) -> void:
	follow(snap.match_serial)
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.SHOT and accepts.call(snap, at):
			shot(snap, at, rock)


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
	var recoil: float = life.recoil_px.get(weapon_id, 0.0)
	var rocking: float = life.rock_px.get(weapon_id, 0.0) if rock else 0.0
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
	var out_ms: float = float(maxi(life.recoil_out_ms, 1))
	var back_ms: float = maxf(float(life.recoil_back_ms), out_ms + 1.0)
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


## The idle clock of this frame, ms: the match time of `snap` at `alpha`, or the furthest it has
## been in this match if that is later. The runner restarts alpha at 0 in the first frame after a
## pause or a background (WORKER mode), so the match time can step back by a tick; a pose that is
## a function of it would play backwards. This clock stays where it was until the match catches up.
func idle_clock(snap: MatchSnapshot, alpha: float) -> float:
	follow(snap.match_serial)
	_idle_ms = maxf(_idle_ms, LifeClock.ms(snap, alpha))
	return _idle_ms


## Brings the idle record `state` of vehicle `id` to idle-clock time `now_ms` and returns what
## changed (CHANGED_SHAKE, CHANGED_LOOK, or 0), for the layer to write. `stands`: the vehicle stood
## still in the last tick, has no target and `reduced` is off; it looks aside (only if
## `state.turns`) and never shakes. `driving`: it drove half a step in the last tick on an order and
## `reduced` is off; it rumbles and does not look. `seen`: it is shown and in view. A rig that does
## neither goes back to rest, seen or not, and a rig that stops driving loses its rumble at once. A
## rig that is not seen is left as it is, and rests for one step when it is seen again, like one
## that has just begun: its phase spreads those first steps over `drive_shake_ms`, so a column that
## sets off together, or a camera that pans back to a convoy, does not write every sprite in one
## frame.
func idle_step(state: Idle, id: int, now_ms: float, stands: bool, driving: bool, seen: bool) -> int:
	var changed: int = 0
	if not driving:
		if state.shake != Vector2.ZERO:
			state.shake = Vector2.ZERO
			changed = CHANGED_SHAKE
		state.shake_to = -1.0
	if not stands:
		if state.look != 0:
			state.look = 0
			changed |= CHANGED_LOOK
		state.look_to = -1.0
	if not (stands or driving):
		state.live = false
		return changed
	if not seen:
		state.shake_to = -1.0
		return changed
	state.live = true
	if driving and (now_ms < state.shake_from or now_ms >= state.shake_to):
		var settled: bool = state.shake_to >= 0.0
		var shake: Vector2 = shake_offset(id, now_ms)
		state.shake_from = span_from
		state.shake_to = span_to
		if settled and shake != state.shake:
			state.shake = shake
			changed |= CHANGED_SHAKE
	if stands and state.turns and (now_ms < state.look_from or now_ms >= state.look_to):
		var side: int = look_side(id, now_ms)
		state.look_from = span_from
		state.look_to = span_to
		if side != state.look:
			state.look = side
			changed |= CHANGED_LOOK
	return changed


## Brings the sweep of the head record `state` of defence `id` to idle-clock time `now_ms`: the
## frames off its aim it should show (0 when not `active`), cached for the stretch they hold.
## True when that is not what the head showed, which it now does (`state.sweep`).
func sweep_step(state: Idle, id: int, now_ms: float, active: bool) -> bool:
	var want: int = 0
	if active:
		if now_ms < state.sweep_from or now_ms >= state.sweep_to:
			state.sweep_want = sweep_offset(id, now_ms)
			state.sweep_from = span_from
			state.sweep_to = span_to
		want = state.sweep_want
	if want == state.sweep:
		return false
	state.sweep = want
	return true


## The engine rumble of driving vehicle `id` at match time `now_ms`, world px for its Hull and
## Turret together: each axis is a whole number of QUANT_PX steps, at most `drive_shake_px` away
## from rest, drawn afresh by `mix(id, step)` once per `drive_shake_ms`. The step counts from a
## phase of the id's own, so the vehicles of a column do not all write in one frame. Zero when
## `drive_shake_px` is below one step. The answer holds for the step: `span_from` and `span_to` say
## for how long.
func shake_offset(id: int, now_ms: float) -> Vector2:
	_forever()
	var reach: int = floori(life.drive_shake_px / QUANT_PX)
	if reach <= 0 or life.drive_shake_ms <= 0:
		return Vector2.ZERO
	var phase: int = LifeClock.pick(id, SALT_SHAKE, life.drive_shake_ms)
	var step: int = floori((now_ms + float(phase)) / float(life.drive_shake_ms))
	span_from = float(step * life.drive_shake_ms - phase)
	span_to = span_from + float(life.drive_shake_ms)
	var span: int = 2 * reach + 1
	var x: int = LifeClock.pick(id, SALT_SHAKE + 2 * step + 1, span) - reach
	var y: int = LifeClock.pick(id, SALT_SHAKE + 2 * step + 2, span) - reach
	return Vector2(float(x), float(y)) * QUANT_PX


## Which way the turret of vehicle `id` looks at match time `now_ms`: 0 straight on, -1 or 1 one
## frame aside, for `look_ms` once in each cycle. A cycle lasts `look_every_ms` plus up to
## `look_every_spread_ms` (6 to 10 s by default), by `mix(id, ...)` and fixed for the id, and starts
## from a phase of the id's own. The window starts in the first half of the spare time of its cycle,
## drawn per cycle, so two windows are never back to back, and the side is drawn per cycle too.
## 0 for a `look_ms` of 0 or one that is not below `look_every_ms`. The answer holds for the stretch
## of the cycle it is in (before the window, the window, after it): `span_from` and `span_to`.
func look_side(id: int, now_ms: float) -> int:
	_forever()
	var window: int = life.look_ms
	if window <= 0 or window >= life.look_every_ms:
		return 0
	var period: int = life.look_every_ms
	period += LifeClock.pick(id, SALT_LOOK, maxi(life.look_every_spread_ms, 0) + 1)
	var phase: int = LifeClock.pick(id, SALT_LOOK + 1, period)
	var at: int = floori(now_ms) + phase
	var cycle: int = floori(float(at) / float(period))
	var start: int = LifeClock.pick(id, SALT_LOOK + 3 * cycle + 2, ((period - window) >> 1) + 1)
	var begins: int = cycle * period - phase  # The cycle's first ms, in match time.
	var into: int = at - cycle * period
	if into < start:
		span_from = float(begins)
		span_to = float(begins + start)
		return 0
	if into < start + window:
		span_from = float(begins + start)
		span_to = float(begins + start + window)
		return 2 * LifeClock.pick(id, SALT_LOOK + 3 * cycle + 3, 2) - 1
	span_from = float(begins + start + window)
	span_to = float(begins + period)
	return 0


## How many frames the head of defence `id` stands off its last aim at match time `now_ms`, within
## `sweep_frames` either way: it holds each frame `sweep_ms` and walks 0, 1 .. reach, back through 0
## to -reach and home, so a sweep is slow and one frame at a time. The walk starts from a phase of
## the id's own. 0 for a `sweep_frames` or `sweep_ms` of 0. The answer holds for the frame:
## `span_from` and `span_to`.
func sweep_offset(id: int, now_ms: float) -> int:
	_forever()
	var reach: int = life.sweep_frames
	if reach <= 0 or life.sweep_ms <= 0:
		return 0
	var steps: int = 4 * reach
	var phase: int = LifeClock.pick(id, SALT_SWEEP, steps * life.sweep_ms)
	var hold: int = floori(float(floori(now_ms) + phase) / float(life.sweep_ms))
	span_from = float(hold * life.sweep_ms - phase)
	span_to = span_from + float(life.sweep_ms)
	var walk: int = hold % steps
	if walk <= reach:
		return walk
	if walk <= 3 * reach:
		return 2 * reach - walk
	return walk - steps


## Brings row `at` of the walk table (`WALK_INTS` ints a row) to snapshot tick `tick`, once for
## each new tick: the last tick's step joins the sum (kept below `stride`, the frame is periodic in
## it), nothing of the new tick is shown yet, and this tick's step is the straight-line length of
## the move `moved_sq` (the squared milli moved, `FixedMath.isqrt` as `Movement` has it, never
## |dx| + |dy|, which walks a diagonal sqrt(2) too fast), or 0 for a squad that does not walk. A
## tick skipped by a catch-up loses its step: a phase hiccup, never a slide.
static func travel_step(
	walk: PackedInt32Array, at: int, tick: int, moved_sq: int, walking: bool, stride: int
) -> void:
	if walk[at + W_TICK] == tick:
		return
	walk[at + W_SUM] = (walk[at + W_SUM] + walk[at + W_STEP]) % stride
	walk[at + W_SHOWN] = 0
	walk[at + W_STEP] = FixedMath.isqrt(moved_sq) if walking else 0
	walk[at + W_TICK] = tick


## The walk frame of row `at` of the walk table at `alpha` into its tick: `floor((travel + phase) /
## quarter) mod frames`, the travel being the sum plus the share of the last step that `alpha`
## reaches, never less than the share already shown in this tick (`W_SHOWN`): a WORKER resume
## restarts alpha at 0 inside a tick, and the feet do not step back. A tick's end meets the next
## tick's start.
@warning_ignore("integer_division")
static func walk_frame(
	walk: PackedInt32Array, at: int, alpha: float, quarter: int, frames: int
) -> int:
	var into: int = maxi(walk[at + W_SHOWN], int(alpha * float(walk[at + W_STEP])))
	walk[at + W_SHOWN] = into
	return (walk[at + W_SUM] + into + walk[at + W_PHASE]) / quarter % frames


## Brings the pose record `state` of squad `id` to idle-clock time `now_ms` and returns its idle
## frame (0 to `frames` - 1), -1 for the standing hull. A `standing` squad (it does not walk and has
## no target) is asked again only outside the stretch its last answer holds for; it began to stand
## at `still_at`, the start of the first tick it stood in (`LifeClock.tick_ms`, so the windows do
## not depend on the frame that saw it first). Any other squad goes back to the hull and forgets.
func pose_step(
	state: Idle, id: int, now_ms: float, still_at: float, standing: bool, frames: int
) -> int:
	if not standing:
		state.still_ms = -1.0
		state.pose = -1
		state.pose_to = -1.0
		return -1
	if state.still_ms < 0.0:
		state.still_ms = still_at
		state.pose_to = -1.0
	if now_ms < state.pose_from or now_ms >= state.pose_to:
		state.pose = pose_idle(id, state.still_ms, now_ms, frames)
		state.pose_from = span_from
		state.pose_to = span_to
	return state.pose


## Which idle frame squad `id` shows at match time `now_ms`, standing since `still_ms`: -1 for the
## first `idle_after_ms`, then one window of `idle_ms` in each cycle of `idle_every_ms` plus up to
## `idle_every_spread_ms` (4 to 7 s by default, fixed for the id) and the hull between, the window
## starting in the first half of its cycle's spare time. The cycle's length and the window's place
## are the id's own, so a column that halts together does not fidget together; the frame is drawn
## per cycle. The answer holds for the stretch `span_from` and `span_to` say.
@warning_ignore("integer_division")
func pose_idle(id: int, still_ms: float, now_ms: float, frames: int) -> int:
	var after: float = still_ms + float(life.idle_after_ms)
	var window: int = life.idle_ms
	span_from = still_ms
	span_to = INF
	if now_ms < after:
		span_to = after
		return -1
	if window <= 0 or frames <= 0 or window >= life.idle_every_ms:
		return -1
	var period: int = life.idle_every_ms
	period += LifeClock.pick(id, SALT_POSE, maxi(life.idle_every_spread_ms, 0) + 1)
	var at: int = floori(now_ms - after)
	var cycle: int = at / period
	var start: int = LifeClock.pick(id, SALT_POSE + 3 * cycle + 2, ((period - window) >> 1) + 1)
	var begins: float = after + float(cycle * period)  # The cycle's first ms.
	var into: int = at - cycle * period
	if into < start:
		span_from = begins
		span_to = begins + float(start)
		return -1
	if into < start + window:
		span_from = begins + float(start)
		span_to = begins + float(start + window)
		return LifeClock.pick(id, SALT_POSE + 3 * cycle + 3, frames)
	span_from = begins + float(start + window)
	span_to = begins + float(period)
	return -1


## An answer that holds for all time, until the function narrows it.
func _forever() -> void:
	span_from = 0.0
	span_to = INF


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
