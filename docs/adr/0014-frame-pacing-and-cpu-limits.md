# ADR 0014: Frame pacing by dropped frames, and main-thread CPU-time limits normalised for clock scaling

Status: proposed, 2026-10-12 (revision 5: ADR 0012 §7's "frame pacing" joins the supersedes
list, and the calibration build also prints a per-frame normalised p95 that C3/C4 can choose.
Revision 4, after the completeness check of revision 3: §3's reference-loop claim was re-run
and corrected; each frame's sample now follows a discarded warm-up run). Nothing here applies until Michael accepts it. On acceptance the lead applies §7.

It does not depend on ADR 0013 (C++ kernels). Michael can accept either one, both or neither.
The calibration run below needs only the GDScript modes of the never-merged probe branches; the C++
mode is optional.

On acceptance it supersedes in part:
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

## Decision

### 1. Frame pacing: dropped frames, cadence and hitches
**Definitions**, each read at run start and at run end:
- `refresh_hz` = `DisplayServer.screen_get_refresh_rate()`;
- the slot V = 1000 / `refresh_hz` ms;
- the period P = 1000 / min(`refresh_hz`, `Engine.max_fps`) ms.

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
- `refresh_hz` differs between the start and the end of the run;
- `refresh_hz` is below `max_fps`;
- the median interval is **below** P × (1 − 2 %): the limiter is not pacing at P (for example
  `max_fps` is not applied), so P is not the period the run was paced at.

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
and the gate phone has four A520 little cores; PR #35's release run 2 attributes its bimodal
worker times to the worker sometimes landing on a mid or little core. ADR 0012 §4 sets
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
- **`ref`:** one fixed GDScript integer loop, `RefLoop.run()` with 1000 iterations (about 30 µs
  on the CI VM, about 0.11-0.13 ms on the phone by the measured release GDScript ratios).
- **`ref_peak`:** a back-to-back burst of at least 400 ms on the main thread before the run,
  keeping the last 200 ms. That is long enough for schedutil and the energy-aware scheduler to
  reach the top clock and core. `ref_peak` is the p25 of the kept samples.
  - It is measured per run, so thermal throttling makes it conservative.
  - It is printed, and across the three warm runs it doubles as a heat indicator.
- **`ref_span`:** at the top of the first `_process` of every frame, two back-to-back `RefLoop`
  runs; the first is a warm-up and is discarded, the second is the frame's sample. Per class
  (all heavy frames, publish frames, fog frames), `ref_span` is the p25 of those samples. Both
  runs are excluded from `work`.
- **Why the warm-up** (evidence comment on PR #41,
  https://github.com/WackeySSL/rts-mobile/pull/41#issuecomment-6128912281, section 6; cloud VM
  with no frequency scaling, official 4.7.2 editor, 60 fps): a single cold run per frame came out
  19-31 % slower than the burst at both p25 and p50 (5 runs), because caches and predictors are
  cold after the frame's sleep, not because of the clock. Normalising by it would have cut every
  main-thread time by about a fifth for no reason. With the discarded warm-up run first, the
  frame's sample agreed with the burst within 0-4 % at both quantiles (3 runs). An earlier draft
  claimed that p25 agreed within 1.5-3 % without a warm-up; the re-run does not support it.
- **Why p25:** a low quantile ignores the samples that preemption or an interrupt lengthened. On
  the VM, p25 and p50 agree once the warm-up is in place, so the choice is not sensitive.
- **Only on perf runs.** The burst and the samples run only while the perf card or a
  `TimingProbe` is active, never in player builds or ordinary matches.
- **The formula:** normalised = raw × min(1, `ref_peak` / `ref_span`).
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
    `median_tolerance_pct` 2.0 (one-sided, §2), `ref_iterations` 1000 and `ref_burst_ms` 400;
  - `tests/project/test_cross_file_facts.gd` (P52) pins them.
- **Plan PRs:**
  - P38t (`PerfGateDef` fields, `RefLoop`; about +30 lines);
  - P38p (the new fields in `data/dev/perf_gate.tres`; about +10);
  - P50a (verdicts, the burst, the main-thread samples; about +60, inside its named split) and
    P50a2 (card rows and copy keys; about +20);
  - P52 (about +10).
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
| C1 | Refresh is 60 Hz at start and end of every mode, and no median interval is below 16.67 ms − 2 % (§2's one-sided rule) | |
| C2 | `ref_peak` is within ± 5 % across the four modes | |
| C3 | Normalised other-frame work p95 in modes 1, 4 and 5 is within ± 10 % of their mean | 4.37 / 6.60 / 6.93 ms, about ± 27 % |
| C4 | Normalised in-frame tick mean in mode 2 is within ± 10 % of mode 1 (same ticks) | 7.20 against 9.04 ms (different stretches) |
| C5 | Dropped frames, cadence and hitches are recorded for every mode, and the raw worker job mean and p95 are printed for modes 4 and 5 (information, no check: the worker is not normalised, §3) | expected 0 dropped in modes 4 and 5 (max 20-22 ms) |

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
- **C3 or C4 fails on both methods: the fallback.** A separate "load-pinned" CPU run pads each main-thread frame
  to at least 0.85 × P of busy time, so schedutil's 80 % rule drives the clocks to the top. The
  main-thread CPU verdicts then come from that run, and pacing from the normal one.
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

### 7. Docs on acceptance (lead, docs PR P26c)
P26c carries the docs of whichever ADRs Michael accepts. If he accepts only this one, P26c holds
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
- **The plan** goes to revision 12 with "ADR 0014: changes" folded into the rows: the contract
  rows `TimingProbe`, `PerfStats`, `PerfGateDef` and "Perf arena" (the `summary()` keys of §4),
  P38t, P38p, P50a, P50a2, P52, the gate procedure, the test plan and the risks, plus the
  calibration row P26n2.
- **This ADR's acceptance note** records Michael's answer; after the calibration run (§5) it also
  records C1-C5 and which outcome applies.
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
  - **A cold sample biases the ratio.** Without the warm-up run, a frame's sample was 19-31 %
    slower than the burst at a fixed clock (§3). The warm-up removed that on the VM (0-4 %); the
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
  - **A per-run `ref_peak` normalises against the throttled peak.** That hides heat from the
    main-thread CPU verdicts. The pacing verdict, the raw worker verdicts and the printed
    `ref_peak` still show it.
  - **The 1 %, 99 % and zero-hitch limits are policy limits**, derived from the 1 Hz cadence and
    the tick period, not measured. They are part of what Michael accepts with this ADR.
