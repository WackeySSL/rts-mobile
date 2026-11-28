# Plan: playable high ground, a natural landscape and a skirmish map generator

Date: 2026-11-28. Author: architect. Row P680 is on branch `claude/p680-highland-plan` (base
`main` at 05c900a4). Rows P680-P699.

Decisions:
- `docs/adr/0055-highland-landscape.md`, **proposed**. Its 16 questions are below ("Decisions
  for Michael"); the answers are recorded in the ADR at acceptance, in this PR or a docs follow-up.
- It amends ADR 0053 §7 (A1, A4, A5, A7-A10 change or are extended; A2, A3, A6, A11 hold), ADR
  0008 §1 (the `heights` layer), ADR 0007 (`STATE_FORMAT` 8), ADR 0042 (the map spec in the
  resume), and, if question 7 is A, ADR 0033 (the facing rule under the transpose). The GDD's
  "Maps (MVP)" is rewritten in P699.

Michael's words (2026-11-28, through the lead, translated from Danish):
1. Rock must not look like man-made walls; natural landforms, for example a whole corner raised,
   or water right up against a cliff edge.
2. "B, so we don't have to redo the map landscape again afterwards. There must be ramps up to
   the raised map landscape."
3. "The landscape must also have bridges and trees and small abandoned houses."
4. Still in force: ADR 0053 §7 option C and silhouette look B (`claude/p656d3-silhouettes`,
   744d5d70).
5. 13:35Z: "We need more than 3 maps. It would be best with a generator that just generates maps,
   so we have no fixed maps. That way the game feels new every time you play it. Fixed maps are
   only for when we build mission maps."

## Goal
Skirmish matches are played on a new, natural landscape every time: plateaus with ramps, cliffs
into water, rivers with bridges and fords, woods and abandoned hamlets, made by a deterministic
generator from a map seed. High ground is playable and gives a readable advantage: it sees down,
and low ground does not see up without a spotter. The tutorials, the perf fixtures and future
missions keep fixed maps. 150 units at 60 fps on the 2021 phone still hold.

Scope pushback: this is about 25 PRs before launch. The plan keeps the first version small on
purpose: two levels, no new Command, no new combat number, no destructible terrain, no ore on
high ground, no garrisons, no screen redesign. Each of those is a later row if Michael asks.

## Affected modules
| Area | Files | Rows |
| --- | --- | --- |
| Sim map data | `game/sim/defs/MapDef.gd` (`heights`, `relief`, `symmetry`), new `game/sim/MapRelief.gd` (pure validation and the cliff derivation), `WorldLoad.gd` (`height`, cliff cost, `set_terrain`), `World.gd` / `WorldShape.gd` (`height` in `MAP_ARRAYS`, `map_symmetry` unhashed, `STATE_FORMAT` 8), `data/terrain/standard.tres` (`bridge` `=`, `house` `H`), `data/rules.tres` (`ramp_clearance_tiles`) | P681 |
| Placement | `Placement.gd`, `PlacementInput.gd` (ramp clearance) | P681 |
| Vision | `FogGrid.gd` (`stamp`, a per-mask flies byte), `FogUpdate.gd` (comment), `native/sim_kernels/src/core/fog.cpp`, `bind/kernel_fog.cpp`, `bind/world_access.h` (`height` in the checked table) | P682 |
| AI | `PlayerView.gd` (relief facts, ground distance, symmetry), `AiEconomy.gd`, `AiArmy.gd`, `AiUnseen.gd`, `AiIntel.gd` (scout), `AiMemory.gd` (mirror by symmetry) | P683, P684, P697 |
| View | new `game/view/Relief.gd` (lift, sort pad, ramp axes, `ground_at` helpers); `WallLayer.gd`, `WallKit.gd`, `WallCover.gd` (relief pieces, mask, taps), `IsoAtlas.gd` (relief band), `WorldSort.gd`, `UnitLayer.gd`, `BuildingLayer.gd`, `HealthBarLayer.gd`, `ProjectileLayer.gd`, `EffectsLayer.gd`, `DecalLayer.gd`, `AirLayer.gd`, `GhostMemoryLayer.gd`, `GhostLayer.gd`, `GroundLayer.gd` / `TerrainKit.gd` (bridge decks, foam), `TerrainPalette.gd`, `MinimapImage.gd`, `MapView.gd`, `MapPreview.gd`; `game/input/PlayerController.gd` (taps, placement); `MatchSnapshot.gd` (`height`) | P685-P687, P689b, P690 |
| Art | `tools/prerender` relief builders, `assets/art/terrain/kit.tres` and looks, `assets/art/models/terrain/*` (reserved), `assets/CREDITS.md`, `assets/art/STYLE.md` | P688, P689a |
| Maps | new `data/maps/highland_showcase.tres` and its scenarios, `scenes/dev/` route; `perf_bases` relief | P691, P692 |
| Generator | new `game/sim/mapgen/` (`MapGen.gd`, `MapSpec.gd`, `MapNoise.gd`, `MapLandforms.gd`, `MapFeatures.gd`, `MapCheck.gd`), new `game/sim/defs/MapGenPresetDef.gd`, `data/mapgen/*.tres` | P693a, P693b, P694 |
| Core and meta | `MatchSetup.gd` (map spec), `MatchRunner.gd` (generate before `from_scenario`), new `game/core/MapCode.gd`, `Replay.gd` (`FORMAT` 4), `ResumeData.gd`, `data/scenarios/skirmish_generated*.tres` (templates), `data/maps/catalog.tres`, `MapCatalog.gd` | P695 |
| UI (minimum) | `game/ui/menu/MapSelect.gd`, `DeployCard.gd`, `menu_flow_service.gd` | P698 |
| Tests and CI | `tests/sim/mapgen/*`, `tests/sim/test_map_fairness.gd`, `test_seat_symmetry.gd`, `tests/ai/test_seat_placement.gd`, `tests/smoke/smoke_run.gd`, `scripts/run-sim-smoke.sh` (flags kept), `.github/workflows/balance.yml` | P684, P696, P697 |
| Docs | `docs/HOW_TO_PLAY.md`, `docs/GDD.md`, `docs/ROADMAP.md`, ADR notes | per row, P699 |

## Command and data changes
- **No new Command.** Moves, attacks and placements work on relief as they are.
- `MapDef`: `heights` (`0`, `1`, `r`), `relief` (view only), `symmetry` (`half_turn`,
  `transpose`). An empty `heights` is all low, so no existing map file changes.
- `World.height` (`LOW` 0, `RAMP` 1, `HIGH` 2, `CLIFF` 3) in `MAP_ARRAYS`; `World.map_symmetry`
  unhashed. `STATE_FORMAT` 8.
- `data/terrain/standard.tres`: `bridge` (`=`, 10/10/10, not buildable) and `house` (`H`,
  0/0/0, not buildable) appended. Scrub keeps its id and rule; its text becomes "woods".
- `data/rules.tres`: `ramp_clearance_tiles` 1; the map rule ints `ramp_width_min` 2,
  `ramp_width_max` 4, `ramp_length_max` 2 (RulesDef defaults equal the file).
- `data/mapgen/kestrel_flats.tres`, `map_2.tres`, `map_3.tres` (`MapGenPresetDef`): every
  generator number (sizes, noise spacing and thresholds, feature counts, ramp counts, ore field
  counts and yields, safe distance, build space, `attempts_max`).
- `Replay.FORMAT` 4 (the map spec), the resume file's setup dictionary gains the spec (its own
  version moves), `MatchSetup.map_spec`.
- `data/maps/catalog.tres`: the three entries become landscape types with the same ids;
  `data/meta/trophies.tres` text only.
- **Exceptions:** 27 (P681: every golden moves, the map layout), 28 (P692: `bases_golden_hex`, a
  plateau in `perf_bases`). Next free after this plan: 29.

## Test plan (what is proven headless)
- **Relief data (P681):** `MapRelief.validate` rule by rule on crafted grids (sizes, characters,
  terrain on high cells, ramp rectangles and axes, reachable plateaus, the diagonal pinch, ring 1
  of starts and ore); the cliff derivation (a high cell next to a low one, a ramp is not low);
  `move_cost` 0 on cliffs for all ground classes and open for AIR; `set_terrain` on a cliff keeps
  0; a unit ordered across a plateau goes through the ramp (both implementations, `sim_impls.gd`,
  which shows that the kernels need no change); placement refuses ramp cells and their clearance
  and accepts a plateau top; the re-pin under exception 27 with every golden listed.
- **Vision (P682):** under both implementations: a low viewer does not stamp high or cliff
  cells; a ramp, high or flying viewer does; stamp and unstamp are symmetric (counts back to 0
  after a walk up and down and after a death); a spotter lets a low unit acquire a high target;
  the FOG lockstep test over 900 ticks on a relief map and once on non-default rules; crafted
  edge cases (a viewer on the map edge, a mask crossing a ramp); every golden unchanged (flat
  maps); the sanitizer job; about 10 mutants.
- **AI (P683, P684, P697):** crafted relief: the wave stages at the ramp foot and climbs as one
  group; fire from an unseen high cell sends the group up the ramp; ore ranked by ground
  distance; the scout visits each ramp top; no map id in `game/ai` (grep test). Transpose maps:
  every AI building of player 2 is the transpose of one of player 1's in 3000 ticks; facing ties.
  Generated seeds: 30 seeds per type, Normal against Normal, 6000 ticks: no stall, both sides
  expand.
- **View (P685-P687, P689b, P690):** lift on every height and along each ramp direction; the
  sort brute force on crafted relief and on 20 quality-suite maps (each lifted rig after every top
  it overlaps, before every low object that overlaps it from in front, 4 samples a px); the relief
  piece tables (every mask, ramps in four directions, cheeks); one row node per diagonal; every
  relief sprite a `PAGE_SORTED` region with no material; the fog states and write bounds; lifted
  shadows and rings in the sorted world; decal strips; silhouettes only for low rigs; `ground_at`
  on tops, ramps, cliffs and flat ground; the placement ghost lifted; air shadows on high ground;
  no node made after warm-up over 300 frames; the relief sprite count per map; the page pin (band
  at most 640 rows); the minimap tones.
- **Generator (P693a, P693b, P694, P695, P696):** the noise and smoothing on fixed seeds (pinned
  digests); exact symmetry for both symmetries; per-version digests of 10 seeds per type and
  size; **the quality suite**: 200 seeds per type and size, each valid by `MapCheck`, exactly
  symmetric, with no 1-cell line, single-cell hole, diagonal pinch or square ring, 0 kit
  fallbacks, under the cell-visit budget, re-rolls under a pinned bound, and the fallback recipe
  valid for every seed it is forced on; the map code round-trips and refuses another version or
  a bad check character; a replay and a resume of a generated match reproduce the final hash;
  `MapSpec` in the resume dictionary; the catalog's ids unchanged and the trophies' keys
  unchanged.
- **Not headless:** the look (Michael's gates), the shader render test (CI), the frame time and
  `mapgen_ms` (CI's perf report and the phone card), the balance (GitHub Actions only).

## Rows
Production lines exclude tests and fixtures (CLAUDE.md). A row over ~400 splits as named.
"Gate" is Michael's look gate on the phone preview unless it says lead.

| Row | Owner | Depends | Scope | Tests | HOW_TO_PLAY | Prod lines | Gate |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P680 | architect | none | This plan and ADR 0055 (proposed). Michael's answers go into the ADR at acceptance | none (docs) | none | 0 | 1 docs lens |
| P681 | gameplay-dev | P680 accepted | **Relief in the sim data**: `MapDef.heights`, `relief`, `symmetry`; `MapRelief.gd` (validation, cliff derivation, ramp axes); `World.height` in `MAP_ARRAYS`, `map_symmetry` unhashed, `STATE_FORMAT` 8; `WorldLoad` (height, cliff cost 0 on ground classes, `set_terrain` keeps cliffs); terrains `bridge` and `house`; `ramp_clearance_tiles` and the ramp rule ints; `Placement` ramp clearance; re-pin under **exception 27** | see Test plan, relief data; mutants | none (P698) | ~260 | none |
| P682 | gameplay-dev | P681 | **The sight rule** (ADR 0055 §4) in `FogGrid.stamp` and `core/fog.cpp` with `kernel_fog.cpp`, `world_access.h`; the per-mask flies byte | see Test plan, vision; lockstep; sanitizer; mutants | none (P698) | ~90 GD + ~70 C++ | none |
| P683 | ai-dev | P682 | **AI relief awareness**: `PlayerView` relief facts (height copy, ramps, plateau ids, ground distance from the HQ); economy by ground distance; army staging at the ramp foot and the group climb; `AiUnseen` up the ramp; the scout's ramp tops; the no-map-id grep test | AI crafted relief | none | ~320 | none |
| P684 | ai-dev + gameplay-dev | P681 (beside P683); only if question 7 is A | **Transpose symmetry**: `AiMemory.mirror` and `AiEconomy`'s frame by `PlayerView.map_symmetry` (a reflected frame); `test_map_fairness`, `test_seat_symmetry`, `test_seat_placement` check each map's own symmetry; ADR 0033's facing tie rule checked on transpose maps (changed only if a test shows bias; a golden move is a named re-pin) | AI transpose tests; existing half-turn tests unchanged | none | ~150 | none |
| P685 | gameplay-dev | P681, P656d3 merged | **View relief model**: `Relief.gd` (lift, sort pad, ramp axes from the snapshot), `MatchSnapshot.height`, `WallCover.ground_at` for tops, ramps and cliffs, the raised mask (rock, high, cliff) | lift, `ground_at`, mask | none | ~200 | none |
| P686 | gameplay-dev | P685, P688 (fixture pieces until it lands) | **Relief pieces in the sorted world**: `WallLayer`/`WallKit` draw tops, cliff faces and crests, ramps and outcrops in the A4 row nodes; A6 states for all; `IsoAtlas` relief band; `MapDef.relief` opt-in; the standard look's relief as every look's fallback; `walls_sandbox` gets a plateau, ramps in four directions and a cliff into water. **Split** if over ~400: ramps become P686b | piece tables, row nodes, fog states, page pin, sprite count | none | ~380 | lead (sandbox) |
| P687 | gameplay-dev | P686 | **Lifted objects**: `UnitLayer`, `BuildingLayer`, bars, `GhostMemoryLayer` and `GhostLayer` lift and sort pad; shadows and rings of lifted rigs in the sorted world (ring art on `PAGE_SORTED`); silhouettes off for lifted rigs; `PlayerController` taps and placement through `ground_at`, the ghost lifted. **P687b** (split taken now): projectiles and effects (interpolated lift), decal strips, `AirLayer` shadows on high ground | the sort brute force, taps, ghost, no allocation per frame | none | ~300 + P687b ~200 | lead (sandbox) |
| P688 | art-director | P680 accepted (beside P681-P687) | **The relief kit**: crests per top terrain, faces (P656d4's rock), foam foot, ramps in four directions with cheeks, for the standard look (heron and crags in P688b, which may follow P698 since the standard look is the fallback); `kit.tres`; CREDITS; STYLE.md; same-scene sheet with units on and below a plateau | kit completeness, sizes, key band 0, light order, the manifest, the kit at most 5 MB | none | ~150 tools + art | **Michael** (sheet next to P653's) |
| P689a | art-director | P688 | **Props art**: trees (4-6), abandoned houses (4), bridge decks and piers per axis, through `tools/prerender` | as P688 | none | ~100 tools + art | **Michael** (sheet) |
| P689b | gameplay-dev | P686, P689a | **Props in the view**: trees on woods cells and houses as sorted props (lifted on high ground, A6 states), bridge decks in the ground layer (`TerrainKit` piece choice by axis), foam on water at a cliff foot | piece choice, props per cell by hash, write bounds | none (P698) | ~250 | lead (sandbox) |
| P690 | gameplay-dev | P681 (beside P685) | **Minimap and preview**: `TerrainPalette` tones for high ground, cliffs, bridges and houses; `MinimapImage`, `MapView`, `MapPreview` read `height` | image pins on a crafted relief map | none | ~100 | none |
| P691 | gameplay-dev + art-director | P682, P687b, P689b, P690 (P684 if transpose) | **The showcase map**: `data/maps/highland_showcase.tres` (about 56 x 56, the chosen symmetry, every feature: a raised corner, a central plateau with two ramps, a ridge, a cliff into a lake, a river with mirrored bridges and a ford, woods, two hamlets), its cross and mirrored scenarios, a dev route; the fairness test entry; **`walls_enabled` on in `scenes/main.tscn`** (relief only where `MapDef.relief` is on) | map validity, symmetry, reachability, fairness; walls on and relief only on opt-in maps | none (P698) | ~60 + map data | **Michael** (phone, both orientations, zoom 0.75-2.0) |
| P692 | gameplay-dev | P687b, P688 | **Perf on relief**: `perf_bases` gets a plateau, a ramp and woods (`relief` on), re-pin `bases_golden_hex` under **exception 28**; `PerfBases` constants re-checked (expected unchanged, 18 / 19 / 25); `mapgen_ms` and the relief sprite count in the perf report | `test_perf_bases.gd`, the pin | none | ~80 | **Michael** (phone perf card on the showcase and perf scene) |
| P693a | gameplay-dev | P681 (beside P682-P692) | **Generator core**: `MapSpec` (version, map seed, type, size, players), `MapGen.VERSION`, `MapGenPresetDef` and the three preset files, `MapNoise` (integer value noise, smoothing, opening and closing), the symmetric writer for both symmetries, the cell-visit counter; no features yet | noise digests, symmetry, budget | none | ~300 | none |
| P693b | gameplay-dev | P693a | **Landforms**: plateaus and raised corners, ridges, lakes and coasts with cliffs into water, rivers along the axis; heights and ramps placed by the relief rules | landform digests, `MapRelief.validate` green on 200 seeds | none | ~380 | none |
| P694 | gameplay-dev | P693b, P682 | **Features and validation**: starts with build space, ore fields (safe and contested, equal by ground distance), bridges and fords, woods clusters, hamlets, road decor; `MapCheck` (reachability, pockets filled or failed, ore balance, build space, ring 1, symmetry); deterministic re-roll and the fallback recipe | the quality suite (first half: validity, symmetry, shape rules) | none | ~380 | none |
| P695 | gameplay-dev | P694 | **Generated skirmish wiring**: `MatchSetup.map_spec` and its dictionary; the runner generates before `from_scenario` (the `DetRng` stream, the template scenarios); `Replay.FORMAT` 4; the resume; `MapCode`; the catalog's three ids as landscape types; `MapPreview` by map code | replay and resume of a generated match, code round-trip, catalog and trophy keys unchanged | none | ~350 | none |
| P696 | qa-engineer + release-engineer | P695, P689b | **Quality suite and CI**: the quality suite's second half (0 kit fallbacks: needs P686 and P689b), per-version digests; `run-sim-smoke.sh` keeps `--map kestrel/heron/curlew/all` as the landscape types, the map seed from the match seed; `balance.yml` seed sweep (types x sizes x seeds, both seats) | `test_smoke_map.gd`, `test_ci_balance_maps.gd`, the suite | none | ~150 (scripts) | none; then the **balance run in Actions** |
| P697 | ai-dev | P683, P695 | **AI on generated maps**: the 30-seed suites per type; fixes they find (no map-specific code) | AI generated-seed suites | none | ~200 | none |
| P698 | touch-ux-dev | P691 (Michael's yes), P695, P697, P688 | **Players get it**: today's map select shows the three landscape types (new titles), a size choice, "New map" and the map code under the preview; the deploy card shows the type and the code; the catalog no longer lists the three fixed maps | menu suites at the six sizes | new `terrain-high-ground`, `terrain-ramps`, `terrain-woods`, `terrain-houses`, `terrain-bridges`, `buildings-ramp-clear`, `menus-new-map`, `menus-map-code`; `terrain-basics` and `terrain-blocked` updated | ~250 | **Michael** (phone: each type at two seeds, both orientations) |
| P699 | architect + lead | P698, the balance run | **Close-out**: GDD "Maps" rewritten; ROADMAP row ticked; ADR 0053 and ADR 0033 notes; which tests of the three fixed maps the generator suites now cover (retire those, keep the rest as fixtures); ADR 0055 status | docs | none | 0 | 1 docs lens |

HOW_TO_PLAY: every relief and generator row lands in P698, the PR in which players first see the
features. Rows under "Not yet in the game" take `later-` ids, and an id never changes, so drafting
them there early would only retire ids later.

### Order, lanes and the critical path
- **Before anything:** P680 accepted. The in-flight P656d rows finish first or beside it (see
  below); P685 needs P656d3 merged.
- **Lane S (sim, gameplay-dev):** P681 → P682 → P694 (after P693b).
- **Lane G (generator, gameplay-dev):** P693a (after P681) → P693b → (P694 in lane S or here)
  → P695.
- **Lane V (view, gameplay-dev):** P685 and P690 (after P681, in parallel) → P686 → P687 →
  P687b → P689b.
- **Lane P (art-director):** P688 → P689a, from acceptance on, beside every gameplay lane.
- **Lane A (ai-dev):** P684 (after P681, if transpose) and P683 (after P682) → P697 (after P695).
- **Then:** P691 (joins S, V, P and P684) → Michael's gate → P692 beside it; P696 after P695;
  P698 after P691's yes, P695 and P697; the balance run; P699.
- **Critical path:** P681 → P685 → P686 → P687 → P687b → P689b → P691 (gate) → P698. The
  generator lane (P693a → P695, five rows) runs beside it and should be ready by P691's gate.
- **Shared files** (verify the combined tree before the second of a pair merges; one read-only
  interaction review when both touch the same system): `MapDef.gd` (P681, P693a), `WallLayer.gd`
  (P686, P689b), `UnitLayer.gd` (P687, P687b), `PlayerView.gd` (P683, P684), `AiEconomy.gd`
  (P683, P684), `MatchSetup.gd` (P695, P698), `scenes/main.tscn` (P691, P698), `IsoAtlas.gd`
  (P686, P687), `data/rules.tres` (P681 only), `test_map_fairness.gd` (P684, P691).

### Look gates
- **Michael:** P688 (relief kit sheet), P689a (props sheet), P691 (the showcase on the phone:
  plateaus, ramps, a cliff into water, bridges, woods, houses, silhouettes behind cliffs, fog on
  plateaus, both orientations, zoom 0.75-2.0), P692 (the phone perf card), P698 (generated maps of
  each type). No merge before his yes on P691 and P698.
- **Lead:** P686, P687, P689b in `walls_sandbox`.

### Owners of HOW_TO_PLAY rows
All in **P698** (touch-ux-dev writes them; gameplay-dev checks the rule text):
- `terrain-high-ground`: "Units on high ground see the ground below. Units below cannot see up
  until one of your units stands on a ramp or on top, or an aircraft flies over; then all your
  units can shoot up." Teach.
- `terrain-ramps`: "Ramps are the only ways up. Cliffs block everyone except aircraft." Teach.
- `buildings-ramp-clear`: "You cannot build on a ramp or right next to one."
- `terrain-woods` (and `terrain-blocked` reworded from scrub to woods): "Soldiers walk through
  woods; vehicles drive round."
- `terrain-houses`, `terrain-bridges`.
- `terrain-basics`: cliffs and rock outcrops stand up and hide what is behind them; a hidden unit
  shows as a hatched shape (P656d3's line, reworded).
- `menus-new-map`, `menus-map-code`.
- The tutorial (ADR 0044) gets a high-ground drill in a later row, from the Teach marks; not in
  this plan.

## The in-flight P656d work (question 15)
- **#733 (P656d1, ground wiring and the stone rule): merges as planned.** Nothing in it conflicts.
- **d4b (`claude/p656d4b-boulder`, the stone set): merges as planned.** The boulders are ground
  decoration and suit the natural look.
- **d3 (`claude/p656d3-silhouettes`, 744d5d70): merges its code, with the walls off in the main
  scene.** Its commit 4f9c3189 ("walls_enabled on in the main scene") must be reverted on the
  branch before merge: otherwise `main` shows today's man-made rock rings raised on all three
  maps. Its commit 0bf9eb72 (walls on in the perf arena) stays, so the perf card keeps counting
  the silhouette call. Its look gate is judged in `walls_sandbox` and the silhouette capture,
  not on Kestrel, Heron or Curlew, which will not ship as they are. Its HOW_TO_PLAY line about
  walls describes nothing players see while the flag is off; the lead either holds it for P698 or
  merges it as is, and P698 rewords it.
- **The flag goes on in P691** (the showcase map), with `MapDef.relief` as a per-map opt-in, so
  the tutorials and the old maps stay flat. Players see relief when P698 ships the generator.
- **ADR 0053's amendments:** A5's 224-row budget and A8's "placement keeps the flat inverse"
  are superseded; A1, A4, A7, A9 and A10 are extended; A2, A3, A6, A11 hold (ADR 0055 §9).

## Balance runs (GitHub Actions only, never in a session)
- **After P691** (optional, the lead's call): one run on the showcase map, both seats, to see
  that the sight rule does not decide matches by seat.
- **After P696 (required):** the seed sweep: three types x three sizes x 20 seeds x both seats,
  Normal and Hard. Read: the seat split (the balance gate's seat check, ADR 0031; the harness's `seat` labels become left and right on transpose maps), the median length against
  the Phase 5 target, stalls 0, re-rolls per seed.
- **After P698 (required before ROADMAP is ticked):** the same sweep on the shipped `main`.

## Risks
1. **The sorted page.** The relief band (lit and dim) may not fit in 640 rows across three looks
   and four ramp directions. Levers: dim by `self_modulate` (halves the band) after the lead
   checks on the web preview that it keeps one batch; trim and pack tighter; relief pieces for
   the standard look only, as every look's fallback.
2. **Sprite count on large relief maps.** Thousands of static sprites cost CPU in the renderer
   on the phone. Pinned at 2,400 per 64 x 64 map; lever: per-row `_draw()` for the tops (one
   canvas item per row).
3. **Sorting on ramps and lifted props** is approximate between ramp cells and their side cliffs.
   The brute-force test bounds it; the look gate judges it. Back-facing ramps may hide their
   units partly with no silhouette.
4. **Generator quality.** "No ugly artefacts" is partly taste. The shape rules and the 0-fallback
   test catch the mechanical ones; Michael's P698 gate catches the rest. Lever: tune the preset
   data before the code. A preset change also changes the output, so `VERSION` covers the
   generator code and the preset data together, and the digest test forces the bump.
5. **Re-rolls and time on the phone.** Bounded by `attempts_max` and the cell-visit budget; CI
   reports `mapgen_ms`. If a type fails often, its preset is too tight.
6. **AI on unknown layouts** may stall at chokes or ignore plateaus. P683 and P697 test 30 seeds
   per type; `AiStall` stays the safety net. The balance sweep is the real check.
7. **Seat fairness under the transpose.** Tie-breaks by lower id, ADR 0033's diagonal ties and
   the AI's frames may favour a seat. P684 tests exact mirrored AI bases; the sweep reads the
   split.
8. **Old replays, resumes and codes** break at P681 (`STATE_FORMAT` 8) and at every generator
   version. Accepted (question 11); the refusal note says why.
9. **Scope.** About 25 PRs before launch; ROADMAP Phase 6 and 7 move back. Michael decides the
   phase (question 16).
10. **In-flight d3** turns the walls on in the main scene today (4f9c3189). If it merges
    unchanged, players see raised rock rings. Revert that commit on the branch first.
11. **Exception numbers.** 27 and 28 are taken here; another plan that re-pins before P681 must
    take 29 and up, or the two collide.

## Decisions for Michael
The same 16 questions as ADR 0055's end, each with the recommended answer first.

| # | Question | Options | Recommended |
| --- | --- | --- | --- |
| 1 | High-ground advantage | A: sight only (low ground needs a spotter on the ramp, on top or in the air). B: A + 1 tile range shooting down. C: A + less damage from below | **A**: readable, no new number, the sight is a strong edge |
| 2 | Ramps | A: 3 wide (2-4), 2 long; 2 ramps on a plateau next to a start, 1-2 elsewhere. B: 2 wide, one each | **A**: chokes without stalls |
| 3 | Plateau tops | A: grass, sand, woods, houses; buildable; no ore and no starts on high ground yet. B: ore and starts up there now (one more view row) | **A**: smallest version; B later after the look gate |
| 4 | Houses | A: block the way, indestructible, hamlets of 2-5. B: destructible. C: garrison (later) | **A** |
| 5 | Bridges | A: over water only, 3 wide, indestructible, with fords. B: destructible (later) | **A** |
| 6 | Trees | A: scrub becomes woods with trees; soldiers through, vehicles round; no sight effect. B: A + hidden inside woods. C: a second dense forest | **A**: one rule players already know |
| 7 | Symmetry | A: transpose, left and right corners, a mirror image on the screen. B: half turn (top and bottom) | **A**: with cliffs, the half turn shows one seat the back of everything |
| 8 | Kestrel, Heron, Curlew | A: out of the menu with the generator, kept as test files, ids become types. B: keep as "classic maps" (+3 redesign rows). C: delete | **A** |
| 9 | Landscape types | A: three types with the old ids, titled "Open Plains", "River Valley", "Highlands". B: keep the old titles | **A**: trophies, wins and unlocks carry over either way |
| 10 | Sizes | A: 48, 56, 64. B: 56 only at first | **A** |
| 11 | Old replays and codes after a generator change | A: refused with a note. B: keep every old generator | **A** |
| 12 | Map seed and match seed | A: separate. B: one seed | **A**: replay a map with fresh randomness |
| 13 | Skirmish options now | A: type, size, "New map", preview, code shown; entering a code later. B: also enter a code now | **A**: the screen redo is parked |
| 14 | When relief turns on | A: the flag on with the showcase (P691), per-map opt-in; players get it with the generator (P698). B: only with the generator | **A**: Michael judges it in the real main scene earlier |
| 15 | In-flight P656d | A: #733 and d4b merge; d3 merges with 4f9c3189 reverted (walls off in main), perf arena walls on. B: hold d3 until P691 | **A** |
| 16 | Roadmap | A: a Phase 5 row before launch. B: after launch as an update | **A** (Michael's "best game"), with the scope risk stated |

Proposed ROADMAP row for answer 16 A (added at acceptance): "Natural landscape with playable
high ground and a skirmish map generator (ADR 0055, rows P680-P699): two heights with cliffs and
ramps, woods, abandoned houses, bridges and fords; every skirmish map generated from a map seed
in three landscape types and three sizes, transpose-symmetric, validated before use; replays,
resumes and map codes store only the spec. Numbers: 200 seeds per type and size validate with 0
kit fallbacks; generation at most 150 ms typical and 400 ms worst on the reference phone (CI's
report); draw calls 18 / 19 / 25; relief at most 2,400 sprites and 640 page rows; the balance
sweep's seat split within the balance gate's seat check (ADR 0031). Michael's look checks in P691 and P698."
