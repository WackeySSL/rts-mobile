extends "res://tests/view/support/damage_fx_suite.gd"
## The fixture and helpers of the hit feedback suites (plan P166): test_hit_fx.gd and
## test_hit_fx_spot.gd extend this. Barracks 1 to 8 on a crafted sheet, all shown, and a weapon
## table of a shell weapon and a hitscan one. Not a test suite.

const Effects: GDScript = preload("res://tests/view/support/effects_rig.gd")
const SPAWNS: Array = [
	[1, 4, 4], [1, 12, 4], [1, 20, 4], [1, 4, 12], [1, 12, 12], [1, 20, 12], [1, 4, 20], [1, 12, 20]
]
const SHELL: int = 0  ## The weapon table of the test: a shell weapon, then a hitscan one.
const RIFLE: int = 1
const SALT_CHIP: int = 0x73000000
const SALT_SPOT: int = 0x74000000
## Chips of a hit for ids 1 to 8 (`3 + LifeClock.pick(id, SALT_CHIP, 3)`), pinned: the same on
## every device and run. A shell's hit id is its projectile id; a rifle's is
## `LifeClock.mix(shooter id, tick)`, here for shooter 1 to 8 at tick START.
const IMPACT_CHIPS: Array[int] = [4, 4, 4, 4, 4, 5, 3, 3]
const SHOT_CHIPS: Array[int] = [3, 3, 5, 4, 3, 5, 4, 3]

var _inject_target: int = 0


func before_test() -> void:
	_open(SPAWNS)
	_weapons()


## The weapon table of the test on the published snapshot.
func _weapons() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.weapon_ids.clear()
	snap.weapon_ids.append(&"tank_cannon")
	snap.weapon_ids.append(&"rifle")
	snap.weapon_projectile_speed = PackedInt32Array([20000, 0])


func _ring() -> FxRing:
	return _air.hits().ring


## An IMPACT of projectile `projectile` on building `target`, at its position.
func _impact(projectile: int, target: int, weapon: int = SHELL) -> PackedInt32Array:
	return Effects.impact(Rig.position_of(_runner, target), weapon, projectile, target)


## A SHOT of `shooter` at building `target`, with the target's position at +6/+7.
func _shot(shooter: int, target: int, weapon: int = RIFLE) -> PackedInt32Array:
	var at: Vector2i = Rig.position_of(_runner, target)
	return Effects.shot(at + Vector2i(3000, 0), at, weapon, shooter, target)


func _hit_at(events: PackedInt32Array, tick: int = START) -> void:
	_ring().clear()
	Rig.deliver(_runner, events, tick)


## Puffs of the ring of style `style` (a `HitFx.Style` value, chips from `HitFx.Style.CHIP`).
func _of(style: int) -> int:
	var found: int = 0
	for slot: int in _ring().count():
		var puff: int = _ring().puff_style(slot)
		found += 1 if (puff == style or (style == HitFx.Style.CHIP and puff >= style)) else 0
	return found


## `LifeClock.pick(id, salt, 1001)` as -0.5 to 0.5, restated.
func _unit(id: int, salt: int) -> float:
	return float(LifeClock.pick(id, salt, 1001)) / 1000.0 - 0.5


## Where the flash of hit `hit_id` on building `target` must be for the event point `ground`
## (milli-tiles) of `weapon`, restated from the ADR: the point lifted by the weapon's muzzle, moved
## by the hash within the middle half of the frame box and clamped into it. The second item says
## whether the clamp left it alone, which is what makes the comparison tell a wrong point apart.
func _restate(hit_id: int, ground: Vector2i, weapon: int, target: int) -> Array:
	var snap: MatchSnapshot = _runner.snapshot
	var box: Rect2 = _buildings.frame_box(snap.index_of(target))
	var inner: Rect2 = Rect2(box.get_center() - box.size * 0.25, box.size * 0.5)
	var lift: float = SpriteLift.muzzle_lift_px(snap.weapon_ids, weapon, _sort.muzzle_px(weapon))
	var raw: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y) - Vector2(0.0, lift)
	raw += Vector2(_unit(hit_id, SALT_SPOT), _unit(hit_id, SALT_SPOT + 1)) * inner.size
	var spot: Vector2 = Vector2(
		clampf(raw.x, inner.position.x, inner.end.x), clampf(raw.y, inner.position.y, inner.end.y)
	)
	return [spot, inner.has_point(raw)]


func _flash_spot() -> Vector2:
	for slot: int in _ring().count():
		if _ring().puff_style(slot) == HitFx.Style.FLASH:
			return _ring().puff_at(slot)
	return Vector2(INF, INF)


func _inject(_tick: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var events: PackedInt32Array = snap.events.duplicate()
	events.append_array(_impact(77, _inject_target))
	snap.events = events
