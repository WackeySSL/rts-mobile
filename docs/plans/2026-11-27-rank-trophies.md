# Plan: Rank screen trophies and progress

Date: 2026-11-27. Author: architect. Row P673 is on branch `claude/p673-rank-trophies-plan` (base
`main` at 5657700e).

Decision: `docs/adr/0054-trophies-and-career-stats.md`, **proposed**. Its questions are below.

It builds on:
- ADR 0042 (save), ADR 0044 (tutorial section), ADR 0045 (rank, XP, `MatchSummary`).
- ADR 0052 (menu look) and ADR 0015 (portrait and landscape).
- Row P664: the `RankScreen` with the rank insignia, "RANK n NAME", the XP bar, NEXT UNLOCK, BACK
  and the `_add_section()` seam. It is in progress and not planned here.
- Row P670: the result look and its unlock card, in progress.
- Lane P672b: touch-drag scrolling on menu pages.

## Goal
Michael, 2026-11-27 (translated): "The commander/rank square takes far too much room on the front
page. Make a separate ranking menu, if it matters that much, where you can see your trophies and
how far you have come in the game."

Two new sections on the Rank screen:
- **A. Trophies.** Earned once and kept. Earned ones are lit and marked EARNED; unearned ones are
  dim and say how to earn them.
- **B. Progress.** How far the player has come.

Plus one "TROPHY EARNED" line on the result screen.

ROADMAP: no checkbox. This extends Phase 5's finished meta. The GDD gets a dated note when
ADR 0054 is accepted.

Scope guard. Not in this plan; these go to the lead's follow-up list:
- Dates on trophies (ADR 0042 §4 allows no clock).
- A NEW badge or a "seen" state.
- Sharing.
- Google Play Games achievements.
- Per-unit statistics and a win-rate chart.
- Trophy rewards (question 2).
- Translations.
- A trophy toast during a match or a lesson.

## Trophy proposal
16 trophies, in display order (catalog order, never earn order).

"Exists today" means the game can know the stat now:
- **yes**: it is saved, or it is in `MatchSummary`.
- **snapshot**: it is in the last `MatchSnapshot` or the setup, but not yet in `MatchSummary`.
  Row P673b copies it.
- **new counter**: nothing records it. The `career` section adds it (P673c).

Abbreviations in the table:
- `ORDER`: `TutorialStart.ORDER`, which is basics, strikes, air and support.
- `hq_type_ids`: `headquarters` (Ironward's Rigworks) and `renew_hq` (Facet's Grid Hub).
- `MapCatalog`: the three maps `kestrel_flats`, `map_2` and `map_3`.

| # | id | Name | How to earn it (the hint text) | Stat it needs | Exists today? |
| --- | --- | --- | --- | --- | --- |
| 1 | `briefed` | Briefed | Finish the Basics lesson | `tutorial.done` has `basics` | yes (save `tutorial`) |
| 2 | `fully_drilled` | Fully Drilled | Finish every tutorial lesson | `tutorial.done` holds all of `ORDER` | yes (save `tutorial`) |
| 3 | `first_sortie` | First Sortie | Finish a skirmish, win or lose | `career.finished` >= 1 | new counter. Back-fill: `progress.next_award_id - 1` |
| 4 | `ground_won` | Ground Won | Win a skirmish | `career.wins` >= 1 | new counter |
| 5 | `warm_up` | Warm-Up | Win a skirmish on Easy | `career.wins_grid[*][easy]` | new counter. The level is in `MatchSummary.level` (yes) |
| 6 | `even_footing` | Even Footing | Win a skirmish on Normal | `career.wins_grid[*][normal]` | new counter |
| 7 | `iron_nerve` | Iron Nerve | Win a skirmish on Hard | `career.wins_grid[*][hard]` | new counter |
| 8 | `ironward_honours` | Ironward Honours | Win a skirmish as Ironward | `career.wins_faction[fossil]` | new counter. Faction: snapshot (`MatchSetup.scenario().factions[seat]`) |
| 9 | `facet_honours` | Facet Honours | Win a skirmish as Facet | `career.wins_faction[renew]` | new counter. Faction: snapshot (as above) |
| 10 | `flats_fords_crags` | Flats, Fords, Crags | Win on Kestrel Flats, Heron Fords and Curlew Crags | `career.wins_grid[map][*]` for every map in `MapCatalog` | new counter. The map is in `MatchSummary.map_id` (yes) |
| 11 | `no_easy_ground` | No Easy Ground | Win on Hard on all three maps | `career.wins_grid[map][hard]` for every map | new counter |
| 12 | `short_work` | Short Work | Win on Normal or Hard in under 10 minutes | this match: win, level in [normal, hard], `ticks` <= 9000 (data) | yes (`MatchSummary.ticks`, `.level`) |
| 13 | `unbroken` | Unbroken | Win on Normal or Hard without losing your Headquarters | this match: win, level in [normal, hard], a `hq_type_ids` row still stands | snapshot (rows at the end). It becomes `MatchSummary.standing_types` |
| 14 | `clean_sheet` | Clean Sheet | Win without losing a single building | this match: win, `lost_buildings` == 0 (sold buildings are no loss) | snapshot (`stat_lost_buildings[side]`). It becomes `MatchSummary.lost_buildings` |
| 15 | `seasoned` | Seasoned | Win 10 skirmishes | `career.wins` >= 10 | new counter |
| 16 | `long_haul` | Long Haul | Finish 25 skirmishes | `career.finished` >= 25 | new counter. Back-fill: `progress.next_award_id - 1` |

Coverage of the request:
- First steps: 1, 3, 4.
- Wins per level: 5, 6, 7.
- Wins per faction: 8, 9.
- Map coverage: 10, 11.
- Tutorial lessons: 1, 2.
- Skill: 11, 12, 13, 14.
- Staying power: 15, 16.

The kinds (ADR 0054 §2):
- `LESSONS`: 1, 2.
- `COUNT`: 3, 4, 8, 9, 15, 16.
- `WIN_GRID`: 5, 6, 7, 10, 11.
- `MATCH`: 12, 13, 14.

The numbers 10 minutes, 10 wins and 25 matches live in `data/meta/trophies.tres`.

Names: our own words, after a check that none is a faction, unit or title of another game (Legal).
They go on Phase 7's trademark screening list with the rank titles. I avoided "First Order" (a film
faction) and "Blitz". Kestrel, Heron and Curlew are our own map names.

Counter trophies show their progress in the hint, e.g. "Win 10 skirmishes (7/10)".

### Where the missing stats come from
The sim publishes snapshots. The view and the UI never reach into the sim. Nothing here adds a
sim field.

| Stat | Source | Added in |
| --- | --- | --- |
| `MatchSummary.faction` | `MenuFlow._on_match_ended` passes `_setup.scenario().factions[_local_seat()].id` (data that exists) | P673b |
| `MatchSummary.built`, `lost_units`, `lost_buildings`, `harvested` | `from_snapshot` copies `snapshot.stat_*[side]`, the same numbers the result screen shows | P673b |
| `MatchSummary.standing_types` | `from_snapshot`: one pass over the end snapshot's rows (`owner == side`, `hp > 0`) and the distinct `type_ids[type_index]`. It runs once per match end, never per tick | P673b |
| `career.*` (finished, wins, `play_ticks`, `best_win_ticks`, `wins_grid`, `wins_faction`, `earned`) | `CareerStats.record(summary)` inside `Progression.award_match` | P673c |

`built` and `harvested` are copied because they cost nothing. No trophy reads them yet. They stay
out of the career until a trophy needs them.

### Icons (art)
The cheapest look that reads at 48 dp:
- **The frame.** One drawn badge frame, a flat-topped hexagon outline with a fill, drawn in code
  by a `TrophyBadge` Control. This is the same approach as ADR 0052's drawn `RankInsignia`, so it
  needs no picture.
  - Lit: filled with the `money` token, the glyph in `ground`.
  - Dim: an outline only, in `muted`, the glyph in `muted`.
- **The pips.** 0 to 3 small drawn pips under the glyph mark the level (Easy 1, Normal 2, Hard 3).
- **The glyph.** One glyph SVG from the existing icon set inside each frame:

| Trophy | Glyph | Art status |
| --- | --- | --- |
| Briefed | `tab_infantry` | exists |
| Fully Drilled | `glyph_check` | exists |
| First Sortie | `glyph_resume` | exists |
| Ground Won | `glyph_victory` | exists |
| Warm-Up, Even Footing, Iron Nerve | `glyph_victory` + 1, 2, 3 pips | exists |
| Ironward Honours | `emblem_fossil` | exists |
| Facet Honours | `emblem_renew` | exists |
| Flats, Fords, Crags | `glyph_map` | **new** |
| No Easy Ground | `glyph_map` + 3 pips | **new** (same file) |
| Short Work | `glyph_time` | **new** |
| Unbroken | `glyph_home` | exists |
| Clean Sheet | `tab_structures` | exists |
| Seasoned | `glyph_all_army` | exists |
| Long Haul | `glyph_restart` | exists |

New art: two hand-written SVG glyphs in the HUD glyphs' greys, each with its `assets/CREDITS.md`
row (P673g):
- `glyph_map`: a folded map with a route line.
- `glyph_time`: an hourglass.

No Figma AI, no artgen.

## Progress section
What it shows, and why:

| Line | Example | Source | Why |
| --- | --- | --- | --- |
| Skirmish wins grid: the maps as rows, Easy, Normal and Hard as columns. Each cell holds the number of wins, or "-" for none. A locked map or level shows the lock glyph and "R4" | `Kestrel Flats  3  1  -` | `career.wins_grid`, `MapCatalog`, the level ids, `Progression.is_unlocked` | This is the one picture of "how far": what is won, what is left, what is locked. 9 cells, about 4 lines |
| Lessons | `LESSONS  3 / 4` | `TutorialDirector.lessons_done()` and `TutorialStart.ORDER` | It costs nothing and matches the Tutorial screen's DONE marks |
| Matches | `MATCHES 12 · WINS 7 · TIME 2 h 05 min` | `career.finished`, `wins`, `play_ticks` / 15 | The three numbers Michael named. Integer math, no float |
| Fastest win | `FASTEST WIN 9:12` | `career.best_win_ticks` | One int, and it gives Short Work's target a number |
| Trophies | the Trophies section's heading, `TROPHIES 5 / 16` | `Progression.earned_count()` and the catalog size | |

Not shown:
- **"Units and buildings unlocked out of the total."** The game has no rank unlocks for units or
  buildings. ADR 0045 §4 locks only maps and levels, and the tech tree opens in each match. A
  count would be invented. The open maps and levels show in the grid's lock marks, and the next
  unlock is already on P664's rank block. So there is no separate line.
- A win rate and per-unit statistics. Each needs more counters for little meaning.

Back-filled numbers:
- MATCHES is exact for old saves: `next_award_id - 1`.
- WINS, TIME, FASTEST WIN and the grid count from the update on (ADR 0054 §5).
- No caveat text is shown. The game is not released, and only Michael's and the testers' saves
  are concerned.

## Affected modules
| Area | Files | Rows |
| --- | --- | --- |
| Trophy data | new `game/meta/TrophyDef.gd`, `game/meta/TrophyCatalog.gd`, `data/meta/trophies.tres` | P673a |
| Match summary | `game/meta/MatchSummary.gd`; `game/ui/menu/menu_flow_service.gd` (one argument in `_on_match_ended`) | P673b |
| Career and the check | new `game/meta/CareerStats.gd`, `game/meta/TrophyRules.gd`; `game/meta/progression_service.gd`, `game/meta/XpAward.gd` | P673c |
| Rank screen: trophies | new `game/ui/menu/TrophyBadge.gd`, `game/ui/menu/RankTrophySection.gd`; one line in `RankScreen.gd`; `RankText` keys | P673d |
| Rank screen: progress | new `game/ui/menu/RankProgressSection.gd`; `RankScreen.gd` (one line, and two columns where the width fits) | P673e |
| Result screen | `game/ui/ResultScreen.gd`, `game/ui/ResultText.gd` | P673f |
| Art | `assets/art/svg/icons/glyph_map.svg`, `glyph_time.svg`, `assets/CREDITS.md` | P673g |
| Main menu hint (question 3) | `game/ui/menu/MainMenu.gd`, `MainMenuText.gd` | P673h |
| Rank banner (question 4, only if yes) | `RankScreen.gd` | P673i |
| Docs | ADR 0054, this plan, `docs/HOW_TO_PLAY.md` and `data/help/how_to_play.tres` (the Rank row, `winning-result`), GDD note, dated notes in ADR 0042 §1 and ADR 0045 §2 | P673 (on acceptance), P673d-f (HOW_TO_PLAY), P673j |

Nothing in `game/sim`, `game/core`, `game/ai`, `game/view` or `native/`. `data/meta/**` is
already outside `balance.yml`'s paths, so no balance run starts.

## Command and data changes
- **Commands:** none. `STATE_FORMAT`, the state hash and the defs hash are unchanged.
- **Data:** a new `TrophyDef` type and `data/meta/trophies.tres`. Its fields are in ADR 0054 §2,
  and every count and tick limit is there.
- **Save:**
  - A new section `career` (ADR 0054 §4), with its own `format` 1.
  - No `SaveService.VERSION` bump. Section `progress` is unchanged.
- **Meta API** (`Progression`):
  - `refresh_trophies() -> Array[StringName]`.
  - `trophy_catalog() -> TrophyCatalog`.
  - `is_earned(id) -> bool`.
  - `earned_count() -> int`.
  - `career() -> Dictionary` (a copy).
  - `XpAward.trophies: Array[StringName]`.
  - The Phase 6 contract (`award_match`, `apply_bonus`, `xp_changed`) is unchanged; the award only
    gains a field.

## When trophies are checked
- **At award time.** `MenuFlow._on_match_ended` builds the summary and calls
  `Progression.award_match(summary)`. For a scored skirmish, that call does five things in order:
  1. Records the career.
  2. Checks every unearned trophy.
  3. Appends the new ones to `earned`.
  4. Writes `career`, then `progress`, in one frame, so one flush holds both.
  5. Returns the award with `trophies` set.
- **Which awards count:**
  - An abandoned match records nothing, as it pays nothing.
  - A surrender counts as finished.
  - A draw counts as finished, not won.
  - A lesson award checks only the state trophies.
- **On the Rank screen.** `RankScreen` calls `refresh_trophies()` each time it enters the tree. A
  finished lesson never reaches an award: it leaves through `return_to_menu`. So the lesson
  trophies, and the ones the back-fill made due, are stamped there.
- **Result screen line** (P673f):
  - The text is "TROPHY EARNED  SHORT WORK", or "2 TROPHIES EARNED  SHORT WORK, UNBROKEN", one
    clipped line.
  - Position: in the XP box, under the rank line and P670's unlock card, above the `OfferSlot`.
    The Double XP offer stays the last block before the buttons and is not changed.
  - It holds its space while the score is pending and collapses with the box when nothing is paid,
    so a late award moves nothing.
  - Double XP changes XP only, never this line.

## Monetization fit
- No rewarded or interstitial ad is tied to a trophy.
- No trophy needs, counts or rewards watching an ad.
- Remove ads changes nothing here.
- **Banner** (question 4). A banner on the Rank screen is allowed, because it is a menu. I
  recommend none at launch:
  - Today only the start page shows a menu banner. The Tutorial, Settings and How to play screens
    keep their foot slot empty.
  - Every visit to the Rank screen passes the main menu's banner.
  - A reward screen with an ad under it feels cheap.
- If Michael says yes (row P673i):
  - The `AdBannerBand` goes in `MenuScreen`'s foot slot, with `start_page` false.
  - It keeps `banner_gap_dp` (16, `data/ads_settings.tres`) of air above the band.
  - The scroll ends above that air, so BACK and every other control stays at least 16 dp away.
    The `AdBannerSlot` layout test proves it.

## Layout
- **Portrait and landscape** (ADR 0015).
  - One column, the `MenuScreen` width.
  - Where the measured safe width fits two columns with the gap, Progress and Trophies stand side
    by side; otherwise they are stacked.
  - The rule is the measured width, never the orientation (P664 uses the same rule for its card).
- **Order, top to bottom.** P664's rank block, then Progress, then Trophies. BACK is where P664
  puts it.
  - Progress is short and answers "how far" at a glance. The trophy list is the long part.
  - If P664 puts BACK at the end of the column, it lands about 1,000 dp down in portrait. That
    goes to P664's owner as a note: the phone's Back works anyway.
- **Trophy rows.** A 48 dp badge, the name (`CapsTitle`), then one muted line with the hint and
  progress, or "EARNED". About 56 dp a row, so 16 rows are about 900 dp.
- **Touch** (touch-ui-rules).
  - The rows and cells are read-only: no touch target, so the 48 dp rule applies to BACK only.
  - `MOUSE_FILTER_PASS` on every row, so P672b's drag scroll starts anywhere on the page.
  - Text autowraps. Nothing assumes width > height.
- **Look.** The theme's tokens only (`money`, `muted`, `ground`, `text`), no colour literal (the
  theme scan). EARNED is a word, not colour alone.

## Test plan (what is proven headless)
- **Data** (P673a, new `tests/meta/test_trophy_data.gd`):
  - The catalog loads and `TrophyCatalog.problem()` is empty.
  - Ids are unique, non-empty and pass `SaveService`'s key rule.
  - Each kind has its fields.
  - `lesson_ids` ⊆ `TutorialStart.ORDER`, and `fully_drilled` lists all of it.
  - `map_ids` equals `MapCatalog.map_ids()`.
  - Levels ⊆ the difficulty ids, and faction keys ⊆ the faction ids.
  - Each `hq_type_ids` type has `tab` -1. Each catalog skirmish scenario spawns exactly one of
    them for its local player.
  - Every glyph file exists.
  - Names and hints are non-empty.
  - A broken catalog (a duplicate id, a refused character, an unknown kind) reports a problem.
- **Summary** (P673b, new `tests/meta/test_match_summary.gd`, plus `test_menu_flow.gd`):
  - From a hand-built `MatchSnapshot`: the faction, the four stats of the local side, and
    `standing_types` (dead rows excluded, distinct ids).
  - A side out of range gives zeros, with no error.
  - An abandoned summary keeps its defaults.
  - `MenuFlow` passes the scenario's faction for the local seat.
- **Career and rules** (P673c, new `tests/meta/test_career_stats.gd`,
  `tests/meta/test_trophy_rules.gd`, `tests/meta/test_progression_trophies.gd`):
  - `record` for win, loss, draw and surrender; abandoned and lesson summaries change nothing.
  - `best_win_ticks` keeps the minimum. Ints are clamped.
  - Malformed entries are dropped with a warning (through the error sink, so no ERROR line).
  - An empty or refused map, level or faction id is skipped, and the award is still paid.
  - Unknown `career` keys survive a write.
  - Back-fill:
    - `finished` = `next_award_id - 1`.
    - Lessons come from `tutorial.done`.
    - The win trophies stay unearned.
    - Nothing is written until an award or a refresh earns something.
  - A table test drives each of the 16 data trophies with one case that earns it and one that
    just misses (ticks 9000 vs 9001, `lost_buildings` 0 vs 1, the HQ standing vs gone).
  - A trophy is earned once: a second qualifying award adds nothing, and `award.trophies` is
    empty.
  - `award.trophies` is in catalog order.
  - A read-only save changes nothing.
  - One flush holds both sections: read the file back after one frame.
  - A `progress` rewrite like an old build's keeps `career`.
  - `apply_bonus` still adds `base_xp` only.
- **Rank screen** (P673d and P673e, new `tests/ui/menu/test_rank_trophies.gd`,
  `test_rank_progress.gd`, plus `test_menu_six_sizes.gd`):
  - At the six sizes in both orientations, every row is inside the column and no label is clipped.
  - Two columns only where the measured width fits.
  - Lit rows read EARNED. Dim rows read their hint and progress ("7/10").
  - The heading count equals `earned_count()`.
  - The grid cells equal the career numbers. A locked cell shows the lock and its rank.
  - Entering the screen stamps a back-filled lesson trophy.
  - The rows are `MOUSE_FILTER_PASS`, and BACK stays at least 48 dp.
  - A missing glyph draws the frame alone, with a warning and no error.
  - No banner (unless P673i).
  - The theme scan is green.
- **Result line** (P673f, `tests/ui/test_result_screen*.gd`, `test_result_screen_offer.gd`):
  - It shows for an award with trophies and stays hidden for none.
  - It holds its space while pending, and the offer slot's y does not move on a late award.
  - A Double XP bonus leaves it as it is.
  - Lesson and dev-menu results are unchanged.
- **Sim smoke and hashes:** unchanged. No row touches the sim, so the golden hashes and the smoke
  must stay byte-equal.
- **Not headless:** the look and the scroll feel on the phone, Michael's check in P673j after
  P672b.

AI-vs-AI runs prove nothing here. Meta never runs in the harness.

## Rows
Line counts are production lines changed. Tests, data and art do not count (CLAUDE.md). Owners
follow Phase 5:
- monetization-dev owns `Progression` and `SaveService` (P510, P511).
- touch-ux-dev owns the screens.

| Row | Owner | Depends | What | Acceptance (tests) | HOW_TO_PLAY | Prod. lines |
| --- | --- | --- | --- | --- | --- | --- |
| P673 | architect | none | This plan and ADR 0054 (proposed). On Michael's answers: ADR 0054 accepted in the same PR, with dated notes in ADR 0042 §1 and ADR 0045 §2 and the GDD "Meta progression" note; rows adjusted to the answers | docs lens | none | 0 |
| P673a | monetization-dev | P673 accepted | **Trophy data:** `TrophyDef` (Kind enum and fields of ADR 0054 §2), `TrophyCatalog` (`trophies`, `hq_type_ids`, `problem()`), `data/meta/trophies.tres` with the 16 trophies of the accepted list | `test_trophy_data.gd` | none | ~120 |
| P673b | monetization-dev | P673 accepted | **Summary facts:** `MatchSummary.faction`, `built`, `lost_units`, `lost_buildings`, `harvested` and `standing_types` from the end snapshot; `MenuFlow` passes the faction | `test_match_summary.gd`; `test_menu_flow.gd` | none | ~60 |
| P673c | monetization-dev | P673a, P673b | **Career and the trophy check:** `CareerStats` (read, clamp, carry unknown keys, back-fill, `record`), `TrophyRules`, and the `Progression` wiring (`award_match` records, checks and writes `career` before `progress`; `refresh_trophies`; accessors; `XpAward.trophies`). If it passes ~400 lines, split it: `CareerStats` first, then the rules and the wiring | `test_career_stats.gd`, `test_trophy_rules.gd`, `test_progression_trophies.gd`; the existing `test_progression*` suites unchanged | none | ~290 |
| P673g | art-director | P673 accepted | **Two glyphs:** `glyph_map.svg`, `glyph_time.svg`, hand-written SVG in the HUD glyphs' greys, with CREDITS rows | P623's art test; the CREDITS coverage test | none | 0 (art) |
| P673d | touch-ux-dev | P673c, P664 merged; P673g for the two glyphs (until then the frame alone) | **Rank screen trophies:** `TrophyBadge` (drawn frame, glyph, pips, lit and dim by token), `RankTrophySection` (heading with the count, 16 rows, hint and progress or EARNED), added through `_add_section()`; `refresh_trophies()` on entry | `test_rank_trophies.gd`; `test_menu_six_sizes.gd` | the Rank row (P664's, e.g. `menus-rank`): trophies | ~200 |
| P673e | touch-ux-dev | P673c, P664 merged | **Rank screen progress:** `RankProgressSection` (wins grid with locks, lessons, matches, wins, time, fastest win); `RankScreen` puts the two sections side by side where the measured width fits | `test_rank_progress.gd`; `test_menu_six_sizes.gd` | the Rank row: progress | ~180 |
| P673f | touch-ux-dev | P673c, P670 merged | **Result line:** "TROPHY EARNED" in the XP box above the `OfferSlot`, with the pending rule | `test_result_screen*.gd`, `test_result_screen_offer.gd` | `winning-result` | ~40 |
| P673h | touch-ux-dev | P664 merged; question 3 | **Main menu hint:** the RANK row reads "03 RANK · SCOUT" (the current title). Nothing else on the main menu | `test_main_menu.gd`; `test_menu_six_sizes.gd` | `menus-main` | ~15 |
| P673i | touch-ux-dev | P673e; question 4 = yes only | **Rank screen banner:** the band in the foot slot, `start_page` false | `AdBannerSlot` gap test on the Rank screen at the six sizes | the Rank row: the advertisement | ~5 |
| P673j | qa-engineer, then architect + lead | P673d, P673e, P673f, P672b | **Proof and Michael's phone check:** the Rank screen at the six sizes in both orientations, screenshots; Michael plays a match, sees the result line, opens Rank and scrolls. Then ADR 0054's implementation note and the architect's memory | the named suites; Michael's yes | none | 0 |

### Waves and lanes
- **Wave 1**, after ADR 0054 is accepted: P673a, P673b and P673g in parallel. They share no
  file.
- **Wave 2:** P673c.
- **Wave 3:** P673d, P673e and P673f in parallel.
  - P673d and P673e each add one `_add_section()` line to `RankScreen.gd`. Verify the combined tree
    once before the second merge.
  - P673f touches only `ResultScreen.gd` and `ResultText.gd`, after P670.
- **Any time after P664:** P673h, if question 3 is yes. It touches `MainMenu.gd` after P664 and
  P665, in series.
- **Last:** P673i, if question 4 is yes; then P673j.
- **Critical path:** P673a → P673c → P673d → P673j, with P664 and P672b as outside gates.
- **Mutation testing:** none of these rows touches `game/sim/` or `native/`.
- **Review:** each code row gets 2 lenses and the docs rows 1 (Token budget).

## Risks
1. **Lesson XP may never be paid.** This is a finding for the lead, outside this plan.
   - A lesson ends by its last beat. Then `TutorialHost._leave` calls `MenuFlow.return_to_menu`,
     which never awards.
   - No lesson file has a `MATCH_WON` beat.
   - So ADR 0045's `lesson_xp` looks reachable only if a lesson match ends in the sim first.
   - Trophies read `tutorial.done` and do not depend on this.
   - To confirm with one headless run of `tests/e2e/test_tutorial_run.gd` reading `Progression.xp()`.
2. **The Headquarters rule rests on data.** A Headquarters cannot be built, sold or taken. P673a's
   test pins it. A later ADR that changes it must change `unbroken` or the summary.
3. **Save keys.** A refused key would refuse the whole `career` write. If the career and the XP
   were written as one unit, that would cost the XP award. Ids are validated in data, and unknown
   runtime ids are skipped (P673c tests both).
4. **Trophy ids are permanent.** Renaming an id loses it for every player. Only `name` and `hint`
   may change.
5. **Older builds and the web preview.** An older build keeps `career` untouched (ADR 0042 §1).
   That is why the counters are not in `progress` and why there is no version bump.
6. **Short Work's threshold.** The human-vs-AI target is 8-10 minutes (P556). 10 minutes on
   Normal may be common or rare. It is one number in data. Tune it after P673j.
7. **Long page.** About 1,000 dp in portrait. It depends on P672b's drag scroll and on where P664
   puts BACK.
8. **Rows in flight.** P664 and P670 change the files that P673d, P673e and P673f build on. Those
   rows wait for the merges and read the merged seam, not this plan's guess.
9. **Scope creep.** NEW badges, dates, Play Games and rewards go to the follow-up list (Scope
   guard).

## Questions for Michael
1. **The trophy list.** Are the 16 trophies above right, with 10 minutes for Short Work, 10 wins
   for Seasoned and 25 matches for Long Haul?
   - Recommended: yes. They cover first steps, every level, both sides, all three maps, the
     lessons and four skill feats.
   - Every one can be earned from a stat the game really has.
   - The numbers are data and easy to change later.
2. **Rewards.** Does a trophy pay XP or a cosmetic?
   - Recommended: neither at launch. XP would upset the rank pacing you approved (rank 4 in about
     five matches), and it raises the question of whether Double XP doubles it.
   - Cosmetics wait with the Headquarters skins until after launch, because the art page is full.
   - The trophy is its own reward.
3. **The main menu RANK row.** Should it keep a tiny hint, "03 RANK · SCOUT", or show only
   "03 RANK"?
   - Recommended: the hint, the rank title only. It adds no height (the reason for moving the card)
     and still says there is something to see.
4. **An ad banner on the Rank screen.** Allowed, because it is a menu.
   - Recommended: none at launch. Only the start page has a menu banner today, every Rank visit
     passes it, and an ad under your trophies feels cheap.
   - If yes: at the foot, 16 dp clear of every button.
