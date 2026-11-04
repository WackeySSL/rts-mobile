# ADR 0029: Buildings shot to pieces: four stages, collapse, ruin and hit feedback (view and art only)

**In short, for Michael:** a building now shows four pictures as it is shot (whole, damaged,
critical, ruin) and changes its shape at each, with smoke and fire on top as particles. When it
dies it flashes, sinks into a dust cloud and leaves a low ruin for 45 seconds that blocks nothing.
Hits flash and throw chips, a collapse you watch shakes the view a little; four questions at the end.

Status: proposed 2026-11-03 (P26as, architect). Written on `main` at 4b5c26d (#297, P26ar,
merged); revised 2026-11-04 after the docs lens (on `main` at 321092e, P157 #299 merged). The
decisions taken from Michael's two reference sheets of 2026-11-03 and from his answer "Kun grafik"
are his and are not open; the questions at the end are. Plan:
`docs/plans/2026-11-03-damage-states.md`, section "ADR 0029 rework" (rows P163-P167, P157c, P158a,
P158b, the re-scoped P159, P148 and P162). On acceptance the lead's P26at writes the dated notes:
ADR 0028 (a status note at the top pointing here, and §3's third amendment: the `Anim` at stage 2
now follows its carrier, §3 here), ADR 0027 §3 (the quota table: damage 24 → 80, the new collapse
ring 40 and hit ring 16), ADR 0027 §8 (what `reduced` keeps), the unit-life plan's "camera shake"
out-of-scope line, ADR 0023 §5 (the part name `ruin`).

It amends ADR 0028: §2 (the thresholds, one list per kind), §3 (what `dmg1` and `dmg2` show, the
`Anim` at stage 2, and the second amendment's open point on the seam, §12 here), §6 (the
particles), §7 (reduced effects), §8 (the budget) and §9 (the data). Everything else in ADR 0028
stands: view and art only, stages as a pure function of hp, the trimmed body with a `Damage`
sibling, `DAMAGE_SCALE`, the vehicle overlays, the remembered stage and the ghosts. No rule, state
column, Command, event or golden hash changes; no file in `game/sim` or `native/` changes.

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
  ids. The sheets' own example buildings and factions are reference only and their names do not go
  into the repo (nor do the images); where a sheet names one of our own buildings (Wind Park,
  `renew_power`; Motor Works, `renew_factory`, STYLE.md), that is our name and is used as such.
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
  primitives, the geometric cut, patches cropped to ink, `cuts`, the count rules) and P157 (the
  neutral sheet, #299, 321092e) are on `main`. P157b (`DAMAGE_SCALE` 0.75) is PR #300 at 1c2a031.
  P158 (`dmg1`/`dmg2` for all 16 buildings, two `damage` points on each of the 14 non-defences and
  one on each defence, the gallery's Stage button; branch `claude/p158-building-damage` at 573f720)
  is on hold because this spec changes its target; it measured the cross-faction page at 3566 with
  both patches at full scale and at 3476 / 2875 / 3023 (cross / mirror Derrick / mirror Lumen) of
  3584 with both at 75 %, so 300 rows over the 3266 baseline became 210. The view on `main`:
  `EffectsLayer._add_death` (a DIED burst), the `DecalLayer` crater (`decals/crater.svg`) that
  `BuildingLayer._drop` lays for a building that falls in sight, and `AirFx` with its one ring,
  the emitters' 80 (P145); the damage ring (64, P148, ADR 0028) and the muzzle ring (24, P149) are
  still to come; P152's wrecks (a husk for 20 s) are a later row. `RtsCamera` has no shake; the
  unit-life plan puts camera shake out of scope ("the camera moves only by the player's hand").
  There is no repair.
- **Hits in the events** (`Combat.gd`): a shell writes `[IMPACT, projectile id, x, y, target id,
  weapon, 0, 0]` when it lands; a hitscan weapon (speed 0, the `rifle`) writes only `[SHOT, shooter
  id, sx, sy, target id, weapon, tx, ty]`, its damage landing in the shot's tick, and so does a
  shell fired while the projectile pool is full (`projectile_overflow`, which ADR 0007 §3 pins at 0).
  The snapshot carries `weapon_projectile_speed`, which `EffectsLayer._add_shot` already reads.
- **Batching** (ADR 0023 §2, ADR 0028's Context): a per-sprite tint, a material or another texture
  inside the sort splits the one `WorldSort` batch; regions, offsets, positions, scales and flips are
  free.

## Decisions in short
Words used below: the **body** is a building's intact picture (`hull`); a **patch** is a picture of
a damaged top that is drawn over the body, whose rows above a cut line are trimmed away; the
**page** is the one atlas texture every sorted sprite of a match comes from (its height is the
budget, 3584 rows); a **ring** is a fixed number of particle slots in `AirFx` whose oldest puff
goes when it is full; a faction's **key band** is the range of colours the bake replaces with the
owner's team colour.
1. **View and art only** (Michael, "Kun grafik"): the ruin is a view entry, like a wreck.
2. **Four stages:** INTAKT, SKADET, KRITISK, RUIN. Buildings switch at 67 and 34 (strict "under"):
   67-100 % intact, 34-66 % SKADET, 1-33 % KRITISK; RUIN after DIED. One list per kind in data.
3. **Pictures:** `dmg1` = SKADET and `dmg2` = KRITISK stay patches over the trimmed body; RUIN is a
   **whole low sprite**, part `ruin`, shown on the dying building's own `Body` sprite. At KRITISK the
   `Anim` follows its carrier (per sheet); in the ruin it is gone.
4. **Art language** per stage from the sheet's table, the five material rules, a rule per building.
5. **Generator v5:** a `ruin` pose, broken (jagged) edges, rods for rebar and beams, interior and
   hole materials, `blow` and `soot` moves, rubble and petal helpers, key faces that may char out of
   the band, 2-4 `damage` points with ink under them at every stage, 1-3 `ruin` points, ambient
   emitters that go quiet when their group breaks.
6. **Particles per stage** in `AirFx`: a fixed-seed choice of the burning points, at most 30 smoke
   puffs per burning building (15 by default), one shared glow pass, no blur; 240 quads in all.
7. **Hit feedback:** a white flash of 60 ms at the hit point and 3-5 chips, from IMPACT and from the
   SHOT of a hitscan weapon. **Only a collapse shakes the camera** (question 4).
8. **Collapse** from DIED: flash and explosion 0-250 ms, sink and dust 250-900 ms, the switch to the
   ruin under the dust at 700, the ruin from 900; it lies 45 s, then sinks into the crater.
9. **Fog:** a collapse and a ruin only for a death the player saw; a ruin is drawn by the fog rule of
   a live building; no ghost of a ruin; nothing is invented for a death not seen.
10. **Reduced effects** keep every picture, the ruin, the fire, the flash and the dust; they drop
    sparks, embers, chips, debris, the ruin's smoke and the shake.
11. **Budget:** no new draw call; collapse writes inside the buildings' write share; the life
    layers' worst moment stays inside ADR 0027 §9's 0.56 ms; the page stays at most 3584 (§11).
12. **The seam rule** of the trimmed body and its patch is the one in `IsoAtlas`'s `DAMAGE_SCALE`
    block (P157b), not ADR 0028's "at least 1 texel".
13. **Repair:** none in the game; recorded for a future repair ADR.

## Decision

### 1. View and art only
- Every part of this ADR reads the published snapshot and its events (`SHOT`, `IMPACT`, `DIED`) in
  the layers' `ticked` and frame paths, and the match time (`LifeClock`). Nothing is added to the
  sim: the ruin is not a row, not an obstacle and not a placement rule.
- **The ruin is a view entry**, kept by `BuildingLayer` after the building's row is gone, like
  P152's wrecks will be kept by `GroundFx`. **Rejected:** a ruin in the sim (a blocked footprint for
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
| SKADET | `dmg1` | a patch over the trimmed body (ADR 0028 §3) | `Damage` sibling of `Body` |
| KRITISK | `dmg2` | a patch over the trimmed body; the `Anim` follows its carrier (below) | `Damage` sibling of `Body` |
| RUIN | `ruin` | a **whole low sprite** of the rubble, the foot and the debris outside the footprint | on the `Body` sprite, re-dressed (§8) |

- **Why the ruin is a whole sprite and not a patch.** A patch shows the change above a cut over the
  intact body's rows below it. After DIED nothing of the intact body may remain: the walls are
  stubs, soot lies over everything and debris lies outside the footprint, below and beside the
  body's canvas. A patch whose cut is the foot is a whole sprite anyway, and its canvas has to be
  wider than the body's for the debris. So the ruin has its own canvas, cropped to its ink, and no
  cut. It is the third damage part on the sheet (`parts` gains `ruin`; its size and anchor like any
  part; `cuts` keeps its two entries for `dmg1` and `dmg2`).
- **The `Anim` at KRITISK follows its carrier** (a lead decision, 2026-11-04; it replaces ADR 0028
  §3's third amendment for stage 2). Michael's "Ja, styrt dem" hid the `Anim` at the old stage 2,
  which was a low ruin; that ruin is now RUIN, where the `Anim` is gone anyway. At KRITISK a part has
  collapsed but most of the building stands, so the moving element runs where its carrier still
  stands in the KRITISK pose and is hidden where its carrier fell. It is per sheet: the model says
  `anim_kritisk run` or `anim_kritisk hide`, and the generator writes it to the sheet
  (`IsoSheetDef.anim_kritisk`, a bool) and refuses `run` when the `anim` part's lowest point has no
  ink under it in `dmg2` (§5's ink check). SKADET: the `Anim` runs, at its rate (ADR 0028 stands).
  The write costs stay those of ADR 0028 §8 (one visibility write when it is hidden).
- **The `Anim` and a defence's `Head` are not in the ruin:** the ruin pose draws no `anim`
  primitive, and the view hides `Anim` and `Head` at the collapse's start (§8), behind the flash.
  ("The turret is lifted off" and "the gun is lifted off" are the defences' ruins: an empty ring.)
  At SKADET and KRITISK a defence's `Head` stays (defences still aim and shoot).
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
  - **The two defences get a second `damage` point** (`defence_turret` and `renew_defence` have one
    each at 573f720; §5 now asks for 2-4).
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
  - **Tanks and spheres:** a hole with a burning gas jet (SKADET), then torn open like a flower of
    plates and burning (KRITISK), then a sooted shell or a heap of plates (RUIN).
  - **Masts and towers** snap in one place and fall in one direction; the top lies beside the stump.
  - Brick (two of our buildings) follows the concrete rule without rebar: it breaks along its
    courses into red-brown lumps.
- **Per building** (the sheet's table for our 16 ids, in our words, with the rules of its two
  example panels that apply to our ids):

  | Fossil id | Rule | Renew id | Rule |
  | --- | --- | --- | --- |
  | `barracks` | concrete, the full concrete rule: the facade breaks along the panel joints and floor slabs, rebar at every break, and the team paint burns off from the top down | `renew_barracks` | the white cladding is sooted, the glass wing shatters |
  | `headquarters` | concrete; the chimney snaps and topples | `renew_hq` | glass and concrete; the floors fall in steps |
  | `power_plant` | brick; the boilers burn | `renew_power` | blades and towers, the mast rule (the sheet's own Wind Park example) |
  | `refinery` | gas spheres, the tank-and-sphere rule; thin pipes and the flare bend and never shatter; the gas leaves the largest soot mark on the ground (§8) | `renew_refinery` | the tanks crack and fall together |
  | `vehicle_factory` | brick and steel trusses; the roof falls in | `renew_factory` | a glass roof, the glass rule (the sheet's own Motor Works example) |
  | `fossil_radar` | the steel lattice bends and topples | `renew_radar` | the dome is punctured, the mast snaps |
  | `defence_turret` | concrete; the turret is lifted off | `renew_defence` | concrete; the gun is lifted off |
  | `fossil_strike` | a steel portal; the ruin is a twisted skeleton | `renew_strike` | the pillars snap, the ring beam falls |

- **Team colour per stage** is the share of the intact picture's key-colour pixels that is still key
  colour: SKADET about 70 %, KRITISK about 35 %, RUIN remnants (a few shards and a panel). The art
  gets there by hiding, turning and charring team faces (§5); a test measures it (§5). For the
  barracks the charred team faces are the top ones first.
- **Depth on the body** (the page, §11): SKADET's changes reach at most half the body's rows from
  its top (ADR 0028 §3's amendment for stage 1; §11's step 3 may tighten it to 35 %); KRITISK may
  reach down to just above the foot (the generator still refuses a change that reaches the foot);
  the ruin rises at most half the body's canvas height.
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
- **Bent steel:** `turn` (today) on short groups, and `rod` with `bend`; no new move. Thin pipes and
  a flare (the refinery) are bent this way, never hidden in pieces.
- **Tank and sphere "flower" plates:** a helper line `petals <cx> <cy> <z> <diameter> <n>
  <tilt>` that expands, when the model is read, into `n` thin plates (boxes) around the opening, each
  turned outward by `tilt` degrees about its base, plus an `interior` disc in the opening.
- **Rubble:** a helper line `rubble <cx> <cy> <sx> <sy> <n> <material>` that expands into `n` small
  boxes and wedges on the ground inside the rect, sizes and tilts from the hash.
- **Masts that snap and fall one way:** authored (a mast in two groups, the upper one turned about
  the break); no generator feature. The "one direction" is an art rule the review checks.
- **Points and counts** (rule 2: 2-4 damage points `(x, y, z, type)` per building):
  - the damage points' **type** is the emitter kind: `damage` (fire and smoke), `dmg_gas` (a gas
    jet at SKADET, a fire from the torn opening at KRITISK: tanks and spheres) or `dmg_spark`
    (sparks and thin smoke, no fire: electrics);
  - a building with damage poses has **2 to 4** of them together (today at most 2);
  - **ink under every point at every stage that uses it** (a lead decision, 2026-11-04): the points
    are one list per building (not per stage), any of them can burn at SKADET and up to three at
    KRITISK (§6), so the generator refuses a point whose projected spot is not inside the outline of
    a primitive that `dmg1` draws, or not inside one that `dmg2` draws (a geometric test, no
    raster), and a point whose projected row is below `dmg1`'s cut (it must sit on a SKADET break);
  - a building with a `ruin` has **1 to 3 `ruin` points**, each with ink under it in the ruin (the
    same test);
  - vehicles keep one `damage` and one `hang`, infantry none; `scar_milli` stays the vehicles'.
- **Ambient emitters that break** (a lead decision, 2026-11-04): an emitter line (`smoke`, `steam`,
  `flame`) may name its group (`group=<name>`); the generator writes per emitter the first stage
  whose pose moves or hides that group (`IsoSheetDef.emitter_quiet`, parallel to `emitters`; 0 for
  never, 1 or 2), and `AirFx` stops that emitter from that stage on (P148). The headquarters'
  chimney, the refinery's flare, the power plant's stacks and the renew refinery's tanks are the
  known cases; an emitter whose spot has no ink at a stage it would still emit at is refused (the
  same ink test).
- **Refusals kept** (ADR 0028 §3's notes): `dmg1` without `dmg2`; a damage move of an `anim` group
  or of `mount` in `dmg1` or `dmg2`; a stage that changes nothing, a change wholly above the canvas,
  a change that reaches the body's foot. **New:** an odd body canvas height for a building with
  damage parts (the seam invariant of §12 holds only for even heights; all 80 real parts are even);
  `anim_kritisk run` with no ink under the `anim` part in `dmg2` (§3).
- **Cut for cost:** no automatic interior (the generator does not invent rooms behind a hidden wall;
  the model places them), no break simulation (a break is authored as groups), no texture or gradient,
  no per-pixel crack pattern. If `petals` turns out costly in review, the plates are authored boxes
  with `turn` moves and the helper is dropped; the art loses nothing but typing.

### 6. Particles per stage (P148, reworked again)
- **Looks** (sprites of `fx/life_atlas.svg`; new frames in §14):

  | Stage | Burning points | Smoke | Fire and light by point type | Other |
  | --- | --- | --- | --- | --- |
  | SKADET | 1 | `smoke`, grey and thin | `damage`: a small `fire` and a weak `glow`; `dmg_gas`: a `jet` (the burning gas jet from the hole) and a weak `glow`; `dmg_spark`: sparks, no fire | - |
  | KRITISK | up to 3 | `soot`, black and thick | `damage` and `dmg_gas`: a large `fire` and a strong `glow` (lit from inside; for a sphere, from its torn-open flower); `dmg_spark`: sparks, no fire | sparks at every burning point |
  | RUIN | the `ruin` points | `smoke`, thin and grey, for 8 s | `ember` for 15 s, a faint `glow` | - |

- **Which points burn** (rule 3): `s = LifeClock.pick(id, SALT_BURN, n)` over the building's `n`
  damage points; SKADET burns point `s`, KRITISK points `s, s + 1, ...` (mod `n`) up to
  `damage_burning_points[1]` (3), so the SKADET fire keeps burning at KRITISK and three equal
  buildings do not burn alike. A point that does not burn emits nothing. A vehicle keeps ADR 0028
  §6's looks at its one point.
- **At most 30 smoke puffs per burning building** (rule 8), and **15 by default**: a data test
  holds, for each stage, `burning points x ceil(life / emit) <= damage_smoke_cap` (30). The default
  numbers are lower so that the rings fit the frame budget (§11): KRITISK `soot` every 400 ms living
  2000 ms is 5 a point, 15 at 3 points; SKADET `smoke` every 500 ms living 2000 ms is 4; the ruin's
  `smoke` every 700 ms living 2000 ms is 3 a point, 9 at 3 points.
- **One shared glow pass, no blur** (rule 8): a `glow` frame (stepped concentric discs in warm
  yellow at low alpha, hue at least 46° and outside both key bands, drawn in the SVG, no filter) is
  drawn under every fire, in `AirFx`'s one `_draw`, as its first pass over all rings, with normal
  alpha blending. **Rejected:** additive blending (a material on its own canvas item: one more draw
  call) and any blur or shader.
- **Ambient emitters** (P145's `smoke`, `steam`, `flame`) go quiet from the stage the sheet's
  `emitter_quiet` names (§5); the others keep puffing at every stage, as ADR 0027 has them.
- **Rings** (all in `AirFx`'s one `_draw` from one texture; sized for §11's frame budget):
  emitters 80 (P145, on `main`), **damage 80** (P148; ADR 0028 planned 64: two or three buildings
  at KRITISK in view at 24 quads each, 15 smoke, 6 fire and 3 glow, 30 with their sparks, plus
  vehicles; beyond that the oldest, most faded smoke goes), muzzle 24 (P149),
  **collapse 40** (§8), **hit 16** (§7): **240 quads in all**. When a ring is full its oldest puff
  goes. P148 makes a ring a small `RefCounted` (`FxRing`, packed arrays), so P165 and P166 add their
  rings with one registration line each in `AirFx.gd`.
- **Who sees it:** a shown building (`BuildingLayer.is_shown`) or a shown ruin (§9) inside the view
  rect grown by a tile, as ADR 0028 §6; a site never burns; a blackout does not stop a fire.

### 7. Hit feedback and the camera shake
- **The flash and the chips** (rule 4): a hit on a building the local player is shown draws a white
  `hit_flash` for `hit_flash_ms` (60) and `hit_chips[0] + LifeClock.pick(hit id, SALT_CHIP,
  hit_chips[1] - hit_chips[0] + 1)` chips (3 to 5, `chip` frames) that fly out from the hit point in
  short arcs for `hit_chip_ms` (350). A hit is:
  - an `IMPACT` with a target id (a shell that landed; the hit id is the projectile id);
  - a `SHOT` of a hitscan weapon (`weapon_projectile_speed` of its weapon 0, the `rifle`): the
    target id at +4, the hit point at +6/+7 (the target's position at the shot); the hit id is the
    shooter id plus the tick (`LifeClock.mix`).
  - **The gap, stated:** a shell fired while the projectile pool is full also hits at once and writes
    only its SHOT; the view cannot tell it from a launch, so it gets no hit feedback. ADR 0007 §3
    pins `projectile_overflow` at 0 in the performance test, so it does not happen in a normal match.
- **Finding the building:** the events give an id, `is_shown` and `frame_box` take a row; P166 adds
  `BuildingLayer.row_of(id)` (the entry's row from `_entries` after `_sync()`, -1 when the building is
  gone), so the check is one dictionary read per hit.
- **The hit point** is the event's point lifted as `EffectsLayer` lifts its impact puff
  (`SpriteLift`), moved by the hash inside the middle `hit_flash_box_milli` (500, the middle half)
  of the building's `frame_box` and clamped into it, so the flash is on the picture. Hits on units
  keep today's puff (the sheet is about buildings). A hit that killed (DIED of the same id in the
  tick) gives the collapse's flash instead (§8).
- **A deviation from the sheet, stated** (a lead decision, 2026-11-04): the sheet asks for a white
  flash on the hit building; we draw it **at the hit point**, not as the whole building turning
  white. A whole white building needs a white copy of every body on the page (about 200 to 358
  rows: it does not fit, §11) or a tint or shader on the body, which splits the one-draw-call world
  at every hit building.
- **The camera shake** (rule 4: only a collapse may shake the camera; question 4 asks whether to
  have it): a small view-only shake, `collapse_shake_px` (3 base px, divided by the zoom) for
  `collapse_shake_ms` (300), decaying, its direction per step from `LifeClock.mix` (no randomness),
  on match time (a pause ends it: the offset goes to 0).
  - **Which collapses shake** (the recommendation of question 4): every collapse the local player
    sees (§9: an own building, or an enemy one shown in its DIED tick) whose footprint centre is
    inside the visible world rect. Own and enemy alike: the kill the player watches is the moment
    to feel; a shake from off screen reads as a fault (the HUD's alerts are for off-screen losses).
    One shake at a time: a new collapse restarts it, never adds to it. A site that dies shakes too;
    a cancelled site does not.
  - **How:** `CameraShake.gd` (made by `LifeFx`, no scene edit) writes `RtsCamera.offset` only.
    `position`, the clamp, the zoom snap and the gestures never move. `screen_to_world` and
    `world_to_screen` add the offset (one term each), so a tap during a shake hits what is drawn.
    It takes "a collapse started" from `BuildingRuins` (P165), so it agrees with §8 and §9.
  - **None in reduced effects.** It amends the unit-life plan's "no camera shake".

### 8. The collapse at 0 % and the ruin
Every time is match time from the DIED tick (`LifeClock.tick_ms(died_tick)`), so a pause freezes
it and a replay draws the same frames. The numbers are data (§14). The times follow the sheet's
rule 5 ("explosion 0-250 ms, dust cloud 250-900 ms, ruin from 900 ms"); its collapse panel's
"1.2 s → 45 s" is an illustration, and the rules written for us win where they differ.

| Time | What | Where it draws |
| --- | --- | --- |
| 0-250 ms | a white flash and the explosion in the middle: today's DIED burst (`EffectsLayer`, unchanged) plus a large `hit_flash` and `collapse_fire_puffs` (2-3) `fire` puffs over the footprint; `Anim` and `Head` hidden | `EffectsLayer`; collapse ring in `AirFx` |
| 250-700 ms | the building sinks into itself: `Body` and `Damage` move down and lose their bottom rows in `collapse_sink_steps` (6) steps, to `collapse_sink_percent` (40) of its rise; `collapse_dust_puffs` (8) `dust_cloud` puffs rise from the foundation along the footprint diamond; `collapse_debris` (6-8) `chip` debris fly out | the building's sprites in the sort; collapse ring |
| 700 ms | the dust is thickest and covers the switch: `Body` is dressed with the `ruin` part (scale, offset, region), `Damage` hidden, the cast shadow removed (the ruin has none) | the sort |
| 700-900 ms | the dust thins and is gone at 900 ms (every dust puff lives inside 250-900 ms) | collapse ring |
| from 900 ms | the ruin; its `ruin` points smoke for 8 s and glow with embers for 15 s | the sort; damage ring |
| 45 s | the ruin sinks into the ground in `ruin_fade_steps` (10) over `ruin_fade_ms` (1500), with `ruin_fade_dust_puffs` (2) dust puffs, and is gone; the crater under it stays | the sort; collapse ring |

- **The ruin entry.** At DIED, `BuildingLayer._drop` hands a building that was shown to
  `BuildingRuins` (a new helper, so `BuildingLayer.gd` grows by calls) instead of freeing its node:
  the entry leaves `_entries` (no pick, no bar, no selection: ADR 0028's rows), its node stays in the
  sort at the same position and sort key, and it is freed at the ruin's end, as `_drop` frees it
  today. No node is made at DIED. At most `ruin_slots` (16) ruins live; the 17th ends the oldest at
  once (its crater stays).
- **Many collapses at once** (a strike): the collapse ring has 40 slots and one collapse wants at
  most 20 (1 flash, 3 fire, 8 dust, 8 debris). When `n` collapses start in one tick, each gets at
  most `collapse_slots / n` puffs, dust first (it covers the switch), then fire, then debris; so
  every building keeps some cover, and eight at once get five puffs each, all dust.
- **The crater** is laid at DIED as today (`DecalLayer.add_crater`, z 1, under the sort): the ruin
  covers it for 45 s and "fades into" it when it sinks away. Its size is the footprint's crater
  (`CRATER_MILLI_PER_TILE`) times `crater_scale_milli` of the building's type id (default 1000;
  `refinery` 1500: the gas leaves the largest soot mark, the sheet's rule), so the crater code gains
  one multiplication.
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
  call); a ruin that fades by `modulate` alpha (splits the batch while it fades; question 3).

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
  region and offset; 6 steps from 250 to 700 ms), 5 at the switch (scale, offset, region, `Damage`
  hidden, the shadow), 2 per fade step (10 steps over 1.5 s): **51** over its life. Collapse writes
  go first in the buildings' share (they are timed), then the queued stage changes. A step that does
  not fit waits a frame and then writes the step of that moment (a coarser sink, never a lost one): a
  strike that kills eight buildings in one tick writes 32 in a step frame, 20 now and the rest in
  the next. The worst frame of ADR 0028 §8 is unchanged (the share is the cap).
- **Frame time** (ADR 0027 §9: at most 0.56 ms of life work per frame on the phone). The estimate:
  - the rest of the life layers about 0.3 ms (ADR 0028 §8's figure; taken here to include P145's
    80 emitter quads and P149's 24 muzzle quads), ADR 0028's stage checks about 0.05 ms;
  - a quad about 1.5 µs. **Derived here, not measured:** ADR 0028 §8 gives "at most 0.15 ms" for
    its whole worst moment (64 damage quads plus the stage checks); about two thirds of it for the
    quads is about 1.5 µs a quad. P147's phone card measures the real figure;
  - so 0.56 - 0.3 - 0.05 = 0.21 ms is left for the damage, collapse and hit rings, about 136 quads:
    **damage 80, collapse 40, hit 16** (with emitters 80 and muzzle 24, 240 quads in all);
  - **the worst moment** (three buildings at KRITISK in view, two collapses and a siege, every ring
    full): 0.3 + 0.05 + 136 x 1.5 µs = **about 0.55 ms**, inside 0.56. No amendment of ADR 0027 §9.
  - The rings are data; P162 pins the counts, P147's phone card the time. If the card shows more,
    the fallbacks are data edits in this order: `damage_slots` 64, the KRITISK smoke to 10 per
    building, `collapse_slots` 32.
- **Fill rate:** thick black smoke is the largest overdraw of the game (about 0.3 M blended px for
  three burning buildings at game zoom); the phone card judges it with the time.
- **Nodes:** none per frame and none at DIED; a ruin keeps the dying building's node for up to
  46.5 s, at most 16 at once.
- **The page** (cross-faction two-player match at bake scale 1.0, budget 3584).
  - **Measured:** P158 at 573f720: the two patches add 300 rows at full scale (3566) and 210 at 75 %
    (3476). Page rows do not follow the area (x 0.5625 at 75 %) but about the scale to the power
    1.24 (0.75^1.24 = 0.70: a shelf is as tall as its tallest slot, so rows shrink with the height
    more than with the area). Every estimate below uses rows(s) = rows(1.0) x s^1.24.
  - **The ruin's size**, from P158's sheets: at most half the body's canvas height (§5's refusal)
    plus 8 rows of debris, and the body's width plus 32 columns, is **0.65** of the two patches'
    area at most; a ruin at 40 % of the canvas height is 0.53. So the ruin costs 159 to 195 rows at
    full scale, 111 to 136 at 75 %, 67 to 83 at 50 %, 51 to 63 at 40 %.
  - The new `dmg1` and `dmg2` are taken at P158's measured cost (their depth rules are the same);
    SKADET kept within 35 % of the body (step 3) saves about 26 rows at 75 % (`dmg1` is 42 % of the
    two patches' area and loses 30 % of its rows). The packing may cost 5-10 % more as the page
    fills.

  | Layout | Rows over 3266 | Cross page | Rows left |
  | --- | --- | --- | --- |
  | P158 as measured: `dmg1` + `dmg2` at full scale | 300 | 3566 | 18 |
  | P158 as measured: `dmg1` + `dmg2` at 75 % | 210 | 3476 | 108 |
  | + `ruin` at full scale, cropped to ink | 369-405 | 3635-3671 | over by 51-87 |
  | + `ruin` at 75 % (steps 1-2) | 321-346 | 3587-3612 | over by 3-28 |
  | + `ruin` at 75 %, SKADET within 35 % (steps 1-3) | 295-320 | 3561-3586 | 23 to over by 2 |
  | steps 1-3, then the ruin at 50 % (question 2, A) | 251-267 | 3517-3533 | 51-67 |
  | steps 1-3, then the ruin at 40 % (question 2, B) | 235-247 | 3501-3513 | 71-83 |
  | steps 1-3, then all three damage parts at 62.5 % (question 2, C) | 236-256 | 3502-3522 | 62-82 |
  | a `ruin` without team colour, shared by all owners | as its row | - | no saving on this page |

  The last three rows take step 3's 26 rows off the patches (210 - 26 = 184 at 75 %, 147 at
  62.5 %). Mirror pages stay under the budget in every layout (Lumen about 3134-3159 with the ruin
  at 75 %). At 3584 rows the page's GPU memory is about 58.7 MB, inside ADR 0023 §2's 64 MB.
- **Why the shared ruin is no fallback:** on the cross-faction page each faction's buildings are
  baked for its one player only, so a ruin without key colours still takes one slot per type; it
  would save only on mirror pages, which have about 400 rows free. It also drops the "remnants" of
  team colour Michael's table keeps. So it is not on the list.
- **What is decided and in what order** (the measured page after P158a and P158b decides):
  1. the ruin cropped to its ink (P163, always);
  2. the ruin baked at its own factor `RUIN_SCALE`, equal to `DAMAGE_SCALE` (0.75) at first
     (P157c, always);
  3. SKADET within the top 35 % of the body's rows (a lead decision: it is still "small nicks", the
     sheet's SKADET);
  4. still over, or under 30 rows left: **Michael chooses** (question 2): A, the ruin at 50 %
     (recommended); B, the ruin at 40 %; C, all three damage parts at 62.5 %. P158b sets
     `RUIN_SCALE` (A, B) or `DAMAGE_SCALE` (C).
  Never a second page (a draw call and about 16 MB more), and never the 512 rows above 3584 that
  ADR 0027 §4 keeps for later types. P153 and P154 of the unit-life plan will not fit beside this
  (their rows already land only if the page has room).

### 12. The seam of the trimmed body and its patch (replaces ADR 0028 §3's second amendment's open point)
ADR 0028 §3's second amendment asked for "at least 1 texel" of overlap and named "the `floor` of the
patch's cut" as a way; P157b's review found that both are wrong (the raster rounds each axis, so a
texel count from `bake_scale` alone is not the region's), and the rule is the one in the
`DAMAGE_SCALE` doc block of `game/view/IsoAtlas.gd` (P157b, #300). It replaces the open point and
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
- `data/life_settings.tres` (`LifeSettings`, view only), with their values:
  - stages: `building_stage_percent` [67, 34], `vehicle_stage_percent` [50, 25] (instead of
    `damage_stage_percent`);
  - burning: `damage_burning_points` [1, 3], `damage_smoke_cap` 30; per stage `damage_emit_ms` and
    `damage_life_ms` (P148's, now per stage): SKADET `smoke` 500 / 2000, KRITISK `soot` 400 / 2000,
    `fire` 500 / 700 (KRITISK at `damage_fire_scale` 1.6), `glow` the life of its fire, `jet`
    300 / 600, `spark` 400 / 500, ruin `smoke` 700 / 2000, `ember` 900 / 1800;
    `ruin_smoke_ms` 8000, `ruin_ember_ms` 15000;
  - rings: `damage_slots` 80, `collapse_slots` 40, `hit_slots` 16;
  - hits: `hit_flash_ms` 60, `hit_flash_box_milli` 500 (the middle half of `frame_box`),
    `hit_chips` [3, 5], `hit_chip_ms` 350;
  - collapse: `collapse_flash_ms` 250, `collapse_fire_puffs` [2, 3], `collapse_sink_ms` [250, 700],
    `collapse_sink_steps` 6, `collapse_sink_percent` 40, `collapse_switch_ms` 700,
    `collapse_dust_ms` [250, 900], `collapse_dust_puffs` 8, `collapse_debris` [6, 8],
    `ruin_from_ms` 900;
  - ruin: `ruin_life_ms` 45000, `ruin_fade_ms` 1500, `ruin_fade_steps` 10, `ruin_fade_dust_puffs` 2,
    `ruin_slots` 16, `crater_scale_milli` {`refinery`: 1500} (others 1000);
  - shake: `collapse_shake_px` 3.0, `collapse_shake_ms` 300.
  - Data tests hold the order of the times (flash end = sink start; sink end = switch; switch <
    ruin start = dust end; ruin start < ruin life), each `[min, max]` with min at most max, the smoke
    cap for every stage, and one collapse's puffs (1 + 3 + 8 + 8 = 20) at most half of
    `collapse_slots`.
- `IsoAtlas.DAMAGE_SCALE` and `IsoAtlas.RUIN_SCALE` are view constants (not balance).
- **New frames in `fx/life_atlas.svg`** (hand-drawn in this repo, STYLE.md's fx rules, no filter):
  `hit_flash` (white, 2), `chip` (3: concrete grey, dark steel, a pale shard), `dust_cloud` (2, large,
  stepped alpha), `ember` (2), `glow` (1, stepped discs, warm yellow), `jet` (2, a sideways gas
  flame, yellow-white). `smoke`, `soot`, `fire` and `spark` exist.

## Consequences
- A building's damage reads in its shape at phone zoom: nicks and blown panes, then a collapsed part
  with its inside showing and fire inside, then a low dark ruin that smokes and glows; a kill is a
  flash, a sinking building, a dust cloud and a short shake.
- Still view and art only: no sim change, no golden hash, no new draw call.
- The generator grows by a pose, two shapes, two helpers, two moves, four materials, an ink test and
  new counts; sixteen buildings get a third picture and their poses are redone (P158's are the
  starting point).
- The page is near its budget: a fourth picture per building, a later building type, or P153 and
  P154 have no room without one of §11's steps.
- `AirFx` holds five rings (240 quads); the life layers' worst moment is about 0.55 ms, inside ADR
  0027 §9; the smoke is thinner than rule 8's cap allows (15 of 30 per building) to stay there.
- `RtsCamera` gains an offset term in two functions; the camera still moves only by the player's
  hand except for a collapse's 300 ms shake.
- Amends (dated notes by the lead's P26at on acceptance): ADR 0028 (§2 lists, §3 stage meanings,
  the `Anim` at stage 2 and the seam, §6, §7, §8, §9), ADR 0027 §3 (the quota table) and §8
  (reduced), the unit-life plan's out-of-scope line (camera shake), ADR 0023 §5 (the part `ruin`).

## Alternatives considered
- **A ruin in the sim** (blocking 45 s): Michael's "Kun grafik"; rejected (§1).
- **The ruin as a third patch over the body:** nothing of the intact body may remain and debris
  lies outside its canvas; rejected for a whole sprite (§3).
- **The `Anim` always hidden at KRITISK** (ADR 0028's third amendment): it was for a low ruin;
  rejected for "follows its carrier" (§3).
- **A new `Ruin` node per death:** a node at DIED; rejected for keeping the dying building's node.
- **A ruin in `DecalLayer`:** wrong occlusion and a third container; rejected (§8).
- **A whole-building white flash:** a page picture per building or a batch split per hit; rejected
  for a flash at the hit point (§7, a stated deviation).
- **Hit feedback from IMPACT alone:** the rifle's hits would get none; rejected for SHOT too (§7).
- **A fade by alpha:** a batch split per fading ruin; rejected for the sink (question 3).
- **Additive glow:** a material, one more draw call; rejected for one alpha glow pass (§6).
- **30 smoke puffs per building by default:** the rings would pass ADR 0027 §9; rejected for 15
  under the cap of 30 (§6, §11).
- **Shake on every own loss or on every collapse anywhere:** a shake from off screen reads as a
  fault; rejected for "seen and on screen" (§7, question 4).
- **A second atlas page or the reserve rows:** rejected (§11).
- **A shared neutral ruin:** saves nothing on the cross page; not a fallback (§11).

## Questions for Michael
1. **When do vehicles look damaged?** Your sheet is about buildings, which now change at 66 % and
   33 %. Recommended: **vehicles keep 50 % and 25 %**, as today. If they changed at 66 %, most of an
   army would look worn after its first fight, and vehicles have no ruin. Alternative: vehicles
   change at 66 % and 33 % too (one number in the data).
2. **If the picture page is still too full.** The ruin is a third picture for each of the 16
   buildings, and the page of pictures has a fixed size. We first trim the ruin to what it shows,
   draw it at 75 % sharpness like the damage pictures, and keep the damaged stage's nicks to the top
   third of the building. If it still does not fit with some room to spare: recommended **A, the
   ruin at 50 % sharpness** (it is low, dark rubble under smoke; your 75 % for the damage pictures
   stays; it frees about 45-55 rows). B: the ruin at 40 % (a bit softer, more room). C: all three
   damage pictures at 62.5 % (a little softer damage everywhere). Not offered: a second page (more
   draw calls and memory on the phone).
3. **How the ruin goes away after 45 seconds.** Recommended: **it sinks into the ground over 1.5
   seconds with a little dust** and leaves the soot mark; this costs nothing. A true see-through
   fade costs one to three extra draw calls per fading ruin for those 1.5 seconds.
4. **The camera shake.** Your sheet says only a collapse may shake the camera; until now the game
   had no shake at all. Recommended: **a small, short shake for every collapse you see on the
   screen, your own buildings and the enemy's**, and none with reduced effects. Alternatives: shake
   only for your own buildings, or no shake at all.
