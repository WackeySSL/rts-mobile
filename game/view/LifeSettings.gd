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
## the frame's size and fades from `dust_alpha` to 0 in its life. A `dust_every_milli` or
## `dust_slots` of 0 turns the dust off.
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

## Damage particles (P148, ADR 0029 sections 6 and 13, ADR 0028 section 6). The damage ring holds
## `damage_slots` puffs. A building at SKADET burns `damage_burning_points[0]` of its damage points
## and at KRITISK up to `[1]`; a data test holds each stage's smoke (points x ceil(life / emit))
## under `damage_smoke_cap`. `damage_emit_ms` and `damage_life_ms` are keyed by the puff: `smoke`
## (SKADET), `soot` (KRITISK), `fire`, `jet`, `spark` and `exhaust` (a damaged vehicle's trail). A
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
	&"jet": 300,
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
