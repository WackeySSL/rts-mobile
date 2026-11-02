# ADR 0027: Unit life and effects (a view-only animation layer)

Status: accepted, 2026-11-02 (Michael; his answers below). Proposed the same day on `main` at
3c29b16 and revised after the lead's one-lens docs review (contract and feasibility). Plan:
`docs/plans/2026-11-02-unit-life.md` (rows P132-P154; P132 is this ADR and plan, with the dated
notes in ADR 0007 and ADR 0023; the lead's P26aq applies the svg-art-style text and the ROADMAP
line). Amends ADR 0007 §10 (one new event kind), ADR 0023 §2 (the z table, the draw-call forecast,
"damage states and animations are not Phase 3") and §5 (the frame names, "out of Phase 3: building
damage states and animations"). Everything else here is view and art: no rule, state column,
Command or golden hash changes.

## Michael's answers (2026-11-02)
1. **Now:** the life lanes run beside HUD v2; where the lead must choose, HUD and the Phase 3 gate
   rows go first.
2. **Yes to P148, P149 and P150; P151-P154 later**, when lanes are free (they stay rows).
3. **A:** a `reduced` flag in data now; the player's switch comes with Phase 5's settings screen.
4. **Life freezes with the match** in a pause.
5. **A:** the Deep Bore's bore lance; the Blackout Array's light seed and mint hex net.
6. **A:** the offline glyphs show at once; the net lands about 0.6 s later.
7. Yes to the svg-art-style text (the lead applies it in P26aq).

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
  `offline_until`, `power_made`/`power_used`, `strike_x/y/tick`, `type_strike_radius`) and every
  `SHOT`, `IMPACT` and `DIED`, except one thing: **a blackout leaves no point.**
  `Strike.apply_superweapon` writes `strike_x`/`strike_y` only for a rupture; a blackout only sets
  `offline_until` on the buildings it hits, so the view cannot place a falling effect on its area,
  and it learns which building fired only by diffing `ready_tick`. The snapshot has no move class
  (`type_move_class` is not copied, and every vehicle has the same one), so tracks versus wheels is
  an art fact.
- **Budgets.** CLAUDE.md rule 6 (150 units at 60 fps on a mid-range 2021 phone), ADR 0014's
  main-thread `work_p95_ms` 5.6 on the phone card, ADR 0023 §2's draw-call forecast (14, about 19
  in the worst moment, trigger 40) and its one atlas page of at most 4096 x 4096 for the sorted world.
- **Fog and own state** (ADR 0010 §2, ADR 0020 §1, ADR 0023 §2): the fog lies on the ground at z 4;
  objects above it are hidden by their own rules; effects are born only on seen tiles. A player's
  power totals and an own row's `order` and `harvest_mode` are that player's state (`PlayerView`
  hands them out for own rows only).
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
   one `LifeFx` node: `GroundFx` z 3, `AirFx` z 25, `StrikeFx` z 55, each ring split into fixed
   quotas per kind (§3).
4. **Art gets a frame axis:** parts may have several frames per direction (`walk`, `idle`, `anim`),
   named `_f<K>`; a frame change looks its region up in a packed table, never through a string key;
   the cross-faction two-player page at bake scale 1.0 stays at most 3584 px tall (§4).
5. **Walking** advances by distance travelled, not by time (§5).
6. **Fog and own state:** life shows only what the view already shows for that row; low power and
   `harvest_mode` drive life on own rows only (§6).
7. **`STRIKE` event** `[5, building id, x, y, kind, owner, landing tick or 0, 0]` (§7).
8. **Numbers in data:** every life number is in `LifeSettings` (`data/life_settings.tres`) or in
   the art's sheet; `reduced` is a flag there, switched by the player in Phase 5 (§8).
9. **Budget:** life costs at most 0.56 ms of main-thread work per frame (10 % of 5.6) on the phone
   card and adds at most 2 draw calls (3 during a strike), pinned by headless tests on the base
   arena (§9).

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
  event of tick `t` is born at `t x 1000 / 15`; its age is the clock minus that, **clamped at 0**. In
  the frame that first shows a tick, alpha is near 0, so an event's effect starts at age about 0.
- **Why match time:** it stops with the match (`MatchRunner.paused`, the app in the background), so
  a paused game freezes mid-step (answer 4); it is the same at the same tick on every device and
  frame rate, so a replay or a second viewer sees the same pose at the same tick (up to alpha
  sampling); and a test sets tick and alpha instead of faking a clock. **Rejected:** the frame clock
  (life would run on in a pause and differ per device).
- **Resume:** in WORKER mode the runner restarts alpha at 0 in the first frame after a pause or a
  background (`MatchRunner.paused`'s comment), so the clock can step back by up to one tick. Every
  age is clamped at 0 and every per-row accumulator moves only forward (§5), so nothing plays
  backwards or goes negative; P136 pins it.
- Existing frame-clock users (`EffectsLayer`, hit times, move marks, the HUD) keep their clock; this
  ADR changes none of them.
- **Variation:** `LifeClock.mix(id, salt)` is a 31-bit integer mix (multiplications by odd
  constants and xor-shifts, masked), pinned by golden values in a test. A periodic life effect
  (idle pose, look-around, head sweep, emitter) picks its phase and its window in each cycle from
  `mix(id, cycle)`, so it is stateless, desynchronised per entity and replays alike; its tests assert
  exact counts for fixed id sets. No `hash()` (its output is not part of any contract), `randi`,
  `randf`, `RandomNumberGenerator`, `CPUParticles2D` or `GPUParticles2D` in life code;
  `tests/view/test_life_purity.gd` scans the life files for them and for `Time.`.

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
  without touching the scene. Each is a ring of slots in packed arrays drawn in one `_draw()` from
  one texture (`EffectsLayer`'s pattern, ADR 0011 §3): no object per effect.

  | z | Layer | What | Why there |
  | --- | --- | --- | --- |
  | 3 | `GroundFx` | dust behind vehicles, track marks, wrecks | on the ground under every sorted object; before `WorldSort` in the tree, so rings (z 3) draw over it; under the fog (z 4), which dims it |
  | 25 | `AirFx` | stack smoke, steam, flare and damage flame, muzzle smoke, exhaust, sparks | over every sorted sprite, under the bars (30) and projectiles (40) |
  | 55 | `StrikeFx` | the superweapons' launch and the effect from the sky | over the effects (50), under the ghost (60) and the strike marks (65) |

- **Accepted draw order:** `GroundFx` at z 3 draws over the unit shadows (z 2) and the building
  shadows (z 1). Dust lies on the ground and over a shadow is right; a track mark or a wreck over a
  cast shadow is a small error that saves a call. If the phone check minds it, marks and wrecks
  move to a second node at z 2 before `WorldSort` (one more call).
- **Quotas.** A ring is split into fixed slot ranges per kind; a kind overwrites only its own oldest
  slot, so a long-lived kind is never pushed out by a busy one:

  | Layer | Kind | Slots | Bound behind it |
  | --- | --- | --- | --- |
  | `GroundFx` | dust | 48 | one puff per `dust_every_milli` of travel per vehicle in view, life 0.6 s |
  | `GroundFx` | track marks | 32 | in view only, life 2.5 s |
  | `GroundFx` | wrecks | 16 | life 20 s; the 17th oldest goes first |
  | `AirFx` | emitters (stack smoke, steam, flare) | 80 | `emit_ms` at least 500 and life at most 2 s: at most 4 live per emitter, 20 emitters in view |
  | `AirFx` | damage smoke and flame | 24 | at most 2 points per building in view |
  | `AirFx` | muzzle smoke, exhaust, sparks | 24 | life at most 0.5 s |
  | `StrikeFx` | launch, fall, net | 8 | at most two strikes at once |

  A row that does not exist yet keeps its slots unused (no slot is lent across kinds).
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
  `anim_ms` (an `anim` part's frame time), `emitters` (kind and point, px, of each smoke, steam,
  flame, exhaust or launch point, per hull frame for a unit, once for a building) and `marks`
  (`tracks`, `wheels` or none, from the model's running gear; the snapshot carries no move class). A
  frame of a part with more than one frame per direction is named `<type_id>_<part>_d<NN>_f<K>.svg`
  (K from 0); a building's `anim` part has no direction (`fossil_radar_anim_f0.svg`). Today's files
  keep their names and bytes.
- **The bake reads the axis before any art uses it.** Today `IsoAtlas._collect_sheet` asks
  `sheet.path(part, dir)`, which has no frame, so a multi-frame part would log "no SVG text" (and
  `push_error` fails every suite). P137 teaches the bake and `WorldSort` the axis, and no art row
  commits a multi-frame part before P137 has merged.
- **No string per frame change.** Today `WorldSort.show_frame` → `IsoAtlas.region` builds a
  `StringName` key with `%` formatting on every call; with poses and animations that would run 15 to
  20 times a frame. P137 resolves a base index for (art id, part, direction, player) when a sprite is
  dressed or its direction changes, and a frame change reads `regions[base + frame]` from a packed
  `Rect2i` table; a test fails if a frame change builds a string key.
- **The sets:** each squad gets `walk` (4 frames) and `idle` (2 frames) in its 8 directions; the
  standing frame stays `hull`; shadows are not posed (the standing shadow serves every pose). A
  building's `anim` has at most 16 frames, cropped to the moving element and anchored at the
  footprint centre, so it needs no mount. A moving part of a vehicle (the tanker's pump arm, later)
  is a cropped overlay on a sprite the rig already has (a tanker has no `Turret`), never a second
  set of full hull frames. The fx sheets are hand-written (above).
- **Budget rule:** with every life frame, the sorted world's page for the cross-faction two-player
  match (Derrick League and Lumen Accord in their key triads) at `bake_scale` 1.0 is at most
  **3584** px tall (7/8 of 4096), leaving 512 rows for later types; mirror matches are smaller. A set
  that would pass it is cut (fewer frames, tighter crops) before any bake scale drops.
  `tests/view/test_iso_atlas_budget.gd` (P137) computes the page with `IsoAtlas.page_size` (no
  raster) from the committed sheets and pins it.
- **Estimates** (two replicas of `RuntimeAtlas.layout` over the committed sheets, the architect's
  with conservative crops and the lead's reviewer's; P137 measures the real page). The page is
  always 4096 wide:

  | Page height at bake scale 1.0 | Cross-faction | Mirror (Derrick) | Mirror (Lumen) |
  | --- | --- | --- | --- |
  | today | 2682 | 2196 | 2226 |
  | + walk (4 x 8 per squad) | 2918 to 3004 | about 2472 | about 2554 |
  | + idle (2 x 8 per squad) | 3060 to 3164 | about 2632 | about 2718 |
  | + building `anim` parts (cropped, at most 16 frames) | about 3350 to 3450 | about 2840 | about 3110 |

  The page's GPU memory (RGBA8, no mipmaps) grows from about 44 MB to at most 56 MB in the
  cross-faction match, inside ADR 0023 §2's 64 MB. The baked slots grow from 480 to about 720, so
  the bake takes about half as long again: P137 reports `atlas_bake_ms` (desktop and the web
  preview) and P147's phone card reports it on the phone.
- **Colours:** life fx are no team colour. Flames are yellow-white (hue at least 46°) and smoke and
  dust are greys, so nothing in them falls in the Derrick League's key band (1.6° to 45.3°, ADR 0023
  §5) and a fire never reads as team colour. Team-coloured parts that move (a rotor's tips) stay in
  the key triad on the atlas like any frame.
- **Originality** (ADR 0023 §13): the superweapon looks are a falling **bore lance** for the Deep
  Bore and a falling **net of light** for the Blackout Array (answer 5). Not used: a beam or column
  from orbit (C&C's Ion Cannon), a missile rising out of silo doors (C&C's and StarCraft's nuclear
  launches), lightning, a mushroom cloud. The "radar dish" Michael asked for is the Signal Mast's
  slatted antenna panel and the Relay Tower's array faces turning, as modelled in P103 and P104,
  never a dish on a dome (svg-art-style bans "a dome on a radar tower").

### 5. Walking without sliding feet
- A squad shows `walk` while it moved in the last tick by at least half its type's step (the hull's
  own rule in `UnitLayer`), `hull` (standing) or an `idle` frame otherwise.
- The walk frame is `floor((travel + phase) / (stride_milli / 4)) mod 4`: `travel` is the row's
  ground distance in milli, accumulated as `|cur - prev|` once per new snapshot tick plus `alpha`
  times the last step inside the tick (never less than the value last shown); `phase` is
  `mix(id, 0) mod stride_milli`. So the cadence follows the speed (a faster squad steps faster), it
  stops at once with the unit, and it does not depend on the frame rate. A frame that skips ticks
  (catch-up) loses those ticks' travel: a phase hiccup, never a slide.
- `stride_milli` is the art's (generator, per model); a data test pins the cadence of every squad of
  both rosters at 1.5 to 3.5 walk cycles per second at its `type_speed`.
- Inside one frame the three figures of a squad step out of phase (the art offsets each figure's
  pose by one frame), so a squad never marches in lockstep.

### 6. Fog and own state
- Life on a rig or a building's sprites is drawn only when the rig or building is (`UnitLayer`'s and
  `BuildingLayer`'s rules); a hidden enemy rig changes nothing on screen.
- **Life shows only what the view already shows for that row:** positions and movement, `hp` of a
  shown row (its bar), `target_row` (today's turret aim follows it for every shown rig), a shown
  enemy site (ADR 0026 §9's badge) and a shown enemy building's blackout (`HealthBarLayer`'s offline
  glyph, ADR 0023 §10). So a building's animation holds while it is a site or offline, for own and
  shown enemy buildings alike.
- **Own state drives own rows only:** the half-rate animation on low power reads the local player's
  `power_made` and `power_used` and applies to the local player's buildings; an enemy building's
  animation never depends on its owner's power. `harvest_mode` drives the tanker's pump arm on own
  tankers only. No life reads `order`, `cargo`, `queue_*`, `credits` or `ready_tick` of an enemy.
- A layer effect is born only where the local player sees its source tile in that tick's fog (own
  rows always), as `EffectsLayer` does, and then lives out its time (at most 2.5 s; a wreck 20 s on
  a tile that was seen). An emitter on an enemy building emits only while `BuildingLayer.is_shown`
  says so; a last-seen ghost (z 5) has no life.
- **Superweapons:** the launch shows at a building the local player is shown; the rupture's falling
  lance is drawn for every player (its warning already is, ADR 0023 §10, so it reveals nothing); its
  burst and crater keep P112b's rule (the point's tile seen). The blackout's falling net shows where
  the local player sees the point's tile or fired it; the offline glyphs keep their rule and show at
  once (answer 6).

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

### 8. Numbers in data, and reduced effects
- **`game/view/LifeSettings.gd`** (a `Resource`) and **`data/life_settings.tres`**, as
  `InputSettings` and `data/input_settings.tres`: view-only, never loaded by `game/sim`, not in
  `defs_hash`. Every life consumer (`UnitLayer`, `BuildingLayer`, `RigLife`, `LifeFx` and its
  layers) has `@export var life: LifeSettings`, which falls back to
  `preload("res://data/life_settings.tres")` when unset; `LifeFx` hands its own to the layers it
  makes; tests pass their own instance. So every number is reachable without a scene edit, and
  Michael can tune or turn off one effect in the `.tres`.
- **What lives there:** per weapon id (dictionaries like `EffectsLayer.flash_px`): `recoil_px`,
  `rock_px`; the recoil times `recoil_out_ms`, `recoil_back_ms`; rigs: `shake_px`, `shake_ms`,
  `look_every_ms` and `look_ms`, `sweep_frames` and `sweep_ms`, `idle_after_ms`, `idle_every_ms`
  and `idle_ms`; `GroundFx`: `dust_every_milli` and lifetimes; `AirFx`: `emit_ms` per emitter kind
  (at least 500), lifetimes, drift, the damage thresholds; `StrikeFx`: `launch_ms`, `fall_ms`,
  `net_land_ms`; the quotas of §3; `low_power_rate` (0.5); and `reduced`. The art's own numbers
  (`stride_milli`, `anim_ms`, `emitters`, `marks`) are in the sheets the generator writes.
  STYLE.md's "Life effects" table documents the looks; the `.tres` is where the numbers live.
- **Reduced** drops the ambient: dust, track marks, wrecks, idle shake, look-around, head sweep,
  stack smoke, steam and flare flames, exhaust, muzzle smoke, the factory puff. It keeps what tells
  the player something: recoil, walking, idle poses (one region write in seconds), building
  animations (they hold when a building is offline or a site), damage smoke and flame, construction
  sparks and the superweapon effects (answer 3).
- **Who writes `reduced`:** nobody during a match, with one carve-out: P147's dev card toggle on the
  perf arena. On a change every life layer empties its rings, and `RigLife` sets the offsets it owns
  back to zero (one write per offset sprite), so no effect is left frozen mid-life. The player's
  switch comes with Phase 5's settings screen, saved in `user://settings.cfg` like `[hud] haptics`
  (ADR 0025) and read at match start; no automatic switch.

### 9. Budget and proof
- **Work:** life costs at most 0.56 ms of main-thread work per frame on the phone card, judged by
  the card with life full and reduced (P147). Life files cannot read `Time`, so the card times the
  life calls in their callers (`UnitLayer._process`, `BuildingLayer._process`, `LifeFx`'s children
  as the card's own probes); a difference of 0.56 ms between two whole phone runs is inside the
  noise. No timing runs in a session (CLAUDE.md, Token budget).
- **Headless bounds** (each row's suite, and P146's combined test on the base arena scenario
  `data/scenarios/perf_bases.tres`: 150 mobile rows, 28 buildings of both factions, both strikes
  inside 900 ticks, ADR 0023 §14; the scenario P93c moves the perf arena scene to):
  - no node and no object made per frame or per effect after warm-up (node and object counts flat
    over 900 ticks with frames between them); `Anim` nodes = the animated buildings;
  - sprite writes per frame counted by a test hook in `RigLife` and `BuildingLayer`: at most 60 on
    average and 150 in any frame;
  - each kind's slots never above its quota (§3); quads drawn never above the ring;
  - each life layer draws from one texture; `LifeFx`'s draw items are counted (the stand-in for
    calls, ADR 0023 §14);
  - the frame path of every life file allocates nothing (the source scan of
    `test_effects_layer_frames.gd`), a frame change builds no string key (§4), and no life file
    reads `Time`, `randi`, `randf` or `RandomNumberGenerator` (`test_life_purity.gd`).
- Layer effects are born only for sources inside the camera's view rect grown by one tile, so a
  big off-screen battle costs no slots.

## Consequences
- The battlefield moves: turrets kick, squads walk and shift, buildings turn, spin, smoke and burn,
  and both superweapons get a launch and a fall from the sky, at about 0.5 ms a frame and two draw
  calls, with no sim change but one event.
- Replays and a second viewer see the same life at the same tick; a paused match freezes it.
- The atlas page grows by about a quarter and the bake by about half; the 3584 rule leaves room for
  Phase 4's types, and P137's test fails the first art row that breaks it.
- The art generator gains poses: more model work per type (P139, P143), deterministic as today.
- `UnitLayer.gd` (708 lines) and `BuildingLayer.gd` (470) grow only by calls into `RigLife.gd`;
  the logic lives in the helper so neither nears gdlint's file length.
- Amends: ADR 0007 §10 (`STRIKE`); ADR 0023 §2 (z table rows 3, 25, 55; forecast 16; building
  animations and damage smoke are no longer "not Phase 3") and §5 (frame names; "out of Phase 3:
  building damage states and animations" withdrawn for what this ADR adds). P132 wrote the dated
  notes in ADR 0007 and ADR 0023; the lead's P26aq applies the svg-art-style text.

## Alternatives considered
- **Particles nodes** (`CPUParticles2D`): a node per emitter, their own random seeds (life would
  differ per replay), and per-node cost; rejected for pooled rings.
- **Shaders for shake, recoil and animation:** a material per sprite splits the sorted world's one
  batch; rejected.
- **Life state in the sim** (an animation phase column): rule 1, and a hash for a look; rejected.
- **A second atlas page for life frames:** splits the y-sorted batch wherever the two pages
  interleave; rejected while the budget rule holds.
- **The frame clock for life:** runs on in a pause, differs per device; rejected (§2).
- **Script exports for the life numbers** (`EffectsLayer`'s way): `LifeFx` makes its layers in code
  and `RigLife` is a helper, so no scene could set them; rejected for `LifeSettings` (§8).
- **Smoke as sprites in `WorldSort`:** sorts exactly, but needs baked-alpha frames on the page and a
  node per puff; `AirFx` at z 25 draws smoke over units in front of a building, which reads as smoke
  in the air; accepted as the cheaper way.

## Questions for Michael (answered 2026-11-02)
The six questions and their recommendations are in the plan's questions section; Michael took every
recommendation (answers above).
