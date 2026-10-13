# ADR 0014: Frame pacing by dropped frames, and main-thread CPU-time limits normalised for clock scaling

Status: accepted, 2026-10-12 (Michael: "1 ja, 2 A, 3 ja, 4 ja"; answer 3 accepts this ADR and the
calibration run of §5, which is still open; see "Acceptance note" at the end). Proposed the
same day (revision 9, after the review of revision 8: the burst runs before
every run, "Run again" included, so `ref_peak` is per run as §3 says (P50a3); the preflight's
refusal sets `INVALID` without `push_error`; P50lp's `pin_busy_pct` enters `PerfGateDef.gd` and
`perf_gate.tres` under the plan's named exception 8. Revision 8, after merging `main` and the review of revision 7: the
burst runs as the second seam of `PerfHud.preflight()`, which P50b's arena script calls before
the runner starts, with an order test (§3, §4); the Context's source facts are listed as not
re-run with the PR that re-proves each; P52 is about +15. Revision 7: `refresh_hz` is a float, so §2 and C1 compare it with
`refresh_tolerance_pct`; P50a depends on the calibration's recorded outcome, and the load-pinned
fallback has a conditional plan row, P50lp, with its busy share in `PerfGateDef`; the burst keeps
the second half of `ref_burst_ms`. Revision 6: the docs PR is P26e and the plan revision is the next
one at acceptance; `Engine.max_fps` 0 counts as `refresh_hz` in P; the cold-sample ranges are
given per quantile. Revision 5: ADR 0012 §7's "frame pacing" joins the supersedes
list, and the calibration build also prints a per-frame normalised p95 that C3/C4 can choose.
Revision 4, after the completeness check of revision 3: §3's reference-loop claim was re-run
and corrected; each frame's sample now follows a discarded warm-up run). Michael accepted it
on 2026-10-12, and the lead applied §7 (acceptance note).

Status note (2026-10-13, calibration recorded in the acceptance note, docs PR P26g): C1 and C2
hold; C3 and C4 fail on the class method and hold on the per-frame method. By §5's outcome "C3
or C4 fails on the class method but holds on the per-frame method", the per-frame method is §3's
formula from 2026-10-13 and P50a implements it; the class p25 factor stays printed as a
diagnostic. No repeat and no load-pinned fallback: P50lp and `pin_busy_pct` are not taken. The
sections this touches (§3, §4's CPU rows, `pin_busy_pct` and P50lp bullets, §5, §7) carry a
dated status line in place.

It does not depend on ADR 0013 (C++ kernels). Michael can accept either one, both or neither.
The calibration run below needs only the GDScript modes of the never-merged probe branches; the C++
mode is optional.

From its acceptance (2026-10-12) it supersedes in part:
- **ADR 0012 §4:**
  - the rows `on_time_ms` (17.5) and `on_time_share_pct` (95);
  - the measured quantity, not the value, of the main-thread limits `work_p95_ms`,
    `work_tick_p95_ms` and `fog_update_p95_ms`. The worker limits `sim_p95_ms` and `job_p99_ms`
    stay on raw time (§3);
  - in "Why held ticks have no verdict", the first cause's reason ("a main-thread hitch delays
    the post, which the on-time share already judges"). §1 says what judges it now; the
    conclusion (no held-tick verdict) and the `held_ticks` above 9 condition stay.
- **ADR 0011 §5 and its acceptance note:** the same on-time rows.
- **ADR 0012 §7**, the "Unchanged" bullet "frame pacing, the heavy window, the draw-call ceiling
  and the fog limit": its frame-pacing part only (§1, §2). The heavy window, the draw-call
  ceiling and the fog limit's value stay; the fog limit's measured quantity is normalised (§3).

It keeps:
- **Michael's answer 1:** the gate runs on his Pixel 9a for good, every CPU-time limit is the 2021
  limit divided by k = 2.5, and the device, k, the 2021 limits and the divided values do not
  change;
- `late_ticks_max` 0, `draw_calls_max` 60, `release_only`, `heavy_rigs` 135 and `heavy_frames_min`
  600;
- the three warm runs of the gate;
- ADR 0012 §4's rationale for the worker limits (half the period, the other half a factor 2
  against a slower or efficiency core and heat) and plan risk 9, because the worker is not
  normalised.

## Context

### What the runs showed
All on the Pixel 9a, release template (PR #35 release runs 1 and 2; spike PR #41).

| Run | Mode | On time (≤ 17.5 ms) | Max interval | Other-frame work p95 |
| --- | --- | --- | --- | --- |
| Release run 1 | 1, tick in the frame | 90.5 % | 29.54 ms | 4.18 ms |
| Release run 2 | 1, tick in the frame | 91.6 % | - | 4.37 ms |
| Release run 2 | 2, code rings (much more render work) | 87.9 % | - | 7.27 ms |
| Release run 2 | 4, GDScript worker | 95.0 % | - | 6.04 ms |
| Spike session | 4, GDScript worker | 98.2 % | 21.75 ms | 6.60 ms |
| Spike session | 5, C++ worker (almost idle) | 93.6 % | 20.41 ms | 6.93 ms |

**Problem 1: the on-time share measures jitter, not dropped frames.**
- With the same work, mode 4 measured 95.0 % in one session and 98.2 % in another.
- Mode 5, whose worker is almost idle, measured 93.6 %.
- In the spike session, no interval in modes 4 and 5 exceeded 22 ms (release run 2 recorded no
  maximum). A frame that misses a vsync at 60 Hz shows as about 33 ms.

The reason lies in how Godot paces frames on Android under Compatibility (Godot 4.7.2 source):
- **Godot's frame loop.** It runs on the GLSurfaceView GLThread:
  - `onDrawFrame` calls `Main::iteration`;
  - that is process, then `RenderingServer::draw`, then `OS::add_frame_delay`, the `max_fps`
    limiter;
  - after that the GLThread calls `eglSwapBuffers`.
- **What it does not use.** There is no Swappy (Vulkan only), no Choreographer and no ADPF, and
  V-Sync cannot be changed.
- **What the probe's interval measures.** It is taken at the top of `_process`, so it measures the
  limiter's sleep and wake-up plus the BufferQueue's back-pressure.
- **Why a late frame often costs nothing.** The display queue (typically 2 buffers) absorbs a frame
  that is a few ms late. A real missed latch costs a whole extra period.

**Problem 2: raw CPU milliseconds follow the clock the governor picks.**
- **How the governor picks.** Linux schedutil sets the target frequency to 1.25 × utilisation ×
  f_max. A light periodic thread is therefore clocked down until it is about 80 % busy at the
  chosen clock.
- **What that does to raw times.** On a light main thread, raw ms can rise towards
  0.8 × 16.7 = 13.3 ms without a single dropped frame.
- **The phone data fit this:**
  - the same view work took 4.18-4.37 ms p95 with the tick in the frame, and 6.04-6.93 ms with
    the tick on the worker, even with an almost idle C++ worker;
  - with mode 2's extra render load, the same in-frame tick code ran 20 % faster (7.20 against
    9.04 ms mean). The probe does not reset the sim between modes, so mode 2 timed a later
    stretch of the same deterministic run; part of the difference may be the stretch (§5 fixes
    that for the calibration);
  - the fog patch p95 rose from 0.36-0.38 ms to 0.59-0.71 ms.
- **Android's docs say the same.** Microbenchmark: clocks drop when a benchmark does not fully use
  the CPU. ADPF's Fixed Performance Mode exists because results "won't be reliable if they aren't
  tested at fixed clock speeds".

### What GDScript can and cannot time
- **Available:**
  - `Time.get_ticks_usec`;
  - the `frame_pre_draw` and `frame_post_draw` signals;
  - `viewport_get_measured_render_time_cpu`;
  - `Engine.get_frames_drawn`;
  - `DisplayServer.screen_get_refresh_rate()` (AOSP: the rate the app experiences, per-app
    override first).
- **Not available:** present or vsync timestamps.
  - Perfetto's FrameTimeline does not support SurfaceViews, and Godot draws into one.
  - The ground truth is `EGL_ANDROID_get_frame_timestamps`, which needs native code.

### Source facts not re-run
The Context's explanations rest on facts from the first research run that are neither in the PR
#41 evidence comment nor re-run. None of them sets a threshold: §1-§3 rest on the measured runs
in the table above, and the calibration (§5) tests the consequences on the phone. Each is
re-proven, or corrected in this ADR, by the PR named:
- Godot 4.7.2's Android frame loop under Compatibility (GLSurfaceView GLThread; `onDrawFrame` calls
  `Main::iteration`; process, `RenderingServer::draw`, then `OS::add_frame_delay`, then
  `eglSwapBuffers`), and that this path uses no Swappy, Choreographer or ADPF and cannot change
  V-Sync: P26e cites the source files and lines at the `4.7.2-stable` tag in this ADR's
  acceptance note, or corrects Context;
- the display queue of typically 2 buffers: P26n2's card records the frame-interval histogram
  (extra slots 0, 1, 2, ≥ 3, §4), which shows whether a few-ms-late frame costs a slot;
- schedutil's target of 1.25 × utilisation × f_max (so a light thread settles at about 80 % busy):
  P26e cites the kernel source or documentation, and P26n2's C3 and C4 test its consequence (raw
  ms rising on a lighter thread) on the gate phone;
- Perfetto's FrameTimeline not supporting SurfaceViews: P26e cites the Perfetto documentation;
  it only explains why option D is not the gate;
- AOSP's `screen_get_refresh_rate()` reporting the rate the app experiences (per-app override
  first): P26n2's C1 prints the start and end values with two decimals;
- the Android documentation quotes (Microbenchmark clocks, ADPF Fixed Performance Mode): P26e
  cites the pages.

## Decision

### 1. Frame pacing: dropped frames, cadence and hitches
**Definitions**, each read at run start and at run end:
- `refresh_hz` = `DisplayServer.screen_get_refresh_rate()`, a float (Android
  `Display.getRefreshRate()`), used unrounded in P and V and printed with two decimals. A panel
  may report 59.94 or 59.999996 Hz; the phone cards so far printed only a rounded "60 Hz", so the
  raw value is not on record yet (P26n2 records it);
- the slot V = 1000 / `refresh_hz` ms;
- the period P = 1000 / min(`refresh_hz`, `Engine.max_fps`) ms, where `max_fps` 0 (unlimited,
  the project default; only ADR 0011's perf runs set 60) counts as `refresh_hz`, so P is then
  1000 / `refresh_hz`.

| Field (`PerfGateDef`) | Value | Rule |
| --- | --- | --- |
| `drop_slots` | 0.5 | A **dropped frame** is a frame interval above `drop_ms` = P + `drop_slots` × V. On the gate phone (60 Hz app-visible, `max_fps` 60) that is 25.0 ms, 1.5 periods. On a 120 Hz panel capped at 60 it would be 20.8 ms |
| `dropped_pct_max` | 1.0 | Dropped frames ≤ 1 % over the run and over the heavy window: at most 6 of 600 heavy-window frames. The same as "p99 interval ≤ 25 ms" |
| `cadence_pct_min` | 99.0 | `cadence_pct` = 100 × P / mean interval ≥ 99, over the run and over the heavy window. It catches sustained slowness that no single interval shows (24 ms frames run at 42 fps) |
| `hitches_max` | 0 | No interval of at least one tick period (`1_000_000 / Sim.TICK_RATE` µs = 66.7 ms) in the heavy window. The 1 % rule alone would pass a single stall. The run-wide count is shown without a verdict |
| `jitter_ms` | 17.5 | Diagnostic only, no verdict: the old share of intervals ≤ 17.5 ms, relabelled "jitter" |

**Held ticks.** ADR 0012 §4 gives held ticks no verdict, partly because "a main-thread hitch
delays the post, which the on-time share already judges". With the on-time share gone, the
dropped-frame and hitch rules take that role. A main-thread hitch holds a tick only when it
delays the post by the period minus the job time, at least about 40 ms for a job inside
`job_p99_ms` (66.7 − 26.7). Such a frame interval is far above `drop_ms` (25 ms), so it counts as
a dropped frame (at most 1 %), and from 66.7 ms on as a hitch (none allowed in the heavy
window). The other cause, a slow job, stays judged by `job_p99_ms` and `late_ticks_max` as ADR
0012 §4 says. So held ticks still get no verdict, and the card still records `held_ticks`.

**Why these values.** They are derived, not tuned to the runs:
- **Why 1 %.** Any systematic miss at 1 Hz or faster (1.67 % of frames at 60 fps) fails, while
  rare one-off misses (driver or OS stalls) pass.
- **How strict that is.** Android vitals' slow-session rule is far looser: more than 25 % of frames
  slower than 50 ms, or than 34 ms.
- **Not divided by k.** Like the old on-time rule, none of these values is divided by k.

### 2. New `INVALID` rules
`INVALID` is for measurement faults only. A run is `INVALID`, with no verdict, when any of these
holds:
- `refresh_hz` at the end differs from `refresh_hz` at the start by more than
  `refresh_tolerance_pct` (1.0) of the start value;
- `refresh_hz` is below `max_fps` × (1 − `refresh_tolerance_pct` / 100), that is below 59.4 Hz
  for `max_fps` 60 (never with `max_fps` 0, which §1 counts as `refresh_hz`);
- the median interval is **below** P × (1 − 2 %): the limiter is not pacing at P (for example
  `max_fps` is not applied), so P is not the period the run was paced at.

No float is compared exactly: a 59.94 Hz panel with `max_fps` 60 is valid, and P is then
1000 / 59.94 = 16.68 ms. 1 % is far above the jitter of a reported refresh rate and far below
the nearest other mode (50 Hz is 17 % below 60), so it only separates a mode change from rounding.

A median **above** P × (1 + 2 %) is never `INVALID`: steady 24 ms frames (median 24 ms) or a run
in which most frames miss a vsync (median about 33 ms) is exactly the slowness the cadence and
dropped-frame rules exist to catch, so it is judged and fails them. ADR 0011 §5's and ADR 0012
§4's `INVALID` rules stay.

### 3. CPU-time limits: the same values; main-thread limits measured as peak-clock-equivalent time
**The values stay the 2021 limits divided by 2.5.** The main-thread limits are compared with
load-normalised time instead of raw wall-clock time. The worker limits stay on raw time.

| Field | Value | Compared with |
| --- | --- | --- |
| `work_p95_ms` | 5.6 | normalised p95 of main-thread frame work, all heavy-window frames |
| `work_tick_p95_ms` | 5.6 | the same, publish frames only |
| `fog_update_p95_ms` | 0.4 | normalised p95 of the fog patch (main thread) |
| `sim_p95_ms` | 13.3 | **raw** p95 of `job_usec` (worker), as ADR 0012 §4 |
| `job_p99_ms` | 26.7 | **raw** p99 of `job_usec`, as ADR 0012 §4 |

**Why the worker stays raw.** A normalisation by a reference loop cancels everything that slows
the loop, not only the clock: it also cancels the core the thread runs on. The energy-aware
scheduler places a light thread on a smaller core for the same reason schedutil lowers its clock,
and the gate phone has four A520 little cores; PR #35's release run 2 hypothesises (its own
label: "Hypothesis") that its bimodal worker times come from the worker sometimes landing on a
mid or little core. That was not measured. ADR 0012 §4 sets
`sim_p95_ms` at half the period precisely so that the other half, a factor 2, covers what k does
not model: a slower or efficiency core, and heat. Normalising the worker would remove that
margin's subject and leave the factor 2 unexplained. So `job_usec` stays raw, ADR 0012 §4's
rationale and plan risk 9 stay true, and the worker takes no reference samples.

**Why the main thread is normalised, core placement included.** The main-thread limits have no
such margin. Their false failures come from the governor and the scheduler slowing a lightly
loaded thread that still meets every frame (Context, problem 2). What the player sees is judged
by the pacing rules (§1); the CPU limits judge the work against peak-clock, big-core time, which
is how k is defined (below). Cancelling core placement there is intended.

**Method (main thread only):**
- **`ref`:** one fixed GDScript integer loop, `RefLoop.run()` with `ref_iterations` (1000)
  iterations (26-28 µs at p25-p50 on the cloud VM, evidence comment section 6; about
  0.11-0.13 ms on the phone by the measured release GDScript ratios).
- **`ref_peak`:** a back-to-back burst of `ref_burst_ms` (400 ms) on the main thread before
  every run, keeping its second half (200 ms at 400; no separate literal). That is long enough
  for schedutil and the energy-aware scheduler to reach the top clock and core. `ref_peak` is
  the p25 of the kept samples. The burst is the `burst_step` seam of `PerfHud.preflight()`,
  called in two places:
  - at scene entry: P50b's `perf_arena.gd` calls `preflight()` in its `_ready` before it starts
    the arena's runner, so no World and no job exist yet (after ADR 0013's self-check if that ADR
    is accepted);
  - on every "Run again" (P50a3): the handler calls `runner.wait_idle()`, then
    `preflight(runner, false)` (the burst alone; the self-check does not repeat), then
    `runner.start()` and `restart()`, so no job is in flight and the burst lies in no timed
    window. The gate's runs 2 and 3 come from "Run again" (gate procedure, step 1), so each of
    the three runs normalises against a peak measured right before it.
  - So it is measured per run, and thermal throttling makes it conservative: a hotter run gets a
    slower peak, never run 1's cooler one.
  - It is printed for every run, and across the three warm runs it doubles as a heat indicator.
- **`ref_span`:** at the top of the first `_process` of every frame, two back-to-back `RefLoop`
  runs; the first is a warm-up and is discarded, the second is the frame's sample. Per class
  (all heavy frames, publish frames, fog frames), `ref_span` is the p25 of those samples. Both
  runs are excluded from `work`.
  - Status (2026-10-13, see the acceptance note): the class `ref_span` is a diagnostic only
    (`speed_main_pct`, §4); the verdicts normalise each frame by its own sample (the formula
    below).
- **Why the warm-up** (evidence comment on PR #41,
  https://github.com/WackeySSL/rts-mobile/pull/41#issuecomment-6128912281, section 6; cloud VM
  with no frequency scaling, official 4.7.2 editor, 60 fps): a single cold run per frame came out
  slower than the burst by 19-31 % at p25 and 22-33 % at p50 (5 runs), because caches and
  predictors are cold after the frame's sleep, not because of the clock. Normalising by it would have cut every
  main-thread time by about a fifth for no reason. With the discarded warm-up run first, the
  frame's sample agreed with the burst within 0-4 % at both quantiles (3 runs). An earlier draft
  claimed that p25 agreed within 1.5-3 % without a warm-up; the re-run does not support it.
- **Why p25:** a low quantile ignores the samples that preemption or an interrupt lengthened. On
  the VM, p25 and p50 agree once the warm-up is in place, so the choice is not sensitive.
- **Only on perf runs.** The burst and the samples run only while the perf card or a
  `TimingProbe` is active, never in player builds or ordinary matches.
- **The formula:** normalised = raw × min(1, `ref_peak` / `ref_span`).
  - Status (2026-10-13, calibration recorded; see the acceptance note): by §5's outcome "C3 or
    C4 fails on the class method but holds on the per-frame method", the formula from 2026-10-13
    is the per-frame method: per main-thread class, the p95 over frames of
    `work_i × min(1, ref_peak / sample_i)`, where `sample_i` is frame i's sample. The class p25
    factor above stays printed as a diagnostic.
- **Normalised ≤ raw by construction.** A raw pass stays a pass. Normalisation can clear a failure
  that a low clock or a small core caused, never create one.
- **Answer 1 still holds.** k is a ratio of peak single-core speeds (ADR 0011 Context), so
  "2021 limit / k" is defined against peak-clock CPU time on the gate phone. Normalisation is what
  makes that comparison well defined for the main thread. Device, k, the 2021 limits and the
  divided values do not change.

### 4. What the probe, the perf card and `PerfGateDef` add
- **Pacing rows:**
  - `refresh_hz` (start and end), `period_ms` and `drop_ms`;
  - the dropped count and share, `cadence_pct` and hitches, each for the run and the heavy window;
  - median, p99 and max interval;
  - a histogram of extra slots (0, 1, 2, ≥ 3);
  - the jitter share.
- **CPU rows:**
  - `ref_peak_us` (p25 and p95 of the burst);
  - `speed_main_pct` (100 × `ref_peak` / `ref_span`) per main-thread class;
  - the normalised p95 next to the raw p95 for all heavy frames, publish frames, other frames
    and fog. Job p95 and p99 stay raw only.

  Raw values stay on the card.

  Status (2026-10-13, see the acceptance note): the normalised rows and the `_norm_` keys below
  carry the per-frame method (§3's status line); `speed_main_pct`, `speed_tick_pct` and
  `speed_fog_pct` (the class p25 factor) stay as diagnostics.
- **`PerfHud.summary()` keys** (the plan's "Perf arena" contract row) and the copy report's JSON,
  which uses the same names:
  - `on_time_pct` and `heavy_on_time_pct` become `jitter_pct` and `heavy_jitter_pct`
    (diagnostic);
  - `refresh_hz` becomes `refresh_hz_start` and `refresh_hz_end`;
  - new: `period_ms`, `drop_ms`, `dropped`, `dropped_pct`, `heavy_dropped`,
    `heavy_dropped_pct`, `cadence_pct`, `heavy_cadence_pct`, `hitches`, `heavy_hitches`,
    `frame_p99_ms` (next to `frame_p50_ms` and `frame_max_ms`), `extra_slots` (an `Array` of
    4 ints: 0, 1, 2 and ≥ 3 extra slots), `ref_peak_us`, `ref_peak_p95_us`, `speed_main_pct`,
    `speed_tick_pct`, `speed_fog_pct`, `work_p95_norm_ms`, `work_tick_p95_norm_ms`,
    `work_other_p95_norm_ms` and `fog_update_p95_norm_ms`;
  - the raw keys stay (`work_p95_ms`, `work_tick_p95_ms`, `work_other_p95_ms`,
    `fog_update_p95_ms`, the `job_*` keys). The main-thread verdicts compare the gate fields of
    the same names with the `_norm_` keys; `sim_p95_ms` and `job_p99_ms` compare with the raw
    `job_p95_ms` and `job_p99_ms`.
- **`PerfGateDef`:**
  - drops `on_time_ms` and `on_time_share_pct`;
  - adds `drop_slots`, `dropped_pct_max`, `cadence_pct_min`, `hitches_max`, `jitter_ms`,
    `median_tolerance_pct` 2.0 (one-sided, §2), `refresh_tolerance_pct` 1.0 (§2),
    `ref_iterations` 1000 and `ref_burst_ms` 400 (the burst keeps its second half, §3);
  - `pin_busy_pct` 85 only if §5's fallback applies (P50lp adds it to `PerfGateDef.gd` and
    `perf_gate.tres` under the plan's named exception 8, reviewed by the lead and qa-engineer,
    who own those files);
    - Status (2026-10-13, see the acceptance note): not taken; `pin_busy_pct` enters neither
      file;
  - `tests/project/test_cross_file_facts.gd` (P52) pins them.
- **Plan PRs:**
  - P38t (`PerfGateDef` fields, `RefLoop`; about +30 lines);
  - P38p (the new fields in `data/dev/perf_gate.tres`; about +10);
  - P50a (verdicts, `PerfHud.preflight(runner)` with its `burst_step` seam, the main-thread
    samples; about +40) and P50a2 (the §2 `INVALID`
    rules next to the ones P50a's split already moves there, about +20; card rows and copy keys,
    about +20). P50a's Depends cell gains "ADR 0014's acceptance note records P26n2's C1-C4
    outcome" (§5), because that outcome picks the formula P50a implements;
  - P50a3 ("Run again" re-runs the burst seam alone after `wait_idle()` and before the runner
    restarts, §3; about +15);
  - P50b (the `preflight()` call before the arena's runner starts, and a headless test that pins
    the order self-check if present, burst, runner start, with no job in flight, and that "Run
    again" runs the burst again but not the self-check; about +25, shared with ADR 0013's P50b
    row and counted once if both are accepted);
  - P50lp, only if §5's fallback applies (the load-pinned run, about +60);
    - Status (2026-10-13, see the acceptance note): not taken;
  - P52 (about +15).
  - No change to `TimingProbe`, `TickJob` (P38j), the worker-file scan (P38j2) or late ticks
    (P38w2): the worker takes no reference samples.

  A gate run judged before these merge does not exist, because the gate needs P50b.

### 5. One calibration run before the normalised verdicts become final
**The build:**
- a probe build on the never-merged spike branch (`claude/p26n-cpp-spike`, which has modes 1-5),
  plus the rows of §4 and the p25 of the discarded warm-up runs (§3), about 100 GDScript lines;
- next to §3's class method (one factor per frame class, from the p25 of that class's samples)
  it prints a **per-frame** normalised p95: the p95 over frames of
  `work_i × min(1, ref_peak / sample_i)`. With bimodal clocks the p95 frames may run slow while
  the class p25 sits near peak, so the class factor can under-correct. Both are ≤ raw, so
  neither can make a verdict stricter than raw;
- release template; no threshold moves with it.
- If ADR 0013 is rejected, mode 5 is simply skipped.

**Every mode times the same ticks.** The probe today never resets the sim between modes, so
mode 4 continues where mode 2 stopped. In the calibration build every mode starts from a fresh
`PerfProbeTick` advanced to the same tick (`PerfProbeLockstep.advance(sim, 3, ...)`), so modes 1,
2, 4 and 5 all time ticks 3-903, and every card prints its start tick.

**The run:** Michael runs modes 1, 2, 4 and 5 for 60 s each in one session, battery saver off and
the phone not charging (about 5 minutes).

**The checks:**

| Check | What must hold | Raw today |
| --- | --- | --- |
| C1 | Refresh is within `refresh_tolerance_pct` (1 %) of 60 Hz, 59.4-60.6 Hz, at start and end of every mode, the raw values printed with two decimals, and no median interval is below P × 0.98 (§2's one-sided rule; 16.33 ms at exactly 60 Hz) | |
| C2 | `ref_peak` is within ± 5 % across the four modes | |
| C3 | Normalised other-frame work p95 in modes 1, 4 and 5 is within ± 10 % of their mean | 4.37 / 6.60 / 6.93 ms, about ± 27 % |
| C4 | Normalised in-frame tick mean in mode 2 is within ± 10 % of mode 1 (same ticks) | 7.20 against 9.04 ms (different stretches) |
| C5 | Dropped frames, cadence and hitches are recorded for every mode, and the raw worker job mean and p95 are printed for modes 4 and 5 (information, no check: the worker is not normalised, §3) | expected 0 dropped in modes 4 and 5 (max 20-22 ms) |

**Build order.** The recorded outcome is an input of P50a, not a later correction: P50a's
Depends cell names "ADR 0014's acceptance note records P26n2's C1-C4 outcome", and P50a
implements the one formula that the note names. P26n2 needs only the spike branch and about five
minutes of Michael's time, and P50a is far down lane B, so the wait should cost no slot; if the
note is still open when lane B reaches P50a, lane B first takes the later rows that do not need
P50a (P45, P44a, P44b, P47, P47p), as lane A does for P54 in ADR 0013's plan.

Status (2026-10-13, see the acceptance note): the run is recorded, so P50a waits for nothing
outside its lane; the outcome is "C3 or C4 fails on the class method but holds on the per-frame
method", and the other outcomes below did not apply.

**Outcomes:**
- **C1-C4 hold:** the normalised verdicts are final, and the lead records the run in this ADR's
  acceptance note.
- **C1 fails:** the session is `INVALID` (a measurement fault, not a result). Michael reruns it
  with the cause recorded (for example a per-app refresh override).
- **C2 fails:** the burst does not reach a stable peak, so every normalised value is unreliable.
  `ref_burst_ms` is lengthened once (to 800) and the run repeated; if C2 still fails, the
  load-pinned fallback below applies, as for C3-C4.
- **C3 or C4 fails on the class method but holds on the per-frame method:** the per-frame method
  becomes the formula of §3 (decided here, so no new ADR; the acceptance note records it), and
  P50a implements that one (the same samples, no extra lines worth counting).
- **C3 or C4 fails on both methods: the fallback.** A separate "load-pinned" CPU run pads each
  main-thread frame to at least `pin_busy_pct` (85) % of P of busy time, so schedutil's 80 % rule
  drives the clocks to the top. The main-thread CPU verdicts then come from that run, and pacing
  from the normal one. P50a then implements the class formula for the normal run's printed
  values only, and the conditional plan row **P50lp** (touch-ux-dev, about +60 lines, Depends
  P50a2) builds the padded run, its `pin_busy_pct` field (in the lead's `PerfGateDef.gd` and qa's
  `perf_gate.tres`, under the plan's named exception 8), and the verdict source switch; the gate
  procedure gains the second run. P50lp exists only if this outcome is recorded.
  - It runs after the pacing runs, with the same conditions (battery saver off, not charging),
    so its heat cannot spill into the runs that pacing verdicts come from; `ref_peak` is printed
    for every run, so carry-over is visible.
  - This costs a second run per gate.
  - It is untested whether Pixel vendor governors follow the 80 % rule.
- **The fallback also fails:** the main-thread CPU limits could only be warnings. That conflicts
  with answer 1, so Michael decides, and the lead brings it back to him then.

The pacing verdicts (§1) do not depend on the calibration.

### 6. Remedies if pacing fails
None is adopted now. Each would need its own ADR, and only if the dropped-frame verdict fails:
- an ADPF performance-hint session (native code);
- Swappy (Vulkan only, so a renderer change);
- EGL present timestamps (`EGL_ANDROID_get_frame_timestamps`) as ground truth.

An optional cross-check in the calibration build reads the EGL timestamps from the spike's
library. It is untested whether Godot's GLThread has the context current inside `_process`.

### 7. Docs on acceptance (lead, docs PR P26e)
P26e carries the docs of whichever ADRs Michael accepts. If he accepts only this one, P26e holds
only this list; if he accepts both, it holds both lists (ADR 0013 §14).
- **Status lines**, replacing the one-line pointers the draft added:
  - ADR 0011 §5 (the pacing rule "interval at most 17.5 ms for 95 % of frames") and its acceptance
    note (the rows `on_time_ms` and `on_time_share_pct`): superseded by ADR 0014 §1 and §2;
  - ADR 0012 §4: the rows `on_time_ms` and `on_time_share_pct` (§1, §2), the measured quantity of
    `work_p95_ms`, `work_tick_p95_ms` and `fog_update_p95_ms` (§3), and the first cause in "Why
    held ticks have no verdict" (now judged by the dropped-frame and hitch rules, §1 "Held
    ticks");
  - ADR 0012 §7: "frame pacing" in the "Unchanged" bullet (§1, §2); the heavy window, the
    draw-call ceiling and the fog limit stay.
- **The plan** goes to the next plan revision at acceptance (15: P26d took revisions 12 and 13, and this PR, P26b, revision 14), with
  "ADR 0014: changes" folded into the rows: the contract rows `TimingProbe`, `PerfStats`,
  `PerfGateDef` and "Perf arena" (the `summary()` keys of §4), P38t, P38p, P50a, P50a2, P50a3, P50b, P52, named exception 8, the
  gate procedure, the test plan and the risks, plus the calibration row P26n2 (and P50lp if §5's
  fallback applies).
  - Status (2026-10-13, see the acceptance note): P50lp is not taken.
- **This ADR's acceptance note** records Michael's answer and the citations (or corrections) that
  "Source facts not re-run" assigns to P26e; after the calibration run (§5) it also records C1-C5
  and which outcome applies.
- No CLAUDE.md, skill, ROADMAP or agent text changes: the ROADMAP gate line ("150 units at 60
  fps") stays, and only the measures behind it change.

## Options considered
**Pacing:**
- **A: keep 17.5 ms / 95 %.** Rejected. It flips its verdict between sessions with the same work:
  mode 4 (the GDScript worker) measured 95.0 % in release run 2 and 98.2 % in the spike session,
  and mode 5, with less work (an almost idle C++ worker), measured 93.6 %.
- **B: dropped frames only.** Rejected. It cannot see sustained 24 ms frames (42 fps), and it
  passes a single long stall.
- **C: dropped share, cadence, zero hitches, and the `INVALID` rules.** Chosen. It needs GDScript
  only, and every value is derived from the refresh rate and the tick period.
- **D: EGL present timestamps.** Not chosen as the gate: it needs native code, works on Android
  only, and is untested on Godot's GLThread. It stays an optional cross-check.

**CPU:**
- **1: raw ms.** Rejected. It gives false failures under DVFS (6.0-6.9 ms raw against 5.6 ms while
  frames are on time).
- **2: main-thread limits normalised, worker limits raw, the same values.** Chosen. It keeps
  answer 1 and one run per gate, needs no tools, and leaves ADR 0012 §4's worker margin for small
  cores and heat intact (§3).
- **2b: the worker normalised as well.** Rejected. A reference loop cannot tell a low clock from a
  little core, so the job p95 would be scaled to big-core time and ADR 0012 §4's factor 2 would
  lose its subject.
- **3: a load-pinned run.** This is the fallback of §5.
- **4: the limits as warnings only.** Rejected. It conflicts with answer 1, so only Michael could
  choose it.
- **5: adb Fixed Performance Mode.** Rejected for the gate. It needs a computer with adb, and its
  operating point is below peak and specific to the device. It is allowed as an optional
  cross-check.
- **ADPF hint session.** It steers clocks and measures nothing. It is a remedy (§6), not a method.

## Consequences
- **The gate's verdicts track what players see and what k models.** Pacing judges dropped
  frames. Main-thread CPU judges peak-clock work; the worker is judged raw, with ADR 0012 §4's
  margin.
- **The card gets about 15 rows**, and on perf runs each frame carries two ref runs (the warm-up
  and the sample) of about 0.11-0.13 ms each, about 0.22-0.26 ms together (about 4-5 % of the
  5.6 ms limit), which the timings exclude. That adds about 1.5 % of main-thread utilisation, so
  its own effect on the governor is small. Player builds take no samples.
- **A main-thread miss may remain after normalisation.** Raw publish-frame work was 6.3-8.5 ms and
  the fog patch 0.71 ms, against 5.6 and 0.4. That would be a finding for the view PRs (P40, P44a,
  P45, P47), not for the method.
- **Risks:**
  - **Intervals are a proxy.** They are timed at frame start, not at present. A run of 18-24 ms
    frames can repeat frames on screen without any interval crossing 25 ms. The cadence rule
    bounds this, but the ground truth needs EGL.
  - **Normalisation assumes the work scales with the clock like the integer ref loop.**
    Memory-bound or driver-bound parts (the fog texture upload, GL calls) scale less, so their
    normalised value can be optimistic. C3 and C4 check this for view work and the in-frame
    tick, not for the fog patch.
  - **A cold sample biases the ratio.** Without the warm-up run, a frame's sample was slower than
    the burst at a fixed clock by 19-31 % at p25 and 22-33 % at p50 (§3). The warm-up removed that on the VM (0-4 %); the
    phone's cores may need more than one run to warm up, which C2-C4 would show only as noise.
    The calibration build prints the p25 of the warm-up runs next to the samples, so a remaining
    gap is visible.
  - **Main-thread normalisation also cancels core placement.** A main thread that EAS moved to a
    smaller core is judged as if on a big core. That is intended (§3), and the pacing rules still
    judge what the player sees.
  - **On Android 15+ the panel may run at 120 Hz while the app sees 60 Hz.** A half-period judder
    is then invisible to the 25 ms rule.
  - **Wall-clock work includes preemption** (the worker landing on the main thread's core).
    Thread CPU time would need native code.
  - **A per-run `ref_peak` normalises against the throttled peak** (the burst runs before every
    run, "Run again" included, §3). That hides heat from the main-thread CPU verdicts. The pacing verdict, the raw worker verdicts and the printed
    `ref_peak` still show it.
  - **The 1 %, 99 % and zero-hitch limits are policy limits**, derived from the 1 Hz cadence and
    the tick period, not measured. They are part of what Michael accepts with this ADR.

## Acceptance note (2026-10-12)
Michael answered the four questions of the plan's amendment ("Open questions for Michael (ADR
0013/0014)") in chat on 2026-10-12, verbatim: **"1 ja, 2 A, 3 ja, 4 ja"**.
- **Answer 3, yes: this ADR is accepted, and Michael does the calibration run of §5** (about 5
  minutes on his Pixel 9a, plan row P26n2).
- Answers 1 and 4 accept ADR 0013 and its agent-file changes (its own acceptance note). Answer 2
  (A) keeps the web preview on the GDScript twins (ADR 0013 §7, option A). For this ADR that
  means: the web build keeps running the sim in the frame (`SYNC`), and its card's frame
  numbers do not gate (gate procedure, step 2); only its hashes count.

**Applied on acceptance (§7), in P26b** (the PR that carried the proposal; the plan's revision 15
folds P26e's row into P26b):
- status lines in ADR 0011 (§5 and its acceptance note) and ADR 0012 (§4, including the first
  cause in "Why held ticks have no verdict", and §7's "frame pacing"), replacing the draft's
  pointers;
- the plan's revision 15: the contract rows `TimingProbe`, `PerfStats`, `PerfGateDef` and "Perf
  arena", P38t, P38p, P50a, P50a2, P50a3, P50b, P52, named exception 8, the gate procedure, the
  test plan, the risks and the calibration row P26n2;
- no CLAUDE.md, skill, ROADMAP or agent text changes (§7).

**Source facts not re-run: the citations assigned to the docs PR.** All four stand; Context
needs no correction.
- **Godot 4.7.2's Android frame loop under Compatibility.** Tag `4.7.2-stable`, commit
  `ed1daf0bf001b61586d9930840f2f1394092c079`:
  - with the `opengl3` driver, `Godot.kt` (lines 547-548) creates a `GodotGLRenderView`, which
    `extends GLSurfaceView` (`platform/android/java/lib/src/main/java/org/godotengine/godot/GodotGLRenderView.java:78`);
    the vendored `gl/GLSurfaceView.java` `extends SurfaceView` (line 166);
  - its `GLThread` (line 1287) runs `guardedRun()` (line 1336), which calls
    `view.mRenderer.onDrawFrame(gl)` (line 1604) and, when that returns true,
    `mEglHelper.swap()` (line 1613), that is `eglSwapBuffers` (line 1205);
  - `gl/GodotRenderer.java`: `onDrawFrame` (line 55) calls `GodotLib.step()` (line 61);
  - `platform/android/java_godot_lib_jni.cpp`: `Java_org_godotengine_godot_GodotLib_step`
    (line 292) calls `os_android->main_loop_iterate` (line 354), which calls `Main::iteration()`
    (`platform/android/os_android.cpp`, lines 380 and 392);
  - `main/main.cpp`: `Main::iteration()` (line 4921) runs the main loop's `process` (line 5062),
    then `RenderingServer::draw` (lines 5089 and 5093), then `OS::add_frame_delay` (line 5178);
  - no Swappy, Choreographer or ADPF on this path: no file under `platform/android/` (Java,
    Kotlin or C++) names `Choreographer` or `PerformanceHint`, and Swappy is compiled only into
    the Vulkan driver (`SWAPPY_FRAME_PACING_ENABLED`, set in `platform/android/detect.py` line 262
    and read only in `drivers/vulkan/rendering_device_driver_vulkan.cpp` and `.h`);
  - V-Sync cannot be changed: `DisplayServerAndroid::window_set_vsync_mode`
    (`platform/android/display_server_android.cpp`, lines 979-985) acts only on the
    RenderingDevice context (`RD_ENABLED`, Vulkan), and `window_get_vsync_mode` returns
    `VSYNC_ENABLED` otherwise (lines 987-994).
- **schedutil's 1.25 × utilisation × f_max.** Linux mainline at `v6.1` and `v6.6`:
  `Documentation/scheduler/schedutil.rst` (line 140: `f_des := min( f_max, 1.25 u * f_max )`);
  `kernel/sched/cpufreq_schedutil.c` (v6.1, line 134: "Take C = 1.25 for the frequency tipping
  point at (util / max) = 0.8", applied in `get_next_freq`, line 140, through `map_util_perf`,
  which adds `util >> 2`, `include/linux/sched/cpufreq.h` line 34). This is the upstream
  governor; whether the Pixel's vendor kernel follows it is what C3 and C4 test, as §5 says.
- **Perfetto's FrameTimeline and SurfaceViews.**
  https://perfetto.dev/docs/data-sources/frametimeline (source
  `docs/data-sources/frametimeline.md` in `google/perfetto`, read 2026-10-12): "SurfaceViews are
  currently **not supported**, but will be, in future." Godot draws into one (above).
- **The Android documentation quotes** (read 2026-10-12):
  - Microbenchmark overview,
    https://developer.android.com/topic/performance/benchmarking/microbenchmark-overview: "Clocks
    on mobile devices dynamically change from high state, for performance, to low state, to save
    power or when the device gets hot", and locked clocks keep them from going "low if a
    benchmark isn't fully utilizing the CPU";
  - ADPF Fixed Performance Mode,
    https://developer.android.com/games/optimize/adpf/fixed-performance-mode: "your results won't
    be reliable if they aren't tested at fixed clock speeds" (Context quotes it verbatim).

**Calibration (§5): recorded 2026-10-13 (docs PR P26g).**
- **The run.** Michael ran P26n2 on his Pixel 9a on 2026-10-13: build `db02f7f` on the
  never-merged spike branch `claude/p26n-cpp-spike` (PR #41), release template, Godot
  4.7.2-stable (official); modes 1, 2, 4 and 5 for 60 s each in one session, battery saver off,
  not charging; every mode from start tick 3; mode 3 sat out (§5 does not use it). The four
  reports Michael pasted are kept verbatim in "The four reports" at the end of this note, the
  source of every value below. The lead's evidence comment on PR #41,
  https://github.com/WackeySSL/rts-mobile/pull/41#issuecomment-6138576314, summarises them. Its
  ranges are rounded and leave out the fog row (raw C3 spread "± 27 %", `speed_main` 19-30 %,
  sample p25 71-112 µs, p50 82-179 µs), so they are narrower than the ones below, which follow
  the reports.
- **The checks** (values per mode 1 / 2 / 4 / 5 unless named). Both methods normalise with
  `f_i = min(1, ref_peak / sample_i)`, where `sample_i` is frame i's sample. "Per-frame" applies
  each frame's own factor: for C3 the p95 over other frames of `work_i × f_i`, for C4 the mean
  over publish frames of `tick_i × f_i`. "Class" is §3's class p25 factor,
  `min(1, ref_peak / ref_span)`, applied to the raw p95 (C3) or the raw mean (C4):

| Check | Recorded | Result |
| --- | --- | --- |
| C1 | `refresh_hz` 60.00 at start and end in all four modes; median interval 16.657 / 16.693 / 16.674 / 16.675 ms, all ≥ 16.333 ms (P × 0.98) | holds |
| C2 | `ref_peak` p25 = p95 = 21.0 µs in all four modes (burst n 9362-9433): 0 % spread | holds (limit ± 5 %) |
| C3, raw | other-frame work p95, modes 1 / 4 / 5: 4.104 / 6.009 / 6.572 ms, mean 5.562: −26.2 % / +8.0 % / +18.2 % | no check |
| C3, class | 1.002 / 1.127 / 1.232 ms, mean 1.120: −10.56 % / +0.60 % / +9.97 % | fails (mode 1; modes 4 and 5 within) |
| C3, per-frame | 1.044 / 0.985 / 1.013 ms, mean 1.014: +3.0 % / −2.9 % / −0.1 % | holds |
| C4, raw | in-frame tick mean, mode 1 → mode 2 (from start tick 3, 899 tick frames in both): 8.977 → 7.383 ms (−17.8 %) | no check |
| C4, class | 1.683 → 1.891 ms (+12.4 %) | fails |
| C4, per-frame | 1.739 → 1.693 ms (−2.6 %) | holds |
| C5 | dropped 0 / 0 / 1 (0.03 %, one 36.49 ms interval) / 0; cadence 100.03 / 100.05 / 100.05 / 100.04 %; hitches 0 in all; extra slots 0/1/2/≥3: all intervals 0 except mode 4's one interval at 1; raw worker job mean / p95: mode 4 (GDScript) 11.147 / 19.442 ms, mode 5 (C++) 0.337 / 0.609 ms; late and held ticks 0 (modes 4 and 5) | recorded, no check |

- **The outcome (§5):** C1 and C2 hold; C3 and C4 fail on the class method and hold on the
  per-frame method. That is §5's outcome "C3 or C4 fails on the class method but holds on the
  per-frame method": the per-frame method is the formula of §3 from 2026-10-13 (decided by §5,
  so no new ADR), and P50a implements that one, with the same samples. The class p25 factor
  (`ref_span` per class, `speed_main_pct`) stays printed as a diagnostic. No repeat (C1 and C2
  hold), no load-pinned fallback: P50lp is not taken, and `pin_busy_pct` enters neither
  `PerfGateDef.gd` nor `perf_gate.tres`. Normalised ≤ raw still holds, because every per-frame
  factor is at most 1. The pacing verdicts (§1) did not depend on the run.
- **Observations** (no decision rests on them):
  - in frames the main thread ran at `speed_main` 18.6-29.6 % of the burst (frame-sample p25
    71-113 µs, p50 82-181 µs over all four rows, fog included, against the burst's 21 µs),
    while every mode met the pacing rules (C5);
  - the discarded warm-up run is only 7-10 % slower than the frame sample (p25 78-123 µs
    against the all-frames sample's 71-112 µs), while that sample is 3.4-5.3 × the burst, so the
    slowdown is mostly the clock or the core placement, not cold caches;
  - normalised to peak, the GDScript mock tick in the frame is about 1.7 ms (C4's per-frame
    1.693-1.739 ms against 7.4-9.0 ms raw).

**The four reports** (verbatim as Michael pasted them in the session on 2026-10-13; every
value in the table and the observations above is read from them):

<details><summary>Mode 1: sprite rings, GDScript tick in the frame</summary>

```text
PERF PROBE P26s | sprite rings | done
tick impl: GDScript
start tick 3 (a fresh tick in every mode)
device Pixel 9a | Android | Godot 4.7.2-stable (official) release
screen (2424, 1080) px | refresh_hz start 60.00, end 60.00 | max_fps 60
frames 3601 in 60.0 s | jitter (<= 17.5 ms, diagnostic, was on time) 91.5 %
frame interval (wall clock): p95 17.94, mean 16.66, max 24.76 ms
process (_process start to draw): p95 14.25, mean 4.24, max 20.96 ms
render CPU (viewport time): p95 1.93, mean 1.59, max 5.76 ms
draw calls (monitor, HUD in): p95 13.00, mean 13.00, max 13.00 calls
work, tick frames (process + render): p95 18.26, mean 12.89, max 23.88 ms
work, other frames (process + render): p95 4.10, mean 3.48, max 7.70 ms
mock tick (15 Hz, usec timer): p95 12.93, mean 8.98, max 17.86 ms
flow slice 512 cells (usec timer): p95 4.01, mean 3.27, max 4.22 ms
fog patch (bytes + set_data + update, 5 Hz): p95 0.35, mean 0.27, max 0.46 ms
pacing, window = the whole timed run (heavy throughout): P 16.67 ms, V 16.67 ms, drop_ms 25.00
dropped (interval > drop_ms) 0 of 3601 (0.00 %) | cadence 100.03 % | hitches (>= 66.7 ms) 0
interval median 16.66, p99 20.35, max 24.76 ms | extra slots 0/1/2/>=3: 3601/0/0/0
ref loop (1000 iterations): ref_peak p25 21.0, p95 21.0 us (400 ms burst, second half, n 9385) | warm-up p25 107.0 us (n 3602, discarded)
cpu all frames, work: n 3601, ref_span p25 100.0 us (p50 112.0, p95 129.0), speed_main 21.0 % | p95 raw 15.907, norm class 3.340, norm frame 3.037 ms
cpu tick frames, work: n 899, ref_span p25 112.0 us (p50 112.0, p95 138.0), speed_main 18.8 % | p95 raw 18.260, norm class 3.424, norm frame 3.501 ms
cpu other frames, work: n 2702, ref_span p25 86.0 us (p50 112.0, p95 121.0), speed_main 24.4 % | p95 raw 4.104, norm class 1.002, norm frame 1.044 ms
cpu fog patches: n 300, ref_span p25 112.0 us (p50 112.0, p95 150.0), speed_main 18.8 % | p95 raw 0.349, norm class 0.065, norm frame 0.079 ms
in-frame tick mean: raw 8.977, norm class 1.683, norm frame 1.739 ms
CALIBRATION P26n2 | mode 1 (sprite rings) | start_tick 3
C1 refresh_hz_start=60.00
C1 refresh_hz_end=60.00
C1 max_fps=60
C1 period_ms=16.667
C1 median_ms=16.657
C1 median_floor_ms=16.333
C2 ref_peak_p25_us=21.0
C2 ref_peak_p95_us=21.0
C2 warmup_p25_us=107.0
C3 other_ref_span_us=86.0
C3 other_ref_p50_us=112.0
C3 other_ref_p95_us=121.0
C3 other_work_p95_raw_ms=4.104
C3 other_work_p95_norm_class_ms=1.002
C3 other_work_p95_norm_frame_ms=1.044
C4 tick_ref_span_us=112.0
C4 tick_ref_p50_us=112.0
C4 tick_ref_p95_us=138.0
C4 tick_mean_raw_ms=8.977
C4 tick_mean_norm_class_ms=1.683
C4 tick_mean_norm_frame_ms=1.739
C5 frames=3601
C5 dropped=0
C5 dropped_pct=0.00
C5 cadence_pct=100.03
C5 hitches=0
```

</details>

<details><summary>Mode 2: code rings, GDScript tick in the frame</summary>

```text
PERF PROBE P26s | code rings | done
tick impl: GDScript
start tick 3 (a fresh tick in every mode)
device Pixel 9a | Android | Godot 4.7.2-stable (official) release
screen (2424, 1080) px | refresh_hz start 60.00, end 60.00 | max_fps 60
frames 3602 in 60.0 s | jitter (<= 17.5 ms, diagnostic, was on time) 89.2 %
frame interval (wall clock): p95 18.76, mean 16.66, max 24.01 ms
process (_process start to draw): p95 12.01, mean 3.53, max 17.12 ms
render CPU (viewport time): p95 5.38, mean 4.35, max 7.10 ms
draw calls (monitor, HUD in): p95 462.00, mean 462.00, max 462.00 calls
work, tick frames (process + render): p95 18.39, mean 13.52, max 21.54 ms
work, other frames (process + render): p95 7.08, mean 6.01, max 10.98 ms
mock tick (15 Hz, usec timer): p95 11.01, mean 7.38, max 13.32 ms
flow slice 512 cells (usec timer): p95 3.91, mean 3.09, max 4.14 ms
fog patch (bytes + set_data + update, 5 Hz): p95 0.34, mean 0.26, max 0.46 ms
pacing, window = the whole timed run (heavy throughout): P 16.67 ms, V 16.67 ms, drop_ms 25.00
dropped (interval > drop_ms) 0 of 3602 (0.00 %) | cadence 100.05 % | hitches (>= 66.7 ms) 0
interval median 16.69, p99 21.30, max 24.01 ms | extra slots 0/1/2/>=3: 3602/0/0/0
ref loop (1000 iterations): ref_peak p25 21.0, p95 21.0 us (400 ms burst, second half, n 9387) | warm-up p25 78.0 us (n 3603, discarded)
cpu all frames, work: n 3602, ref_span p25 71.0 us (p50 82.0, p95 113.0), speed_main 29.6 % | p95 raw 16.405, norm class 4.852, norm frame 3.864 ms
cpu tick frames, work: n 899, ref_span p25 82.0 us (p50 83.0, p95 114.0), speed_main 25.6 % | p95 raw 18.391, norm class 4.710, norm frame 4.309 ms
cpu other frames, work: n 2703, ref_span p25 71.0 us (p50 82.0, p95 113.0), speed_main 29.6 % | p95 raw 7.082, norm class 2.095, norm frame 2.583 ms
cpu fog patches: n 300, ref_span p25 83.0 us (p50 100.0, p95 134.0), speed_main 25.3 % | p95 raw 0.340, norm class 0.086, norm frame 0.080 ms
in-frame tick mean: raw 7.383, norm class 1.891, norm frame 1.693 ms
CALIBRATION P26n2 | mode 2 (code rings) | start_tick 3
C1 refresh_hz_start=60.00
C1 refresh_hz_end=60.00
C1 max_fps=60
C1 period_ms=16.667
C1 median_ms=16.693
C1 median_floor_ms=16.333
C2 ref_peak_p25_us=21.0
C2 ref_peak_p95_us=21.0
C2 warmup_p25_us=78.0
C4 tick_ref_span_us=82.0
C4 tick_ref_p50_us=83.0
C4 tick_ref_p95_us=114.0
C4 tick_mean_raw_ms=7.383
C4 tick_mean_norm_class_ms=1.891
C4 tick_mean_norm_frame_ms=1.693
C5 frames=3602
C5 dropped=0
C5 dropped_pct=0.00
C5 cadence_pct=100.05
C5 hitches=0
```

</details>

<details><summary>Mode 4: sprite rings, GDScript worker tick</summary>

```text
PERF PROBE P26s | sprite rings, worker tick | done
tick impl: GDScript, worker from tick 3
start tick 3 (a fresh tick in every mode)
device Pixel 9a | Android | Godot 4.7.2-stable (official) release
screen (2424, 1080) px | refresh_hz start 60.00, end 60.00 | max_fps 60
frames 3602 in 60.0 s | jitter (<= 17.5 ms, diagnostic, was on time) 94.0 %
frame interval (wall clock): p95 17.58, mean 16.66, max 36.49 ms
process (_process start to draw): p95 3.85, mean 2.53, max 13.46 ms
render CPU (viewport time): p95 2.81, mean 1.83, max 6.13 ms
draw calls (monitor, HUD in): p95 13.00, mean 13.00, max 13.00 calls
work, tick frames (process + render): p95 6.52, mean 4.59, max 10.13 ms
work, other frames (process + render): p95 6.01, mean 4.28, max 14.72 ms
mock tick (15 Hz, usec timer): p95 18.88, mean 10.90, max 23.56 ms
flow slice 512 cells (usec timer): p95 4.19, mean 3.29, max 4.34 ms
fog patch (bytes + set_data + update, 5 Hz): p95 0.62, mean 0.40, max 1.41 ms
worker tick usec: mean 10897.5, p95 18884.0, max 23559.0 | flow slice usec: mean 3293.8, p95 4194.0, max 4343.0
late ticks (job post to done above 66.7 ms): 0 of 900 ticks
held ticks (boundary reached with the job running): 0 of 900 ticks
job post to done (worker wake-up + tick + slice): p95 19.60, mean 11.40, max 24.68 ms
worker job (tick + slice, wall clock on the worker): p95 19.44, mean 11.15, max 24.48 ms
pacing, window = the whole timed run (heavy throughout): P 16.67 ms, V 16.67 ms, drop_ms 25.00
dropped (interval > drop_ms) 1 of 3602 (0.03 %) | cadence 100.05 % | hitches (>= 66.7 ms) 0
interval median 16.67, p99 19.80, max 36.49 ms | extra slots 0/1/2/>=3: 3601/1/0/0
ref loop (1000 iterations): ref_peak p25 21.0, p95 21.0 us (400 ms burst, second half, n 9433) | warm-up p25 120.0 us (n 3603, discarded)
cpu all frames, work: n 3602, ref_span p25 112.0 us (p50 113.0, p95 240.0), speed_main 18.8 % | p95 raw 6.136, norm class 1.150, norm frame 1.020 ms
cpu tick frames, work: n 899, ref_span p25 112.0 us (p50 113.0, p95 232.0), speed_main 18.8 % | p95 raw 6.517, norm class 1.222, norm frame 1.095 ms
cpu other frames, work: n 2703, ref_span p25 112.0 us (p50 113.0, p95 245.0), speed_main 18.8 % | p95 raw 6.009, norm class 1.127, norm frame 0.985 ms
cpu fog patches: n 300, ref_span p25 112.0 us (p50 113.0, p95 213.0), speed_main 18.8 % | p95 raw 0.618, norm class 0.116, norm frame 0.102 ms
CALIBRATION P26n2 | mode 4 (sprite rings, worker tick) | start_tick 3
C1 refresh_hz_start=60.00
C1 refresh_hz_end=60.00
C1 max_fps=60
C1 period_ms=16.667
C1 median_ms=16.674
C1 median_floor_ms=16.333
C2 ref_peak_p25_us=21.0
C2 ref_peak_p95_us=21.0
C2 warmup_p25_us=120.0
C3 other_ref_span_us=112.0
C3 other_ref_p50_us=113.0
C3 other_ref_p95_us=245.0
C3 other_work_p95_raw_ms=6.009
C3 other_work_p95_norm_class_ms=1.127
C3 other_work_p95_norm_frame_ms=0.985
C5 frames=3602
C5 dropped=1
C5 dropped_pct=0.03
C5 cadence_pct=100.05
C5 hitches=0
C5 job_mean_ms=11.147
C5 job_p95_ms=19.442
C5 job_tick_mean_ms=10.897
C5 job_tick_p95_ms=18.884
C5 job_done_mean_ms=11.397
C5 job_done_p95_ms=19.596
```

</details>

<details><summary>Mode 5: sprite rings, C++ worker tick</summary>

```text
PERF PROBE P26s | sprite rings, C++ worker tick | done
tick impl: C++ (android template_release arm64 -O3), worker from tick 3
start tick 3 (a fresh tick in every mode)
C++ matches GDScript: yes (60 ticks)
device Pixel 9a | Android | Godot 4.7.2-stable (official) release
screen (2424, 1080) px | refresh_hz start 60.00, end 60.00 | max_fps 60
frames 3602 in 60.0 s | jitter (<= 17.5 ms, diagnostic, was on time) 94.9 %
frame interval (wall clock): p95 17.51, mean 16.66, max 21.64 ms
process (_process start to draw): p95 4.25, mean 2.98, max 9.76 ms
render CPU (viewport time): p95 3.06, mean 2.07, max 10.88 ms
draw calls (monitor, HUD in): p95 13.00, mean 13.00, max 13.00 calls
work, tick frames (process + render): p95 7.60, mean 5.42, max 12.86 ms
work, other frames (process + render): p95 6.57, mean 4.93, max 13.02 ms
mock tick (15 Hz, usec timer): p95 0.47, mean 0.28, max 5.73 ms
flow slice 512 cells (usec timer): p95 0.21, mean 0.11, max 0.24 ms
fog patch (bytes + set_data + update, 5 Hz): p95 0.67, mean 0.40, max 0.95 ms
worker tick usec: mean 279.6, p95 475.0, max 5727.0 | flow slice usec: mean 113.5, p95 212.0, max 244.0
late ticks (job post to done above 66.7 ms): 0 of 900 ticks
held ticks (boundary reached with the job running): 0 of 900 ticks
job post to done (worker wake-up + tick + slice): p95 0.94, mean 0.50, max 5.89 ms
worker job (tick + slice, wall clock on the worker): p95 0.61, mean 0.34, max 5.78 ms
pacing, window = the whole timed run (heavy throughout): P 16.67 ms, V 16.67 ms, drop_ms 25.00
dropped (interval > drop_ms) 0 of 3602 (0.00 %) | cadence 100.04 % | hitches (>= 66.7 ms) 0
interval median 16.68, p99 18.34, max 21.64 ms | extra slots 0/1/2/>=3: 3602/0/0/0
ref loop (1000 iterations): ref_peak p25 21.0, p95 21.0 us (400 ms burst, second half, n 9362) | warm-up p25 123.0 us (n 3603, discarded)
cpu all frames, work: n 3602, ref_span p25 112.0 us (p50 179.0, p95 268.0), speed_main 18.8 % | p95 raw 6.827, norm class 1.280, norm frame 1.041 ms
cpu tick frames, work: n 899, ref_span p25 112.0 us (p50 179.0, p95 267.0), speed_main 18.8 % | p95 raw 7.595, norm class 1.424, norm frame 1.097 ms
cpu other frames, work: n 2703, ref_span p25 112.0 us (p50 179.0, p95 268.0), speed_main 18.8 % | p95 raw 6.572, norm class 1.232, norm frame 1.013 ms
cpu fog patches: n 300, ref_span p25 113.0 us (p50 181.0, p95 272.0), speed_main 18.6 % | p95 raw 0.668, norm class 0.124, norm frame 0.102 ms
CALIBRATION P26n2 | mode 5 (sprite rings, C++ worker tick) | start_tick 3
C1 refresh_hz_start=60.00
C1 refresh_hz_end=60.00
C1 max_fps=60
C1 period_ms=16.667
C1 median_ms=16.675
C1 median_floor_ms=16.333
C2 ref_peak_p25_us=21.0
C2 ref_peak_p95_us=21.0
C2 warmup_p25_us=123.0
C3 other_ref_span_us=112.0
C3 other_ref_p50_us=179.0
C3 other_ref_p95_us=268.0
C3 other_work_p95_raw_ms=6.572
C3 other_work_p95_norm_class_ms=1.232
C3 other_work_p95_norm_frame_ms=1.013
C5 frames=3602
C5 dropped=0
C5 dropped_pct=0.00
C5 cadence_pct=100.04
C5 hitches=0
C5 job_mean_ms=0.337
C5 job_p95_ms=0.609
C5 job_tick_mean_ms=0.280
C5 job_tick_p95_ms=0.475
C5 job_done_mean_ms=0.501
C5 job_done_p95_ms=0.935
```

</details>
