# ADR 0027: Unit life and effects (a view-only animation layer)

Status: proposed, 2026-11-02, on `main` at 3c29b16. Plan: `docs/plans/2026-11-02-unit-life.md`
(rows P132-P154). Amends ADR 0007 §10 (one new event kind), ADR 0023 §2 (the z table, the
draw-call forecast, "damage states and animations are not Phase 3") and §5 (the frame names, "out of
Phase 3: building damage states and animations"). Everything else here is view and art: no rule,
state column, Command or golden hash changes.

## Context
- **Michael, 2026-11-02** (in Danish, translated): "When tanks fire, the turret gives a small jerk.
  When soldiers move, they move their legs. When they stand still they could shift a little, so the
  game feels more alive. Include the extra ideas (dust behind driving tanks, smoke from the
  refinery, a radar dish turning on a building) - the more small details the better. Also when a
  superweapon fires, something should come out of the building that launches it, and a graphic
  strike should come down from the air onto the chosen area."
- **Today** a rig is a `Node2D` in `WorldSort` with `Shadow`, `Hull` and `Turret` sprites on the
  match's one atlas (ADR 0023 §2); a region changes only when a 16-step direction changes; a
  building is a `Body` (and a defence's `Head`) that never moves; `EffectsLayer` (z 50) draws
  flashes, tracers, puffs and bursts from `SHOT`, `IMPACT` and `DIED` on the frame clock
  (`Time.get_ticks_msec`). ADR 0023 §2 and §5 put building animations and damage states out of
  Phase 3. Squads have one frame per direction, so they glide.
- **What the view can read.** The snapshot has every column the life needs (positions and
  `prev_pos_*`, `target_row`, `hp` and `type_max_hp`, `harvest_mode`, `build_left`,
  `offline_until`, `ready_tick`, `power_made`/`power_used`, `strike_x/y/tick`,
  `type_strike_radius`) and every `SHOT`, `IMPACT` and `DIED`, except one thing: **a blackout leaves
  no point.** `Strike.apply_superweapon` writes `strike_x`/`strike_y` only for a rupture; a blackout
  only sets `offline_until` on the buildings it hits, so the view cannot place a falling effect on
  its area, and it learns which building fired only by diffing `ready_tick`.
- **Budgets.** CLAUDE.md rule 6 (150 units at 60 fps on a mid-range 2021 phone), ADR 0014's
  main-thread `work_p95_ms` 5.6 on the phone card, ADR 0023 §2's draw-call forecast (14, about 19
  in the worst moment, trigger 40) and its one atlas page of at most 4096 x 4096 for the sorted world.
- **Fog** (ADR 0010 §2, ADR 0023 §2): the fog lies on the ground at z 4; every object above it is
  hidden by its own rule, and effects are born only on seen tiles.
- **Phase.** We are in Phase 3 (HUD v2 lanes running). Unit life is polish (ROADMAP Phase 5), asked
  for now by the owner. It touches no file of the HUD lanes except `scenes/main.tscn` once.

## Decisions in short
1. Unit life is **view and art only**. The sim gains one event kind, `STRIKE` (§7), and nothing
   else. No view state feeds back; life never moves a rig's or building's node, so sort keys, picks,
   bars and orders are unchanged.
2. **The life clock** is match time, `(tick + alpha) x 1000 / 15` ms from the published snapshot
   and `runner.alpha()`; variation comes from an integer hash of the entity id. No `Time`, `randi`,
   `randf`, `RandomNumberGenerator`, `hash()` or Particles node in life code (§2).
3. **Where life draws:** on the existing sprites (region, offset and position writes on change only;
   one `Anim` child per animated building, made with the building), and in three pooled layers under
   one `LifeFx` node: `GroundFx` z 3, `AirFx` z 25, `StrikeFx` z 55 (§3).
4. **Art gets a frame axis:** parts may have several frames per direction (`walk`, `idle`, `anim`),
   named `_f<K>`; the sorted world stays one page, and the cross-faction two-player page at bake
   scale 1.0 stays at most 3584 px tall (§4).
5. **Walking** advances by distance travelled, not by time (§5).
6. **Fog:** life on a rig or building inherits its visibility; layer effects are born only where the
   local player sees their source; the rupture's falling lance is public like its warning (§6).
7. **`STRIKE` event** `[5, building id, x, y, kind, owner, landing tick or 0, 0]` (§7).
8. **Reduced effects:** a flag now (`data/life_settings.tres`), no switch in the UI until Phase 5's
   settings screen (§8).
9. **Budget:** life costs at most 0.56 ms of main-thread work per frame (10 % of 5.6) on the phone
   card and adds at most 2 draw calls (3 during a strike), pinned by headless tests (§9).

## Decision

### 1. View and art only
- The sim, its state, its hashes and its kernels do not change, except §7's event (not state).
- A life effect reads the published snapshot (and its events in `runner.ticked`), never the World
  (ADR 0012 §3), and writes only view nodes.
- **No life moves a node that something else reads:** a rig's and a building's node position (the
  y-sort key, the pick centre, the bar anchor) stays the projected sim position. Recoil, rock and idle
  shake move child sprites (`Hull`, `Turret`, `Head`) by an offset; poses change regions. Idle life
  never changes the facing the hull shows by more than its own frames, so nothing reads as an order.

### 2. The life clock and variation
- `LifeClock.ms(snap, alpha)` = `(snap.tick + alpha) x 1000 / Sim.TICK_RATE`, a view float. An
  event of tick `t` is born at `t x 1000 / 15`; its age is the clock minus that. In the frame that
  first shows a tick, alpha is near 0, so an event's effect starts at age about 0.
- **Why match time:** it stops with the match (`MatchRunner.paused`, the app in the background), so
  a paused game freezes mid-step; it is the same at the same tick on every device and frame rate,
  so a replay or a second viewer sees the same pose at the same tick (up to alpha sampling); and a
  test sets tick and alpha instead of faking a clock. **Rejected:** the frame clock (life would run
  on in a pause and differ per device).
- Existing frame-clock users (`EffectsLayer`, hit times, move marks, the HUD) keep their clock; this
  ADR changes none of them.
- **Variation:** `LifeClock.mix(id, salt)` is a 31-bit integer mix (multiplications by odd
  constants and xor-shifts, masked), pinned by golden values in a test. A periodic life effect
  (idle pose, look-around, head sweep, emitter) picks its phase and its window in each cycle from
  `mix(id, cycle)`, so it is stateless, desynchronised per entity and replays alike. No `hash()`
  (its output is not part of any contract), `randi`, `randf`, `RandomNumberGenerator`,
  `CPUParticles2D` or `GPUParticles2D` in life code; `tests/view/test_life_purity.gd` scans the life
  files for them and for `Time.`.

### 3. Where life draws
- **On existing sprites** (`UnitLayer`, `BuildingLayer`, with the per-row state in a helper,
  `RigLife.gd`, carried by `UnitLayer`'s merge by unit id like the hit times): turret and head
  recoil, hull rock, idle shake, head sweep, turret look-around, squad walk and idle poses. A write
  happens only when the quantised value changes (a region index, an offset rounded to 0.5 world px).
- **One `Anim` child** (`Sprite2D`, a region of the same atlas, white) for each building whose sheet
  has an `anim` part, made in `BuildingLayer._make` and freed with the building: never per frame.
  It draws right after the `Body` in the building's node, so it sorts with the building.
- **Three pooled layers** under one `LifeFx` (`Node2D`) that `scenes/main.tscn` gets once, between
  `DecalLayer` and `WorldSort`; `LifeFx` makes its children in code, so later rows add a layer
  without touching the scene. Each is a fixed ring of slots in packed arrays drawn in one `_draw()`
  from one texture (`EffectsLayer`'s pattern, ADR 0011 §3): no object per effect.

  | z | Layer | What | Why there |
  | --- | --- | --- | --- |
  | 3 | `GroundFx` | dust behind vehicles, track marks, wrecks | on the ground under every object; before `WorldSort` in the tree, so rings (z 3) draw over it; under the fog (z 4), which dims it |
  | 25 | `AirFx` | stack smoke, steam, flare and damage flame, muzzle smoke, exhaust, sparks | over every sorted sprite, under the bars (30) and projectiles (40) |
  | 55 | `StrikeFx` | the superweapons' launch and the effect from the sky | over the effects (50), under the ghost (60) and the strike marks (65) |

- **Textures:** `GroundFx` and `AirFx` draw `assets/art/svg/fx/life_atlas.svg`, `StrikeFx` draws
  `assets/art/svg/fx/strike_atlas.svg`; hand-written SVG, normal imports at scale 0.5 like
  `effects_atlas.svg`, none on the sorted world's page.
- **Draw calls:** `GroundFx` 1, `AirFx` 1, `StrikeFx` 1 or 2 while a strike plays (quads and the
  net's lines), 0 when empty. The forecast of ADR 0023 §2 becomes 16 (14 + 2), about 22 in the worst
  moment (19 + 3), under the trigger of 40.
- **Not used:** shaders or materials on sorted sprites and per-sprite `modulate` in `WorldSort`
  (either splits the one batch, ADR 0023 §2); Particles nodes (a node per emitter, their own
  randomness); a second atlas page for life frames (it would interleave in the sort).

### 4. Art: the frame axis and the atlas budget
- **The frame axis** (the generator, art-director): an `ArtPrim` may carry `group=<name>`; an
  `ArtModel` may list poses, each a part (`walk`, `idle` or `anim`), a frame count and, per frame,
  moves of named groups (an offset, and a turn about one axis through a pivot). The generator draws
  each pose frame with today's projection, light and shadow rules. `IsoSheetDef` gains `frames`
  (per part; 1 for every part of today), `stride_milli` (a squad's ground travel per walk cycle),
  `anim_ms` (an `anim` part's frame time) and `emitters` (kind and point, px, of each smoke, steam,
  flame or launch point, per hull frame for a unit, once for a building), and `marks` (`tracks`,
  `wheels` or none, for `GroundFx`; the snapshot does not carry the move class). A frame of a part
  with more than one frame per direction is named
  `<type_id>_<part>_d<NN>_f<K>.svg` (K from 0); a building's `anim` part has no direction
  (`<type_id>_anim_f<K>.svg`). Today's files keep their names and bytes.
- **The sets:** each squad gets `walk` (4 frames) and `idle` (2 frames) in its 8 directions; the
  standing frame stays `hull`; shadows are not posed (the standing shadow serves every pose). A
  building's `anim` has at most 16 frames, cropped to the moving element and anchored at the
  footprint centre, so it needs no mount. The fx sheets are hand-written (above).
- **Budget rule:** with every life frame, the sorted world's page for the cross-faction two-player
  match (Derrick League and Lumen Accord in their key triads) at `bake_scale` 1.0 is at most
  **3584** px tall (7/8 of 4096), leaving 512 rows for later types; mirror matches are smaller. A set
  that would pass it is cut (fewer frames, tighter crops) before any bake scale drops.
  `tests/view/test_iso_atlas_budget.gd` (P137) computes the page with `IsoAtlas.page_size` (no
  raster) from the committed sheets and pins it.
- **Estimates** (a replica of `RuntimeAtlas.layout` over the committed sheets; P137 measures the
  real page):

  | Page at bake scale 1.0 | Cross-faction | Mirror (Derrick) | Mirror (Lumen) |
  | --- | --- | --- | --- |
  | today | 4078 x 2682 | 4096 x 2196 | 4094 x 2226 |
  | + walk (4 x 8 per squad) | 3004 | 2472 | 2554 |
  | + idle (2 x 8 per squad) | 3164 | 2632 | 2718 |
  | + building `anim` parts (cropped, at most 16 frames) | about 3450 | about 2840 | about 3110 |

  The page's GPU memory (RGBA8, no mipmaps) grows from about 44 MB to about 56 MB in the
  cross-faction match, inside ADR 0023 §2's 64 MB.
- **Colours:** life fx are no team colour. Flames are yellow-white (hue at least 46°) and smoke and
  dust are greys, so nothing in them falls in the Derrick League's key band (1.6° to 45.3°, ADR 0023
  §5) and a fire never reads as team colour. Team-coloured parts that move (a rotor's tips) stay in
  the key triad on the atlas like any frame.
- **Originality** (ADR 0023 §13): the superweapon looks are a falling **bore lance** for the Deep
  Bore and a falling **net of light** for the Blackout Array (plan, P135 and P141). Not used: a beam
  or column from orbit (C&C's Ion Cannon), a missile rising out of silo doors (C&C's and StarCraft's
  nuclear launches), lightning, a mushroom cloud. The turning radars are the Signal Mast's slatted
  antenna panel and the Relay Tower's array faces, as modelled in P103 and P104, never a dish on a
  dome (svg-art-style's list).

### 5. Walking without sliding feet
- A squad shows `walk` while it moved in the last tick by at least half its type's step (the hull's
  own rule in `UnitLayer`), `hull` (standing) or an `idle` frame otherwise.
- The walk frame is `floor((travel + phase) / (stride_milli / 4)) mod 4`: `travel` is the row's
  ground distance in milli, accumulated as `|cur - prev|` once per new snapshot tick plus `alpha`
  times the last step inside the tick; `phase` is `mix(id, 0) mod stride_milli`. So the cadence
  follows the speed (a faster squad steps faster), it stops at once with the unit, and it does not
  depend on the frame rate. A frame that skips ticks (catch-up) loses those ticks' travel: a phase
  hiccup, never a slide.
- `stride_milli` is the art's (generator, per model); a data test pins the cadence of every squad of
  both rosters at 1.5 to 3.5 walk cycles per second at its `type_speed`.
- Inside one frame the three figures of a squad step out of phase (the art offsets each figure's
  pose by one frame), so a squad never marches in lockstep.

### 6. Fog
- Life on a rig or a building's sprites is drawn only when the rig or building is (`UnitLayer`'s and
  `BuildingLayer`'s rules); a hidden enemy rig changes nothing on screen.
- A layer effect is born only where the local player sees its source tile in that tick's fog (own
  rows always), as `EffectsLayer` does, and then lives out its time (at most 2.5 s; a wreck 20 s on
  a tile that was seen). An emitter on an enemy building emits only while `BuildingLayer.is_shown`
  says so; a last-seen ghost (z 5) has no life.
- **Superweapons:** the launch shows at a building the local player is shown; the rupture's falling
  lance is drawn for every player (its warning already is, ADR 0023 §10, so it reveals nothing); its
  burst and crater keep P112b's rule (the point's tile seen). The blackout's falling net shows where
  the local player sees the point's tile or fired it; the offline glyphs keep their rule.
- Nothing life draws depends on hidden state: no effect for a row the local player is not shown, no
  hint of an unseen strike building's charge.

### 7. The `STRIKE` event (amends ADR 0007 §10)
- `World.Event.STRIKE = 5`: `[5, building id, point x, point y, kind, owner, landing tick, 0]`,
  appended by `Strike.apply_superweapon` for every **accepted** `SUPERWEAPON`, after the point is
  clamped (so it is the point the sim uses). `kind` is `Strike.Kind` (1 rupture, 2 blackout); the
  landing tick is the rupture's `strike_tick` and 0 for a blackout. A dropped command writes none.
- It is written in COMMANDS, in command order beside the `SPAWNED` record a `PLACE` already writes
  there (`add_building` goes through `add_unit`), so before the tick's IMPACT, SHOT and DIED
  records. Combat's header comment ("the first `events` writer of a tick is `advance_projectiles`")
  has been stale since `PLACE` wrote a `SPAWNED` in COMMANDS; P133 corrects it. `events` is not
  state: no hash, golden, `STATE_FORMAT` or snapshot list changes, and no kernel writes events in
  COMMANDS.
- **Why:** the blackout keeps no point (§Context), and both launches need the building. **Rejected:**
  storing the blackout's point as state (a hashed column and a re-pin for a view need); inferring it
  from the buildings that went dark (wrong when none is in range, and a leak of which ones did).

### 8. Reduced effects
- `game/view/LifeSettings.gd` (a `Resource`) with `reduced: bool`, default false, in
  `data/life_settings.tres`; view-only, never loaded by `game/sim`, not in `defs_hash`. Each life
  row reads it and nothing else writes it during a match.
- **Reduced** drops the ambient: dust, track marks, wrecks, idle shake, look-around, head sweep,
  stack smoke, steam and flare flames, exhaust, muzzle smoke. It keeps what tells the player something: recoil, walking,
  idle poses (one region write in seconds), building animations (they stop when a building is
  offline), damage smoke and flame, construction sparks and the superweapon effects.
- **Now:** the flag and its tests, and the perf card's toggle (P147). The player's switch comes with
  Phase 5's settings screen, saved in `user://settings.cfg` like `[hud] haptics` (ADR 0025); no
  automatic switch.
- Per-effect numbers (sizes, times, rates) are exports of their scripts with defaults documented in
  STYLE.md's "Life effects" table, as `EffectsLayer`'s are; per-art numbers are in the sheets.
  They are look, not balance (CLAUDE.md rule 5 covers the sim's numbers).

### 9. Budget and proof
- **Work:** life costs at most 0.56 ms of main-thread work per frame on the phone card, judged by
  the card with life full and reduced (P147). No timing runs in a session (CLAUDE.md, Token budget).
- **Headless bounds** (each row's suite, and P146's combined test on the 150-unit perf arena
  scenario):
  - no node and no object made per frame or per effect after warm-up (node and object counts flat
    over 900 ticks with frames between them); `Anim` nodes = the animated buildings;
  - sprite writes per frame counted by a test hook in `RigLife` and `BuildingLayer`: at most 60 on
    average and 150 in any frame in the 150-unit arena;
  - ring capacities `GroundFx` 96 and `AirFx` 96 slots, `StrikeFx` 8; quads drawn never above them;
  - each life layer draws from one texture; `LifeFx`'s draw items are counted (the stand-in for
    calls, ADR 0023 §14);
  - the frame path of every life file allocates nothing (the source scan of
    `test_effects_layer_frames.gd`) and reads no `Time`, `randi`, `randf` or
    `RandomNumberGenerator` (`test_life_purity.gd`).
- Layer effects are born only for sources inside the camera's view rect grown by one tile, so a
  big off-screen battle costs no slots.

## Consequences
- The battlefield moves: turrets kick, squads walk and shift, buildings turn, spin, smoke and burn,
  and both superweapons get a launch and a fall from the sky, at about 0.5 ms a frame and two draw
  calls, with no sim change but one event.
- Replays and a second viewer see the same life at the same tick; a paused match freezes it.
- The atlas page grows by about a quarter; the 3584 rule leaves room for Phase 4's types, and P137's
  test fails the first art row that breaks it.
- The art generator gains poses: more model work per type (P139, P143), deterministic as today.
- `UnitLayer.gd` (708 lines) and `BuildingLayer.gd` (470) grow only by calls into `RigLife.gd`;
  the logic lives in the helper so neither nears gdlint's file length.
- Amends: ADR 0007 §10 (`STRIKE`); ADR 0023 §2 (z table rows 3, 25, 55; forecast 16; "animations
  are not Phase 3" for building animations and damage smoke) and §5 (frame names, "out of Phase 3:
  building damage states and animations"). On acceptance the lead's docs row writes dated notes in
  ADR 0007 and ADR 0023 before their "## Context" and the svg-art-style line of the plan.

## Alternatives considered
- **Particles nodes** (`CPUParticles2D`): a node per emitter, their own random seeds (life would
  differ per replay), and per-node cost; rejected for pooled rings.
- **Shaders for shake, recoil and animation:** a material per sprite splits the sorted world's one
  batch; rejected.
- **Life state in the sim** (an animation phase column): rule 1, and a hash for a look; rejected.
- **A second atlas page for life frames:** splits the y-sorted batch wherever the two pages
  interleave; rejected while the budget rule holds.
- **The frame clock for life:** runs on in a pause, differs per device; rejected (§2).
- **Smoke as sprites in `WorldSort`:** sorts exactly, but needs baked-alpha frames on the page and a
  node per puff; `AirFx` at z 25 draws smoke over units in front of a building, which reads as smoke
  in the air; accepted as the cheaper way.

## Questions for Michael
Recommendations in the plan's questions section (Q1-Q6): priority beside HUD v2, which optional
details, reduced effects, pause, the superweapon looks and the blackout's timing.
