# Plan: damage states of buildings and vehicles

Date: 2026-11-03. Base: `main` at 64f0402 (P141 merged; P145 `AirFx` in review on
`claude/p145-air-fx`). Decisions: `docs/adr/0028-damage-states.md`, **accepted** 2026-11-03
(Michael's answers 1 A, 2 A). Phase: 3 by date, ROADMAP Phase 5 by kind (polish), like the unit
life (ADR 0027); no ROADMAP box, and no row here is on the Phase 3 gate path. Rows P155-P162 and the
reworked P148 of `docs/plans/2026-11-02-unit-life.md`; P155 (this plan and ADR 0028) is done on
`claude/damage-states-plan`; the lead's acceptance row is P26ar.

**Reworked 2026-11-03 by ADR 0029** (`docs/adr/0029-buildings-shot-to-pieces.md`, proposed, P26as,
on `main` at 4b5c26d; revised 2026-11-04 on 321092e), from Michael's reference sheets for buildings that are shot to pieces and his
answer "Kun grafik": four stages (INTAKT, SKADET, KRITISK, RUIN) at 67 and 34, a whole `ruin` sprite
after DIED, a collapse, hit feedback and a collapse-only camera shake. The section "ADR 0029 rework"
below holds the new and re-scoped rows (P163-P167, P157c, P158a, P158b; P159, P148 and P162
re-scoped); where it differs from the rows above, it wins. P158 as written is replaced by P158a and
P158b.

## Goal
Michael, 2026-11-03: buildings and vehicles under 50 % hp look as if they are falling apart, in two
stages (under 50 %: cracks, soot, smoke; under 25 %: falling apart, fire and sparks); infantry not.
Buildings by generated pictures of each stage, vehicles by overlays, smoke and fire by P148. All of
it view and art, honest to the fog, in both orientations and on the web, inside the page budget
(3584) and rule 6.

## Out of scope
Repair and healing (no rule in the sim; ADR 0028 §2 says what a repair ADR would decide), stages
for infantry, a damaged defence head, a damaged shadow or build card, death animations (P152's
wrecks stay a separate row), sound, camera shake, any sim rule, state or event. (2026-11-03,
ADR 0029: the collapse at 0 %, the ruin and a collapse-only camera shake are now in scope; repair,
sound and any sim rule stay out.)

## Affected modules
- `tools/artgen/`: `ArtModel.gd`, `ArtMove.gd`, `ArtGen.gd`, `ArtSheet.gd`, `ArtRender.gd`,
  `ArtPalette.gd` (the char colour), `IsoSheetDef.gd` (`cuts`, `scar_milli`, `root`); the `damage`
  and `hang` emitter kinds (P156).
- Art: `assets/art/models/*/*.tres` (damage poses, `damage` and `hang` points), generated
  `<id>_dmg1.svg` and `<id>_dmg2.svg` under `assets/art/iso/*/bld/`, new hand-written
  `assets/art/svg/damage/*.svg` (each with a "Keep File" `.import`) and the hand-written sheet
  `assets/art/svg/damage/damage_sheet.tres`, outside the generated tree (ADR 0028 §4);
  `assets/art/STYLE.md` ("Damage stages" under Generated art, "Damage overlays").
- `game/view/`: new `BuildingDamage.gd`, `VehicleDamage.gd`; changed `IsoAtlas.gd` and
  `WorldSort.gd` (the neutral sheet), `BuildingLayer.gd`, `BuildingAnims.gd` (`dress_ghost` finds
  its `Anim` by name), `GhostMemoryLayer.gd`, `UnitLayer.gd` (calls only), `AirFx.gd`, `LifeFx.gd`
  (one export), `LifeSettings.gd`; `art_gallery_build.gd`, `art_gallery_units.gd`.
- `data/life_settings.tres` (new fields); `scenes/main.tscn` (two exports wired: P159, P148).
- Tests: `tests/art/` (generator, patches, overlays), `tests/view/` (stages, ghosts, overlays, the
  damage ring, the page test's `TODAY_*`), `tests/view/test_life_budget.gd` (P162).
- Docs: `docs/HOW_TO_PLAY.md` (Buildings, Units), dated notes by P26ar.

## Command and data changes
- No Command, event, state column or hash. The sim is untouched (ADR 0028 §1).
- `data/life_settings.tres` (`LifeSettings`, view-only): `damage_stage_percent` ([50, 25]), the one
  write budget `damage_writes_per_frame` (60) and its building share `damage_building_writes` (20)
  from P159; `damage_loose` (on) from P161; P148 appends `damage_emit_ms`, `damage_life_ms`,
  `damage_vehicle_fire_scale`, `damage_slots` (64).
- Sheet fields the generator writes: `cuts` (buildings), `scar_milli` (vehicles), emitter kinds
  `damage` (buildings: two points; vehicles: one per hull frame) and `hang` (vehicles, one per hull
  frame). `IsoSheetDef.root` (empty for every generated sheet) is set only in the hand-written
  neutral sheet.

## Rows
Size = production lines (tests, fixtures, models, generated frames and SVG not counted).
"At once" = may start the day P26ar lands.

| Row | Lane | Owner | Title | Size | Depends | Box |
| --- | --- | --- | --- | --- | --- | --- |
| P155 | - | architect | docs: this plan and ADR 0028 (accepted 2026-11-03); done on `claude/damage-states-plan` | 0 | - | - |
| P26ar | - | lead | docs: ADR 0028 on acceptance: Michael's answers in it, the dated notes in ADR 0027 §3, §4, §8, ADR 0023 §2, §5 and the unit-life plan's P148 row | 0 | P155 | - |
| P156 | A | art-director | art: generator v4, damage poses (`dmg1`, `dmg2`: `shift`, `turn`, `hide`, `char`, `damage=<k>` primitives), the geometric cut row, the patch crop with its overlap, `cuts`, `scar_milli`, the `damage` and `hang` kinds, `IsoSheetDef.root`; no model gets them here, today's files byte-identical (at once) | 230 | P26ar | - |
| P157 | V2 | touch-ux-dev | view: the neutral sheet in the bake: loaded from `IsoAtlas.NEUTRAL_SHEET` (not the index), added by `WorldSort.bake` after its art-id filter and after `_player_arts`, collected for every player as shared slots, its bases resolved once per bake; the page test counts it | 70 | P156 | - |
| P157b | V2 | touch-ux-dev | view (2026-11-03, ADR 0028 §3's second amendment): the damage patches baked at `DAMAGE_SCALE` (`IsoAtlas.build` and `planned_page` rasterise `dmg1`/`dmg2` parts at `bake_scale x DAMAGE_SCALE`; each region carries its own scale; `WorldSort`'s dress or the sprite scale uses it); the page test counts the patches at that scale | 60 | P157 | - |
| P158 | A | art-director | art: `dmg1` and `dmg2` of the sixteen buildings, two `damage` points each, the gallery's stage view, STYLE.md "Damage stages", the page test's `TODAY_*`; 2026-11-03 (Michael, ADR 0028 §3's amendment): stage 1 shows holes, down to half the body; stage 2 has largely collapsed, down to just above the foot; again 2026-11-03: stage 2 a low ruin (rubble, wall stubs); third: stage-2 poses may collapse the parts that carried anim elements, and the gallery's Stage view hides the `Anim` at stage 2 | models + 40 | P156; P157b for its final `TODAY_*` | - |
| P159 | V1 | touch-ux-dev | view: building stages (`BuildingDamage`, the trimmed body and `Damage` child, the stage queue in the buildings' write share), the remembered stage, ghosts at their stage (`GhostMemoryLayer.building_layer`, `main.tscn`, `BuildingAnims.dress_ghost` by name), the `LifeSettings` fields; HOW_TO_PLAY Buildings; 2026-11-03: the `Damage` child at its region's scale, at least 1 texel of overlap (ADR 0028 §3's second amendment); at stage 2 the `Anim` child is hidden, shown again at stage 1 or 0 (third amendment) | 230 | P158; also P160 if P158 took ADR 0028 §3's fallback (b) | - |
| P160 | A2 | art-director | art: the hand-written overlays (`scar1`, `scar2`, `loose`) in `assets/art/svg/damage/` with "Keep File" imports, their hand-written sheet `damage_sheet.tres` there (`root` set), STYLE.md "Damage overlays"; `damage`, `hang` and `scar_milli` on the eight vehicle models; the gallery | SVG + models + 30 | P156, P157 | - |
| P161 | V1 | touch-ux-dev | view: vehicle overlays (`VehicleDamage`, `Scar` and `Loose` children of `Hull`, the rig kind bit, positions per hull frame, the pool reset, the stage queue in the vehicles' write share, `damage_loose`); HOW_TO_PLAY Units | 190 | P159, P160 | - |
| P148 | V3 | touch-ux-dev | view (reworked, ADR 0028 §6): `AirFx`'s damage ring (64), soot, fire and sparks by stage from the `damage` points of buildings and vehicles, `LifeFx.unit_layer`; HOW_TO_PLAY Buildings and Units clauses | 200 | P145, P159, P160 | - |
| P162 | H | qa-engineer | test: the damage budget on the base arena (`perf_bases.tres`), in `test_life_budget.gd` | 0 | P146, P148, P161 | - |

(2026-11-03, ADR 0029: P158 is replaced by P158a and P158b; P159, P148 and P162 are re-scoped; new
rows P157c and P163-P167. See "ADR 0029 rework" below.)

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
- **A2** (art-director): P160. Owns `assets/art/svg/damage/`, the vehicle models' damage tags,
  `art_gallery_units.gd`. It waits for P157, so no sheet is committed that the bake cannot read (the
  pitfall of ADR 0027 §4), and for P156, whose validation knows the `damage` and `hang` kinds and
  whose `IsoSheetDef` has `root`. Nothing it commits is under `assets/art/iso/`, so
  `test_artgen.gd`'s generated-file check and the index's 28 sheets stay as they are. P158
  and P160 both regenerate sheets, of different models: no file in common but the page test's
  `TODAY_*` and STYLE.md's change log (the second to merge rebases).
- **V2** (touch-ux-dev): P157, after P156 (it reads `IsoSheetDef.root`), then P157b (2026-11-03:
  the patches at `DAMAGE_SCALE`). Owns `IsoAtlas.gd`, `WorldSort.gd`.
- **V1** (touch-ux-dev): P159 → P161. Owns `BuildingLayer.gd`, `BuildingAnims.gd`,
  `GhostMemoryLayer.gd`, `UnitLayer.gd`, `BuildingDamage.gd`, `VehicleDamage.gd`, `LifeSettings.gd` and `data/life_settings.tres` (P148
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
- **Start at once after P26ar:** P156. Then P157 and P158 (after P156), P160 (after P157), P159
  (after P158; and after P160 if P158 took fallback (b)), P161 and P148 (after P159 and P160), P162.
  (2026-11-03: P157b after P157; P158's final `TODAY_*` after P157b, so P159 waits for both.)
- **Path:** P156 → P158 → P159 → P161 → P162 (five slots); the vehicle chain P156 → P157 → P160 →
  P161 is as long, so P161 waits for whichever ends last. P148 runs beside P161. (2026-11-03: P157b
  joins the building path before P158's final `TODAY_*`: P156 → P157 → P157b → P158 → P159 → P161
  → P162; P158's model work may run beside P157 and P157b.)

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
  `hang` and one `damage` per hull frame for a vehicle); `IsoSheetDef.root` empty gives today's
  paths for every committed sheet and set gives `<root>/<id>_<part>[_d<NN>][_f<K>].svg`; every
  committed frame and sheet is byte-identical (staleness test); the key band rules hold for charred
  faces.
- **P157** `IsoAtlas.load_sheets()` is unchanged (the index only); the neutral sheet is loaded from
  `IsoAtlas.NEUTRAL_SHEET`, and while that file does not exist yet (before P160) the bake is today's,
  with no error; `WorldSort.bake` adds it after its art-id filter for every scenario (a scenario
  with no vehicle bakes it too) and after `_player_arts`, so a scenario with no factions still finds
  its players' factions from the type sheets alone (a test); a sheet of faction `neutral` is
  collected for every player and each frame with no key colour is one slot (two triads, one region);
  `WorldSort` resolves its bases once per bake (no string key per change, the P137 hook); the page
  tests of the cross-faction and both mirror matches include it (with a crafted neutral sheet until
  P160); `atlas_bake_ms` reported in the PR.
- **P157b** (2026-11-03, ADR 0028 §3's second amendment) `IsoAtlas.DAMAGE_SCALE` = 0.75;
  `IsoAtlas.build` and `planned_page` rasterise the `dmg1` and `dmg2` parts at `bake_scale x
  DAMAGE_SCALE` and every other part at `bake_scale` (a test: a crafted sheet's patch region is 75 %
  of its full-scale size, its body unchanged); each region carries its own scale, and `WorldSort`'s
  dress (or the sprite scale) draws a patch at `ART_SCALE / (bake_scale x DAMAGE_SCALE)`, so it
  lands on the same world px as at full scale; the page tests count the patches at that scale; it
  states the overlap rule P159 uses (at least 1 texel at every bake scale down to `MIN_SCALE`).
- **P158** Each of the sixteen buildings has `dmg1` and `dmg2` from its model's poses (none
  hand-edited), damage in the top part of the picture (the examples: broken roof edges, missing
  panels, tilted or fallen chimneys, masts and stacks, scorch), the `anim` element's group and mount
  untouched, two `damage` points on the broken parts; the gallery shows each building intact, at
  stage 1 and at stage 2, in both orientations' zooms; the page test passes at most 3584 for the
  cross-faction match and both mirrors and its `TODAY_*` are updated (estimate 3534 for the cross
  match); if it does not pass, the row applies ADR 0028 §3's fallback (a), then (b), and says so in
  the PR; shadows and cards byte-identical. (Amended 2026-11-03, Michael, after the first pass,
  ADR 0028 §3's amendment: "the top part" and the estimate are replaced. Stage 1: clear holes, roof
  or wall sections gone, the dark inside visible, the cut at most at 50 % of the body's rows from
  its top. Stage 2: largely collapsed, most of the upper structure gone or fallen, walls lowered or
  broken, rubble, the dark inside showing, down to just above the foot (a change that reaches the
  foot is still refused); the footprint, the foot outline and the `mount` and `anim` groups stay;
  stage 2 reads clearly stronger at game zoom without smoke. The first pass measured 3376 / 2774 /
  3002; the rework reports the real figures. If the page passes 3584, the lead and Michael choose
  the fallback, not this row (chosen the same day: P157b); `tests/art/test_artgen_damage.gd`'s
  "cut in the top third" case is on P156's fixture model, not a rule for the sixteen buildings.) (Amended again 2026-11-03: stage 2
  is a low ruin, only rubble and wall stubs on the footprint, a `mount` or `anim` element alone on a
  stub; the patches are baked at `DAMAGE_SCALE` (P157b), and the final `TODAY_*` are measured after
  P157b.) (Third amendment, 2026-11-03: stage-2 poses may collapse the parts that carried anim
  elements, since the `Anim` is hidden at stage 2; the gallery's Stage view hides the `Anim` at
  stage 2.)
- **P160** The neutral overlays (`scar1` 2 frames, `scar2` 2, `loose` 4: two skirt plates for
  `tracks`, two fenders for `wheels`) pass the hand-drawn rules (STYLE.md, no pattern or filter, no
  colour in either key band at saturation 0.30 or more, embers at hue 46° or more), hold ink inside
  their canvas with the gutter, and are authored in this repo (CREDITS unchanged); they and their
  sheet are under `assets/art/svg/damage/`, each SVG with a "Keep File" import (`importer="keep"`),
  the sheet's `root` set to that folder and `faction` `neutral`; `test_artgen.gd`'s generated-file
  check, the 28-sheet index and `test_art_assets.gd`'s hand-drawn rules pass unchanged; every vehicle
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
  enemy building is shown, in `ticked` (a frame that plays two ticks notes both), after a `_sync()`
  (a test kills a lower row in the same tick, so the entries' rows compact: the right building is
  noted); a building shown again applies its stage of now; the memory is cleared on a new match and
  on a change of the local player; a ghost shows its remembered stage (trimmed sprite and `Damage`
  child before its `Anim`, dim, no smoke), `dress_ghost` finds the `Anim` by name (a ghost with both
  children shows the rest frame on the `Anim`, not on the patch), and an unknown id shows stage 0;
  the stage writes cost 5 (0 → 1, 0 → 2) and 4 (1 → 2) and never pass `damage_building_writes` (20)
  in a frame: a crafted 40-building burst at stage 1 is applied 4 a frame in 10 frames, oldest first;
  writes counted in `life_writes`; the same snapshots give the same regions on two runs; `reduced`
  keeps it all. Under fallback (b) the stage-1 scars come from P160's sheet at the building's
  `damage` points (the same costs). (2026-11-03, ADR 0028 §3's second amendment: the `Damage`
  child is drawn at its region's scale (P157b), and the trimmed body and the patch keep at least 1
  texel of overlap at every bake scale, a test at `MIN_SCALE`. Third amendment: at stage 2 the
  building's `Anim` child is hidden (one visibility write more in 0 → 2 and 1 → 2), and it shows
  again, running, when the stage falls back to 1 or 0; a defence's `Head` stays at every stage; a
  test pins it, replacing "the `Anim` keeps its frames and rate at both stages" for stage 2.)
  HOW_TO_PLAY Buildings row (below).
- **P161** A vehicle (any non-`INFANTRY` armour) whose hp crosses a line shows `Scar` (`scar1` or
  `scar2`, the look by `mix(id, salt)`, scaled by `scar_milli`) and at stage 2 `Loose` (the `marks`
  look), both children of `Hull`, at the sheet's `damage` and `hang` points of the hull frame shown,
  `Loose` mirrored when its point is left of the centre; a stage change costs 3 (0 → 1), 5 (1 → 2)
  or 7 (0 → 2) writes; a hull frame change of a damaged vehicle writes 1 (stage 1) or 2 (stage 2)
  positions, and the flip only when the hang point changes side; those follow writes are applied in
  the frame, first, and the queued stage changes take what is left of the vehicles' share
  (`damage_writes_per_frame` minus `damage_building_writes`, 40), oldest first, so a crafted drop of
  100 vehicles to 40 % in one snapshot is applied in 8 frames and no frame's vehicle stage writes
  pass 40; a recoil rock or a drive rumble writes none to them and they move with `Hull`; a squad
  never gets them (the rig kind bit: a squad and a tanker never share a pooled rig); a rig out of the
  pool, a new rig and a rig that turns visible apply their row's stage of now; a hidden enemy rig's
  overlays are hidden with it and its stage changes write nothing; `damage_loose` off shows no
  `Loose`; node counts flat after warm-up (the children are made with the rig); the `WorldSort`
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
  hp to 40 % and then 20 % of its max in the snapshot (view input only), plus a pass that turns
  every damaged vehicle in step (one group move order): node and object counts flat after warm-up;
  the damage stage writes never above 20 (buildings) and 40 (vehicles) in a frame; all life writes at
  most 60 per frame on average and 150 in any frame (ADR 0028 §8's worst frame: 20 + up to 60 follow
  writes + about 47 of the other life rows, about 127 for 30 vehicles turning in step); if the
  in-step pass passes 150, the PR reports it and the lead sets `damage_loose` off in
  `data/life_settings.tres` (ADR 0028 §8's fallback); the damage ring within 64; `WorldSort` and the
  ghost layer each draw from one texture; `LifeFx`'s draw items unchanged in number; the page at
  most 3584. Pinned numbers in the PR.

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
| P159 buildings | a stage check per building entry per tick (about 60 integer compares) | 4 or 5 per stage change, at most 20 a frame (the buildings' share), twice per building per match |
| P159 ghosts | only on a ghost redraw (fog version) | a region and a child per ghost on a redraw |
| P161 vehicles | the stage check rides on `_note_hits`' hp compare | 3, 5 or 7 per stage change, at most 40 a frame with the follow writes (the vehicles' share); follow: 1 or 2 per hull frame change of a damaged vehicle, +1 flip on a side change, never deferred |
| P148 damage ring | one schedule test per damaged source in view per tick; at most 64 quads planned | 0 (quads) |

Worst frame of writes: 20 + 40 = 60 from the damage states while the follow writes fit the
vehicles' share, about 107 with the other life rows; a group of 30 damaged vehicles turning in step
gives 20 + 60 + 47 = 127, 40 of them 147, against ADR 0027 §9's 150 (P162 pins it; `damage_loose`
off is the fallback).

Work: about 0.05 ms per frame on average and 0.15 ms in the worst moment on the phone (GDScript's 1
to 2 µs per touched row, an estimate the phone card judges), inside ADR 0027 §9's 0.56 ms with the
other life rows (about 0.3 ms). Draw calls unchanged (16, about 22 in the worst moment).

## HOW_TO_PLAY impact
No new control; wording only, no Teach mark.
- **P159**, Buildings, a new row "A building is badly damaged": "Under half its health a building
  shows cracks, soot and broken edges at its top; under a quarter it is falling apart, with parts
  tilted, fallen or missing. (2026-11-03, ADR 0028 §3's amendment: P159 words it as holes under
  half, largely collapsed under a quarter.) A building under construction does not show it. An enemy building shows
  its damage only while you see it; its dimmed picture in the fog shows the damage you last saw
  (`damage_stage_percent` in `data/life_settings.tres`)."
- **P161**, Units, "Watch a unit drive or fight" gains: "A vehicle under half its health is sooty;
  under a quarter it is scorched and a loose plate hangs off it. Infantry do not show it."
- **P148** adds to both: "A damaged building or vehicle smokes; under a quarter it burns and throws
  sparks (the sparks are off with reduced effects)."

## ADR 0029 rework (2026-11-03, P26as; revised 2026-11-04 after the docs lens)
Decisions: `docs/adr/0029-buildings-shot-to-pieces.md` (proposed). Base: `main` at 321092e (P157
merged as #299). Open at the time of writing: P157b (PR #300 at 1c2a031), P158
(`claude/p158-building-damage`, 573f720, on hold). Size = production lines (tests, fixtures, models,
generated frames and SVG not counted: an art row's generated files never count toward the ~400-line
guide). "At once" = may start the day P26as lands: the rows that start at once do not depend on the
open questions of ADR 0029.

| Row | Lane | Owner | Title | Size | Depends | HOW_TO_PLAY |
| --- | --- | --- | --- | --- | --- | --- |
| P26as | - | architect | docs: ADR 0029 and this section | 0 | P26ar | no |
| P26at | - | lead | docs: ADR 0029 on acceptance: Michael's answers in it; dated notes in ADR 0028 (top; §3's third amendment: the `Anim` at stage 2 follows its carrier), ADR 0027 §3 (quota table: damage 24 → 80, collapse 40, hit 16) and §8, ADR 0023 §5, the unit-life plan's out-of-scope line | 0 | P26as, the answers | no |
| P163 | A | art-director | art: generator v5a: the `ruin` pose (`damage=3`, a whole picture cropped to ink, no `anim`, `mount` may move, debris limits, the height refusal, needs `dmg2`), materials `interior`, `slab`, `hole`, `rebar`, `beam`, moves `blow` and `soot`, `char` of key faces out of the band, the counts (2-4 `damage`/`dmg_gas`/`dmg_spark`, 1-3 `ruin`), the ink test for points and emitters, `anim_kritisk`, emitter `group=` and `emitter_quiet`, the odd-canvas refusal, the key-share test; at once | 240 | P26as | no |
| P163b | A | art-director | art: generator v5b: shapes `broken` (teeth) and `rod` (with `bend`), helpers `petals` and `rubble` | 200 | P163 | no |
| P167 | A4 | art-director | art: life atlas frames `hit_flash`, `chip`, `dust_cloud`, `ember`, `glow`, `jet`, their `LifeRegions` entries, STYLE.md's fx section, the gallery's life page; at once | SVG + 30 | P26as | no |
| P157c | V2 | touch-ux-dev | view: `ruin` joins `IsoAtlas.DAMAGE_PARTS` with its own factor `RUIN_SCALE`, equal to `DAMAGE_SCALE` (0.75) at first (P158b lowers it if question 2 says so); the page tests count a crafted ruin | 30 | P157b | no |
| P158a | A | art-director | art: the eight Fossil buildings in four stages (`dmg1` SKADET, `dmg2` KRITISK, `ruin`), 2-4 typed damage points (a second one for `defence_turret`), 1-3 ruin points, `anim_kritisk`, emitter groups; carries the P158 branch's gallery Stage button (now with RUIN), page-test structure and `DAMAGE_PARTS` pin; STYLE.md "Damage stages" rewritten to four stages; `TODAY_*` | models + 60 | P163b, P157c | look text if P159 merged first |
| P158b | A3 | art-director | art: the eight Renew buildings, the same (a second point for `renew_defence`); the final `TODAY_*`; ADR 0029 §11's steps 3 and 4 if needed | models + 10 | P163b, P157c; merges after P158a | look text if P159 merged first |
| P159 | V1 | touch-ux-dev | view (re-scoped): building stages SKADET and KRITISK by `building_stage_percent` [67, 34], `vehicle_stage_percent` [50, 25]; the `Anim` at KRITISK by `anim_kritisk`; ADR 0029 §12's seam rule; the ruin hook and the `BuildingRuins.gd` stub; the rest as its row above | 260 | P157b | yes (what it shows) |
| P161 | V1 | touch-ux-dev | view: vehicle overlays, as its row above; reads `vehicle_stage_percent` | 190 | P159, P160 | yes (as above) |
| P148 | V3 | touch-ux-dev | view (re-scoped again): `FxRing`; particles per stage for buildings and vehicles; the burning points; the smoke cap and defaults; the glow pass; `jet` at SKADET, sparks by point type; quiet ambient emitters; the damage ring 80 | 260 | P145, P159, P160, P167 | yes |
| P165 | V6 | touch-ux-dev | view: the collapse and the ruin (`BuildingRuins` filled in, `CollapseFx`): the timed sequence, sink, switch, dust inside 250-900 ms, the slot split for many collapses, 45 s, the sink to the crater, `crater_scale_milli`, removal by a shown building on its tiles, the fog rule, sites and cancelled sites, the ruin's smoke and embers | 320 | P159, P148, P157c, P167 | yes |
| P166 | V7 | touch-ux-dev | view: hit feedback (`HitFx`: the flash and 3-5 chips from IMPACT and from hitscan SHOT on shown buildings, `BuildingLayer.row_of`) and the collapse camera shake (`CameraShake`, the offset terms in `RtsCamera`) | 190 | P148, P165, P167 | yes |
| P162 | H | qa-engineer | test (re-scoped): the damage budget plus collapses, hits and ruins on `perf_bases.tres` | 0 | P146, P148, P161, P165, P166 | no |

**Rows that do not change:** P156 and P157 (merged), P157b (#300; its `DAMAGE_SCALE` doc block is
ADR 0029 §12's seam rule), P160 (the vehicle overlays). P161 changes only the name of the list it
reads (`vehicle_stage_percent`); if Michael answers question 1 with "follow the buildings", the list
becomes [67, 34] by a data edit and its HOW_TO_PLAY clause says "two thirds" and "a third".

### Lanes, files and order (rework)
Lane names are this plan's; the unit-life plan's V4 and V5 (P141, P147) are not reused.
- **A** (art-director): P163 → P163b → P158a. Owns `tools/artgen/`, the Fossil building models,
  `art_gallery_build.gd`, the page test's `TODAY_*` until P158a merges.
- **A3** (art-director): P158b, beside P158a after P163b; owns the Renew building models; merges
  after P158a (rebases `TODAY_*`, STYLE.md's change log and the gallery).
- **A2** (art-director): P160 (unchanged; may start now, P157 has merged).
- **A4** (art-director): P167 at once (`assets/art/svg/fx/life_atlas.svg`, `LifeRegions.gd`,
  `art_gallery_life.gd`).
- **V2** (touch-ux-dev): P157b → P157c (`IsoAtlas.gd`, `WorldSort.gd`).
- **V1** (touch-ux-dev): P159 → P161 (`BuildingLayer.gd`, `BuildingDamage.gd`, `BuildingAnims.gd`,
  `GhostMemoryLayer.gd`, the stub `BuildingRuins.gd`, `UnitLayer.gd`, `VehicleDamage.gd`,
  `LifeSettings.gd`, `data/life_settings.tres`; later rows append their fields).
- **V3** (touch-ux-dev): P148 (`AirFx.gd`, `LifeFx.gd`, new `FxRing.gd`).
- **V6** (touch-ux-dev): P165 (fills `BuildingRuins.gd`; new `CollapseFx.gd`; calls in
  `BuildingLayer.gd`; one ring line in `AirFx.gd`).
- **V7** (touch-ux-dev): P166 (new `HitFx.gd`, `CameraShake.gd`; two lines in `RtsCamera.gd`;
  `BuildingLayer.row_of`; one ring line in `AirFx.gd`; `LifeFx.gd` makes `CameraShake`).
- **H** (qa-engineer): P162.
- **Shared, serialised:** `AirFx.gd` (P148, then one line each from P165 and P166, in that order);
  `BuildingLayer.gd` (P159, then P165's calls, then P166's `row_of`); `BuildingRuins.gd` (P159's
  stub, then P165); `data/life_settings.tres` (P159 first, then P148, P165, P166 append);
  `docs/HOW_TO_PLAY.md` Buildings rows (P159, P158a/b, P148, P165, P166: each rebases on the one
  before); `assets/art/STYLE.md` (P163, P163b, P167, P158a, P158b: different sections, one change
  log). `scenes/main.tscn`: P159 and P148 as above; P165 and P166 add no export (`CameraShake` and
  the rings are made in code from `LifeFx`'s existing references).
- **Start at once after P26as:** P163, P167, P160; P157c and P159 after P157b. The questions touch
  only P159's data (question 1), P158b's steps 3-4 and `RUIN_SCALE` (question 2), P165's fade
  (question 3) and P166's shake (question 4); the answers are expected before those rows open.
- **Path:** P157b → P159 → P148 → P165 → P166 → P162 (six slots; P157 has merged). P148 also waits
  for P160 (A2) and P167 (A4); both may start now and are one slot each, so the path runs through
  them only if either takes longer than P157b and P159 together. The art path P163 → P163b →
  P158a → P158b (four) runs beside it; the vehicle path P160 → P161 joins at P162. P159 no longer
  waits for the art: a sheet without damage parts shows intact, so P159 and P165 are tested on
  crafted sheets and the real look arrives with P158a and P158b.
- **HOW_TO_PLAY's look text** ("blown windows, soot, a broken corner ...") describes the art, so it
  lands with whichever of P159 and P158b merges last; P159 alone writes only what it shows (the
  picture changes at two thirds and at a third).

### Acceptance per row (rework)
Every row: the common rules above (its suite alone, gdformat and gdlint, no `Time`, `randi`,
`randf`, `RandomNumberGenerator` or Particles node in a life file, `test_life_purity.gd` gains the
new view files, no allocation on a frame path, no node per frame, every number from `LifeSettings`
or a sheet, no file in `game/sim` or `native/`, a phone-preview check line in the PR). Art rows:
every committed generated file deterministic and byte-identical on a second run (staleness test).
- **P163** On a crafted model in a test's temporary output (none committed): a `ruin` pose
  generates `<id>_ruin.svg`, a whole picture cropped to its ink, with `damage=3` primitives only
  there and no `anim` primitive; a ruin may move `mount`, `dmg1` and `dmg2` still may not; a ruin
  primitive more than a quarter tile outside the footprint or above 0.1 tile there is refused, as
  is a ruin whose ink rises above half the body's canvas and a ruin without `dmg2`; `interior`,
  `slab`, `hole`, `rebar` and `beam` draw their pinned colours; `blow 50` on a group of four panes
  turns exactly the two first in the hash order into `hole` and keeps the frames; `soot <p>` chars
  every hull face; a `char` of a key face whose result stays inside the key band is refused, one
  outside it passes; 2-4 points of `damage`, `dmg_gas`, `dmg_spark` pass, 1 and 5 are refused; a
  point below `dmg1`'s cut, or whose spot is not inside the outline of a primitive drawn in `dmg1`
  or in `dmg2`, is refused; 1-3 `ruin` points with ink under them pass, 0, 4 and one over empty
  ground are refused; `anim_kritisk run` is written to the sheet and refused when the `anim`
  part's lowest point has no ink under it in `dmg2`; an ambient emitter with `group=` whose group a
  stage moves or hides gets `emitter_quiet` of that stage (1 when `dmg1` moves it, 2 when only
  `dmg2` does, 0 without a group); vehicles and infantry keep their counts; an odd body canvas
  height with damage parts is refused; the key-share test (the stages rasterised with
  `Image.load_svg_from_string`) passes the crafted model at SKADET 55-85 %, KRITISK 20-50 %, RUIN
  1-20 % and fails a crafted model outside them; every committed file is byte-identical.
- **P163b** `broken teeth=N low=f` draws N teeth between f and the full height, the same on two runs
  and different for two lines; `rod` draws a stroke at its width with no outline at its midpoint's
  depth, `bend` makes two segments; `petals` expands to `n` plates turned by `tilt` and an
  `interior` disc, `rubble` to `n` ground primitives inside its rect (exact counts); every
  committed file is byte-identical.
- **P167** The new frames pass the hand-drawn rules (STYLE.md, no filter or pattern, no colour in
  either key band at saturation 0.30 or more, flames, embers and the glow at hue 46° or more,
  `hit_flash` white); each has a `LifeRegions` entry (atlas, first region, count, size, pivot); the
  gallery's life page shows them; CREDITS unchanged.
- **P157c** `IsoAtlas.RUIN_SCALE` is a constant of its own, equal to `DAMAGE_SCALE` (0.75);
  `IsoAtlas.part_factor(&"ruin")` is `RUIN_SCALE`; a crafted sheet's ruin region is that share of
  its full-scale size and its body is unchanged; `WorldSort.dress` draws it at the same world px as
  at full scale; the page tests count a crafted ruin; the `DAMAGE_PARTS` pin lists `dmg1`, `dmg2`,
  `ruin`.
- **P158a, P158b** Each building of the faction has `dmg1`, `dmg2` and `ruin` from its model (none
  hand-edited) after ADR 0029 §4's table, its material rule and its own rule (the barracks' team
  paint burns off from the top down; the refinery's thin pipes and flare bend and never shatter);
  SKADET changes the silhouette (a nick at a corner, a mast or a wing; blown panes with frames; soot
  over the holes) within the top half of the body's rows; KRITISK shows a collapsed part with the
  inside visible (slabs, rebar or beams, dark rooms) down to just above the foot at most; the ruin
  is low (at most half the canvas height), messy and sooted, never clean blocks, with debris outside
  the footprint and no `anim` or head; the key share passes the bands of P163; 2-4 typed damage
  points (the two defences gain a second one) and 1-3 ruin points, all with ink under them;
  `anim_kritisk` set for each building with an `anim` (run where the carrier stands in `dmg2`, hide
  where it falls); the ambient emitters on a chimney, flare, stack or tank that a stage breaks name
  their group (the headquarters, the refinery, the power plant, the renew refinery); the gallery
  shows each building at the four stages in both orientations' zooms (the `Anim` at KRITISK by
  `anim_kritisk`, none in the ruin); shadows and cards byte-identical; the page test passes at most
  3584 for the cross-faction match and both mirrors, with `TODAY_*` updated and the figures in the
  PR. P158b: if the measured page passes 3584, or has under 30 rows left, after ADR 0029 §11's
  steps 1-2, it applies step 3 (SKADET within the top 35 %), and if that is still not enough, the
  option Michael chose in question 2 (`RUIN_SCALE` or `DAMAGE_SCALE`), and says so in the PR. The
  look text of HOW_TO_PLAY lands here if P159 merged first (below).
- **P159** (re-scoped) As its acceptance above, with: `BuildingDamage.stage_of` over the golden
  table of `[67, 34]` (hp 67 of 100 is 0, 66 is 1, 34 is 1, 33 is 2, 1 is 2; max hp 1 with hp 1 is 0)
  and of `[50, 25]` for vehicles (the earlier table); a data test holds `100 > P1 > P2 > 0` for both
  lists. The `Anim` at KRITISK: shown and running when the sheet's `anim_kritisk` is true, hidden
  when it is false (one visibility write, as ADR 0028 §8), running at SKADET; a defence's `Head`
  stays at both stages; this replaces "the `Anim` is hidden at stage 2" above. The seam (ADR 0029
  §12): the `Damage` patch is a sibling of `Body` at the same position, the body is trimmed by
  `IsoAtlas.body_cut_row(cut, canvas_h, region_h)` with `region_filter_clip_enabled`, the patch uses
  its whole region, the strict overlap invariant holds at `MIN_SCALE` for crafted even canvases (and
  the odd 101 / 97 case gives 0, the reason for P163's refusal), a ghost's patch child has
  `scale = body_texels / patch_texels`, and a `show_frame` or `show_base` after a stage is followed
  by the trim again (a test). The ruin hook: P159 creates `game/view/BuildingRuins.gd` as a stub
  with `adopt(entry, died_tick, was_site, cancelled)`, and `_drop` of a shown building calls it (the
  DIED records of the tick give the tick and `Production.DIED_CANCEL_FLAG_AT`); the stub frees the
  node and lays the crater exactly as today (the crater and node counts of today's tests hold).
  HOW_TO_PLAY, Buildings, a new row "A building is badly damaged", what P159 shows: "Under two
  thirds of its health a building's picture changes to a damaged one, and under a third to a
  critically damaged one. A building under construction does not show it. An enemy building shows
  its damage only while you see it; its dimmed picture in the fog shows the damage you last saw
  (`building_stage_percent` in `data/life_settings.tres`)." The look text, landed by the later of
  P159 and P158b: "Damaged: blown windows, soot and a broken corner, mast or wing. Critical: part of
  it has collapsed and you can see inside."
- **P148** (re-scoped again) As its acceptance above, with: the rings are `FxRing` objects drawn in
  `AirFx`'s one `_draw` (the emitter ring of P145 unchanged, its tests green); the damage ring holds
  `damage_slots` (80); a shown complete building at SKADET burns exactly the point
  `LifeClock.pick(id, SALT_BURN, n)` with grey `smoke` and, by its type, a small `fire` and a weak
  `glow` (`damage`), a `jet` and a weak `glow` (`dmg_gas`) or sparks and no fire (`dmg_spark`); at
  KRITISK the points `s, s + 1, ...` up to `damage_burning_points[1]` with `soot`, a large `fire`
  and a strong `glow` (`damage` and `dmg_gas`: **a `jet` only ever at SKADET**), sparks at every
  burning point, and sparks and no fire at a `dmg_spark` point; three buildings of one type with
  fixed ids burn the pinned points; with the default numbers no burning building has more than 15
  live smoke puffs, and a data test holds every stage's numbers under `damage_smoke_cap` (30); every
  glow is drawn before every other quad; an ambient emitter stops from its sheet's `emitter_quiet`
  stage on and keeps puffing before it; vehicles as ADR 0028 §6 with `vehicle_stage_percent`;
  `reduced` keeps smoke, fire and glow and drops the sparks. HOW_TO_PLAY, Buildings and Units: "A
  damaged building burns at one spot with thin grey smoke; under a third it burns from inside with
  thick black smoke and throws sparks. A damaged vehicle smokes; under a quarter it burns and
  throws sparks (the sparks are off with reduced effects)."
- **P165** `BuildingRuins.adopt` (P159's stub) runs the collapse. A crafted DIED of a shown complete
  building plays, on match time from the DIED tick: at 0 ms the `Anim` and `Head` hidden and the
  collapse ring's flash and `collapse_fire_puffs` fire; the sink steps (`collapse_sink_steps`, to
  `collapse_sink_percent` of the rise by `collapse_switch_ms`) with `collapse_dust_puffs` dust and
  `collapse_debris` debris, every dust puff born and gone inside `collapse_dust_ms` (250-900); at
  `collapse_switch_ms` the `Body` dressed with `ruin`, `Damage` hidden, the shadow removed; from
  `ruin_from_ms` the ruin's points smoke (`ruin_smoke_ms`) and glow with embers (`ruin_ember_ms`) in
  the damage ring within the smoke cap; at `ruin_life_ms` the sink to nothing in `ruin_fade_steps`
  over `ruin_fade_ms` with `ruin_fade_dust_puffs`, then the node freed; the crater is laid at DIED,
  scaled by `crater_scale_milli` (a refinery's 1.5 times the default), and stays; `n` collapses in
  one tick get at most `collapse_slots / n` puffs each, dust first (eight at once: five dust each);
  a pause freezes the sequence and two runs give the same regions and quads; a ruin is not picked,
  has no bar and leaves the selection; a site's death plays the flash, explosion and dust and ends
  in the crater with no ruin; a cancelled site plays nothing and leaves no crater; a sheet without
  `ruin` ends in the crater at the switch; an own or shown building placed on overlapping tiles
  removes the ruin in that tick, a hidden enemy one does not until it is shown; an enemy ruin is
  drawn only while any cell of its footprint is seen, and one seen again inside its time is drawn
  with the time left; a building that died unseen leaves no ruin; the 17th ruin ends the oldest;
  collapse writes go first in `damage_building_writes` and a crafted eight-building kill never
  writes more than 20 in a frame, with no lost step; no node at DIED; `BuildingRuins` tells
  `CameraShake` (P166) that a collapse started; `reduced` keeps the ruin, the fire, the flash and
  the dust and drops debris, embers and the ruin's smoke. HOW_TO_PLAY, Buildings, "A building is
  destroyed" becomes: "It flashes, sinks into itself in a cloud of dust and leaves a low, smoking
  ruin for 45 seconds, then a crater for the rest of the match. The ruin blocks nothing: units drive
  over it, and a building placed on it clears it at once. One you saw fall, and any of your own,
  leaves the ruin and the crater; one destroyed out of your sight leaves neither."
- **P166** A hit on a shown building, found by `BuildingLayer.row_of(id)` (-1 for a building that
  is gone), draws a `hit_flash` for `hit_flash_ms` (60) at the lifted hit point inside the middle
  `hit_flash_box_milli` (500) of its `frame_box` and exactly `hit_chips[0] + pick(hit id, SALT_CHIP,
  hit_chips[1] - hit_chips[0] + 1)` chips living `hit_chip_ms` (pinned for fixed ids); a hit is an
  IMPACT with a target, or the SHOT of a weapon whose `weapon_projectile_speed` is 0 (the rifle:
  target id at +4, point at +6/+7); a SHOT of a shell weapon, an IMPACT on a unit, on a hidden
  building or with target 0 draws none; a hit whose target died in the tick draws none (the
  collapse's flash is P165's); the hit ring holds `hit_slots` (16) and overwrites its oldest; a
  collapse that `BuildingRuins` reports and whose footprint centre is in the visible world rect
  shakes `RtsCamera.offset` by at most `collapse_shake_px / zoom` for `collapse_shake_ms`, decaying,
  and ends at 0; a collapse off screen, unseen or of a cancelled site does not shake; a second
  collapse restarts the shake, never adds; a pause ends it at 0; `position`, the clamp and the zoom
  snap never change by it, and `screen_to_world(world_to_screen(p))` is `p` during a shake;
  `reduced` keeps the flash, drops the chips and the shake. HOW_TO_PLAY, Buildings, "A building is
  hit, or selected" gains: "A white flash and a few chips show where a shot hit it."; "A building is
  destroyed" gains: "If you watch it fall, the view shakes briefly (not with reduced effects)."
  (Question 4 may change or drop the shake.)
- **P162** (re-scoped) As its acceptance above, plus: a crafted tick that kills eight shown buildings
  at once and a siege pass of shells and rifle fire on buildings in view; the building writes never
  above 20 in a frame with the collapse steps; `AirFx` never plans more than 240 quads (80 + 80 + 24
  + 40 + 16); at most 16 ruins; node and object counts flat after warm-up; the page at most 3584.
  Pinned numbers in the PR.

### Test plan (rework, what is proven headless)
- **Sim untouched:** no file in `game/sim` or `native/`; golden and checkpoint hashes unchanged.
- **Stages:** the two golden tables (P159); the `Anim` at KRITISK by `anim_kritisk` (P159).
- **Seam:** the strict overlap at `MIN_SCALE`, the ghost scale and the trim after `show_frame` (P159).
- **Collapse and ruin:** the timed sequence on match time, the dust window, the slot split, the
  removal rule, the fog rule, sites and cancels, the crater scale, the cap, the writes, determinism
  on two runs (P165).
- **Particles:** the burning points by `pick`, the jet only at SKADET, the smoke cap, the glow
  order, quiet emitters, the ring caps, reduced (P148, P165, P166).
- **Hits:** IMPACT and hitscan SHOT, the row lookup, exact chip counts (P166).
- **Art:** the generator's new refusals, the ink test and shapes on crafted models, staleness, the
  key share, the page (P163, P163b, P158a, P158b, P157c).
- **Budget:** P162 on the base arena; P147's phone card is the only timing.

### Risks (rework)
- **The page** is at its edge (ADR 0029 §11): with steps 1-3 the estimate is 3561-3586, so step 4
  (question 2) is likely needed. P158b measures it.
- **`AirFx` time:** the worst moment is estimated at about 0.55 ms against ADR 0027 §9's 0.56 ms
  with a per-quad cost derived, not measured; the rings are data and P162 and the phone card decide
  (ADR 0029 §11's fallbacks).
- **A mass kill** (a strike): the collapse ring gives each building only a few dust puffs, so the
  switch to the ruin may show through; accepted for the budget, P162's eight-building pass shows it
  in the gallery check.
- **Art effort:** 48 generated pictures with new materials and shapes; P158a and P158b split it by
  faction so they run in parallel.
- **A cancelled site today:** `game/view/` reads no `Production.DIED_CANCEL_FLAG_AT`, so a shown
  cancelled site seems to get `EffectsLayer`'s DIED burst and `BuildingLayer`'s crater now. P165
  skips the collapse and the crater for it; the burst is `EffectsLayer`'s (HUD lane): a follow-up
  for the lead to check.

## Questions for Michael
ADR 0029's four questions (the vehicles' thresholds, the page fallback, the ruin's fade, the camera
shake) are at its end, each with its recommendation.

The two questions are at the end of ADR 0028 (how much of a building breaks; the vehicles' darker
look), each with its recommendation.

## Risks
- **The page.** The patches are estimated at 3534 of 3584 (50 px left); the estimate takes full-width
  patches, so cropping to ink should leave more, but a building whose damage reaches down its walls
  costs rows fast (35 % patches: 3583). P158's page test decides; ADR 0028 §3's fallbacks are in order
  and never touch the bake scale. P153 and P154 (unit-life plan) may then not fit: their rows already
  land only if the page has room. (2026-11-03, ADR 0028 §3's amendment: the first pass measured
  3376; stage 1 now reaches half the body and stage 2 nearly the foot, so the page may pass 3584;
  P158's rework measures it and the lead and Michael choose the fallback. Chosen the same day: the
  patches at `DAMAGE_SCALE` 0.75, P157b.)
- **The cut seam.** A sub-rectangle of a filtered texture samples the row above its top edge; the
  4 px overlap covers it at bake scale 0.75 and 0.5 too. P158's gallery check at the three zooms is
  where a seam would show.
- **Canvas items.** A battle with many damaged vehicles adds up to two sprites each to the sorted
  batch; cheap on the GPU, but each is a canvas item for the renderer. P162 counts them; P147's
  phone run decides; the fallback is `damage_loose` off (a `.tres` edit), then the scar only from
  stage 2 (a row of its own, with ADR 0028 §4 amended by a dated note).
- **Readability:** smoke and fire from many sources can drown the battle; every rate and life is in
  `data/life_settings.tres`, and the quota caps the puffs.
- **Art effort:** sixteen damage models with two stages each are real model work (P158); blockout
  quality first, polish later.
- **`main.tscn`:** two exports in two rows, rebased, one combined-tree check by the lead.
