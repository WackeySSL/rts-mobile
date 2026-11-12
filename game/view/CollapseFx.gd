class_name CollapseFx
extends RefCounted
## The particles of a building's collapse (ADR 0029 section 8, plan P165): the collapse ring of
## `AirFx`, `life.collapse_slots` (40) quads. `BuildingCollapse.adopt` calls `start` at the DIED;
## `emit`, once a tick, gives each collapse its puffs when they are due, on match time from the DIED
## tick: at 0 a large `hit_flash` and `fire` puffs over the footprint, at `collapse_dust_ms[0]` on
## the `dust_cloud` puffs along the footprint diamond (each born and gone inside `collapse_dust_ms`)
## and, at the start of the sink, the `chip` debris. The collapses that run share the ring: each
## gets at most `collapse_slots / n` puffs, dust first, then the flash, the fire, the debris
## (eight at once get five dust puffs each). A puff is born only in the view rect `AirFx` passes
## (a collapse runs whether or not it is on screen). `reduced` keeps the flash, the fire and the
## dust and drops the debris. At most `collapse_max` collapses run at once; a new one over the cap
## takes the oldest's place. A sold building's collapse is `quiet`: dust only, no flash, no fire
## and no debris (ADR 0037 section 3). Allocates nothing after `read`. View only.

enum Style { FLASH, FIRE, DUST, DEBRIS }  ## Debris styles follow: `Style.DEBRIS + direction`.
const KINDS: Array[StringName] = [&"hit_flash", &"fire", &"dust_cloud", &"chip"]
const K_FLASH: int = 0
const K_FIRE: int = 1
const K_DUST: int = 2
const K_CHIP: int = 3
const MAX_DIRECTIONS: int = 8  ## At least `collapse_debris[1]`.
## Salts of `LifeClock`, far from the other life layers' (DamageFx 0x70.., HitFx 0x73.. to 0x75..).
const SALT_COUNT: int = 0x76000000
const SALT_SPOT: int = 0x77000000
const SALT_LOOK: int = 0x78000000
## The eight places on a footprint's diamond a puff stands at (the corners and the middles of the
## edges), as fractions of the diamond's half width and half height.
## Layout, not balance: the fire puffs of a collapse stand this many places apart on the eight, so
## two or three of them spread round the footprint and never side by side (coprime to eight).
const FIRE_STRIDE: int = 3
static var diamond: PackedVector2Array = PackedVector2Array(
	[
		Vector2(0.0, -1.0),
		Vector2(0.5, -0.5),
		Vector2(1.0, 0.0),
		Vector2(0.5, 0.5),
		Vector2(0.0, 1.0),
		Vector2(-0.5, 0.5),
		Vector2(-1.0, 0.0),
		Vector2(-0.5, -0.5),
	]
)

var ring: FxRing = FxRing.new()
var _cap: int = 0
var _next: int = 0  ## The number of the newest collapse.
var _seq: PackedInt32Array = PackedInt32Array()  ## Per slot: its number, 0 for a free slot.
var _id: PackedInt32Array = PackedInt32Array()
var _start: PackedInt32Array = PackedInt32Array()  ## The DIED tick.
var _at: PackedVector2Array = PackedVector2Array()  ## The footprint centre, world px.
var _rise: PackedFloat32Array = PackedFloat32Array()  ## The picture's height above it.
var _foot: PackedByteArray = PackedByteArray()
var _pending: PackedByteArray = PackedByteArray()  ## 1 until the tick's split gives it its puffs.
var _dust: PackedByteArray = PackedByteArray()  ## The puffs it may spend, by kind.
var _fire: PackedByteArray = PackedByteArray()
var _flash: PackedByteArray = PackedByteArray()
var _debris: PackedByteArray = PackedByteArray()
var _dust_born: PackedByteArray = PackedByteArray()
var _burst: PackedByteArray = PackedByteArray()  ## 1 once the flash and fire were born.
var _chips: PackedByteArray = PackedByteArray()  ## 1 once the debris was born.
var _quiet: PackedByteArray = PackedByteArray()  ## 1 for a sale's collapse: dust only.


func _init() -> void:
	ring.setup(KINDS, Style.DEBRIS + MAX_DIRECTIONS)
	ring.set_pass(K_DUST, FxRing.CLOUD)  # Under the fire and the flash.


## Takes the ring's size, the collapse table's and the looks from `life`.
func read(life: LifeSettings) -> void:
	ring.size_to(life.collapse_slots)
	_make_if_resized(maxi(life.collapse_max, 0))
	var one: Vector2 = Vector2.ONE
	var alpha: float = life.collapse_alpha
	var flash_ms: float = float(life.collapse_flash_ms)
	ring.set_style(Style.FLASH, K_FLASH, flash_ms, 0.0, 0.0, life.collapse_flash_grow, alpha, 0.0)
	ring.set_style(Style.FIRE, K_FIRE, flash_ms, 0.0, 0.0, life.collapse_fire_grow, alpha, 0.0)
	var dust: float = float(life.collapse_dust_life_ms)
	var rise: float = life.collapse_dust_rise_px
	var grow: Vector2 = life.collapse_dust_grow
	ring.set_style(Style.DUST, K_DUST, dust, rise, 0.0, grow, life.collapse_dust_alpha, 0.0)
	for dir: int in mini(life.collapse_debris_fly_px.size(), MAX_DIRECTIONS):
		var fly: Vector2 = life.collapse_debris_fly_px[dir]
		var chip_ms: float = float(life.collapse_debris_ms)
		ring.set_style(Style.DEBRIS + dir, K_CHIP, chip_ms, fly.y, fly.x, one, alpha, 0.0)


## Forgets every collapse (a new match); the ring is cleared by its owner.
func end_all() -> void:
	_seq.fill(0)


## The collapses that run now.
func count() -> int:
	var running: int = 0
	for slot: int in _cap:
		if _seq[slot] != 0:
			running += 1
	return running


## Starts the particles of building `id`'s collapse: `centre` is its footprint centre (world px),
## `rise` the height of its picture above it, `foot` its side in tiles, `tick` the DIED tick. Over
## the cap it takes the place of the oldest collapse, whose puffs live out.
func start(
	id: int, centre: Vector2, rise: float, foot: int, tick: int, quiet: bool = false
) -> void:
	if _cap == 0:
		return
	var slot: int = 0  # A free slot, else the oldest's.
	for at: int in _cap:
		if _seq[at] == 0:
			slot = at
			break
		if _seq[at] < _seq[slot]:
			slot = at
	_next += 1
	_seq[slot] = _next
	_id[slot] = id
	_start[slot] = tick
	_at[slot] = centre
	_rise[slot] = rise
	_foot[slot] = clampi(foot, 1, 255)
	_pending[slot] = 1
	_dust_born[slot] = 0
	# A cheap skip of `_burn`; `_split` also gives a sale no flash or fire.
	_burst[slot] = 1 if quiet else 0
	_quiet[slot] = 1 if quiet else 0
	_chips[slot] = 0


## One tick: the collapses started since the last one split the ring, and every collapse gets the
## puffs whose time has come (each at its own time, not the tick's). The puffs that lived out give
## their slots back first.
func emit(snap: MatchSnapshot, life: LifeSettings, view: Rect2) -> void:
	ring.compact(LifeClock.tick_ms(snap.tick))
	_split(life)
	var now: float = LifeClock.tick_ms(snap.tick)
	for slot: int in _cap:
		if _seq[slot] == 0:
			continue
		var born: float = LifeClock.tick_ms(_start[slot])
		if _burst[slot] == 0:
			_burst[slot] = 1
			_burn(slot, born, life, view)
		_dusts(slot, born, now, life, view)
		if _chips[slot] == 0 and born + float(life.collapse_sink_ms[0]) <= now:
			_chips[slot] = 1
			if not life.reduced:
				_chip(slot, born + float(life.collapse_sink_ms[0]), life, view)
		if now >= born + float(life.collapse_end_ms):
			_seq[slot] = 0


# Divides the ring over every collapse that runs, `collapse_slots / running` puffs each: a collapse
# that is new gets its puffs (dust first, then the flash, the fire, the debris), and one that runs
# already keeps what it has born and loses the unborn dust and debris that no longer fit. So a
# second wave takes only what the first one has not yet used, and no live puff is overwritten.
@warning_ignore("integer_division")
func _split(life: LifeSettings) -> void:
	var waiting: int = 0
	var running: int = 0
	for slot: int in _cap:
		if _seq[slot] != 0:
			running += 1
			waiting += _pending[slot]
	if waiting == 0:
		return
	var share: int = maxi(life.collapse_slots, 0) / running
	var fires: PackedInt32Array = life.collapse_fire_puffs
	var chips: PackedInt32Array = life.collapse_debris
	for slot: int in _cap:
		if _seq[slot] == 0:
			continue
		if _pending[slot] == 0:
			_trim(slot, share)
			continue
		_pending[slot] = 0
		var left: int = share
		_dust[slot] = mini(life.collapse_dust_puffs, left)
		left -= _dust[slot]
		var quiet: bool = _quiet[slot] == 1  # A sale: dust only, no flash, fire or debris.
		_flash[slot] = 0 if quiet else mini(1, left)
		left -= _flash[slot]
		var want: int = fires[0] + LifeClock.pick(_id[slot], SALT_COUNT, fires[1] - fires[0] + 1)
		_fire[slot] = 0 if quiet else mini(want, left)
		left -= _fire[slot]
		want = chips[0] + LifeClock.pick(_id[slot], SALT_COUNT + 1, chips[1] - chips[0] + 1)
		_debris[slot] = 0 if (life.reduced or quiet) else mini(want, left)


# Cuts the unborn dust and debris of the running collapse in `slot` to what is left of `share`
# after the puffs it has spent: the flash, the fire, the dust born and, once born, the debris.
func _trim(slot: int, share: int) -> void:
	var spent: int = _flash[slot] + _fire[slot] + _dust_born[slot]
	# Defensive: the debris is dead by the end (a data test), so its count never matters later.
	spent += _debris[slot] if _chips[slot] == 1 else 0
	var left: int = maxi(share - spent, 0)
	var unborn: int = mini(_dust[slot] - _dust_born[slot], left)
	_dust[slot] = _dust_born[slot] + unborn
	left -= unborn
	if _chips[slot] == 0:
		_debris[slot] = mini(_debris[slot], left)


# The flash and the fire puffs of a collapse, at its DIED time `born`.
func _burn(slot: int, born: float, life: LifeSettings, view: Rect2) -> void:
	var id: int = _id[slot]
	var spot: Vector2 = _at[slot] - Vector2(0.0, _rise[slot] * life.collapse_lift_milli / 1000.0)
	var half: Vector2 = _half(slot) * (float(life.collapse_fire_spread_milli) / 1000.0)
	if _flash[slot] > 0 and view.has_point(spot):
		ring.add(Style.FLASH, spot, born, LifeClock.mix(id, SALT_LOOK))
	var first: int = LifeClock.pick(id, SALT_SPOT, diamond.size())
	for k: int in _fire[slot]:
		var place: Vector2 = spot + diamond[(first + k * FIRE_STRIDE) % diamond.size()] * half
		if view.has_point(place):
			ring.add(Style.FIRE, place, born, LifeClock.mix(id, SALT_LOOK + 1 + k))


# The dust puffs of a collapse whose time came by `now`, each at its own time inside
# `collapse_dust_ms`: the first at its start, the others evenly up to the latest that still ends in
# time.
@warning_ignore("integer_division")
func _dusts(slot: int, born: float, now: float, life: LifeSettings, view: Rect2) -> void:
	var wanted: int = _dust[slot]
	var from: int = life.collapse_dust_ms[0]
	var room: int = maxi(life.collapse_dust_ms[1] - from - life.collapse_dust_life_ms, 0)
	var half: Vector2 = _half(slot) * (float(life.collapse_spread_milli) / 1000.0)
	var first: int = LifeClock.pick(_id[slot], SALT_SPOT + 1, diamond.size())
	while _dust_born[slot] < wanted:
		var j: int = _dust_born[slot]
		var at_ms: float = born + float(from + j * room / maxi(wanted - 1, 1))
		if at_ms > now:
			break
		_dust_born[slot] = j + 1
		var spot: Vector2 = _at[slot] + diamond[(first + j) % diamond.size()] * half
		if view.has_point(spot):
			ring.add(Style.DUST, spot, at_ms, LifeClock.mix(_id[slot], SALT_LOOK + 16 + j))


# The debris of a collapse, born when the sink starts, along the directions in turn.
func _chip(slot: int, at_ms: float, life: LifeSettings, view: Rect2) -> void:
	var dirs: int = clampi(life.collapse_debris_fly_px.size(), 0, MAX_DIRECTIONS)
	if dirs == 0:
		return
	var id: int = _id[slot]
	var spot: Vector2 = _at[slot] - Vector2(0.0, _rise[slot] * life.collapse_lift_milli / 1000.0)
	if not view.has_point(spot):
		return
	var first: int = LifeClock.pick(id, SALT_SPOT + 2, dirs)
	for k: int in _debris[slot]:
		var look: int = LifeClock.mix(id, SALT_LOOK + 32 + k)
		ring.add(Style.DEBRIS + (first + k) % dirs, spot, at_ms, look)


# The footprint diamond's half width and height, world px.
func _half(slot: int) -> Vector2:
	return Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * float(_foot[slot])


# Makes the table for `want` collapses (any change forgets them all).
func _make_if_resized(want: int) -> void:
	if want != _cap:
		_resize(want)


func _resize(want: int) -> void:
	_cap = want
	_next = 0
	_foot.resize(want)
	_foot.fill(0)
	_pending.resize(want)
	_pending.fill(0)
	_dust.resize(want)
	_dust.fill(0)
	_fire.resize(want)
	_fire.fill(0)
	_flash.resize(want)
	_flash.fill(0)
	_debris.resize(want)
	_debris.fill(0)
	_dust_born.resize(want)
	_dust_born.fill(0)
	_burst.resize(want)
	_burst.fill(0)
	_chips.resize(want)
	_chips.fill(0)
	_quiet.resize(want)
	_quiet.fill(0)
	_seq.resize(want)
	_seq.fill(0)
	_id.resize(want)
	_start.resize(want)
	_at.resize(want)
	_rise.resize(want)
