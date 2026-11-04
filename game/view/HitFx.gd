class_name HitFx
extends RefCounted
## The hit feedback of `AirFx` (ADR 0029 section 7, plan P166): a white flash and a few chips where
## a shot hit a building the local player is shown, into a ring of `life.hit_slots` (16). A hit is
## an IMPACT with a target, or the SHOT of a weapon whose projectile speed is 0 (the rifle: target
## id at +4, the point at +6/+7). A SHOT of a shell, an IMPACT on a unit, on a building that is
## gone or hidden, or with target 0 draws nothing, and neither does a hit whose target has a DIED
## record in the same tick: the death's own effects stand for it. The flash is `hit_flash_ms` of
## match time, `hit_chips[0] + LifeClock.pick(hit id, SALT_CHIP, ...)` chips fly out for
## `hit_chip_ms`, each along one of the `hit_chip_fly_px`. The flash lies inside the middle
## `hit_flash_box_milli` of the building's `frame_box`, so it is on the picture. Both are drawn in
## the flame pass, the last, so smoke and clouds do not cover a hit. `reduced` keeps the flash and
## drops the chips. No camera shake. View only; allocates nothing after `read`.

enum Style { FLASH, CHIP }  ## Chip styles follow: `Style.CHIP + direction`.
const KINDS: Array[StringName] = [&"hit_flash", &"chip"]
const K_FLASH: int = 0
const K_CHIP: int = 1
const MAX_DIRECTIONS: int = 4
## Salts of `LifeClock`, far from the other life layers' (RigLife 0x1.. to 0x3.., dust 0x4..,
## animations 0x5.., AirFx 0x6.., DamageFx 0x70.. to 0x72..).
const SALT_CHIP: int = 0x73000000
const SALT_SPOT: int = 0x74000000
const SALT_LOOK: int = 0x75000000

var ring: FxRing = FxRing.new()


func _init() -> void:
	ring.setup(KINDS, Style.CHIP + MAX_DIRECTIONS)


## Empties the ring (a new match).
func clear() -> void:
	ring.clear()


## Takes the ring's size and the looks of the flash and of each chip direction from `life`.
func read(life: LifeSettings) -> void:
	ring.size_to(life.hit_slots)
	ring.set_style(
		Style.FLASH,
		K_FLASH,
		float(life.hit_flash_ms),
		0.0,
		0.0,
		life.hit_flash_grow,
		life.hit_alpha,
		0.0
	)
	for dir: int in mini(life.hit_chip_fly_px.size(), MAX_DIRECTIONS):
		var fly: Vector2 = life.hit_chip_fly_px[dir]
		ring.set_style(
			Style.CHIP + dir,
			K_CHIP,
			float(life.hit_chip_ms),
			fly.y,
			fly.x,
			Vector2.ONE,
			life.hit_alpha,
			0.0
		)


## One tick's events: a flash and chips for each hit on a shown building. The puffs that lived out
## give their slots back first.
func emit(snap: MatchSnapshot, life: LifeSettings, buildings: BuildingLayer) -> void:
	ring.compact(LifeClock.tick_ms(snap.tick))
	var events: PackedInt32Array = snap.events
	var speeds: PackedInt32Array = snap.weapon_projectile_speed
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		var kind: int = events[at]
		if kind == World.Event.IMPACT:
			_hit(snap, at, events[at + 1], 2, life, buildings)
		elif kind == World.Event.SHOT:
			var weapon: int = events[at + 5]
			if weapon >= 0 and weapon < speeds.size() and speeds[weapon] == 0:
				_hit(snap, at, LifeClock.mix(events[at + 1], snap.tick), 6, life, buildings)


# The hit of the record at `at`, id `id`, whose point is at `at + point` and `at + point + 1`.
func _hit(
	snap: MatchSnapshot, at: int, id: int, point: int, life: LifeSettings, buildings: BuildingLayer
) -> void:
	var events: PackedInt32Array = snap.events
	var target: int = events[at + 4]
	var row: int = buildings.row_of(target)
	if row < 0 or not buildings.is_shown(row) or _died(events, target):
		return
	var box: Rect2 = buildings.frame_box(row)
	if box.size == Vector2.ZERO:
		return
	var weapon: int = events[at + 5]
	var sheet_px: float = 0.0
	if buildings.world_sort != null:
		sheet_px = buildings.world_sort.muzzle_px(weapon)
	var lift: float = SpriteLift.muzzle_lift_px(snap.weapon_ids, weapon, sheet_px)
	var spot: Vector2 = (
		IsoProjection.ground_to_px(events[at + point], events[at + point + 1]) - Vector2(0.0, lift)
	)
	var inner: Rect2 = Rect2(Vector2.ZERO, box.size * (float(life.hit_flash_box_milli) / 1000.0))
	inner.position = box.get_center() - inner.size * 0.5
	spot += Vector2(_unit(id, SALT_SPOT), _unit(id, SALT_SPOT + 1)) * inner.size
	spot = Vector2(
		clampf(spot.x, inner.position.x, inner.end.x), clampf(spot.y, inner.position.y, inner.end.y)
	)
	var born: float = LifeClock.tick_ms(snap.tick)
	ring.add(Style.FLASH, spot, born, LifeClock.mix(id, SALT_LOOK))
	if life.reduced:
		return
	var dirs: int = clampi(life.hit_chip_fly_px.size(), 0, MAX_DIRECTIONS)
	var span: int = life.hit_chips[1] - life.hit_chips[0] + 1
	var chips: int = life.hit_chips[0] + LifeClock.pick(id, SALT_CHIP, span)
	if dirs == 0:
		return
	var first: int = LifeClock.pick(id, SALT_LOOK, dirs)
	for k: int in chips:
		ring.add(Style.CHIP + (first + k) % dirs, spot, born, LifeClock.mix(id, SALT_LOOK + 1 + k))


# Whether the events hold a DIED record of unit `id`.
func _died(events: PackedInt32Array, id: int) -> bool:
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED and events[at + 1] == id:
			return true
	return false


# `LifeClock.pick(id, salt, 1001)` as -0.5 to 0.5.
func _unit(id: int, salt: int) -> float:
	return float(LifeClock.pick(id, salt, 1001)) / 1000.0 - 0.5
