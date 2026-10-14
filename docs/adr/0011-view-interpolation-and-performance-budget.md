# ADR 0011: View interpolation, draw structure and the performance budget (probe, headless test, phone gate)

Status: accepted, 2026-10-12 (Michael). Proposed 2026-10-11 (revision 5 after the five-lens plan review and three completeness checks, same day).

Status note (2026-10-12): partly superseded by ADR 0012: §1 (the view reads `runner.snapshot`,
not the World), §2 (the prev positions live in the snapshot), §3 (the z list becomes one z per
batch group), §4 (the CI ceiling becomes a printed phone estimate and the enforced budget a
regression ratchet; the 4.0 ms starting value of `mean_ms` is withdrawn), §5 (the meaning and
values of `work_p95_ms` and `sim_p95_ms` in the acceptance note, and the debug-APK margin; the
gate uses the release template), §6 step 4 (the worker thread, adopted), and the sim cost
estimate (1.9 ms mean on CI).

Amendment note (2026-10-12, from the P34b and P34c art reviews): §1 gains `type_armour` and
`weapon_ids`, which the art spec keys effects and bars on (copied into the snapshot by ADR 0012's
"Amendment (2026-10-12, P34b review)"). §3's `MapView` bake follows `assets/art/STYLE.md` § "Fog
and terrain": up to three tones per terrain id and tile rects instead of one colour per id, and
NEAREST filtering. The map bakes no grid (Michael, 2026-10-12, after the Art gallery check: "fjern
gitter"); Phase 1's 1 px grid lines are gone on purpose. §2: a new projectile slot (its `proj_id`
changed in the last tick) is not drawn until its second tick, because it has no heading yet (ADR
0012's amendment); it no longer gets prev = current.

Status note (2026-10-12, ADRs 0013 and 0014 accepted): §6 step 5 (GDExtension) is adopted by ADR
0013 §15 for the sim's hot phases, before steps 1 and 2 are exhausted; steps 1 and 2 stay the
remedies for the main thread, the view and the GDScript-only phases, and step 3 is unchanged. §5's
pacing rule "interval at most 17.5 ms for 95 % of frames" and the acceptance note's rows
`on_time_ms` and `on_time_share_pct` are superseded by ADR 0014 §1 and §2 (dropped frames at most
1 %, cadence at least 99 %, no hitch in the heavy window); the 17.5 ms share stays only as a
jitter diagnostic.

## Context
ROADMAP Phase 2 asks for three things:
- "View interpolation at the display frame rate";
- "Performance test: 150 units for 900 ticks, ms per tick reported and the budget enforced";
- the gate "150 units at 60 fps on a mid-range Android phone, and the same seed gives the same
  match".

CLAUDE.md rule 6 sets the budget (150 units at 60 fps on a mid-range 2021 Android phone) and
asks to pool projectiles and effects.

Phase 1 already lerps rigs between `MatchRunner.prev_pos_*` and `World.pos_*` with
`runner.alpha()` (ADR 0003 Consequences), and maps rig `i` to row `i`. `qa-engineer` names
`tests/perf/` and `tests/perf/budget.cfg`.

Michael's phone is the device every Phase 1 phone check used: 2424x1080, 420 dpi, a 152 px left
cutout. Its model is unknown. That panel matches recent 60-120 Hz phones (for example Pixel 9),
which run GDScript at roughly the speed of the cloud VM. Public single-core scores put 2021
mid-range chips (Snapdragon 720G/732G, Helio G95) at about a third of that (recalled, not
measured).

Facts (Godot 4.7.2; scratch benches by the plan review; renderer numbers under Compatibility on
Mesa/llvmpipe with Xvfb, so draw-call counts are reliable and times are not):
- **Draw calls per item inside one `_draw()`:** filled `draw_rect`, `draw_line` (any width,
  antialiased or not) and `draw_texture_rect` batch into one call for 100 items.
  `draw_circle`, `draw_arc`, `draw_polyline`, unfilled `draw_rect` and `draw_colored_polygon` cost
  one call per item. 128 `draw_circle` cost 0.455 ms of GDScript per frame, against 0.029 ms as
  textured quads.
- **Absolute z batching works:** 150 three-layer rigs went from 360 draw calls in tree order to
  13 with absolute `z_index` per layer. An arena-like frame drawn with circles and arcs took 233
  draw calls, and 15 with textured quads.
- **Phase 1 selection rings** (two antialiased unfilled circles per ring) cost 6 draw calls per
  ring: 450 for 75 selected units.
- `RenderingServer.viewport_get_measured_render_time_cpu()` returns real values under
  Compatibility once `viewport_set_measure_render_time` is on.
- **Sim cost estimate** with every phase written in the aliased style of ADR 0007 §1: about
  1.9 ms mean per tick on the VM, 3.3-6 ms on ticks with flow slices and large orders
  (two 75-unit `Formation.assign` calls take about 1 ms each). The Phase 1 indexing style lands
  near 5 ms mean. The view adds about 0.3 ms for rigs, up to 0.75 ms for a full fog rebuild and
  0.38 ms for the hash every 15th tick.
- **CI timing noise** (900 ticks of a 0.35 ms tick on a 4-core VM): idle p95 0.46-0.52 ms; with 8
  busy processes p50 is unchanged but p95 rises to 4.2-4.8 ms and the mean doubles. A scheduler
  slice lands in the p95.
- At 60 fps and 15 Hz, one frame in four carries a tick. If tick frames miss 16.7 ms, 25% of
  frames are slow however cheap the other frames are.

## Decision

### 1. What the view reads (read only, as before)
- **`World`, through `runner.world`, re-read every frame:**
  - per row: `unit_id`, `owner`, `type_index`, `pos_*`, `hp`, `order` and `target`;
  - type tables (`type_ids`, `type_names`, `type_max_hp`, `type_speed`, `type_selection_radius`,
    `type_weapon`, and `type_armour`, amended 2026-10-12) and `weapon_projectile_speed` (and
    `weapon_ids`, amended 2026-10-12; see the amendment note);
  - projectile slots (`proj_id`, `proj_owner`, `proj_weapon`, `proj_x`, `proj_y`);
  - map (`map_cols`, `map_rows`, `terrain`, `terrain_ids`, `map_version`);
  - `fog` (`version_of`, dirty lists, `visible`, `explored`) and `rows_version`;
  - `events`, but only inside `MatchRunner.ticked`.
- **`MatchRunner`:** `prev_pos_*` (aligned to the current rows), `prev_proj_*` (per slot),
  `alpha()` and `match_serial`.
- **Two rules keep a threaded tick possible later (section 6) as a runner-only change:**
  - a view layer never keeps a reference to a World array across frames;
  - a layer detects a new match through `runner.match_serial`, never through World identity,
    and then resets every cache it holds (rig maps, fog bytes, effect ring, projectile prev,
    map texture).

### 2. Interpolation
- **Units:** `lerp(prev, cur, alpha)` per row (Phase 1 rule). After rows change, `MatchRunner`
  rebuilds `prev_pos_*` for the new rows with a merge walk by id:
  - a surviving row keeps its old prev;
  - a new row gets prev = current, so it never slides in from (0, 0);
  - a dead row is dropped.

  The arrays keep their buffers (capacity `max_rows`), and the copy costs O(rows) only on ticks
  that change rows.
- **Projectiles:** `lerp(prev_proj, proj, alpha)` per live slot. A slot whose `proj_id` changed
  in the last tick ~~has prev = current~~ is not drawn in that tick (amended 2026-10-12, see ADR
  0012's "Amendment (2026-10-12, P34b review)").
- **Not interpolated:**
  - hp, fog and visibility, which change per tick;
  - effects and the turret's turn, which run on the frame clock (`delta`, view only, as Phase 1's
    hull easing does).
- **Turret aim (view only):** the turret turns towards the interpolated position of
  `world.target` at the rig's `turn_rate`. With no target it follows the hull. A squad (no
  turret) turns its whole rig towards its target while it has one.

### 3. Draw structure
- **Rigs:** `UnitLayer` maps rigs to rows through a list rebuilt by the id merge when
  `rows_version` changes. The sync runs first in every entry point (`_process`, `set_selected`,
  `fill_pick_snapshot`, `unit_screen_position`), so a call made inside `ticked` never uses a
  stale map. A death frees its rig. There is **no rig pool in Phase 2** (nothing spawns
  mid-match); pooling comes with production in Phase 3. A type with no `<type_id>_turret.svg`
  gets no Turret layer, checked once per type with `ResourceLoader.exists` (works on imported
  resources in exports).
- **Selection rings** are `Sprite2D`s with one shared ring texture (art-director), at absolute z
  1, scaled for dp and zoom, so they batch like hulls. The ring keeps the Phase 1 node contract
  that tests pin (a `Ring` node, first child of its rig, created on the first selection, with
  the Phase 1 `radius` and `unit`); only its drawing changes, to a scaled texture. A sprite
  scales its baked stroke with the ring, so the stroke is 3 dp (plus the 1 dp outline on each
  side) when the radius is at its 18 dp minimum and grows with the radius above it. This
  partly supersedes ADR 0004 §7 (rings drawn in code); STYLE.md's ring row changes with it.
- **No node per projectile, effect or health bar.** `ProjectileLayer`, `EffectsLayer` (fixed ring,
  `capacity` 128, oldest overwritten, state in packed arrays) and `HealthBarLayer` each draw in
  one `_draw()`.
- **Draw-call rule for every world draw layer:** per-item drawing uses only filled rects,
  straight lines and textured quads from one shared small texture (`draw_texture_rect` or
  `draw_texture_rect_region` on one atlas). No per-item circle, arc, polyline, polygon or
  unfilled rect. Effects (shell, rocket, muzzle flash, impact puff, death burst) are sprites in
  one SVG atlas from the art spec; tracers are lines; health bars and the enemy bar's notch are
  rects. Scratch arrays are sized once, so steady-state frames create no new Objects; that is
  tested with `Performance.OBJECT_COUNT` (an object-leak check), and per-frame cost is judged on
  the perf card, not claimed by that test.
- **Batching and draw order:** every world layer gets an absolute `z_index`
  (`z_as_relative = false`): map 0, rig layers (ring 1, hull 2, team 3, turret 4), health bars 5,
  projectiles 6, effects 7, fog 8, markers 9. Measured: this takes rigs from 360 draw calls to 13.
- **`MapView`** bakes the terrain once per match and per `map_version` into one `ImageTexture` at
  8 px per tile (two-tone grass and the scrub pattern included; amended 2026-10-12: the tiles
  and tones of STYLE.md and no grid (Michael, 2026-10-12), see the amendment note) and draws it
  with one textured rect. It replaces `TestMapView` (ADR 0002 §5). Like `FogLayer` (ADR 0010 §2) it
  exposes its CPU-side bake (`func image() -> Image`) for tests, which never read an
  `ImageTexture` back after `update()`.

### 4. Headless performance test (`tests/perf/`, qa-engineer)
- **Scenario:** `data/scenarios/perf_arena.tres` (data lands in P27b, so every sim PR can measure
  it):
  - a 64x64 map. A north-south rock ridge at columns 31-32 runs the full height except three gaps
    inside rows 25-39, plus a pond and scrub. The fight happens inside a 26 x 15 tile window
    centred on tile (32, 32), the view of the arena camera at zoom 0.75 on a 16:9 screen;
  - per side 30 light tanks, 27 rifle squads and 18 rocket squads, so 150 units at tick 0, both
    armies inside that window (player 1 west of the ridge, player 2 east), spawn jitter 300 milli;
  - opening orders at tick 0: each side attack-moves to the other side's spawn centre.

  The run therefore uses flow fields, separation in the gaps, targeting, hitscan, projectiles,
  deaths and fog, with the whole fight on screen.
- **Run:** through `MatchLoop` (ADR 0007 §9), the same driver as the runner, with seed 42. Each
  step is timed with `Time.get_ticks_usec()` in the test, with a `SimProbe` for the per-phase
  split. 900 ticks, every tick counted (no warm-up excluded).
- **Method (fixed, not a retry):** seed 42 runs three times. Two runs are needed anyway for the
  same-seed check. The enforced numbers are the minimum over the three runs of mean, p50 and p95.
  All three runs are printed.
- **Report:** one line
  `PERF sim units=150 ticks=900 runs=3 mean_ms=… p50_ms=… p95_ms=… p99_ms=… max_ms=… worst15_ms=… ticks_per_s=… alive_end=… proj_peak=… projectile_overflow=… phases=<ms per phase> hash=<16 hex>`
  on stdout (`worst15_ms` is the costliest window of 15 consecutive ticks; `phases=` lists all
  `SimProbe.Phase.COUNT` phases in id order as `name:ms` pairs from `SimProbe.PHASE_NAMES`,
  for example `phases=commands:0.05,flow:0.00,grids:0.04,...`, with 0 for a phase not yet in
  the tick (ADR 0007 §4); the hash comes from `World.hash_hex`), and the same numbers as JSON in `reports/perf/sim.json` (git-ignored).

  Status note (2026-10-14, P26r docs, after P38p, #92; the text above stays as accepted): the
  merged line has another key order than the template above, because `ref_ms`, ADR 0012 §4's
  phone estimates and the `World.stats` maxima sit between its keys: `PERF sim units= ticks=
  runs= mean_ms= p50_ms= p95_ms= p99_ms= max_ms= worst15_ms= ticks_per_s= ref_ms=
  est_phone_mean_ms= est_phone_p95_ms= alive_end= proj_peak= projectile_overflow=
  stats_max=<stat:max,…> phases=<phase:ms,…> hash=<16 hex>`, with three decimals. The method's
  minimum covers every statistic on the line (also `p99_ms`, `max_ms` and `worst15_ms`) and every
  phase mean, each taken separately over the three seed-42 runs, so the phase means sum to a
  little less than `mean_ms` (the checkpoint hash is in no phase). Each run prints a `RUN sim `
  line. Details: the Phase 2 plan, contract row "Perf test" and section P38p.
- **Deterministic cost bounds (exact, cannot flake):** from `World.stats`, per tick: flow cells
  settled at most `flow_cells_per_tick`; separation pairs at most `separation_scan` x units; line
  checks at most the moving units; targeting candidates and fog cells stamped at most the bounds
  set in P49 from the measured maxima plus 25%. P49 runs after fog updates enter the tick (P46),
  so the fog bound and the `fog` phase are measured, not guessed. These catch the algorithmic
  regressions that matter, so a sim PR never raises a cost bound itself: a rise goes to
  qa-engineer.
- **Wall-clock budget:** `tests/perf/budget.cfg` (`[sim]` `mean_ms`, `p95_ms`, `ticks`, `units`).
  - Before P49 fixes it, the harness runs at least 10 times on the CI runner (workflow_dispatch
    or a temporary loop).
  - The ceiling is the gate phone's sim threshold (`sim_p95_ms`, section 5) divided by the
    phone-to-CI speed ratio measured by the P26s probe. The floor is 1.5 times the worst
    min-of-3 seen in calibration.
    The budget is the ceiling. If the floor is above the ceiling, the sim is already too slow:
    that is a finding for section 6, not a reason to raise the number.
  - That rule gives `p95_ms`. `mean_ms` follows the same rule on the mean: its ceiling is the
    `p95_ms` ceiling times the calibration's ratio of min-of-3 mean to min-of-3 p95, and its
    floor is 1.5 times the worst min-of-3 mean seen in calibration.
  - `mean_ms` starts at no more than 4.0 ms (the qa-engineer rule "start at 4 ms per tick on
    CI"), whatever the ceiling gives. If the calibration floor of the mean is above 4.0 ms, that
    is a finding for section 6, not a reason to start higher.
  - The line also prints `ref_ms`, a fixed GDScript reference loop timed in the same run, so a
    proven runner-speed problem can switch to a relative budget through a new ADR.
- **Other fail rules:** the unit count at tick 0 is not 150; `projectile_overflow > 0`; `alive_end`
  or the projectile peak outside the bounds pinned in P49 (so a balance change cannot silently
  shrink the measured load); `Performance.MEMORY_STATIC` grows by more than a generous bound
  between tick 100 and tick 900. A sim PR after P49 that changes the arena run (the fog rules,
  P46b, which change who fires; later tuning) re-pins the golden hashes and, only if they fall
  outside, the `alive_end` and projectile-peak bounds around its new measured values with the
  P49 margins, with a note (plan exception 3). It never changes the cost bounds or
  `budget.cfg`.
- **Same seed, same match, at scale:** the three seed-42 runs give identical 15-tick checkpoints.
  Seed 43 gives a different final hash. The seed-42 checkpoint hashes every 150 ticks and the
  final hash are pinned as literals in `data/dev/perf_gate.tres` (golden values) and checked by
  `tests/perf/test_golden_hashes.gd`, a separate file with no clock, so it can run alone on
  another architecture. The wall-clock budget lives only in `tests/perf/test_sim_perf.gd`. A
  sim PR that changes the golden values updates them on purpose, with a note.
- **Before P49:** the harness lands right after the match loop and the runner (P38p) as report
  only, with a catastrophic cap of 20 ms mean. Every later sim PR quotes its `PERF` line before
  and after the change.
- **CI:** `verify` runs the suite like any test. `ci.yml`'s job summary copies the `PERF` line.
  A small arm64 Linux job runs the determinism suites and `test_golden_hashes.gd` by path, if an
  official arm64
  Linux editor build of 4.7.2 exists (P51b checks this first).

### 5. Phone measurement
- **Gate device (Michael, 2026-10-12): Michael's own phone**, permanently (2424x1080, 420 dpi,
  Android; the P26s report and every perf card record its model). No 2021 phone is bought and no
  step waits for one. It stands in for the "mid-range 2021 Android phone" of CLAUDE.md rule 6
  through stricter limits:
  - every CPU-time threshold is the limit set for a 2021 mid-range phone divided by the
    slowdown factor **k = 2.5** (assumed, not measured: the plan's estimate inside the "2 to 4
    times slower" range of ADR 0008's Context; the recalled scores above suggest up to 3). Work
    that fits the divided limit on the gate phone would fit the 2021 limit on a phone k times
    slower;
  - the 2021 limits are: tick-frame work p95 14 ms (of the 16.7 ms frame), device `Sim.step`
    p95 8 ms, fog update p95 1 ms;
  - the frame-pacing rules (interval at most 17.5 ms for 95% of frames, the 600-frame heavy
    window) are not divided: they are measured at 60 fps on the gate phone and prove that the
    frame keeps its pace;
  - the draw-call ceiling is a count and is not divided. It guards the GPU and driver side,
    which the division does not model;
  - what the proxy for rule 6 does not model: GPU fill rate, memory bandwidth and thermal
    limits of an older phone. The margins there are the Compatibility renderer, the draw-call ceiling, three
    runs in a row (a warm phone) and the debug APK (GDScript slower than release);
  - k, the 2021 limits and the gate device change only through a new ADR. A slower test phone
    can be added later the same way, if field data (playtests, store reviews, Android vitals)
    shows that the proxy for rule 6 misses real slow phones.
- **Probe first (P26s).** A throwaway dev scene on a draft PR, run on the gate phone after P26
  merges and before the art and view PRs start (P34 on): 150 rigs with the real tank SVGs at
  absolute z, 75 ring sprites, 150 health bars, 60 projectiles and 128 effects drawn as textured
  quads, a 64x64 fog texture patched at 5 Hz, and the optimised mock tick at 15 Hz in the frame,
  with every unit on screen at zoom 0.75. Its card shows the numbers listed below, and the same
  mock tick runs headless on CI, which gives the phone-to-CI speed ratio. The probe gives the
  ratio for `budget.cfg` (section 4), the starting `flow_cells_per_tick` (ADR 0008 §3, a data
  value) and a check of the draw contracts (section 3). It does not change the gate thresholds
  (acceptance note). A draw contract that the probe contradicts changes through a new ADR before
  the art and view PRs that use it.
- **The perf arena** (`scenes/dev/perf_arena.tscn`, dev menu "Perf arena"):
  - the same scenario and seed 42, through the same `MatchRunner`;
  - the real view (map, units, projectiles, effects, health bars, player 1's fog) with
    `reveal_enemies` on (ADR 0010 §2), and every player-1 unit selected at start (a view-only
    selection, no Command), so rings are drawn;
  - camera at zoom 0.75 centred on tile (32, 32);
  - `Engine.max_fps = 60`, so a 90 or 120 Hz panel is judged at 60 fps;
  - `DisplayServer.screen_set_keep_on(true)` during the run, through an injectable Callable
    (headless `screen_is_kept_on()` stays false, so tests assert on the sink, not on the display
    server);
  - `TouchInput` for pan and zoom only, no `PlayerController`, so no Command can enter;
  - a layer-mode selector before a run (all, no fog, no bars, no effects and projectiles, rigs
    only). Gate runs use "all"; the mode is printed on the card.
- **`PerfHud` records from tick 0 to 900**, using one shared `PerfStats` class (percentiles,
  mean, worst window) that the CI test uses too:
  - frame interval (`Time.get_ticks_usec()` deltas);
  - frame work: process time plus render-thread CPU time, split into tick frames and other
    frames;
  - runner tick time (the whole `_tick`: match loop, hash, prev copies) and `Sim.step` time with
    the per-phase split;
  - view time (UnitLayer and the draw layers' `_process`), fog update time;
  - draw calls (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`);
  - `drawn_rigs`: rows shown and inside the camera's visible world rect;
  - the **heavy window**: frames with `drawn_rigs` at least 135.
- **The card** (at tick 900 the runner pauses):
  - about 8 grouped lines that fit the safe area at every UI profile at 14 sp or more;
  - one verdict line per criterion and an overall `GATE: PASS` or `GATE: FAIL`;
  - `INVALID` if the app was paused or backgrounded during the run;
  - checkpoint hashes compared with the golden values in `data/dev/perf_gate.tres`, shown as
    `MATCH` or `MISMATCH` with the first differing tick;
  - model, OS, engine version, debug flag, refresh rate, screen size, zoom and layer mode;
  - "Copy report" puts the summary and the checkpoint hashes on the clipboard as JSON
    (`DisplayServer.clipboard_set` by default, through the injectable `clipboard_sink`, because
    the headless display server cannot read a clipboard back), so Michael pastes text instead
    of reading digits from a screenshot; "Run again" restarts with the same seed. Controls are
    at least 48 dp and inside the safe area.
- **Gate thresholds** live in `data/dev/perf_gate.tres` and the card reads them. A run passes
  when:
  - the heavy window holds at least 600 frames (10 s);
  - at least 95% of frames are on time (interval at most 17.5 ms), over the run and over the
    heavy window;
  - frame work p95 on tick frames in the heavy window is at most `work_p95_ms`;
  - device `Sim.step` p95 is at most `sim_p95_ms`;
  - draw calls p95 at most `draw_calls_max`;
  - fog update p95 at most `fog_update_p95_ms`;
  - every checkpoint hash matches.

  The values are the 2021 limits divided by k on the gate device (above), listed in this ADR's
  acceptance note, which `tests/project/test_cross_file_facts.gd` compares with
  `data/dev/perf_gate.tres`.
- Debug APKs run GDScript slower than release, so the gate errs on the safe side. The web
  preview's numbers are reported but do not gate; its hashes must match.

### 6. When the budget is missed
In order (the card's per-phase and per-layer numbers pick the step):
1. Tune cadences and slices in `data/rules.tres` (retarget, fog, flow cells per tick, line
   check period), one value per PR with before and after numbers.
2. Fix the costly phase or layer in GDScript (aliasing, fewer passes, dirty updates).
3. Move the rendering of rigs to `MultiMeshInstance2D`.
4. Run the tick on a worker thread one tick ahead, with the view reading a per-tick copy of the
   World owned by the runner (possible as a runner-only change because of the two rules in
   section 1; inline on the web build, which has no threads).
5. Move hot sim loops to GDExtension (ADR 0001 Consequences).

Steps 3 to 5 each need a new ADR.

## Consequences
- The "View interpolation" box is ticked only with the 150-unit arena running on the phone
  (ADR 0003 Consequences), not with the Phase 1 lerp.
- `verify` gets slower by about 4 x 900 arena ticks plus 5 x 300 ticks of the runner check, about 10-20 s on
  CI.
- `reports/perf/` joins `reports/gdunit/` under the existing `reports/.gdignore`.
- The phone check needs no tools on Michael's side: the card is the measurement, and "Copy
  report" carries it to chat.
- The model, refresh rate and screen size on the card record the gate device, so a later
  regression can be compared on the same model.
- Art for effects becomes an atlas of small sprites instead of code-drawn shapes, so effects
  stay within the draw-call ceiling at 150 units.
- The divided limits are tight: on a phone as fast as the VM, the estimate in Context (3.3-6 ms
  on flow and order ticks) would exceed `sim_p95_ms` (3.2 ms) if such ticks are more than 5% of
  a run. The gate may therefore fail on sim time first; section 6 gives the order of remedies,
  and the per-phase split on the card picks the step.
- With one gate device, regressions are compared on the same model across phases. A phone slower
  than k assumes can still run below 60 fps; that is the accepted limit of the proxy for rule 6
  until field data says otherwise.

## Acceptance note (2026-10-12, Michael)
Michael accepted ADRs 0007-0011 with the plan's answers (`docs/plans/2026-10-11-phase-2.md`,
"Answers (Michael)"). Gate device: his own phone, permanently; k = 2.5. The thresholds in
`data/dev/perf_gate.tres` (`PerfGateDef` defaults, P38t; pinned by
`tests/project/test_cross_file_facts.gd`, P52):

| Field | Value | Rule |
| --- | --- | --- |
| `heavy_rigs` | 135 | frames with at least 135 drawn rigs form the heavy window |
| `heavy_frames_min` | 600 | 10 s at 60 fps; not divided |
| `on_time_ms` | 17.5 | frame interval; not divided |
| `on_time_share_pct` | 95 | over the run and over the heavy window; not divided |
| `work_p95_ms` | 5.6 | 14 ms on a 2021 phone / 2.5 |
| `sim_p95_ms` | 3.2 | 8 ms on a 2021 phone / 2.5 |
| `fog_update_p95_ms` | 0.4 | 1 ms on a 2021 phone / 2.5 (ADR 0010 §2) |
| `draw_calls_max` | 60 | a count; not divided |

The P26s probe had not run at acceptance; its report changes none of these values (section 5).
