# ADR 0054: Trophies and career stats on the Rank screen

**In short, for Michael:**
- The Rank screen gets two new parts: **Trophies** (16 badges you earn once and keep; earned ones
  are lit and say EARNED, the others are dim and say how to earn them) and **Progress** (your
  skirmish wins per map and level, the lessons done, matches, wins and time played).
- Trophies give **no XP and no cosmetic** at launch (question 2). The rank tuning stays as you
  approved it, and Double XP never touches a trophy.
- No ad is tied to a trophy. The result screen gets one line, "TROPHY EARNED", above the Double XP
  offer, which stays as it is.
- Your own save and the testers' saves keep everything. The lessons you finished and the number
  of matches you played count at once. Wins and play time count from the update on, because the
  game never saved them.
- You said yes to all four recommendations (below).

Status: **accepted, 2026-11-27 (Michael: "Ja til alle anbefalinger", yes to every
recommendation of the plan's four questions; accepted in docs row P673 of the plan).** Proposed
the same day by the architect in row P673 on branch `claude/p673-rank-trophies-plan` (base `main`
at 5657700e, merged up to 8693766f before acceptance), with the plan
`docs/plans/2026-11-27-rank-trophies.md`. Questions 1 to 4 of the plan are this ADR's.

## Michael's answers (2026-11-27)
Verbatim: "Ja til alle anbefalinger".
- **Question 1, the trophy list:** the 16 trophies of the plan stand as proposed. Short Work is
  10 minutes (9000 ticks), Seasoned 10 wins and Long Haul 25 matches, all in data (§2).
- **Question 2, rewards:** none at launch. No XP and no cosmetic for a trophy (§6).
- **Question 3, the main menu:** the RANK row keeps a title hint, e.g. "03 RANK · SCOUT". It lands
  in P664, which now builds the main menu after Michael's Figma with a small footer profile line
  (plan row P673h, folded into P664).
- **Question 4, a Rank screen banner:** none at launch (§9). Plan row P673i is not now.
- Decided in the same answer, outside this ADR: a lesson's XP shows as "+40 XP" on its row of the
  Tutorial screen (row P674b).

Builds on: ADR 0042 (one save file, sections, versions), ADR 0043 (menu flow), ADR 0044 (the
tutorial section), ADR 0045 (rank, XP, `MatchSummary`), ADR 0052 (menu look, the drawn rank
insignia) and row P664 (the Rank screen and its `_add_section()` seam).

Amends by dated notes, written in P673 on acceptance:
- ADR 0042 §1: the section list gains `career` (this ADR §4).
- ADR 0045 §2: `MatchSummary` gains the fields of §3 below.
- The GDD's "Meta progression": trophies at launch, no reward.

## Context
- Michael, 2026-11-27: the commander card takes too much room on the main menu; make a separate
  ranking menu "where you can see your trophies and how far you have come in the game". Row P664
  moves the card to a new `RankScreen` with a section seam.
- What the game knows today when a match ends:
  - `MatchSummary`: outcome, level, map id, ticks, local side, lesson id.
  - The last `MatchSnapshot`: per player `stat_built`, `stat_lost_units`,
    `stat_lost_buildings` (a sold building or a cancelled site is no loss, `Outcome.count_losses`)
    and `stat_harvested`; the rows with owner, type and hit points.
  - `MatchSetup.scenario().factions[seat]`: the faction the local player played.
- What the save knows today:
  - `progress`: `xp`, `next_award_id` (one more than the number of scored skirmishes), the last
    8 awards and the lessons paid.
  - `tutorial`: `done`, the lessons finished (the Tutorial screen's DONE mark).
  - Nothing counts wins, wins per map, level or faction, or play time.
- A lesson ends on its last beat, not on a match end. Until P674 (#709) it left through
  `MenuFlow.return_to_menu`, which never awards, so `progress.lessons` stayed empty for lessons
  played before P674. Since P674, `MenuFlow.finish_lesson` scores the lesson once
  (`MatchSummary.for_lesson`, a win with the lesson id) after the director saved `tutorial.done`.
  `tutorial.done` stays the record of the lessons done; `progress.lessons` is the record of the
  XP paid.
- ADR 0045 §1: meta is never sim state, never in a hash or a replay. ADR 0042 §4: no clock time in
  the save.

## Decision
### 1. Where it lives
- `Progression` (`game/meta/progression_service.gd`) stays the one writer. It owns the new
  section and the trophy check, because it already owns the award, the read-only guard and the
  error sink.
- New `RefCounted`/`Resource` classes with `class_name`, all in `game/meta/`, none an autoload:
  - `TrophyDef` (Resource): one trophy.
  - `TrophyCatalog` (Resource): the list and the Headquarters type ids, with a validation method.
    The instance is `data/meta/trophies.tres` (already outside `balance.yml`'s paths through
    `!data/meta/**`).
  - `CareerStats`: reads, checks, back-fills and records the `career` section.
  - `TrophyRules`: pure static checks of one `TrophyDef` against the career, the lessons done and
    (for a match trophy) the summary.
- Nothing in `game/sim`, `game/core`, `game/ai` or `native/`. No Command. `STATE_FORMAT`, the
  state hash and the defs hash are unchanged.

### 2. A trophy is data
`TrophyDef` fields:
- `id: StringName`: a save key, stable forever. A data test checks it is non-empty, unique and
  free of the characters `SaveService` refuses (`= [ ] ; "`, line breaks, edge spaces). Rename
  the `name`, never the `id`.
- `name: String` and `hint: String`: English player text, shown through `tr()`. Original words,
  added to Phase 7's trademark screening list with the rank titles (ADR 0045 §3).
- `glyph: StringName`: the icon stem under `res://assets/art/svg/icons/`; `pips: int` (0 to 3).
- `kind: Kind` and its parameters:
  - `LESSONS`: every id in `lesson_ids` is in `tutorial.done`.
  - `COUNT`: the career counter `counter` (`finished`, `wins`, or `wins_faction` with `key` = a
    faction id) is at least `count`.
  - `WIN_GRID`: every pair of `map_ids` x `levels` has a win; an empty list means "any". So
    "a Hard win on each map" is `map_ids` = the three maps and `levels` = `[hard]`.
  - `MATCH`: this match is a win and meets every set filter: `levels` (empty = any),
    `max_ticks` (0 = no limit), `hq_standing` (true = the Headquarters still stands),
    `max_buildings_lost` (-1 = any).
- Every number (counts, tick limits) is in the `.tres` (CLAUDE.md rule 5).
- The first three kinds depend only on saved state. They can be checked at any time, and so
  they can be back-filled. `MATCH` is checked only when a match is awarded.

### 3. What the summary adds
`MatchSummary` gains, all filled in `from_snapshot` from the last published snapshot and the
setup. No view or UI reads the sim; the sim is untouched:
- `faction: StringName`: `MenuFlow` passes `_setup.scenario().factions[seat].id` (empty when
  unknown).
- `built`, `lost_units`, `lost_buildings`, `harvested`: the snapshot's `stat_*[local_side]` (0
  when the side is out of range).
- `standing_types: Array[StringName]`: the distinct type ids of the local player's rows with hit
  points above 0 at the end. One pass over the rows, once per match end, never per tick.

"The Headquarters was never destroyed" equals "a row of a type in `hq_type_ids` still stands at
the end". This holds because a Headquarters cannot be built (`tab` -1), sold (`buildings-sell`)
or taken. A data test pins `tab` -1 for each listed type, and that each skirmish scenario spawns
exactly one for its local player. If a later ADR makes a Headquarters buildable, that test fails
first.

### 4. Save: the new section `career`
One new section, owned by `Progression` through `CareerStats`:

| Key | Type | Meaning |
| --- | --- | --- |
| `format` | int | 1; the section's own format, like `MatchSetup.VERSION` |
| `finished` | int | skirmishes that ended (win, loss, draw, surrender) |
| `wins` | int | skirmish wins |
| `play_ticks` | int | the ticks of every finished skirmish, summed |
| `best_win_ticks` | int | the shortest win in ticks; 0 = no win yet |
| `wins_grid` | Dictionary | map id -> (level id -> wins) |
| `wins_faction` | Dictionary | faction id -> wins |
| `earned` | PackedStringArray | trophy ids, in the order they were earned |

- Every int is clamped to 0 and `MatchSetup.LIMIT` on read. A malformed entry is dropped with a
  warning (as `Progression._read` does for awards).
- An id that `SaveService` would refuse as a key (empty, or with a refused character) is
  skipped with a warning. It never reaches `set_section`, so it can never refuse the whole
  section, and with it the XP award.
- Keys the code does not know are carried through on write: `CareerStats` starts from the raw
  section and replaces only its own keys. So a newer build's keys survive an older build.
- **No save version bump.** ADR 0042 §3's migrations rewrite existing sections; this one is new.
  An older build keeps an unknown section unchanged (ADR 0042 §1). A bump would make every older
  build read-only on this save, including an older web preview on the same origin, and gain
  nothing.
- **Not in `progress`.** An older build's `Progression._read` rebuilds `progress` from its four
  keys and writes it back whole. It would wipe any new key there on its next award.
- No dates. ADR 0042 §4 allows no clock time, so `earned` keeps only the order.
- One award writes `career` and then `progress` in the same call. `SaveService` coalesces them
  into one flush at the end of the frame, so the file holds both or neither.

### 5. Back-fill for existing saves
When `career` has no `format`, `CareerStats` builds it in memory:
- `finished` = `progress.next_award_id - 1` (every scored skirmish took one id; lessons take
  none).
- Every other counter starts at 0.
- `earned` starts empty.

The next write saves it (an award, or a refresh that earns something). Nothing is written at boot,
so a headless run never writes the device's save. Then the state trophies are checked:
- Can be back-filled: the lesson trophies (`tutorial.done`) and the "finished N" trophies.
- Cannot be back-filled: every win-based trophy, the wins grid, the faction wins, play time and
  the fastest win. No saved record holds them; an award's `base_xp` cannot tell a win from a loss.
  They count from the update on.

The game is not released, so the saves concerned are Michael's and the testers'.

### 6. When trophies are checked
- **`Progression.award_match(summary)`**, for a scored skirmish:
  1. Record the summary into the career (an abandoned match records nothing, as it pays nothing;
     a surrender is finished, not a win).
  2. Check every unearned trophy (state kinds and `MATCH`).
  3. Append the new ids to `earned`.
  4. Write.
  5. Put the new ids, in catalog order, on the award: `XpAward.trophies: Array[StringName]`.
  A lesson award (`MenuFlow.finish_lesson`, P674) records no career and checks the state kinds
  only; `tutorial.done` already holds the lesson then, so its trophy comes on the result of that
  award. A read-only or refusing save changes nothing (the
  award is null, as today).
- **`Progression.refresh_trophies() -> Array[StringName]`**, state kinds only. The Rank screen
  calls it each time it enters the tree. It stamps the trophies the back-fill made due (and a
  lesson replay, which pays nothing and so has no award) and writes only when something is new.
- Accessors for the screens: `trophy_catalog()`, `is_earned(id)`, `earned_count()`, `career()`
  (a read-only copy). No new signal: the Rank screen refreshes on entry, and the result screen
  reads the award.
- Trophies never touch XP. `apply_bonus` and Double XP are unchanged.

### 7. Result screen
- One line, "TROPHY EARNED  <NAME>" or "<n> TROPHIES EARNED  <NAME>, <NAME>", clipped to one line.
- It sits in the XP box under the rank line (and P670's unlock card), above the `OfferSlot`.
- It follows the box's existing rule: it holds its space while the score is pending and collapses
  when the award has no trophy. A late award moves nothing.
- No sound, no animation, no ad.

### 8. Rank screen
- Two sections through P664's `_add_section()` seam, each its own script:
  - Progress (P673e).
  - Trophies (P673d).
- One column. Two columns side by side only where the measured safe width fits both, never by
  orientation (ADR 0015).
- Trophy rows and grid cells are read-only: no touch target, `MOUSE_FILTER_PASS`, so P672b's drag
  scroll works over them.
- The icon is one drawn badge frame (like ADR 0052's drawn rank insignia) with a glyph SVG
  inside. A lit badge uses the `money` token; a dim one uses `muted`. EARNED is a word, never
  colour alone.

### 9. Ads
- No rewarded or interstitial ad is tied to a trophy.
- No trophy counts or needs an ad.
- The Rank screen hosts no banner at launch (question 4, Michael: none). Its foot slot stays empty, as on the
  Tutorial, Settings and How to play screens. If Michael wants one, it is the `AdBannerBand` in
  `MenuScreen`'s foot slot with `start_page` false. That keeps `banner_gap_dp` (16) of air above
  the band. The scroll ends above that air, so no control is ever nearer.

## Consequences
- 16 trophies and a progress block for one data file, four small meta classes and two menu
  sections. No sim, hash or replay change; no balance run.
- Back-fill is partial (§5), and the plan says so.
- The trophy ids are permanent save keys.
- "Headquarters never destroyed" rests on a data rule that a test pins.
- `progress.lessons` and `tutorial.done` can differ for lessons finished before P674; trophies use
  `tutorial.done`, so those lessons still count.

## Alternatives considered
- **Counters in `progress`.** Rejected (§4): an older build would erase them.
- **A save version bump with a migration.** Rejected (§4): nothing to migrate, and it would lock
  older builds out of the save.
- **Per-trophy progress flags in the save.** Rejected: derive from counters; only `earned` is
  stored.
- **A new stat in the sim for "Headquarters lost".** Rejected: it changes the World, the hash and
  `STATE_FORMAT` for a meta badge; the end snapshot already answers it.
- **Google Play Games achievements.** Out of scope: a new SDK, sign-in and data-safety answers.
  It could mirror these ids later.
- **A trophy reward in XP.** Rejected at launch (question 2): it moves ADR 0045's tuning, and it
  raises the question of whether Double XP doubles it.
