# ADR 0029: Buildings shot to pieces: four stages, collapse, ruin and hit feedback (view and art only)

Status: proposed 2026-11-03 (P26as, architect). Written on `main` at 4b5c26d (#297, P26ar,
merged). The decisions taken from Michael's two reference sheets of 2026-11-03 and from his answer
"Kun grafik" are his and are not open; the questions at the end are. Plan:
`docs/plans/2026-11-03-damage-states.md`, section "ADR 0029 rework" (rows P163-P167, P157c, P158a,
P158b, the re-scoped P159, P148 and P162). On acceptance the lead's P26at writes the dated notes:
ADR 0028 (a status note at the top pointing here), ADR 0027 §8 (what `reduced` keeps) and the
unit-life plan's "camera shake" out-of-scope line, ADR 0023 §5 (the part name `ruin`).

It amends ADR 0028: §2 (the thresholds, one list per kind), §3 (what `dmg1` and `dmg2` show; the
second amendment's open point on the seam, §12 here), §6 (the particles), §7 (reduced effects), §8
(the budget) and §9 (the data). Everything else in ADR 0028 stands: view and art only, stages as a
pure function of hp, the trimmed body with a `Damage` sibling, `DAMAGE_SCALE`, the hidden `Anim` at
stage 2, the vehicle overlays, the remembered stage and the ghosts. No rule, state column, Command,
event or golden hash changes; no file in `game/sim` or `native/` changes.

**Why a new ADR and not a fourth amendment of ADR 0028.** The sheets add three systems ADR 0028
does not have (a collapse with a ruin, hit feedback, a camera shake), change the meaning of both
stage pictures and the thresholds, and touch ADR 0027 and ADR 0023 too. ADR 0028 already carries
three dated amendments of its §3; a fourth that rewrites §2, §3, §6, §7 and §8 would leave no
readable text. ADR 0028 stays the record of the stage mechanics; this ADR is the record of the look.

## Context
- **Michael, 2026-11-03.** Two reference sheets "as inspiration for buildings that are breaking":
  one shows two example buildings in four stages each; the other ("Bygninger der bliver skudt i
  stykker") has a four-stage table, five material rules, "two layers: sprite + effects", the
  collapse at 0 % with timings, eight rules for us and a material rule for each of our 16 building
  ids. The building and faction names on the sheets are reference examples only: our factions,
  buildings and names stay, and no name from the sheets goes into the repo (nor the images).
- **What the sheet says is wrong with today's damage art** (P158's first pass, which it shows):
  1. the damaged stage looks like the intact one (the same shape, a darker roof, a bent chimney:
     on a phone the difference cannot be seen);
  2. the destroyed stage is clean straight blocks in the original colours: it reads as toy blocks,
     not as a ruin;
  3. no interior: a break never shows floor slabs, beams or dark rooms behind;
  4. no life: no smoke, fire, embers or debris outside the footprint, and white stays white.
- **Michael's answer to "what does the 45 s ruin block?": "Kun grafik"** (graphics only). The ruin
  lies 45 s and blocks nothing; a building placed on its tiles removes it at once. This overrides
  the sheet's rule 6 ("the ruin lies 45 s and blocks the field"). So ADR 0028's "view and art only"
  stands: no sim change, no golden hash change.
- **What exists.** P156 (generator v4: damage poses `shift`, `turn`, `hide`, `char`, `damage=<k>`
  primitives, the geometric cut, patches cropped to ink, `cuts`, the count rules) is on `main`.
  P157 (the neutral sheet, PR #299) and P157b (`DAMAGE_SCALE` 0.75, branch
  `claude/p157b-damage-scale` at 9a3b8b3) are open. P158 (`dmg1`/`dmg2` for all 16 buildings, two
  `damage` points each, the gallery's Stage button; branch `claude/p158-building-damage` at
  573f720) is on hold because this spec changes its target; it measured the page at
  3476 / 2875 / 3023 (cross / mirror Derrick / mirror Lumen) of 3584 with both patches at 75 %,
  210 rows over the 3266 baseline. The view: `EffectsLayer._add_death` (a DIED burst), the
  `DecalLayer` crater (`decals/crater.svg`) that `BuildingLayer._drop` lays for a building that
  falls in sight, `AirFx` (rings: emitters 80, damage 64 by ADR 0028, muzzle 24), P152's wrecks
  (a husk for 20 s, later). `RtsCamera` has no shake; the unit-life plan puts camera shake out of
  scope ("the camera moves only by the player's hand"). There is no repair.
- **Batching** (ADR 0023 §2, ADR 0028's Context): a per-sprite tint, a material or another texture
  inside the sort splits the one `WorldSort` batch; regions, offsets, positions, scales and flips are
  free.

## Decisions in short
1. **View and art only** (Michael, "Kun grafik"): the ruin is a view entry, like a wreck.
2. **Four stages:** INTAKT, SKADET, KRITISK, RUIN. Buildings switch at 67 and 34 (strict "under"):
   67-100 % intact, 34-66 % SKADET, 1-33 % KRITISK; RUIN after DIED. One list per kind in data.
3. **Pictures:** `dmg1` = SKADET and `dmg2` = KRITISK stay top patches over the trimmed body; RUIN
   is a **whole low sprite**, part `ruin`, shown on the dying building's own `Body` sprite.
4. **Art language** per stage from the sheet's table, the five material rules, a rule per building.
5. **Generator v5:** a `ruin` pose, broken (jagged) edges, rods for rebar and beams, interior and
   hole materials, `blow` and `soot` moves, rubble and petal helpers, key faces that may char out of
   the band, 2-4 `damage` points and 1-3 `ruin` points per building.
6. **Particles per stage** in `AirFx`: a fixed-seed choice of the burning points, at most 30 smoke
   puffs per burning building, one shared glow pass, no blur.
7. **Hit feedback:** a white flash of 60 ms at the hit point and 3-5 chips, from IMPACT. **Only a
   collapse shakes the camera**, view-only, a collapse the player sees on screen, none in reduced.
8. **Collapse** from DIED: flash and explosion 0-250 ms, sink and dust from 250, the switch to the
   ruin under the dust at 700, the ruin from 900; it lies 45 s, then sinks into the crater.
9. **Fog:** a collapse and a ruin only for a death the player saw; a ruin is drawn by the fog rule of
   a live building; no ghost of a ruin; nothing is invented for a death not seen.
10. **Reduced effects** keep every picture, the ruin, the fire, the flash and the dust; they drop
    sparks, embers, chips, debris, the ruin's smoke and the shake.
11. **Budget:** no new draw call; collapse writes inside the buildings' write share; the page stays
    at most 3584 (estimate and fallbacks in §11).
12. **The seam rule** of the trimmed body and its patch is the one in `IsoAtlas`'s `DAMAGE_SCALE`
    block (P157b), not ADR 0028's "at least 1 texel".
13. **Repair:** none in the game; recorded for a future repair ADR.

## Decision

### 1. View and art only
- Every part of this ADR reads the published snapshot and its events (`IMPACT`, `DIED`) in the
  layers' `ticked` and frame paths, and the match time (`LifeClock`). Nothing is added to the sim:
  the ruin is not a row, not an obstacle and not a placement rule.
- **The ruin is a view entry**, kept by `BuildingLayer` after the building's row is gone, like
  P152's wrecks are kept by `GroundFx`. **Rejected:** a ruin in the sim (a blocked footprint for
  45 s): Michael's answer, and it would be hashed state, a placement rule and a golden re-pin.

### 2. Four stages and their thresholds
- **INTAKT 100-67 %, SKADET 66-34 %, KRITISK 33-1 %, RUIN 0 %** (Michael: "skift ved 66 % og 33 %").
  Under ADR 0028 §2's strict "under" rule the integers are **`[67, 34]`**:
  `stage = (1 if hp x 100 < max x 67) + (1 if hp x 100 < max x 34)`. So 67 % exactly is intact,
  anything under 67 % is SKADET, 34 % exactly is SKADET, anything under 34 % is KRITISK. The
  sheet's bands are these thresholds read as whole percents rounded down (66.9 % reads as 66).
- **RUIN is not a value of the function.** A row with hp 0 or less is removed by the sim in the same
  tick (`World` REMOVE, a DIED record), so the view never sees a live row at 0 %; RUIN is what the
  view shows after a building's DIED (§8).
- **The thresholds stay in data, one list per kind:** `LifeSettings.building_stage_percent`
  (`[67, 34]`) and `LifeSettings.vehicle_stage_percent` (`[50, 25]`, ADR 0028's values, until
  Michael answers question 1). They replace ADR 0028 §9's single `damage_stage_percent` (not on
  `main` yet: P159 creates the fields). The data test holds `100 > P1 > P2 > 0` for each list.
  `BuildingDamage.stage_of(hp, max, percents)` takes the list, so buildings, vehicles and `AirFx`
  still share one function. No hysteresis, no latch (ADR 0028 §2 stands).
- **Sites** show no stage (ADR 0028 §2 stands).

### 3. The pictures of each stage
| Stage | Part | What it is | Where it draws |
| --- | --- | --- | --- |
| INTAKT | `hull` | today's body | `Body` in the sort |
| SKADET | `dmg1` | top patch over the trimmed body (ADR 0028 §3) | `Damage` sibling of `Body` |
| KRITISK | `dmg2` | top patch over the trimmed body; the `Anim` hidden (ADR 0028 §3, third amendment) | `Damage` sibling of `Body` |
| RUIN | `ruin` | a **whole low sprite** of the rubble, the foot and the debris outside the footprint | on the `Body` sprite, re-dressed (§8) |

- **Why the ruin is a whole sprite and not a patch.** A patch shows the change above a cut over the
  intact body's rows below it. After DIED nothing of the intact body may remain: the walls are
  stubs, soot lies over everything and debris lies outside the footprint, below and beside the
  body's canvas. A patch whose cut is the foot is a whole sprite anyway, and its canvas has to be
  wider than the body's for the debris. So the ruin has its own canvas, cropped to its ink, and no
  cut. It is the third damage part on the sheet (`parts` gains `ruin`; its size and anchor like any
  part; `cuts` keeps its two entries for `dmg1` and `dmg2`).
- **The `Anim` and a defence's `Head`** are not in the ruin: the ruin pose draws no `anim`
  primitive, and the view hides `Anim` and `Head` at the collapse's start (§8), behind the flash.
  ("The turret is lifted off" and "the gun is lifted off" are the defences' ruins: an empty ring.)
- **A building whose sheet has no `ruin`** (a crafted test sheet, a type added later) collapses into
  the crater: the sequence of §8 without the switch, the building hidden at 700 ms.
- **What P158's art becomes** (its poses no longer match: its `dmg1` "holes down to half" and its
  `dmg2` "a low ruin"):
  - P158's `dmg1` poses (holes, roofs torn out, the dark inside) are the **starting point of the new
    `dmg2`, KRITISK**: a part has collapsed, the inside is visible. They gain the interior (slabs,
    rebar, beams), the breaks of their material rule and soot.
  - P158's `dmg2` poses (rubble and wall stubs) are the **starting point of `ruin`**: they lose the
    stubs that carried an `anim` element or a `mount` (the ruin has neither), gain the foot, soot
    over everything and debris outside the footprint.
  - The **new `dmg1`, SKADET, is new work**: small nicks at a corner, a mast or a wing, blown panes
    with their frames kept, soot over the holes; the silhouette changes, unlike P158's first pass.
  - Kept from the branch: the gallery's Stage button (now four stages), the page test's structure
    and the `DAMAGE_PARTS` pin, the tests. The branch is not merged as it is; the art rows of the
    plan (P158a, P158b) carry what is kept.

### 4. Art language per stage
**The table** (Michael's sheet; the rule for every building and every stage):

| | INTAKT | SKADET | KRITISK | RUIN |
| --- | --- | --- | --- | --- |
| Life | 100-67 % | 66-34 % | 33-1 % | 0 % |
| Silhouette | whole | small nicks: a corner, a mast, a wing | a part has collapsed | low: stubs and a heap |
| Surfaces | clean | blown panes, soot over the holes | the inside shows: slabs, rebar, beams, dark rooms | soot over everything, debris outside the footprint |
| Light | - | one fire, a weak glow | fire lit from inside | embers |
| Smoke | - | grey and thin | black and thick | thin and grey, 8 s |
| Team colour | 100 % | about 70 % | about 35 % | only remnants |

- Each stage changes the **shape** more than the one before; damage must read in the silhouette, not
  in the colour alone (the sheet's heading). The ruin is low, dark and messy, never clean blocks.
- **Smoke, fire, embers and sparks are never drawn into a sprite** (the sheet's "two layers: sprite
  plus effects", rule 2): a sprite is one picture with no smoke or fire, so the particles can move
  and go out. The particles are §6.
- **The five material rules:**
  - **Concrete** breaks along the panel joints and the floor slabs; rebar sticks out of every break;
    grey lumps and dust.
  - **Steel** bends and twists, it never shatters; the skeleton stays standing in the ruin.
  - **Glass:** the panes go first, as dark holes; the frames stay; shards lie on the ground.
  - **Tanks and spheres:** a hole, then a burning gas jet, then torn open like a flower of plates.
  - **Masts and towers** snap in one place and fall in one direction; the top lies beside the stump.
  - Brick (two of our buildings) follows the concrete rule without rebar: it breaks along its
    courses into red-brown lumps.
- **Per building** (the sheet's table for our 16 ids, in our words):

  | Fossil id | Rule | Renew id | Rule |
  | --- | --- | --- | --- |
  | `barracks` | concrete, the full concrete rule | `renew_barracks` | the white cladding is sooted, the glass wing shatters |
  | `headquarters` | concrete; the chimney snaps and topples | `renew_hq` | glass and concrete; the floors fall in steps |
  | `power_plant` | brick; the boilers burn | `renew_power` | blades and towers, the mast rule |
  | `refinery` | gas spheres, the tank-and-sphere rule | `renew_refinery` | the tanks crack and fall together |
  | `vehicle_factory` | brick and steel trusses; the roof falls in | `renew_factory` | a glass roof, the glass rule |
  | `fossil_radar` | the steel lattice bends and topples | `renew_radar` | the dome is punctured, the mast snaps |
  | `defence_turret` | concrete; the turret is lifted off | `renew_defence` | concrete; the gun is lifted off |
  | `fossil_strike` | a steel portal; the ruin is a twisted skeleton | `renew_strike` | the pillars snap, the ring beam falls |

- **Team colour per stage** is the share of the intact picture's key-colour pixels that is still key
  colour: SKADET about 70 %, KRITISK about 35 %, RUIN remnants (a few shards and a panel). The art
  gets there by hiding, turning and charring team faces (§5); a test measures it (§5).
- **Depth on the body** (the page, §11): SKADET's changes reach at most half the body's rows from
  its top (ADR 0028 §3's amendment for stage 1); KRITISK may reach down to just above the foot (the
  generator still refuses a change that reaches the foot); the ruin rises at most half the body's
  canvas height.
- **Originality** (CLAUDE.md Legal, ADR 0023 §13, ADR 0028 §4): every picture is generated here from
  our own models; flames stay yellow-white and smoke grey, outside both factions' key bands.

### 5. Generator v5 (`tools/artgen/`)
Features the art needs, each one a simple 3D-to-SVG step (primitives, moves, palette, the painter's
order), deterministic (no randomness: where a helper varies, it varies by an integer hash of the
model id and the line, as `LifeClock.mix` does in the view), **generated, never hand-edited**:
- **The `ruin` pose:** a third damage part of a building, `ruin`, frame 0, with `damage=3`
  primitives (drawn only in the ruin). It is a whole picture (no cut, no overlap), cropped to its
  ink. It draws no `anim` primitive; unlike `dmg1` and `dmg2` it may move or hide the `mount` group.
  Its primitives may lie up to a quarter tile outside the footprint at a height of at most 0.1 tile
  (debris on the ground; the sort error of §8 stays a few px of flat rubble). Refused: a ruin whose
  ink rises above half the body's canvas height; a ruin without `dmg2`.
- **Broken edges:** a shape `broken`, a box whose top edge (along its longer horizontal axis) is a
  zigzag of `teeth=N` points between `low=<fraction>` and the full height (the heights from the hash),
  drawn as an extruded polygon: front and back faces plus one quad per tooth segment. This answers
  the sheet's point 2 (no clean blocks).
- **Interior faces and slab edges at breaks:** palette materials `interior` (the dark room: two flat
  near-black tones by the face's normal, no light ramp), `slab` (a concrete slab's edge: a lit top,
  a dark side) and `hole` (a blown pane: near-black blue-grey). The model places them as
  `damage=<k>` primitives behind what a stage hides (point 3).
- **Rebar and beams:** a shape `rod` from one point to another (`x0 y0 z0 x1 y1 z1`, width in art
  px, optional `bend=<degrees>` that breaks it into two segments), drawn as a stroke of `rebar`
  (rust-dark) or `beam` (steel) in the painter's order at its midpoint's depth, with no outline.
- **Soot and the team fraction:** a move `soot <percent>` chars every hull face of the stage;
  `char` may now take a **team (key) face**, and the generator refuses a char of a key face whose
  result is not wholly outside its faction's key band (so a half-charred face never takes a wrong
  team colour). A test rasterises each stage (the bake's SVG raster, `Image.load_svg_from_string`)
  and checks the key-band share of the intact picture's: SKADET 55-85 %, KRITISK 20-50 %, RUIN
  1-20 % (the sheet's 70 % / 35 % / remnants with room for the art).
- **Panes into dark holes, frames kept:** a move `blow <percent>` on a group turns the `glass`
  primitives of the group to `hole`, the first `percent` of them in the hash order; the frames are
  other primitives and stay.
- **Bent steel:** `turn` (today) on short groups, and `rod` with `bend`; no new move.
- **Tank and sphere "flower" plates:** a helper line `petals <cx> <cy> <z> <diameter> <n>
  <tilt>` that expands, when the model is read, into `n` thin plates (boxes) around the opening, each
  turned outward by `tilt` degrees about its base, plus an `interior` disc in the opening.
- **Rubble:** a helper line `rubble <cx> <cy> <sx> <sy> <n> <material>` that expands into `n` small
  boxes and wedges on the ground inside the rect, sizes and tilts from the hash.
- **Masts that snap and fall one way:** authored (a mast in two groups, the upper one turned about
  the break); no generator feature. The "one direction" is an art rule the review checks.
- **Points and counts** (rule 2: 2-4 damage points `(x, y, z, type)` per building):
  - the damage points' **type** is the emitter kind: `damage` (fire and smoke), `dmg_gas` (a burning
    gas jet, for tanks and spheres) or `dmg_spark` (sparks and thin smoke, no fire: electrics);
  - a building with damage poses has **2 to 4** of them together (today at most 2), each on a break
    that exists from SKADET on (its projected row above `dmg1`'s cut; refused otherwise), because a
    stage-1 fire may pick any of them (§6);
  - a building with a `ruin` has **1 to 3 `ruin` points** on its rubble (the ruin's smoke and
    embers);
  - vehicles keep one `damage` and one `hang`, infantry none; `scar_milli` stays the vehicles'.
- **Refusals kept** (ADR 0028 §3's notes): `dmg1` without `dmg2`; a damage move of an `anim` group
  or of `mount` in `dmg1` or `dmg2`; a stage that changes nothing, a change wholly above the canvas,
  a change that reaches the body's foot. **New:** an odd body canvas height for a building with
  damage parts (the seam invariant of §12 holds only for even heights; all 80 real parts are even).
- **Cut for cost:** no automatic interior (the generator does not invent rooms behind a hidden wall;
  the model places them), no break simulation (a break is authored as groups), no texture or gradient,
  no per-pixel crack pattern. If `petals` turns out costly in review, the plates are authored boxes
  with `turn` moves and the helper is dropped; the art loses nothing but typing.

### 6. Particles per stage (P148, reworked again)
- **Looks** (sprites of `fx/life_atlas.svg`; new frames in §14):

  | Stage | Burning points | Smoke | Fire and light | Other |
  | --- | --- | --- | --- | --- |
  | SKADET | 1 | `smoke`, grey and thin | a small `fire`, a weak `glow` | `dmg_spark` points: sparks |
  | KRITISK | up to 3 | `soot`, black and thick | a large `fire`, a strong `glow` (lit from inside); `dmg_gas`: a `jet` | sparks |
  | RUIN | the `ruin` points | `smoke`, thin and grey, for 8 s | `ember` for 15 s, a faint `glow` | - |

- **Which points burn** (rule 3): `s = LifeClock.pick(id, SALT_BURN, n)` over the building's `n`
  damage points; SKADET burns point `s`, KRITISK points `s, s + 1, ...` (mod `n`) up to
  `damage_burning_points[1]` (3), so the SKADET fire keeps burning at KRITISK and three equal
  buildings do not burn alike. A point that does not burn emits nothing. A vehicle keeps ADR 0028
  §6's looks at its one point.
- **At most 30 smoke puffs per burning building** (rule 8): a data test holds, for each stage,
  `burning points x ceil(life / emit) <= damage_smoke_cap` (30); for example KRITISK `soot` every
  250 ms living 2500 ms at 3 points is 30. The ruin's smoke obeys the same cap at its 1-3 points.
- **One shared glow pass, no blur** (rule 8): a `glow` frame (stepped concentric discs in warm
  orange at low alpha, drawn in the SVG, no filter) is drawn under every fire, in `AirFx`'s one
  `_draw`, as its first pass over all rings, with normal alpha blending. **Rejected:** additive
  blending (a material on its own canvas item: one more draw call) and any blur or shader.
- **Rings** (all in `AirFx`'s one `_draw` from one texture): emitters 80 (P145), **damage 128**
  (ADR 0028's 64: buildings at up to 30 smoke plus fire and glow, and vehicles), muzzle 24 (P149),
  **collapse 64** (§8: flash, fire, dust, debris), **hit 32** (§7). When a ring is full its oldest
  puff goes. P148 makes a ring a small `RefCounted` (`FxRing`, packed arrays), so P165 and P166 add
  their rings with one registration line each in `AirFx.gd`.
- **Who sees it:** a shown building (`BuildingLayer.is_shown`) or a shown ruin (§9) inside the view
  rect grown by a tile, as ADR 0028 §6; a site never burns; a blackout does not stop a fire.

### 7. Hit feedback and the camera shake
- **The flash and the chips** (rule 4): an `IMPACT` whose target id is a building the local player is
  shown (`BuildingLayer.building(id)` and `is_shown`) draws a white `hit_flash` for `hit_flash_ms`
  (60) and `3 + LifeClock.pick(projectile id, SALT_CHIP, 3)` chips (3-5, `chip` frames) that fly
  out from the hit point in short arcs for `hit_chip_ms`. The hit point is the IMPACT's point lifted
  as `EffectsLayer` lifts its impact puff (`SpriteLift`), moved by the hash within the middle half
  of the building's `frame_box` and clamped into it, so the flash is on the picture. Hits on units
  keep today's puff (the sheet is about buildings). A shell that killed (DIED of the same id in the
  tick) gives the collapse's flash instead.
- **Why a flash at the hit point and not the whole building white.** A white silhouette per
  building is a second body picture on the page (about 200 to 358 rows: it does not fit, §11); a
  white tint or a shader on the body splits the batch at every hit building. Question 3 asks.
- **The camera shake** (rule 4: only a collapse may shake the camera): a small view-only shake,
  `collapse_shake_px` (3 base px, divided by the zoom) for `collapse_shake_ms` (300), decaying,
  its direction per step from `LifeClock.mix` (no randomness), on match time (a pause ends it: the
  offset goes to 0).
  - **Which collapses shake:** every collapse the local player sees (§9: an own building, or an
    enemy one shown in its DIED tick) whose footprint centre is inside the visible world rect. Own
    and enemy alike: the kill the player watches is the moment to feel; a shake from off screen
    reads as a fault (the HUD's alerts are for off-screen losses). One shake at a time: a new
    collapse restarts it, never adds to it. A site that dies shakes too; a cancelled site does not.
  - **How:** `CameraShake.gd` (made by `LifeFx`, no scene edit) writes `RtsCamera.offset` only.
    `position`, the clamp, the zoom snap and the gestures never move. `screen_to_world` and
    `world_to_screen` add the offset (one term each), so a tap during a shake hits what is drawn.
  - **None in reduced effects.** It amends the unit-life plan's "no camera shake".

### 8. The collapse at 0 % and the ruin
Every time is match time from the DIED tick (`LifeClock.tick_ms(died_tick)`), so a pause freezes
it and a replay draws the same frames. The numbers are data (§14).

| Time | What | Where it draws |
| --- | --- | --- |
| 0-250 ms | a white flash and the explosion in the middle: today's DIED burst (`EffectsLayer`, unchanged) plus a large `hit_flash` and 2-3 `fire` puffs over the footprint; `Anim` and `Head` hidden | `EffectsLayer`; collapse ring in `AirFx` |
| from 250 ms | the building sinks into itself: `Body` and `Damage` move down and lose their bottom rows in steps, to `collapse_sink_percent` (40) of its rise by 700 ms; a dust cloud rises from the foundation (`dust_cloud` puffs along the footprint diamond); 8-10 `chip` debris fly out | the building's sprites in the sort; collapse ring |
| about 700 ms | the dust is thickest and covers the switch: `Body` is dressed with the `ruin` part (scale, offset, region), `Damage` hidden, the cast shadow removed (the ruin has none) | the sort |
| from 900 ms | the ruin; its `ruin` points smoke for 8 s and glow with embers for 15 s; the dust settles by 1200 ms | the sort; damage ring |
| 45 s | the ruin sinks into the ground over `ruin_fade_ms` (1500) in steps, with two dust puffs, and is gone; the crater under it stays | the sort; collapse ring |

- **The ruin entry.** At DIED, `BuildingLayer._drop` hands a building that was shown to
  `BuildingRuins` (a new helper, so `BuildingLayer.gd` grows by calls) instead of freeing its node:
  the entry leaves `_entries` (no pick, no bar, no selection: ADR 0028's rows), its node stays in the
  sort at the same position and sort key, and it is freed at the ruin's end, as `_drop` frees it
  today. No node is made at DIED. At most `ruin_slots` (16) ruins live; the 17th ends the oldest at
  once (its crater stays).
- **The crater** is laid at DIED exactly as today (`DecalLayer.add_crater`, z 1, under the sort):
  the ruin covers it for 45 s and "fades into" it when it sinks away. No change to the crater code.
- **A building on the ruin's tiles removes it at once** (Michael): when a building row whose
  footprint overlaps a ruin's footprint is shown to the local player (an own site from its first
  tick, an enemy one when it is shown), the ruin goes in that tick, with no fade; its puffs live out.
- **A site that dies** (killed while `build_left > 0`) gets the flash, the explosion and the dust,
  and then the crater; no ruin (it was never built). **A cancelled site** (`DIED` with
  `Production.DIED_CANCEL_FLAG_AT` set) gets no collapse, no ruin, no shake and no crater (the
  view reads no cancel flag today, so a shown cancelled site seems to get a crater now; P165 fixes
  it). The entry remembers whether it was a site at its last tick (ADR 0028 §2 already reads it).
- **The sort:** the ruin stands at the building's sort key, so a unit that drives over the ruin's
  south half is drawn over it and one in its north half behind its rubble, which is right for a low
  heap. Debris outside the footprint (at most a quarter tile, on the ground) may draw over a unit's
  foot north of the footprint: accepted (a few px of flat rubble).
- **No new draw call:** the ruin is a region of the sorted world's page, the particles are quads in
  `AirFx`'s one `_draw`, the burst is `EffectsLayer`'s, the crater is `DecalLayer`'s existing one.
  **Rejected:** a ruin in `DecalLayer` (under the sort: units behind a stub would draw over it, and
  the crater's container after the shadows would draw over the ruin, or a third container costs a
  call); a ruin that fades by `modulate` alpha (splits the batch while it fades; question 4).

### 9. Fog and ghosts
- **Live stages:** ADR 0028 §5 stands (a stage only on a shown row; the remembered stage; ghosts at
  it, dimmed, with no particles).
- **A collapse and a ruin only for a death the player saw:** an own building, or an enemy building
  shown in the tick of its DIED (`entry.shown`, the rule of today's crater). A collapse runs whether
  or not it is on screen; its particles are born only in the view rect grown by a tile.
- **A ruin is drawn by the fog rule of a live building:** an own ruin always; an enemy ruin while any
  cell of its footprint is seen now (`BuildingLayer.any_cell_seen`). Out of sight it is hidden, and
  the crater under it shows under the explored fog as today. Seen again inside its 45 s, it is drawn
  with the time it has left. A ruin's smoke and embers follow the same rule (§6).
- **No ghost of a ruin.** A building that falls in sight leaves no `LastSeen` record (the sim drops
  it), so no ghost stands on its ruin or its crater; `GhostMemoryLayer` needs no change.
- **A building that dies unseen** gets no collapse, no ruin and no crater (today's rule). Its ghost
  stays, at its remembered stage, until the player sees any cell of that spot; then the record is
  dropped and the ground is empty. **Rejected:** a ruin drawn when the empty spot is first seen: the
  view does not know when the building died, so it cannot know whether a ruin would still lie there,
  and it would mark kills of long ago.
- **Removing a ruin** reveals nothing: it happens only when the overlapping new building is shown
  (§8), the moment the player sees what replaced it.
- **A change of the local player** re-applies the fog rule to the ruins; a collapse in flight plays on.

### 10. Reduced effects (amends ADR 0028 §7 and ADR 0027 §8)
- **Kept:** the stage pictures, the ruin and its 45 s, the sink at the end, the fire and its glow on
  the burning points, the damage smoke (ADR 0028 §7), the hit flash (it says "you hit it"), the
  collapse's flash, explosion and dust (the dust hides the switch).
- **Dropped:** sparks, embers, hit chips, collapse debris, the ruin's smoke (ambient after the
  collapse), the camera shake. On the switch the dropped kinds stop being born; live puffs live out.

### 11. Budget
- **Draw calls: none new** (§8). ADR 0027's forecast stays 16 (about 22 in the worst moment).
- **Sprite writes** (counted in `life_writes`, inside `damage_building_writes`, 20 a frame, ADR 0028
  §8): a collapse costs 2 at its start (`Anim`, `Head`), 4 per sink step (`Body` and `Damage`,
  region and offset; `collapse_sink_steps` 6 from 250 to 700 ms), 5 at the switch (scale, offset,
  region, `Damage` hidden, the shadow), 2 per fade step (10 over 1.5 s): about 55 over its life.
  Collapse writes go first in the buildings' share (they are timed), then the queued stage changes.
  A step that does not fit waits a frame and then writes the step of that moment (a coarser sink,
  never a lost one): a strike that kills eight buildings in one tick writes 32 in a step frame, 20
  now and the rest in the next. The worst frame of ADR 0028 §8 is unchanged (the share is the cap).
- **Particles** (no writes): `AirFx` plans at most 80 + 128 + 24 + 64 + 32 = 328 quads (168 under
  ADR 0028). At ADR 0028 §8's estimate of about 1.5 µs a quad on the phone the 160 more cost about
  0.24 ms in the worst moment (four buildings at KRITISK in view during two collapses and a siege),
  so the life layers' worst moment is about 0.7 ms against ADR 0027 §9's 0.56 ms; the average stays
  far under it (a collapse lasts 1.2 s, a ruin smokes 8 s, a puff is born only in view). P162 pins
  the counts; P147's phone card judges the time; the fallbacks are data edits in this order:
  `damage_slots` 96, the KRITISK smoke to 20 per building, `collapse_slots` 48.
- **Fill rate:** thick black smoke is the largest overdraw of the game (about 0.5 M blended px for
  four burning buildings at game zoom); the phone card judges it with the time.
- **Nodes:** none per frame and none at DIED; a ruin keeps the dying building's node for up to
  46.5 s, at most 16 at once.
- **The page** (cross-faction two-player match at bake scale 1.0, budget 3584; P158 measured 3476
  with `dmg1` and `dmg2` at 75 %, 210 rows over the 3266 baseline). The ruin's size is estimated
  from P158's sheets (573f720): P158's `dmg2` picture from its ink top down to the canvas foot, plus
  8 rows and 32 columns of debris, is 1.03 M art px² for the 16 buildings against the two patches'
  1.27 M (0.81); a truly low ruin, without the stubs that carried an anim element or a mount, about
  0.6. Scaled by the measured 210 rows, a ruin costs 129 to 171 rows at 75 %. The new `dmg1` and
  `dmg2` are taken at P158's measured cost (their depth rules are the same); the packing may cost
  5-10 % more as the page fills.

  | Layout | Rows over 3266 | Cross page | Fits 3584? |
  | --- | --- | --- | --- |
  | P158 as measured: `dmg1` + `dmg2` at 75 % | 210 | 3476 | yes, 108 left |
  | + `ruin` at full scale, cropped to ink | 439-514 | 3705-3780 | no |
  | + `ruin` at 75 % (`DAMAGE_SCALE`) | 339-381 | 3605-3647 | no, 21-63 over |
  | + `ruin` at 75 %, SKADET at most 35 % of the body | about 314-356 | 3580-3622 | at the edge |
  | + `ruin` at 50 % | 267-286 | 3533-3552 | yes, 32-51 left |
  | all three damage parts at 62.5 % | 236-265 | 3502-3531 | yes, 53-82 left |
  | a `ruin` without team colour, shared by all owners | as its row above | - | no saving on this page |

  Mirror pages stay under the budget in every layout (Lumen about 3150-3195 with the ruin at 75 %).
  At 3584 rows the page's GPU memory is about 58.7 MB, inside ADR 0023 §2's 64 MB.
- **Why the shared ruin is no fallback:** on the cross-faction page each faction's buildings are
  baked for its one player only, so a ruin without key colours still takes one slot per type; it
  would save only on mirror pages, which have about 400 rows free. It also drops the "remnants" of
  team colour Michael's table keeps. So it is not on the list.
- **What is decided and in what order** (the measured page after P158a and P158b decides):
  1. the ruin cropped to its ink (P163, always);
  2. the ruin baked at `DAMAGE_SCALE` (P157c: `ruin` joins `IsoAtlas.DAMAGE_PARTS`, always);
  3. SKADET at most 35 % of the body's rows (a lead decision: it is still "small nicks", the sheet's
     SKADET);
  4. still over: **Michael chooses** (question 2): the ruin alone at 50 % (recommended), or all three
     damage parts at 62.5 %.
  Never a second page (a draw call and about 16 MB more), and never the 512 rows above 3584 that
  ADR 0027 §4 keeps for later types. P153 and P154 of the unit-life plan will not fit beside this
  (their rows already land only if the page has room).

### 12. The seam of the trimmed body and its patch (replaces ADR 0028 §3's second amendment's open point)
ADR 0028 §3's second amendment asked for "at least 1 texel" of overlap and named "the `floor` of the
patch's cut" as a way; P157b's review found that both are wrong (the raster rounds each axis, so a
texel count from `bake_scale` alone is not the region's), and the rule is the one in the
`DAMAGE_SCALE` doc block of `game/view/IsoAtlas.gd` (P157b, 9a3b8b3). It replaces the open point and
the P26ar note's `ceil(cut x bake_scale)`:
- the patch (`Damage`) is a **sibling** of the body, with the same parent and the same position;
- the body is trimmed by **T = `IsoAtlas.body_cut_row(cut, canvas_h, region_h)`** texels, the
  integer ceil of `cut x region_h / canvas_h` (`region.position.y += T`, `region.size.y -= T`,
  `offset.y += T`), with **`region_filter_clip_enabled = true`** on the trimmed body;
- the patch uses its **whole region**, through `WorldSort.dress`;
- the overlap is **strictly greater than 0** at every bake scale for even canvases, which all real
  parts are (an odd one at 0.25 gives exactly 0: canvas 101, cut 97); in world px,
  `(patch.offset.y + patch region.size.y) x patch.scale.y > body.offset.y x body.scale.y`;
- under a **ghost body** (`BuildingAnims.dress_ghost`) the patch is a child with
  `scale = body_texels / patch_texels` (and `offset = -origin x patch_texels`), as the ghost's
  `Anim` is;
- **`show_frame` and `show_base` rewrite `region_rect`**, so the trim is applied again after each.
- The generator refuses odd body canvas heights for buildings with damage parts (§5). The ruin has
  no seam (a whole sprite).

### 13. Repair (rule 7; none in the game)
There is no repair, healing or regeneration (ADR 0028 §2). For a future repair ADR: **repair runs
backwards: fire and smoke go out first, then the sprite steps back one stage.** When hp rises past a
threshold by its band (ADR 0028 §2's foreseen band, a number beside `building_stage_percent`), the
burning points of the stage left stop being born at once (puffs live out), and the picture steps
back `repair_step_ms` later. A ruin never repairs: the row is gone.

### 14. Numbers in data and new sprites
- `data/life_settings.tres` (`LifeSettings`, view only): `building_stage_percent` ([67, 34]) and
  `vehicle_stage_percent` ([50, 25]) instead of `damage_stage_percent`; `damage_burning_points`
  ([1, 3]); `damage_smoke_cap` (30); the per-stage `damage_emit_ms` and `damage_life_ms` (P148's,
  now per stage: `smoke` SKADET, `soot` KRITISK, `fire`, `glow`, `jet`, `spark`, ruin `smoke` and
  `ember`); `ruin_smoke_ms` (8000), `ruin_ember_ms` (15000); `damage_slots` (128); `hit_flash_ms`
  (60), `hit_chip_ms`, `hit_slots` (32); the collapse's `collapse_flash_ms` (250),
  `collapse_sink_ms` (250 to 700), `collapse_sink_steps` (6), `collapse_sink_percent` (40),
  `collapse_switch_ms` (700), `ruin_from_ms` (900), `collapse_dust_ms` (250 to 1200),
  `collapse_slots` (64), `ruin_life_ms` (45000), `ruin_fade_ms` (1500), `ruin_slots` (16);
  `collapse_shake_px` (3.0), `collapse_shake_ms` (300). Data tests hold the order of the times
  (flash end = sink start, sink end = switch, switch < ruin start < dust end < ruin life) and the
  smoke cap.
- `IsoAtlas.DAMAGE_SCALE` stays a view constant (not balance); the ruin's factor (question 2) is
  one too.
- **New frames in `fx/life_atlas.svg`** (hand-drawn in this repo, STYLE.md's fx rules, no filter):
  `hit_flash` (white, 2), `chip` (3: concrete grey, dark steel, a pale shard), `dust_cloud` (2, large,
  stepped alpha), `ember` (2), `glow` (1, stepped discs), `jet` (2, a sideways gas flame,
  yellow-white). `smoke`, `soot`, `fire` and `spark` exist.

## Consequences
- A building's damage reads in its shape at phone zoom: nicks and blown panes, then a collapsed part
  with its inside showing and fire inside, then a low dark ruin that smokes and glows; a kill is a
  flash, a sinking building, a dust cloud and a short shake.
- Still view and art only: no sim change, no golden hash, no new draw call.
- The generator grows by a pose, two shapes, two helpers, two moves, four materials and new counts;
  sixteen buildings get a third picture and their poses are redone (P158's are the starting point).
- The page is near its budget: a fourth picture per building, a second faction's ruins of a later
  type, or P153 and P154 have no room without one of §11's steps.
- `AirFx` holds five rings (328 quads); the worst moment of the life layers passes ADR 0027 §9's
  0.56 ms by estimate (about 0.7 ms); the phone card decides and the fallbacks are data.
- `RtsCamera` gains an offset term in two functions; the camera still moves only by the player's
  hand except for a collapse's 300 ms shake.
- Amends (dated notes by the lead's P26at on acceptance): ADR 0028 (§2 lists, §3 stage meanings and
  the seam, §6, §7, §8, §9), ADR 0027 §8 (reduced) and the unit-life plan's out-of-scope line
  (camera shake), ADR 0023 §5 (the part `ruin`).

## Alternatives considered
- **A ruin in the sim** (blocking 45 s): Michael's "Kun grafik"; rejected (§1).
- **The ruin as a fourth patch over the body:** nothing of the intact body may remain and debris
  lies outside its canvas; rejected for a whole sprite (§3).
- **A new `Ruin` node per death:** a node at DIED; rejected for keeping the dying building's node.
- **A ruin in `DecalLayer`:** wrong occlusion and a third container; rejected (§8).
- **A whole-building white flash:** a page picture per building or a batch split per hit; rejected
  for a flash at the hit point (question 3).
- **A fade by alpha:** a batch split per fading ruin; rejected for the sink (question 4).
- **Additive glow:** a material, one more draw call; rejected for one alpha glow pass (§6).
- **Shake on every own loss or on every collapse anywhere:** a shake from off screen reads as a
  fault; rejected for "seen and on screen" (§7).
- **A second atlas page or the reserve rows:** rejected (§11).
- **A shared neutral ruin:** saves nothing on the cross page; not a fallback (§11).

## Questions for Michael
1. **Vehicles' thresholds.** Your sheet is about buildings. Recommended: **vehicles keep 50 % and
   25 %** (ADR 0028), buildings get 66 % and 33 %; a tank with soot after one hit at 66 % would make
   most of an army look worn after its first fight, and vehicles have no ruin. Alternative: vehicles
   switch at 66 % and 33 % too (a data edit).
2. **If the page is still too full** after the ruin is cropped, baked at 75 % and SKADET is kept to
   the top third. Recommended: **A, the ruin alone at 50 %** (it is low, dark rubble under smoke;
   the patches keep the 75 % you chose; it frees about 70-95 rows). B: all three damage pictures at
   62.5 % (a little softer damage everywhere). Not offered: a second texture page (draw calls and
   memory on the phone).
3. **The 60 ms white hit flash.** Recommended: **a white flash at the hit point on the building**,
   plus the 3-5 chips. A whole building turning white for 60 ms would cost a white copy of every
   building on the page (it does not fit) or a tint that breaks the one-draw-call world at every
   hit.
4. **How the ruin "fades" to the soot mark after 45 s.** Recommended: **it sinks into the ground
   over 1.5 s with a little dust** (free). A true see-through fade costs one to three extra draw
   calls per fading ruin for those 1.5 s.
