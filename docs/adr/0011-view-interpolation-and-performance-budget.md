# ADR 0011: View interpolation, pooling and the performance budget (headless test and phone gate)

Status: proposed, 2026-10-11

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
`tests/perf/` and `tests/perf/budget.cfg`, starting at 4 ms per tick on CI.

Michael's phone is the device every Phase 1 phone check used: 2424x1080, 420 dpi, a 152 px left
cutout. Its model is unknown. That resolution is typical of 2023-2024 phones, which run
GDScript faster than a 2021 mid-range phone.

Facts:
- **Mock tick** (ADR 0008): 0.7 ms mean and 1.25 ms p95 on the cloud VM. The real sim has more
  phases, so we estimate 1.5 to 2.5 ms (not yet measured).
- **Not verified:**
  - GDScript speed on Michael's phone;
  - whether the Compatibility renderer batches the sprites of 150 three-layer rigs better when
    the layers are grouped by `z_index`;
  - the frame cost of 150 rigs on any phone.

  The perf arena (decision 5) measures all three.

## Decision

### 1. What the view reads (read only, as before)
- **`World`:**
  - per row: `unit_id`, `owner`, `type_index`, `pos_*`, `hp`, `order` and `target`;
  - type tables (`type_ids`, `type_names`, `type_max_hp`, `type_speed`, `type_selection_radius`,
    `type_weapon`) and `weapon_projectile_speed`;
  - projectile slots (`proj_id`, `proj_owner`, `proj_weapon`, `proj_x`, `proj_y`);
  - map (`map_cols`, `map_rows`, `terrain`, `terrain_ids`, `map_version`);
  - `fog` and `rows_version`;
  - `events`, but only inside `MatchRunner.ticked`.
- **`MatchRunner`:** `prev_pos_*` (aligned to the current rows), `prev_proj_*` (per slot) and
  `alpha()`.

### 2. Interpolation
- **Units:** `lerp(prev, cur, alpha)` per row (Phase 1 rule). After rows change, `MatchRunner`
  rebuilds `prev_pos_*` for the new rows with a merge walk by id:
  - a surviving row keeps its old prev;
  - a new row gets prev = current, so it never slides in from (0, 0);
  - a dead row is dropped.
  
  The arrays keep their buffers, and the copy costs O(rows) only on ticks that change rows.
- **Projectiles:** `lerp(prev_proj, proj, alpha)` per live slot. A slot whose `proj_id` changed
  in the last tick has prev = current.
- **Not interpolated:**
  - hp, fog and visibility, which change per tick;
  - effects and the turret's turn, which run on the frame clock (`delta`, view only, as Phase 1's
    hull easing does).
- **Turret aim (view only):** the turret turns towards the interpolated position of
  `world.target` at the rig's `turn_rate`. With no target it follows the hull. A squad (no
  turret) turns its whole rig towards its target while it has one.

### 3. Pooling and draw structure
- **Rigs:** `UnitLayer` keeps a pool per type. A death hides the rig and returns it to the pool.
  A spawn takes one from the pool or builds one. Rigs map to rows through a list rebuilt by the
  same id merge when `rows_version` changes. A type with no `<type_id>_turret.svg` gets no Turret
  layer (STYLE.md "a unit without a turret leaves Turret out"), checked once per type.
- **No node per projectile, effect or health bar.**
  - `ProjectileLayer` draws every live projectile in one `_draw()` per frame.
  - `EffectsLayer` keeps a fixed ring of effects: muzzle flash, tracer, impact, death burst. It is
    `@export var capacity: int = 128`. The oldest effect is overwritten, its state lives in
    packed arrays, and it draws in one `_draw()`.
  - `HealthBarLayer` draws bars for damaged or selected units in one `_draw()`.
  - None of them allocates per frame in steady state. Tests pin this the way Phase 1's "frames
    leave no new objects alive" does.
- **Batching and draw order:**
  - Every world layer gets an absolute `z_index` (`z_as_relative = false`), because the
    renderer sorts all canvas items of a canvas layer by z before tree order. The order is: map
    0, rig layers (ring 1, hull 2, team 3, turret 4), health bars 5, projectiles 6, effects 7,
    fog 8, markers 9.
  - The renderer then draws all rings, then all hulls, then all team layers, then all turrets,
    so consecutive sprites share a texture.
  - A turret is never drawn above a health bar, the fog or a marker. Relative offsets such as -1
    would have put rings under the map.
  - Expected gain: one batch per (type, layer) instead of up to 450 alternating textures. Not
    verified: the perf arena measures it. If 150 units miss 60 fps, the next step is one
    `MultiMeshInstance2D` per (type, layer), through a new ADR.
- `MapView` draws the terrain once into its canvas item (redrawn only when the world or
  `map_version` changes). It replaces `TestMapView` (ADR 0002 §5).

### 4. Headless performance test (`tests/perf/`, qa-engineer)
- **Scenario:** `data/scenarios/perf_arena.tres`:
  - a 64x64 map with a rock ridge with 3 gaps, water and scrub;
  - per side 30 light tanks, 27 rifle squads and 18 rocket squads, so 150 units at tick 0;
  - spawn jitter 300 milli;
  - opening orders at tick 0: each side attack-moves to the other's base.
  
  The run therefore uses flow fields, separation in the gaps, targeting, hitscan, projectiles,
  deaths and fog.
- **Run:** a pure loop (no Node) with seed 42:
  - `ScenarioOrders` commands are stamped like the runner does;
  - each `Sim.step` is timed with `Time.get_ticks_usec()` in the test code (never in the sim);
  - 900 ticks, every tick counted (no warm-up excluded), because the first ticks hold the flow
    field work that a real match has too.
- **Report:** one line
  `PERF sim units=150 ticks=900 mean_ms=… p50_ms=… p95_ms=… max_ms=… alive_end=… projectile_overflow=… hash=<16 hex>`
  on stdout, and the same numbers as JSON in `reports/perf/sim.json` (git-ignored, `.gdignore`).
- **Budget:** `tests/perf/budget.cfg` (`ConfigFile`, section `[sim]`): `mean_ms = 4.0`,
  `p95_ms = 8.0`, `ticks = 900`, `units = 150`. The test fails when:
  - the mean or the p95 is above budget;
  - the unit count at tick 0 is not 150;
  - `projectile_overflow > 0`;
  - fewer than 10 units died by tick 900 (the fight must happen, or the test measures a march).
- **Flakiness control:**
  - The budget is about twice the expected cost.
  - Only the mean and the p95 are enforced. Single slow ticks (runner noise, GC of engine
    objects) cannot fail the run, and the max is reported, not enforced.
  - No retries (`qa-engineer` rule).
  - A failure on `main` without a sim change is investigated as a bug. If shared-runner noise is
    proven, the method changes through a new ADR (for example a budget relative to a fixed
    GDScript reference loop timed in the same run), never by raising the number silently.
  - `budget.cfg` changes only in a PR that shows before and after numbers. The budget is
    tightened when the measured mean stays below half of it for a phase.
- **Same seed, same match, at scale:** the same suite runs the arena twice and compares the
  15-tick checkpoints. It also runs seed 43 and expects a different final hash, so the seed is
  proven to matter. It prints the seed-42 final hash that the phone must reproduce.
- **CI:** `verify` runs the suite like any test. `ci.yml`'s job summary copies the `PERF` line
  from the verify log, so every run shows the numbers.

### 5. Phone measurement (`scenes/dev/perf_arena.tscn`, dev menu "Perf arena")
- **The scene:**
  - the same scenario and seed 42;
  - the real view (map, units, projectiles, effects, health bars, fog for player 1);
  - camera at zoom 0.75 over the ridge;
  - `TouchInput` for pan and zoom only. No `PlayerController`, so no Command can enter and the
    hash stays comparable.
- **`PerfHud` records from tick 0 to 900:**
  - frame time from `Time.get_ticks_usec()` deltas in `_process`;
  - `runner.last_tick_usec` per tick;
  - `Performance.TIME_PROCESS`;
  - unit and projectile counts.
- **At tick 900 the runner pauses and a card shows:**
  - frames, average fps and frame ms p50/p95/max;
  - the share of frames above 17.5 ms;
  - sim ms per tick p50/p95/max on the device;
  - process ms p95 and units alive;
  - the final hash (16 hex);
  - `OS.get_model_name()`, `OS.get_name()`, `Engine.get_version_info().string` and the debug
    flag.

  "Run again" restarts with the same seed. The card's controls are at least 48 dp and inside the
  safe area.
- **Gate thresholds** (debug APK from `android-dev-latest`, the build Michael already installs;
  a debug build runs GDScript slower than release, so this errs on the safe side):
  - at least 95% of frames at or below 17.5 ms;
  - an average of at least 58 fps;
  - device sim p95 at or below 8 ms, so a tick plus rendering fits in one 60 fps frame;
  - two runs give the same final hash, and it equals CI's `PERF` hash for that commit and the web
    preview's.
  
  The web preview's frame numbers are reported but do not gate. The ROADMAP gate names an
  Android phone.
- **Headroom for a phone newer than the 2021 target:** the plan's open question 1 decides it.
  The recommendation is device sim p95 ≤ 4 ms and process p95 ≤ 8 ms on Michael's phone, as a
  stand-in for a phone about twice as slow. Whatever Michael answers is recorded in this ADR's
  acceptance note, not by editing this text later.

### 6. When the budget is missed
In order:
1. Profile with the arena card and Godot's profiler on desktop.
2. Tune cadences in `data/rules.tres` (retarget, fog, flow cells per tick).
3. Move the rendering to `MultiMeshInstance2D`.
4. Move hot sim loops to GDExtension (ADR 0001 Consequences).

Steps 3 and 4 each need a new ADR.

## Consequences
- The "View interpolation" box is ticked only with the 150-unit arena running on the phone
  (ADR 0003 Consequences), not with the Phase 1 lerp.
- `verify` gets slower by about 3 x 900 ticks, a few seconds on CI.
- `reports/perf/` joins `reports/gdunit/` under the existing `reports/.gdignore`.
- The phone check needs no tools on Michael's side: the card is the measurement.
- `OS.get_model_name()` on the card records the gate device, so a later regression can be
  compared on the same model.
