# Plan: visual polish pass (the eight board proposals) and the SKADET picture

Date: 2026-11-09. Base: `main` at b6bfe95 (Phase 4 wave 7 merged; waves 8 and 9 running). Author:
architect (row P200, branch `claude/plan-visual-polish`). Decisions:
- `docs/adr/0034-skadet-shows-the-intact-picture.md`, **accepted** 2026-11-09 (Michael's "A",
  relayed by the lead): buildings drop the SKADET picture.
- `docs/adr/0035-visual-polish-fog-tint-map-edge-world-grade-team-marks.md`, **proposed**: the parts
  of the eight proposals that change accepted ADRs (fog colour, map edge, world grade, team colour
  under units and on the ring, the draw-call forecast).

Revised 2026-11-09 after the docs lens (touch-ux-dev as implementer; 4 must, 6 should): the
damage part lists stay stage-indexed (P201, P202, ADR 0034 §3), P201 merges after P202, P216 owns
the card's forecast constants, the Hud moves to layer 2 under `WorldGrade` at layer 1 (P214), one
worst-case figure (about 25), and the smaller fixes listed in the commit.

Phase: ROADMAP Phase 5 ("Polish and meta") by kind, pulled forward as ADR 0027's unit life was; it
adds no ROADMAP box (the polish has no acceptance criterion of its own; each row has its phone
check). No row touches `game/sim`, `game/ai`, `native/` or balance data, so none changes a golden
hash, a balance run's result or the Phase 4 gate, and **no row waits for Phase 4's gate**. One row
(P214) writes `data/look_settings.tres`, and any merge under `data/**` starts `balance.yml`: see
Risks.

## Goal
Michael, 2026-11-09: "ja" to all eight proposals of art-director's Figma board "Polish proposals"
(https://www.figma.com/design/QyyrwPHx9QtBFSNW5j0S3l; the exports `polish_1_*.png` to
`polish_8_*.png` and `polish_board_overview.png`, and the real phone screenshots, were read for this
plan). Also Michael, 2026-11-09, answer "A": drop the buildings' SKADET picture (ADR 0034). The
battlefield should read better on a phone at zoom 0.75 to 1.5, in both orientations and on the web
preview, inside rule 6's budget, with no sim change.

## Out of scope
Shaders, materials, additive blending, Particles nodes, blur; any sim, AI or Command change; a
settings switch for the grade (Phase 5's settings screen; until then `LifeSettings.reduced`); new
units, buildings or maps; the minimap's look (it keeps MapView's 8 px bake); the building selection
frame's colours; sound.

## What exists, per proposal (checked on b6bfe95)
| # | Proposal | What is there today | What the board gets wrong or leaves out |
| --- | --- | --- | --- |
| 1 | Contact shadows / AO | `tools/artgen/ArtShadow.gd`: cast shadows, black 35 % as one group, the contact shadow is the base of the same polygon; unit shadows z 2 (rig child), building shadows in `DecalLayer` z 1; all on the sorted world's page, baked once per faction (no key colour) | "No runtime cost" holds for draw calls, but larger shadow canvases add page rows, and the cross page is 3550 of 3584. STYLE.md "Light" forbids gradients in generated frames: the soft pad must be stepped (like ADR 0029's glow) |
| 2 | Ring and health bar | `ui/selection_ellipse.svg` (white 12 px band, dark outline, 168 x 96, `RING_TEX_RX_PX` 72) on a `Ring` sprite at z 3, own units only; `HealthBarLayer.gd`: 6 dp bars of filled rects in one `_draw`, own plain, enemy notched (Michael's answer 3), 1 dp dark edge already there | Bars already have the outline. A ring tinted by `modulate` alone fails for dark triads (Kul) and orange is near the amber of attack-move and enemy bars; 10 % ticks on a 16 or 22 dp bar are 1.6-2.2 dp apart, too dense. Rounded bar ends would be per-item draw calls (ADR 0011) |
| 3 | Team pad | Nothing; team colour is 8-12 % of a model as bands (ADR 0022 Q3) | The board says the pad lets allegiance read "in greyscale": it does not (both sides get a pad); the colour-free cues stay the own-only ring and the enemy notch. A pad in key colours makes unit shadow frames per player (mirror pages grow) |
| 4 | Build cards | `ItemTile.gd` (88 x 96 / 92 x 100 dp cards, cost plate at the foot, ADR 0032's sash and 26 dp seal on a locked card), `theme.tres` (`ItemTile`, `ItemCost`, ...), `HudTheme.gd` (dp scaling); the side's accent by faction id lives in `BuildButton.ACCENTS` | The board names `BuildButton.gd`: the cards are `ItemTile.gd` (BuildButton is the corner BUILD button). `StyleBoxFlat` has no gradient: the "bevelled gradient face" becomes two flat tones and a 1 dp light top line. The board's "calmer locked state with a small lock plate" replaces ADR 0032's accepted sash (Q1). Its chip beside the name breaks ADR 0032's one-line room ("Bunkho / use" in the mockup) |
| 5 | Ground variety | `GroundLayer.gd` (a `TileMapLayer`), `GroundAtlas.gd`, 12 tiles `ground/<id>_a|b.svg`, variant by `(column + row) % 2`; STYLE.md "Iso ground tiles": no gradient, **no rim** (Michael 2026-10-27: the rim read as a grid) | "Large-scale two-tone patches" made as tile variants would put a darker diamond on a cell, which reads as the grid Michael removed; patches and blends must be overlays across cell edges. "~40 KB" is the SVG; the page holds the raster (about 8 KB per 64 x 32 tile) |
| 6 | Grade and vignette | Nothing (no `CanvasModulate`, one `Hud` `CanvasLayer` at layer 1) | Screen-fixed: the "warm key light from the upper left" is a grade, not a light. ADR 0023 §2's z table and forecast need it (ADR 0035 §3) |
| 7 | Muzzle and impact | `EffectsLayer.gd`: muzzle FLASH (32 px region), tracer, impact PUFF, vehicle BURST, infantry FADE in a 128-slot ring from `fx/effects_atlas.svg`; `PuffFx` muzzle smoke (24 slots), `HitFx` flash and chips on buildings (ADR 0029 §7) | Most of it exists; the proposal is a look upgrade. Its "additive blend, +2 to 4 draw calls" is rejected by ADR 0029 §6: normal alpha with a bright core, 0 new calls (ADR 0035 §6). "Cap ~24 live" is the existing rings |
| 8 | Fog and map edge | `FogLayer.gd`: one RGBA8 texel per cell, black, alpha 255 / 140 / 0, linear, z 4 on the ground; off-map clear colour #16191D (`GroundLayer.OFF_MAP_COLOR`) | Blue-grey fog changes ADR 0010 §2 and the GDD (Q2). A long falloff is allowed at the map edge only, never at the limit of sight (ADR 0035 §1) |
| - | SKADET picture (lead's addition) | `dmg1` patch per building (16 frames at `DAMAGE_SCALE` 0.75), `BuildingDamage.picture` already falls back to the body when a sheet has no `dmg1` | ADR 0034 |

Legal and originality: none of the eight copies a look, name or UI of another game; team-coloured
ground marks, ticked bars, vignettes and starburst flashes are generic. The rule that every frame is
generated or hand-written in this repo holds (no web or AI images); art-director describes each new
SVG in its header (STYLE.md "Originality").

## Affected modules
- `tools/artgen/`: `ArtShadow.gd` (occlusion pad, team pad), `ArtModel.gd`, `ArtDamage.gd`,
  `ArtSheet.gd`, `ArtGen.gd` (no `dmg1` frame), generated frames under `assets/art/iso/`
  (shadows, `_dmg1.svg` removed, sheets), `assets/art/models/*/*.tres` (the `dmg1` pose lines).
  Read and unchanged, because the part lists keep `dmg1` as the name of stage 1 (ADR 0034 §3):
  `ArtMove.gd:57` (a `dmg1` pose still parses as a damage pose, so `ArtModel` can refuse it) and
  `IsoSheetDef.gd:124` (`origin`'s literal `[hull, shadow, dmg1, dmg2]`).
- `assets/art/svg/`: `ui/selection_ellipse_team.svg` (new), `ground/<id>_c|d.svg` (new),
  `ground/edge_*.svg` (new transition pieces), `fx/effects_atlas.svg`, `fx/life_atlas.svg`.
- `assets/art/STYLE.md`: "Light", "Feedback markers", "Health bars", "Iso ground tiles", "Combat
  effects", "Life effects", "Damage stages (P158a)", new "Grade, fog and map edge".
- `game/view/`: new `RingArt.gd`, `BarMarks.gd`, `GroundPick.gd`, `GroundEdges.gd`,
  `LookSettings.gd`, `WorldGrade.gd`, `MapEdge.gd`; changed `BuildingDamage.gd` (`picture`
  only), `UnitLayer.gd` (the ring texture source, net 0 lines: it is at 1000),
  `HealthBarLayer.gd`, `GroundLayer.gd`, `GroundAtlas.gd`, `FogLayer.gd`, `EffectsLayer.gd`,
  `GroundFx.gd`, `LifeRegions.gd` (art row), `art_gallery_build.gd`, `art_gallery_iso.gd`,
  `art_gallery_ground.gd`.
- `game/ui/`: `ItemTile.gd`, `theme.tres`; `PerfBases.gd` (the forecast constants, P216).
- Scenes: `scenes/main.tscn` and `scenes/dev/perf_arena.tscn` (V4 lane only: `WorldGrade`,
  `CanvasModulate`, `MapEdge`, the Hud's layer 1 -> 2).
- Data: `data/look_settings.tres` (new, view only, P214).
- Docs: `docs/HOW_TO_PLAY.md` (rows below), GDD and ADR notes (P200b).

## Command and data changes
No Command, no sim state, no event, no hash. One new view-only data file, `data/look_settings.tres`
(`LookSettings`), written whole by P214 from STYLE.md's "Grade, fog and map edge" (P213). The
impact dust uses `GroundFx`'s existing `dust_slots` (48), so `data/life_settings.tres` is not
touched. Sheets lose the `dmg1` part (ADR 0034); `cuts` keeps two entries, index stage - 1; the
three part lists stay `[dmg1, dmg2]` as stage-to-part tables.

## ADR 0029 note (draft, for P200b)
To go in ADR 0029 after its status block and before "## Context", and as one line at the end of §3
and of §4 (the lead places them; the text above them stays as accepted):

> Status note (2026-11-09, ADR 0034 accepted the same day, Michael's answer "A"): **SKADET draws
> the INTAKT picture.** No `dmg1` frame is generated or shipped and no sheet has a `dmg1` part;
> `BuildingDamage.picture` returns 0 for stage 1, so stage 1 shows the untrimmed body with
> SKADET's particles of §6 unchanged. KRITISK keeps `dmg2`. The part lists stay `[dmg1, dmg2]` as
> stage-to-part tables (every reader indexes them by stage) and `cuts` keeps two entries. The stage
> function, the thresholds 67/34, the remembered stage of a ghost, the collapse, the hit feedback
> and the vehicles' stages are unchanged. In §3's table the SKADET row's part and patch, in §4's
> table the SKADET entries of "Silhouette", "Surfaces" and "Team colour", §4's SKADET clause of
> "Depth on the body", §5's refusal "`dmg1` without `dmg2`" (now: any `dmg1` pose is refused) and
> its stage-1 ink rule (now: ink in the intact picture) are replaced by ADR 0034; §10's page gains
> the freed rows.

Matching one-line notes: ADR 0028 §3 (the stage-1 patch is withdrawn by ADR 0034), ADR 0023 §5's
part names (`dmg1` withdrawn), and the GDD's damage table row "Damaged" (2/3 to 1/3: "no picture of
its own; one fire, thin grey smoke").

## Rows
Sizes are production lines (`tests/` excluded; SVG, generated frames and `.tres` do not count).
Lanes: art-director owns `assets/`, `tools/artgen/`, STYLE.md and the `tests/art/` suites;
touch-ux-dev owns `game/view/`, `game/ui/` and their tests. Row ids P200-P219; P195-P199 stay
reserved; P200b is the lead's.

| Row | Lane | Owner | Title | Size | Depends | Group |
| --- | --- | --- | --- | --- | --- | --- |
| P200 | - | architect | docs: this plan, ADR 0034 (accepted), ADR 0035 (proposed) | 0 | - | done |
| P200b | - | lead | docs on acceptance: ADR 0029/0028/0023 notes (draft above), ADR 0035's answers and its notes in ADR 0010 §2 / 0023 §2 / 0027 §9, GDD lines (damage table, fog), svg-art-style skill text | 0 | P200, Michael's answers | 0 |
| P201 | V2 | touch-ux-dev | view: SKADET draws the intact picture (`BuildingDamage.picture`, gallery Stage button); part lists unchanged | 30 | P202 (written beside it, merged after it) | 2 |
| P202 | A | art-director | art: generator writes no `dmg1` frame (stage indexing kept); 16 frames and their sheet parts go; `dmg2` byte-identical; page pins down | 60 + art | P200b | 1 |
| P203 | A | art-director | art: occlusion pad and contact line in every shadow frame (`ArtShadow`), STYLE.md "Light" | 100 + art | P202 | 2 |
| P204 | A | art-director | art: team pad in unit shadow frames (key triad), page check | 60 + art | P203 | 3 |
| P205 | A2 | art-director | art: `ui/selection_ellipse_team.svg` (two bands, stepped glow); STYLE.md ring row and "Health bars" ticks and pip | SVG + 0 | P200b | 1 |
| P206 | V1 | touch-ux-dev | view: the ring baked once per match in the local player's triad (`RingArt.gd`) | 90 | P205 | 2 |
| P207 | V2 | touch-ux-dev | view: health-bar ticks (one line pass) and the owner's pip (`BarMarks.gd`) | 140 | P205, P201 | 2 |
| P208 | G | touch-ux-dev | ui: build cards: faction rail, cost chip, two-tone face; ADR 0032's locked card kept | 180 + theme | P200b (Q1) | 1 |
| P209 | A3 | art-director | art: ground variants `c` and `d` for the six terrains, STYLE.md "Iso ground tiles" | SVG + 0 | P200b | 1 |
| P210 | V3 | touch-ux-dev | view: ground variant by an integer coordinate hash (`GroundPick.gd`), c/d with fallback | 70 | P200b | 1 |
| P211 | A3 | art-director | art: transition pieces (edges and corners) and patch blotches on the ground page | SVG + 0 | P209 | 2 |
| P212 | V3 | touch-ux-dev | view: `GroundEdges.gd`: the pieces and blotches per cell, static, one canvas item | 200 | P210, P211 | 3 |
| P213 | A4 | art-director | art: STYLE.md "Grade, fog and map edge": the colours and their greyscale checks | 0 | P200b | 1 |
| P214 | V4 | touch-ux-dev | view: `LookSettings` + `data/look_settings.tres` (whole), `WorldGrade` (CanvasModulate + gradient layer 1, Hud to layer 2) in both scenes | 150 | P213 | 2 |
| P215 | V4 | touch-ux-dev | view: fog texels in `fog_rgb` (only if Q2 = B) | 40 | P214, ADR 0035 accepted | 3 |
| P216 | V4 | touch-ux-dev | view: `MapEdge.gd`: the map-edge mask and mist band; the card's forecast constants 18 / 19 / 25 (`PerfBases.gd`) | 190 | P215 (or P214 if Q2 = A), P207 | 4 |
| P217 | A4 | art-director | art: flash frame 2 and core in `effects_atlas.svg`; impact dust frames in `life_atlas.svg` (`LifeRegions`) | SVG + 20 | P213 | 2 |
| P218 | V1 | touch-ux-dev | view: the flash's second frame (`EffectsLayer`), impact dust in `GroundFx`'s dust ring | 120 | P206, P217 | 3 |
| P219 | H | qa-engineer | tests: the polish guard (draw calls per layer on both scenes, the forecast of 18, page pins, grade bounds) and the base-arena card read | tests | P201-P218 | 5 |

Groups (what can run at once; each group needs the rows of the groups before it only where Depends
says so): group 1 = P202, P205, P208, P209, P210, P213 (six lanes; if the lead's verify queue is
the limit, take P202, P205 and P213 first: P202 is Michael's early ask and frees the page, the
other two gate four view rows); group 2 = P201, P203, P206, P207, P211, P214, P217 (P201 can be
written in group 1 beside P202 and merges right after it); group 3 = P204, P212, P215, P218;
group 4 = P216; group 5 = P219. Critical path: P213 -> P214 -> P215 -> P216 -> P219 (five rows).

Why P201 merges after P202: `tests/view/test_damage_parts_pin.gd` pins the view's and the
generator's part lists equal, and the view rule is only proven on the shipped art once the
`dmg1` frames are gone. With the lists kept (ADR 0034 §3) neither order breaks the page (a
committed `dmg1` part is still baked at `part_factor` 0.75 until P202 removes it), but one order
keeps the reviews simple.

### File ownership per lane (no two open rows share a file)
| Lane | Rows | Files (production) | Tests |
| --- | --- | --- | --- |
| A | P202 -> P203 -> P204 | `tools/artgen/ArtModel.gd`, `ArtDamage.gd`, `ArtSheet.gd`, `ArtGen.gd`, `ArtShadow.gd`; `assets/art/models/**`; `assets/art/iso/**`; STYLE.md "Light", "Damage stages (P158a)" | `tests/art/test_artgen_*.gd` (P202: the `dmg1` pose fixtures of `test_artgen_v5_materials.gd:82-157` and `test_artgen_v5_points.gd` move to `dmg2` or become refusal cases), `test_fossil_*`, `test_renew_*`, `artgen_v5_support.gd`; `tests/view/test_iso_atlas_budget.gd` (the `TODAY_*` pins only) |
| A2 | P205 | `assets/art/svg/ui/selection_ellipse_team.svg`; STYLE.md "Feedback markers", "Health bars" | `tests/art/test_artgen_cards.gd` (append) |
| A3 | P209 -> P211 | `assets/art/svg/ground/*`; STYLE.md "Iso ground tiles" | `tests/art/test_ground_art*.gd`, `ground_art_support.gd` |
| A4 | P213 -> P217 | STYLE.md "Grade, fog and map edge" (new), "Combat effects", "Life effects"; `assets/art/svg/fx/effects_atlas.svg`, `fx/life_atlas.svg`; `game/view/LifeRegions.gd` | `tests/art/test_life_atlases.gd`, `tests/view/test_effects_layer*.gd` (region pins only) |
| V1 | P206 -> P218 | `game/view/RingArt.gd` (new), `UnitLayer.gd` (ring source lines only), `art_gallery_iso.gd`; then `EffectsLayer.gd`, `GroundFx.gd` | `tests/view/test_selection_rings.gd`, `test_ring_art.gd` (new), `test_feedback.gd`, `test_unit_layer.gd`; `test_effects_layer*.gd`, `test_ground_fx*.gd` |
| V2 | P201 -> P207 | `game/view/BuildingDamage.gd` (`picture` and its doc), `art_gallery_build.gd`, comments in `BuildingLayer.gd`; then `HealthBarLayer.gd`, `BarMarks.gd` (new) | `tests/view/test_building_damage*.gd`, `test_damage_parts_pin.gd` (header comment only), `test_damage_scale.gd` (unchanged asserts, see P201), `support/damage_rig.gd`, `test_building_layer.gd`, `tests/art/test_art_gallery_build.gd`; then `test_health_bar*.gd` |
| V3 | P210 -> P212 | `game/view/GroundLayer.gd`, `GroundAtlas.gd`, `GroundPick.gd` and `GroundEdges.gd` (new), `art_gallery_ground.gd` | `tests/view/test_ground_layer.gd`, `test_ground_scenes.gd`, `test_ground_pick.gd` and `test_ground_edges.gd` (new) |
| V4 | P214 -> P215 -> P216 | `game/view/LookSettings.gd`, `WorldGrade.gd`, `MapEdge.gd` (new), `FogLayer.gd`, `data/look_settings.tres`, `scenes/main.tscn`, `scenes/dev/perf_arena.tscn`; `game/ui/PerfBases.gd` (P216: `CALLS_FORECAST`, `CALLS_STRIKE`, `CALLS_WORST` and their doc lines only) | `tests/view/test_world_grade.gd`, `test_map_edge.gd` (new), `test_fog_layer*.gd`; `tests/ui/test_perf_bases.gd` (P216: the forecast card line only) |
| G | P208 | `game/ui/ItemTile.gd`, `game/ui/theme.tres` | `tests/ui/test_item_tile_look.gd` (new), `test_build_sidebar_items*.gd`, `test_item_tile_words.gd`, `test_display_name_fit.gd`, `test_touch_target_sizes.gd`, `test_ui_theme*.gd` |
| H | P219 | none | `tests/view/test_polish_budget.gd` (new) |

Shared: STYLE.md (each art row its own sections only), `docs/HOW_TO_PLAY.md` (own rows only),
`tests/view/test_iso_atlas_budget.gd` (lane A only; P201 must not touch it). No row edits
`IsoAtlas.gd` (its `DAMAGE_PARTS` stays). `BuildButton.gd` is read (its `ACCENTS`), not edited.
`PerfBases.gd` is edited by P216 only (lane G does not touch it).

## Acceptance per row
**P201 (view, SKADET).** Indexing stays by stage (ADR 0034 §3): `BuildingDamage.PARTS`,
`IsoAtlas.DAMAGE_PARTS` and `ArtModel.DAMAGE_PARTS` stay `[dmg1, dmg2]` (stage-to-part tables,
index stage - 1), `PARTS[k - 1]` and `cuts[k - 1]` keep their meaning, and `picture(sheet, stage)`
returns 0 for stage 0 and 1 and 2 for stage 2 when the sheet has `dmg2` and two `cuts`.
- Tests: `picture(sheet, 1)` is 0 for every sheet, also a crafted one that still has a `dmg1`
  part; stage 2 shows `dmg2` on the shipped sheets; a ghost remembered at stage 1 shows the body
  (`test_building_damage_ghost.gd`); SKADET's particles still start at 67 % (`test_damage_fx*.gd`
  unchanged).
- Writes: `BuildingLayer` calls `BuildingDamage.cost(from, to, ...)` with picture stages (its
  `stage_want` is `picture(sheet, raw)`), so an hp change from INTAKT to SKADET is no picture
  change and writes nothing (`test_building_damage_flow.gd` gains that case); INTAKT or SKADET to
  KRITISK is the picture change 0 -> 2. `cost` itself is unchanged.
- `tests/view/test_damage_parts_pin.gd` keeps its three equal lists and `size() == 2`; only its
  header comment changes ("both lists stay `[dmg1, dmg2]`; `dmg1` names stage 1, which has no
  picture"). `tests/view/test_damage_scale.gd`'s crafted `dmg1` regions and
  `part_factor(&"dmg1") == 0.75` (:164) stay true (the table still names `dmg1`) and stay as they
  are: they test the bake factor of a crafted sheet, not a shipped picture.
- The gallery's Stage button walks INTAKT, SKADET (intact), KRITISK (`art_gallery_build.gd`,
  `tests/art/test_art_gallery_build.gd`).
- HOW_TO_PLAY row "A building is badly damaged": under two thirds a building smokes and burns at
  one spot and keeps its shape; under a third part of it has collapsed (owner: this row).
- Phone: shoot a building to 60 % in the base arena; it stays whole with smoke and one fire; under
  34 % it breaks.

**P202 (art, drop `dmg1`).** Indexing stays by stage (ADR 0034 §3): `ArtModel.DAMAGE_PARTS`
stays `[dmg1, dmg2]`, `damage_prims(stage)` reads `DAMAGE_PARTS[stage - 1]` and `ArtGen` the
stage `DAMAGE_PARTS.find(part) + 1` as today; `ArtModel.damage_parts()` lists only `dmg2` (stage
1 is never a picture, also when a `damage=1` primitive exists), so no `dmg1` frame is written. A
model with a `dmg1` pose is refused (replaces "dmg1 without dmg2"); no `_dmg1.svg` is left; every
`_dmg2.svg` is byte-identical to b6bfe95 (the row lists `git diff --stat` of `assets/art/iso`);
sheets have no `dmg1` part and keep two `cuts`, index stage - 1 (the first 0); the point-ink test
checks the intact picture and stage 2;
`emitter_quiet` recomputed (1 -> 2 or 0; the four known emitters listed in the PR); the SKADET
team-share test goes; `TODAY_CROSS`, `TODAY_MIRROR_DERRICK`, `TODAY_MIRROR_LUMEN` move down and the
PR quotes the rows freed and the bytes (16 KB per row). STYLE.md "Damage stages (P158a)" says
SKADET has no picture. No view file touched.

**P203 (art, occlusion).** Every unit and building shadow frame gets a soft occlusion pad (stepped
discs or rings in one `<g opacity>`, no gradient element) and a thin contact line round the base,
under the cast shadow; no ink inside a hull, turret or building frame (STYLE.md "Light" holds);
`tests/art/test_artgen_shadows.gd` pins the pad (it lies under the footprint or the hull's ground
outline, at most `AO_REACH` beyond it, darkest at the contact line); the page pins move and every
page stays within 3584. If a page passes 3584, stop and report: Q3's answer applies (ADR 0035
§4.3). The wellhead's hand-drawn shadow gets the same pad by hand. Phone: buildings and tanks sit
on the grass in the base arena at zoom 0.75 and 1.5.

**P204 (art, team pad).** Each unit's shadow frames hold a pad in the faction's key triad (mid tone
fill at about 55 %, light rim), under the cast shadow; a squad has one pad per figure group or one
for the squad (art-director decides and records it); the key-band test passes on the shadow frames;
`test_artgen_plates.gd` still checks models only (a test says so); `IsoAtlas` bakes these shadows
per player (a test on a mirror match: two slots); pages within 3584 (pins updated). Phone: both
sides in a mirror match at zoom 0.75: own and enemy pads in different colours; on sand and grass.
HOW_TO_PLAY row "Look at your units": "each stands on a small pad in its team colour" (this row).

**P205 (art, ring and bar spec).** New `ui/selection_ellipse_team.svg`, the same canvas and centre
line as `selection_ellipse.svg` (168 x 96, semi-axes 72 and 36 px): the white band with its dark
outline kept, an outer band in the key triad (mid, light edge), a stepped inner glow at low alpha,
no gradient element; the old file stays until P206 switches the reader. STYLE.md: the ring row
(team band outside, white inside), its greyscale check on grass and sand for all eight triads (Kul
and Guld named), and "Health bars": the pip (a square of the bar's height minus the edges, in the
owner's team light colour, at the bar's left end, inside the edge, never over the notch) and the
ticks (dark 1 dp marks every 25 % on unit bars and the 24 dp building bar, every 10 % on the 40 and
56 dp building bars: never closer than 4 dp). `test_artgen_cards.gd` pins the new ellipse's even
stroke as it pins the old one.

**P206 (view, team ring).** `RingArt.texture_for(triad)` bakes `selection_ellipse_team.svg` once per
match with the local player's triad (the `IsoPlayerArt` replacement; one `ImageTexture`, cached by
match serial); every `Ring` uses it with white modulate; `UnitLayer` changes only its texture
source (net 0 lines); `test_sorted_world_batch.gd` and `test_selection_rings.gd` pass (rings one
texture, z 3); a new test bakes the ring for Signal and Kul and reads the outer band in the triad
and the inner band white; the gallery's Iso page shows it. No allocation per frame. Phone: select
tanks on grass and sand at the three zooms, portrait and landscape.

**P207 (view, bar marks).** `BarMarks.gd` plans the ticks and the pip: the pip is one filled rect
per bar in the rect pass (`MAX_RECTS_PER_BAR` 6 -> 7), in the owner's team light colour (own: the
local triad; enemy: its player's; owner 0: none); the ticks are one `draw_multiline` per frame
after the rects and before the glyphs (at most +1 draw call while any bar shows); tick spacing never
under 4 dp (a test over every class at 1.0 to 2.37 base px per dp); the overlap tests pass and the
pip never covers the notch; no allocation per frame (packed arrays reused). `HealthBarLayer.gd`
grows by at most 30 lines. HOW_TO_PLAY row "A unit is selected, or has just been damaged": marks
on the bar every quarter and a dot in the owner's colour (this row). Phone: a hit enemy group and an
own selected group at zoom 0.75 on the 6-inch profile.

**P208 (ui, cards).** On every `ItemTile` card: a top rail `RAIL_DP` (3) high in the side's accent
by faction id. `BuildButton.ACCENTS` maps a faction id to a theme variation name
(`&"AccentRenew"`, `&"AccentFossil"`), not to a colour: the rail reads
`get_theme_color(&"accent", BuildButton.ACCENTS[side])` from the card's theme (the copy `HudTheme`
scales), as `BuildButton` does. Then a two-tone face (the theme's `ItemTile` boxes: two flat tones
and a 1 dp light top line drawn with the rail; no gradient texture unless Michael asks after the
phone check), the cost as a chip on the existing foot plate (`ItemCost`: dark text
`on_accent` on the accent, contrast at least 4.5:1 checked by a test for both accents;
`ItemCostLow` keeps the amber money cue on dark). The name keeps its own line: ADR 0032's room is
unchanged (`test_display_name_fit.gd` untouched and green). LOCKED keeps ADR 0032's sash and seal
(Q1 A); READY keeps its banner; UNAFFORDABLE keeps its stripes. Card sizes unchanged, so the 48 dp
rule and the safe areas hold: `test_touch_target_sizes.gd` and `test_hud_walk_scans.gd` at the six
sizes pass; the theme scans of `test_ui_theme*.gd` (no font calls in code) pass. HOW_TO_PLAY row
"Tap an item in the open tab": "its price on a chip in your side's colour" (this row). Phone: the
drawer open upright and sideways, both factions, every state (available, locked, short of money,
full, ready).

**P209 (art, ground variants).** `ground/<id>_c.svg` and `_d.svg` for the six terrains: the same
base to every edge and the same edge rule as a and b (no rim, no gradient; `test_ground_art.gd`'s
base probes at 0.89/0.93/0.97 and its 3 x 3 seamless blocks over a, b, c, d mixed); new details
(tufts, specks, stones) inside the 0.3-tile middle; greyscale means within 2 levels of a and b.
STYLE.md: the variant rule becomes GroundPick's (P210). Phone: none until P210.

**P210 (view, variant pick).** `GroundPick.variant(col, row, count)`: an integer hash of the cell
(no `hash()`, no RNG, no float; same on every device; `test_life_purity`-style scan), spread
tested (each of 4 variants 20-30 % on a 64 x 64 map, no 2 x 2 block of one variant above a bound);
`GroundAtlas` loads `c` and `d` when present and falls back to `a`/`b` (the row can merge before
P209); fills and `map_version` patches unchanged; MapView's bake and the minimap unchanged. Phone:
the open grass of the skirmish map reads without a visible repeat at zoom 0.75.

**P211 (art, transitions).** For an ordered list of overlaying terrains that art-director fixes in
STYLE.md (for example sand over grass, grass over scrub, ore stain over grass, sand over water as a
shore), per terrain four edge pieces (one per diamond side) and four corner pieces, 64 x 32 at 1x,
ragged edges and specks, no gradient, no line along the cell edge; three patch blotches (two-tone
irregular shapes, 2 to 4 tiles across) for grass and sand. Each piece only ever lies over a
different terrain (the "no rim" rule: two equal tiles never get a piece). Tests: sizes, the key list
against STYLE.md, no ink outside the piece's half of the diamond.

**P212 (view, ground edges).** `GroundEdges.gd`, a code-made child of `GroundLayer` drawn before
`Fields`: for each cell, the edge piece of each side whose neighbour has a higher terrain in the
list, a corner piece where only the diagonal neighbour does, and blotches by `GroundPick`; all from
the ground page (`GroundAtlas` adds the pieces), drawn in one static `_draw`, redrawn only when the
match or `map_version` changes (no per-frame work); at most 8 pieces per cell (pinned); none
between two equal terrains (pinned on a crafted map); same texture as the tiles, so the ground stays
one batch (P219 counts it). Size split P212b (blotches) if over 400. Phone: shore and sand edges
read soft; no grid shows anywhere.

**P213 (art, grade spec).** STYLE.md "Grade, fog and map edge": the canvas modulate (each channel
at least 0.90), the gradient's warm and cool colours, its vignette and `grade_alpha_max`, `fog_rgb`
(luminance at most 40; and #000000 for Q2 A), the mist colour (its peak at least 20 levels above the
unexplored fog and the off-map colour), `edge_inner_tiles` (at most 2), `edge_outer_tiles`, the
inner alpha (at most 0.6); greyscale table of grass, sand, the explored dim, both default triads and
the ring under the grade. The `CanvasModulate` tints `FogLayer` and `MapEdge` too (ADR 0035 §3),
so the fog's and the mist's luminance bounds are measured after the modulate; the clear colour
(off-map) is not tinted, so the mist's outer end is chosen to meet it after the modulate. No code.

**P214 (view, grade).** `LookSettings.gd` (a Resource with a preload fallback) and
`data/look_settings.tres` with every field of P213 (grade, fog and edge, so no later row edits
`data/`); `WorldGrade.gd`: a `CanvasModulate` in the world canvas and a `CanvasLayer` at layer 1,
with the `Hud` `CanvasLayer` raised from the default 1 to layer 2 in `main.tscn` and
`perf_arena.tscn` (layer 0 is the root canvas; the order never rests on tree order between equal
layers; a test pins `WorldGrade.layer < Hud.layer` on both scenes), holding one `TextureRect`
(IGNORE, full rect, a
small `GradientTexture2D`, at most 128 x 128); hidden quad with `LifeSettings.reduced`; both
`main.tscn` and `perf_arena.tscn` carry it so the card measures it. Tests: the bounds of P213, one
canvas item on the layer, no input taken (`test_hud_walk.gd` passes, a tap through the vignette
reaches the map). Phone: base arena both orientations; the HUD corners read the same.

**P215 (view, fog colour; only if Q2 = B).** `FogLayer` writes `fog_rgb` with today's alphas;
`test_fog_layer*.gd` read the colour from `LookSettings` and keep their alpha asserts;
`test_fog_hiding_edges.gd` unchanged. HOW_TO_PLAY: the Fog section's row "Look at the map" (line
92; another row of that name exists elsewhere): "Dark blue-grey ground has never been seen" (this
row). Phone: start a skirmish, scout: unexplored, explored and seen read apart.

**P216 (view, map edge).** `MapEdge.gd` at z 4 after `FogLayer`: one mask texture of
`(cols + 2m) x (rows + 2m)` texels made at match start (and on a map change), linear filtering,
under the fog's transform; the bounds of P213 pinned per texel class (inside, edge, mist peak,
outside); one draw call; no per-frame work; the camera clamp tests unchanged. The card's forecast
(ADR 0035 §7): `PerfBases.CALLS_FORECAST` 16 -> 18, `CALLS_STRIKE` 17 -> 19, `CALLS_WORST` 22 ->
25 and their doc lines; `tests/ui/test_perf_bases.gd`'s card line becomes "forecast 18, 19 while a
strike is aimed or in flight, about 25 at worst, plus the HUD (no verdict)". HOW_TO_PLAY: the Fog
section's row "Look at the map" (line 92): "the map's edge fades into mist" (this row). Phone: pan
to every corner of the map at zoom 0.75, upright and sideways; the edge reads, a base near the edge
stays clear.

**P217 (art, effects).** `effects_atlas.svg`: a second flash frame `FLASH2` (the starburst's open
phase) and a brighter core in `FLASH` and `PUFF`, in free space of the sheet (regions pinned in
STYLE.md "Combat effects"); `life_atlas.svg`: `impact_dust` frames (a flat 2:1 ring of dust) in
`LifeRegions` and STYLE.md "Life effects"; normal alpha only, hue rules of the key bands kept.

**P218 (view, effects).** `EffectsLayer`: a FLASH slot shows `FLASH` then `FLASH2` by age (one
region switch, no new slot, no new call); `GroundFx`: an IMPACT whose tile the player sees leaves
one
`impact_dust` puff in the dust ring (`dust_slots`; reduced: none, as dust today); no new ring, no
`life_settings.tres` change; `test_life_budget.gd` bounds hold. Phone: a tank fight in the base
arena at zoom 1.0.

**P219 (tests, guard).** `test_polish_budget.gd`: on `main.tscn` and `perf_arena.tscn`, the world's
layers by z and texture (ADR 0012's llvmpipe count where available, else the canvas-item and
texture walk of `test_sorted_world_batch.gd`): ground and edges one texture, `MapEdge` 1,
`WorldGrade` 1, the forecast 18 in an ordinary frame of the base arena (the figure P216 puts in
`PerfBases`); the page pins; the grade
bounds. The lead reads the base-arena card on the phone (draw calls p95, `work_p95_ms` at most 5.6)
before and after the wave and posts both.

## Costs per proposal
| # | Draw calls | Overdraw / fill | Memory | Per-frame CPU |
| --- | --- | --- | --- | --- |
| SKADET (0034) | 0 | 0 | about -100 page rows: about -1.5 to -2 MB texture per match; -149 KB SVG; 16 fewer bakes | fewer writes at 67 % |
| 1 Occlusion | 0 | shadow quads a few px larger (alpha) | page rows: measured, inside 3584 | 0 |
| 2 Ring, bars | ring 0; ticks at most +1 while bars show | 0 | ring texture 168 x 96 RGBA, about 64 KB once | +1 rect per shown bar, one multiline call |
| 3 Team pad | 0 | as 1 | mirror pages grow by one faction's unit shadows; cross 0 | 0 |
| 4 Cards (HUD) | a few rects per card (HUD, outside the world forecast) | 0 | 0 | 0 while closed |
| 5 Ground | 0 (same page; P219 counts) | edges and blotches over part of the ground | about 12 + 32 + 6 tiles on the ground page, about 10 KB each with the gutter: about 0.5 MB | 0 (static) |
| 6 Grade | +1 | one blended full-screen quad | gradient texture at most 64 KB | 0 |
| 7 Effects | 0 | as today | a few regions in existing atlases | one region switch per flash |
| 8 Fog, edge | +1 (`MapEdge`) | the edge band, at most one screen | mask about 25 KB at 64 x 64 cells | 0 (built at start) |

Forecast (the perf card's figures, ADR 0035 §7): 16 -> 18 ordinary, 17 -> 19 with a strike,
22 -> about 25 at worst; under the trigger of 40 and the ceiling of 60.

## Test plan (what is proven headless)
- Determinism of the look: `GroundPick` and the impact dust use integer hashes or `LifeClock`;
  purity scans (no `hash()`, `randi`, `Time`) cover the new view files.
- Batching and calls: `test_sorted_world_batch.gd` (unchanged: no new child of a rig at z 10),
  P219's guard on both scenes, ring one texture (P206), bars' call count (P207).
- Page: `test_iso_atlas_budget.gd` pins after P202, P203 and P204, within 3584.
- HUD: the 48 dp and safe-area scans at the six sizes (P208, and P214 for the vignette layer taking
  no input); the theme scans; the one-line name room (ADR 0032).
- Fog: alpha and hiding tests unchanged; colour from `LookSettings` (P215).
- Art: generator tests per art row (shadows, damage, plates, key band, ground seams).
- There are no golden screenshots in this repo: the look is judged in the art gallery's pages and on
  Michael's phone through the web preview (`bash scripts/export-web.sh`); no row adds one.
- No timing in a session: the perf suites run inside verify.sh only; the phone card is read by the
  lead.

## HOW_TO_PLAY impact
P201 ("A building is badly damaged"), P204 ("Look at your units"), P207 (the unit bar row), P208
("Tap an item in the open tab"), P215 and P216 (the Fog section's row "Look at the map", line 92).
None for P202, P203, P205, P206 (the ring's colour is not described today), P209-P214, P217,
P218. GDD lines (damage table, fog) are P200b's.

## Questions for Michael
1. **Locked build cards.** The board's cards show a small lock plate on a locked card. On
   2026-11-06 you chose the diagonal sash with the missing building's name (ADR 0032). A: keep the
   sash and give the cards only the new rail, price chip and face (recommended: the sash tells the
   player what to build first). B: replace the sash with the small lock plate (a new ADR; the
   missing building's name would move to a tap).
2. **Unexplored ground.** The board fades the map into a blue-grey mist. A: unexplored ground stays
   black; only the map's edge gets the mist. B: unexplored ground becomes a very dark blue-grey that
   matches the mist, still clearly darker than anything seen (recommended: it is what the board
   shows, and the edge of sight stays as sharp as today).
3. **If the new shadows do not fit the one texture page.** The soft pads under units and buildings
   make the shadow pictures a little larger; the dropped SKADET pictures free room, which is likely
   enough. If it is not: A: bake the shadows at 75 % size (they are soft, so it does not show;
   recommended). B: draw the pads as separate small pictures (one more draw call and 150 more
   nodes).

## Risks
- **Page budget.** Cross page 3550 of 3584 today; P202 frees about 100 rows before P203 and P204
  spend them. Lane A's order (P202 first) is the mitigation; Q3 is the fallback.
- **The grid comes back.** Variants or transition pieces with a tone change at a cell edge read as
  a grid (Michael removed the rim for that). P209/P211's base-to-edge tests and the "pieces only
  between different terrains" test guard it; Michael's phone check decides.
- **Team colours near feedback colours.** Derrick orange rings and pads sit near the amber of
  attack-move chevrons and enemy bars; the white inner band and the notch keep the shapes apart.
  The greyscale table of P205 names the weak triads.
- **Grade drift.** A canvas tint moves every measured contrast; the bounds of ADR 0035 §3 and
  P213's graded table keep it small; reduced effects hide the vignette.
- **`data/**` starts a balance run.** The first `data/` merge starts `balance.yml`: cancel it, its
  results cannot change (no sim input changed), or batch it with a Phase 4 tuning merge. The view
  rows that use `data/look_settings.tres` are P214, which writes it whole (every field of P213), and
  P215 and P216, which only read it; no other row touches `data/` (P218 uses the existing
  `dust_slots`).
- **UnitLayer is at 1000 lines** (gdlint): P206 moves the ring source into `RingArt.gd`, net 0.
- **Lead's verify queue.** Group 1 has seven lanes; take four first (above).
- **Michael may reject a part on the phone** (as with the camera shake): each proposal is its own
  rows, so an answer removes it cleanly (the vignette is P214's quad, the pad is P204, the map
  edge P216).
