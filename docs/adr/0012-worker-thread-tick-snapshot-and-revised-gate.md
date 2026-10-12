# ADR 0012: Sim tick on a worker thread, the view snapshot, and the revised performance gate

Status: proposed, 2026-10-12 (Michael asked for it: "ok ADR 0012"). Revision 2, the same day,
after a review in four lenses (performance, gameplay, view, tests), and revision 3 after the
completeness check; "Revision 2" and "Revision 3" at the end list what changed. When accepted, it
supersedes in part:
- ADR 0011 §1 (what the view reads), §2 (where the prev positions live), §3 (the z list), §4 (the
  CI ceiling becomes a printed estimate; the enforced CI budget becomes a regression ratchet; its
  4.0 ms starting value of `mean_ms` is withdrawn), §5
  (the meaning and values of `work_p95_ms` and `sim_p95_ms` in its acceptance note, and the
  debug-APK margin), §6 step 4 (adopted here), and its sim cost estimate (1.9 ms mean on CI);
- ADR 0010 §1-2 where the view reads the fog and its dirty lists from the World (now
  `runner.snapshot.fog`);
- ADR 0008 §3 (the flow-slice budget, the starting `flow_cells_per_tick`, and a slice on every
  tick);
- ADR 0007 §6 (where the runner's per-tick work runs) and §10's last bullet (view handlers read
  `runner.snapshot.events` inside `ticked`, not `runner.world.events`);
- ADR 0003 §7, for the `WORKER` clock only (at most one publish per frame instead of up to
  `max_catch_up_ticks` ticks; the drain and stamp at the boundary before the post). `SYNC` is
  unchanged.

It keeps Michael's answer 1 (the gate runs on his phone with k = 2.5) and CLAUDE.md rule 6.

## Context
The Phase 2 plan (P26s) says that a contract the phone probe contradicts changes through a new ADR
before P34 starts. The probe ran on 2026-10-12. The full reports are comments on PR #35.

**Gate phone:** Google Pixel 9a (2025 mid-range, Tensor G4: 1 X4, 3 A720 and 4 A520 cores),
Android, 2424x1080, 60 Hz. The probe ran as a debug export, in 60 s runs, with the mock tick and
the flow slice inside the frame:

| Mode | On time (<= 17.5 ms) | Draw calls | Render CPU mean / p95 | Work p95, tick frames / other frames | Mock tick mean / p95 | Flow slice (512 cells) mean / p95 |
| --- | --- | --- | --- | --- | --- | --- |
| 1: sprite rings, tints grouped by team | 83.5 % (repeat 83.2 %) | 13 | 1.53 / 1.94 ms | 20.62 / 4.64 ms | 10.96 / 15.33 ms (repeat 11.12 / 15.38) | 3.57 / 4.39 ms |
| 2: Phase 1 code-drawn rings | 80.6 % | 462 | 4.06 / 5.14 ms | 20.02 / 7.33 ms | 8.77 / 12.51 ms | 3.41 / 4.24 ms |
| 3: sprite rings, tints alternating by row | 84.3 % | 161 | 2.07 / 2.54 ms | 20.93 / 5.17 ms | 10.86 / 15.24 ms | 3.64 / 4.54 ms |

The fog patch cost 0.29 ms mean (0.37 ms p95). In the four runs, the slowest tick took 1.13 to
1.76 times the p95 tick.

**CI side** (GitHub runner, `godot --headless`, `tests/perf/probe_tick.gd`, min of 3 runs): mock
tick 2.51 ms mean, 3.36 ms p95; flow slice of 512 cells 1.10 ms mean, 1.13 ms p95. The
phone-to-CI ratio is 4.4 (tick mean), 4.6 (tick p95) and 3.2 (flow slice mean), so the ratio
depends on the workload and on the statistic. The cloud VM gives the same numbers as CI (P26s
`PerfProbeTick`, min of 3: 2.30 ms mean, 3.20 ms p95).

**The earlier tick estimates are stale.** ADR 0008 priced the optimised mock at 0.7 ms mean and
1.25 ms p95, and ADR 0011 priced the real tick at 1.9 ms mean on CI from that. The probe's mock
costs 3.3 times more (per phase on the VM, in ms per tick: grids 0.035, move and separation 0.71,
acquire 0.64, fog stamp 0.97). If that factor carried over to the real tick (an extrapolation),
the real tick would cost about 6 ms mean on CI and about 28 ms mean on the debug phone.

**Debug against release** (CI machine, official 4.7.2 `linux_debug` and `linux_release`
templates, 1800 frames per phase):
- tight-loop mock tick: mean 2.38 to 1.78-1.80 ms (x1.32-1.34), p95 3.55 to 2.58-2.93 ms;
- a phone-sized job (5 mock steps at 15 Hz): mean 12.54 to 9.00-9.36 ms (x1.34-1.39), p95 19.4 to
  12.5-13.2 ms (x1.47-1.55);
- the same job on a dedicated worker costs 4-5 % more than in the frame (9.36 / 13.18 ms against
  9.00 / 12.55 ms), and a single step at 15 Hz on the worker has a p95 1.25-1.4 times that of a
  tight loop (wake-up and cache effects).

Applied to the phone's debug p95 of 15.33 ms, the release mock tick on the worker would take
about 10.4-13.3 ms p95, against the 13.3 ms limit (§4). The two ends come from two methods, so
the range is a spread of methods, not a confidence interval:
- low end, from the phone-sized job measured on the worker: 15.33 x 13.2 / 19.4 = 10.4 ms;
- high end, from the tight loop plus 5 % for the worker: 15.33 x 2.93 / 3.55 x 1.05 = 13.3 ms,
  exactly on the limit.

That is an estimate; the release run measures it.

**What the probe contradicts:**
- **ADR 0011 §5 and its acceptance note (budget and gate).** The gate phone runs this GDScript
  about 4.4 times slower than CI, not at about the cloud VM's speed. The 15 Hz tick runs inside a
  frame, so every tick frame misses its deadline (20.6 ms p95), and only 83.5 % of frames are on
  time against the 95 % required. The mock tick alone is about five times the sim limit (15.3 ms
  p95 against `sim_p95_ms` 3.2 ms). The frames without a tick are fine (4.64 ms p95).
- **ADR 0011 §4 (the CI ceiling).** The ceiling `sim_p95_ms / ratio` cannot sit above the
  calibration floor (§4), so the enforced CI budget could never be set by its own rule.
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
this ADR names the data values that the release run sets (§4) and makes no decision wait for it.

**Facts verified for this ADR** (Godot 4.7.2, 2026-10-12, scratch projects on the cloud VM; the
release-template facts on the official `linux_release` template):
- **Packed arrays are references in GDScript.** After `b = a`, a write through `b` changes `a`.
  `duplicate()` is a lazy copy-on-write. Capturing 27 arrays takes 6.5-9 µs back to back, and
  30-40 µs mean (0.06 ms p95) at 15 Hz on a worker. The first write to the source afterwards
  reallocates that array (its size plus 32 B) and copies it on the writing thread, at about
  0.03 ns per byte for these sizes (0.11 µs for 600 B, 0.82-0.89 µs for 32 KB).
- **Hand-off:** a dedicated `Thread` with two `Semaphore`s works (`post`, `wait`, `try_wait`).
  `try_wait` returns false while nothing was posted, and one post is one token: `try_wait()`
  returns true once, then false. Frame-paced at 15 Hz with the worker asleep between jobs (1,800
  frames on CI): the main thread's side of a boundary (`try_wait`, swap, `post`) takes p50
  54-62 µs, p95 79-101 µs, max 0.23-0.34 ms; the worker wakes p50 114-116 µs, p95 176-183 µs,
  max 1.5 ms after the post. Main-thread frame work did not change with the worker running
  (release, view only: p95 2.96 ms; with the worker: 2.81 ms over all frames, 2.86 ms on publish
  frames), against 14.4 ms p95 for tick frames with the tick in the frame. In 2000 hand-offs, the
  main thread read a published duplicate while the worker wrote the source array: no crash, and
  every value was right. No engine error or warning appeared in any threaded run.
- **The shared pool measured worse.** `WorkerThreadPool` at high priority: job p95 14.83 ms
  against 13.18 ms on the dedicated thread (the same 5-step job), and main-thread stalls up to
  1.42 ms against 0.23 ms. Low priority gets 1 of the 4 pool threads on CI (`WorkerThreadPool: 4
  threads, 1 max low-priority`), with a wake-up max of 1.5 ms.
- **Cross-thread property access serializes.** Reading a property through an object reference
  (`h.arr[i]`, as in `world.pos_x[row]`, or `node.position`) while another thread does the same
  made each thread 2-4 times slower on the release template: typed `h.arr[i]` x2.1-3.0, untyped
  member x1.7-3.3, `Node2D.position` get x1.8-2.1 and set x3.9-8. Aliased typed locals, `self`
  members, typed method calls and static calls kept their speed (x0.8-1.14). Repo code: the real
  `Formation.assign` (75 units; its inner loop reads `world.pos_x` and `world.unit_id` per pair)
  on a worker, while the main thread set 150 `Node2D` positions: release 0.728 to 1.326 ms
  (x1.82), editor 1.050 to 2.241 ms. The P26s mock tick (aliased locals and members) did not slow
  down next to the view (1.765 ms against 1.778 ms alone). The editor and the debug template also
  serialize method calls (x2.7-4.1) and static calls (x2.5-4.4), so debug-template worker timings
  are pessimistic. The single-threaded CI harness cannot see any of this.
- **Thread life cycle.**
  - Freeing a started `Thread` that was never joined prints a `WARNING`, which the `verify.sh`
    scan (`SCRIPT ERROR|^ERROR:|Parse Error`) misses. A worker still blocked on its semaphore at
    process exit also leaves `ERROR: 1 resources still in use at exit`, which fails `verify.sh`
    with no pointer to the test.
  - `wait_to_finish()` on a `Thread` that was never started logs an `ERROR`.
  - A Node that was never added to the tree gets only `NOTIFICATION_PREDELETE` when freed, not
    `_exit_tree()`. `wait_to_finish()` works inside that notification. Phase 1's runner tests
    build runners that way (`auto_free(MatchRunner.new())`, never `add_child`).
- **Node access from a worker.** Writing the `position` of a `Node2D` inside a running tree from a
  worker: the editor and the debug template refuse the write and print `ERROR: ... The caller
  thread can't call the function set_position() on this node. Use call_deferred()`; the release
  template writes it silently. `set_name` errors in all three. So a headless debug run of a real
  scene in `WORKER` mode reports any Node a job touches, and a release build reports nothing.
  (Revision 1 said "logged nothing": that test wrote a node outside a running tree.)
- **Feature checks:** `OS.has_feature("threads")` is true on desktop headless, and
  `DisplayServer.get_name()` returns `"headless"`. The web preset has
  `variant/thread_support=false` (`export_presets.cfg`).
- **`Performance.MEMORY_STATIC`** reads 0 on the release template.
- **Revision 1's late-tick rule counted frame hitches.** Implemented literally on CI with a 10 ms
  job, a first frame of 68-145 ms after loading and a single 150-400 ms frame mid-run each counted
  one late tick, with the job 0-2 ms old when it was declared late. Without a hitch: no late tick
  in 225 publishes, even with a 20.6 ms mean job.
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
- **The tick on the shared `WorkerThreadPool`.** Rejected: measured higher job p95 and longer
  main-thread stalls than a dedicated thread (above), it is shared with engine tasks, and every
  tick needs a waited task id.
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
  uses the snapshot and a headless scene test has run them on the worker (§3; plan P50w, P50b).
- **Worker:** one dedicated `Thread` per runner, created for the first job. It runs
  `TickJob.serve()`: wait on the `work` semaphore, return if `quit` is set, run one job, post the
  `done` semaphore, and repeat. Priority is normal. It is not the `WorkerThreadPool` (Context).
  If `Thread.start()` returns an error (for example a thread limit), the runner resolves to
  `SYNC` for the rest of its life, calls `push_warning` once, and runs the job it was about to
  post inline in that frame. The rule is the pure
  `static func mode_after_start(mode: int, start_error: int) -> int`, tested as a table.
- **Hand-off.** The two semaphores are the only synchronisation, and they also give the memory
  ordering. The runner is in one of three states:

  | State | Meaning |
  | --- | --- |
  | `IDLE` | no job posted, or the last one was published or discarded |
  | `RUNNING` | a job was posted, and its `done` token has not been taken |
  | `FINISHED` | the token was taken; the job is not published yet |

  The `done` token is taken only in `RUNNING`: by one `try_wait()` per frame, or by the timed
  wait below. A wait in `IDLE` or `FINISHED` therefore returns at once and never blocks on a
  token that is already gone. Every wait is a `try_wait()` loop with `OS.delay_msec(1)` steps and
  a 5 s cap; at the cap it calls `push_error` and returns false. A logic slip then fails a test
  instead of hanging CI (gdUnit4's per-test timeout is a SceneTree timer, which cannot fire while
  the main thread blocks). The transitions live in one pure
  `static func hand_off(state: int, event: int) -> Vector2i` (x = next state, y = action), tested
  as a table without threads:

  | Event | `IDLE` | `RUNNING` | `FINISHED` |
  | --- | --- | --- | --- |
  | frame, running and not paused | refill: drain, post, clock 0 → `RUNNING` | `try_wait()`; taken → `FINISHED` | none |
  | tick boundary | not reached (the refill came first) | hold → `RUNNING` | publish, drain, post → `RUNNING` |
  | `wait_idle()` | true | timed wait → `FINISHED` | true |
  | `start()` | tick-0 snapshot → `IDLE` | timed wait, discard, tick-0 snapshot → `IDLE` | discard, tick-0 snapshot → `IDLE` |
  | `run_ticks(n)`, n > 0 | n inline → `IDLE` | timed wait, publish (the first of n), n - 1 inline → `IDLE` | publish (the first of n), n - 1 inline → `IDLE` |
  | stop | join → `IDLE` | timed wait, discard, join → `IDLE` | discard, join → `IDLE` |

- **Ownership:** from the `work.post()` that starts a job to the `done` that ends it, the worker
  owns:
  - the World;
  - the `MatchLoop` and its `Replay`;
  - the probe and the command list;
  - the snapshot the job writes.

  In that window the main thread touches none of them. It reads only the published snapshot and
  the runner fields set at publish. Outside the window the main thread owns everything. Inside a
  `ticked` handler no job is in flight (publish, emit, then drain and post), so the World there
  equals the published snapshot.
- **One job is exactly one tick:** `MatchLoop.step(world, commands, probe)` (stamping, the
  record, `Sim.step` and the checkpoint every 15 ticks), then `snapshot.capture(world, previous)`
  (§3), then the timings: `job_usec` (the job, wall clock on the thread that ran it), `post_usec`
  (set by the main thread at the post) and `end_usec` (set by the worker before `done.post()`),
  all from `Time.get_ticks_usec()` in `game/core`. Two jobs never run at once, and a job never runs
  two ticks.
- **One tick ahead.** At each tick boundary of the runner's clock, the main thread does, in this
  order:
  1. **Publish.** If the job is finished, the job's snapshot becomes `runner.snapshot`, the
     published runner fields (`last_hash`, `last_tick_usec`, `last_runner_tick_usec`) are set
     from it, and `ticked(tick)` is emitted.
  2. **Drain.** It drains `CommandQueue` into the command list. `MatchLoop` stamps the commands
     with the tick the job will step.
  3. **Start.** It creates the next snapshot object and posts the next job.

  State N is therefore computed during the period before it is shown. During
  `[T_N, T_N+1)` the view interpolates from the prev positions to state N, as in `SYNC`, so the
  picture's timing does not change.
- **Command latency:**
  - A command submitted inside a `ticked(N)` handler is stamped N in both modes. The Phase 4 AI
    acts there, so AI-vs-AI runs are equal in both modes.
  - A command from touch input between two boundaries lands one tick later in `WORKER` than in
    `SYNC`: 66.7 ms more input latency. Move and target markers still show at once.
  - A refill drains like a boundary, so a command queued while paused or before the first job
    gets the same stamp in both modes.
  - Determinism is unaffected, because the replay records the stamped ticks.
- **The clock in `WORKER` mode:**
  - At most one publish per frame. After it, the whole ticks still owed are dropped and only the
    part of a tick is kept, as `SYNC` drops its backlog beyond `max_catch_up_ticks`. After a long
    frame the match runs a little behind wall time, as it does in `SYNC` after its four ticks.
  - The clock starts at 0 on every refill (after `start()`, `run_ticks()` and a pause), and the
    refill frame does not advance it. On a resume after a pause, the clock also restarts at 0.
- **A held tick:** a boundary reached while the job is `RUNNING`. The runner holds:
  - it publishes nothing and starts no job;
  - `alpha()` stays at 1.0, so the view shows the newest state;
  - the clock stops at the boundary, so the time spent waiting is dropped, not caught up later;
  - `held_ticks` increments once for the held job (a diagnostic on the card).

  Every frame then polls `try_wait()`. The first frame that takes the token publishes the job,
  drains and posts the next one, and the clock restarts at 0 in that frame. `_process` never
  blocks. Commands keep queuing in `CommandQueue` meanwhile, and none is dropped.
- **A late tick** is one where the worker really was slow: its post-to-done time
  (`end_usec - post_usec`) exceeds the tick period, `TICK_USEC = 1_000_000 / Sim.TICK_RATE`
  (66 666 µs; derived from the tick rate, never a literal). `late_ticks` counts them at
  publish, and `latency_usec_max` keeps the largest post-to-done time of the run. A hold caused by
  a main-thread hitch or by catch-up is a held tick, not a late one: the hitch itself is judged
  by the on-time share.
- **Synchronous mode:** the same `TickJob.run()` runs inline on the main thread at the boundary
  and publishes at once. It is used:
  - by every headless test (`AUTO` resolves to `SYNC` headless). The runner's own worker tests
    (plan P38w, P38w2) and the worker scene test (P50w) are the exceptions: they set `WORKER`
    explicitly;
  - by `run_ticks(n)`, inline, except that a job already in flight is published as the first of
    the n ticks (table above), so the published tick always advances by exactly n;
  - by `Replay.play` and `tests/perf`, which drive `MatchLoop` or `TickJob` directly with no
    runner;
  - by the web build. Threads are off in the web preset, so the web preview keeps the in-frame
    tick and its hitches. The APK is the gate.
- **Waiting and status:** `wait_idle(timeout_msec: int = 5000) -> bool` returns true once no job
  is `RUNNING`, or false at the cap. The finished job stays unpublished until the next boundary or
  `run_ticks()`. `job_in_flight() -> bool` is true in `RUNNING`. `worker_active() -> bool` is true
  while a started thread has not been joined.
- **Guarded access.** `world`, `loop`, `replay` and `probe` are properties over private fields.
  Their getters call `push_error` when the resolved mode is `WORKER` and the state is `RUNNING`, so
  a missed reader fails deterministically in any `WORKER` test instead of racing. The rule is the
  pure `static func shared_access_allowed(mode: int, state: int) -> bool`, tested as a table; no
  test triggers the error itself (the log scan would catch it). The probe is installed through
  `set_probe(probe: SimProbe)`, which waits idle first.
  Each of the four properties also has a setter, because in Godot 4.7.2 an assignment to a
  getter-only script property is silently ignored (no parse or runtime error; verified headless),
  so a test that installs a probe or swaps in a World would stop doing it without a word. The
  `world`, `loop` and `replay` setters assign the private field under the getters' rule (for
  tests: main thread, no job `RUNNING`); the `probe` setter calls `set_probe()`.
- **`start()`** (both modes) waits for and discards a job in flight, builds the World and the
  `MatchLoop`, increments `match_serial`, captures the tick-0 snapshot with
  `capture(world, null)` into a new snapshot and publishes it before it returns (without emitting
  `ticked`), resets `late_ticks`, `held_ticks` and `latency_usec_max`, and sets the clock to 0.
  The next `_process` refills.
- **Stop.** One `_join_worker()` is called from both `_exit_tree()` and
  `NOTIFICATION_PREDELETE`. It is idempotent and joins only when `_thread != null and
  _thread.is_started()`: it sets `quit`, posts `work` and calls `wait_to_finish()`. A runner that
  never entered the tree is therefore joined when it is freed. `static func live_workers() -> int`
  (a static counter on `MatchRunner`, main thread only, allowed outside `game/sim`) lets a test
  prove the join without calling a freed object. Tests need not add the runner to the tree.
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
  before any job, and nothing in the sim keeps a def.
- **No threading in the sim:** the sim never creates or waits on a thread.
- **Only the job's objects:** every object a job touches is reachable from the World, the
  `MatchLoop`, the probe, the command list or the job's snapshot, and none of them is a Node or a
  Resource. A reachability test checks it (below).
- **Alias before the loop, on both threads.** On the worker (all of `Sim.step`, including
  event-cadence code such as `Formation.assign` and command validation, and `capture`) and in the
  main thread's per-row and per-item loops (`UnitLayer`, `fill_pick_snapshot`, the layers'
  `_draw()`), object properties are read into typed locals once before the loop; no loop reads
  `obj.prop` per row. Reason: Godot serializes cross-thread property access, so two threads doing
  it at once both run 2-4 times slower (Context). `Formation.assign`'s inner loop is converted in
  plan P37a.
- **No main-thread access during a job** to the World, the loop, the replay, the probe, the
  command list or the job's snapshot (§1, ownership; guarded at runtime by the getters).
- **The main thread reads the World only inside a `ticked` handler or after `wait_idle()`**, never
  from `_process`, a timer or an input handler. Phase 4's AI and `PlayerView` read it there.
- **A published snapshot is never written** by either thread (§3, one snapshot per publish).
- **Commands change hands once.** A submitted `Command` belongs to the runner from then on.
  Nobody reads or writes it afterwards, except through the replay after `wait_idle()`. Every
  `Command` factory duplicates the arrays it is given (`unit_ids`, and `payload` from v1), as
  `attack_move` already does, and a test per factory changes the caller's array after the call.

**Guards:**
- `tests/project/test_sim_purity.gd` (qa) bans in `game/sim`, each with a matching and a
  non-matching fixture: `static var`, `signal `, `.emit(`, `call_deferred(`, `load(`,
  `preload(`, `ResourceLoader`, `ResourceSaver`, `Thread`, `Mutex`, `Semaphore`,
  `WorkerThreadPool` and `await`.
- `tests/core/test_tick_job.gd` (lead):
  - a reachability walk from a `TickJob` on the prepared arena (World, `MatchLoop`, `Replay`,
    a `TimingProbe`, the command list, the snapshot) through script variables, `Array` and
    `Dictionary` values, with a visited set, fails on any reachable Node or Resource; a fixture
    probe subclass holding a Node must fail;
  - a source scan of the worker files in `game/core` (`TickJob.gd`, `MatchSnapshot.gd`,
    `TimingProbe.gd`) bans `get_tree`, `get_node`, `Engine.`, `Input.`, `OS.`, `CommandQueue`,
    `DetRng`, `signal `, `.emit(` and `call_deferred(`.
- A headless run of `main.tscn` with `tick_mode = WORKER` (plan P50w; `perf_arena.tscn` in P52)
  makes any write to an in-tree Node from the worker an `ERROR` line, which `verify.sh` fails on.
  Release builds have no such guard, which is why the structural checks stay.

Determinism and replays do not change: the thread changes when a tick runs, not what it computes.
The golden hashes (seed and scenario orders, no human commands) are equal in both modes, and a
test proves it.

### 3. What the view reads: `MatchSnapshot`
- **`game/core/MatchSnapshot.gd`**, a pure `RefCounted` with no Node. It holds the view's copy of
  one tick:
  - **header:** `match_serial`, `tick`, `rows_version`, `map_version`, `last_hash`, and the row
    count. The World holds neither `match_serial` nor `last_hash`, so `capture` does not set
    them: `TickJob.run()` sets `snapshot.match_serial` (from the runner, handed to the job at the
    post) and `snapshot.last_hash` (from `loop.last_hash`) right after the capture, and `start()`
    does the same for the tick-0 snapshot;
  - **rows:** `unit_id`, `owner`, `type_index`, `pos_x`, `pos_y`, `hp`, `order`, `target` and
    `target_row` (the target's row in this snapshot, -1 when there is no target or it is gone,
    computed in `capture` on the worker), each with exactly `unit_count()` entries;
  - **prev positions:** `prev_pos_x` and `prev_pos_y`, aligned to this snapshot's rows;
  - **type and weapon tables:** the ones ADR 0011 §1 lists;
  - **projectiles:** `proj_id`, `proj_owner`, `proj_weapon`, `proj_x` and `proj_y`, plus
    `prev_proj_id`, `prev_proj_x` and `prev_proj_y`;
  - **map:** `map_cols`, `map_rows`, `terrain` and `terrain_ids`;
  - **fog:** `fog: FogGrid`;
  - **runtime:** `events` and `stats` of this tick;
  - **timings:** `phase_usec` (a copy of the `TimingProbe`'s), `step_usec` (`Sim.step`),
    `job_usec`, `post_usec` and `end_usec` (§1).

  Methods: `unit_count()`, `index_of(id)` (binary search over the ascending ids),
  `cell_of(x, y)` (the same formula as `World.cell_of`, so the layers that hide by fog share one
  formula: x and y are clamped into the map, column `clampi(x / 1000, 0, map_cols - 1)` and row
  `clampi(y / 1000, 0, map_rows - 1)`, so a position outside the map gives the nearest edge cell
  and never indexes outside the fog arrays; the plan pins the clamp in `World.cell_of` from its
  first PR, P29b) and `capture(world: World, previous: MatchSnapshot) -> void`.
- **Copied columns:** `MatchSnapshot.COPIED` and `MatchSnapshot.NOT_COPIED`
  (`Array[StringName]`). A test checks that their union is exactly the World's `ROW_ARRAYS`,
  `TYPE_ARRAYS`, `WEAPON_ARRAYS`, `PROJECTILE_ARRAYS` and `MAP_ARRAYS`, that they are disjoint,
  and that every `COPIED` name is a snapshot property. A Phase 3 column added to the World then
  fails the test until it is classified, as ADR 0007 §2's coverage test does for the hash.
- **Copies:** `capture` takes every copied array with `duplicate()` (O(1)). The next tick's first
  write to each array reallocates and copies it inside `Sim.step`, on the worker, so the cost
  shows in the probe time of the phase that writes first (Context: under 0.1 ms per tick on CI in
  total). The fog uses `FogGrid.copy_into(dst: FogGrid)` (gameplay-dev, P32), which duplicates
  the grid's arrays and scalars, so the snapshot answers every FogGrid read method.
- **Prev positions:**
  - When `rows_version` is unchanged, `prev_pos_*` are the previous snapshot's `pos_*` (the same
    buffers, which nobody writes).
  - When it changed, a merge walk by id (on the worker, ADR 0011 §2): a survivor keeps its old
    position, a new row starts at its current position, and a dead row is dropped.
  - A `previous` that is null or has another `match_serial` counts as none: prev = current.
  - Projectiles: the `prev_proj_*` arrays are the previous snapshot's arrays. A layer treats a
    slot whose `proj_id` differs from `prev_proj_id` as new and draws it at its current position.
- **One snapshot per publish** (it replaces revision 1's double buffer). When it posts a job, the
  main thread creates a new `MatchSnapshot` (with its `FogGrid`) and hands it to the job together
  with the current `runner.snapshot` as `previous`. The job writes only the new object; publishing
  makes it `runner.snapshot`; nobody writes it afterwards. At most two snapshots exist in
  `WORKER` mode (the published one and the one in flight). A layer that holds a snapshot, or one of
  its arrays, past a publish reads an old tick, never a torn one.
- **View rules** (they replace the first bullet of ADR 0011 §1):
  - Production code in `game/view`, `game/input` and `game/ui` reads only `runner.snapshot`,
    `runner.alpha()`, `runner.scenario` (an immutable Resource, read on the main thread) and the
    published runner fields. It never reads `runner.world`, `runner.loop`, `runner.replay` or
    `runner.probe`.
  - Layers read `runner.snapshot` afresh in every `_process` and handler, and detect a restart
    through `snapshot.match_serial` only.
  - `events` are read only inside `ticked`.
  - Per-row loops alias the snapshot arrays into typed locals first (§2).
  - The perf card takes its checkpoints from `snapshot.last_hash` at ticks that are multiples of
    150.
  - Tests may read and write `runner.world` in `SYNC` mode or after `wait_idle()`. In `SYNC` mode
    they may also write the published snapshot's arrays to set up a view case; the World is not
    affected, because those arrays are copies.
  - A scan (plan P50w, before any scene runs the worker) rejects `.world`, `.loop`, `.replay` and
    `.probe` in `game/view`, `game/input` and `game/ui`, and `.loop`, `.replay` and `.probe` in
    `game/ai` (whose World reads inside `ticked` are allowed and guarded at runtime).
- **Allocation:** per tick, the main thread creates two objects (the snapshot and its
  `FogGrid`), `capture` makes one wrapper per copied array, and the next tick's first writes
  reallocate about 15 arrays (about 70 KB; the fog's `visible` at 32 KB is the largest) inside
  `Sim.step`. Never one allocation per row or per cell. The old snapshot is freed at publish, so
  `Performance.OBJECT_COUNT` stays flat (packed arrays are not Objects). The `MEMORY_STATIC` check
  of plan P38w runs on CI only, because that monitor reads 0 on release builds.

### 4. Gate and budget (replaces ADR 0011's acceptance-note values where the probe contradicts them)
**Gate runs** use the release-template perf APK (plan P51r) in `WORKER` mode, three runs in a
row, on Michael's phone.

| Field | Value | Rule |
| --- | --- | --- |
| `heavy_rigs` | 135 | unchanged |
| `heavy_frames_min` | 600 | unchanged; not divided |
| `on_time_ms` | 17.5 | unchanged; not divided |
| `on_time_share_pct` | 95 | unchanged: over the run and over the heavy window |
| `work_p95_ms` | 5.6 | 14 ms on a 2021 phone / 2.5, as before. **New meaning:** p95 of the main thread's frame work (process plus render CPU) over **all** frames of the heavy window, with the sim on the worker |
| `work_tick_p95_ms` | 5.6 | **new:** the same p95 over the heavy window's publish frames only (one frame in four). They carry the swap, the `ticked` handlers, the fog patch, the panel refresh and the rig re-map after deaths, and an all-frames p95 is only their p80 |
| `sim_p95_ms` | 13.3 | **New meaning:** p95 of the worker job (`job_usec`: `MatchLoop.step` plus the capture, wall clock on the worker), on the release template. The 2021 limit is 33.3 ms, half the 66.7 ms period; divided by k = 2.5 |
| `job_p99_ms` | 26.7 | **new:** p99 of `job_usec`. The 2021 limit is one period (66.7 ms) / 2.5 |
| `late_ticks_max` | 0 | **new:** no job whose post-to-done time exceeds the period (§1), in the whole run |
| `fog_update_p95_ms` | 0.4 | unchanged (ADR 0010 §2; it runs on the main thread in `ticked`) |
| `draw_calls_max` | 60 | unchanged; not divided |
| `release_only` | true | **new:** a card from a debug template shows the verdict line `build: FAIL (debug template)`, so `GATE: FAIL` |
| `ci_ratio_mean` | 4.4 | **new, provisional, not a threshold:** phone mean / CI mean of the mock tick (10.96 / 2.51, debug run); set from the release run |
| `ci_ratio_p95` | 4.6 | **new, provisional, not a threshold:** phone p95 / CI p95 (15.33 / 3.36, debug run); set from the release run |

**Invalid runs.** Besides ADR 0011 §5's rules, a run whose heavy-window draw-call p95 or render
CPU p95 is 0 is `INVALID`. A monitor that a release template compiles out would otherwise pass its
verdict silently. The card also shows, without a verdict: job mean, p50 and max,
`latency_usec_max`, `held_ticks`, and the flow line of §5.

**Why held ticks have no verdict.** A hold is visible (one frame or more of frozen motion), but it
has two causes that are judged elsewhere. A main-thread hitch delays the post, which the on-time
share already judges. A slow job holds once its post-to-done time passes the time left after a
late post (from about 50 ms on the gate phone, because the post can come up to one frame after
the boundary); such a job is far above `job_p99_ms` (26.7 ms), so the p99 verdict keeps them under
1 % of ticks, and above one period they are late ticks. A hold verdict would judge the same frames
twice. The first release perf-arena card records `held_ticks`; if it is above 9 (1 % of the 900
ticks), the lead proposes a `held_ticks_max` field through a new ADR.

**What the CPU-time limits cover.** Every CPU-time threshold is a 2021 limit divided by k = 2.5
(ADR 0011 §5):
- **The p95 job** may take half the period on a 2021 phone (33.3 ms). The other half is a factor
  2 for typical ticks, against what k does not model: a slower or efficiency core and heat.
- **The p99 job** may take one period on a 2021 phone (66.7 ms, so 26.7 ms on the gate phone).
  This gates the tail, which the p95 limit does not bound: in the probe the slowest tick took up
  to 1.76 times the p95. The p99 skips the 9 slowest of 900 ticks, so tick 0 (the opening orders
  for 150 units and a checkpoint hash) does not fail it.
- **`late_ticks_max` 0** is the absolute check on the gate phone: no job ran longer than one
  period from post to done. Below the p99 limit it fires only on a stall of the worker
  (preemption, a little core), which is what it should catch.
- **Not modelled:** the tail beyond the p99 on a 2021 phone, the core Android's scheduler picks,
  and heat. Three warm runs and field data answer them (Consequences).

The withdrawn debug-APK margin of ADR 0011 §5 is replaced by these limits.

**CI budget** (replaces ADR 0011 §4's ceiling rule; its method stays: min of 3, deterministic cost
bounds, golden hashes, `ref_ms`):
- **ADR 0011 §4's 4.0 ms starting value is withdrawn.** `budget.cfg` starts at 1.5 x the
  calibrated min-of-3 and only ever tightens. The mock tick alone takes 2.51 ms mean and 3.36 ms
  p95 on CI, and the real tick is estimated at about 6 ms mean (Context), so the old rule ("a mean
  floor above 4.0 ms is a finding for §6") would block P49b exactly as the ceiling would. The
  qa-engineer role text ("start at 4 ms per tick on CI") changes with it (plan: "On acceptance").
  The device verdict stays with the gate.
- **The device-derived ceiling is withdrawn as an assertion.** With the debug ratio it is
  13.3 / 4.6 = 2.9 ms, while the mock tick alone takes 3.36 ms p95 on CI, and ADR 0011 §4's floor
  (1.5 times the worst min-of-3) would be at least 5.0 ms. The floor fits under the ceiling only
  for a ratio at or below 13.3 / (1.5 x CI p95), about 2.6 for a mock-sized tick: a release
  template 1.7 times faster than debug, against the measured 1.32-1.39. Kept, it would leave P49
  unmergeable with the gate queued behind it.
- **Enforced: a regression ratchet** (plan P49b): `budget.cfg` `mean_ms` and `p95_ms` are 1.5
  times the worst min-of-3 seen in at least 10 CI calibration runs of the final Phase 2 tick
  (after P46b), plus the deterministic cost bounds, the outcome and memory bounds and the golden
  hashes (P49a). It catches a regression; the device verdict belongs to the gate.
- **CI measures what the gate measures:** `tests/perf` times `TickJob.run()` in `SYNC` (the step,
  the capture and the first-write copies, the same quantity as `job_usec`), with `Sim.step` and
  the phase split as sub-lines (P49a). P38p, which merges before `TickJob` exists, times
  `MatchLoop.step`.
- **Estimate, printed and not asserted:** the `PERF` line prints
  `est_phone_mean_ms` = mean x `ci_ratio_mean` and `est_phone_p95_ms` = p95 x `ci_ratio_p95`.
  The lead compares `est_phone_p95_ms` with 13.3 ms in each sim PR's review (the early warning),
  and a PR above it starts the remedy order (ADR 0011 §6) then, not at the gate.
- **Decision point:** P46's `PERF` line, the first with every phase in the tick. If its
  `est_phone_p95_ms` is above 2 x 13.3 = 26.6 ms, the lead starts drafting the GDExtension ADR in
  parallel with remedy steps 1 and 2 (§7).

**The release run** (Michael, once; nothing waits for it):
- The P26s probe gains a worker mode (about 40 lines on the never-merged probe branch):
  `PerfProbeTick.step()` on a dedicated `Thread` with the two-semaphore hand-off, one tick ahead,
  the view unchanged. Michael runs both modes in one session of the release APK. The report gives
  the worker job mean and p95, held ticks, the main thread's frame work with the tick out of the
  frame, and draw calls and render CPU (which must read above 0 on release; if not, the card's
  render line needs another source, a finding for plan P50a).
- `ci_ratio_mean` = the release worker job mean / 2.51 ms and `ci_ratio_p95` = the release worker
  job p95 / 3.36 ms, each rounded up to one decimal, in `data/dev/perf_gate.tres`: the lead's
  one-value PR (plan exception 5). No `budget.cfg` value moves with them.
- `flow_cells_per_tick` in `data/rules.tres` (§5): gameplay-dev's one-value PR. After P49a it
  re-pins the golden hashes under the plan's exception 3.
- **Later re-derivation from the real tick:** the first release perf-arena card (after P50b and
  P51r) gives the phone's job mean for a commit. With CI's `TickJob` mean for the same commit, if
  that real ratio differs from `ci_ratio_mean` by more than 10 %, the lead opens another
  exception-5 PR for both ratios.

No gate threshold waits for the release run: each one follows from k, the 2021 limits and the
period.

### 5. Flow fields on the worker
- **Flow ticks sit inside the job p95.** At 256 cells a field takes 16 ticks, and the arena
  opening asks for four fields (two players, each with `FOOT` and `TRACKED` units), served one at
  a time (ADR 0008 §3). That is up to 64 of 900 ticks (7 %), more than the 5 % a p95 ignores. The
  condition is therefore: the p95 of ordinary ticks plus the slice stays within 13.3 ms.
- **No slice on hash ticks.** `Sim.step` passes 0 cells to `FlowCache.advance` on the ticks on
  which `MatchLoop` adds a checkpoint (the same `% Replay.CHECKPOINT_PERIOD` test on the same tick
  value; 60 of 900 ticks), so the slice and the hash never land in the same job. It depends on
  the tick only, so it is deterministic (plan P37b).
- **The value now** (debug run): `flow_cells_per_tick = floor(512 x 2.0 / slice_mean_ms / 64) x
  64`, clamped to 64..1024, with `slice_mean_ms` the mean cost of a 512-cell slice:
  512 x 2.0 / 3.57 = 286.8, so **256** (about 1.8 ms debug, about 1.3 ms release). The mean is used,
  not the p95, because the work per cell is fixed; the scheduler's noise is judged by the job's
  p95.
- **The release run re-derives it from the measured headroom:** the largest multiple of 64 in
  64..512 for which the release worker job p95 (probe, worker mode) plus `cells x
  (release 512-cell slice mean / 512)` stays at or below 12.0 ms (13.3 ms less a 10 % margin for
  what the mock lacks), and not above the 2 ms rule applied to the release slice mean. If the
  mock alone leaves no room for
  64 cells, the value is 64 and the release run's report names it as an early-warning finding
  (risk 1).
- **Completion:** the arena map has 3980 open cells. At 256 one field completes in 16 working
  ticks (about 1.1 s). The arena opening's fourth field completes after about 64 working ticks,
  about 69 ticks with the hash ticks skipped: about 4.6 s.
- **Meanwhile** units steer `DIRECT` and slide (ADR 0008 §2, unchanged), and a field already in
  the cache is reused at once. The slicing counts cells, so it stays deterministic.
- **On the card** (no verdict): `phases_ms` holds each phase's mean per tick over the run, and
  `flow_slice_p95_ms` is the p95 of the `FLOW` phase over the ticks whose `stats[FLOW_CELLS]`
  equals `flow_cells_per_tick`, so the slice's cost is checked on the real map.

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
- **Expected count:** map 1 + rings 1 + hulls T + team T x O + turrets T_t + bars 1 +
  projectiles 1 + effects up to 2 + fog 1, with T unit types, O owners and T_t turret types. In
  the Phase 2 arena (T = 3, O = 2, T_t = 1) that is 17 calls plus the HUD. The ceiling stays at 60.
- **Trigger:** when that forecast passes 40 calls (two thirds of the ceiling; for example eight
  types and four players give 32 team groups alone), rigs move to `MultiMeshInstance2D` (ADR 0011
  §6 step 3) through an ADR, rather than wider bands.
- **Markers** are in the main scene only; the arena has none, so the gate never counts them. A
  Phase 1 mark is a `CanvasGroup` with up to 8 visible `Line2D`, about 10 calls each, and up to 4
  marks live at once: up to about 40 calls on top of the world for a moment. Drawing the marks in
  one `_draw()` is a Phase 5 polish item if the play sessions find the main scene hitching.
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
  - the CI method of ADR 0011 §4 (min of 3, deterministic cost bounds, golden hashes, `ref_ms`),
    with the ratchet of §4 in place of the ceiling.
- **The ADR 0011 §6 remedy order:** steps 1 to 3 are unchanged. Step 4 (the worker thread) is
  adopted here. Step 5 (GDExtension) needs its own ADR.
- **GDExtension (C++) is not adopted now.** Its ADR is written and proposed when a release
  perf-arena card in `WORKER` mode (the first one after P50b and P51r, or a gate run) misses
  `sim_p95_ms` or `job_p99_ms`, or shows late ticks, after steps 1 (data tuning) and 2 (GDScript
  fixes of the costliest phase) have each been tried with before and after numbers. The lead
  starts drafting it earlier, in parallel with steps 1 and 2, when P46's `est_phone_p95_ms` is
  above 26.6 ms (§4). The CI floor no longer triggers anything.

  That ADR also has to change the stack line of CLAUDE.md ("GDScript ... No C#"), which only an
  ADR may do.
- **Build order:** nothing waits for Michael's release run. P38s, P38j and P38w are needed in
  every outcome (a GDExtension tick would also run off the frame, and the view reads the snapshot
  either way). P49a, P50b and P51r need no phone number, and P49b needs only CI.
- **The web preview** runs `SYNC`. Its numbers are reported but do not gate, and its hashes must
  match.

## Consequences
- **Timing:** the picture keeps its timing. On Android and desktop, touch commands take effect
  one tick (66.7 ms) later; on the web they do not.
- **The main thread** no longer carries the sim. By the probe's other frames (4.64 ms p95 on the
  debug build) and the CI measurement (frame work unchanged with the worker running), the main
  thread fits `work_p95_ms` and frames should be on time.
- **What the worker fixes, and what it does not.** It removes the frame-pacing failure (every
  tick frame late). It does not make the job budget certain:
  - the estimated release mock tick on the worker is 10.4-13.3 ms p95, against 13.3 ms;
  - the real tick does more than the mock (combat, projectiles, line checks, orders), and the
    stale ADR 0011 estimate understated even the mock by a factor of 3.3.

  The release run, P46's estimate and then the release perf-arena card show whether GDScript on a
  worker is enough. A GDExtension ADR is a real possibility, and its trigger is fixed above.
- **The gate build** is now the release template, as players get it. The release run sets
  `ci_ratio_mean`, `ci_ratio_p95` and `flow_cells_per_tick`, and the gate thresholds are final on
  acceptance.
- **The CI budget catches regressions, not the device verdict.** The phone gate is the only
  device verdict; CI prints an estimate.
- **More code in the runner:** the snapshot, the job, the worker's life cycle, the hand-off states
  and the clock rules. That is four lead PRs (P38s, P38j, P38w, P38w2; each has a named split, and
  P38w is expected to take it), one qa PR (P50w) and one release-engineer PR. The view PRs (P40,
  P43a, P44a, P44b, P45, P47, P47p) read the snapshot instead of the World.
- **Threading risks:** two busy threads heat the phone more. The worker is busy about 15 % of
  each period and asleep in between, so Android's scheduler may put it on a little core (the gate
  phone has four A520s), and the clock ramps after each sleep. Neither is modelled by k, and the
  CI harness cannot see either. The release run's worker mode measures them on the gate phone;
  the p95 margin, three warm runs and field data answer the rest.
- **Races:** the shared surface is small (two semaphores, one snapshot per publish, one command
  list). Headless proof now reaches further: the getters fail a main-thread read during a job,
  debug builds refuse a Node write from the worker with an `ERROR`, a headless scene test runs
  `main.tscn` on the worker, and the worker tests compare every published snapshot with `SYNC`,
  including under real overlap. The final proof is still golden hashes that match on the phone,
  because a release build has no Node guard.
- **Flow fields** complete later than ADR 0008 planned (about 4.6 s for the arena's fourth field
  at 256 cells); units drive straight meanwhile.
- **Docs when accepted:**
  - the lead adds one status line each to ADRs 0003 (§7, the `WORKER` clock only), 0007 (§6,
    §10), 0008 (§3), 0010 (§1-2) and 0011 (§1-§6 as listed above, including the withdrawn 4.0 ms
    start) (status notes, not rewrites);
  - the lead asks Michael to approve the one-line change of the qa-engineer role's budget rule
    (`.claude/agents/qa-engineer.md`, "start at 4 ms per tick on CI") to the ratchet of §4;
  - `rts-sim-conventions` gets a "Threading" section (§2, including the alias rule for both
    threads), the new flow-slice rule and the snapshot rule;
  - this ADR's PR carries the plan amendment.

## Revision 2 (2026-10-12, review in four lenses)
- §1: late ticks count only a slow worker (post-to-done above the period); a hold is a separate
  diagnostic; the `WORKER` clock drops whole ticks after a publish and restarts at 0 on refill and
  resume; refill drains; hand-off states with timed waits and a pure transition table; guarded
  getters and `set_probe`; `start()` publishes the tick-0 snapshot and resets the counters; join
  from `_exit_tree()` and `NOTIFICATION_PREDELETE`, only for a started thread; `live_workers()`
  and `job_in_flight()`.
- §2: the alias rule for both threads (measured contention), World reads only in `ticked` or after
  `wait_idle()`, Command factories duplicate their arrays, wider purity bans, the reachability
  walk and the worker-file scan, and the headless `WORKER` scene run as the Node guard.
- §3: one snapshot per publish instead of a double buffer, `target_row`, `cell_of`, the
  `COPIED`/`NOT_COPIED` coverage, prev reset on another `match_serial`, `runner.scenario` allowed,
  the wider scan moved before any scene runs the worker, the allocation wording.
- §4: `work_tick_p95_ms` and `job_p99_ms` gated, two ratios, the zero-monitor `INVALID` rule, the
  CI ceiling replaced by a ratchet and a printed estimate, `TickJob.run()` timed on CI, the P46
  decision point, and a worker mode for the release run.
- §5: flow ticks inside the p95, no slice on hash ticks, the release value from the measured
  headroom, four fields in about 4.6 s.
- §6: the call formula, the MultiMesh trigger and the marker cost.
- §7: the GDExtension triggers restated on the real tick, and the build order.
- Context: corrected Node-guard and thread-lifecycle facts, frame-paced hand-off numbers, the pool
  measurement, the contention measurement, debug against release, the stale tick estimates.

## Revision 3 (2026-10-12, completeness check)
- Header: ADR 0003 §7 added to the supersede list (the `WORKER` clock only); ADR 0011 §4's 4.0 ms
  starting value withdrawn (§4, with the qa-engineer role line on acceptance).
- §1: `world`, `loop`, `replay` and `probe` get setters (a getter-only property silently ignores
  assignments in 4.7.2); `run_ticks(n)` wording; `TICK_USEC` derived from `Sim.TICK_RATE`; a
  failed `Thread.start()` falls back to `SYNC` with one warning (`mode_after_start`).
- §3: `cell_of` clamps into the map, pinned in `World.cell_of` from P29b; `match_serial` and
  `last_hash` set by `TickJob.run()` after the capture.
- §4: why held ticks have no verdict, and the condition for proposing one.
- Context: the two derivations behind the 10.4-13.3 ms estimate.
