# ADR 0016: What a checkpoint costs on the worker job, and how to bring it under the watch line

Status: accepted, 2026-10-22 (Michael: 1 ja, 2 A, 3 ja, 4 ja). Proposed 2026-10-22 (the lead's
gate issue #157). Docs PR "ADR 0016". This ADR does not hold the Phase 2 gate: the gate's
verdicts pass, and the line it is about is a watch line, not a verdict (ADR 0013 §15).

## Acceptance note (2026-10-22)
Michael answered the four questions at the end in chat on 2026-10-22, verbatim "Ja dine
anbefalinger" (yes to the lead's recommendations), which the lead records as "1 ja, 2 A, 3 ja,
4 ja":
1. **ja:** `fog.visible` leaves the state hash in P65. The golden hashes change once, re-pinned
   under the plan's new exception 10 (§3), and `World.STATE_FORMAT` becomes 2.
2. **A:** the watch line stays 3.325 ms (25 % of `sim_p95_ms` 13.3) on both halves,
   `job_minus_step_p95_cp_ms` and `job_minus_step_p95_noncp_ms`. It stays a watch line without a
   verdict, as ADR 0013 §15 has it.
3. **ja:** P65 waits until Michael has confirmed the Phase 2 gate (issue #157), so the gate is
   judged against today's golden hashes. P65q changes no hash and may land before.
4. **ja:** if the first gate card after P65 is still above the line, the lead adds P66 and P66b
   without asking again. P67 is then decided from P66b's card in a dated status note here.

The decision below is unchanged by the acceptance; only review fixes to its wording were made
before it. The rows are in `docs/plans/2026-10-11-phase-2.md`, "Amendment (ADR 0016)", and
exception 10 is in that plan's "File ownership". Nothing here is applied in code yet: P65q and
P65 apply it.

Code facts are from `main` at 80c4006. Byte counts come from a headless scratch probe on that
commit (GDScript phases, seed 42, the perf arena, 900 ticks through `MatchLoop`; it counted bytes
and read no clock). Its checkpoint hashes at ticks 150, 450 and 900 equal `golden_hex` in
`data/dev/perf_gate.tres`, so it played the gate's run. The probe was deleted afterwards.

## Context

### The line and what the gate phone measured
ADR 0013 §15's engine-side watch line: `job_minus_step_p95_cp_ms` and
`job_minus_step_p95_noncp_ms` should each stay at or below 25 % of `sim_p95_ms`. `sim_p95_ms` is
13.3 in `perf_gate.tres`, so the line is 3.325 ms (§15 writes "3.3 ms"). Above it, §15 names
three remedies, each through its own ADR and never a port row: fewer copied arrays (ADR 0012
§3), fewer hashed bytes, or a longer `CHECKPOINT_PERIOD` (ADR 0007).

The Phase 2 gate runs (Pixel 9a, release template, `WORKER`, `NATIVE`, perf arena seed 42, 150
units, 900 ticks; issue #157 gives runs 1, 3 and 4):

| Key (ms) | Run 1 | Run 3 | Run 4 | Gate limit |
|---|---|---|---|---|
| `job_minus_step_p95_cp_ms` | 3.325 | 3.587 | 3.411 | watch line 3.325 |
| `job_minus_step_p95_noncp_ms` | 0.752 | 0.771 | 0.772 | watch line 3.325 |
| `job_p95_ms` (`sim_p95_ms` verdict) | 5.834 | 5.988 | 5.577 | 13.3 |
| `job_p95_noncp_ms` | 5.366 | 5.41 | 5.368 | - |
| `job_mean_ms` | 3.070 | 2.992 | 2.991 | - |
| `job_p99_ms` | 7.341 | 7.302 | 7.050 | 26.7 |
| `job_max_ms` | 13.905 | 16.952 | 12.992 | - |

Run 3 is 0.26 ms and run 4 0.09 ms above the line. Run 1 sits exactly on 3.325 ms: it meets "at
or below 25 %" and misses the rounded 3.3. (Run 4's gate verdict failed `heavy_frames_min`
because the camera had been panned; its sim and job numbers are unaffected.) The non-checkpoint half is far below on both.

CI (x86_64 runner, P49a's `WATCH sim job_minus_step impl=native` line, 11 calibration runs, 60
checkpoint ticks and 840 others each): `job_minus_step_p95_cp_ms` 0.200-0.415 (median 0.335),
`job_minus_step_p95_noncp_ms` 0.028-0.055 (median 0.043).

### Where a checkpoint runs (code on main)
- `MatchLoop.step` (`game/sim/MatchLoop.gd`) runs `ScenarioOrders.collect`, stamps and records
  the commands (only when there are any), calls `Sim.step`, and then, when
  `world.tick % Replay.CHECKPOINT_PERIOD == 0` (`Replay.CHECKPOINT_PERIOD` is 15), sets
  `last_hash = world.state_hash()` and calls `replay.add_checkpoint(world.tick, last_hash)`.
- `TickJob.run` (`game/core/TickJob.gd`) reads the clock into `started`, calls `loop.step`, sets
  `out.last_hash`, calls `out.capture(world, previous)`, copies the `TimingProbe`'s `phase_usec`,
  and sets `job_usec = end_usec - started`.
- `StepProbe.step_usec` runs from `begin()` to the last `mark()` inside `Sim.step`, so it leaves
  the hash out (its header says so).
- `PerfHud.record_snapshot` files `job_ms - step_usec / 1000.0` under checkpoint ticks when
  `snap.tick % Replay.CHECKPOINT_PERIOD == 0`, else under the others.
- `Sim.step` gives `FlowCache.run` a budget of 0 when
  `(world.tick + 1) % Replay.CHECKPOINT_PERIOD == 0` (ADR 0012 §5: no flow slice on hash ticks).
  The period therefore also decides which ticks skip flow work, so it shapes the match itself.

**Inside `job_usec - step_usec`:** the orders and stamping around `Sim.step`, the probes' own
calls, `state_hash()` on checkpoint ticks, `MatchSnapshot.capture` and the `phase_usec` copy.
**Outside `job_usec`:** the hand-off and the publish on the main thread, and the buffer copies
that `capture`'s `duplicate()` defers. `MatchSnapshot.gd` says capture is "O(1); the World's
next write copies the buffer", so those copies land in the next tick's `Sim.step`, inside
`step_usec`.

### What `state_hash()` does per checkpoint (`game/sim/World.gd`)
SHA-256 through `HashingContext` (`_start_hash`, `HASH_SHA256`) over 24 sections
(`ROW_ARRAYS.size() + HASH_OTHER_SECTIONS`, 20 + 4) fed as 26 blocks, since the projectile and fog
sections feed two blocks each. `_feed` puts a 16-byte `[tag, size]` before each block. The first 8
digest bytes are the hash.

Bytes fed at the perf arena (64x64 map, 2 players, `max_projectiles` 512, `rng.state()` 4 ints):

| Section | Tick 15 (150 rows) | Tick 900 (71 rows) | Built in GDScript by |
|---|---|---|---|
| header: `STATE_FORMAT`, 9 `HASHED_SCALARS`, `rng.state()`, as int64 | 112 | 112 | 9 `get()`, one array |
| map: the cached digest (rebuilt only when `map_version` moves) | 8 | 8 | - |
| 20 `ROW_ARRAYS` columns, int32 per row | 12,000 | 5,680 | `get()` + `to_byte_array()` copy each |
| projectiles: 10 ints per live slot, then `proj_free[0, proj_free_top)` | 2,048 | 2,156 | two walks over all 512 slots |
| fog `visible`: int32 per cell and player | 32,768 | 32,768 | `to_byte_array()` copy |
| fog `explored`: one byte per cell and player | 8,192 | 8,192 | passed as is (no copy) |
| block headers, 26 x 16 | 416 | 416 | 26 new `PackedInt64Array` |
| **Total** | **55,544** | **49,332** | |

Over the 60 checkpoints the total is 49,260 to 56,040 bytes; live projectiles peak at 28. The
fog is 40,960 bytes, 73-83 % of each checkpoint, and `visible` alone is 58-67 %. ADR 0007 §8's
P31b status note found the same on the VM: "Most of the cost is the fog".

### What `MatchSnapshot.capture` does on every published tick (`game/core/MatchSnapshot.gd`)
26 `duplicate()` calls (8 row columns, 7 type and weapon tables, 5 projectile columns,
`terrain`, the 3 `ID_LISTS`, `events`, `stats`) and `world.fog.copy_into(fog)`, which duplicates
every Packed array of `FogGrid.HASHED` and `UNHASHED`. All of these are O(1). Real work in
GDScript: `_fill_target_rows` (one `bsearch` per row), and `_align_prev` (a walk over the rows)
when `rows_version` changed. The fog arrays the next tick writes (32,768 bytes of `visible`, 8,192
each of `explored` and `listed`, 8,192 of `dirty`), and every row and projectile column it writes,
are then copied by that write, inside `step_usec`.

### The lead's reading, checked
- **"Non-checkpoint ticks pay the snapshot capture only."** Mostly. They pay capture, the GDScript
  around `Sim.step` and the probe calls. Capture's buffer copies fall in the next `step_usec`, not
  in this line. So "fewer copied arrays" (§15's first remedy) mostly lowers `step_usec`, not either
  half of the watch line.
- **"The hash costs about 2.6-2.8 ms at p95."** The checkpoint and non-checkpoint p95s differ by
  2.573 ms (run 1) and 2.816 ms (run 3). A difference of two p95s estimates the hash's cost; it is
  not the hash's own p95, which nothing measures. On CI the same difference is 0.292 ms (medians),
  so the phone-to-CI ratio is 8.8-9.6. That is near the native ratios in `perf_gate.tres`
  (`ci_ratio_native_mean` 11.1, `ci_ratio_native_p95` 12.1), not the GDScript ones (4.4, 5.9). This is why §15's
  1.7-2.2 ms estimate (380 µs times 4.4-5.9) came out low. The ratio hints that engine C++ (the
  digest) dominates on the phone, but it does not prove it: nothing splits the digest from
  `state_hash`'s GDScript block building.
- **"A longer `CHECKPOINT_PERIOD` lowers how often, not the per-checkpoint p95."** Correct (§1(d)).
- **"Phase 3 adds hashed state."** Correct in direction. ADR 0010 §1 already says the per-player
  last-seen memory "will live inside `FogGrid` and be hashed". Every int32 grid per cell adds
  16,384 bytes per checkpoint on a 64x64 map (4,096 cells x 4 bytes), times the players when it is
  kept per player.
- **ADR 0013 §15's premise.** It says capture and `state_hash` "already run in the engine's C++,
  so a port cannot speed them up". That holds for the digest and the `duplicate()` calls only. The
  blocks the digest reads are built in GDScript.

## Decision

### 1. The options, judged
The watch-line number is the per-checkpoint p95 of `job_usec - step_usec`.

| Option | Lowers the watch-line number? | Hash and golden values | PR size |
|---|---|---|---|
| (a) Fewer bytes: leave out `fog.visible` | Yes, by an amount nobody has measured | Change once (`STATE_FORMAT` 2) | small |
| (b) MD5 or SHA-1 through `HashingContext` | Only the digest's share; unmeasured | Change once | tiny |
| (b') Our own 64-bit hash, GDScript and C++ | GDScript: no, slower; C++: see (e) | Change | medium |
| (c) Hash off the job, after publish | Yes, to about the non-checkpoint level | Unchanged | large, 2-3 PRs |
| (c2) Spread the hash over the period | Yes, but every other tick pays a share | 1: unchanged; 2: change | large |
| (d) Longer `CHECKPOINT_PERIOD` | **No** | Change (the flow skip moves) | tiny |
| (e) Native state hash, GDScript twin | Only the GDScript share; unmeasured | Unchanged if the bytes stay | about one port |
| (f) Change the line itself | The yardstick moves, not the cost | Unchanged | docs |

**(a) Hash fewer bytes.** `fog.visible` is derived state. By `FogUpdate`'s contract, `fog_cell`
is the cell last stamped, a row's mask is its type index (or the pad mask), and `remove_dead`
unstamps dying rows. So each count is the number of a player's live rows whose disc, stamped at
`fog_cell`, covers the cell. Those inputs are all hashed (`owner`, `type_index`, `fog_cell` in
`ROW_ARRAYS`), and the sight tables are in `defs_hash`. `explored` is history, not derived, and
stays. Leaving `visible` out:
- cuts the bytes per checkpoint to 16,476-23,256 (25 blocks: the fog section feeds one), and
  drops the largest `to_byte_array()` copy;
- costs one bump of `STATE_FORMAT` to 2 and a single re-pin;
- changes nothing on x86_64, arm64 or the web: same algorithm, same little-endian bytes,
  `state_hash` has no native version (the GDScript function builds the blocks on every target,
  and the engine's `HashingContext` digests them), and ADR 0013 is not touched;
- has no main-thread cost.

What it gives up: a `visible` bug that never reaches a row stops showing in the checkpoint hash.
Three things keep it covered:
- the kernel locksteps already compare it, through `StateDiff`'s full state
  (`tests/sim/native/test_fog_lockstep.gd`);
- `NativeKernels.self_check` compares only `state_hash()`, so it gains a direct `visible`
  comparison;
- a new derivation test rebuilds the counts from the rows at every checkpoint of the arena.

The p95 drop is not predictable from the code. The per-call costs stay (25 of the 26 blocks, the
1,024-iteration projectile walk); only the byte-proportional share falls, by 58-67 %. The line
needs at least 0.26 ms off run 3.

**(b) A cheaper digest.** `HashingContext` offers `HASH_MD5`, `HASH_SHA1` and `HASH_SHA256`: the
same engine code on every target, so the cross-platform result is unchanged. Collision strength
does not matter here: the hash detects desyncs, not attacks, and only 64 bits are kept. Whether
MD5 or SHA-1 is faster than SHA-256 in the engine's arm64 build is not measured here. It lowers
only the digest's share, so it is worth a re-pin only after a measurement says the digest
dominates.

**(b') Our own 64-bit hash.** In GDScript, this is a VM loop over 49,260-56,040 bytes (one step
per byte or per int) every checkpoint. That is slower than the engine digest on the web path and
in the GDScript twin that (e) would keep. It is only worth having inside (e).

**(c) Hash off the job.** The published snapshot cannot be hashed as it is: it carries only the
COPIED columns. `goal_x`, `goal_y`, the `nav_*` columns, `cooldown`, `proj_target`, `proj_free`,
`rng.state()` and most hashed scalars are not in it. So a checkpoint tick would need a second
O(1) capture of every hashed array. The digest would then run off the job:
- on the main thread, it is out: ADR 0014's `work_p95_ms` (5.6) and hitch rules;
- `WorkerThreadPool` measured worse than the dedicated thread (ADR 0012 Context);
- on the sim worker after `done.post()`, it is outside `job_usec` but still on the worker's
  timeline.

The hash values do not change, if the deferred and the synchronous paths run the same function
on the same copy. But `MatchLoop` is the one tick driver (ADR 0007 §9): `Replay.play` checks
`loop.last_hash` right after each step, and the runner would need a deferred path. Two code paths
for one checkpoint is the drift ADR 0007 §9 exists to prevent, and the snapshot would need the
hash's own tick. The line would be met by moving the cost out of the measured window, not by
removing it. The flow skip of ADR 0012 §5 would lose its reason, and dropping it would change the
run. Worth it only if checkpoint ticks ever threaten the sim verdicts themselves.

**(c2) Spread the hash over the period.** Two forms:
1. On the checkpoint tick, take an O(1) copy-on-write capture of every hashed array (as above),
   then feed one or two of the 24 sections per tick on the job and finish before the next
   checkpoint. The checkpoint keeps its meaning and its values, so nothing is re-pinned. The
   checkpoint half falls toward the non-checkpoint level, but each of the 14 ticks between pays
   on average about 1/14 of the hash (0.18-0.20 ms from the 2.573-2.816 ms estimate), and more on
   the tick that feeds the fog, which is 73-83 % of the bytes, unless that block is sliced too.
   The next tick's writes copy the captured columns the snapshot does not hold, inside
   `step_usec`. `MatchLoop` and `Replay.play` would get the hash up to 14 ticks late, while
   `Replay.play` compares `loop.last_hash` right after the step, and the last tick of a run must
   still hash at once: the deferred second path ADR 0007 §9 exists to prevent.
2. Hash the live state in parts, one part per tick on the job, and finish on the checkpoint tick.
   The path stays synchronous and single, but the checkpoint mixes ticks: it no longer equals
   `state_hash()` of the World at its tick (which `NativeKernels.self_check` and the hash tests
   use), the values change and are re-pinned (exception 10), and a mismatch can no longer be
   recomputed from one saved state.

Both spread the cost rather than remove it, raise every tick's floor, and leave the flow skip
without its reason. Rejected for the same reasons as (c).

**(d) A longer `CHECKPOINT_PERIOD`.** This **does not lower the watch-line number**: each
checkpoint hashes the same bytes. It changes how often the cost comes, and which ticks
`Sim.step` runs without a flow slice. That changes the arena run, so it is a re-pin under the
plan's exception 3. The golden ticks 150-900 stay checkpoints for a period of 30, 75 or 150. A
replay finds a desync up to one period later. One side effect: at 30, checkpoint ticks are 30 of
900 (3.3 %), under the 5 % a p95 ignores, so `job_p95_ms` would stop landing on them. That lowers
the `sim_p95_ms` reading, not this line.

**(e) A native state hash with a GDScript twin.** ADR 0013 §6 bans Godot API inside a kernel, so
a kernel cannot call `HashingContext`. It would need its own C++ SHA-256 (from FIPS 180-4) that
feeds the same bytes in the same order, with today's `state_hash()` as the twin and the web path.
- The hash values stay bit-identical, so nothing is re-pinned.
- It removes the GDScript block building, but its digest is not known to beat the engine's.
- ADR 0013 §1 lists `state_hash` as GDScript-only, and §15 says "never a port row". So it needs
  its own ADR and a kernel row with locksteps, the sanitizer and the twin rule (§5).
- It has no main-thread cost.
- It is only worth doing if a measurement shows the GDScript share dominates.

**(f) The line itself.** The 25 % share is the same for a cost paid on every tick and one paid on 1
tick in 15. The gate's own sim verdict already reads checkpoint ticks:
- they are 60 of 900 ticks (6.7 %, more than the 5 % a p95 ignores; ADR 0013 §15's own reason
  for the split), and `job_p95_ms` reads them: it is 0.21-0.58 ms above `job_p95_noncp_ms` on
  runs 1, 3 and 4;
- it passes with room: at most 5.988 against 13.3;
- the cost is on the worker, about once a second, against a 66.7 ms tick (`late_ticks` 0).

So the checkpoint half is an early warning for growth, not a pacing risk today. Raising it to 50 %
(6.65 ms), or replacing it with CI's count of hashed bytes, are defensible choices. Which one is
Michael's decision (question 2); this ADR does not make it.

### 2. Recommendation
Do (a), because the fog's counts are most of the bytes fed every checkpoint, and they are derived
from state that stays hashed. It is the smallest change that lowers the watch-line number: one
re-pin, no change of algorithm, no new code path, no ADR 0013 exception, and the web path gains
too. Before it, add CI's deterministic byte count, so Phase 3's growth shows up in every PR's log
rather than on the next phone card. Keep (b), (e) and a measurement behind the next card. Reject
(c), (c2) and (d) for now. Keep the line as written unless Michael picks otherwise (question 2).

### 3. PRs and order
P-numbers continue the shared sequence: the portrait plan holds P59-P64, so the next free number
is P65. The rows go into the Phase 2 plan's PR table, after its Gate row (P65 waits for the
gate, answer 3); they extend P49a's and P50a2's keys.

| Row | Owner | Size (production lines) | Depends | What |
|---|---|---|---|---|
| P65q | qa-engineer | 0 (about 80 test lines) | - | The `WATCH sim job_minus_step` line, or a sibling `WATCH sim hash_bytes`, prints the bytes `state_hash` feeds per checkpoint: min and max over the run. Test code counts the exact byte stream `state_hash` feeds (every section's blocks plus each block's 16-byte tag and size header) and proves the count by rebuilding that stream and checking that its SHA-256 gives `world.state_hash()` (the first 8 digest bytes, `decode_s64(0)`) at the checkpoints. No clock, no production code. Report-only, like P49a's watch lines. Lands first, so P65's drop shows in CI. |
| P65 | gameplay-dev | about 40-60 (tests about 150) | P65q; Michael's confirmation of the Phase 2 gate (issue #157; answer 3) | `FogGrid.HASHED` becomes `[&"explored"]` and `visible` joins `UNHASHED`; `World.STATE_FORMAT` 2; the doc comments of `state_hash` and `hash_section_names` (the `"fog"` section keeps its name). `NativeKernels.self_check` (`game/core/NativeKernels.gd`, the lead's file, under exception 10) compares `fog.visible` as well. New test: at every checkpoint of the seed-42 arena, and in the fog lockstep's crafted cases, counts rebuilt from `owner`, `type_index` and `fog_cell` equal `fog.visible`. Re-pins under exception 10, which also lets it change the fog line of `rts-sim-conventions`' "Determinism checks" to `fog.explored`. Touches `native/`, so it gets the native checklist and its mutants. |
| P66 (conditional) | lead | about 50 | P65's card | Only if the first card after P65 is above the line. `TickJob` reads the clock after `loop.step` and after `capture`. The snapshot gains `loop_usec` and `capture_usec` beside `step_usec`. |
| P66b (conditional) | touch-ux-dev | about 110 | P66 | The card and `summary()` print `loop_minus_step_p95_cp_ms`, `loop_minus_step_p95_noncp_ms` and `capture_p95_ms`, with no verdict. Their cp-minus-noncp difference estimates the hash's cost (a difference of two p95s, as in Context). P66 cannot split that estimate further: `state_hash` lives in `game/sim`, which reads no clock. So `PerfHud.run_preflight` (main thread, no job, before the run, beside the `ref_peak` burst) also times `HashingContext` with `HASH_SHA256`, `HASH_MD5` and `HASH_SHA1` over one `PackedByteArray` as large as P65q's maximum byte count, and the card prints `digest_sha256_us`, `digest_md5_us` and `digest_sha1_us`, with no verdict. |
| P67 (conditional) | decided in a status note here | - | P66b's card | Digest share: the preflight's SHA-256 time; GDScript share: P66b's hash estimate minus it (the block building and the per-block `update()` calls). Both are estimates: the probe runs on the main thread over one buffer, not on the worker over 25 blocks. If the digest dominates: (b), MD5 or SHA-1 by the probe's times, as a one-constant change plus a re-pin under exception 10. If the GDScript share dominates: (e), through its own ADR. |

**Exception 10** (new, a named one-line exception like 1-9 of the plan). A PR that changes the
state hash's layout or algorithm re-pins, with a note saying why:
- `golden_hex` in `data/dev/perf_gate.tres` (`golden_ticks` stays);
- `TICK_0_SEED_1` in `tests/sim/test_world_hash.gd`, with its history comment;
- the `STATE_FORMAT` pin in `tests/sim/test_world_v1.gd`;
- `KNOWN_FORMATS` in `native/sim_kernels/sanitizer/dump.h`, which
  `tests/project/test_ci_workflow.gd` requires to know `World.STATE_FORMAT`.

The owner of each file reviews its line. P65, the first such PR, also changes two of the lead's
files, and the lead reviews them: `game/core/NativeKernels.gd`, whose `self_check` compares
`fog.visible` as well as `state_hash()` (with its case in the lead's
`tests/core/test_native_kernels.gd`), and the fog line of
`.claude/skills/rts-sim-conventions/SKILL.md`'s "Determinism checks", which then names
`fog.explored` only. Exception 3's run-outcome pins (`ALIVE_END_PIN`,
`PROJ_PEAK_PIN`) do not move, because the run does not change. No replay is stored before Phase 5
(ADR 0007 §9 "Storage"), so none breaks.

### 4. What the next gate card must show
On each of the three runs, at the commit after P65:
- `job_minus_step_p95_cp_ms` at or below the line Michael keeps (3.325 ms under answer 2A);
- `job_minus_step_p95_noncp_ms` at or below 3.325 ms (0.77 today);
- `golden_hashes: PASS` against the re-pinned list;
- `impl: PASS`, with a self-check that now compares `visible`;
- every verdict that passes today still passing.

CI's P65q line shows the byte drop (at most 23,256 per checkpoint at the arena). If the
checkpoint half is still above the line, P66 and P66b follow (question 4).

## Consequences
- The checkpoint hash no longer covers the fog's counts directly. The kernel locksteps (full
  state), the self-check (with `visible`) and the derivation test cover them. ADR 0010's
  consequence "a fog divergence is caught like any other" holds for `explored` and, through the
  rows, for everything a count changes.
- Every hash printed before P65 differs from those after it. `STATE_FORMAT` 2 marks the change.
- Phase 3 state that is derived (caches, counts rebuilt from rows) stays out of the hash by the
  same rule: hash the state a rebuild starts from, and prove the rebuild with a test. State that
  is history (the last-seen memory, ore left, credits) is hashed.
- CI shows hashed-byte growth on every PR (P65q), before a phone card does.
- §15's "fewer copied arrays" remedy is recorded as acting mostly on `step_usec`, and its "a port
  cannot speed them up" as true only for the digest and the `duplicate()` calls: the blocks the
  digest reads are built in GDScript (Context).

## Alternatives considered
- **(c) Hash after publish.** Rejected for now: the largest change, a second checkpoint path
  beside `MatchLoop`, and the cost moves rather than shrinks. Revisit if checkpoint ticks approach
  `sim_p95_ms` or `job_p99_ms`.
- **(c2) Spread the hash over the period.** Rejected: it spreads the cost onto every tick, and
  either delays the checkpoint (a second path) or changes what a checkpoint means.
- **(d) A longer `CHECKPOINT_PERIOD`.** Rejected: it leaves the watch-line number as it is,
  changes the run (the flow skip) and coarsens the replay check.
- **(b) and (e) now.** Deferred: choosing between them needs P66b's digest probe beside the P66
  split, and (b) would cost a second re-pin.
- **(b') A GDScript 64-bit hash.** Rejected: in GDScript, which (e)'s twin and the web path would
  run, it is slower than the engine digest.
- **Bit-packing `explored` in the hash.** Rejected for now: it saves 7,168 bytes of digest input
  but needs a GDScript loop over 8,192 cells per checkpoint, and nothing has measured which of
  the two costs more.
- **Do nothing.** Possible under answer 2C; then P65q still lands, as Phase 3's early warning.

## On acceptance
Done 2026-10-22 with the acceptance; the notes record decisions that P65 will apply, not done
facts. The skill's fog line is P65's (exception 10).
- `docs/plans/2026-10-11-phase-2.md`: an "Amendment (ADR 0016)" section with rows P65q, P65,
  P66, P66b and P67 as in §3, and exception 10 after exception 9.
- ADR 0007 §8: a dated status note (`FogGrid.HASHED` is `[explored]`, `STATE_FORMAT` 2, why
  `visible` is out, the derivation test).
- ADR 0010 §1 and Consequences: a dated status note on the hashed fog arrays.
- ADR 0013 §15: a dated status note with Michael's answer to question 2, the two corrections in
  "Consequences", and that a native hash, if ever, comes by its own ADR.
- `.claude/skills/rts-sim-conventions/SKILL.md`, "Determinism checks": the rule "derived state
  stays out of the hash, with a rebuild test". The fog line says `explored` only from P65 on.
- No `docs/ROADMAP.md` box and no `CLAUDE.md` line changes.

## Questions for Michael
1. The fog's visibility counts are about 60 % of the bytes hashed every second, and they can be
   rebuilt from the units, which stay in the hash. Do you accept leaving them out (P65), which
   changes the six golden hashes once? (ja/nej)
2. The watch line is an early warning, not a gate verdict: the gate's own sim limit (job p95
   13.3 ms) is met with more than twice the margin (5.6-6.0 ms on the gate phone). Which rule
   for checkpoint ticks? A: keep 3.325 ms (25 % of 13.3; run 1 sat exactly on it, runs 3 and 4
   were 0.09-0.26 ms above). B: 6.65 ms on checkpoint ticks only. C: drop the checkpoint half
   and watch the hashed-byte count in CI instead.
3. P65 changes the golden hashes that the gate card compares against. Should it wait until you
   have confirmed the Phase 2 gate? (ja/nej)
4. P66 and P66b only add timing numbers to the card, so the next step can be chosen from
   measurements. If the first card after P65 is still above the line, may the lead add them
   without asking you again? (ja/nej)
