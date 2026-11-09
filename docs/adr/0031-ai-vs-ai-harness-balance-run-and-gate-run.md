# ADR 0031: The AI-vs-AI harness, the balance report JSON, the balance run and the Phase 4 gate run

**In short, for Michael:** `run-sim-smoke.sh` plays real computer-against-computer matches to the
end (at most 15 minutes of game each), counts what every unit type did and writes one JSON file.
GitHub runs about 190 such matches after each merge that changes AI, balance or sim files, or when
the lead starts it, adds them up and posts the result on an issue labelled `balance`. Balance
changes are one number in `data/` per pull request, checked on the same seeds before and after. The
gate is judged on 100 fresh seeds that no tuning ever saw. Michael answered the five questions on
2026-11-06 (Acceptance note).

Status: **accepted, 2026-11-06** (Michael: 1 A, 2 A, 3 A, 4 ja, 5 A; Acceptance note below).
Proposed 2026-11-06 (architect, docs row P170, PR #345); revised the same day after the lead's docs
lens on fe338f5; accepted by the docs row P170b on the same PR. Base: `main` at f51e3ff. Plan:
`docs/plans/2026-11-06-phase-4.md`. Builds on ADR 0030 (the AI) and ADR 0020 §3 and §5 (headless
drivers call `AiDriver.think_all` before `MatchLoop.step`). Amends ADR 0020's answer 2 (the smoke's
three matches become full AI-vs-AI matches; its flags and exit codes stay, the schema number moves
to 2 and one top-level key moves, §3) and records ADR 0013 §3's note on `run-sim-smoke.sh` (it runs
`AUTO` from Phase 4 and prints the implementation). No sim rule, Command, state column or golden
hash changes.

Status note (2026-11-06, P26be docs, from the reviews of P186): the note at the end of §2 records
how the harness reads §1's kill attribution and §2's flags. No accepted text changed; the note
narrows §2's "as today" for `--matches` (at most nine digits), the one old call whose meaning
changes.

Status note (2026-11-07, P26bf docs, from the reviews of P187): the note at the end of §4 records
how `balance-summary.sh` names its markdown, tells the gate run apart and judges a gate set. No
accepted text changed; the note reads §4's "plus `PATH.md`", "a draw counting half" (a timeout
too), `by_faction` (left out of a mirror) and "present when the run is the gate run" (`--gate`),
and §6's checks (a `set` check first) and its 200-match rerun. The Phase 4 plan's P190 row has
a dated note on how the mirrors and the rerun are summarised.

Status note (2026-11-09, P26bi docs, from the reviews of P188 and P190): the notes at the end of
§5 and §7 record that `workflow_dispatch` has no `ref` input (a run plays the commit it is
dispatched on), the gate and `post` guards, the manual gate rerun, and how §7's strike case reads
"each charged strike building". No other accepted text changed; §5's inputs list and §8's "with
`ref`" are read through the §5 note.

## Acceptance note (2026-11-06)
Michael answered the eight questions of ADR 0030 and this ADR in chat on 2026-11-06. The lead had
numbered them 1-8 in chat (1-3 are ADR 0030's, 4-8 are this ADR's). Verbatim: "1 C, 2 A, 3 Ja, 4 A,
5 A, 6 forstår ikke hvordor der er noget der skla køre om natten? er det ikke et færdig spil uden
noget server? men hvis jeg skal vælge lyder A fornuftigt, 7 Ja, 8 A."

(In English, his answer 6: "don't understand why something has to run at night? isn't it a
finished game without any server? but if I have to choose, A sounds sensible".) The lead answered
that the run is a development tool on GitHub's machines that players never see. Michael followed
up on 6 the same day in two messages, verbatim:
- "dvs. at de 100 kampe vil tage 2 dage at spille?" ("so the 100 matches will take 2 days to
  play?") The lead answered that the matches run headless and sharded, about 30 minutes for all
  sets, not in real time.
- "bare kør dem når det passer ind i dit floa, kan ikke se hvorfro vi skal vente til et bestemt
  tidspunkt med at køre dem?" ("just run them when it fits your flow, can't see why we should wait
  for a particular time to run them?")

He then added two more messages, verbatim:
- "det jeg mener med det er at du skal ikke vente til et bestemt tidspunkt med at køre dem hvis
  det passer ind" ("what I mean is that you should not wait for a particular time to run them if it
  fits in")
- "du skla kun vente hvis du kan se at det giver mening at samle noget sammen så de ikke skal køre
  så mange gange" ("you should only wait if you can see that it makes sense to gather something
  together so they don't have to run so many times")

Under these the lead decided the trigger and the batching of §5 and §8: no schedule; a run after
each push to `main` that changes AI, balance or sim files, and by hand; a workflow-level
concurrency group that cancels a run in progress, so a burst of merges ends in one run on the
newest commit; and the lead may merge several small tuning PRs together so one run reports on all
of them. The lead records this ADR's five as "1 A, 2 A, 3 A (changed by Michael's follow-up),
4 ja, 5 A" (chat numbers 4-8):
1. **A (chat 4, "40-60 % against the mirror AI"):** the gate set crosses the factions; each faction
   and the top start win 40-60 % of 100 held-out matches; a share of 350-399 or 601-650 per-mille
   on check 1 or 2 gets one more run of 100 held-out seeds, and the 200 decide (§6). Options B
   (seat only) and C (both) were not chosen; the same-faction mirrors stay a check of the balance
   run only.
2. **A (chat 5, "every unit type is used"):** each of the twelve unit types is built in at least 50
   of the 100 gate matches; under 5 % of its side's production is a report flag, not a gate check.
   Option B was not chosen.
3. **A, changed by Michael's follow-up (chat 6, the balance run): on demand and after merges that
   change AI, balance or sim files; no schedule.** The sets and seeds of §5 are A's; the time of day
   and the "only when `main` changed" check are gone, because the path filter of §5 replaces them;
   the concurrency group and the lead's batching of tuning PRs (§8) answer "only wait if it makes
   sense to gather something together". Options B (every night) and C (by hand only) were not chosen
   as written. Michael asked why anything runs at night when the game has no server; §5 now says
   what the run is.
4. **ja (chat 7, who tunes):** ai-dev merges data-only tuning rows, one number each, after the
   lead's review, without asking Michael each time; he sees every report on the `balance` issue
   and the gate report before the gate.
5. **A (chat 8, the phone check):** Normal to the end as each faction; Easy and Hard may end with
   Surrender after about 5 minutes. Option B was not chosen.

The decision below is the accepted text; P170b changed the status, this note, one sentence in §5
that answers Michael's question, §5's triggers and the name "balance run" (from "nightly"; the
workflow is `balance.yml`) after his follow-up, the wording that named open answers, and the
questions' "answered" marks. Nothing is applied in code yet: the plan's rows apply it.

## Context
- **ROADMAP Phase 4, boxes 3-5:** "`run-sim-smoke.sh` runs real headless AI-vs-AI matches with
  seeds and writes the report JSON"; "`balance-nightly.yml` and an open issue labelled `balance`;
  first report in `docs/balance/`" (P170b renamed the file in box 4 to `balance.yml`, Michael's
  follow-up of 2026-11-06); "Gate: Normal wins 40-60% against the mirror AI over 100
  matches, no match lasts over 15 minutes, every unit type is used".
- **CLAUDE.md, Token budget:** no AI-vs-AI balance runs and no timing runs in a session; balance
  runs go to GitHub Actions only. `verify.sh`'s smoke step stays (`scripts/verify.sh:57-58` calls
  `run-sim-smoke.sh --matches 3`), and verify runs once per PR head in a session and in CI.
- **The smoke as merged (P95, #225):** `scripts/run-sim-smoke.sh` takes `--matches N` and
  `--report PATH`, exits 0/1/2/3, and runs `tests/smoke/run_sim_smoke.gd`, which plays
  `tests/smoke/smoke_run.gd`: seeds 1 to N, Kestrel Flats, `dummy_fossil` (player 1) against
  `dummy_renew` (player 2), 1 800 ticks (`smoke_run.gd:22-33`), each tick `think_all` then
  `loop.step` (`:79-86`); it fails on a dropped Command (`:138-144`); report schema 1 with a
  top-level `scenario` (`:112`) and per-player totals from the World's `stat_*` columns. It runs
  the GDScript sim (`run-sim-smoke.sh:26`), while ADR 0013's note says Phase 4's body "runs `AUTO`
  and prints the resolved implementation in its report ... The Phase 4 plan records this."
- **The skill `balance-report`:** seeds 1..N; win rate per side and per difficulty pairing, match
  length median and 90th percentile, per unit type production share, kills per 1000 credits spent
  and survival rate; flags outside 40-60 %, a median outside 8-10 minutes, a type below 5 % or above
  40 % of production; at most three data-only proposals; the nightly job comments on the open
  `balance` issue.
- **Scenarios:** `skirmish_kestrel_flats.tres` puts the Derrick League at the top (player 1, tile
  7,7) and the Lumen Accord at the bottom (player 2, 54,54); `skirmish_kestrel_flats_mirrored.tres`
  swaps the factions, player 1 still at the top. Player 1 is always the top seat.
- **Per-type facts:** the World keeps per-player totals only (`stat_built`, `stat_lost_*`,
  `stat_harvested`). Its `events` (rewritten each tick, not state) hold `SPAWNED` and `DIED`
  records with the row's id, position, type and owner, `SHOT` records with the shooter's id and
  the target's id, and `STRIKE` records with the landing tick (`World.gd:14-16`,
  `Combat.gd:284-291`).
- **CI:** `ci.yml`'s verify job ran 29-30 minutes with a 45-minute timeout (`ci.yml:43-45`); no
  scheduled workflow runs the sim; `docs/balance/` holds only `.gitkeep`.
- **Balance numbers are shared with pinned hashes:** `perf_arena.tres` loads `data/rules.tres` and
  three Derrick League unit files, `perf_bases.tres` both rosters, and `controls_test.tres` (whose
  tick-0 hash is `TICK_0_SEED_1`, `tests/sim/test_world_hash.gd:6`, `:301-303`) the shipped
  `light_tank.tres` and `rules.tres`; the fog and targeting rigs load those scenarios
  (`tests/sim/support/fog_worlds.gd:11-12`, `targeting_worlds.gd:20-21`). `RulesDef`'s script
  defaults are pinned equal to `data/rules.tres` (`game/sim/defs/RulesDef.gd:3-5`,
  `tests/sim/test_defs_data.gd:120-129`) and feed every hand-built World (`World.gd:641-643`).

## Decision

### 1. The harness
- **Loop unchanged:** `smoke_run.gd` keeps ADR 0020 §3's loop (`AiDriver.think_all`, then
  `MatchLoop.step`), with controllers from `AiFactory.create` (ADR 0030 §6) for players 1 and 2
  (the harness seats them itself; no `MatchRunner`) and streams
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
    of that target (a rupture's kills to the strike building's type when a `STRIKE` record's
    landing tick is this tick and no shot was recorded). This is an attribution for balance
    reading, documented as such, not a rule;
  - *spent* is produced times `type_cost`; structures placed are counted per type too.
- **The flow cache:** after each step the harness counts `flow_full_ticks`, the ticks after which
  every slot of `world.flow` is referenced (ADR 0030 §4).
- The World is only read, so the state hash is the same with and without the counting (a test).
- **AI counters:** the harness copies `AiController`'s ints (`waves`, `retreats`, `scouts`,
  `strikes`, `commands`, `work_max`; ADR 0030 §3) per player, for any controller.

### 2. The script's flags (CI and the skills call them; old calls keep their meaning)
`bash scripts/run-sim-smoke.sh [--matches N] [--report PATH] [--seed-start S] [--levels A,B]
[--scenarios KIND] [--ticks T]`
- `--matches N`, `--report PATH`: as today (N > 0; seeds `S .. S + N - 1`).
- `--seed-start S` (default 1): for shards and for held-out seeds.
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
- **`verify.sh` keeps `--matches 3`:** three full Normal-vs-Normal matches, crossed.
- **Verify's whole cost** (estimates; P186 and P189 read the real figures from CI's log): the
  smoke's 3 full matches, P180's and P193's matches and about five 2 700-tick suite matches (P176,
  P179, P188), about 80 000 ticks in all. The AI suites run their matches `AUTO` through
  `tests/sim/support/sim_impls.gd` (native when the library loads, which verify builds; GDScript
  otherwise, the reference). Native at 0.3-0.6 ms a tick (the base arena's native tick is 0.2-0.4
  ms at 178 rows; full bases reach about 230 rows) plus the thinks: about 1 minute on top of
  today's 29-30. If the smoke step alone passes 3 minutes, a qa-engineer row adds `--ticks 4500` to
  the verify call (never a silent change).

Note (2026-11-06, P26be docs, from the reviews of P186):
- **Kill attribution, in order:** a `SHOT` at the row in the tick it dies credits that shooter;
  else an enemy rupture landing in that tick, when the row died within the rupture's radius of the
  `STRIKE` point, credits the strike building's type; else the row's last shooter; else nobody. A
  cancelled site is neither a loss nor a kill. This reads §1's "no shot was recorded" as no shot
  at the row in that tick, so a rupture beats an older shooter; the radius test is the harness's
  own. P187's markdown (§4) states this order, not "the last shooter".
- **Per-type maps** hold only the types that occurred (absent means 0). P187's checks that need
  every unit type (§6 check 4 and §4's flag under 50 per-mille) read the faction rosters. `kills`
  can hold structure types, which have no `spent`; P187's kills per 1 000 credits skips them.
- **A dropped Command** fails the run naming its seed and the tick of the first drop. The tick is
  printed, not stored: the report's keys stay those of §3.
- **Flags:** an empty value is a bad flag (exit 2), and the numbers take at most nine digits, so
  `--matches` with ten or more digits, valid before, now exits 2. No caller passes one.
- **Cost today:** until P176-P180 merge, the smoke's controllers send few or no Commands, so CI's
  smoke time is a floor. The lead reads it again after P176, P178 and P180 against the 3-minute
  line above.

### 3. The report JSON, schema 2
One file per run. Every schema 1 key keeps its name and meaning except one: the top-level
`scenario` **moves to `matches[].scenario`**, because a `cross` run plays two scenarios; the
top-level `scenarios` names the kind. Every number is an int (ticks, counts, credits, per-mille
shares), so equal runs give equal text; `JSON.stringify` with sorted keys and a trailing newline
(`smoke_run.gd:121-122`).

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
    "dropped_commands": 0, "spawn_refused": 0, "flow_full_ticks": 0,
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
  `tests/smoke/balance_summary.gd`, the same GDScript the suites test) merges the shard reports of
  one set. It refuses reports of another `commit`, `impl`, `ticks_per_match` or `scenarios`, or
  whose level pair differs **as an unordered pair** (so `easy,normal` and `normal,easy` merge;
  `easy,normal` and `hard,normal` are refused); each refusal names the field. It sorts matches by
  (seed, level order) and writes the merged JSON with this `summary`, plus `PATH.md`:
  - `matches`, `victories`, `draws`, `timeouts`, `dropped_commands` (sum), `flow_full_ticks` (sum
    and the most in one match);
  - win shares in per-mille, a draw counting half to each side: `by_faction` (`fossil`,
    `renew`), `by_seat` (`top`, `bottom`), and `by_level` when the two levels differ, read from
    each player's `level` (so a swapped pair counts each level on both seats);
  - `length_ticks`: median, 90th percentile, max (the markdown shows minutes);
  - per unit type: `produced`, `share_permille` of its faction's production,
    `kills_per_1000_credits_x100`, `survival_permille`, `matches_built`;
  - `distinct_final_hashes`;
  - `flags`: the skill's (a share outside 400-600, a median outside 7 200-9 000 ticks, a type under
    50 or over 400 per-mille of its faction's production) and three more: any timeout, any
    `flow_full_ticks`, and `distinct_final_hashes` under 95 % of `matches`;
  - `gate`: present when the run is the gate run (§6), with each check's value, limit and verdict.
- The markdown is a fixed template (tables, then flags, then the gate); it says that kills are
  attributed to the last shooter.

Note (2026-11-07, P26bf docs, from the reviews of P187):
- **The markdown file** is `--out PATH` with a trailing `.json` replaced by `.md` (`x.json` gives
  `x.md`), else PATH with `.md` added. It states §2's note's attribution order, not only "the last
  shooter".
- **The gate run:** `balance-summary.sh` writes `gate` only when it is given `--gate`; P190
  passes the flag on the gate run's summary.
- **The gate judges only a gate set:** its first check, `set`, fails unless the matches are exactly
  100 with seeds 1001-1100 or exactly 200 with seeds 1001-1200, the levels are `normal,normal`,
  the kind is `cross` and the two rosters hold twelve unit types between them. The rerun band
  (350-399 or 601-650 on checks 1 and 2) applies at exactly 100 matches and gives the verdict
  `rerun`; on the 200, checks 1 and 2 decide against 400-600 and checks 3-7 are judged on all
  200 (check 4: every type built in at least 100; check 6: at least 190 distinct hashes). Any
  failing check makes the verdict `fail`.
- **A timeout counts half to each side in the win shares**, as a draw does, so a set's two
  faction shares (and its two seat shares) add up to 1 000, give or take 1 from rounding; the
  timeout itself is still flagged and fails gate check 3.
- `by_faction` is left out of a same-faction set. A faction whose roster is missing, does not
  load or holds no unit type, or a type in two rosters, fails the summary (`FAILED`, exit 1).

### 5. The balance run (`balance.yml`, release-engineer, P190)
- **What it is:** a development tool that runs on GitHub's machines, like the CI that checks every
  pull request; players never see it, and the game stays offline with no server.
- **Triggers** (Michael's follow-up of 2026-11-06: "run them when it fits your flow"; no schedule):
  - `push` to `main` with a path filter: `data/**`, `game/ai/**`, `game/sim/**` and `native/**`
    (the harness runs native, §1). A merge that changes none of them starts no run, so no
    "unchanged `main`" check is needed;
  - `workflow_dispatch`, so the lead can start it by hand, with inputs `suite` (`balance`, `gate`,
    `custom`), `ref` (default `main`), and for `custom` `levels`, `scenarios`, `matches`,
    `seed_start`.
  - It never runs on `pull_request`, is never a required check and never blocks a PR.
  - **Batching by concurrency:** one workflow-level `concurrency` group,
    `balance-${{ github.ref }}-${{ inputs.suite || 'balance' }}`, with `cancel-in-progress: true`.
    A `push` run has no inputs, so it and a manual `balance` run share the group: a burst of merges
    collapses to one completed run on the newest commit. A manual `gate` or `custom` run has its
    own group, so a merge never cancels it.
- **Jobs and permissions** (the workflow's top level grants nothing; each job names its own):
  - `build` (`contents: read`): Godot and the native library through the existing scripts,
    uploaded once as an artifact.
  - `shards` (`contents: read`; a matrix; 30-minute timeout): each shard runs
    `run-sim-smoke.sh --matches M --seed-start S --levels A,B --scenarios K --report
    build/balance/<set>-<A>-<B>-<S>.json`.
  - `summarise` (`contents: read`): `balance-summary.sh` per set; one artifact
    `balance-<date>-<sha>` with each set's JSON and markdown (kept 90 days).
  - `post` (`issues: write`, **checks out nothing and runs no repository code**): downloads the
    markdown artifact and runs `gh issue comment` on the open issue labelled `balance`, one comment
    with a block per set and the ref and SHA at its top. Only `push` runs and `balance` or `gate`
    runs on `main` post; a `custom` run, or any run on another ref, keeps its result as the
    artifact only (the tuning PR links it).
- **Sets and shards** (`push` and `suite=balance`):

  | Set | Levels | Scenarios | Seeds | Shards |
  | --- | --- | --- | --- | --- |
  | tuning set | `normal,normal` | `cross` | 1-100 | 4 x 25 |
  | ladder Easy | `easy,normal` and `normal,easy` | `cross` | 1-10 each | 2 x 10 |
  | ladder Hard | `hard,normal` and `normal,hard` | `cross` | 1-10 each | 2 x 10 |
  | mirrors | `normal,normal` | `fossil-mirror`, `renew-mirror` | 1-20 each | 2 x 20 |
  | baseline | `easy,dummy` and `dummy,easy` | `cross` | 1-5 each | 2 x 5 |

  Each set is summarised on its own; a ladder's or the baseline's two halves merge (unordered
  pair). `gate` runs §6's held-out set only.
- **No open `balance` issue:** the `post` job fails and says so (CLAUDE.md: say what is missing, no
  work-around). The lead opens the issue and the label once (P190's acceptance).
- **Cost** (estimate): about 190 matches at 5-10 s each on native, so 20-35 runner minutes per run,
  one run per merge that touches the filtered paths (fewer when merges come close together and a
  newer one cancels the older). P190 reads the real figure from the first runs.
- `tests/project/test_ci_workflow.gd` pins the triggers, each job's permissions, that `post` has
  no checkout step, the script calls, the shard table and that no seed of the `balance` sets
  reaches 1000 (release-engineer's suite).

Note (2026-11-09, P26bi docs, from the reviews of P190):
- **No `ref` input.** `workflow_dispatch` takes `suite` and `custom`'s set inputs only. A run plays
  the commit it is dispatched on: an "after" run (§8) is dispatched from the PR's branch, and every
  job checks out that one commit, so one run never mixes commits. This keeps a branch's code and
  caches in that branch's scope, records the right `commit` in each report, and makes the
  concurrency group key on the tested branch, so two branches' `custom` runs never cancel each
  other (two on one branch still do, so they run one after the other).
- **Guards:** `suite=gate` runs only on `main`, checked before any checkout; `post` runs only on
  `main` and never for `custom`. A `custom` run refuses seeds 1000-1100 (the balance sets end below
  1000 and the gate plays 1001-1100) and more than 200 matches.
- **`build`** uploads the native library only; the shard and summarise jobs install Godot from the
  cache. `post` finds the open issue labelled `balance` titled "Balance reports" and never creates
  it.
- **The gate rerun** of §6 is merged by hand: a `custom` run of seeds 1101-1200 with the gate's
  sets, then `balance-summary.sh --gate` over both runs' reports (the workflow's header). A later
  row may automate it.
- **Pins** live in `tests/project/test_ci_balance_workflow.gd` (`test_ci_workflow.gd` already holds
  gdlint's 20 public methods).

### 6. The Phase 4 gate run
- **Held-out seeds.** The balance run's tuning set (seeds 1-100) is what every tuning row is judged
  on, so the gate does not reuse it. The gate run is `suite=gate` on the `main` commit under test:
  100 Normal vs Normal matches, `cross`, **seeds 1001-1100**, which no balance run and no tuning row
  ever plays (P190's shard table and `test_ci_workflow.gd` keep the balance run below 1000). The
  gate run is a separate manual run (`workflow_dispatch`, `suite=gate`). Seeds 1001, 1003, ... put
  the Derrick League at the top and 1002, 1004, ... the Lumen Accord.
- **Checks** (the summary's `gate` block; every one must pass):
  1. each faction's win share is 400-600 per-mille (draws half);
  2. the top seat's win share is 400-600 per-mille;
  3. no timeout, and the longest match is at most 13 500 ticks;
  4. every unit type of both factions (twelve, tankers included) is "used": built in at least 50 of
     the 100 matches (answer 2 A);
  5. `dropped_commands` is 0 in every match;
  6. at least 95 distinct final hashes;
  7. `impl` is `native`, recorded.
- **Chance.** At a true 50 % a share of 100 matches has a standard deviation of 5 points, so a fair
  AI misses 40-60 % on one check about one time in twenty, and on check 1 or 2 about one time in
  ten. Michael's answer 1 A carries one fixed answer to that, decided before any run: a share of
  350-399 or 601-650 per-mille on check 1 or 2 gets **one** more run, seeds 1101-1200 on the same
  commit, and the 200 matches together decide against 400-600. Outside 350-650 the gate fails and
  tuning goes on. No other re-run.
- Michael's phone check follows the run (plan, "Gate procedure").

### 7. Determinism, proven headless
- A short AI-vs-AI match (2 700 ticks) twice from one seed gives the same record and the same
  checkpoint hashes (session, P188).
- Its replay, played without any AI, reaches the same checkpoints (`Replay.play`; ADR 0020 §3).
- The same match on the GDScript and the native implementation gives the same final hash (session,
  where the library is built; CI's verify).
- **The superweapon:** an `OpponentAi` on player 1 of `data/scenarios/dev_strikes.tres` (strike
  buildings with a short charge, P112d) fires each charged strike building within 900 ticks, drops
  nothing, and its replay matches (session, P188), since the 2 700-tick matches never reach a
  5-minute charge.
- The `determinism-arm64` job runs P188's suite too (the plan's exception 21), so x86_64 and arm64
  agree, strikes included.
- The harness's counting changes no hash (the state hash with and without it).
- The full-length cases (13 500 ticks, 100 seeds) run only in Actions.

Note (2026-11-09, P26bi docs, from the reviews of P188): "fires each charged strike building" is
read as each building of the computer's own strike type. The fossil computer fires its Deep Bore;
the Dusk Array fires only while a wave is in the field, after tick 4 050 on Normal, so P181's
hand-built suite covers it. The strike case owns its `strike_min_value` and charge, so tuning
cannot stop the shot, and its replay runs on the GDScript twin, so arm64 compares the two
implementations with a strike in the log. The arm64 check step requires the suite (the plan's
exception 21, widened to two lines).

### 8. The balance workflow
- **Data only, one number per pull request** (the skill; ai-dev). A tuning row names the number, its
  file, the flag it answers, the expected effect, and **the balance run (its commit) whose report
  it was judged on**. Nothing runs in a session; ai-dev reads the reports.
- **Before and after.** "Before" is that named run of `main`. "After" is either a `custom` run of
  the same sets on the PR's branch (`workflow_dispatch` with `ref`; artifact only, §5), or, when
  the lead batches, the balance run that the merge starts.
- **The lead's batching** (Michael, 2026-11-06: "only wait if it makes sense to gather something
  together"): when several small tuning PRs wait at once, the lead merges them together and lets
  one balance run report on all of them; that run is the "after" of each, and the batch's
  `docs/balance/<yyyy-mm-dd>-<topic>.md` lists the PRs and the run. With the concurrency group of
  §5, merges that land close together end in one run anyway.
- **Tuning moves no golden hash.** Plan row P171 gives the perf arena, the base arena and the
  controls test map (`controls_test.tres`) frozen copies of every def they load
  (`data/dev/arena/`: rules, units, buildings, weapons, factions), with the same numbers, type ids
  and roster order, so `golden_hex`, `bases_golden_hex`, `TICK_0_SEED_1`, the fog and targeting
  rigs and the `[sim]`/`[bases]` workloads stay as they are while `data/units/` moves. P171b points
  the sim suites' hand-built Worlds at the same copies and pins `RulesDef`'s script defaults to the
  frozen `data/dev/arena/rules.tres` instead of `data/rules.tres`, so a hand-built World keeps
  the frozen rules and a tuning row on `data/rules.tres` touches only that file and its literal in
  `test_defs_data.gd`.
- **What tuning still moves, on purpose:** the printed smoke and `perf_ai` hashes, and the suites
  that play the shipped Skirmish or read the shipped roster (the plan's exception 20 lists them).
  The `[ai]` ratchet (P189b) is calibrated by `test_ai_perf.gd` on frozen copies of the AI defs
  (`data/dev/arena/ai/`) and on `perf_ai.tres`'s frozen unit defs, so a data tuning row does not
  move its workload (the phone's Perf AI card keeps the shipped AI defs; it is report-only); an AI
  code row may, and a rise it causes is a qa-engineer PR with its reason, as for `[sim]`.
- **Pins:** a tuning row also updates the literal that pins its number under the plan's named
  exception 20; the owner of each file reviews.
- **Rule changes are not tuning:** artillery splash (ADR 0018 question 4), an artillery back-away
  rule (Phase 3 plan risks), pausing a strike's charge at low power (ADR 0023 §10), a blackout that
  stops a second producer (ADR 0023 §10's note) and a new field regrowth model (ADR 0023 §11) each
  need their own ADR and a gameplay-dev row. The plan lists them as conditional, not scheduled.
- **`docs/balance/`:** the first report (P191, box 4), the gate run's report, and the before and
  after of each tuning row or batch as `docs/balance/<yyyy-mm-dd>-<topic>.md`. The balance run
  itself writes no file in the repository; it comments and keeps its artifact.

## Consequences
- Every `verify.sh` plays three real matches; CI's verify grows by about a minute (estimate).
- A balance number can change without any golden hash or perf calibration moving.
- The gate is judged out of sample, on seeds the tuning never read.
- The report counts kills by "last shooter"; splash, ruptures and focus fire make it an estimate,
  which the markdown says.
- Actions minutes: about 20-35 per balance run, one run per merge that touches AI, balance or sim
  files, plus the lead's manual runs.
- The `balance-report` skill's lines changed with Michael's ja to ADR 0030 question 3 (P170b).

## Alternatives considered
- **Timeouts as draws:** would hide the "no match over 15 minutes" box. Rejected.
- **The gate on the balance run's seeds 1-100:** the same text as the last balance run, and in
  sample.
- **Same-faction mirrors as the gate set:** proves seat fairness and AI symmetry but not faction
  balance; kept as a set of the balance run (question 1's B, not chosen).
- **Per-type counters in the sim** (new hashed `stat_*` columns): would re-pin every golden and add
  sim work for a report; the events give the same counts outside the sim.
- **A Python merge script:** a second implementation of the summary; the GDScript one is tested by
  the same suites.
- **The balance run writing `docs/balance/` itself:** a bot commit or PR per run; comments and
  artifacts are enough until a human tunes.
- **Re-pinning the arenas on each tuning row** instead of freezing them: churn on every tuning PR
  and a ratchet calibrated on a moving workload.

## Questions for Michael (answered 2026-11-06: 1 A, 2 A, 3 A changed by the follow-up, 4 ja, 5 A)
The questions below are kept as they were asked, "nightly" included; the Acceptance note and §5
record what was decided.

1. **"Wins 40-60 % against the mirror AI".** **Answered: A.** Both sides play Normal. Recommended:
   **A**, because it checks that the two factions are even, which is the balance you will feel, and
   B still runs every night as a check.
   - A (chosen): the factions: on 100 new matches (each side starts at the top in half of them) the
     Derrick League and the Lumen Accord each win 40-60 %, and the top start wins 40-60 % too. A
     result of 35-39 % or 61-65 % gets one more run of 100 new matches, and the 200 decide; outside
     35-65 % it fails.
   - B (not chosen): the seat only: same-faction matches (League against League, Accord against
     Accord, 50 each); the top start wins 40-60 % in each; no re-run.
   - C (not chosen): both A's and B's checks, 200 matches, no re-run.
2. **"Every unit type is used".** **Answered: A.** Recommended: **A**, because B would mostly
   measure the mix the computer is told to build, not whether a unit is worth building.
   - A (chosen): each of the twelve unit types is built in at least half of the 100 gate matches; a
     type under 5 % of its side's production is flagged in the report.
   - B (not chosen): each type is at least 5 % of its side's production over the 100 matches.
3. **The nightly run.** **Answered: A, then changed by Michael's follow-up** (Acceptance note): on
   demand and after merges that change AI, balance or sim files; no schedule; renamed the balance
   run. Recommended:
   **A**, because a run on an unchanged `main` repeats the last one exactly and costs about 30
   minutes of GitHub's machines.
   - A (chosen for its sets; its schedule replaced by the follow-up): every night at 03:30 Danish
     winter time (02:30 UTC), only when `main` changed: the 100 tuning matches, Easy and Hard
     against Normal (20 each), the two same-faction mirrors (20 each) and Easy against the old dummy
     (10).
   - B (not chosen): every night, changed or not.
   - C (not chosen): only when started by hand.
4. **Who tunes.** **Answered: ja.** May ai-dev change one balance number per pull request in `data/`
   from the reports, merged after the lead's review, without asking you each time? You see every
   report on the `balance` issue and the gate run's report before the gate. (ja/nej; recommended:
   **ja**, because tuning takes many small steps and each one is checked on the same seeds.)
5. **Your phone check at the gate.** **Answered: A.** Six matches: Easy, Normal and Hard, each as
   both factions. Recommended: **A**, because Normal is the level the gate judges, and five minutes
   is enough to feel whether Easy and Hard are right.
   - A (chosen): play Normal to the end as each side; Easy and Hard may end with Surrender once you
     have the feel (after about 5 minutes).
   - B (not chosen): all six to the end.
