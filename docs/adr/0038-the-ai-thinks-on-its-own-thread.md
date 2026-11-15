# ADR 0038: The AI thinks on its own thread; its Commands land at T+1

**In short, for Michael:** the computer players stop thinking inside the sim's tick. The sim
hands each one a copy of what it may see at tick T, and the computer thinks on a thread of its
own while the sim goes on. Its orders take effect one tick later (67 ms), after yours. If the
computer is ever slower than one tick, the sim waits for it, so a match plays out exactly the same
on every phone, in the tests and in the web preview. The computer reacts 67 ms later, less than
a tap on the screen takes.

Status: **accepted, 2026-11-13** (Michael chose option 3 of the architect's AI lever memo in chat
the same day). He picked "AI on its own thread (Recommended)" from the lead's two-question card.
Written by the architect on branch
`claude/p26bw-levers` (base `main` at 99e1c6bd), with the plan rows P301-P304 and P304b in
`docs/plans/2026-11-09-air-and-tech.md`.

Supersedes:
- ADR 0020 §3's "where it runs: inside the tick job": that the controllers think in `TickJob.run`
  before `loop.step`, and that "the AI reads state N and its commands are stamped N, in both
  modes". The rest of ADR 0020 §3 stands: the human's Commands come first, every Command is
  stamped and recorded like a player's, `Replay.play` needs no AI, the scans of `game/ai`, and
  every driver that stands for the phone (`MatchRunner`, the smoke and the harness, `perf_ai`)
  plays the phone's path. The `tests/ai` rigs keep the lag-0 composition on purpose (§6).
- ADR 0030 §1's sentence "**The AI never sends a Command the sim drops** (`dropped_commands` stays
  0; ADR 0031's harness fails on any)", for the runs that play the shipped path (§6 below).
- ADR 0031's "a dropped Command fails the run" (§2's P26be note) and its gate check 5
  (`dropped_commands` is 0 in every match), for the same runs (§6).
- ADR 0031 §1's "Loop unchanged ... ADR 0020 §3's loop", §2's exit code 1 "a dropped Command"
  (now: drops over §6's bound) and §7's strike case "drops nothing", for the runs of §6.
- ADR 0020 §5's "`dropped_commands` stays 0" in a dummy-vs-dummy match, for the runs of §6. At lag
  0 it stands.

Amends by dated notes (the accepted text of each stays as it is): ADR 0012 (a status note on its
P68b notes), ADR 0020 (a status note on §3 and §5), ADR 0030 §4 (a note on §1 and §4), ADR 0031
(a status note on §1, §2, §6 and §7) and ADR 0036 §14 (a note on `perf_ai_4b`).

## Context
- **Where the time goes** (the memo of 2026-11-13, `main` 99e1c6bd). Each `OpponentAi` thinks every
  5 ticks and rotates three slots (ADR 0030 §2). With two computer players, 6 of every 15 ticks
  carry a think, and 2 of them (13 % of ticks) carry the ARMY slot. The sim job's p95 therefore sits
  on the ARMY-think ticks:
  - the step itself, about 4 ms (inferred: the p95 of about 10.2 ms minus the think);
  - the `PlayerView` and the ARMY think, about 6 ms (`ai_think_p95_ms` 5.6-6.1).

  That is why P198b's five slots cut the think by 1.3 ms but `sim_p95_ms` by only 0.14 ms: more
  ticks then carried a think.
- **The cards today.** After Phase 4b's merge wave 7 (`main` 99e1c6bd) Michael's three Perf AI
  cards read `sim_p95_ms` 10.27, 9.93 and 10.16, with `job_minus_step_p95_cp_ms` 3.35, 3.36 and
  3.85. The revisit trigger is 11 ms (the Phase 4 plan's P26bv note), the card's verdict 13.3 ms.
- **What P250-P300 add.** About 1,810 more lines of AI, +47 % on `game/ai`'s 3,816. About 1,000
  land in the ARMY slot (P251, P267, P295b, P300, parts of P250 and P283): new passes over own
  aircraft, medics and carriers, and two new searches (the raid target and the drop point, each
  against seen anti-air). Against P198's stage times (ARMY slot = view + refresh + army, about
  74 % of the think), the estimate is **+40 to +70 % on the ARMY slot, +2 to +3.5 ms**: a sim p95
  of about 12-13.5 ms in a match with air, over the 11 ms trigger and at the 13.3 ms verdict.
- **`perf_ai` cannot see it.** It runs on frozen pre-4b defs (`data/dev/arena/`: no aircraft,
  carriers or mines), so the card would show only about +0.5 ms of that work.
- **The options the memo put to Michael:**

  | Option | Sim p95 now (est.) | After P250-P300, air match (est.) | AI quality | Rows / lines | Needs | Risk |
  | --- | --- | --- | --- | --- | --- | --- |
  | 1a. Smaller caps (`target_tests_max` 512 to 256, `sectors_max` 64 to 32, `squads_max` 4 to 3) | ~9-9.5 (only where the caps bind) | 11-12.5 | worse targets, coarser scouting, smaller groups (Hard is hit most) | 1 row: data, re-pins, a balance run | nothing | the gain is eaten by P251/P267 |
  | 1b. The ARMY think every 3 s, not every 1 s | ~7.5 on paper | ~7.5 on paper | retreats, focus fire and raids run late; the spike stays (p99) | 1 row | a change to ADR 0030 | it games the p95 |
  | 2. The AI's hot loops in C++ with GDScript twins | 7.5-8 | 8-9 | unchanged | 5-7 rows, ~1,300-1,800 lines (~900 C++), plus ~+40 % on every later ARMY row | a new ADR and CLAUDE.md's Stack line | high: decision code that still changes, kept in lockstep twice |
  | **3. The AI on its own thread, its orders 1 tick (67 ms) later** | **~7-8** (the checkpoint ticks then set the p95: the step + 3.4-3.9) | **~7.5** (the AI grows on its own core, with 66 ms per tick) | +67 ms reaction | **4 rows, ~500 lines, no C++** | this ADR; no Stack change | medium: threads |

  Michael chose 3 on 2026-11-13. Option 2 stays in reserve; by these numbers it is not needed.
- **What holds today** (ADR 0012, ADR 0020 §3): `TickJob.run` calls `AiDriver.think_all(world,
  controllers, commands)` and then `loop.step`, on the worker in `WORKER` and inline in `SYNC`.
  `MatchLoop.step` stamps every Command of its list with the tick and the next `sequence`, in list
  order, and records it; `Sim.step` sorts by (tick, player, sequence).
- **`PlayerView` aliases World arrays.** `PlacementInput.of_world` hands out the World's own
  `terrain`, `terrain_buildable`, `move_cost`, `fog.explored`, `owner`, `type_index`, `pos_x`,
  `pos_y` and four type tables, and the view's row columns behind the getters (`_ids`, `_owner`,
  `_pos_x`, ...) are aliases too (ADR 0020 §1's P78 note). GDScript shares a packed array by
  reference on assignment (`rts-sim-conventions`), so a view that outlives its tick reads what the
  step writes. Only `duplicate()` gives a separate array, as `MatchSnapshot.capture` does for the
  main thread (ADR 0012 §3).
- **Cross-thread property access serializes** (ADR 0012 §2's measurement): `obj.prop` read in a
  loop while another thread does the same makes both 2-4 times slower; aliased typed locals keep
  their speed.

## Decision

### 1. The pipeline: the view at T, the Commands at T+1
For every tick T, the job (`TickJob.run`, on the sim worker in `WORKER`, inline in `SYNC`) does, in
this order:
1. **Collect.** If a batch of AI Commands was made from the views of tick T-1, the job waits until
   it is done (§3) and appends it to the tick's list, after the human's drained Commands. A batch
   is collected exactly once, in the job of the tick after its views.
2. **Views.** For every controller whose turn it is at T (ADR 0020 §2's turn test, unchanged), the
   job builds its `PlayerView` from the World as it stands before step T, in ascending player
   order, two of one player in list order: the order `AiDriver.think_all` uses today. A view holds
   no World array (§4).
3. **Hand-off.** The job hands the views and their controllers to the AI side as one batch:
   - in `WORKER`, to the AI thread (§2), which thinks while the job goes on;
   - in `SYNC`, the job runs the thinks itself, at once, and keeps the batch for the next tick.
4. **Step.** `loop.step` runs tick T with the list from step 1. `MatchLoop` stamps the collected
   batch (made from the views of T-1) with T and records it like a player's Commands, as today.

So the AI's Commands made from the state at tick T enter **step T+1**, after the human's Commands of
T+1, stamped T+1. At most one batch is in flight at any time. A tick with no controller due posts no
batch, and the next tick collects nothing.

- **The order inside a batch** is the order of the thinks (ascending player, then list order) and,
  inside one think, the order the controller appended them. `Sim.step`'s sort by (tick, player,
  sequence) is unchanged.
- **The end of a match, and a new one.** A batch collected when `match_end_tick` is above 0 is
  dropped by the job unsent: it is not stamped, not recorded and not counted. Nothing thinks once
  the match has ended, as before (ADR 0020 §2's P82 note). A batch belongs to the match whose World
  its views were built from. `MatchRunner.start()` waits for a batch in flight, as it waits for the
  job. It then drops that batch and any kept `SYNC` batch before it builds the new World. P301 tests
  it: a runner that ends a match with a batch pending and starts again (as `PerfHud.run_again()`
  does) plays the second match to the first one's checkpoint hashes. A batch dropped this way was
  already counted in its controllers' `commands`, so §6's C can hold one unsent batch per match;
  the bound tolerates that.
- **The think cadence is unchanged** (ADR 0030 §2): period 5, three slots, never a view on a
  checkpoint tick. The views are built on the job thread, so the rule still keeps their cost off
  the checkpoint steps. Player 4's batch (made on `tick % 5 == 3`) can land in a checkpoint step,
  which costs only the Commands.
- **`AiDriver`.** `think_all` stays as the lag-0 composition (views, then thinks, appended to the
  list the caller steps at once), for the `tests/ai` rigs (§6). P301 adds the two halves the job
  calls, building the views and running the thinks of a batch, and one small pure holder of the
  batch in `game/core` (no Node, no Resource; the walk of `tests/core/test_tick_job.gd` covers it).
  The names are P301's. P301 puts the lagged tick in one pure function of `AiDriver` (collect, the
  views, the thinks inline, keep the batch). `TickJob.run` in `SYNC`, `smoke_run.gd`,
  `ai_perf_run.gd` and `test_match_runner_ai.gd`'s headless loop all call it before
  `MatchLoop.step`. `TickJob` in `WORKER` differs only in handing step 3 to the AI thread.

### 2. The AI thread (`WORKER` only)
- `MatchRunner` starts the AI thread at the first `start()` that resolves `WORKER` with at least one
  controller, and keeps it across later `start()`s, as it keeps the sim worker. It hands work over
  with two semaphores, as ADR 0012 §1 does for the job (`ai_work`, `ai_done`). It is joined at
  `stop()` and on the runner's `PREDELETE`, after the sim worker. ADR 0012's thread life-cycle rules
  apply.
- **What it touches:** the controllers, the batch's views and the batch's Command list. It never
  reads the World, the loop, the replay, the probe or a snapshot. ADR 0020 §3's thread rules for
  `game/ai` (no Node, no autoload, no engine singleton, no clock) are unchanged.
- **The controllers belong to the AI thread while a batch is in flight.** No other thread reads a
  controller or its `AiMemory` then. The main thread reads them only after `wait_idle()`, which
  waits for the job and then for the batch in flight. Whoever takes `ai_done` first, `wait_idle()`
  or step 1 of §1, marks the batch done in the holder. Step 1 waits on `ai_done` only for a batch
  not marked done. P303 tests that order.
- **`SYNC` has no AI thread:** the web (no threads), every headless run, the suites and the perf
  harness. A `SYNC` run thinks inline in step 3 of §1. If the AI thread's `Thread.start()` fails,
  the thinks run inline in the job for the rest of the runner's life (step 3's `SYNC` branch), on
  the sim worker in `WORKER`. The sim worker is unaffected and the results are the same (§3). A
  test forces the failure: one warning, equal hashes.
- **The alias rule.** The AI thread runs GDScript beside the job and the main thread. A manager loop
  that reads `obj.prop` per row slows itself and every thread doing the same (Context). P303
  measures it on the card (§7); if it shows, a follow-up row applies `rts-sim-conventions`'
  "alias before the loop" rule to the ARMY slot's loops.

### 3. Waiting: the result never depends on timing
- In step 1 of §1 the job waits for the batch in flight, however long it takes. A slow AI makes
  the job late (ADR 0012's late tick); it never moves a Command to another tick and never skips
  one. So a run's Commands, stamps, records and hashes are a function of the seed and the human's
  Commands only, whatever the thread speeds.
- **`SYNC` equals `WORKER`:** the same match from the same seed and the same human Commands gives
  the same Commands, the same replay and the same hash at every checkpoint in both modes. P303
  proves it headless (§7).
- **Normal play never waits.** A batch has the rest of tick T, plus the job of T+1 up to step 1,
  about 66 ms of wall time at 15 Hz. The ARMY think is about 6 ms today and about 8-9.5 ms after
  P250-P300 (the memo's estimate), on a big core. On a little core it may run 2-3 times slower and
  still fit.

### 4. `PlayerView` holds no World array
- **Every array a view holds is its own**, a `duplicate()` made on the job thread in step 2 of §1,
  as `MatchSnapshot.capture` does for the main thread (ADR 0012 §3). That covers the row columns
  behind the getters, `columns()` (already copies, ADR 0020 §1's P198 note), the type tables and
  the placement input.
- **`PlacementInput.of_world` keeps its aliases** for its readers in the sim (`Production.gd:191`
  and `:232`), which read it at once on the job thread. `PlayerView` uses a copying builder
  instead. The name is P302's. `MatchSnapshot.placement_input()` is not changed.
- **The cost.** A `duplicate()` shares the buffer until the World's next write, which then copies
  it in the step, on the job thread. The arrays the snapshot copies anyway (`owner`, `type_index`,
  `pos_x`, `pos_y`, `hp`, ...) cost nothing more: the World copies once per write, however many
  readers share the old buffer. The rest (`terrain`, `move_cost`, `fog.explored` and the type
  tables) cost about 0.1-0.3 ms of copying per ECONOMY think (the memo), less when the step writes
  none of them.
- **The rule for later rows.** A new field of `PlayerView` is a copy or an int. A view or a column
  is dropped at the end of its think (ADR 0020 §1's P198 note, unchanged): held longer, it keeps a
  buffer the World has forked.
- **The poisoned-view test stays** (`tests/ai/test_ai_poisoned_view.gd`), and P302 adds the
  alias test: after `PlayerView.of`, a write to every World array the view was built from leaves
  every getter, `columns()`, `placement` and `is_explored` answering as before the write.

### 5. Replays and the record
- `Replay` and its format are unchanged. The AI's Commands are recorded with the stamp they are
  applied at (T+1), so `Replay.play` needs no AI and reproduces the run. A replay recorded before
  P301 still plays to its own hashes, because its stamps are data.
- `run-sim-smoke.sh` keeps its flags, its exit code numbers and report schema 2 (CLAUDE.md,
  Commands); exit code 1 now means drops over §6's bound.

### 6. Dropped Commands under the one-tick lag
A Command the AI checked against its view at T can be refused at T+1, because step T changed the
World under it: an `ATTACK` target that died or left sight, a tile that filled, credits spent.
The sim drops it and counts it in `dropped_commands`, as it does today for a human tap made on a
picture that is already one tick old. The sim's rules do not change. A stale drop heals at the next
think: a Command is dropped only when what it names is gone or blocked.
- **The AI's checks keep their rule, at its own tick.** ADR 0030 §1's rule now reads: every
  Command passes the sim's checks at the tick its view was built. The `tests/ai` suites prove that
  at lag 0: their rigs keep calling `AiDriver.think_all` and `loop.step` in the same tick, and their
  `dropped_commands == 0` assertions stay as they are.
- **The runs that play the shipped path** (the smoke, the balance and gate runs, `perf_ai`,
  `MatchRunner`, and the suites P301 moves onto the path, §8) count stale drops. A drop there
  fails the run only above a bound. A match fails when `dropped_commands > STALE_DROP_PERCENT * C /
  100` (integer division). C is the sum of its players' `commands`, the report's existing key;
  schema 2 is unchanged. `STALE_DROP_PERCENT` is 1, kept as one constant in
  `tests/smoke/smoke_run.gd`, which `balance_summary.gd` reads. A match of fewer than 100 Commands
  allows none. The summary's gate check 5 becomes "matches over the bound: 0". That replaces ADR
  0031's "a dropped Command fails the run" and its gate check 5. Fixed-seed suites do not use the
  bound: each pins its exact `dropped_commands` (the run is deterministic), so a new drop still
  fails there. The smoke still exits 1 over the bound and prints the seed, the tick of the first
  drop, and the match's drops and Commands.
- **The bound is provisional.** P301 reports the stale drops it measured on the smoke's three seeds
  and on P188's matches, Hard's included. If either rate is above half the bound, P301 stops and
  reports to the lead before it merges. The lead also reads the stale drops per set in §8's balance
  run, including the ladder Hard set. The lead confirms the 1 % or sets another value in a dated
  note after the balance run of §8, before the next gate run. A per-match count far above the
  measured rate means an AI bug, not staleness.

- **(2026-11-14, P301, the lead's decision) Expired and stale drops.** P301 measured every drop of
  the smoke's full matches (Hard seeds 1 and 2, Normal seed 1) at lag 1. Each drop is applied one
  tick after its view:

  | Command | Why it was dropped | Hard s1 | Hard s2 | Normal s1 | Kind |
  | --- | --- | --- | --- | --- | --- |
  | MOVE (one unit) | the unit died in the lag tick | 7 | 4 | 1 | expired |
  | ATTACK | the target died in the lag tick | 0 | 4 | 0 | expired |
  | ATTACK | the target lives, no unit of the group can hit it now | 1 | 1 | 0 | stale |
  | PLACE | credits spent between the view and the apply | 0 | 1 | 0 | stale |
  | Total (of 475, 515 and 366 Commands) | | 8 | 10 | 1 | |

  16 of the 19 are expired: the subject or the target died in the lag tick, which no check at T
  could know (a Command that was already invalid at its view tick would count as stale; the
  smoke subtracts the expired count of the batch's own view tick, and none of the 19 was). The
  bound is there to catch AI misbehaviour, so the bound is refined: **expired drops are not
  counted; stale drops (every other drop) must stay at or under `STALE_DROP_PERCENT`, 1 %.**
  Measured stale rate: Hard 1 of 475 (0.2 %) and 2 of 515 (0.4 %), Normal 0 of 366; so Hard is
  at most 0.4 %. The count is made outside the sim (no hashed state, no `World.Stat`):
  `smoke_run.gd`'s `expired_in()` reads the World before each step, for the unit orders (ATTACK_MOVE,
  MOVE, ATTACK, STOP) whose units are all gone and the ATTACKs whose target is gone, and the match
  record gains `expired_commands` (additive; schema 2 keeps its other keys). Stale = `dropped_commands`
  less `expired_commands`. The smoke prints both, the summary's gate check 5 counts the matches whose
  stale drops are over the bound, and `test_smoke_run.gd` pins the exact pairs (dropped, expired,
  Commands: Hard seed 1 8, 7, 475; Hard seed 2 10, 8, 515; Normal seed 1 1, 1, 366). The PLACE case
  goes to the P250 follow-up list. P188's matches (`test_ai_determinism`: Normal vs Hard, 2700 ticks,
  and the 900-tick strike match) drop 0 on the shipped path.

### 7. The card: `ai_wait`, the think and `perf_ai_4b`
- **`ai_wait`.** `MatchSnapshot` gets `ai_wait_usec`: the time step 1 of §1 blocked on the batch
  (0 when it was ready, when none was in flight, and always in `SYNC`). The card's report-only AI
  line (`PerfBases.AI_LINE`) gains `ai_wait_p95_ms`, `ai_wait_max_ms` and `ai_waits` (the ticks with
  a wait above 0), with no verdict. The line's pin test is re-made with them. In normal play the
  p95 should read 0.00. Above 0 it means the AI thread is starved or slower than a tick. The time
  waited is inside `job_usec`, so `sim_p95_ms` counts it honestly.
- **`think_usec`** keeps its meaning for the card and for `WATCH ai think` (views plus thinks, the
  sum wherever they ran). It is stamped into the snapshot of the tick that collects the batch (T+1)
  in both modes, so each batch counts once and `SYNC` and `WORKER` cards compare. A tick that
  collects nothing reads 0. The card can then be compared across P303. Because the thinks run off
  the job, `sim_p95_ms` no longer contains them, only the views.
- **`perf_ai_4b` (P304).** A second AI arena, `data/scenarios/perf_ai_4b.tres`, plays the base
  arena's layout with frozen copies of Phase 4b's unit defs in `data/dev/arena/`: aircraft,
  airfields, anti-air, the engineering centre and space centre, the transports and drone squads,
  and, as soon as P290 has merged, the ground carriers and minelayers (P304b). Each side gets those
  rows at tick 0, as `perf_ai.tres` spawns a charged strike building, so the ARMY slot's new passes
  run from the first think.
  - Its AI defs are copies of `perf_ai`'s frozen AI defs (P189b's early scout and wave) in their
    own folder, `data/dev/arena/ai_4b/`. `data/dev/arena/ai/` and `test_frozen_ai_defs.gd` stay as
    they are.
  - It shares `perf_air`'s frozen unit defs (P253) where both need the same type.
  - Every later AI row that adds an `OpponentDef` or `AiDifficultyDef` field also sets it in the
    `ai_4b` copies (the shipped Normal value), in the same PR. A test compares the field names of
    the `ai_4b` copies with the shipped defs (the names, not the values).
  - The arena has no golden pair (as `perf_ai`): its hash is printed, not pinned.
  - From P304's merge, the per-wave Perf AI card (the Phase 4 plan's P26bu note) runs on
    `perf_ai_4b`, three times, and the 11 ms and 5 ms triggers read it. `perf_ai` keeps its CI
    suite and its printed hash. The lead may run both arenas.

### 8. Rows, re-pins and the balance run
- **P301: orders at T+1, in `SYNC`, with the re-pin.** The pipeline of §1 and the batch holder;
  `TickJob`, `MatchRunner` (`SYNC` only), `tests/smoke/smoke_run.gd` and
  `tests/perf/support/ai_perf_run.gd` move onto it, so the phone, the smoke and `perf_ai` play the
  same path. §6's bound in the smoke and in the summary's gate check. **Exception 26** (the next
  free number) covers its pins and only these:
  - the printed `perf_ai` hash and flow line;
  - the smoke's printed hashes;
  - `test_ai_perf.gd`'s contact ticks in its header;
  - every fixed-seed pin, `dropped_commands` assertion or Command-log pin in a suite that plays a
    computer player through `smoke_run.gd`, `ai_perf_run.gd`, `MatchRunner` or `TickJob`:
    `tests/ai/test_ai_determinism.gd`, `tests/perf/test_ai_perf.gd`,
    `tests/smoke/test_smoke_run.gd`, `tests/core/test_match_runner_ai.gd`,
    `tests/core/test_tick_job.gd`, `tests/ui/test_skirmish_routes.gd`,
    `tests/ui/test_level_choice.gd`;
  - check 5's label and values where the summary and the smoke pin them:
    `tests/smoke/test_balance_summary.gd`, `test_balance_summary_entry.gd`, `test_smoke_entry.gd`,
    `fixtures/balance_summary_golden.md`, `tests/project/test_run_sim_smoke_script.gd`.

  Each changed line is named in the PR. A suite outside this list that moves stops the row and goes
  to the lead.

  P301 also updates the comments that state a think's stamp (`PlayerView.gd`'s `row_ready_tick`
  doc, "`tick + 1` for a think at `view.tick`", and `AiStrikes.gd:128-130`): at lag 1 the stamp is
  `view.tick + 2`. The charge and offline checks are monotone, so the old `+ 1` stays safe.

  `golden_hex`, `bases_golden_hex` and `TICK_0_SEED_1` play no AI and must not move: P301 asserts
  them unchanged. Step 3 of "Merge order of the shared rows" (no other row re-pins a golden)
  therefore holds.
- **P302: a view with no World alias** (§4), with the alias test. Hash-neutral: no pin moves.
- **P303: the AI thread** (§2), `ai_wait` (§7), and the `SYNC` = `WORKER` hash test:
  - `tests/core`: one `MatchRunner` with two `OpponentAi` plays the same seed for at least 900
    ticks, once in `SYNC` and once in `WORKER` with the AI thread. Both give equal Command logs and
    equal checkpoint hashes.
  - A second case forces waits with a test controller in `tests/` that delays its think by more than
    one tick. It reads `ai_wait_usec` above 0 and gives the same hashes as `SYNC`.
  - It is a thread test, so it runs 3 times in a row before the push (CLAUDE.md, Token budget).
  - The thread life cycle: no `WARNING` at stop and free; the thinks inline on a failed start; the
    `ai_done` order of §2; a restart with a batch pending (§1).
- **P304 and P304b: `perf_ai_4b`** (§7), the second for the ground carriers and minelayers.
- **Owners of the card and route lines.** P303 edits `PerfBases.AI_LINE` and the card's keys, and
  P304 the Perf AI route (`DevRoutes.gd`, `perf_arena.gd`, `tests/ui/test_perf_ai.gd`). Those are
  touch-ux-dev's files (P184, P185): touch-ux-dev reviews those lines in both rows.
- **The balance run.** After P301 merges, the lead runs the balance workflow once on `main`
  (`workflow_dispatch`; P301 changes no file under `data/`). It compares the win shares and match
  lengths with the last run, which no tuning should need, and reads the stale drops for §6's bound.
  The run happens in GitHub Actions, never in a session.
- **Order.** P301 -> P302 -> P303. P303 needs both: the thread may hold a view only once the view
  holds no alias. P301-P303 merge before P251. They touch `game/core`, `AiDriver` and `PlayerView`,
  not the managers, so P250 and P252 do not wait for them. P304 waits for its frozen data rows (§7)
  and need not block P251; P304b follows P290. (This deviates from the memo, which put R4 before
  P251: P304 waits for P253 and part 2's P264. Until it merges, P251's cost shows only in
  `ai_wait`.)

### 9. Proof (what is proven headless)
- Lag 0: the `tests/ai` suites, unchanged, with `dropped_commands == 0`.
- Lag 1 in `SYNC`: the smoke, `test_ai_determinism` (twice from one seed, the GDScript twin, a
  replay without AI to the same checkpoints) and `perf_ai`'s bounds, all on the shipped path.
- `SYNC` = `WORKER`: P303's suite.
- No alias: P302's suite and the poisoned-view test.
- The order inside a step: a `tests/core` case where a human Command and an AI Command of one
  player land in one tick, in the order of §1.
- Not provable headless: the phone's `ai_wait`, the contention of §2 and the cards; Michael's card
  runs after each merge wave cover them.

## Consequences
- The AI's think leaves the sim job. The job keeps the views (about 0.1-0.3 ms more per ECONOMY
  think for the copies). The estimate is `sim_p95_ms` about 7-8 ms now and about 7.5 ms after
  P250-P300. The checkpoint ticks then set the p95: the step + 3.4-3.9 ms.
- The AI reacts one tick (67 ms) later than today. Its own reaction delay is a slot round (15 ticks,
  ADR 0030 §2) plus `reaction_ticks`, so 1 tick more changes no behaviour a player can see. It may
  change match outcomes slightly, so the balance run of §8 follows.
- A third thread runs on the phone in a match with a computer player. Its CPU time is the think
  time it already used, now beside the sim rather than inside it.
- `game/ai`'s cost no longer adds to `sim_p95_ms` while it fits in a tick. The card's `ai_wait`
  line watches that. So ADR 0030 §4's budget per think keeps its counted bounds, but its time stops
  being the sim's p95.
- **Phase 5's save and resume** (ADR 0030 §3's note on `AiMemory`) must also write the batch in
  flight, or save only at a tick that collects nothing and builds no view. Otherwise a resumed match
  applies one batch fewer than the uninterrupted run and diverges.
- One re-pin under exception 26, no golden moves, no `STATE_FORMAT` change, no new Command, no data
  change. ADR 0012's hand-off, publish rule and gate are unchanged; the job gains §1's steps and
  the snapshot one field (§7).
- **CLAUDE.md.** No line changes. The Stack section stays as it is: no C++ for the AI, no new
  language. Architecture rule 4 (Commands only) and rule 3 (randomness only via `DetRandom`) hold
  unchanged. The `game/core` line ("no game rules") holds: the batch holder has no rule.
- **Wording outside CLAUDE.md that needs Michael's yes** (the lead asks, after P303 has merged):
  - `.claude/agents/ai-dev.md`, the bullet "AI code reads the match only through `PlayerView` ...".
    Replace "and runs inside the tick job through `AiDriver.think_all` before `loop.step` (on
    the sim worker thread in WORKER mode)" with "and thinks on a `PlayerView` built at tick T: on
    its own thread in WORKER mode, inline in SYNC; its Commands enter step T+1 after the human's
    (ADR 0038)".
  - `rts-sim-conventions`, the **AI** bullet. Replace "`AiDriver.think_all` calls the controllers
    inside the tick job before `loop.step`, so their Commands are stamped and recorded like a
    player's." with "The job builds each due controller's `PlayerView` at tick T, holding copies
    only; the controllers think on the AI thread (inline in `SYNC`), and their Commands enter step
    T+1 after the human's, stamped and recorded like a player's. The job waits for a late batch, so
    `SYNC` and `WORKER` hash alike (ADR 0038)."
  - `rts-sim-conventions`, "Threading (ADR 0012 §2)". Add the bullet "- The AI thread (ADR 0038)
    touches only the controllers, their views and the batch's Commands, never the World. New loops
    in `game/ai` alias before the loop; existing ones are converted only by a row that the card's
    contention calls for (ADR 0038 §2)."

## Alternatives considered
- **1a, smaller caps:** cheap, but they cost target quality on Hard, and P251 and P267 eat the gain.
- **1b, a slower ARMY slot:** it lowers the p95 by spreading the cost, not by removing it. The spike
  stays in the p99, and retreats and focus fire act late.
- **2, C++ kernels for the AI's hot loops:** the same p95 for 3-4 times the lines. It opens
  CLAUDE.md's Stack line, and decision code that still changes would be kept in two languages.
  Kept in reserve.
- **The AI on the main thread** (ADR 0012's first plan): its cost would land in the main thread's
  publish-frame p95 (ADR 0020's Context).
- **The thinks at lag 0 on a thread, joined before the step:** no gain. The step would wait for the
  whole think on every think tick.
- **A lag of more than one tick:** more slack the AI does not need (§3), and slower reactions.
- **Filtering stale AI Commands before the sim:** it needs a check of the sim's rules outside
  `game/sim`, or a second view at T+1 on the job thread. The first breaks "no game rules" in
  `game/core`; the second gives back the time this ADR saves.
- **The sim accepting a stale Command as a no-op:** a sim rule change. It would also hide bad human
  Commands, and it would move `dropped_commands`, which the hash covers (ADR 0007 §5's P26o note).
