# ADR 0045: Commander rank, XP and unlocks

**In short, for Michael:** each finished match gives XP: more for a win, more on a harder level, a
little per minute up to a cap. XP raises your commander rank. Recommended: rank 2 opens map 2, rank 3
opens Hard and rank 4 opens map 3, all within about five matches; each rank also gives a title and
an insignia. Nothing needs an ad: Phase 6's Double XP offer only speeds it up. Headquarters skins
wait until after launch, because the art page is nearly full.

Status: **proposed, 2026-11-15 (awaiting Michael).** Written by the architect on branch
`claude/p500-phase5-plan` (base `main` at a2204d2f) with the plan
`docs/plans/2026-11-15-phase-5.md` (rows P511, P524, P525, P532). Questions 4 and 15 of the plan
are this ADR's. The `Progression` interface is agreed with Phase 6 (2026-11-15).

Amends by a dated note at acceptance (P500b): the GDD's "Meta progression" (skins after launch, per
question 4).

## Context
- GDD: "Commander rank from XP (win, loss, difficulty bonus). Unlocks: maps, Hard difficulty,
  cosmetic Headquarters skins; all eight team colours are open from the start. Everything can be
  unlocked without watching ads. Rewarded ads offer double XP after a match and +500 starting
  credits for the next match."
- Phase 6 (agreed): `award_match(summary) -> XpAward`, `apply_bonus(award_id, multiplier) -> bool`
  once per award and persisted, signal `xp_changed`; the multiplier is Phase 6 data.
- The atlas's page 1 holds every y-sorted picture and is nearly full after Phase 4b (ADR 0036 §15);
  a skin per faction's Headquarters is two more models on it.

## Decision
### 1. Where it lives
Autoload **`Progression`** (`game/meta/progression_service.gd`, no `class_name`), with
`ProgressionDef` (Resource, `data/meta/progression.tres`), `MatchSummary` and `XpAward`
(`RefCounted`s with `class_name`). Meta, not sim: XP is never game state, never in a hash or a
replay. Integer arithmetic only, so tests are exact.

### 2. XP
- `MatchSummary` (built by `MenuFlow` from the last snapshot and the `MatchSetup`): outcome (win,
  loss, draw, surrender), level, map id, ticks, local side, lesson id or none.
- `base_xp = outcome_xp[outcome] * level_percent[level] / 100 + min(minutes * xp_per_minute,
  minute_cap)`; surrender counts as a loss; an abandoned match (Exit to menu, a failed restore)
  gives no award at all; a tutorial lesson pays `lesson_xp` once per lesson (question 15).
- `award_match` returns an `XpAward` with a stable `id` (a counter in the save), `base_xp` and
  `bonus_applied` false, and adds `base_xp`. `apply_bonus(id, multiplier)` adds `base_xp *
  (multiplier - 1)` once, for one of the last `awards_kept` (8) awards, sets `bonus_applied`,
  saves, emits `xp_changed`, and returns true; any other call returns false.

### 3. Ranks
`rank_xp` (a rising list; a data test checks it rises), `rank_titles` (original words, screened in
Phase 7's trademark step) and an insignia per rank drawn by art-director (SVG, own work). The rank
is derived from XP, never stored on its own.

### 4. Unlocks (question 4, option A)
`unlocks` in data: a list of (rank, kind, id): map 2 at rank 2, Hard at rank 3, map 3 at rank 4
(starting values; XP tuned so a player who wins about half on Normal reaches rank 4 in about five
matches). Kestrel Flats, Easy and Normal are open from the start; the eight team colours stay open
(GDD). A locked card shows its rank. Headquarters skins are out of scope for launch. The dev menu
ignores locks.

### 5. Save
Section `progress` in `SaveService`: `xp`, `next_award_id`, the last awards (`id`, `base_xp`,
`bonus_applied`), lessons paid. A newer save version is not written (ADR 0042 §3).

## Consequences
- Rank and unlocks are cheap: one data file, one autoload, three screens read them.
- A player who wants Hard at once waits about two matches (option A); option B removes every lock.
- Skins need their own art row and page room after launch.

## Alternatives considered
- **B. Cosmetic only** (everything open). Simpler, kinder to experienced players; loses the GDD's
  sense of progress.
- **C. The GDD as written, skins at launch.** Costs two models on a full atlas page before launch.
- **XP in the sim or the replay.** Rejected: not game state; a balance change would move no hash.
