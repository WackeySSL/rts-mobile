# Plan: the Treadline restyle (UI look, faction rename, art direction)

Date: 2026-11-24. Base: `main` at 52b2649e. Author: architect, row P600, on branch
`claude/p600-treadline-plan`. Decision: `docs/adr/0049-treadline-restyle.md` (**proposed**; it is
accepted in row P603 with Michael's answers). ROADMAP: no checkbox. The restyle improves finished
Phase 5 screens and adds no acceptance criterion. Phase 7's trademark box gains the new names
(P603's note). No code row starts before P603.

## Goal
Michael's decisions of 2026-11-24:
1. Restyle the look toward his Figma file (`HsBPSXZ6PTRp6KkdhEi6bT`), starting with the UI: the
   battle HUD, the menus, loading, pause, victory and the build drawer, in both orientations.
2. Rename the factions: **Nordværn** (orange, today's Derrick League, id `fossil`) and **Helix**
   (blue, today's Lumen Accord, id `renew`). The title Treadline stays (ADR 0006). The text stays
   English.
3. Define the target art look in words and pick the art pipeline after P601's prototype.

Scope guard. Not in this plan:
- Campaign, multiplayer, the unit-details screen.
- A radio or subtitle feed.
- Move, Attack, Guard or Patrol buttons.
- A landscape layout like the file's (unless question 1 is B, and then in a later plan).
- New unit or building art (it comes after P621).
- Translations.
- Any change to the sim's rules.

These go to the lead's follow-up list if a row asks for them.

## Affected modules
| Area | Files (main ones) | Rows |
|---|---|---|
| Theme and fonts | `game/ui/theme.tres`; `assets/art/fonts/<mono>/` (only if question 6 is B); `assets/CREDITS.md`, `LicenceCatalog.gd`, the export notices | P604, P605, P609-P617 |
| Battle HUD (look only) | `EconomyPill.gd`, `RadarScope.gd`, `AttackToast.gd`, `BuildButton.gd`, `StrikeButton.gd`, `GroupColumn.gd`, `EconomyCard.gd`, `CommandBar.gd` and `OrderFlow` (P581), `BuildSidebar.gd`, `ItemTile.gd` | P609-P611 |
| Top row (geometry) | `EconomyPill.gd`, `HudCorners.gd` (the pill's width only) | P618 |
| Menus | `MainMenu.gd`, `MenuScreen.gd`, `MapSelect.gd`, `DeployCard.gd`, `PauseMenu.gd`, `ResultScreen.gd` | P613-P617 |
| Names | `data/factions/*.tres`, `MainMenuText.gd`, `MapSelectText.gd` (side names read from `FactionDef`), `data/help/how_to_play.tres`, `data/tutorial/text_en.tres`; `data/units/*.tres` only if question 3 is B | P607, P608 |
| Sim (conditional) | `game/sim/WorldHash.gd` (`defs_hash` skips `type_names`); golden pairs | P606 |
| Route colour | the side-to-triad choice of the menu routes (`WorldSort.TRIADS` index for Helix) | P604 |
| Docs | ADR 0049; dated notes in ADR 0025, 0023 and 0006; `docs/GDD.md`, `docs/HOW_TO_PLAY.md`, `assets/art/STYLE.md` ("Treadline UI look") | P602, P603, P607, P620 |

Nothing in `game/ai`, `game/core` or `native/`. `game/sim` is touched only by P606, and only if
question 3 is B. The rows that touch `data/factions/` or `data/units/` start one balance run
(`balance.yml` paths). Those changes are written in one row (P607). `data/tutorial/**` and
`data/help/**` do not start one.

## Command and data changes
- **Commands:** none. `STATE_FORMAT` is unchanged.
- **Data:**
  - `FactionDef.display_name`: "Nordværn" and "Helix", or the name from answer 2.
  - `UnitDef.display_name` only if question 3 is B.
  - The help and lesson tables change values only. New keys `menu.side.fossil` and
    `menu.side.renew` replace the hard-coded `SIDE_FOSSIL` and `SIDE_RENEW`, or the menus read
    `FactionDef`; P607 picks one and tests it.
- **Theme:**
  - New values for `HudTokens`, `AccentFossil`, `AccentRenew`, `Menu*` and `GuideTokens`.
  - New tokens if P602 finds them (expected: `line`, `panel_raised`, `text_dim` and `stripe`).
  - A `FontVariation` `MonoLabel` (only if question 6 is B).
  - No type is renamed.
- **Hash:** the defs hash moves once, in P606, and only if question 3 is B (ADR 0049 §6).

## Test plan (what is proven headless)
- **Tokens** (`tests/ui/test_ui_theme_tokens.gd`, new in P604):
  - Every token resolves.
  - Each accent is at least 15° in hue from danger and from money.
  - Text on the accent has a contrast of 4.5:1 or more.
  - `test_ui_theme_scan.gd` still finds no colour or font outside the theme.
- **Fonts** (P605, only if question 6 is B):
  - `test_font_assets.gd` covers the mono face (æøåäöüßÆØÅÄÖÜ).
  - The Licences screen and the export notices list it.
- **Geometry unchanged** (P609-P617): `HudCorners`' pinned tables, P581's
  `test_command_bar_stack.gd`, the guide sweep, `test_build_sidebar*` and the menu suites all pass
  at the six sizes and both orientations, with no edit to their expected rects.
- **Menus:**
  - Main menu tiles: two columns only where the measured width allows, and at least 48 dp.
  - The start banner keeps its 48 dp of air.
  - The pause foot banner is at least 16 dp away and upright only.
  - The result and deploy screens carry no ad slot.
- **Rename** (P607, P608):
  - A scan finds no "Derrick League" or "Lumen Accord" in player-facing text (`data/help`,
    `data/tutorial`, `data/factions`, the `*Text.gd` tables).
  - The menu side names equal `FactionDef.display_name` in upper case.
  - `test_how_to_play_coverage.gd` and `test_lesson_data.gd` stay green.
- **Hash** (P606, only if question 3 is B):
  - Changing a `display_name` keeps `defs_hash`.
  - Changing a cost, a speed or an id changes it.
  - The golden pairs and the smoke hashes are re-pinned in that row.
- **Clock and count** (P618):
  - The label changes once a second and on a count change, never per frame (a counter in the
    test).
  - The pill fits the top row at the six sizes, or the clock and count go.
  - The guide sweep is green.
- **View only** (P619): the tutorial bot's Basics under the new theme gives the same command log
  and state hash as before.
- **Not headless:**
  - How close the look is to the file.
  - Whether it reads well on the phone.
  - The HUD's draw calls on the phone's perf card (at most 4 over today, ADR 0049 §9).
  These are Michael's check in P620.

## Rows
Line counts are production lines changed (tests, data, theme values and art do not count;
CLAUDE.md).

| Row | Owner | Depends | What | Acceptance (tests) | HOW_TO_PLAY | Prod. lines |
|---|---|---|---|---|---|---|
| P600 | architect | none | **Done on this branch.** This plan and ADR 0049 (proposed) | docs lens | none | 0 |
| P601 | art-director (another lane) | none | **Running.** One prototype unit and one prototype building in the new style. Its content is planned there. It feeds P621 with measured costs: SVG bytes, bake ms, page rows, a phone screenshot | its own | none | n/a |
| P602 | art-director | none (it can run now) | **The Figma read-out** (ADR 0049 §1 tool rules: base64 screenshots of at most 1000 px, kept in the scratchpad only; no asset URL fetched; no generated code pasted). Writes `assets/art/STYLE.md` "Treadline UI look": each colour with its role, its theme token and its hex; the type scale; the panel, border and corner rules; the spacing; the order glyphs the file shows. It checks ADR 0049 §3's table against every screen in both orientations and lists the differences. It lists every name in the file (screens and the four art sheets) as clear, risky or blocked, with the reason (ADR 0049 §2). It reports whether the labels use a mono face (question 6). It computes the accent checks for the file's orange and blue | docs lens | none | 0 |
| P603 | architect | Michael's answers, P602 | **Acceptance.** ADR 0049 status and answers. Dated notes: ADR 0025 §13 and §15, ADR 0023 §6, ADR 0006 (the trademark note names the new factions), and ADR 0032 if names change. The rows are checked against the answers (drop P605 if 6 is A, P606 if 3 is A, P618 if 7 is B) | docs lens; `tests/project` doc tests | none | 0 |
| P604 | touch-ux-dev | P603; P585 (#641) merged | **Tokens v3.** The new values in `HudTokens`, `AccentFossil` (Nordværn orange), `AccentRenew` (Helix blue), `HudPanel`, the `Menu*` styles and `GuideTokens` (values only); new tokens from P602; Helix's default triad from the cyan to the blue (answer 5) where the routes pick the side's colour | `test_ui_theme_tokens.gd` (new); `test_ui_theme_scan.gd`; the route test for the side's triad | none | ~40 |
| P605 | art-director | P604 (only if answer 6 is B) | **The mono label face.** Unmodified upstream file and `OFL.txt` under `assets/art/fonts/<family>/`, a CREDITS row, `LicenceCatalog` and the export notices; `FontVariation` `MonoLabel` in the theme; web size reported in the PR | `test_font_assets.gd` (glyphs); the licences and notices tests | none | ~20 |
| P606 | gameplay-dev | P603 (only if answer 3 is B) | **Names leave the defs hash** (ADR 0049 §6). `WorldHash.defs_hash` skips `type_names` (and any other name table it feeds); golden pairs and smoke hashes re-pinned once; at most about 10 mutants | `test_world_hash.gd` (a name change keeps the hash, a cost or an id change moves it); the perf goldens; the smoke | none | ~10 |
| P607 | gameplay-dev | P603; P606 if answer 3 is B | **The rename, data and text.** `FactionDef` display names; the menus' side names from one source; the pause, result and dev labels; unit and building names only by answer 3; `docs/GDD.md` (factions, lore by answer 4, the name tables); `docs/HOW_TO_PLAY.md` rows `factions-*`, `menus-main`, `menus-skirmish` and every other row that names a side (`units-*`, `buildings-*`, `build-menu-*`, `superweapon-*`; P607 greps them), and `data/help/how_to_play.tres` | the player-text scan; the side names equal `FactionDef` in upper case; `test_main_menu.gd`, `test_map_select*`, `test_how_to_play_coverage.gd` | the rows named | ~50 |
| P608 | ai-dev | P607; P594 merged | **The lesson text rename.** `data/tutorial/text_en.tres` and any prompt that names a side or a renamed unit | `test_lesson_data.gd`; `test_tutorial_run.gd`; the player-text scan now with no exception | none | data |
| P609 | touch-ux-dev | P604 | **The HUD corners' look.** `HudPanel`, the pill, the scope's frame, the attack toast (the file's alert line), BUILD, the strike button, the group column, the economy card: theme styles and code that reads tokens. No `HudCorners` change. Anything animated is steady with Reduced effects | `HudCorners` tables unchanged; the theme scan; the 48 dp and safe-area checks at the six sizes; the reduced cases | none | ~120 |
| P610 | touch-ux-dev | P604; P581 (#639) merged | **The command bar's look.** The icon-over-word style for every order (CLEAR, STOP, HOME, REPAIR, BOARD, UNLOAD, MINE, MEND, SELL); lit, dim and warn states from the theme; P581's sizes kept. New glyphs, if P602 lists any, are art-director's own SVGs in a sub-row P610a | `test_command_bar_stack.gd` unchanged and green; `test_command_bar*`; the theme scan | none | ~80 |
| P611 | touch-ux-dev | P604; P591 merged | **The build drawer's look** (the file's production screen). Panel, tabs, `ItemTile`, ADR 0032's sash, the queue row; tile sizes unchanged | `test_build_sidebar*`; `test_item_tile*`; the guide sweep green | none | ~80 |
| P612 | touch-ux-dev | P604; P592 merged | **The guide card in the objectives-panel look.** `GuideTokens` and the guide card's theme styles (values only). No `CoachMark.gd` edit | `test_guide_blink.gd`'s token cases; the guide sweep green | none | ~10 |
| P613 | touch-ux-dev | P604, P607 | **Main menu tiles.** Icon and word tiles, two columns where the measured width allows, else one; the title in the new type; the backdrop token the intro's open-out meets; no Campaign or Multiplayer; the banner's 48 dp kept | `test_main_menu.gd` at the six sizes (column rule, 48 dp, banner gap); the intro's hand-over test | `menus-main` (tiles) | ~180 |
| P614 | touch-ux-dev | P613 | **The menu frame and Skirmish.** `MenuScreen`'s header and back bar; `MapSelect` cards, side and level chips, Start, the offer slot; Settings, How to play and Licences take the frame | `test_map_select*`, `test_menu_screen*`, `test_settings_screen*` at the six sizes; offer by choice only | `menus-skirmish` if its words change | ~160 |
| P615 | touch-ux-dev | P613 | **Loading.** `DeployCard` in the new look, still: no bar, no spinner, no ad | `test_deploy_card*` at the six sizes | none | ~50 |
| P616 | touch-ux-dev | P609 | **Pause.** `PauseMenu`'s card, buttons and chips in the new look; the foot banner rules unchanged | `test_pause_menu*` (six sizes; banner upright only, at least 16 dp, none when it scrolls); `test_tutorial_host_input.gd` | none | ~80 |
| P617 | touch-ux-dev | P609 | **Victory and defeat.** `ResultScreen`'s emblem, word, stats and buttons in the new look; Double XP by choice; no banner | `test_result_screen*` at the six sizes; no ad slot | none | ~100 |
| P618 | touch-ux-dev | P609; P595 merged (only if answer 7 is A) | **Clock and unit count in the pill.** Match time from the snapshot's tick and the own unit count, shown when the top row has room (measured); the label is set on change only; `HudCorners`' pill width; the guide dock re-checked | `test_economy_pill*`; `test_hud_corners*`; the guide sweep; the per-frame counter | **New row** `the-screen-in-battle-clock` in "The screen in battle", and its help entry | ~120 |
| P619 | qa-engineer | P609-P618 | **Restyle proof.** The screen-size scan covers every restyled suite in both orientations; the view-only check (Basics: same log and hash); screenshots at the six sizes for the PR | the named suites | none | 0 (tests) |
| P620 | architect + lead | P619 | **Phone check and close-out.** Michael plays a skirmish and Basics, upright and sideways, with Reduced effects on and off, and reads the HUD's draw calls on the perf card. ADR 0049 implementation note; STYLE.md and `touch-ui-rules` notes (with Michael's yes); memory | Michael's yes; docs lens | none | 0 |
| P621 | architect | P601; Michael's look at it | **The art pipeline decision.** ADR 0050: option A, B or C of ADR 0049 §7, with P601's measured costs; then an art plan for the rosters | docs lens | none | 0 |

### Waves, lanes and the critical path
- **Wave 0:** P600 (this branch) and P601 (running).
- **Wave 1, now:** P602 (art-director, lane F). It is read-only on the file and writes docs only,
  so it waits for no guide row. Michael answers ADR 0049 with P602's name list in hand.
- **Wave 2:** P603.
- **Wave 3:**
  - P604 (lane H, touch-ux-dev), as soon as P585 (#641) is on `main`.
  - P606 then P607 (lane N, gameplay-dev). P606 runs only if answer 3 is B.
- **Wave 4, in parallel:**
  - P609 (lane H).
  - P613 (lane M, touch-ux-dev, after P607).
  - P605 (lane F, if answer 6 is B).
- **Wave 5:**
  - Lane H: P610 (after P581), P616, P617, in series.
  - Lane M: P614, then P615.
- **Gated by guide v2:**
  - P611 after P591.
  - P612 after P592.
  - P608 (lane A, ai-dev) after P594.
  - P618 after P595.
  Each joins lane H in that order when its gate opens.
- **Wave 6:** P619, then P620.
- **Any time after P601 and Michael's look:** P621.
- **Critical path:** P602 → P603 → P604 → P609 → P618 → P619 → P620. Its length is set by guide
  v2's lane T1: P618 cannot start before P595, which ends T1's series (P585, P588, P589, P591,
  P592, P594, P595). Every other restyle row runs beside it.
- **`theme.tres`:** lanes H and M both edit it, in disjoint type blocks (H: `Hud*`, `Order*`,
  `Item*`, `Guide*`; M: `Menu*`). At most one open PR per lane edits it. Before the second of two
  PRs waiting on the same merge goes in, verify their combined tree once (CLAUDE.md).
- **Same-system interaction reviews:** none. No two restyle rows in one wave touch the same
  component, and guide rows touch the theme only in P585.
- **HOW_TO_PLAY:** the restyle rows own `menus-main` (P607, then P613, in series), `menus-skirmish`
  (P607, then P614), `factions-*`, every other side-naming row (P607) and
  `the-screen-in-battle-clock` (P618). Guide lane T1 owns `menus-tutorial-guide`, `menus-tutorial`,
  `menus-tutorial-end` and `menus-settings`.

## Risks
1. **"Helix" is a C&C unit name** (Generals: Zero Hour). Answer 2 settles it. If kept, the Phase 7
   trademark search must say it is safe before release. A later rename is cheap: a faction name is
   not hashed.
2. **The read-out was not done by the architect** (no Figma tools in this session). ADR 0049 §3's
   table comes from the lead's read-out. P602 checks it and lists the differences, and P603 folds
   them in before any code row.
3. **The look of the file depends on its renders.** A UI tuned against photo-like pictures can look
   empty over our flat art until P621's art lands. P620 judges the HUD over today's art. Token
   values can be tuned later without code.
4. **`theme.tres` merge friction** between lanes H and M and the guide's P585. Disjoint type
   blocks, one open PR per lane and a combined-tree verify keep it small.
5. **The accent change shifts team colours.** Helix in blue moves units off cyan. The fog
   (dark blue-grey, ADR 0035) and water may read closer to blue. P604's checks cover the HUD.
   The world look is in P620's phone check, and the triad is one data value to revert.
6. **Draw calls.** Stripes and frames as textures could break HUD batches. One UI texture at most
   and flat boxes elsewhere, with P620's phone reading (at most 4 over today).
7. **Scope creep** from the file: the radio line, objectives, Train, Guard and Patrol, unit
   details, campaign. ADR 0049 §4 names each. New asks go to the follow-up list.
8. **Art pipeline B** needs a pinned renderer in CI and in sessions. If chosen, its install script
   is the first row of the art plan. Until it exists, a row that needs it says what is missing and
   stops.

## Michael's answers
Pending (ADR 0049, "Questions for Michael"). P603 records them here.
