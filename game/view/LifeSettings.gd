class_name LifeSettings
extends Resource
## Every number of the unit-life layer (ADR 0027 section 8, plan 2026-11-02-unit-life.md): view
## only, never loaded by `game/sim` and not in `defs_hash`. The instance is
## `res://data/life_settings.tres`, where all tuning happens; the defaults here are the ones that
## file holds. Every life consumer has `@export var life: LifeSettings` and falls back to that file
## when it is unset, so a number is reachable without a scene edit. A test that wants another value
## calls `duplicate()` first.
## The sections follow the plan's core rows: P136 owns the recoil, P138 the dust, P140 and P142 the
## idle life of rigs, P141 the strikes, P144 the building animations and P145 the emitters. A row
## only reads its section; the optional rows (P148 and on) append their own fields below.
## The art's own numbers (`stride_milli`, `anim_ms`, `emitters`, `marks`) are in the sheets.

## Reduced effects (ADR 0027, answer 3): drops the ambient (dust, track marks, wrecks, drive rumble,
## look-around, head sweep, stack smoke, steam, flare flames, exhaust, muzzle smoke, the factory
## puff) and keeps what tells the player something (recoil, walking, idle poses, building
## animations, damage smoke, construction sparks, the superweapon effects). Only the perf arena's
## card writes it in a match (P147); the player's switch comes with Phase 5.
@export var reduced: bool = false

## Recoil (P136), per weapon id like `EffectsLayer.flash_px`: how far the turret (or a defence's
## head) kicks back along the aim, in world px at zoom 1, and how far the hull rocks with it (the
## hull and the turret move together by this much, the turret by its own recoil on top). A weapon
## with no row, or 0, does not kick: the squads' rifle and rockets have none because a squad has no
## turret. Every weapon that a turreted vehicle or a defence fires has a row (a data test).
@export var recoil_px: Dictionary[StringName, float] = {
	&"tank_cannon": 3.0,
	&"heavy_cannon": 4.0,
	&"turret_gun": 2.5,
	&"artillery_gun": 5.0,
	&"redoubt_gun": 2.5,
	&"arcline_gun": 4.0,
}
## The hull rock, heavy guns only. A defence has no hull to rock: its body never moves.
@export var rock_px: Dictionary[StringName, float] = {
	&"heavy_cannon": 1.0,
	&"artillery_gun": 1.5,
	&"arcline_gun": 1.0,
}
## Match-time ms after the SHOT: the kick peaks at `recoil_out_ms` and the turret is back on its
## mount at `recoil_back_ms`, then nothing is written. `recoil_back_ms` counts from the shot, not
## from the peak, and is read as at least one ms after the peak.
@export var recoil_out_ms: int = 50
@export var recoil_back_ms: int = 200
## Kicks running at once, per layer (a fixed table, nothing is made per shot). A shot that finds it
## full does not kick: a rig never keeps a stale offset.
@export var kick_slots: int = 128

## Idle life of vehicles and defences (P140, P140b). A vehicle that drove at least half a step in
## the last tick on an order rumbles: its hull and turret shift by up to `drive_shake_px` on each
## axis (whole 0.5 px steps, so 0.5 is the smallest that rumbles), a new offset at most once per
## `drive_shake_ms`. A standing vehicle never shakes; a turreted one with no target turns its turret
## one frame aside for `look_ms`, once in each cycle of `look_every_ms` plus up to
## `look_every_spread_ms` (by `LifeClock.mix`, fixed for a unit); a complete, online defence head
## with no target walks to `sweep_frames` frames either side of its last aim and back, holding each
## frame `sweep_ms`. A 0 in `drive_shake_px`, `look_ms` or `sweep_frames` turns that effect off.
@export var drive_shake_px: float = 0.5
@export var drive_shake_ms: int = 80
@export var look_every_ms: int = 6000
@export var look_every_spread_ms: int = 4000
@export var look_ms: int = 900
@export var sweep_frames: int = 2
@export var sweep_ms: int = 700

## Idle poses of squads (P142): after standing `idle_after_ms` with no target a squad shows an idle
## frame for `idle_ms` once per cycle of `idle_every_ms` plus up to `idle_every_spread_ms`.
@export var idle_after_ms: int = 1500
@export var idle_every_ms: int = 4000
@export var idle_every_spread_ms: int = 3000
@export var idle_ms: int = 600

## `GroundFx` dust (P138): one puff per `dust_every_milli` of travel per vehicle in view, living
## `dust_life_ms`, in `dust_slots` slots of the ring.
@export var dust_every_milli: int = 700
@export var dust_life_ms: int = 600
@export var dust_slots: int = 48

## Strikes (P141): the launch at the building lasts `launch_ms`, the fall from the sky the last
## `fall_ms` before the landing, and the blackout's net lands by `net_land_ms`. `strike_slots`
## is the quota of `StrikeFx`.
@export var launch_ms: int = 700
@export var fall_ms: int = 600
@export var net_land_ms: int = 600
@export var strike_slots: int = 8

## Building animations (P144): the rate of an own building's animation while the local player's
## power is short (1.0 is the full rate).
@export var low_power_rate: float = 0.5

## `AirFx` emitters (P145), per emitter kind (`smoke`, `steam`, `flare`): the time between puffs
## (at least 500, so an emitter has at most four puffs alive) and a puff's life (at most 2000),
## then how far smoke and steam rise and drift in their life, in world px, and the ring's quota.
@export var emit_ms: Dictionary[StringName, int] = {&"smoke": 700, &"steam": 600, &"flare": 500}
@export
var emit_life_ms: Dictionary[StringName, int] = {&"smoke": 1800, &"steam": 1200, &"flare": 700}
@export var emit_rise_px: float = 24.0
@export var emit_drift_px: float = 6.0
@export var emitter_slots: int = 80

## `GroundFx` dust, the rest of its numbers (P138): a puff is born `dust_back_milli` behind the
## vehicle's position, along the way it came, grows from `dust_grow_from` to `dust_grow_to` times
## the frame's size and fades from `dust_alpha` to 0 in its life. A `dust_every_milli` of 0 turns
## the dust behind vehicles off (the puff at a factory's exit stays, P150); a `dust_slots` of 0
## turns both off.
@export var dust_back_milli: int = 300
@export var dust_alpha: float = 0.8
@export var dust_grow_from: float = 0.6
@export var dust_grow_to: float = 1.2

## `StrikeFx`, the rest of its numbers (P141): the lance (or the seed) rises `strike_rise_px` in
## `launch_ms` and fades, the launch flash lasts `launch_flash_ms`; the shadow of the falling lance
## grows from `fall_shadow_from` of its size to the full one and to `fall_shadow_alpha`; the
## launch's ring of dust grows to `launch_ring_grow_to` times its size; the net starts
## `net_scale_from` times its size, lands at full size with `net_alpha`, then settles as a ring for
## `net_settle_ms` (the interior fades faster than the ring of its boundary cells; the landing
## flash and the glints fade too).
@export var strike_rise_px: float = 96.0
@export var launch_flash_ms: int = 250
@export var fall_shadow_from: float = 0.4
@export var fall_shadow_alpha: float = 0.5
@export var net_scale_from: float = 1.6
@export var net_alpha: float = 0.9
@export var net_settle_ms: int = 500
@export var launch_ring_grow_to: float = 2.0

## `AirFx`, the rest of its numbers (P145): a puff of smoke or steam grows from `emit_grow_from` to
## `emit_grow_to` times its frame while it rises and drifts; a flame stays on its point and goes
## from `emit_flame_from` to `emit_flame_to` times its frame. Smoke and steam fade from `emit_alpha`
## to 0 in the puff's life; a flame holds `emit_alpha` until the next flame is born and fades in
## the overlap that is left. An `emit_ms` of 0 for a kind, or an `emitter_slots` of 0, turns it off.
@export var emit_alpha: float = 0.85
@export var emit_grow_from: float = 0.6
@export var emit_grow_to: float = 1.2
@export var emit_flame_from: float = 1.0
@export var emit_flame_to: float = 0.7

## Damage stages (P159, ADR 0029 section 2, ADR 0028 section 8): the lines of the stages as
## `[P1, P2]`, strict "under" (`BuildingDamage.stage_of`): hp x 100 below max x P1 is SKADET (stage
## 1) and below max x P2 KRITISK (stage 2). One list per kind; a data test holds 100 > P1 > P2 > 0.
@export var building_stage_percent: PackedInt32Array = PackedInt32Array([67, 34])
@export var vehicle_stage_percent: PackedInt32Array = PackedInt32Array([50, 25])
## Sprite writes a frame may spend on stage changes, and the part of them that is the buildings'
## (the rest is the vehicles'): a fixed split, so the result never depends on which layer runs
## first. The vehicle layer (P161) reads its share as `damage_writes_per_frame -
## damage_building_writes`.
@export var damage_writes_per_frame: int = 60
@export var damage_building_writes: int = 20

## Vehicle overlays (P161, ADR 0028 sections 4 and 8): whether a vehicle at stage 2 hangs a loose
## part. Off drops its region, visibility, position and flip writes (the fallback if P162's worst
## frame passes 150); the scar stays.
@export var damage_loose: bool = true
## Damage particles (P148, ADR 0029 sections 6 and 13, ADR 0028 section 6). The damage ring holds
## `damage_slots` puffs. A building at SKADET burns `damage_burning_points[0]` of its damage points
## and at KRITISK up to `[1]`; a data test holds each stage's smoke (points x ceil(life / emit))
## under `damage_smoke_cap`. `damage_emit_ms` and `damage_life_ms` are keyed by the puff: `smoke`
## (SKADET), `soot` (KRITISK), `fire`, `spark` and `exhaust` (a vehicle's trail); `jet` has a life
## only, since a jet is born with the fire at its point. A
## KRITISK fire and its glow are `damage_fire_scale` times their frame, a vehicle's fire
## `damage_vehicle_fire_scale`. Smoke and soot rise `damage_rise_px` and drift `emit_drift_px`; a
## spark rises `damage_spark_rise_px`. A glow's alpha is `glow_weak_alpha` (SKADET),
## `glow_strong_alpha` (KRITISK) or `glow_faint_alpha` (a crater). A glow is steady: one per burning
## point, born again the tick the last one ends, each living the ticks of its fire's (or ember's)
## `damage_emit_ms`, so at most one glow per point shows.
## Craters (ADR 0029 section 6; P165 adds them): a source of a fallen building smokes
## (`crater_smoke`) for `crater_smoke_ms` and glows with embers (`ember`) for `crater_ember_ms`; at
## most `crater_sources` are alive at once, the oldest ends first.
@export var damage_slots: int = 80
@export var damage_burning_points: PackedInt32Array = PackedInt32Array([1, 3])
@export var damage_smoke_cap: int = 30
@export var damage_emit_ms: Dictionary[StringName, int] = {
	&"smoke": 500,
	&"soot": 400,
	&"fire": 500,
	&"spark": 400,
	&"exhaust": 600,
	&"crater_smoke": 700,
	&"ember": 900,
}
@export var damage_life_ms: Dictionary[StringName, int] = {
	&"smoke": 2000,
	&"soot": 2000,
	&"fire": 700,
	&"jet": 600,
	&"spark": 500,
	&"exhaust": 1200,
	&"crater_smoke": 2000,
	&"ember": 1800,
}
@export var damage_fire_scale: float = 1.6
@export var damage_vehicle_fire_scale: float = 0.8
@export var damage_rise_px: float = 28.0
@export var damage_spark_rise_px: float = 14.0
@export var glow_weak_alpha: float = 0.3
@export var glow_strong_alpha: float = 0.55
@export var glow_faint_alpha: float = 0.2
@export var crater_smoke_ms: int = 8000
@export var crater_ember_ms: int = 15000
@export var crater_sources: int = 16

## Hit feedback (P166, ADR 0029 sections 7 and 13): a shot that hits a shown building draws a white
## `hit_flash` for `hit_flash_ms` (growing from `hit_flash_grow.x` to `.y` times its frame, at
## `hit_alpha`) inside the middle `hit_flash_box_milli` (of 1000) of the building's `frame_box`, and
## `hit_chips[0]` to `[1]` chips that fly out for `hit_chip_ms`, each along one of the
## `hit_chip_fly_px` (east, up; at most five). The hit ring holds `hit_slots` of them.
@export var hit_slots: int = 16
@export var hit_flash_ms: int = 60
@export var hit_flash_box_milli: int = 500
@export var hit_flash_grow: Vector2 = Vector2(0.7, 1.2)
@export var hit_alpha: float = 1.0
@export var hit_chips: PackedInt32Array = PackedInt32Array([3, 5])
@export var hit_chip_ms: int = 350
@export var hit_chip_fly_px: PackedVector2Array = PackedVector2Array(
	[
		Vector2(-14.0, 10.0),
		Vector2(-6.0, 18.0),
		Vector2(0.0, 22.0),
		Vector2(6.0, 18.0),
		Vector2(14.0, 10.0),
	]
)

## The collapse of a building shot to pieces (P165, ADR 0029 sections 8, 10 and 13), on match time
## from its DIED tick: at 0 the picture's `Anim` and `Head` go, a `hit_flash` of
## `collapse_flash_grow` times its frame and `collapse_fire_puffs[0]` to `[1]` `fire` puffs burn for
## `collapse_flash_ms`;
## the body and its patch sink in `collapse_sink_steps` steps from `collapse_sink_ms[0]` to `[1]`,
## to `collapse_sink_percent` of the picture's rise; `collapse_dust_puffs` `dust_cloud` puffs, each
## living `collapse_dust_life_ms`, are born inside `collapse_dust_ms` along the footprint diamond
## (`collapse_spread_milli` of 1000 of it; the fire puffs `collapse_fire_spread_milli`) and rise
## `collapse_dust_rise_px`; `collapse_debris[0]` to `[1]` chips fly out for `collapse_debris_ms`,
## each along one of the `collapse_debris_fly_px`; the node is hidden at `collapse_hide_ms` and
## freed at `collapse_end_ms`. The flash and the fire stand at `collapse_lift_milli` of 1000 of the
## picture's rise. The collapses that run share the ring: each gets at most `collapse_slots / n`
## puffs, dust first, then the flash, the fire and the debris. At most `collapse_max` run at once.
## `crater_scale_milli` is the crater's size by building type, in thousandths of the footprint's
## crater (a type with no entry has 1000).
@export var collapse_slots: int = 40
@export var collapse_max: int = 16
@export var collapse_flash_ms: int = 250
@export var collapse_fire_puffs: PackedInt32Array = PackedInt32Array([2, 3])
@export var collapse_sink_ms: PackedInt32Array = PackedInt32Array([250, 700])
@export var collapse_sink_steps: int = 6
@export var collapse_sink_percent: int = 60
@export var collapse_hide_ms: int = 700
@export var collapse_dust_ms: PackedInt32Array = PackedInt32Array([250, 900])
@export var collapse_dust_puffs: int = 8
@export var collapse_dust_life_ms: int = 450
@export var collapse_dust_rise_px: float = 18.0
@export var collapse_dust_grow: Vector2 = Vector2(0.8, 1.5)
@export var collapse_dust_alpha: float = 0.8
@export var collapse_spread_milli: int = 700
@export var collapse_fire_spread_milli: int = 350
@export var collapse_debris: PackedInt32Array = PackedInt32Array([6, 8])
@export var collapse_debris_ms: int = 450
@export var collapse_debris_fly_px: PackedVector2Array = PackedVector2Array(
	[
		Vector2(-26.0, 8.0),
		Vector2(-18.0, 22.0),
		Vector2(-8.0, 30.0),
		Vector2(0.0, 34.0),
		Vector2(8.0, 30.0),
		Vector2(18.0, 22.0),
		Vector2(26.0, 8.0),
		Vector2(0.0, 18.0),
	]
)
@export var collapse_flash_grow: Vector2 = Vector2(1.4, 2.6)
@export var collapse_fire_grow: Vector2 = Vector2(1.2, 0.8)
@export var collapse_alpha: float = 1.0
@export var collapse_lift_milli: int = 500
@export var collapse_end_ms: int = 900
@export
var crater_scale_milli: Dictionary[StringName, int] = {&"refinery": 1500, &"renew_refinery": 1500}

## Muzzle smoke and exhaust puffs (P149, ADR 0027 sections 3 and 8): the small puffs of `AirFx`'s
## `PuffFx` ring, `puff_slots` of them for muzzle smoke, exhaust and (P150) construction sparks,
## each living at most 500 ms. A SHOT of a weapon that fires a projectile (a cannon, artillery or a
## rocket; the rifle does not) leaves a `puff` `muzzle_smoke_ms` long at the flash's point, that
## many px from the shooter towards the target (`muzzle_reach_px` per weapon id, the figures of
## `EffectsLayer.muzzle_px`, `muzzle_reach_default_px` for a weapon with no row). A vehicle that
## starts to drive puffs `exhaust` once from its exhaust point; one that stands puffs again every
## `puff_idle_ms.x` to `.y` ms, a time of its own by `LifeClock.pick` (an `x` of 0 or less turns
## idle puffs off). A puff rises `*_rise_px` and drifts east `*_drift_px` while it grows from
## `*_grow.x` to `.y` times its frame and fades from `*_alpha` to 0. A `puff_slots` of 0, or a
## `muzzle_smoke_ms` or `exhaust_ms` of 0, turns it off.
@export var puff_slots: int = 24
@export var muzzle_smoke_ms: int = 500
@export var muzzle_reach_default_px: float = 13.0
@export var muzzle_reach_px: Dictionary[StringName, float] = {
	&"tank_cannon": 31.0,
	&"rocket": 13.0,
	&"rifle": 13.0,
	&"heavy_cannon": 13.0,
	&"turret_gun": 13.0,
	&"artillery_gun": 13.0,
	&"breaker_rocket": 13.0,
	&"redoubt_gun": 13.0,
	&"arcline_gun": 13.0,
}
@export var muzzle_smoke_rise_px: float = 10.0
@export var muzzle_smoke_drift_px: float = 4.0
@export var muzzle_smoke_grow: Vector2 = Vector2(0.7, 1.5)
@export var muzzle_smoke_alpha: float = 0.8
@export var exhaust_ms: int = 500
@export var exhaust_rise_px: float = 8.0
@export var exhaust_drift_px: float = 3.0
@export var exhaust_grow: Vector2 = Vector2(0.7, 1.4)
@export var exhaust_alpha: float = 0.8
@export var puff_idle_ms: Vector2i = Vector2i(3000, 5000)

## Construction sparks (P150, ADR 0027 sections 3 and 8): a site (`build_left` above 0) the player
## is shown throws a `spark` every `spark_ms` from a `LifeClock.mix` spot of its footprint, lifted
## `spark_lift_px` onto the framework. A spark lives `spark_life_ms` (at most 500) in the ring of
## `puff_slots`, rises `spark_rise_px`, grows from `spark_grow.x` to `.y` times its frame and fades
## from `spark_alpha` to 0. A `spark_ms` or `spark_life_ms` of 0 turns the sparks off; `reduced`
## keeps them. The dust puff at a factory's exit is `GroundFx`'s dust (`dust_*`, `dust_slots`).
@export var spark_ms: int = 200
@export var spark_life_ms: int = 300
@export var spark_lift_px: float = 16.0
@export var spark_rise_px: float = 10.0
@export var spark_grow: Vector2 = Vector2(1.0, 0.5)
@export var spark_alpha: float = 1.0
