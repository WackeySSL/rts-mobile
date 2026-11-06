# ADR 0031: The AI-vs-AI harness, the balance report JSON, the nightly run and the Phase 4 gate run

**In short, for Michael:** `run-sim-smoke.sh` plays real computer-against-computer matches to
the end (at most 15 minutes of game each), counts what every unit type did and writes one JSON
file. GitHub runs 100 or more such matches every night after `main` changed, adds them up and
posts the result on an issue labelled `balance`. Balance changes are one number in `data/` per
pull request, checked on the same seeds before and after. Five questions at the end.

Status: **proposed**, 2026-11-06 (architect, docs row P170). Base: `main` at f51e3ff. Plan:
`docs/plans/2026-11-06-phase-4.md`. Builds on ADR 0030 (the AI) and ADR 0020 §3 and §5 (headless
drivers call `AiDriver.think_all` before `MatchLoop.step`). Amends ADR 0020's answer 2 (the smoke's
three matches become full AI-vs-AI matches; its flags, exit codes and the report's top-level keys
stay, the schema number moves to 2) and records ADR 0013 §3's note on `run-sim-smoke.sh` (it runs
`AUTO` from Phase 4 and prints the implementation). No sim rule, Command, state column or golden
hash changes.

## Context
- **ROADMAP Phase 4, boxes 3-5:** "`run-sim-smoke.sh` runs real headless AI-vs-AI matches with
  seeds and writes the report JSON"; "`balance-nightly.yml` and an open issue labelled `balance`;
  first report in `docs/balance/`"; "Gate: Normal wins 40-60% against the mirror AI over 100
  matches, no match lasts over 15 minutes, every unit type is used".
- **CLAUDE.md, Token budget:** no AI-vs-AI balance runs and no timing runs in a session; balance
  runs go to GitHub Actions only. `verify.sh`'s smoke step stays (`scripts/verify.sh:57-58` calls
  `run-sim-smoke.sh --matches 3`), and verify runs once per PR head in a session and in CI.
- **The smoke as merged (P95, #225):** `scripts/run-sim-smoke.sh` takes `--matches N` and
  `--report PATH`, exits 0/1/2/3, and runs `tests/smoke/run_sim_smoke.gd`, which plays
  `tests/smoke/smoke_run.gd`: seeds 1 to N, Kestrel Flats, `dummy_fossil` (player 1) against
  `dummy_renew` (player 2), 1 800 ticks (`smoke_run.gd:22-33`), each tick `think_all` then
  `loop.step` (`:79-86`); it fails on a dropped Command (`:138-144`); report schema 1 with per
  player totals from the World's `stat_*` columns. It runs the GDScript sim (`run-sim-smoke.sh:26`),
  while ADR 0013's note says Phase 4's body "runs `AUTO` and prints the resolved implementation in
  its report ... The Phase 4 plan records this."
- **The skill `balance-report`:** seeds 1..N; win rate per side and per difficulty pairing, match
  length median and 90th percentile, per unit type production share, kills per 1000 credits spent
  and survival rate; flags outside 40-60 %, a median outside 8-10 minutes, a type below 5 % or above
  40 % of production; at most three data-only proposals; the nightly comments on the open `balance`
  issue.
- **Scenarios:** `skirmish_kestrel_flats.tres` puts the Derrick League at the top (player 1, tile
  7,7) and the Lumen Accord at the bottom (player 2, 54,54); `skirmish_kestrel_flats_mirrored.tres`
  swaps the factions, player 1 still at the top. Player 1 is always the top seat.
- **Per-type facts:** the World keeps per-player totals only (`stat_built`, `stat_lost_*`,
  `stat_harvested`). Its `events` (rewritten each tick, not state) hold `SPAWNED` and `DIED`
  records with the row's id, position, type and owner, and `SHOT` records with the shooter's id and
  the target's id (`World.gd:16`, `Combat.gd:284-291`).
- **CI:** `ci.yml`'s verify job ran 29-30 minutes with a 45-minute timeout (`ci.yml:43-45`); no
  scheduled workflow runs the sim; `docs/balance/` holds only `.gitkeep`.
- **Balance numbers are shared with the arenas:** `data/scenarios/perf_arena.tres` loads
  `data/rules.tres` and three Derrick League unit files, `perf_bases.tres` both rosters. Any tuning
  of those files would move the arenas' golden hashes (`data/dev/perf_gate.tres`) and the workload
  the `[sim]` and `[bases]` ratchets were calibrated on.

## Decision

### 1. The harness
- **Loop unchanged:** `smoke_run.gd` keeps ADR 0020 §3's loop (`AiDriver.think_all`, then
  `MatchLoop.step`), with controllers from `AiFactory.create` (ADR 0030 §6) and streams
  `DetRandom.create(seed, STREAM_AI_BASE + player)`, as `MatchRunner` makes them through `DetRng`.
- **A match** ends at the tick the match ends, or at the cap, `--ticks` (default **13 500**, 15
  minutes): a match still running at the cap is a **timeout**.
- **Implementation:** `AUTO`: native when the library loads, else GDScript, printed per run and
  stored in the report (ADR 0013's note). The twins agree by their locksteps; the harness's own
  check is §7.
- **Counting by type, outside the sim:** after each step the harness reads `world.events`:
  - `SPAWNED` after tick 0 of a type with a queue tab is *produced*; scenario rows and a refinery's
    free tanker (the tanker that spawns in the tick its refinery is placed) are *free* (counted
    apart);
  - `DIED` is *lost* for its owner and type;
  - `SHOT` sets the target's last shooter; a `DIED` credits a *kill* to the type of the last shooter
    of that target (a rupture's kills to the strike building's type when the strike landed that
    tick and no shot was recorded). This is an attribution for balance reading, documented as
    such, not a rule;
  - *spent* is produced times `type_cost`; structures placed are counted per type too.
  The World is only read, so the state hash is the same with and without the counting (a test).
- **AI counters:** `OpponentAi` exposes plain ints (waves launched, retreats, scouts sent, strikes
  fired, Commands sent, `work_max`); `DummyAi` reports 0. The harness copies them per player.

### 2. The script's flags (CI and the skills call them; old calls keep their meaning)
`bash scripts/run-sim-smoke.sh [--matches N] [--report PATH] [--seed-start S] [--levels A,B]
[--scenarios KIND] [--ticks T]`
- `--matches N`, `--report PATH`: as today (N > 0; seeds `S .. S + N - 1`).
- `--seed-start S` (default 1): for shards.
- `--levels A,B` (default `normal,normal`): the controller of player 1 and 2: `easy`, `normal`,
  `hard` (`OpponentDef` of the player's faction with that `AiDifficultyDef`) or `dummy` (the
  faction's dummy `AiDef`).
- `--scenarios KIND` (default `cross`): `cross` plays seed k on `skirmish_kestrel_flats` when k is
  odd and on `..._mirrored` when k is even, so each faction holds each seat in half the matches;
  `derrick`, `lumen` use one of the two; `fossil-mirror`, `renew-mirror` the same-faction scenarios
  of P174.
- `--ticks T` (default 13 500).
- **Exit codes unchanged:** 0 ok; 1 a dropped Command, a Godot error line or the OK line missing;
  2 a bad flag; 3 Godot missing. A timeout is **not** a smoke failure (the gate judges it).
- **`verify.sh` keeps `--matches 3`:** three full Normal-vs-Normal matches, crossed. Estimate on
  CI, native: about 13 500 ticks at 0.3-0.6 ms (the base arena's native tick is 0.2-0.4 ms at 178
  rows; full bases reach about 230 rows) plus the thinks, so 5-10 s a match and under a minute in
  all. P186 reads the real figure from CI's log. If verify's smoke step passes 3 minutes, P186's
  follow-up adds `--ticks 4500` to the verify call only (a qa-engineer row, not a silent change).

### 3. The report JSON, schema 2
One file per run; a key of schema 1 keeps its name and meaning. Every number is an int (ticks,
counts, credits, per-mille shares), so equal runs give equal text; `JSON.stringify` with sorted
keys and a trailing newline (`smoke_run.gd:121-122`).

```
{
  "schema": 2, "status": "ok" | "failed",
  "commit": "<GITHUB_SHA or 'local'>", "impl": "native" | "gdscript",
  "ticks_per_match": 13500, "seed_start": 1, "matches_requested": 100,
  "levels": ["normal", "normal"], "scenarios": "cross",
  "matches": [ {
    "seed": 1, "scenario": "res://data/scenarios/skirmish_kestrel_flats.tres",
    "ticks": 8211, "end": "victory" | "draw" | "timeout",
    "winner": 2, "match_end_tick": 8211, "state_hash": "<16 hex>",
    "dropped_commands": 0, "spawn_refused": 0,
    "players": [ {
      "player": 1, "faction": "fossil", "seat": "top", "ai": "opponent_fossil", "level": "normal",
      "credits": 0, "units": 0, "buildings": 0, "built": 0, "lost_units": 0,
      "lost_buildings": 0, "harvested": 0, "defeated_tick": 0,
      "produced": {"<type_id>": 0}, "free": {"<type_id>": 0}, "lost": {"<type_id>": 0},
      "kills": {"<type_id>": 0}, "spent": {"<type_id>": 0}, "structures": {"<type_id>": 0},
      "waves": 0, "retreats": 0, "scouts": 0, "strikes": 0, "commands": 0, "think_work_max": 0
    } ]
  } ],
  "summary": { ...section 4... }
}
```

### 4. The summary, the merge and the markdown
- `scripts/balance-summary.sh --out PATH REPORT...` (qa-engineer, P187; Godot headless running
  `tests/smoke/balance_summary.gd`, the same GDScript the suites test) merges shard reports: it
  refuses reports of another `commit`, `impl`, `ticks_per_match`, `levels` or `scenarios` (each
  refusal names the field), sorts matches by seed, and writes the merged JSON with this `summary`,
  plus `PATH.md` for the issue comment and `docs/balance/`:
  - `matches`, `victories`, `draws`, `timeouts`, `dropped_commands` (sum);
  - win shares in per-mille, a draw counting half to each side: `by_faction` (`fossil`,
    `renew`), `by_seat` (`top`, `bottom`), `by_level` when the levels differ;
  - `length_ticks`: median, 90th percentile, max (the markdown shows minutes);
  - per unit type: `produced`, `share_permille` of its faction's production,
    `kills_per_1000_credits_x100`, `survival_permille`, `matches_built`;
  - `distinct_final_hashes`;
  - `flags`: the skill's (a share outside 400-600, a median outside 7 200-9 000 ticks, a type under
    50 or over 400 per-mille of its faction's production) and two more: any timeout, and
    `distinct_final_hashes` under 95 % of `matches` (seeds that do not vary the match);
  - `gate`: present when the run is the gate set (§6), with each check's value, limit and verdict.
- The markdown is a fixed template (tables, then flags, then the gate); the nightly posts it as is.

### 5. The nightly (`balance-nightly.yml`, release-engineer, P190)
- **Triggers:** `schedule` (02:30 UTC) and `workflow_dispatch` with inputs `suite` (`nightly`,
  `gate`, `custom`), `ref` (default `main`), and for `custom` `levels`, `scenarios`, `matches`,
  `seed_start`.
- **Skip:** a scheduled run whose `main` SHA equals the last successful nightly's ends at once
  (question 3).
- **Jobs:** `build` (Godot and the native library through the existing scripts, uploaded once);
  `shards` (a matrix; each shard `run-sim-smoke.sh --matches 25 --seed-start S --levels ...
  --report build/balance/<set>-<S>.json`, 30-minute timeout); `merge` (`balance-summary.sh` per
  set, one artifact `balance-<date>-<sha>` with the JSON and markdown, then a comment on the open
  issue labelled `balance`). Permissions: `contents: read`, and `issues: write` on `merge` only.
- **Sets** (`nightly`):
  - the gate set: 100 Normal vs Normal, `cross`, seeds 1-100;
  - the ladder: Easy vs Normal and Hard vs Normal, 20 each, as `--levels easy,normal` seeds 1-10
    plus `--levels normal,easy` seeds 1-10 (the same for Hard), `cross`, so each level plays both
    seats and both factions;
  - the mirrors: `fossil-mirror` and `renew-mirror`, Normal vs Normal, 20 each (seat fairness and
    AI symmetry, question 1's B as a nightly check);
  - the baseline: Easy vs the dummy, 10 (`easy,dummy` 5 and `dummy,easy` 5).

  `gate` runs the gate set only. The summary of each set is its own block in the comment.
- **No open `balance` issue:** the merge job fails and says so (CLAUDE.md: say what is missing, no
  work-around). The lead opens the issue and the label once (P190's acceptance).
- **Cost** (estimate): about 190 matches at 5-10 s each on native, so 20-35 runner minutes a night
  when `main` moved. P190 reads the real figure from the first runs.
- `tests/project/test_ci_workflow.gd` pins the triggers, the permissions, the script calls and the
  shard seeds (release-engineer's suite).

### 6. The Phase 4 gate run
- **The set:** `suite=gate` on the `main` commit under test: 100 Normal vs Normal matches,
  `cross`, seeds 1-100, so seeds 1, 3, ... put the Derrick League at the top and 2, 4, ... the
  Lumen Accord (question 1).
- **Checks** (the summary's `gate` block; every one must pass):
  1. each faction's win share is 400-600 per-mille (draws half);
  2. the top seat's win share is 400-600 per-mille;
  3. no timeout, and the longest match is at most 13 500 ticks;
  4. every unit type of both factions (twelve, tankers included) is "used" (question 2);
  5. `dropped_commands` is 0 in every match;
  6. at least 95 distinct final hashes;
  7. `impl` is `native`, recorded.
- **Chance, decided before the run:** at a true 50 % the share of 100 matches has a standard
  deviation of 5 points, so a fair AI misses 40-60 % about one time in twenty. If check 1 or 2 lands
  in 350-399 or 601-650 per-mille, the lead runs seeds 101-200 once (`custom`, same commit) and the
  gate reads the share of all 200 against 400-600; outside 350-650 on the first 100 the gate fails
  and tuning goes on. No other re-run.
- Michael's phone check follows the run (plan, "Gate procedure").

### 7. Determinism, proven headless
- A short AI-vs-AI match (2 700 ticks) twice from one seed gives the same record and the same
  checkpoint hashes (session, P188).
- Its replay, played without any AI, reaches the same checkpoints (`Replay.play`; ADR 0020 §3).
- The same match on the GDScript and the native implementation gives the same final hash (session,
  where the library is built; CI's verify).
- The `determinism-arm64` job runs P188's suite too (P188's request to release-engineer), so x86_64
  and arm64 agree.
- The harness's counting changes no hash (the state hash with and without it).
- The full-length cases (13 500 ticks, 100 seeds) run only in Actions.

### 8. The balance workflow
- **Data only, one number per pull request** (the skill; ai-dev). A tuning row names the number,
  its file, the flag it answers, the expected effect, and shows before and after on the same seeds:
  "before" is the latest nightly of `main`, "after" is a `custom` run of the same sets on the PR's
  branch (`workflow_dispatch` with `ref`). Nothing runs in a session; ai-dev reads the reports.
- **Tuning moves no golden hash.** Plan row P171 gives both arenas frozen copies of every def they
  load (`data/dev/arena/`: rules, units, buildings, weapons, factions), with the same numbers, so
  `golden_hex`, `bases_golden_hex`, `TICK_0_SEED_1` and the `[sim]`/`[bases]` workloads stay as
  they are while `data/units/` moves; P171b points the sim suites' hand-built Worlds at the same
  copies, so a tuning row only touches the pins that intentionally read shipped data.
- **Pins:** a tuning row also updates the literal that pins its number (roster data tests, display
  tests) under the plan's named exception 20; the owner of each file reviews.
- **Rule changes are not tuning:** artillery splash (ADR 0018 question 4), an artillery back-away
  rule (Phase 3 plan risks), pausing a strike's charge at low power (ADR 0023 §10), a blackout that
  stops a second producer (ADR 0023 §10's note) and a new field regrowth model (ADR 0023 §11) each
  need their own ADR and a gameplay-dev row. The plan lists them as conditional, not scheduled.
- **`docs/balance/`:** the first report (P191, box 4), the gate run's report, and the before and
  after of each tuning row as `docs/balance/<yyyy-mm-dd>-<topic>.md`. The nightly itself writes
  no file in the repository; it comments and keeps its artifact (90 days).

## Consequences
- Every `verify.sh` plays three real matches; CI's verify grows by under a minute (estimate).
- A balance number can change without any golden hash or perf calibration moving.
- The report counts kills by "last shooter"; splash, ruptures and focus fire make it an estimate,
  which the markdown says.
- Actions minutes: about 20-35 a night when `main` moved.
- The `balance-report` skill's step 1 gains the new flags and the merge step (lead, on Michael's
  yes to the skill change, plan row P170b).

## Alternatives considered
- **Timeouts as draws:** would hide the "no match over 15 minutes" box. Rejected.
- **Same-faction mirrors as the gate set:** proves seat fairness and AI symmetry but not faction
  balance; kept as nightly-only sets (`fossil-mirror`, `renew-mirror`), offered as question 1's B.
- **Per-type counters in the sim** (new hashed `stat_*` columns): would re-pin every golden and add
  sim work for a report; the events give the same counts outside the sim.
- **A Python merge script:** a second implementation of the summary; the GDScript one is tested by
  the same suites.
- **The nightly writing `docs/balance/` itself:** a bot commit or PR every night; comments and
  artifacts are enough until a human tunes.
- **Re-pinning the arenas on each tuning row** instead of freezing them: churn on every tuning PR
  and a ratchet calibrated on a moving workload.

## Questions for Michael
1. **"Wins 40-60 % against the mirror AI".** Both sides are Normal; what must be even?
   - A: the factions: the Derrick League and the Lumen Accord each win 40-60 % of 100 crossed
     matches (each side starts at the top in half of them), and the top start wins 40-60 % too.
   - B: the seat only: same-faction matches (League against League, Accord against Accord, 50
     each), and the top start wins 40-60 % in each.
   - C: both (200 matches).
   Recommended: **A** (B runs every night anyway as a check).
2. **"Every unit type is used".**
   - A: each of the twelve unit types is built in at least half of the 100 gate matches; a type
     under 5 % of its side's production is only flagged in the report.
   - B: each type is at least 5 % of its side's production over the 100 matches.
   Recommended: **A** (B mostly measures the AI's chosen mix, not balance).
3. **The nightly run.**
   - A: every night at 03:30 Danish winter time (02:30 UTC), only when `main` changed: the 100-match
     gate set, Easy and Hard against Normal (20 each), the two same-faction mirrors (20 each)
     and Easy against the old dummy (10), about 30 minutes of GitHub's machines.
   - B: every night, changed or not.
   - C: only when started by hand.
   Recommended: **A**.
4. **Who tunes.** ai-dev may change one balance number per pull request in `data/` from the
   reports, merged after the lead's review, without asking you each time; you see every report on
   the `balance` issue and the gate run's report before the gate. (ja/nej; recommended: **ja**)
5. **Your phone check at the gate.** Six matches: Easy, Normal and Hard, each as both factions.
   - A: play Normal to the end as each side; Easy and Hard may end with Surrender once you have the
     feel (after about 5 minutes).
   - B: all six to the end.
   Recommended: **A**.
