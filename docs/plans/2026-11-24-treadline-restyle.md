# Plan: the Treadline restyle (UI look, faction rename, art pipeline, closer zoom)

Date: 2026-11-24. Author: architect. Rows P600, P603 and P621 were on branch
`claude/p600-treadline-plan` (PR #642, merged as 653383c5). Row P621b is on
`claude/p621b-adr0050-accept`.

Decisions:
- `docs/adr/0049-treadline-restyle.md`, **accepted** 2026-11-24 with Michael's answers (row
  P603, done on this branch).
- `docs/adr/0050-art-pipeline-svg-units-png-buildings-fixed-colours-deeper-zoom.md`, **accepted**
  2026-11-24 (row P621b). Everything on the map is generator SVG. Figma AI is for stand-alone
  art. One coherent look (§8).
- ADR 0051 (#643, accepted by the lead's row P622): Figma's own AI features may make art that
  ships.

ROADMAP: no checkbox. The restyle improves finished Phase 5 screens. Phase 7's trademark box
covers the new names (ADR 0006's note). Row numbers P622 and P623 belong to ADR 0051's lane, so
the art rows start at P630.

## Goal
Michael's decisions and answers of 2026-11-24:
1. Restyle the look toward his Figma file (`HsBPSXZ6PTRp6KkdhEi6bT`), starting with the UI: the
   battle HUD, the menus, loading, pause, victory and the build drawer, in both orientations. The
   corner HUD keeps its geometry (answer 1 A).
2. Rename the factions only: **Nordværn** (orange, today's Derrick League, id `fossil`) and
   **Facet** (blue, today's Lumen Accord, id `renew`). Unit and building names and the lore stay
   (answers 3 A, 4 A). The title Treadline stays (ADR 0006). The text stays English.
3. **One coherent look across all graphics** (units, buildings, terrain, effects, UI icons, item
   cards). Every art route and batch passes the same-scene check (ADR 0050 §8). Units become more
   realistic in SVG, with fixed faction colours and a small team marker. Every building is
   generator SVG with the Figma vector's faceted form. Figma AI makes only stand-alone art:
   menu and loading backdrops, portraits and store art (ADR 0050 §2, answer 1).
4. A zoom level closer than today's (ADR 0050 §6).

Scope guard. Not in this plan:
- Campaign, multiplayer, the unit-details screen.
- A radio or subtitle feed.
- Move, Attack, Guard or Patrol buttons.
- The file's landscape layout.
- Translations.
- Any change to the sim's rules or hashes.

These go to the lead's follow-up list if a row asks for them.

## Affected modules
| Area | Files (main ones) | Rows |
|---|---|---|
| Theme and fonts | `game/ui/theme.tres`; a mono face only if P602 finds one; `assets/CREDITS.md`, `LicenceCatalog.gd`, the export notices | P604, P605, P609-P617 |
| Battle HUD (look only) | `EconomyPill.gd`, `RadarScope.gd`, `AttackToast.gd`, `BuildButton.gd`, `StrikeButton.gd`, `GroupColumn.gd`, `EconomyCard.gd`, `CommandBar.gd` and `OrderFlow` (P581), `BuildSidebar.gd`, `ItemTile.gd` | P609-P611 |
| Top row (geometry) | `EconomyPill.gd`, `HudCorners.gd` (the pill's width only) | P618 |
| Menus | `MainMenu.gd`, `MenuScreen.gd`, `MapSelect.gd`, `DeployCard.gd`, `PauseMenu.gd`, `ResultScreen.gd` | P613-P617 |
| Names | `data/factions/*.tres`, `MainMenuText.gd`, `MapSelectText.gd`, `data/help/how_to_play.tres`, `data/tutorial/text_en.tres`, `docs/GDD.md` | P607, P608 |
| Generator | `tools/artgen/` (`ArtModel`, `ArtPalette`, a detail renderer, macros), `assets/art/models/**`, `assets/art/iso/**` | P630-P632, P630c, P638-P647 |
| Bake and view | `game/view/IsoAtlas.gd`, `WorldSort.gd` (the key table), the galleries | P632 |
| Same-scene check | a composer in `tools/artgen`, `tools/artgen/same_scene.tres`, `tests/art/test_same_scene.gd` | P629, every art row |
| Stand-alone art (Figma AI) | PNG backdrops and portraits under `assets/art/menu/`; `assets/LICENSE.md`; CREDITS rows and their test; `MainMenu.gd`, `DeployCard.gd`, `MapSelect.gd` (placement only) | P623, P650 |
| Zoom | `data/input_settings.tres`, `InputSettings.gd`, `RtsCamera.gd` tests; `TutorialConditions.gd` (Kind 19), `data/tutorial/basics.tres` | P633, P634 |
| Docs | ADRs 0049, 0050; `svg-art-style`, `assets/art/STYLE.md`, `docs/HOW_TO_PLAY.md` | P602, P621b, P630b, P649 |

Nothing in `game/sim`, `game/ai`, `game/core` or `native/`. Two rows start a balance run (the
`balance.yml` paths): P607 (`data/factions/`) and P634 (`data/input_settings.tres`).
`data/tutorial/**` and `data/help/**` do not start one.

## Command and data changes
- **Commands:** none. `STATE_FORMAT`, the state hash and the defs hash are unchanged. No unit name
  changes, so P606 is not run (ADR 0049 §6). It moves to Phase 7.
- **Data:**
  - `FactionDef.display_name`: "Nordværn" and "Facet".
  - The help and lesson tables change values only. The menus' side names come from one source
    (`FactionDef`, or new keys `menu.side.fossil` and `menu.side.renew`; P607 picks one and tests
    it).
  - `zoom_levels` becomes (0.75, 1, 1.5, 2.0), appended (P634).
  - `TutorialConditions.Kind` 19 `ZOOM_AT_LEAST`, appended (P633).
- **Theme:** new values for `HudTokens`, `AccentFossil`, `AccentRenew`, `Menu*` and `GuideTokens`,
  plus new tokens if P602 finds them. No type is renamed.
- **Art:**
  - `ArtModel.detail` (0-3, default 0 = today's bytes).
  - Fixed faction materials in `ArtPalette`.
  - One sentinel key triad in place of the two per-faction keys.

## Test plan (what is proven headless)
- **Tokens** (`tests/ui/test_ui_theme_tokens.gd`, new in P604):
  - Every token resolves.
  - Each accent is at least 15° in hue from danger and from money.
  - Text on the accent has a contrast of 4.5:1 or more.
  - The theme scan is green.
- **Geometry unchanged** (P609-P617): `HudCorners`' pinned tables, P581's
  `test_command_bar_stack.gd`, the guide sweep, `test_build_sidebar*` and the menu suites pass at
  the six sizes and both orientations, with no edit to their expected rects.
- **Menus:**
  - Tiles: two columns only where the measured width allows, at least 48 dp.
  - The start banner keeps its 48 dp of air.
  - The pause foot banner is upright only and at least 16 dp from any control.
  - No ad slot on the result or deploy screens.
- **Rename:**
  - No "Derrick League" or "Lumen Accord" in player-facing text.
  - The side names equal `FactionDef.display_name` in upper case.
  - The coverage and lesson-data suites are green.
- **Clock and count** (P618):
  - The label is set on change only (a per-frame counter in the test).
  - The pill fits, or they go.
  - The guide sweep is green.
- **Generator** (P630-P632):
  - `--check` stays byte-identical at detail 0.
  - Each level uses only the allowed elements.
  - Gradient ids are in order, and no key colour is in a gradient.
  - Polygon and byte budgets per frame hold.
  - The key band holds against the sentinel, and the bake replaces it for all eight triads.
  - The share bands hold, and the page rows stay inside the 40-row tolerance.
- **Same scene** (P629): the sheet builds headless for both factions at four zooms; the light
  order, tone bands, edge rule, detail-density band and contact-shadow style hold for every
  sprite on it.
- **Facet primitives** (P630c): a chamfered box and rotated prisms give the expected faces and
  normals; `--check` is byte-identical for every existing model.
- **Building budgets** (from P644): per footprint, 1,500, 900 and 500 polygons and 128, 80 and
  48 KB per frame; no bolt on a face over 0.25 tile² (ADR 0050 §1).
- **AI marking** (P623): every CREDITS row marked AI-made has the file and frame, the feature,
  the date, the prompt, the hand edits and the screen. No AI-made path is in the reserved scope
  without `assets/LICENSE.md`'s exclusion.
- **Stand-alone art** (P650): text over each backdrop meets 4.5:1 with the theme's scrim token.
  The screens pass at the six sizes with the picture in place. No stand-alone picture is in the
  match atlas.
- **Zoom** (P633, P634):
  - The camera snaps to four levels.
  - The overshoot is bounded at the new last level.
  - The start index is unchanged, and a turn keeps the level.
  - The picker, the minimap and edge pan pass at every level.
  - The gallery's cross-file fact holds.
  - Basics ends at level 2 or 3.
- **Per art batch:**
  - The 32 px greyscale readability check.
  - Silhouettes tell apart in a mirror match.
  - Marker and faction shares are in their bands.
  - The page budget holds.
  - The same-scene check is green, and its sheet is attached to the PR.
- **View only** (P619): the tutorial bot's Basics under the new theme gives the same log and
  hash.
- **Not headless:**
  - The look against the file.
  - The softness at zoom 2.0.
  - The bake time and the HUD's draw calls on the phone's perf card.
  These are Michael's checks in P620 and P649.

## Rows
Line counts are production lines changed (tests, data, theme values and art do not count;
CLAUDE.md). `tools/artgen` code counts.

| Row | Owner | Depends | What | Acceptance (tests) | HOW_TO_PLAY | Prod. lines |
|---|---|---|---|---|---|---|
| P600 | architect | none | **Done (#642).** The plan and ADR 0049 | docs lens | none | 0 |
| P601 | art-director (another lane) | none | **Done as exploration** (`claude/p601-style-proto`, never merged). The reference for ADR 0050 | its own | none | n/a |
| P602 | art-director | none (now) | **The Figma read-out** (ADR 0049 §1 tool rules). `STYLE.md` "Treadline UI look": colours with role, token and hex; type scale; panel, border and corner rules; spacing; the order glyphs. It checks ADR 0049 §3 against every screen and lists differences, screens every name in the file (§2) and says whether the labels use a mono face | docs lens | none | 0 |
| P603 | architect | Michael's answers | **Done (#642).** ADR 0049 accepted; dated notes in ADR 0006, 0023 (§6) and 0025 (§13, §15); rows checked: P605 only if P602 finds a mono face, P606 not run (answer 3 A), P618 kept (answer 7 A) | docs lens | none | 0 |
| P604 | touch-ux-dev | P602; P585 (#641) merged | **Tokens v3.** New values in `HudTokens`, `AccentFossil` (Nordværn orange), `AccentRenew` (Facet blue, the hue of ADR 0050 §3), `HudPanel`, `Menu*` and `GuideTokens` (values only); new tokens from P602. No team-colour change (that is P632) | `test_ui_theme_tokens.gd` (new); the theme scan | none | ~40 |
| P605 | art-director | P604; only if P602 finds a mono face | **The mono label face.** ADR 0025 §13's process; `FontVariation` `MonoLabel` | `test_font_assets.gd`; the licences and notices tests | none | ~20 |
| P607 | gameplay-dev | P603 | **The faction rename.** `FactionDef` display names; the side names from one source; the pause, result and dev labels; `docs/GDD.md` faction names (the lore stays); `HOW_TO_PLAY.md` rows `factions-*`, `menus-main`, `menus-skirmish` and every row that names a side (P607 greps them); `data/help/how_to_play.tres` | the player-text scan; side names equal `FactionDef`; `test_main_menu.gd`, `test_map_select*`, the coverage test | the rows named | ~50 |
| P608 | ai-dev | P607; P594 merged | **The lesson text rename** (`data/tutorial/text_en.tres`) | `test_lesson_data.gd`; `test_tutorial_run.gd`; the scan with no exception | none | data |
| P609 | touch-ux-dev | P604 | **The HUD corners' look** (pill, scope frame, alert toast, BUILD, strike button, group column, economy card). No `HudCorners` change; steady with Reduced effects | `HudCorners` tables unchanged; theme scan; 48 dp and safe area at the six sizes | none | ~120 |
| P610 | touch-ux-dev | P604; P581 (#639) merged | **The command bar's look** (icon over word for every order; P581's sizes kept). New glyphs in a sub-row P610a (art-director, own SVG) | `test_command_bar_stack.gd` unchanged; `test_command_bar*` | none | ~80 |
| P611 | touch-ux-dev | P604; P591 merged | **The build drawer's look**; tile sizes unchanged | `test_build_sidebar*`; `test_item_tile*`; the guide sweep | none | ~80 |
| P612 | touch-ux-dev | P604; P592 merged | **The guide card in the objectives-panel look** (theme values only, no `CoachMark.gd` edit) | `test_guide_blink.gd`'s token cases; the sweep | none | ~10 |
| P613 | touch-ux-dev | P604, P607 | **Main menu tiles**; the backdrop token (P650 adds the Figma-AI backdrop). Menu whites move to the text token. | `test_main_menu.gd` (columns, 48 dp, banner gap); the intro hand-over test | `menus-main` | ~180 |
| P614 | touch-ux-dev | P613 | **The menu frame and Skirmish**. Menu whites move to the text token. | `test_map_select*`, `test_menu_screen*`, `test_settings_screen*` | `menus-skirmish` if its words change | ~160 |
| P615 | touch-ux-dev | P613 | **Loading** (a still `DeployCard`, no ad) | `test_deploy_card*` | none | ~50 |
| P616 | touch-ux-dev | P609 | **Pause** (foot banner rules unchanged) | `test_pause_menu*`; `test_tutorial_host_input.gd` | none | ~80 |
| P617 | touch-ux-dev | P609 | **Victory and defeat** (Double XP by choice, no banner) | `test_result_screen*` | none | ~100 |
| P618 | touch-ux-dev | P609; P595 merged | **Clock and unit count in the pill** (answer 7 A), set on change only, shown when the top row has room | `test_economy_pill*`; `test_hud_corners*`; the sweep; the per-frame counter | **New row** `the-screen-in-battle-clock` and its help entry | ~120 |
| P619 | qa-engineer | P609-P618 | **UI restyle proof**: the size scan in both orientations, the view-only check, screenshots | the named suites | none | 0 (tests) |
| P620 | architect + lead | P619 | **UI phone check and close-out** (skirmish and Basics, both orientations, Reduced effects on and off, HUD draw calls); ADR 0049 implementation note | Michael's yes | none | 0 |
| P621 | architect | P601, Michael's answer | **Done (#642).** ADR 0050 (proposed) | docs lens | none | 0 |
| P621b | architect | Michael's answer 1 | **Done on `claude/p621b-adr0050-accept`.** ADR 0050 accepted ("ja, kør med generator-SVG og Figma AI til menuer"): generator SVG on the map, Figma AI for stand-alone art, the facet form, the building budget. Dated notes in ADR 0023, 0027, 0035 and 0051. P635 and P636 struck, P644 and P645 SVG batches, P630c and P650 added | docs lens | none | 0 |
| P623 | lead (ADR 0051's lane) | #643 merged | **AI-made files outside the reserved scope** (ADR 0051 §4, §5). One line in `assets/LICENSE.md` excludes every file that `assets/CREDITS.md` marks "AI-made with Figma AI, no copyright claimed by AppCode ApS". A test (`tests/project/test_credits_ai_rows.gd`) checks that each such row has the Figma link and frame, the feature, the date, a short prompt, the hand edits and "screened: …", and that every AI-made path sits under the exclusion | the new test; `test_export_notices` unchanged | none | ~10 |
| P629 | art-director | ADR 0050 answers 2-5 (in) | **The same-scene check** (ADR 0050 §8): a headless composer in `tools/artgen` (the bake's SVG loader, PNG decode, `Image` blends) builds the sheet: both factions' units and buildings on the same ground tiles, four zooms, the world grade, a mirror pair, effects, cards and glyphs. `test_same_scene.gd` with the bands in `tools/artgen/same_scene.tres` (outside `data/`). Today's art is the first baseline | the composer runs headless; the bands hold for today's art; a crafted off-light sprite fails | none | ~200 |
| P630 | art-director | ADR 0050 answers 2-5 (in) | **Generator features, no output change** (ADR 0050 §1): face decals, per-primitive detail override, macros (tracks, wheel sets, grilles, hatches, pylons). The batch lists of P638-P647 are fixed in this PR from `assets/art/iso/index.tres` | `--check` byte-identical for every model; `ArtModel.problems` for the new primitives | none | ~300 |
| P630c | art-director | P630 | **Facet primitives, no output change** (ADR 0050 §1, §2): a chamfered (bevelled) box and rotated prisms (n-gon prisms and frustums turned about the vertical axis, sloped faces), so buildings and Facet's wedge hulls get crisp facets. The target is P601's Figma-vector form (`round2/figma_facet_hq_1_0.png`, `scene/scene_b_figma_vector_1_0.png`) in place of the dome (`scene/scene_a_svg_1_0.png`). A test model of that form is committed under `tests/art`, not as game art | `--check` byte-identical for every model; faces and normals of the new primitives; the test model passes P629's bands | none | ~200 |
| P630b | architect + art-director | answer 5 (in) | **`svg-art-style` and STYLE.md text** of ADR 0050 §4 (yes given), plus §8's same-scene rule and §4's decided "Stand-alone pictures" bullet (Michael's yes asked for that bullet) | docs lens | none | 0 |
| P631 | art-director | P630 | **The detail renderer in the generator**, rewritten with P601's `ArtDetail` as reference: per-model `detail` 0-3, hash-seeded, metal sheen gradients from L2 (answer 4) | detail 0 byte-identical; allowed elements per level; gradient ids and no key in a gradient; polygon and 64 KB budgets; `--check` stable at every level | none | ~350 |
| P632 | art-director | P630 | **Fixed faction colours and the team marker, the migration** (ADR 0050 §3): one sentinel key triad; fixed Nordværn and Facet materials; every frame regenerated (hex only); the bake's key table; gallery triads; `TEAM_SHARE` 2-12 % for the transition; `FACTION_SHARE` for detail at least 1; default marker colours (answer 3) in the match routes | the key band against the sentinel; only sentinel hexes in frames; the bake for all eight triads (gradients too); the page within 40 rows; the route default test | none | ~150 |
| P633 | ai-dev | P592, P594 merged | **Zoom in the tutorial** (ADR 0050 §6): Kind 19 `ZOOM_AT_LEAST`; Basics `zoom` uses it with value 2; `problems()` takes the pinch with it; the hint's AUTO rule; "four zoom levels" in the prompt | `test_tutorial_conditions.gd` (Kind 19); `test_lesson_data.gd`; `test_tutorial_run.gd` (ends at level 2 and at 3) | none | ~40 |
| P634 | touch-ux-dev | P633 | **The fourth zoom level** 2.0 (answer 2) appended to `zoom_levels` and the `InputSettings` default; camera, picker, minimap and edge-pan tests over four levels; the gallery zoom row; `test_lift_sheets.gd`'s list. One balance run | `test_input_settings.gd`; the camera suites; `test_minimap.gd`; `test_picker.gd`; `test_placement_edge_pan.gd`; the cross-file fact | `camera-pinch` ("four zoom levels") and its help text | ~30 |
| P635 | — | — | **Struck** (ADR 0050 answer 1: no PNG on the map) | — | — | 0 |
| P636 | — | — | **Struck** (ADR 0050 answer 1) | — | — | 0 |
| P637 | art-director | #643, P601 | **Done** on `claude/p601-style-proto` (6be63003, `docs/proto/p601/README.md` "Round 3 (P637)"): (a) artgen SVG most coherent, (b) Figma vector best silhouette, (c) Figma AI breaks the scene. Not merged | — | none | 0 |
| P638 | art-director | P629, P631, P632 | **Nordværn ground vehicles** at L2 (scout tank, tank, artillery, tanker): fixed panels, marker | per-batch checks | none | art |
| P639 | art-director | P638, P630c | **Facet ground vehicles** at L2 | per-batch checks | none | art |
| P640 | art-director | P639 | **Nordværn squads** (all infantry, poses) | per-batch checks | none | art |
| P641 | art-director | P640 | **Facet squads** | per-batch checks | none | art |
| P642 | art-director | P641 | **Nordværn support and air** (carrier, minelayer, aircraft) | per-batch checks | none | art |
| P643 | art-director | P642 | **Facet support and air** | per-batch checks | none | art |
| P644 | art-director | P643, P630c | **Nordværn 3x3 buildings** (all six) at SVG L2 with L3 bevels, the building budget and the marker plate in the frame; P601's 404 KB works frame is the case to bring under 128 KB | per-batch checks; the building budgets | none | art |
| P645 | art-director | P644 | **Facet 3x3 buildings** (all six), the headquarters first, rebuilt to the faceted form of P630c's target and passed through P629's check beside the round-3 scene | per-batch checks; the building budgets | none | art |
| P646 | art-director | P645 (one page-pin PR at a time) | **Nordværn 2x2 and 1x1 buildings** at SVG L2 without bolts | per-batch checks | none | art |
| P647 | art-director | P646 | **Facet 2x2 and 1x1 buildings**; the last batch to merge narrows `TEAM_SHARE` to 2-6 % | per-batch checks; the narrowed band | none | art |
| P650 | art-director | P623; P604; P613, P614, P615 | **Figma-AI stand-alone art** (ADR 0050 §2, ADR 0051): the main-menu backdrop, the loading backdrop (`DeployCard`) and one hero portrait per faction for the side cards (main menu, map select), in both orientations' crops. Each PNG has its CREDITS row ("AI-made with Figma AI, no copyright claimed by AppCode ApS"; file and frame, feature, date, the prompt, hand edits) and its resemblance screen recorded. The token check: text over the picture meets 4.5:1 with a theme scrim token, the hue sits with the accents, no detail fights the HUD. The pictures are wired by theme or data reference, never a path literal in code. No picture on the map | P623's test; `test_main_menu.gd`, `test_map_select*`, `test_deploy_card*` at the six sizes with the pictures; the contrast check | none | ~60 |
| P648 | qa-engineer | P634, P647, P645 | **Art proof**: the page budgets, readability over all rosters, mirror matches, zoom at four levels, CI's `atlas_bake_ms` against twice today's | the named suites | none | 0 (tests) |
| P649 | architect + lead | P648 | **Art phone check and close-out**: Michael plays a cross and a mirror match, zooms to 2.0, reads the bake time; ADR 0050 implementation note; memory | Michael's yes | none | 0 |

### Waves, lanes and the critical path
- **Done:** P600, P603, P621 (#642), P621b (this branch), P601 and P637 (prototype branch, not
  merged). Guide v2's P585, P586 and P587 are on `main`; P581 (#639) is open.
- **Can start right now, each in a free lane:**
  - P602 (art-director, lane F).
  - P607 (gameplay-dev, lane N).
  - P623 (the lead, ADR 0051's lane).
  - P629 and P630, then P630b (art-director, lane G; P629 and P630 touch different files, so
    one agent each).
- **Blocked now:**
  - P604 waits for P602. Then lane H (touch-ux-dev): P609, P610 (after P581), P616, P617, and
    P611, P612 and P618 as guide v2's P591, P592 and P595 open.
  - Lane M (touch-ux-dev): P613 (after P604 and P607), P614, P615.
  - P633 (ai-dev) waits for P592 and P594, then P634 (lane H).
  - P608 waits for P594.
  - P650 (lane F) waits for P623 and the restyled menus (P604, P613-P615).
- **Art lane G (art-director):**
  1. P629 and P630.
  2. Then P630c, P631 and P632, in parallel. They touch primitives, the renderer and the
     palette and frames; verify the combined tree.
  3. Then the batches in series (one page-pin PR at a time): P638 to P643, P644, P645, P646,
     P647.
- **Close-out:** P619 then P620 (UI); P648 then P649 (art).
- **Critical paths:**
  - Art, the longest: P630 → P631 → P638 → P639 → … → P643 → P644 → P645 → P646 → P647 →
    P648 → P649. That is 15 rows, all in lane G's series, because each batch moves the page pins.
  - UI: P602 → P604 → P609 → P618 → P619 → P620, gated by guide v2's P595.
  - Menus art: P623 and P602 → P604 → P613 → P614 → P615 → P650.
- **Shared pins:** every art batch moves `tests/view/test_iso_atlas_budget.gd`'s page pins.
  `theme.tres` goes one open PR per lane, in disjoint type blocks (H: `Hud*`, `Order*`, `Item*`,
  `Guide*`; M: `Menu*`; P650 adds only its scrim token and references, after P615), with a
  combined-tree verify before the second merge.
- **Guide v2 rules held:**
  - No `HudCorners` geometry before P595 (P618 is the only geometry row).
  - No `CoachMark.gd` edit except P633's hint rule, after P592.
  - Lesson data only after P594 (P608, P633).
- **HOW_TO_PLAY owners:**
  - `menus-main` and `menus-skirmish`: P607, then P613 and P614.
  - Every side-naming row: P607.
  - `the-screen-in-battle-clock`: P618.
  - `camera-pinch`: P634.
  - Guide lane T1 keeps `menus-tutorial-guide`, `menus-tutorial`, `menus-tutorial-end` and
    `menus-settings`.

## Risks
1. **The read-out was not done by the architect** (no Figma tools in that session). P602 checks
   ADR 0049 §3 and lists differences before P604.
2. **A mixed look** (Michael: "helhed … ikke tilfældigt", one whole, not random). The map has
   one source (generator SVG), and every art PR carries the same-scene check. The Figma-AI
   menu pictures stand alone and pass the token check. Their risks are a look close to another
   game and no copyright claim (ADR 0051 §5); the resemblance screen lowers the first.
   **Building weight:** P601's Nordværn works frame is 404 KB. The budget (128 KB) and the
   no-bolts-on-big-walls rule bring it down, and P644 proves it on that very building.
3. **The bake time grows** with L2 units (about 2 to 3 times). The budget is twice today's on the
   phone (P648 and P649). Levers in order: L1 for far parts, then 8 vehicle directions.
4. **Softness at zoom 2.0** is accepted by design, and Michael judges it in P649. The only lever,
   `bake_scale` 1.1, costs about 18 MB and the free page rows (ADR 0050 §6).
5. **The transition look.** Between P632 and the last batch, old models show today's team bands
   beside remodelled units with fixed panels. This is acceptable on `main`, and no store build
   depends on it.
6. **The page pins** are edited by every batch, so the batches run in series.
7. **`theme.tres` friction** between lanes H and M and the guide's P585: disjoint blocks and a
   combined-tree verify.
8. **Draw calls:** one UI texture at most. Building markers ride the same page, so they add no
   call.
9. **Scope creep** from the file. ADR 0049 §4 names each item. New asks go to the follow-up list.
10. **The bands of the same-scene check** may be too loose to catch a mismatch, or too tight
    for real variety. P629 sets them from today's art, and Michael's eye on each sheet is the
    final check. Band changes go through the review.

## Michael's answers
- **ADR 0049** (2026-11-24, "A, SVG til enheder …, faste farver, Facet …", then "ja til
  resten"):
  - 1 A, 2 Facet, 3 A, 4 A.
  - 5 superseded by fixed faction colours with a team marker.
  - 6 no mono face unless the file uses one.
  - 7 A.
  - 8 yes: Michael runs the free searches.
- **ADR 0050** (2026-11-24, "ja til alle 4, men vi skal have afgjort om det er figma Ai der
  vinder, vi skal have en helhed i grafikken hele vejen rundt så det virker gennemarbejdet og
  ikke tilfældigt"):
  - 2: zoom 2.0, appended, soft past 1.5.
  - 3: markers own white and computer red, with a dark rim.
  - 4: gradient sheen.
  - 5: the `svg-art-style` text.
  - 1 (after P637): "ja, kør med generator-SVG og Figma AI til menuer". Generator SVG for
    everything on the map; Figma AI for stand-alone art.
  - The principle of one coherent look, the same-scene check (§8).
