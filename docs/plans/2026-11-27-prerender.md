# Plan: pre-rendered terrain and buildings, SVG units restyled toward P655

Date: 2026-11-27. Author: architect. Row P654 is on branch `claude/p654-prerender-adr` (base
`main` at 7648d987).

Decisions:
- `docs/adr/0053-prerendered-terrain-and-buildings.md`, **accepted** 2026-11-27 in this PR (P654;
  P654b folded in). Michael chose "3D til terræn + bygninger, SVG-enheder" and "Vi kan starte der
  og så kan tanks laves til 3D senere når jeg har set det?" (the lead: yes), then answered the
  ADR's seven questions with "Godkend alle 7 (anbefalet)".
- CLAUDE.md's Legal, Layout and Stack lines are edited by the lead (approved by Michael's answer 2), before any PNG art merges (P656 / P644).
- It builds on ADR 0050 (accepted, amended 2026-11-26): §8's one look, A1-A7's team panels, §1's
  byte budget and §6's zoom. ADR 0050 gets a dated note in this PR.
- The evidence is two prototype branches that are never merged: `claude/p653-prerender-prototype`
  (`docs/proto/p653/README.md`) and `claude/p655-detailed-tank` (`docs/proto/p655/README.md`).

This plan takes over these rows of `docs/plans/2026-11-24-treadline-restyle.md` once ADR 0053 is
accepted:
- P644 to P647 become the pre-rendered building batches here. They keep their numbers and are
  split into parts.
- P643 stays an SVG batch drawn under ADR 0050's amendment and waits only on P652. If P658 lands
  first, P643 follows P658's materials. If P643 lands first, P658 includes its four models.

The rows there are marked, not deleted. P648 and P649 (art proof and close-out) stay there, after
P647.

ROADMAP: one new checkbox in Phase 5, the terrain kit (row P656 and its parts).

## Goal
Michael, 2026-11-27: "3D til terræn + bygninger, SVG-enheder". So:
1. **A terrain kit pre-rendered from our own 3D models**, at the sprites' density: four variants
   of each terrain, blends, cliff edges at rock and shores at water. Roads are added in the map
   looks as decoration only (question 4, answered).
2. **Every building pre-rendered** from our own model data at today's density, with the team
   panels recoloured at match start. Ironward's 3x3 buildings come first, with the recolour pass
   (P644).
3. **The SVG units restyled toward P655**: darker gunmetal bodies, team colour on the turret and
   the skirt or side panels, a longer gun. One row for all 18 detail-2 models, Ironward first,
   Facet in its own white and graphite language (P658). Its band gate is already met (below).
4. **Michael's look check** (P659): 3D terrain and buildings in the game with the SVG units on
   top. There he decides whether units go 3D. No unit pre-render row is planned before that.

Scope guard. Not in this plan:
- Pre-rendered units (open until P659).
- 2x density.
- Roads that change movement (a sim and balance change).
- Fields, the wellhead, ore, effects, damage overlays, glyphs, icons and the UI: they stay SVG.
- New maps, map editing and animated water.
- Any change to the sim, a Command, a hash or `data/`.

These go to the lead's follow-up list.

## Affected modules
| Area | Files (main ones) | Rows |
|---|---|---|
| The bake tool | `tools/prerender/` (mesh builder, rig, bake scenes, Python post, `requirements.txt`, `owned.tres`), `scripts/prerender.sh` | P656a, P656b |
| The manifest | `assets/art/prerender/manifest.tres`, `tests/art/test_prerender_manifest.gd` | P656b, every art row |
| Model data | `assets/art/models/<faction>/<id>_detail.tres` (buildings), `assets/art/models/terrain/` (kit) | P656c, P656c2, P644b-P647b |
| Terrain kit | `assets/art/terrain/` (tiles, `kit.tres`, `looks/`) | P656c, P656c2, P656f |
| Ground view | `game/view/GroundLayer.gd`, `GroundAtlas.gd`, a new `TerrainKit.gd`; `game/ui/PerfBases.gd` (forecast, only if the edge layer adds a call) | P656d, P656f |
| Recolour | `game/view/TeamRecolour.gd` (twin), `team_recolour.gdshader`, `TeamRecolourPass.gd`; a CI render step (`scripts/ci/run-render-tests.sh`, `.github/workflows/ci.yml`) | P644a |
| Atlas | `game/view/IsoAtlas.gd` (PNG frames, keyed parts), `WorldSort.gd` (owns the pass), `tools/artgen` (sheets of owned ids: `.png` paths, no SVG), the galleries | P644a2 |
| Same-scene check | `tools/artgen` composer (kit ground, twin-recoloured PNG buildings), `tools/artgen/same_scene_ground.tres` (new), `tests/art/test_same_scene.gd` | P656e |
| SVG units | `assets/art/models/**` (units), `assets/art/iso/**` (frames), `tools/artgen` `ArtPalette` (new body materials), STYLE.md | P658, P643 |
| Docs | ADR 0050 (notes), ADR 0023 (note), `assets/CREDITS.md`, `assets/art/STYLE.md`, `docs/HOW_TO_PLAY.md`, `docs/ROADMAP.md` | P654, P654b and the art rows |

Nothing in `game/sim`, `game/ai`, `game/core`, `native/` or `data/`. No row starts a balance run
(`data/**` is not touched).

## Command and data changes
- **Commands, `STATE_FORMAT`, the state hash, the defs hash:** none.
- **`data/`:** none. `kit.tres`, the look decor lists and `_detail.tres` are art under
  `assets/`, with no balance number in them.
- **Art formats:**
  - `IsoSheetDef` frames may be `.png`. `tools/artgen` writes those paths for owned ids.
  - A sheet lists its keyed parts, so `IsoAtlas` does not scan pixels.
  - New: the manifest resource, `TerrainKitDef` (`kit.tres`) and `SameSceneGroundBands`.
- **CLAUDE.md:** the Legal, Layout and Stack lines of ADR 0053 §6. CLAUDE.md's Legal, Layout and Stack lines are edited by the lead (approved by Michael's answer 2), before any PNG art merges (P656 / P644).
  Until then no PNG frame or kit tile merges.

## Test plan (what is proven headless)
- **Manifest** (P656b, every art row after it):
  - every committed PNG matches its manifest line (sha256, bytes, size);
  - no PNG is missing from the manifest;
  - each frame is its sheet's canvas at its part's factor;
  - a source model whose hash moved without a re-bake fails, naming the id;
  - no owned id still has an SVG frame or card.
- **Bake tool** (P656a, P656b):
  - mesh builder face counts and normals;
  - the triangle cap of 60,000 refuses more;
  - the rig's constants equal `IsoProjection`'s and `ArtShadow`'s (read, never copied);
  - `prerender.sh`'s version preflight: exit codes for a match, a mismatch and a missing tool;
  - the post refuses a clipped sentinel pixel.
- **Recolour** (P644a), on committed fixtures cut from a P655-style render and its ground-truth
  re-render in Signal and Kobolt:
  - the twin's mean error is at most 3.5/255, p99 at most 40, at most 2 % of team pixels over
    12/255 and at most 2 magenta fringe pixels a frame (P653: 3.1, 38.9, 1.9 %, 1; P655: 2.5, 9,
    0.1 %, 0);
  - `coverage` is exact on crafted mixes;
  - CI only: the render test, shader against twin, at most 1/255 a channel.
- **Atlas** (P644a2):
  - a PNG sheet packs to the same regions and offsets as an SVG sheet with the same canvases;
  - keyed parts are per player and shadows per faction;
  - under the dummy renderer the keyed frames stay in the sentinel;
  - the page rows are within the 40-row tolerance.
- **Ground** (P656c, P656d, P656f):
  - Kit completeness: every terrain id has 4 variants, every mask of the choice table has a
    piece, each piece is 128 x 64 to 100 texels and its lip is at most 36 texels.
  - The piece-choice tables, and the fixed cell hash in place of any random call.
  - The lip rule on every shipped map.
  - The writes: every cell once, then at most 9 per changed cell. There is no per-frame write.
  - `covers_map()`, and the SVG fallback for a terrain or look without kit pieces.
  - The ground page at most 512 rows of 4096 px.
- **Same scene** (P656e and every art row): the frozen bands of `same_scene.tres`, plus ADR 0053
  §8's ground bands:
  - the ground's mean saturation at most 0.30;
  - at most 5 % of the ground in a route triad's hue band;
  - no key-band pixel in the ground;
  - the ground's detail density at most 30 edges per 100 px²;
  - the 32 px greyscale spread at least 80 for every sprite over each kit terrain.
- **Per building batch** (P644b-P647b):
  - TEAM_SHARE by `coverage`, 30-65 % in the default view;
  - KRITISK at 20-50 % of the intact coverage;
  - the shape pairs under 0.85 in d06 and d10 (A4);
  - the 32 px greyscale spread at least 80;
  - the bytes per frame: 3x3 128 KB, 2x2 80 KB, 1x1 48 KB;
  - the page pins, and the manifest.
- **Per SVG unit row** (P658, P643):
  - the frozen same-scene audit green;
  - TEAM_SHARE 30-65 % (key band, A3) in the default view and 25-75 % in every direction;
  - the shape pairs under 0.85;
  - the 32 px greyscale spread at least 80;
  - the page pins.
- **Not headless:**
  - the look (Michael, P659);
  - the softness at zoom 2.0;
  - the readback and bake time on the phone (CI's `atlas_bake_ms`, the phone card in P659).

## Rows
Line counts are production lines changed (tests, fixtures, art, model data and docs do not count;
CLAUDE.md). Code in `tools/` counts, as in the restyle plan.

| Row | Owner | Depends | What | Acceptance (tests) | HOW_TO_PLAY | Prod. lines |
|---|---|---|---|---|---|---|
| P653 | art-director (another lane) | none | **Done as a prototype** (`claude/p653-prerender-prototype`, 5d2fa55d, never merged): tank, 3x3 building and terrain patch pre-rendered; `recolour2`; numbers | its own | none | n/a |
| P655 | art-director (another lane) | P653 | **Done as a probe** (`claude/p655-detailed-tank`, 9c6dcd71, never merged): a detailed Ironward `heavy_tank` (42,032 triangles) at 1x; the verdict "close at zoom 2, not at zoom 1"; recolour mean 2.5/255 | its own | none | n/a |
| P654 | architect | P621c merged | **This PR.** ADR 0053 (accepted 2026-11-27, P654b folded in), this plan, the ADR 0050 notes, the restyle plan's row notes, the ROADMAP row | docs lens | none | 0 |
| P654b | architect + lead | Michael's answers | **Done inside P654** (2026-11-27, "Godkend alle 7 (anbefalet)"): ADR 0053 accepted with the answer under each question; status notes in ADR 0023 §5 and ADR 0050; rows adjusted (P656f kept: roads as decoration). CLAUDE.md's Legal, Layout and Stack lines are edited by the lead (approved by Michael's answer 2), before any PNG art merges (P656 / P644). | docs lens | none | 0 |
| P656a | art-director | P654 merged | **The bake tool's core** in `tools/prerender/`, rewritten from P653 and P655 (not copied): the mesh builder (ArtMesh faces with bevel strips, plane-clipped solids, cylinders, domes, tori), the `_detail.tres` reader, the rig (an orthographic camera at `IsoProjection`'s angles, the sun along `ArtShadow`'s direction, fill, sky, SSAO), the hull and turret rig and 16 directions (unit-ready, ADR 0053 §1), the 60,000-triangle cap. `scripts/prerender.sh` with the pinned-version preflight (stops and names the difference; installs nothing) | mesh face counts and normals; the cap; the rig constants read from `IsoProjection` and `ArtShadow`; the preflight's exit codes | none | ~380 |
| P656b | art-director | P656a | **The post and the manifest.** The Python post (linear-light box filter to 1x, exposure gain only, PNG with no time, gamma or ICC chunks), `requirements.txt` pins, the refusal of clipped sentinel pixels; `assets/art/prerender/manifest.tres` and its writer; `prerender.sh --check` (re-render and compare only on the pinned stamp); `tests/art/test_prerender_manifest.gd` | the manifest test on a committed fixture PNG; a moved model hash fails; `--check` refuses another stamp | none | ~260 |
| P656c | art-director | P656b; the lead's CLAUDE.md edit | **The terrain kit, standard look**: the terrain model data under `assets/art/models/terrain/`; about 80 pieces (6 terrain ids x 4 variants, 8 blends, about 12 cliff lips, about 12 shores, water variants; the road pieces are made here and placed in P656f); `assets/art/terrain/kit.tres`; the manifest lines; the CREDITS row; STYLE.md "Terrain kit (ADR 0053)" | kit completeness; sizes; the lip at most 36 texels; no key-band pixel; the kit PNGs at most 5 MB; the manifest | none | art |
| P656c2 | art-director | P656c | **The two map looks' variants** (Curlew Crags, Heron Fords) as kit pieces, at most 4 per terrain they replace | the same as P656c, per look; the ground page with each look at most 512 rows | none | art |
| P656e | art-director | P656c | **The same-scene sheet on the kit ground.** The composer draws the kit's tiles in place of the SVG diamonds, and PNG buildings through the twin once P644a has merged (until then the SVG ones); `tools/artgen/same_scene_ground.tres` (new) with ADR 0053 §8's ground bands, set from today's diamonds and the kit; `same_scene.tres` untouched. The PR attaches the sheet at four zooms | the frozen audit green; the ground bands green; a crafted over-saturated ground tile fails | none | ~150 |
| P656d | gameplay-dev | P656c | **The ground wiring** (ADR 0053 §7): `TerrainKit.gd` (the pure piece choice, a fixed cell hash for the variants), `GroundAtlas` on the kit page, `GroundLayer`'s base and edge layers at scale 0.5, rewrites of the changed cells and their 8 neighbours, the lip rule, the SVG fallback. `PerfBases`' forecast constants and their test move only if the edge layer adds a call | the choice tables; the lip rule on every shipped map; the write bounds; `covers_map()` and the fallback; the page budget; `test_ground_*` and `test_perf_bases.gd` | `terrain-basics` (blends, cliffs at rock, shores at water, four arrangements) | ~300 |
| P656f | gameplay-dev | P656d (question 4 answered: decoration) | **Roads as decoration** in the map looks (`assets/art/terrain/looks/<look>/decor.tres`, cells and road pieces; a road replaces the base piece). No sim or movement change | the decor list loads; road cells only on passable ground; the write bound unchanged; no `data/` file touched | **New row** `terrain-roads`: roads are only looks, units are not faster on them | ~120 |
| P658 | art-director | P652 merged | **The SVG unit restyle toward P655, one row:** all 18 detail-2 models of P638-P642, Ironward first, then Facet in its own white and graphite language; P643's four models too if P643 has merged first. **The band gate is met** (throwaway measure on `main` c09c91be, nothing committed): (1) Ironward `heavy_tank` with the P652 `faction` → `team` swap and gunmetal step s3, as **new** materials (not the shared iron and steel): iron #2B2E32, steel #5C6066, body #4A4D52, reads `tone_sat` 0.132, `tone_sat_all` 0.379, 32 px spread 142.5, max mirror overlap 0.78, TEAM_SHARE 43.2 %, every frozen same-scene band passes; (2) Facet `renew_tank` at t2: graphite #2B2E32, titanium #5C6066, white kept, reads `tone_sat` 0.113, `tone_sat_all` 0.325, spread 199.5, TEAM_SHARE 52.1 %, all pass. **Binding bands, so the design limits:** `black_edge_max` 0.02 binds first (iron #212427 gives 0.223); `light_left_min` -0.04 binds second, Ironward only (s3b #25282B gives -0.042). The darkest body tone stays at about #25282B or lighter, and a right side is never much darker than its left. **The gun:** +0.2 tile longer (mirror overlap 0.78 → 0.685, spread -3); a taller turret gives nothing and is not taken. The team colour sits on the turret and the skirt or side panels (TEAM_SHARE 30-65 %, A3). **Stop rule:** if a longer barrel would move projectile spawns (muzzle points in `game/view` or `data/`), that change is a separate row and this one keeps today's muzzle points. STYLE.md "Unit restyle (P658)". **Split** into P658a (Ironward) and P658b (Facet) only if the production diff (the `ArtPalette` materials and any generator code; model data and frames do not count) goes over about 400 lines | per-unit checks for all its models; the frozen audit green with `same_scene.tres` byte-identical; `--check` clean; the page pins | `units-look`, `units-look-aircraft`, `units-look-carrier`, `units-look-minelayer`, `units-medic-squad-look` if their words change | art (+ materials) |
| P643 | art-director | P652 | (The restyle plan's row.) **Facet support and air**, still an SVG batch drawn under ADR 0050's amendment. If P658 has merged, it uses P658's materials; if not, P658 later takes these four models too | per-unit checks | the look rows of its models | art |
| P644a | gameplay-dev | P654 merged | **The recolour** (ADR 0053 §4): `TeamRecolour.gd` (the twin, `recolour` and `coverage`), `team_recolour.gdshader`, `TeamRecolourPass.gd` (the SubViewport pass, the readback, sync if `force_draw` works on desktop, Android and web, otherwise awaited behind the loading card; never a frame with sentinel magenta). The CI render step under `xvfb-run` with Compatibility. Fixtures: crops of a pre-rendered frame and its ground truth | the twin's error bounds; `coverage`; the render test in CI (at most 1/255); a runner without xvfb stops the row | none | ~250 |
| P644a2 | gameplay-dev | P644a, P656b | **The PNG path in the atlas**: `IsoAtlas` reads `.png` frames (`keep` importer, `load_png_from_buffer`), takes the keyed parts from the sheet, recolours per player through `WorldSort`'s pass, and resizes with Lanczos only below scale 1.0; `tools/artgen` writes `.png` paths and no SVG for the ids in `tools/prerender/owned.tres`; the galleries show PNG sheets. A fixture PNG building under `tests/art/fixtures` | regions and offsets equal to an SVG sheet of the same canvases; per-player keyed slots; the sentinel under the dummy renderer; `gen-art.sh --check` clean; the gallery tests | none | ~220 |
| P644b | art-director | P644a2, P656e, P658 | **Ironward 3x3, part 1**: `headquarters`, `refinery`, `vehicle_factory`. Detail data, bake (`hull`, `dmg2` with `char` and `hide`, `shadow`, cards in the faction colour), the manifest, CREDITS, SVG frames and cards deleted, `owned.tres`, the page pins. The PR attaches the same-scene sheet beside the SVG units on the kit ground | per-building checks; TEAM_SHARE by coverage 30-65 %; KRITISK 20-50 %; at most 128 KB a frame; the frozen audit and the ground bands green | `buildings-look` if its words change | art |
| P644c | art-director | P644b | **Ironward 3x3, part 2**: `fossil_airfield`, `fossil_space` (16 anim frames), `fossil_strike` (4 anim frames), anim crops at most a quarter of the body | as P644b | as P644b | art |
| P659 | architect + lead | P644c, P656d, P658 | **Michael's look check of 3D terrain and buildings with SVG units; he decides on 3D units.** He plays a cross and a mirror match on the phone (both orientations, zoom 0.75 to 2.0), with the perf card's draw calls and `atlas_bake_ms`. Recorded: (1) keep pre-rendered buildings (yes: P645 starts; no: P645-P647 return to the restyle plan's SVG batches and P644's ids leave `owned.tres` in one row); (2) 3D units yes or no (yes: a unit ADR and plan with P655 as the start, `heavy_tank` first; no: P658's look is the units' look) | Michael's answers in ADR 0053 | none | 0 |
| P645a | art-director | P659 (buildings kept) | **Facet 3x3, part 1**: `renew_hq` first, in ADR 0050 §2's faceted form, then `renew_refinery` and `renew_factory`. Each pair with its P644 counterpart under 0.85 in d06 and d10 | as P644b; the pairs | none | art |
| P645b | art-director | P645a | **Facet 3x3, part 2**: `renew_airfield`, `renew_space`, `renew_strike` | as P645a | none | art |
| P646a | art-director | P645b | **Ironward 2x2**: `barracks`, `power_plant`, `fossil_engineering`, `fossil_radar` (16 anim frames), `fossil_weld_shed` | as P644b, 80 KB a frame | none | art |
| P646b | art-director | P646a | **Ironward 1x1 with heads**: `defence_turret`, `fossil_aa` (16 head directions, trimmed boxes, unit-style rig) | as P644b, 48 KB a frame; head pins within 40 rows | none | art |
| P647a | art-director | P646b | **Facet 2x2**: `renew_barracks`, `renew_power`, `renew_engineering`, `renew_radar`, `renew_drone_dock`; the pairs with P646a | as P646a; the pairs | none | art |
| P647b | art-director | P647a | **Facet 1x1 with heads**: `renew_defence`, `renew_aa`; the pairs with P646b; KRITISK restored to 20-50 % for every building (the restyle plan's P647 item) | as P646b; KRITISK 20-50 % for all 26 | none | art |

After P647b come the restyle plan's P648 (art proof) and P649 (art phone check, close-out).

### Order, lanes and the critical path
- **The lead's order:** P621c (done) → P652 ∥ P654 → P656 and P658 → P644 → P659.
- **Can start once P654 has merged**, each in its own lane:
  - Lane P (art-director): P656a → P656b → P656c → P656c2 and P656e.
  - Lane R (gameplay-dev): P644a, then P644a2 (after P656b).
  - Lane W (gameplay-dev): P656d after P656c, then P656f.
- **Lane G (art-director, the page pins, one PR at a time):** P652 (open), then P658 and P643 in
  whichever order they are ready (both wait only on P652). P658 does not wait for P654; its band
  gate is met.
- **Buildings:** P644b (after P644a2, P656e, P658) → P644c → P659 → P645a → P645b → P646a →
  P646b → P647a → P647b → P648 → P649. Building bodies keep their canvases, so they do not move
  page 1's rows. Heads do (P646b, P647b). The building rows still go in series, because each one
  edits the manifest and the page pins.
- **Shared files:**
  - `assets/art/prerender/manifest.tres` and `tools/prerender/owned.tres`: one open PR at a time.
    The second to merge merges `main` first.
  - `tests/view/test_iso_atlas_budget.gd`'s pins: lanes G and the building rows. Verify the
    combined tree before the second merge.
  - `assets/CREDITS.md`, STYLE.md and `HOW_TO_PLAY.md`. Row P657 (the Ironward rename) works in
    the same files: the second to merge merges `main` and keeps both.
- **Critical path:** P654 → P656a → P656b → P656c → P656e → P644b → P644c → P659. P644a and
  P644a2 run beside it. The longest chain to the end is the building series after P659.

### Owners of HOW_TO_PLAY rows
- `terrain-basics`: P656d.
- `terrain-roads` (new): P656f.
- `units-look`, `units-look-aircraft`, `units-look-carrier`, `units-look-minelayer` and
  `units-medic-squad-look`: P658 and P643, for their own models.
- `buildings-look`: P644b, then each building row if its words change.

## Risks
1. **The look gain on buildings is smaller than hoped.** P653 used blockouts, and P655 showed that
   fine detail is lost at 1x. The gain is light, edges and occlusion, not rivets. Lever: P659,
   where Michael can stop the buildings after P644 (P645 waits for him).
2. **Two art sources on one map.** The same-scene check, with ADR 0053 §8's ground bands, guards
   it. Michael's eye on every sheet is the final check.
3. **The readback at match start.** `force_draw` plus `get_image` may not run inside a frame on
   every platform (the web preview above all). P644a tests desktop, Android and web, and falls
   back to an awaited pass behind the loading card. The twin is the last fallback (slow, with
   `push_error`).
4. **The shader cannot run headless.** The twin is the reference, and the CI render test ties the
   shader to it. That test needs xvfb and Mesa on the runner. If they are missing, P644a stops and
   says so.
5. **The bake container drifts.** A new Ubuntu or Mesa build changes low bits. `prerender.sh`
   refuses to bake on it, and the move is an explicit re-bake row with a sheet for Michael.
6. **No non-linear grade.** P653's look used a post grade (contrast 0.12, saturation 1.15).
   ADR 0053 §4 drops it so the recolour stays exact. P656a and P656c tune the lights and
   materials instead, and the P656e sheet shows the result.
7. **Ground texture bandwidth.** The kit's density is twice today's ground, and it fills the whole
   screen. It is the same density as the sprites, and with no mipmaps it shimmers in the same way
   at zoom 0.75. P659's phone card is the check.
8. **Closed (2026-11-27): the frozen same-scene bands and P658's darker bodies.** The throwaway
   gate on c09c91be passed every frozen band (`heavy_tank` s3, `renew_tank` t2; numbers in P658's
   row). What remains is a design limit, not a risk: `black_edge_max` binds at iron #212427 and
   `light_left_min` at #25282B (Ironward), so no body tone goes darker than about #25282B.
9. **Closed (2026-11-27): TEAM_SHARE with the team colour on the turret and the side panels.** The
   gate read 43.2 % (`heavy_tank`) and 52.1 % (`renew_tank`), inside 30-65 %. Each model of P658
   is still banded by its own test.
10. **Effort.** About one P638-size row per building (P655's estimate). The 26 buildings are in 8
    rows of 2 to 7 buildings, so a row can run long. A row that runs over splits by building.
11. **Legal drift.** A Figma look reference used as a template, or one of the file's names, could
    creep in. ADR 0053 §6 and the review's legal lens guard against it. Nothing from the file is
    committed.
12. **Row numbers.** P656, P658 and P659 were handed out by the lead, and P657 is the rename lane.
    Parts use letter suffixes (P658a and P658b only if P658 splits), so they never take a number
    another lane holds (grep open branches before adding rows).

## Michael's answers
- 2026-11-26 (the lead's AskUserQuestion), verbatim: "Trinvis: terræn + én detaljeret tank
  (Recommended)". This gave rows P653 and P655.
- 2026-11-27, after P655, verbatim: "3D til terræn + bygninger, SVG-enheder".
- 2026-11-27, verbatim: "Vi kan starte der og så kan tanks laves til 3D senere når jeg har set
  det?" The lead answered yes. Units are SVG for now, and 3D units are decided in P659.
- 2026-11-27, verbatim: "Ironward (Recommended)". Nordværn becomes Ironward in all new text. Row
  P657 renames the existing text.
- 2026-11-27, to ADR 0053's seven questions, verbatim: "Godkend alle 7 (anbefalet)". The recommended answer to all
  seven; the ADR is accepted.
