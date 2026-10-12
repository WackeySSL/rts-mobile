# ADR 0012: Sim tick on a worker thread, the view snapshot, and the revised performance gate

Status: proposed, 2026-10-12 (Michael asked for it: "ok ADR 0012"). When accepted, it supersedes
in part:
- ADR 0011 §1 (what the view reads), §2 (where the prev positions live), §3 (the z list), §5 (the
  meaning and values of `work_p95_ms` and `sim_p95_ms` in its acceptance note, and the debug-APK
  margin) and §6 step 4 (adopted here);
- ADR 0008 §3 (the flow-slice budget and the starting `flow_cells_per_tick`);
- ADR 0007 §6 (where the runner's per-tick work runs).

It keeps Michael's answer 1 (the gate runs on his phone with k = 2.5) and CLAUDE.md rule 6.

## Context
The Phase 2 plan (P26s) says that a contract the phone probe contradicts changes through a new ADR
before P34 starts. The probe ran on 2026-10-12. The full reports are comments on PR #35.

**Gate phone:** Google Pixel 9a (2025 mid-range, Tensor G4), Android, 2424x1080, 60 Hz. The probe
ran as a debug export, in 60 s runs, with the mock tick and the flow slice inside the frame:

| Mode | On time (<= 17.5 ms) | Draw calls | Render CPU mean / p95 | Work p95, tick frames / other frames | Mock tick mean / p95 | Flow slice (512 cells) mean / p95 |
| --- | --- | --- | --- | --- | --- | --- |
| 1: sprite rings, tints grouped by team | 83.5 % (repeat 83.2 %) | 13 | 1.53 / 1.94 ms | 20.62 / 4.64 ms | 10.96 / 15.33 ms (repeat 11.12 / 15.38) | 3.57 / 4.39 ms |
| 2: Phase 1 code-drawn rings | 80.6 % | 462 | 4.06 / 5.14 ms | 20.02 / 7.33 ms | 8.77 / 12.51 ms | 3.41 / 4.24 ms |
| 3: sprite rings, tints alternating by row | 84.3 % | 161 | 2.07 / 2.54 ms | 20.93 / 5.17 ms | 10.86 / 15.24 ms | 3.64 / 4.54 ms |

The fog patch cost 0.29 ms mean (0.37 ms p95). In the four runs, the slowest tick took 1.13 to
1.76 times the p95 tick.

**CI side** (GitHub runner, `godot --headless`, `tests/perf/probe_tick.gd`, min of 3 runs): mock
tick 2.51 ms mean, 3.36 ms p95; flow slice of 512 cells 1.10 ms mean, 1.13 ms p95. The
phone-to-CI ratio is 4.4 (tick mean), 4.6 (tick p95) and 3.2 (flow slice mean).

**What the probe contradicts:**
- **ADR 0011 §5 and its acceptance note (budget and gate).** The gate phone runs this GDScript
  about 4.4 times slower than CI, not at about the cloud VM's speed. The 15 Hz tick runs inside a
  frame, so every tick frame misses its deadline (20.6 ms p95), and only 83.5 % of frames are on
  time against the 95 % required. The mock tick alone is about five times the sim limit (15.3 ms
  p95 against `sim_p95_ms` 3.2 ms). The frames without a tick are fine (4.64 ms p95).
- **ADR 0008 §3 (flow slice budget).** At 0.2 ms per slice on the gate phone, a slice would hold
  about 28 cells. A 64x64 field would then take about 140 ticks (about 10 s), which is
  unworkable.
- **ADR 0011 §3, in part (team-tint batching).** When the team tints alternate row by row, the
  draw calls rise from 13 to 161, above the 60-call ceiling, while render CPU rises only by about
  0.5 ms. Phase 3 production appends rows in time order, so mode 3 is what a real match looks
  like.
- **Confirmed:** ring sprites (13 calls against 462), atlas quads, rect health bars, and the fog
  patch.

A release-template build of the probe is being produced. Its numbers are not available yet, so
this ADR names the two data values that the release run sets (§4) and makes no decision wait for
it.

**Facts verified for this ADR** (Godot 4.7.2, 2026-10-12, scratch projects on the cloud VM):
- **Packed arrays are references in GDScript.** After `b = a`, a write through `b` changes `a`.
  `duplicate()` is a lazy copy-on-write: it took 0.13 µs for a 4 MB array, and the first write
  to either side afterwards paid the copy (2.5 ms for 4 MB), on the thread that writes.
- **Hand-off:** a dedicated `Thread` with two `Semaphore`s works (`post`, `wait`, `try_wait`;
  `try_wait` returns false while nothing was posted). In 2000 hand-offs, the main thread read a
  published duplicate while the worker wrote the source array: no crash, and every value was
  right. One post-and-wait round trip costs about 40 µs.
- **Feature checks:** `OS.has_feature("threads")` is true on desktop headless, and
  `DisplayServer.get_name()` returns `"headless"`. The web preset has
  `variant/thread_support=false` (`export_presets.cfg`).
- **An unjoined `Thread` only warns.** Freeing a `Thread` that was never joined prints a
  `WARNING`, not an `ERROR`, so the log scan of `verify.sh` (`SCRIPT ERROR|^ERROR:|Parse Error`)
  does not catch it.
- **Godot does not guard Node access from a worker.** Writing a Node2D's `name` and `position`
  from another thread logged nothing headless. Any guard against it must be structural.
- **The shared pool is limited.** The setting `threading/worker_pool/low_priority_thread_ratio`
  exists: the shared `WorkerThreadPool` gives low-priority tasks only part of the pool, and every
  task id must be waited on.
- **Draw calls under Compatibility** (Mesa llvmpipe with Xvfb, so the counts are reliable and the
  times are not), for 150 sprites at one absolute z:

  | Sprites at the same z | Draw calls |
  | --- | --- |
  | one texture, one tint | 1 |
  | one texture, tints alternating | 150 |
  | three textures interleaved (mixed unit types) | 150 |
  | the same three textures, one z per texture | 3 |
  | alternating tints, one z per tint | 2 |

  The probe drew tank art only, so mixed unit types were never measured on the phone. The
  mechanism is the same as for the tints.
- **Colour inside one `_draw()` does not break batches.** In the probe, the bars alternated two
  fill colours per item and the effects varied their alpha, and both stayed inside the 13 calls
  of mode 1.

**Options considered:**
- **Slice the tick across the four frames of its period** (one thread, so the web would gain
  too). Rejected: the tick's phases depend on each other in order and differ in cost, every sim
  module would have to become resumable, and the view would need a snapshot anyway. A quarter of
  the probe's tick (about 4 ms) on top of 4.6 ms of view work still misses 5.6 ms.
- **Run the phases of one tick in parallel on the pool.** Rejected for now: it puts the order of
  writes at risk, and the order is what determinism depends on.
- **Move rigs to MultiMesh (ADR 0011 §6 step 3).** Not needed: the render side passes.
- **GDExtension (C++) for the hot phases.** Not adopted now (§7).

## Decision

### 1. The sim tick runs on a worker thread (Android and desktop)
- **Owner:** `MatchRunner` (`game/core`). It gets `enum TickMode { SYNC = 0, WORKER = 1, AUTO = 2 }`
  and `@export var tick_mode: TickMode = TickMode.SYNC`. At `start()`, `AUTO` resolves to
  `WORKER` when `OS.has_feature("threads")` is true, `OS.has_feature("web")` is false and
  `DisplayServer.get_name()` is not `"headless"`; otherwise it resolves to `SYNC`. The pure
  `static func resolve_mode(mode: int, threads: bool, web: bool, headless: bool) -> int` is
  tested as a table. `main.tscn` and `perf_arena.tscn` set `AUTO` only once every view reader
  uses the snapshot (§3; plan P50b).
- **Worker:** one dedicated `Thread` per runner, created for the first job. It runs
  `TickJob.serve()`: wait on the `work` semaphore, return if `quit` is set, run one job, post the
  `done` semaphore, and repeat. Priority is normal. It is not the `WorkerThreadPool`, which is
  shared with engine tasks, limits low-priority tasks, and needs a waited task id for every tick.
- **Hand-off:** the two semaphores are the only synchronisation, and they also give the memory
  ordering. The main thread starts a job with `work.post()`. It polls with `done.try_wait()` and
  blocks on `done.wait()` only inside `wait_idle()`, `start()`, `run_ticks()` and the stop.
- **Ownership:** from the `work.post()` that starts a job to the `done` that ends it, the worker
  owns:
  - the World;
  - the `MatchLoop` and its `Replay`;
  - the probe and the command list;
  - the back snapshot.

  In that window the main thread touches none of them. It reads only the front snapshot and the
  runner fields set at publish. Outside the window the main thread owns everything.
- **One job is exactly one tick:** `MatchLoop.step(world, commands, probe)` (stamping, the
  record, `Sim.step` and the checkpoint every 15 ticks), then `back.capture(world, front)` (§3),
  then the timings. Two jobs never run at once, and a job never runs two ticks.
- **One tick ahead.** At each tick boundary of the runner's clock, the main thread does, in this
  order:
  1. **Publish.** If the job is done, it swaps back and front, sets the published runner fields
     (`last_hash`, `last_tick_usec`, `last_runner_tick_usec`) and emits `ticked(tick)`.
  2. **Drain.** It drains `CommandQueue` into the command list. `MatchLoop` stamps the commands
     with the tick the job will step.
  3. **Start.** It posts the next job.

  State N is therefore computed during the period before it is shown. During
  `[T_N, T_N+1)` the view interpolates from the prev positions to state N, as in `SYNC`, so the
  picture's timing does not change.
- **Command latency:**
  - A command submitted inside a `ticked(N)` handler is stamped N in both modes. The Phase 4 AI
    acts there, so AI-vs-AI runs are equal in both modes.
  - A command from touch input between two boundaries lands one tick later in `WORKER` than in
    `SYNC`: 66.7 ms more input latency. Move and target markers still show at once.
  - Determinism is unaffected, because the replay records the stamped ticks.
- **A late job.** If the job is not done at a boundary, the runner holds:
  - it publishes nothing and starts no job;
  - `alpha()` stays at 1.0, so the view shows the newest state;
  - the clock stops at the boundary, so the time spent waiting is dropped, not caught up later;
  - `late_ticks` increments once for the held tick, and `late_usec_max` records the longest
    hold.

  Every frame then polls `try_wait()`. The first frame that sees the job done publishes it and
  starts the next job, and the clock's next tick counts from that frame. `_process` never blocks.
  Commands keep queuing in `CommandQueue` meanwhile, and none is dropped.
- **Catch-up:** in `WORKER` mode at most one publish happens per frame. Backlog beyond
  `max_catch_up_ticks` is dropped, as in `SYNC`.
- **Refill:** while the runner runs (not paused) with no job in flight, after `start()`,
  `run_ticks()`, a pause or an application resume, the next `_process` posts a job at once. It
  does not wait for a boundary.
- **Synchronous mode:** the same `TickJob.run()` runs inline on the main thread at the boundary
  and publishes at once. It is used:
  - by every headless test (`AUTO` resolves to `SYNC` headless). The runner's own worker tests
    (plan P38w) are the one exception: they set `WORKER` explicitly;
  - by `run_ticks(n)`, always inline. It first waits for the job in flight and publishes it,
    which counts as the first of the n ticks, so the published tick always advances by exactly
    n;
  - by `Replay.play` and `tests/perf`, which drive `MatchLoop` directly with no runner;
  - by the web build. Threads are off in the web preset, so the web preview keeps the in-frame
    tick and its hitches. The APK is the gate.
- **`wait_idle()`** blocks until no job is in flight. The finished job stays unpublished until
  the next boundary or `run_ticks()`. Tests and tools call it before they read `runner.world`,
  `runner.replay` or `runner.loop` in `WORKER` mode.
- **Stop.** `start()` waits for the job in flight and discards it. `_exit_tree()` sets `quit`,
  posts `work` and calls `wait_to_finish()`. `func worker_active() -> bool` lets tests prove the
  join, because an unjoined thread only warns.
- **Pause** (`paused` or an application pause): the job in flight finishes, and nothing publishes
  until the clock runs again.

### 2. Thread-safety rules for the sim
The sim stays free of Node, SceneTree, autoloads, Input, rendering, OS time and frame delta
(CLAUDE.md rule 1). That is what makes `Sim.step` safe to run on a worker. It also needs these
rules:
- **No shared mutable statics:** no `static var` in `game/sim`. Constants are read-only and safe
  from any thread.
- **No signals:** no `signal`, `.emit(` or `call_deferred(` in `game/sim`. Signals are emitted
  only on the main thread (`ticked`, at publish).
- **No Resources in the tick:** no Resource load, read or write inside `Sim.step` or
  `MatchLoop.step`. `World.from_scenario` copies the defs into World arrays on the main thread,
  before any job.
- **Only the job's objects:** every object a job touches is reachable from the World, the
  `MatchLoop`, the probe, the command list or the back snapshot. `TickJob` holds no Node; a test
  checks its property list.
- **No main-thread access during a job** to the World, the loop, the replay, the probe, the
  command list or the back snapshot (§1, ownership).
- **A published snapshot is never written**, by either thread.
- **Commands change hands once.** A submitted `Command` belongs to the runner from then on.
  Nobody reads or writes it afterwards, except through the replay after `wait_idle()`.

`tests/project/test_sim_purity.gd` (qa) bans `static var`, `signal `, `.emit(` and
`call_deferred(` in `game/sim`.

Determinism and replays do not change: the thread changes when a tick runs, not what it computes.
The golden hashes (seed and scenario orders, no human commands) are equal in both modes, and a
test proves it.

### 3. What the view reads: `MatchSnapshot`
- **`game/core/MatchSnapshot.gd`**, a pure `RefCounted` with no Node. It holds the view's copy of
  one tick:
  - **header:** `match_serial`, `tick`, `rows_version`, `map_version`, `last_hash`, and the row
    count;
  - **rows:** `unit_id`, `owner`, `type_index`, `pos_x`, `pos_y`, `hp`, `order` and `target`,
    each with exactly `unit_count()` entries;
  - **prev positions:** `prev_pos_x` and `prev_pos_y`, aligned to this snapshot's rows;
  - **type and weapon tables:** the ones ADR 0011 §1 lists;
  - **projectiles:** `proj_id`, `proj_owner`, `proj_weapon`, `proj_x` and `proj_y`, plus
    `prev_proj_id`, `prev_proj_x` and `prev_proj_y`;
  - **map:** `map_cols`, `map_rows`, `terrain` and `terrain_ids`;
  - **fog:** `fog: FogGrid`;
  - **runtime:** `events` and `stats` of this tick;
  - **timings:** `phase_usec` (a copy of the `TimingProbe`'s), `step_usec` (`Sim.step`) and
    `job_usec` (the whole job, wall clock on the thread that ran it).

  Methods: `unit_count()`, `index_of(id)` (binary search over the ascending ids) and
  `capture(world: World, previous: MatchSnapshot) -> void`.
- **Copies:** `capture` takes every array with `duplicate()`. That costs O(1); the real copy
  happens on the worker's first write in the next tick, at about 0.6 ns per byte. The fog uses
  `FogGrid.copy_into(dst: FogGrid)` (gameplay-dev, P32), which duplicates the grid's arrays and
  scalars, so the snapshot answers every FogGrid read method.
- **Prev positions:**
  - When `rows_version` is unchanged, `prev_pos_*` are the previous snapshot's `pos_*` (the same
    buffers, which nobody writes).
  - When it changed, a merge walk by id (on the worker, ADR 0011 §2): a survivor keeps its old
    position, a new row starts at its current position, and a dead row is dropped.
  - Projectiles: the `prev_proj_*` arrays are the previous snapshot's arrays. A layer treats a
    slot whose `proj_id` differs from `prev_proj_id` as new and draws it at its current position.
- **Double buffer:** the front snapshot is read by the main thread, and the back snapshot is
  written by the job. Publishing swaps them. Each runner has two snapshot objects, and each
  capture reassigns the back's arrays.
- **View rules** (they replace the first bullet of ADR 0011 §1):
  - Production code in `game/view`, `game/input` and `game/ui` reads only `runner.snapshot`,
    `runner.alpha()`, `runner.match_serial` and the published runner fields. It never reads
    `runner.world`.
  - The two rules of ADR 0011 §1 stay: no reference to a snapshot array across frames, and a
    restart is detected through `match_serial`.
  - `events` are read only inside `ticked`.
  - Tests may read and write `runner.world` in `SYNC` mode, or after `wait_idle()`.
  - A scan in P52 rejects `.world` in those three folders.
- **Allocation:** each tick makes a fixed number of small allocations outside `game/sim` (one
  per snapshot array), never one per row or per cell. The `Performance.OBJECT_COUNT` checks of
  the view stay valid, because packed arrays are not Objects. A memory test in P38w checks that
  `MEMORY_STATIC` stays flat over 900 ticks.

### 4. Gate and budget (replaces ADR 0011's acceptance-note values where the probe contradicts them)
**Gate runs** use the release-template perf APK (plan P51r) in `WORKER` mode, three runs in a
row, on Michael's phone.

| Field | Value | Rule |
| --- | --- | --- |
| `heavy_rigs` | 135 | unchanged |
| `heavy_frames_min` | 600 | unchanged; not divided |
| `on_time_ms` | 17.5 | unchanged; not divided |
| `on_time_share_pct` | 95 | unchanged: over the run and over the heavy window |
| `work_p95_ms` | 5.6 | 14 ms on a 2021 phone / 2.5, as before. **New meaning:** p95 of the main thread's frame work (process plus render CPU) over **all** frames of the heavy window, with the sim on the worker. A frame that publishes is one frame in four, so its extra cost (swap, `ticked` handlers) lands inside the p95 |
| `sim_p95_ms` | 13.3 | **New meaning:** p95 of the worker job (`job_usec`: `MatchLoop.step` plus the capture, wall clock on the worker), on the release template. The 2021 limit is 33.3 ms, half the 66.7 ms period; divided by k = 2.5 |
| `late_ticks_max` | 0 | **new:** no held tick in the whole run |
| `fog_update_p95_ms` | 0.4 | unchanged (ADR 0010 §2; it runs on the main thread in `ticked`) |
| `draw_calls_max` | 60 | unchanged; not divided |
| `release_only` | true | **new:** a card from a debug template shows the verdict line `build: FAIL (debug template)`, so `GATE: FAIL` |
| `ci_ratio` | 4.4 | **new, provisional:** the phone-to-CI ratio of the mock tick means (debug run); set from the release run |

**The period margin.** On a 2021 phone (k = 2.5), a p95 tick then takes at most 33.3 ms. The other
33.3 ms of the period (a factor 2) covers:
- ticks above the p95 (in the probe the slowest tick took up to 1.8 times the p95);
- the worker running on a slower core;
- heat.

The withdrawn debug-APK margin of ADR 0011 §5 is replaced by this explicit margin.

**CI budget.** The ADR 0011 §4 rule is unchanged, with the new inputs:
- the `budget.cfg` `p95_ms` ceiling is `sim_p95_ms / ci_ratio` = 13.3 / 4.4 = **3.0 ms**;
- the mean ceiling is that ceiling times the calibration's ratio of mean to p95;
- `mean_ms` starts at no more than 4.0 ms;
- the floor is 1.5 times the worst min-of-3 seen in calibration.

The CI mock tick alone (3.36 ms p95) is already above 3.0 ms, so with the debug ratio the real
tick will probably miss. The release ratio decides this. If P49's calibration floor is above the
ceiling while `ci_ratio` is still the provisional 4.4, the lead asks Michael for the release run
before P49 merges. Nobody raises the ceiling for any other reason.

**Early warning.** From P38p on, each sim PR's `PERF` line gives a gate-phone estimate: its p95
times `ci_ratio`. The lead compares it with 13.3 ms in review, and a PR whose estimate passes it
starts the remedy order (ADR 0011 §6) then, not at the gate.

**Set by the release run** (data values with a value now; nothing waits for them):
- `ci_ratio` in `data/dev/perf_gate.tres`: the release mock-tick mean on the phone divided by the
  CI mean (2.51 ms), rounded up to one decimal. The lead sets it in a one-value PR (plan,
  exception 5). If P49 has merged, the same PR moves `budget.cfg` to the new ceiling, and
  qa-engineer reviews those lines.
- `flow_cells_per_tick` in `data/rules.tres` (§5): gameplay-dev's one-value PR. After P49 it
  re-pins the golden hashes under the plan's exception 3.

No gate threshold waits for the release run: each one follows from k, the 2021 limits and the
period.

### 5. Flow fields on the worker
- **Slice budget:** about 2 ms on the gate phone (release template), which is 5 ms on a 2021 phone
  with k = 2.5. That is 15 % of the job's 13.3 ms. It replaces the 0.2 ms of ADR 0008 §3.
- **Rule:** `flow_cells_per_tick = floor(512 x 2.0 / slice_mean_ms / 64) x 64`, clamped to
  64..1024. `slice_mean_ms` is the mean cost of a 512-cell slice. The mean is used, not the p95,
  because the work per cell is fixed; the scheduler's noise is judged by the job's p95.
- **Now (debug run):** 512 x 2.0 / 3.57 = 286.8, so the value is **256**. The release run
  re-derives it with the same rule.
- **Completion:** the arena map has 3980 open cells, so a field completes in 16 ticks (about
  1.1 s) at 256, against 8 ticks at 512. An order that needs two movement classes gets its second
  field after about 2.1 s, because the cache serves one field at a time.
- **Meanwhile** units steer `DIRECT` and slide (ADR 0008 §2, unchanged), and a field already in
  the cache is reused at once. The slicing counts cells, so it stays deterministic.

### 6. Team tints and unit textures keep batching
- **Rule** (extends ADR 0011 §3): sprites at one absolute z batch only while consecutive sprites
  share both texture and modulate. Each unit draw layer therefore gets one z per batch group:
  z = the layer's base + the group.
- **The z bands** (they replace the list in ADR 0011 §3):

  | z | Layer and group |
  | --- | --- |
  | 0 | map |
  | 1 | selection ring (one texture, no tint) |
  | 10 + `type_index` | hull |
  | 20 + 8 x `type_index` + `owner` | team |
  | 100 + `type_index` | turret |
  | 110 | health bars |
  | 120 | projectiles |
  | 130 | effects |
  | 140 | fog |
  | 150 | markers |

  The bands hold type indexes 0-9 and owners 0-7. A type or owner beyond them takes its band's
  last group: the picture stays right and only costs extra calls. Wider bands need a new ADR.
- **The rig node contract stays:** rigs named `Unit<id>` in row order, with children
  `[Ring, Hull, Team, Turret]`. A container per owner would break it, which is why the z bands
  are used instead.
- **No second art set.**
- **Expected count** in the Phase 2 arena: map 1 + rings 1 + hulls 3 + team 6 + turrets 1 + bars
  1 + projectiles 1 + effects up to 2 + fog 1 + markers up to 2, so about 20 calls plus the HUD.
  The ceiling stays at 60.
- **What else batches:** the rings share one white texture, so they are one call. Bars,
  projectiles and effects each draw in one `_draw()`, where colour per item is vertex data and
  does not break the batch (probe).
- **Proof:** a headless test in P40 asserts the z per group, and the perf arena card counts the
  calls on the phone.
- **Visual cost:** an overlap of two units of different types or owners can draw one unit's
  layer over the other's. Separation keeps such overlaps short.

### 7. What stays, and when GDExtension comes
- **Unchanged:**
  - Michael's answer 1: the gate runs on his phone permanently, with the 2021 limits divided by
    k = 2.5;
  - CLAUDE.md rule 6;
  - frame pacing, the heavy window, the draw-call ceiling and the fog limit;
  - the CI method of ADR 0011 §4: min of 3, deterministic cost bounds, golden hashes, `ref_ms`.
- **The ADR 0011 §6 remedy order:** steps 1 to 3 are unchanged. Step 4 (the worker thread) is
  adopted here. Step 5 (GDExtension) needs its own ADR.
- **GDExtension (C++) is not adopted now.** Its ADR is written when either of these holds:
  - the release gate run in `WORKER` mode misses `sim_p95_ms` or shows late ticks, after steps 1
    (data tuning) and 2 (GDScript fixes of the costliest phase) have each been tried with before
    and after numbers;
  - earlier: P49's calibration floor stays above the CI ceiling computed with the release
    `ci_ratio`, after steps 1 and 2.

  That ADR also has to change the stack line of CLAUDE.md ("GDScript ... No C#"), which only an
  ADR may do.
- **The web preview** runs `SYNC`. Its numbers are reported but do not gate, and its hashes must
  match.

## Consequences
- **Timing:** the picture keeps its timing. On Android and desktop, touch commands take effect
  one tick (66.7 ms) later; on the web they do not.
- **The main thread** no longer carries the sim. By the probe's other frames (4.64 ms p95 on the
  debug build), the main thread fits `work_p95_ms` and frames should be on time.
- **Speed is still uncertain:**
  - the debug mock tick (15.3 ms p95) is above the new 13.3 ms;
  - the real tick does more than the mock (combat, projectiles, line checks, orders, the hash
    every 15th tick).

  Only the release run, and then the perf arena, show whether GDScript on a worker is enough. A
  GDExtension ADR is a real possibility, and its trigger is fixed above.
- **The gate build** is now the release template, as players get it. The release run sets
  `ci_ratio` and `flow_cells_per_tick`, and the gate thresholds are final on acceptance.
- **More code in the runner:** the snapshot, the job, the worker's life cycle and the late-tick
  policy. That is three lead PRs and one release-engineer PR. The view PRs (P40, P43a, P44a,
  P44b, P45, P47, P47p) read the snapshot instead of the World.
- **Threading risks:** two busy threads heat the phone more. A 2021 phone with few big cores may
  run the worker on an efficiency core (unverified; it depends on Android's scheduler). Neither
  is modelled by k. The period margin, three warm runs and field data are the answers.
- **A race is not provable headless.** The worker tests compare every checkpoint with `SYNC` and
  check that each snapshot is consistent on every frame. The real proof is golden hashes that
  match on the phone. The rules of §2 keep the shared surface small: two semaphores, two snapshot
  objects and one command list.
- **Flow fields** complete about 0.5 s later than ADR 0008 planned (at 256 cells); units drive
  straight meanwhile.
- **Docs when accepted:**
  - the lead adds one status line each to ADRs 0007, 0008 and 0011 (status notes, not
    rewrites);
  - `rts-sim-conventions` gets a "Threading" section (§2), the new flow-slice rule and the snapshot
    rule;
  - this ADR's PR carries the plan amendment.
