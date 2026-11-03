# Plan: damage states of buildings and vehicles

Date: 2026-11-03. Base: `main` at 64f0402 (P141 merged; P145 `AirFx` in review on
`claude/p145-air-fx`). Decisions: `docs/adr/0028-damage-states.md`, **accepted** 2026-11-03
(Michael's answers 1 A, 2 A). Phase: 3 by date, ROADMAP Phase 5 by kind (polish), like the unit
life (ADR 0027); no ROADMAP box, and no row here is on the Phase 3 gate path. Rows P155-P162 and the
reworked P148 of `docs/plans/2026-11-02-unit-life.md`; P155 (this plan and ADR 0028) is done on
`claude/damage-states-plan`; the lead's acceptance row is P26ar.

## Goal
Michael, 2026-11-03: buildings and vehicles under 50 % hp look as if they are falling apart, in two
stages (under 50 %: cracks, soot, smoke; under 25 %: falling apart, fire and sparks); infantry not.
Buildings by generated pictures of each stage, vehicles by overlays, smoke and fire by P148. All of
it view and art, honest to the fog, in both orientations and on the web, inside the page budget
(3584) and rule 6.

## Out of scope
Repair and healing (no rule in the sim; ADR 0028 §2 says what a repair ADR would decide), stages
for infantry, a damaged defence head, a damaged shadow or build card, death animations (P152's
wrecks stay a separate row), sound, camera shake, any sim rule, state or event.

## Affected modules
- `tools/artgen/`: `ArtModel.gd`, `ArtMove.gd`, `ArtGen.gd`, `ArtSheet.gd`, `ArtRender.gd`,
  `ArtPalette.gd` (the char colour), `IsoSheetDef.gd` (`cuts`, `scar_milli`); the `damage` and `hang`
  emitter kinds (P156).
- Art: `assets/art/models/*/*.tres` (damage poses, `damage` and `hang` points), generated
  `<id>_dmg1.svg` and `<id>_dmg2.svg` under `assets/art/iso/*/bld/`, new hand-written
  `assets/art/iso/neutral/dmg/*.svg` and `damage_sheet.tres`, `assets/art/STYLE.md` ("Damage stages"
  under Generated art, "Damage overlays").
- `game/view/`: new `BuildingDamage.gd`, `VehicleDamage.gd`; changed `IsoAtlas.gd` (the neutral
  sheet), `BuildingLayer.gd`, `GhostMemoryLayer.gd`, `UnitLayer.gd` (calls only), `AirFx.gd`,
  `LifeFx.gd` (one export), `LifeSettings.gd`; `art_gallery_build.gd`, `art_gallery_units.gd`.
- `data/life_settings.tres` (new fields); `scenes/main.tscn` (two exports wired: P159, P148).
- Tests: `tests/art/` (generator, patches, overlays), `tests/view/` (stages, ghosts, overlays, the
  damage ring, the page test's `TODAY_*`), `tests/view/test_life_budget.gd` (P162).
- Docs: `docs/HOW_TO_PLAY.md` (Buildings, Units), dated notes by P26ar.

## Command and data changes
- No Command, event, state column or hash. The sim is untouched (ADR 0028 §1).
- `data/life_settings.tres` (`LifeSettings`, view-only): `damage_stage_percent` ([50, 25]) and
  `damage_changes_per_frame` (12) from P159; P148 appends `damage_emit_ms`, `damage_life_ms`,
  `damage_vehicle_fire_scale`, `damage_slots` (64).
- Sheet fields the generator writes: `cuts` (buildings), `scar_milli` (vehicles), emitter kinds
  `damage` (buildings: two points; vehicles: one per hull frame) and `hang` (vehicles, one per hull
  frame).

## Rows
Size = production lines (tests, fixtures, models, generated frames and SVG not counted).
"At once" = may start the day P26ar lands.

| Row | Lane | Owner | Title | Size | Depends | Box |
| --- | --- | --- | --- | --- | --- | --- |
| P155 | - | architect | docs: this plan and ADR 0028 (accepted 2026-11-03); done on `claude/damage-states-plan` | 0 | - | - |
| P26ar | - | lead | docs: ADR 0028 on acceptance: Michael's answers in it, the dated notes in ADR 0027 §3, §4, §8, ADR 0023 §2, §5 and the unit-life plan's P148 row | 0 | P155 | - |
| P156 | A | art-director | art: generator v4, damage poses (`dmg1`, `dmg2`: `shift`, `turn`, `hide`, `char`, `damage=<k>` primitives), the geometric cut row, the patch crop with its overlap, `cuts`, `scar_milli`, the `damage` and `hang` kinds; no model gets them here, today's files byte-identical (at once) | 220 | P26ar | - |
| P157 | V2 | touch-ux-dev | view: the neutral sheet in the bake (`faction` `neutral`, collected for every match, shared slots) and its bases in `WorldSort`; the page test counts it (at once) | 60 | P26ar | - |
| P158 | A | art-director | art: `dmg1` and `dmg2` of the sixteen buildings, two `damage` points each, the gallery's stage view, STYLE.md "Damage stages", the page test's `TODAY_*` | models + 40 | P156 | - |
| P159 | V1 | touch-ux-dev | view: building stages (`BuildingDamage`, the trimmed body and `Damage` child, the stage queue), the remembered stage, ghosts at their stage (`GhostMemoryLayer.building_layer`, `main.tscn`), the `LifeSettings` fields; HOW_TO_PLAY Buildings | 220 | P158 | - |
| P160 | A2 | art-director | art: the overlays (`scar1`, `scar2`, `loose`) in `assets/art/iso/neutral/dmg/`, their sheet, STYLE.md "Damage overlays"; `damage`, `hang` and `scar_milli` on the eight vehicle models; the gallery | SVG + models + 30 | P156, P157 | - |
| P161 | V1 | touch-ux-dev | view: vehicle overlays (`VehicleDamage`, `Scar` and `Loose` children of `Hull`, the rig kind bit, positions per hull frame, the pool reset); HOW_TO_PLAY Units | 180 | P159, P160 | - |
| P148 | V3 | touch-ux-dev | view (reworked, ADR 0028 §6): `AirFx`'s damage ring (64), soot, fire and sparks by stage from the `damage` points of buildings and vehicles, `LifeFx.unit_layer`; HOW_TO_PLAY Buildings and Units clauses | 200 | P145, P159, P160 | - |
| P162 | H | qa-engineer | test: the damage budget on the base arena (`perf_bases.tres`), in `test_life_budget.gd` | 0 | P146, P148, P161 | - |

**P148, how its row changes** (in the unit-life plan the row reads "damage smoke and flame by hp
(buildings, vehicles)", 120 lines, after P145): it moves here with its id, owner and lane (V3) and
grows to 200 lines. Its thresholds become the two stages (50 % and 25 % for buildings and vehicles
alike; the "vehicle below 33 %" line goes); its sources become the sheets' `damage` points instead of
`mix`-chosen roof points; it gains sparks and the vehicles' stage 2 fire; its quota grows from 24 to
64 slots in a ring of its own; it now Depends on P159 and P160 too. P26ar writes the pointer line in
the unit-life plan. In lane V3 the unit-life plan's P149 and P150 may go before P148 while P148 waits
for its art (pick order, they share `AirFx.gd`).

## Lanes, files and order
- **A** (art-director): P156 → P158. Owns `tools/artgen/`, the building models,
  `art_gallery_build.gd`. Today's generated files stay byte-identical in P156 (staleness test).
- **A2** (art-director): P160. Owns `assets/art/iso/neutral/`, the vehicle models' damage tags,
  `art_gallery_units.gd`. It waits for P157, so no sheet is committed that the bake cannot read (the
  pitfall of ADR 0027 §4), and for P156, whose validation knows the `damage` and `hang` kinds. P158
  and P160 both regenerate sheets, of different models: no file in common but the page test's
  `TODAY_*` and STYLE.md's change log (the second to merge rebases).
- **V2** (touch-ux-dev): P157. Owns `IsoAtlas.gd`, `WorldSort.gd`.
- **V1** (touch-ux-dev): P159 → P161. Owns `BuildingLayer.gd`, `GhostMemoryLayer.gd`, `UnitLayer.gd`,
  `BuildingDamage.gd`, `VehicleDamage.gd`, `LifeSettings.gd` and `data/life_settings.tres` (P148
  appends its fields after P159). `UnitLayer.gd` is 916 lines: P161 adds calls only (at most about
  30 lines); the logic lives in `VehicleDamage.gd`.
- **V3** (touch-ux-dev): P148 (with the unit-life plan's P149, P150 in pick order). Owns `AirFx.gd`,
  `LifeFx.gd`.
- **H** (qa-engineer): P162, after the unit-life plan's P146 has made `test_life_budget.gd`.
- **Shared, serialised:** `scenes/main.tscn` in P159 (`GhostMemoryLayer.building_layer`) and P148
  (`LifeFx.unit_layer`; the perf arena scene too if P147 has merged): the second rebases, the lead
  checks the combined tree once. `docs/HOW_TO_PLAY.md`: P159 and P148 edit the Buildings rows, P161
  and P148 the Units row "Watch a unit drive or fight": P148 rebases on whichever merged first.
  `assets/art/STYLE.md`: P156, P158, P160 (different sections, one change log).
- **Start at once after P26ar:** P156 and P157. Then P158 (after P156), P160 (after P156 and P157),
  P159 (after P158), P161 and P148 (after P159 and P160), P162.
- **Path:** P156 → P158 → P159 → P161 → P162 (five slots; P148 runs beside P161).

## Acceptance per row
Every row: its suite passes alone, gdformat and gdlint are clean, no `Time`, `randi`, `randf`,
`RandomNumberGenerator` or Particles node in a life file (`test_life_purity.gd` gains the new view
files), no allocation on a frame path (the source scan), no node per frame, every number from
`LifeSettings` or a sheet, no file in `game/sim` or `native/` touched; a phone-preview check line in
the PR. `mix`-driven tests assert exact counts for fixed id sets.

- **P156** A crafted model with `dmg1` and `dmg2` poses generates `<id>_dmg1.svg` and `<id>_dmg2.svg`
  in a test's temporary output (never committed here), deterministically; `shift`, `turn`, `hide`,
  `char <percent>` and a `damage=<k>` primitive each change exactly the pinned faces; the cut row
  equals the lowest projected row of the changed primitives' outlines before and after (crafted
  cases: a hidden chimney, a tilted mast, a charred roof, an added beam), and a raster check of the
  crafted case shows no pixel below it differs; the patch ends 4 art px under the cut and is cropped
  to its ink; `cuts` and the patch anchors round-trip in the sheet; a damage move of an `anim` group
  or a `mount` primitive fails the model with its line; the `damage` and `hang` kinds validate (one
  `hang` and one `damage` per hull frame for a vehicle); every committed frame and sheet is
  byte-identical (staleness test); the key band rules hold for charred faces.
- **P157** A sheet of faction `neutral` is collected for every player of every match and each frame
  with no key colour is one slot (a test with two triads finds one region for both players);
  `WorldSort` resolves its bases once per bake (no string key per change, the P137 hook); a frame of
  it that is missing logs no error unless the sheet lists it; the page tests of the cross-faction and
  both mirror matches include it; `atlas_bake_ms` reported in the PR.
- **P158** Each of the sixteen buildings has `dmg1` and `dmg2` from its model's poses (none
  hand-edited), damage in the top part of the picture (the examples: broken roof edges, missing
  panels, tilted or fallen chimneys, masts and stacks, scorch), the `anim` element's group and mount
  untouched, two `damage` points on the broken parts; the gallery shows each building intact, at
  stage 1 and at stage 2, in both orientations' zooms; the page test passes at most 3584 for the
  cross-faction match and both mirrors and its `TODAY_*` are updated (estimate 3534 for the cross
  match); if it does not pass, the row applies ADR 0028 §3's fallback (a), then (b), and says so in
  the PR; shadows and cards byte-identical.
- **P160** The neutral overlays (`scar1` 2 frames, `scar2` 2, `loose` 4: two skirt plates for
  `tracks`, two fenders for `wheels`) pass the hand-drawn rules (STYLE.md, no pattern or filter, no
  colour in either key band at saturation 0.30 or more, embers at hue 46° or more), hold ink inside
  their canvas with the gutter, and are authored in this repo (CREDITS unchanged); every vehicle
  model has a `damage` point on its top face and a `hang` point on the camera side per hull frame and
  a `scar_milli`; the gallery shows each vehicle at stage 1 and 2 in its 16 directions; the page test
  passes and its `TODAY_*` are updated (estimate: unchanged).
- **P159** `BuildingDamage.stage_of` matches the golden table (`[50, 25]`: 50 % exactly is 0, 49 %
  is 1, 25 % exactly is 1, 24 % is 2; max hp 1; hp 0); a complete building whose hp crosses a line
  shows the trimmed body (the region from the cut down, same base, offset by the cut) and its
  `Damage` child with `dmg<k>`, after `Body` and before `Anim` and `Head`; its node position,
  `rise`, `frame_box`, pick shape and `bar_lift_px` are unchanged; a site (and a cancelled site)
  shows stage 0 whatever its hp, and a site that took hits shows its stage in the frame it is
  complete; the `Anim` keeps its frames and rate at both stages; a hidden enemy building's stage
  change writes nothing and shows when it is seen again; `last_seen_stage` is written only while the
  enemy building is shown, in `ticked` (a frame that plays two ticks notes both), cleared on a new
  match and on a change of the local player; a ghost shows its remembered stage (trimmed sprite and
  `Damage` child, dim, no smoke) and an unknown id shows stage 0; at most `damage_changes_per_frame`
  stage changes are applied in one frame (a crafted 40-building burst takes 4 frames); writes counted
  in `life_writes`; the same snapshots give the same regions on two runs; `reduced` keeps it all.
  HOW_TO_PLAY Buildings row (below).
- **P161** A vehicle (any non-`INFANTRY` armour) whose hp crosses a line shows `Scar` (`scar1` or
  `scar2`, the look by `mix(id, salt)`, scaled by `scar_milli`) and at stage 2 `Loose` (the `marks`
  look), both children of `Hull`, at the sheet's `damage` and `hang` points of the hull frame shown,
  `Loose` mirrored when its point is left of the centre; a hull frame change writes their positions
  (at most 3 writes), a recoil rock or a drive rumble writes none to them and they move with `Hull`;
  a squad never gets them (the rig kind bit: a squad and a tanker never share a pooled rig); a rig out
  of the pool shows stage 0 until its unit's stage says otherwise; a hidden enemy rig's overlays are
  hidden with it; node counts flat after warm-up (the children are made with the rig); the `WorldSort`
  batch draws from one texture; `reduced` keeps them. HOW_TO_PLAY Units row (below).
- **P148** `AirFx` has a damage ring of `damage_slots` (64), its own, drawn in the same `_draw` from
  the same texture; a shown, complete building at stage 1 emits `soot` from each `damage` point every
  `damage_emit_ms` from a per-id and per-point phase, at stage 2 also `fire` and `spark`; a shown
  vehicle at stage 1 trails `exhaust` from its hull frame's `damage` point (born at the rig's drawn
  point, left in the world), at stage 2 `soot`, a `fire` at `damage_vehicle_fire_scale` and `spark`;
  a blackout does not stop it; a site, a squad, a hidden enemy and a source outside the view rect
  grown by a tile emit nothing; the ring never holds more than 64 and overwrites its oldest;
  `reduced` keeps the soot, the trail and the fire, drops the sparks, and the switch leaves the
  damage ring's puffs alive while the ambient ring empties; a new match empties both; the ambient
  emitters of P145 are unchanged (their tests green). HOW_TO_PLAY clauses (below).
- **P162** On `data/scenarios/perf_bases.tres` (150 mobile rows, 28 buildings, both strikes inside
  900 ticks, so real damage happens), plus a crafted pass that sets every building and vehicle row's
  hp to 40 % and then 20 % of its max in the snapshot (view input only): node and object counts flat
  after warm-up; life writes at most 60 per frame on average and 150 in any frame; the damage ring
  within 64; `WorldSort` and the ghost layer each draw from one texture; `LifeFx`'s draw items
  unchanged in number; the page at most 3584. Pinned numbers in the PR.

## Test plan (what is proven headless)
- **Sim untouched:** no file in `game/sim` or `native/` changes in any row; golden and checkpoint
  hashes unchanged; `test_sim_purity.gd` and `test_view_reads_snapshot.gd` green.
- **The stage function:** golden table and exact edges (P159), shared by P161 and P148.
- **Determinism of the look:** the same snapshots, ticks and alphas give the same regions, offsets,
  overlay looks and ring contents on two runs (P159, P161, P148); `mix`-picked looks are exact for a
  fixed id set.
- **Fog:** crafted worlds with a hidden enemy building and vehicle (no write, no smoke), an enemy
  building that is hit after it leaves sight (the ghost keeps the earlier stage), one seen again
  (the stage of now), a building that falls out of sight (its ghost keeps the last stage seen).
- **Art:** the generator's determinism and staleness, the geometric cut against a raster check, the
  `anim` and `mount` guard, the key band for charred faces and overlays, the page budget (P156,
  P158, P160).
- **Budget:** each row's bounds plus P162's combined test; the phone card (P147) is the only timing,
  and its run on `perf_bases` includes the strikes' damage.
- **Orientation:** every stage picture and overlay is world space; the gallery checks both
  orientations' zooms (P158, P160).

## Performance estimate
| Row | Work per frame | Writes |
| --- | --- | --- |
| P159 buildings | a stage check per building entry per tick (about 60 integer compares) | up to 5 per stage change, at most 12 changes per frame, twice per building per match |
| P159 ghosts | only on a ghost redraw (fog version) | a region and a child per ghost on a redraw |
| P161 vehicles | the stage check rides on `_note_hits`' hp compare | up to 6 per stage change; up to 3 per hull frame change of a damaged vehicle |
| P148 damage ring | one schedule test per damaged source in view per tick; at most 64 quads planned | 0 (quads) |

About 0.05 ms per frame on average and 0.15 ms in the worst moment on the phone (GDScript's 1 to
2 µs per touched row, an estimate the phone card judges), inside ADR 0027 §9's 0.56 ms with the
other life rows (about 0.3 ms). Draw calls unchanged (16, about 22 in the worst moment).

## HOW_TO_PLAY impact
No new control; wording only, no Teach mark.
- **P159**, Buildings, a new row "A building is badly damaged": "Under half its health a building
  shows cracks, soot and broken edges at its top; under a quarter it is falling apart, with parts
  tilted, fallen or missing. A building under construction does not show it. An enemy building shows
  its damage only while you see it; its dimmed picture in the fog shows the damage you last saw
  (`damage_stage_percent` in `data/life_settings.tres`)."
- **P161**, Units, "Watch a unit drive or fight" gains: "A vehicle under half its health is sooty;
  under a quarter it is scorched and a loose plate hangs off it. Infantry do not show it."
- **P148** adds to both: "A damaged building or vehicle smokes; under a quarter it burns and throws
  sparks (the sparks are off with reduced effects)."

## Questions for Michael
The two questions are at the end of ADR 0028 (how much of a building breaks; the vehicles' darker
look), each with its recommendation.

## Risks
- **The page.** The patches are estimated at 3534 of 3584 (50 px left); the estimate takes full-width
  patches, so cropping to ink should leave more, but a building whose damage reaches down its walls
  costs rows fast (35 % patches: 3583). P158's page test decides; ADR 0028 §3's fallbacks are in order
  and never touch the bake scale. P153 and P154 (unit-life plan) may then not fit: their rows already
  land only if the page has room.
- **The cut seam.** A sub-rectangle of a filtered texture samples the row above its top edge; the
  4 px overlap covers it at bake scale 0.75 and 0.5 too. P158's gallery check at the three zooms is
  where a seam would show.
- **Canvas items.** A battle with many damaged vehicles adds up to two sprites each to the sorted
  batch; cheap on the GPU, but each is a canvas item for the renderer. P162 counts them; P147's
  phone run decides; the fallbacks, in order, are the scar only from stage 2 and `Loose` dropped
  under `reduced` (a row of its own, with ADR 0028 §7 amended by a dated note).
- **Readability:** smoke and fire from many sources can drown the battle; every rate and life is in
  `data/life_settings.tres`, and the quota caps the puffs.
- **Art effort:** sixteen damage models with two stages each are real model work (P158); blockout
  quality first, polish later.
- **`main.tscn`:** two exports in two rows, rebased, one combined-tree check by the lead.
