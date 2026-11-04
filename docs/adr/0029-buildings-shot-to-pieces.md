# ADR 0029: Buildings shot to pieces: three damage stages, a collapse into the crater, hit feedback (view and art only)

**In short, for Michael:** a building shows three pictures as it is shot (whole, damaged, critical)
and changes its shape at each, with smoke and fire on top as particles. When it dies it flashes,
sinks into a dust cloud and is gone, leaving the crater with a little smoke and embers. Hits flash
and throw chips. The camera never shakes, and there is no ruin picture (your answers of 2026-11-04).

Status: **accepted 2026-11-04** (Michael's answers: 1 keep 50/25 for vehicles, 2 A, 3 sink,
4 "Ingen rystelse"; see "Answers" at the end). Proposed 2026-11-03 (P26as, architect) on `main` at
4b5c26d (#297, P26ar, merged); revised 2026-11-04 after the docs lens (on `main` at 321092e, P157
#299 merged); the camera shake taken out on acceptance (answer 4).
**Revised 2026-11-04 before merge: Michael dropped the ruin** ("Fjern ruinen, den er der i så kort
tid at det er lige meget"); the collapse ends in today's crater, and answers 2 and 3 are moot.
The decisions taken from Michael's two reference sheets of 2026-11-03 and from his answers are his.
Plan: `docs/plans/2026-11-03-damage-states.md`, section "ADR 0029 rework" (rows P163, P163b, P167,
P158a, P158b, P165, P166 and the re-scoped P159, P160, P161, P148 and P162). The acceptance row
P26at is folded into P26as: the same PR writes the dated notes in ADR 0028 (a status note at the top
and notes in §2, §3, §4, §6-§9), ADR 0027 (§3's quota table: damage 24 → 80, a collapse ring of 40,
a hit ring of 16; §8, what `reduced` keeps) and ADR 0023 §5 (the new sheet fields). The unit-life
plan's "no camera shake" line stays as it is.

Status note (2026-11-04, P26au docs; on `main` at 48e7415): dated notes at the end of §4, §5, §7,
§12 and §13, with pointers in §6 and §10, record what was built and decided. P163 (#306), P163b
(#307), P161 (#308) and P148 (#309) are merged. P148b (#310), P158a, P158b and P166 are on their
branches. The decisions are Michael's and the lead's. No accepted text changed.

Status note (2026-11-04, P26av docs; on `main` at 6eab1e6): P148b (#310), P158a (#312), P158b
(#313), P166 (#314) and P165, as P165a (#315) and P165b (#316), are merged. A dated note at the end
of §8 records what P165a and P165b built and what the lead decided for them, with pointers in §9,
§10 and §13. The P26au notes written from their branches (the page figures in §4 and §10, §7's chips
and cull, §13's P148b notes) hold as merged. No accepted text changed.

It amends ADR 0028: §2 (the thresholds, one list per kind), §3 (what `dmg1` and `dmg2` show, the
`Anim` at stage 2, the damage points, and the second amendment's open point on the seam, §11 here),
§4 (what `scar_milli` means, the loose part's scale and mirror), §6 (the particles), §7 (reduced
effects), §8 (the budget) and §9 (the data). Everything else in ADR 0028 stands: view and art only,
stages as a pure function of hp, the trimmed body with a `Damage` sibling, `DAMAGE_SCALE`, the
vehicle overlays, the remembered stage and the ghosts. No rule, state column, Command, event or
golden hash changes; no file in `game/sim` or `native/` changes.

**Why a new ADR and not a fourth amendment of ADR 0028.** The sheets add two systems ADR 0028
does not have (a collapse, hit feedback), change the meaning of both stage pictures and the
thresholds, and touch ADR 0027 and ADR 0023 too. ADR 0028 already carries three dated amendments of
its §3; a fourth that rewrites §2, §3, §6, §7 and §8 would leave no readable text. ADR 0028 stays the
record of the stage mechanics; this ADR is the record of the look.

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
- **Michael's answers on the ruin.** First "Kun grafik" (the sheet's 45 s ruin would block
  nothing), then, on 2026-11-04, **"Fjern ruinen, den er der i så kort tid at det er lige meget"**
  (drop the ruin, it is there so briefly that it does not matter). So the sheet's RUIN picture, its
  rule 1's fourth sprite and its rule 6 (the ruin lies 45 s) are not built; the collapse of its rule
  5 ends in today's crater. The sheet's point 2 above is answered by the KRITISK picture and the
  collapse, not by a ruin.
- **What exists.** P156 (generator v4: damage poses `shift`, `turn`, `hide`, `char`, `damage=<k>`
  primitives, the geometric cut, patches cropped to ink, `cuts`, the count rules) and P157 (the
  neutral sheet, #299, 321092e) are on `main`. P157b (`DAMAGE_SCALE` 0.75) is PR #300. P158
  (`dmg1`/`dmg2` for all 16 buildings, two `damage` points on each of the 14 non-defences and one on
  each defence, the gallery's Stage button; branch `claude/p158-building-damage` at 573f720) is on
  hold because this spec changes its target; it measured the cross-faction page at 3566 with both
  patches at full scale and at 3476 / 2875 / 3023 (cross / mirror Derrick / mirror Lumen) of 3584
  with both at 75 %. The view on `main`: `EffectsLayer._add_death` (a DIED burst), the `DecalLayer`
  crater (`decals/crater.svg`) that `BuildingLayer._drop` lays for a building that falls in sight,
  and `AirFx` with its one ring, the emitters' 80 (P145); the damage ring (P148) and the muzzle ring
  (24, P149) are still to come; P152's wrecks (a husk for 20 s) are a later row. `RtsCamera` has no
  shake; the unit-life plan puts camera shake out of scope ("the camera moves only by the player's
  hand"), and this ADR keeps it so (answer 4). There is no repair.
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
1. **View and art only.** No ruin: a dead building collapses into today's crater.
2. **Three damage stages:** INTAKT, SKADET, KRITISK. Buildings switch at 67 and 34 (strict
   "under"): 67-100 % intact, 34-66 % SKADET, 1-33 % KRITISK; at 0 % the collapse. One list per kind
   in data; vehicles keep 50 and 25 (answer 1).
3. **Pictures:** `dmg1` = SKADET and `dmg2` = KRITISK stay patches over the trimmed body; no third
   picture. At KRITISK the `Anim` follows its carrier (per sheet; a missing field hides it).
4. **Art language** per stage from the sheet's table, the five material rules, a rule per building.
5. **Generator v5:** broken (jagged) edges, rods for rebar and beams, petal plates, interior and
   hole materials, the `blow` move, key faces that may char only out of the band, 2-4 typed `damage`
   points with ink under them at both stages, ambient emitters that go quiet when their group
   breaks, `anim_kritisk`.
6. **Particles per stage** in `AirFx`: a fixed-seed choice of the burning points, at most 30 smoke
   puffs per burning building (15 by default), one shared glow pass, no blur; 240 quads in all.
7. **Hit feedback:** a white flash of 60 ms at the hit point and 3-5 chips, from IMPACT and from the
   SHOT of a hitscan weapon. **Nothing shakes the camera** (answer 4, "Ingen rystelse").
8. **Collapse** from DIED: flash and explosion 0-250 ms, the building sinks behind the dust
   250-700 ms and is hidden at 700, the dust settles by 900 and the node is freed; the crater lies
   there; smoke 8 s and embers 15 s rise over it.
9. **Fog:** a collapse only for a death the player saw; the smoke over the crater by the fog rule of
   a live building; nothing is invented for a death not seen.
10. **Reduced effects** keep every picture, the fire, the flash, the sink and the dust; they drop
    sparks, embers, chips, debris and the smoke over the crater.
11. **Budget:** no new draw call; collapse writes inside the buildings' write share (at least 6);
    the life layers' worst moment stays inside ADR 0027 §9's 0.56 ms; the two patches at 75 % keep
    the page under 3584.
12. **The seam rule** of the trimmed body and its patch is the one in `IsoAtlas`'s `DAMAGE_SCALE`
    block (P157b), not ADR 0028's "at least 1 texel".
13. **Vehicle overlays:** `scar_milli` 1000 is the scar's canvas as drawn; the loose part has one
    view scale `LOOSE_SCALE`; both set when a rig is dressed; a mirrored loose part by a negative
    `scale.x`.
14. **Repair:** none in the game; recorded for a future repair ADR.

## Decision

### 1. View and art only
- Every part of this ADR reads the published snapshot and its events (`SHOT`, `IMPACT`, `DIED`) in
  the layers' `ticked` and frame paths, and the match time (`LifeClock`). Nothing is added to the
  sim.
- **The collapse is a view entry**, kept by `BuildingLayer` for the 900 ms after the building's row
  is gone (§8). **Rejected:** a ruin, in the sim (a blocked footprint) or in the view (a 45 s
  picture): Michael's answers.

### 2. Three damage stages and their thresholds
- **INTAKT 100-67 %, SKADET 66-34 %, KRITISK 33-1 %** (Michael: "skift ved 66 % og 33 %"). Under ADR
  0028 §2's strict "under" rule the integers are **`[67, 34]`**:
  `stage = (1 if hp x 100 < max x 67) + (1 if hp x 100 < max x 34)`. So 67 % exactly is intact,
  anything under 67 % is SKADET, 34 % exactly is SKADET, anything under 34 % is KRITISK. The
  sheet's bands are these thresholds read as whole percents rounded down (66.9 % reads as 66).
- **0 % is the collapse.** A row with hp 0 or less is removed by the sim in the same tick (`World`
  REMOVE, a DIED record), so the view never sees a live row at 0 %; what follows a building's DIED
  is §8.
- **The thresholds stay in data, one list per kind:** `LifeSettings.building_stage_percent`
  (`[67, 34]`) and `LifeSettings.vehicle_stage_percent` (`[50, 25]`, ADR 0028's values, Michael's
  answer 1). They replace ADR 0028 §9's single `damage_stage_percent` (P159 creates the fields). The
  data test holds `100 > P1 > P2 > 0` for each list. `BuildingDamage.stage_of(hp, max, percents)`
  takes the list, so buildings, vehicles and `AirFx` still share one function. No hysteresis, no
  latch (ADR 0028 §2 stands).
- **Sites** show no stage (ADR 0028 §2 stands).

### 3. The pictures of each stage
| Stage | Part | What it is | Where it draws |
| --- | --- | --- | --- |
| INTAKT | `hull` | today's body | `Body` in the sort |
| SKADET | `dmg1` | a patch over the trimmed body (ADR 0028 §3) | `Damage` sibling of `Body` |
| KRITISK | `dmg2` | a patch over the trimmed body; the `Anim` follows its carrier (below) | `Damage` sibling of `Body` |

- **No third picture.** `IsoAtlas.DAMAGE_PARTS` stays `[dmg1, dmg2]`; there is no `ruin` part and no
  ruin scale. The sheet's RUIN column is answered by the collapse (§8).
- **The `Anim` at KRITISK follows its carrier** (a lead decision, 2026-11-04; it replaces ADR 0028
  §3's third amendment for stage 2). Michael's "Ja, styrt dem" hid the `Anim` at the old stage 2,
  which was a low ruin; at the new KRITISK a part has collapsed but most of the building stands, so
  the moving element runs where its carrier still stands in the KRITISK pose and is hidden where its
  carrier fell. It is per sheet: the model says `anim_kritisk run` or `anim_kritisk hide`, the
  generator writes it to the sheet (`IsoSheetDef.anim_kritisk`, a bool) and requires it of every
  building with an `anim` and a `dmg2`, and refuses `run` when the `anim` part's lowest point has no
  ink under it in `dmg2` (§5's ink test). The view reads the sheet property; **a sheet without the
  field hides the `Anim` at KRITISK** (a lead decision on P159). SKADET: the `Anim` runs, at its rate
  (ADR 0028 stands). The write costs stay those of ADR 0028 §8 (one visibility write when hidden).
- **A defence's `Head`** stays at SKADET and KRITISK (defences still aim and shoot); the collapse
  hides it with the rest (§8).
- **What P158's art becomes** (its poses no longer match: its `dmg1` "holes down to half" and its
  `dmg2` "a low ruin"):
  - P158's `dmg1` poses (holes, roofs torn out, the dark inside) are the **starting point of the new
    `dmg2`, KRITISK**: a part has collapsed, the inside is visible. They gain the interior (slabs,
    rebar, beams), the breaks of their material rule and soot.
  - P158's `dmg2` poses (rubble and wall stubs, a low ruin) are **dropped**: there is no ruin.
  - The **new `dmg1`, SKADET, is new work**: small nicks at a corner, a mast or a wing, blown panes
    with their frames kept, soot over the holes; the silhouette changes, unlike P158's first pass.
  - **The two defences get a second `damage` point** (`defence_turret` and `renew_defence` have one
    each at 573f720; §5 asks for 2-4).
  - Kept from the branch: the gallery's Stage button (three stages), the page test's structure and
    the `DAMAGE_PARTS` pin, the tests. The branch is not merged as it is; the art rows of the plan
    (P158a, P158b) carry what is kept.

### 4. Art language per stage
**The table** (Michael's sheet, without its RUIN column; the rule for every building and stage):

| | INTAKT | SKADET | KRITISK |
| --- | --- | --- | --- |
| Life | 100-67 % | 66-34 % | 33-1 % |
| Silhouette | whole | small nicks: a corner, a mast, a wing | a part has collapsed |
| Surfaces | clean | blown panes, soot over the holes | the inside shows: slabs, rebar, beams, dark rooms |
| Light | - | one fire, a weak glow | fire lit from inside |
| Smoke | - | grey and thin | black and thick |
| Team colour | 100 % | about 70 % | about 35 % |

- Each stage changes the **shape** more than the one before; damage must read in the silhouette, not
  in the colour alone (the sheet's heading). KRITISK's breaks are jagged and show the inside, never
  clean blocks (the sheet's point 2).
- **Smoke, fire, embers and sparks are never drawn into a sprite** (the sheet's "two layers: sprite
  plus effects", rule 2): a sprite is one picture with no smoke or fire, so the particles can move
  and go out. The particles are §6.
- **The five material rules:**
  - **Concrete** breaks along the panel joints and the floor slabs; rebar sticks out of every break;
    grey lumps and dust.
  - **Steel** bends and twists, it never shatters.
  - **Glass:** the panes go first, as dark holes; the frames stay.
  - **Tanks and spheres:** a hole with a burning gas jet (SKADET), then torn open like a flower of
    plates and burning (KRITISK).
  - **Masts and towers** snap in one place and fall in one direction; the top lies beside the stump.
  - Brick (two of our buildings) follows the concrete rule without rebar: it breaks along its
    courses into red-brown lumps.
- **Per building** (the sheet's table for our 16 ids, in our words, with the rules of its two
  example panels that apply to our ids; a rule about the ruin is not built):

  | Fossil id | Rule | Renew id | Rule |
  | --- | --- | --- | --- |
  | `barracks` | concrete, the full concrete rule: the facade breaks along the panel joints and floor slabs, rebar at every break, and the team paint burns off from the top down | `renew_barracks` | the white cladding is sooted, the glass wing shatters |
  | `headquarters` | concrete; the chimney snaps and topples | `renew_hq` | glass and concrete; the floors fall in steps |
  | `power_plant` | brick; the boilers burn | `renew_power` | blades and towers, the mast rule (the sheet's own Wind Park example) |
  | `refinery` | gas spheres, the tank-and-sphere rule; thin pipes and the flare bend and never shatter; the gas leaves the largest soot mark on the ground (§8) | `renew_refinery` | the tanks crack and fall together |
  | `vehicle_factory` | brick and steel trusses; the roof falls in | `renew_factory` | a glass roof, the glass rule (the sheet's own Motor Works example) |
  | `fossil_radar` | the steel lattice bends and topples | `renew_radar` | the dome is punctured, the mast snaps |
  | `defence_turret` | concrete; the turret is lifted off in the collapse (the `Head` goes with the flash, §8) | `renew_defence` | concrete; the gun is lifted off in the collapse, as the turret |
  | `fossil_strike` | a steel portal that bends and twists | `renew_strike` | the pillars snap, the ring beam falls |

  (At SKADET and KRITISK a defence's `Head` stays seated, so its breaks show in the hull around
  it. The portal's "the ruin is a twisted skeleton" is a ruin rule and is not built.)
- **Team colour per stage** is the share of the intact picture's key-colour pixels that is still key
  colour: SKADET about 70 %, KRITISK about 35 %. The art gets there by hiding, turning and charring
  team faces (§5); a test measures it (§5). For the barracks the charred team faces are the top ones
  first.
- **Depth on the body** (the page, §10): SKADET's changes reach at most half the body's rows from
  its top (ADR 0028 §3's amendment for stage 1; §10's fallback tightens it to 35 %); KRITISK may
  reach down to just above the foot (the generator still refuses a change that reaches the foot).
- **Originality** (CLAUDE.md Legal, ADR 0023 §13, ADR 0028 §4): every picture is generated here from
  our own models; flames stay yellow-white and smoke grey, outside both factions' key bands.

Notes (2026-11-04, P26au docs; the text above stays as accepted):
- (Michael, 2026-11-04) **The look of both factions' buildings is approved**, from the sheets of
  P158a and P158b (intact, SKADET, KRITISK).
- (Michael, 2026-11-04) **SKADET may reach past the top half of the body's rows, at most 80 %.**
  It replaces "at most half" in "Depth on the body" above. Two things push the cut down: a team
  colour that sits low (a change there keeps the SKADET key share of 55-85 %, §5) and a blown pane
  that sits low (its outline sets the cut). 13 of the 16 pass the half. The deepest: the Redoubt
  (`defence_turret`) 76 %, the Rigworks (`headquarters`) and the Heavy Yard (`vehicle_factory`)
  69 % (P158a); the Motor Works (`renew_factory`) 72 %, the Crew Hall (`renew_barracks`) and the
  Rail Battery (`renew_defence`) 64 % (P158b).
- (P158a) **The Derrick League has no glass.** A blown pane there is a `hole` box over a `lamp`
  window. `blow` is used by the Lumen Accord only.
- (P158a) **No brick.** The table's "brick" for the Turbine Hall (`power_plant`) and the Heavy Yard
  (`vehicle_factory`) is concrete in the art, because ADR 0023 dropped brick. Both follow the
  concrete rule; the brick line of the material rules has no building.
- (P158a, P158b) **§10's first fallback** ("SKADET within the top 35 %") can no longer apply to many
  of the sixteen without breaking the key-share band. A raster probe on the intact hulls puts at
  least nine above the band even if every key pixel in the top 35 % went, among them the Rigworks,
  the Heavy Yard, the Redoubt, the Crew Hall and the Rail Battery. For them only the second fallback
  (tighter KRITISK patches) is left.
- (P158a and P158b together, on `claude/p158b-renew-damage` at 35f4954, not yet merged) **The page
  with all 16 buildings** is measured: cross-faction 3550 (3558 in the other key triads), Derrick
  League mirror 3008, Lumen Accord mirror 3140. All are within 3584, so no fallback of §10 is
  taken.

### 5. Generator v5 (`tools/artgen/`)
Features the art needs, each one a simple 3D-to-SVG step (primitives, moves, palette, the painter's
order), deterministic (no randomness: where a helper varies, it varies by an integer hash of the
art id and the line), **generated, never hand-edited**:
- **Broken edges:** a shape `broken`, a box whose top edge (along its longer horizontal axis) is a
  zigzag of `teeth=N` points between `low=<fraction>` and the full height (the heights from the hash),
  drawn as an extruded polygon: front and back faces plus one quad per tooth segment (the sheet's
  point 2: no clean blocks).
- **Interior faces and slab edges at breaks:** palette materials `interior` (the dark room: two flat
  near-black tones by the face's normal, no light ramp), `slab` (a concrete slab's edge: a lit top,
  a dark side) and `hole` (a blown pane: near-black blue-grey). The model places them as
  `damage=<k>` primitives behind what a stage hides (point 3).
- **Rebar and beams:** a shape `rod` from one point to another (`x0 y0 z0 x1 y1 z1`, width in art
  px, optional `bend=<degrees>` that breaks it into two segments), drawn as a stroke of material
  `rebar` (rust-dark) or `beam` (steel) in the painter's order at its midpoint's depth, with no
  outline.
- **Panes into dark holes, frames kept:** a move `blow <percent>` on a group turns
  `roundi(percent x n / 100)` of the group's `n` intact `glass` primitives to `hole`, the first in the
  hash order: an **inlined djb2** of the art id and the primitive's line index (a lead decision on
  P163; not `hash()`, which is not pinned across engine versions). Primitives already `hole` do not
  count; a `blow` on a group with no glass is refused. The frames are other primitives and stay.
- **Team faces:** `char` may now take a **team (key) face**; the generator refuses a char of a key
  face whose result is not wholly outside its faction's key band (a lead decision on P163: a charred
  team face must leave the band, so a half-charred face never takes a wrong team colour). A test
  rasterises each stage (the bake's SVG raster, `Image.load_svg_from_string`) and checks the
  key-band share of the intact picture's: SKADET 55-85 %, KRITISK 20-50 % (the sheet's 70 % and
  35 % with room for the art). Soot over holes is `char` on the groups around them (no stage-wide
  move: that was the ruin's "soot over everything").
- **Bent steel:** `turn` (today) on short groups, and `rod` with `bend`; no new move. Thin pipes and
  a flare (the refinery) are bent this way, never hidden in pieces.
- **Tank and sphere "flower" plates:** a helper line `petals <cx> <cy> <z> <diameter> <n>
  <tilt>` that expands, when the model is read, into `n` thin plates (boxes) around the opening, each
  turned outward by `tilt` degrees about its base, plus an `interior` disc in the opening (KRITISK).
- **No rubble helper:** it was for the ruin's heap on the ground; a KRITISK patch cannot reach the
  foot (a change there is refused), so rubble on the ground has no stage to be in. Debris on a roof
  or a slab is authored with `broken` and small boxes.
- **Masts that snap and fall one way:** authored (a mast in two groups, the upper one turned about
  the break); no generator feature. The "one direction" is an art rule the review checks.
- **Points and counts** (rule 2: 2-4 damage points `(x, y, z, type)` per building):
  - the damage points' **type** is the emitter kind: `damage` (fire and smoke), `dmg_gas` (a gas
    jet at SKADET, a fire from the torn opening at KRITISK: tanks and spheres) or `dmg_spark`
    (sparks and thin smoke, no fire: electrics);
  - **every building with damage poses has 2 to 4** of them together (today at most 2);
  - **ink under every point at both stages** (a lead decision): the points are one list per building
    (not per stage), any of them can burn at SKADET and up to three at KRITISK (§6), so the generator
    refuses a point whose projected spot is not inside the outline of a primitive drawn at stage 1,
    or not inside one drawn at stage 2 (a geometric test, no raster). Stage 1 of a model with `dmg2`
    only is the intact picture plus its `damage=1` primitives;
  - vehicles keep one `damage` and one `hang`, infantry none; `scar_milli` stays the vehicles' (§12).
- **Ambient emitters** (`smoke`, `steam`, `flame`): each must have ink under it at every stage at
  which it still emits (the same test). An emitter line may name its group (`group=<name>`); the
  generator writes per emitter the first stage whose pose moves or hides that group
  (`IsoSheetDef.emitter_quiet`, parallel to `emitters`; 0 for never, 1 or 2), and `AirFx` stops that
  emitter from that stage on (P148). An empty `emitter_quiet` (every sheet without damage poses)
  reads as all zeros. The headquarters' chimney, the refinery's flare, the power plant's stacks and
  the renew refinery's tanks are the known cases.
- **Refusals kept** (ADR 0028 §3's notes): `dmg1` without `dmg2`; a damage move of an `anim` group
  or of `mount`; a stage that changes nothing, a change wholly above the canvas, a change that
  reaches the body's foot. **New:** an odd body canvas height for a building with damage parts (the
  seam invariant of §11 holds only for even heights; all 80 real parts are even); a building with an
  `anim` and a `dmg2` that does not state `anim_kritisk`; `anim_kritisk run` with no ink under the
  `anim` part in `dmg2` (§3).
- **Cut for cost:** no automatic interior (the generator does not invent rooms behind a hidden wall;
  the model places them), no break simulation (a break is authored as groups), no texture or gradient,
  no per-pixel crack pattern. If `petals` turns out costly in review, the plates are authored boxes
  with `turn` moves and the helper is dropped; the art loses nothing but typing.

Notes (2026-11-04, P26au docs; generator v5a, P163 #306, and v5b, P163b #307, as merged; the text
above stays as accepted):
- (P163) **The `blow` order** is djb2 over the UTF-8 bytes of the art id (32 bits), mixed with the
  primitive's line index by `ArtDamage._mix`. It is not one hash of the id and the line, as "an
  inlined djb2 of the art id and the primitive's line index" above may read. `broken`'s teeth vary
  by the same seed and mix.
- (P163) A damage point must also lie above `dmg1`'s cut, off a SKADET break. **A model with `dmg2`
  only has no `dmg1` cut, so its points have no cut rule.** This is open; no real model has `dmg2`
  only, so none hits it.
- (P163b) **`petals` carries a part and a material**:
  `petals <part> <material> <cx> <cy> <z> <diameter> <n> <tilt>`. It is allowed only in `hull` and
  `anim`.
- (P163b) **`rod` takes any material**, not only `rebar` and `beam`, **and casts no shadow.** Both
  are the generator's own decisions; this ADR decided "no outline" and named `rebar` and `beam`.
- (P163b) **`taper` is refused** on `rod`, `broken` and `petals`.

### 6. Particles per stage (P148, reworked again)
- **Looks** (sprites of `fx/life_atlas.svg`; new frames in §13):

  | Stage | Burning points | Smoke | Fire and light by point type | Other |
  | --- | --- | --- | --- | --- |
  | SKADET | 1 | `smoke`, grey and thin | `damage`: a small `fire` and a weak `glow`; `dmg_gas`: a `jet` (the burning gas jet from the hole) and a weak `glow`; `dmg_spark`: sparks, no fire | - |
  | KRITISK | up to 3 | `soot`, black and thick | `damage` and `dmg_gas`: a large `fire` and a strong `glow` (lit from inside; for a sphere, from its torn-open flower); `dmg_spark`: sparks, no fire | sparks at every burning point |
  | after the collapse | every damage point, at ground height | `smoke`, thin and grey, for 8 s | `ember` for 15 s, a faint `glow` | - |

- **Which points burn** (rule 3): `s = LifeClock.pick(id, SALT_BURN, n)` over the building's `n`
  damage points; SKADET burns point `s`, KRITISK points `s, s + 1, ...` (mod `n`) up to
  `damage_burning_points[1]` (3), so the SKADET fire keeps burning at KRITISK and three equal
  buildings do not burn alike. A point that does not burn emits nothing. A vehicle keeps ADR 0028
  §6's looks at its one point.
- **Over the crater** (rule 5's "smoke 8 s, embers 15 s", without the ruin): from `collapse_end_ms`
  (900) the building's damage points, at their ground x and y (z 0, so the smoke rises from the
  crater, not from the air where the walls were), smoke for `crater_smoke_ms` (8000) and glow with
  embers for `crater_ember_ms` (15000). A building without a sheet or points uses its footprint
  centre. These sources live in the damage ring; at most `crater_sources` (16) at once, the oldest
  ends first. P148 draws them, P165 adds them at the collapse's end.
- **At most 30 smoke puffs per burning building** (rule 8), and **15 by default**: a data test
  holds, for each stage and for the crater, `points x ceil(life / emit) <= damage_smoke_cap` (30).
  The default numbers are lower so that the rings fit the frame budget (§10): KRITISK `soot` every
  400 ms living 2000 ms is 5 a point, 15 at 3 points; SKADET `smoke` every 500 ms living 2000 ms is
  4; the crater's `smoke` every 700 ms living 2000 ms is 3 a point, 12 at 4 points.
- **One shared glow pass, no blur** (rule 8): a `glow` frame (stepped concentric discs in warm
  yellow at low alpha, hue at least 46° and outside both key bands, drawn in the SVG, no filter) is
  drawn under every fire and ember, in `AirFx`'s one `_draw`, as its first pass over all rings, with
  normal alpha blending. **Rejected:** additive blending (a material on its own canvas item: one more
  draw call) and any blur or shader.
- **Ambient emitters** (P145's `smoke`, `steam`, `flame`) go quiet from the stage the sheet's
  `emitter_quiet` names (§5); the others keep puffing at every stage, as ADR 0027 has them.
- **Rings** (all in `AirFx`'s one `_draw` from one texture; sized for §10's frame budget):
  emitters 80 (P145, on `main`), **damage 80** (P148; ADR 0028 planned 64: two or three buildings
  at KRITISK in view at 24 quads each, 15 smoke, 6 fire and 3 glow, 30 with their sparks, plus
  vehicles and the craters' smoke; beyond that the oldest, most faded smoke goes), muzzle 24 (P149),
  **collapse 40** (§8), **hit 16** (§7): **240 quads in all**. When a ring is full its oldest puff
  goes. P148 makes a ring a small `RefCounted` (`FxRing`, packed arrays), so P165 and P166 add their
  rings with one registration line each in `AirFx.gd`.
- **Who sees it:** a shown building (`BuildingLayer.is_shown`), or a crater whose footprint the
  player sees (§9), inside the view rect grown by a tile, as ADR 0028 §6; a site never burns; a
  blackout does not stop a fire.

(2026-11-04, P26au docs: what P148 (#309) and P148b (#310) built and decided for this section, the
glow, the jet, the vehicles' fire, the ring and the crater sources, is in the note at the end of
§13.)

### 7. Hit feedback (no camera shake)
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
  keep today's puff (the sheet is about buildings). A hit whose target has a DIED record in the
  same tick draws no hit flash and no chips: the death's own effects stand for it (today's DIED
  burst, and §8's collapse flash once P165 has landed), so the hit feedback needs nothing of the
  collapse to be right.
- **A deviation from the sheet, stated** (a lead decision, 2026-11-04): the sheet asks for a white
  flash on the hit building; we draw it **at the hit point**, not as the whole building turning
  white. A whole white building needs a white copy of every body on the page (about 200 to 358
  rows: it does not fit, §10) or a tint or shader on the body, which splits the one-draw-call world
  at every hit building.
- **No camera shake** (Michael, 2026-11-04: "Ingen rystelse"). The sheet's rule 4 ("kun kollaps
  må ryste kameraet", only a collapse may shake the camera) is a limit, and no shake at all meets
  it. `RtsCamera` is untouched; the camera moves only by the player's hand, as the unit-life plan
  has it. A collapse is felt through its flash, its sink and its dust.

Notes (2026-11-04, P26au docs; P166, lead decisions; the text above stays as accepted). P166's PR
is not open yet; its work is on `claude/p166-hit-fx` (ea2577a, built on P148b), in
`game/view/HitFx.gd`.
- **The chips fly straight**, each along one of five directions in data (`hit_chip_fly_px`), and
  fade. They do not fly in arcs, because `FxRing` motion is linear: an arc would need a velocity per
  puff. This replaces "in short arcs" above.
- **A hit whose spot is outside the view is not drawn**, as the damage ring's puffs are not. So a
  siege off screen does not push the flashes in view out of the 16-slot hit ring.

### 8. The collapse at 0 %
Every time is match time from the DIED tick (`LifeClock.tick_ms(died_tick)`), so a pause freezes
it and a replay draws the same frames. The numbers are data (§13). The times follow the sheet's
rule 5 ("explosion 0-250 ms, dust cloud 250-900 ms"); its "ruin from 900 ms" becomes the crater.

| Time | What | Where it draws |
| --- | --- | --- |
| 0-250 ms | a white flash and the explosion in the middle: today's DIED burst (`EffectsLayer`, unchanged) plus a large `hit_flash` and `collapse_fire_puffs` (2-3) `fire` puffs over the footprint; `Anim` and `Head` hidden | `EffectsLayer`; collapse ring in `AirFx` |
| 250-700 ms | the building sinks into itself: `Body` and `Damage` move down and lose their bottom rows in `collapse_sink_steps` (6) steps, to `collapse_sink_percent` (60) of its rise; `collapse_dust_puffs` (8) `dust_cloud` puffs rise from the foundation along the footprint diamond; `collapse_debris` (6-8) `chip` debris fly out | the building's sprites in the sort; collapse ring |
| 700 ms | the dust is thickest: the building's node is hidden (`collapse_hide_ms`) and its cast shadow removed; the crater under it shows through the thinning dust | the sort |
| 700-900 ms | the dust settles and is gone at 900 ms (every dust puff lives inside 250-900 ms); at `collapse_end_ms` (900) the node is freed | collapse ring |
| from 900 ms | the crater, with thin grey smoke for 8 s and embers for 15 s over it (§6) | `DecalLayer`; damage ring |

- **The collapse entry.** At DIED, `BuildingLayer._drop` hands a building that was shown to the
  collapse helper instead of freeing its node: the entry leaves `_entries` (no pick, no bar, no
  selection: ADR 0028's rows), its node stays in the sort at the same position and sort key until
  `collapse_end_ms`, and it is freed then, as `_drop` frees it today. No node is made at DIED. P159
  ships the hook as `BuildingRuins.gd` (a stub that frees the node and lays the crater as today);
  P165 fills it in and renames it `BuildingCollapse.gd`. At most `collapse_max` (16) collapses run
  at once; the 17th ends the oldest at once (hidden and freed; its crater stays).
- **Many collapses at once** (a strike): the collapse ring has 40 slots and one collapse wants at
  most 20 (1 flash, 3 fire, 8 dust, 8 debris). When `n` collapses start in one tick, each gets at
  most `collapse_slots / n` puffs, dust first (it covers the hide), then fire, then debris; so every
  building keeps some cover, and eight at once get five puffs each, all dust.
- **The crater** is laid at DIED as today (`DecalLayer.add_crater`, z 1, under the sort), so it is
  under the sinking building and shows when the building is hidden. Its size is the footprint's
  crater (`CRATER_MILLI_PER_TILE`) times `crater_scale_milli` of the building's type id (default
  1000; `refinery` 1500: the gas leaves the largest soot mark, the sheet's rule), so the crater code
  gains one multiplication. It stays for the rest of the match, as today.
- **A building placed on the crater's tiles** (the sim allows it at once) stops the crater's smoke
  and embers when the new building is shown to the local player (an own site from its first tick,
  an enemy one when it is shown); their puffs live out. The crater itself behaves as today.
- **A site that dies** (killed while `build_left > 0`) gets the flash, the explosion, the sink and
  the dust, and then the crater, with no smoke over it (it never burned). **A cancelled site**
  (`DIED` with `Production.DIED_CANCEL_FLAG_AT` set) gets no collapse and no crater (the view reads no
  cancel flag today, so a shown cancelled site seems to get a crater now; P165 fixes it). The entry
  remembers whether it was a site at its last tick (ADR 0028 §2 already reads it).
- **No new draw call:** the sinking building is its own sprites on the page, the particles are quads
  in `AirFx`'s one `_draw`, the burst is `EffectsLayer`'s, the crater is `DecalLayer`'s existing one.

Notes (2026-11-04, P26av docs; P165a #315 and P165b #316 as merged, lead decisions; the text above
stays as accepted):
- **`crater_scale_milli` also holds `renew_refinery` 1500**, the Lumen Accord's refinery. The text
  above and §13 name only `refinery`.
- **The crater source is added at DIED**, with its start tick at DIED + ceil(`collapse_end_ms` x 15
  / 1000) ticks (14 ticks, about 933 ms, for 900 ms). So `end_crater_sources_on` finds the source
  even when a building is placed on the tiles during the collapse, before the smoke starts. A site
  that dies adds none, as above (it never burned).
- **Where the smoke is ended.** `BuildingLayer._refresh_shown` calls
  `AirFx.end_crater_sources_on` once per entry, the first time the entry is shown. That covers an
  own site from its first tick, and a hidden enemy building when it is later shown.
  `AirFx._on_ticked` calls `building_layer.sync_rows()` before it feeds any ring, so the stop lands
  in that tick
  whatever order the `ticked` handlers run in. This is how §13's P148b note ("P165 calls
  `end_crater_sources_on` before `AirFx`'s `ticked` handler emits") is met.
- **The shadow** goes at the hide (700 ms, `collapse_hide_ms`), as the table above has it (P159's
  stub removed it at DIED). A building that plays no collapse (a cancelled site, or any with
  `collapse_max` 0) still loses it at DIED.
- **A cancelled site draws no DIED burst either.** `EffectsLayer._add_death` skips a DIED with
  `Production.DIED_CANCEL_FLAG_AT` set, beside "no collapse and no crater" above.
- **The sink.** The body keeps at least `ceil(patch.scale.y / body.scale.y)` rows (1 with no
  patch). The patch follows the whole move, snapped to the body's rows, even where the body has no
  rows left to give, and loses only the rows that would hang below the body's foot. So a building
  whose body its stage has trimmed still sinks to `collapse_sink_percent` of its rise, and §11's
  overlap stays above zero at every bake scale.
- **Writes** (§10):
  - starts and hides are written oldest first;
  - a sink step goes to the collapse with the fewest steps written, so none is starved;
  - with `collapse_max` 0 no collapse runs, but the crater and its smoke still stand.
- **Particles** (P165b, `CollapseFx`, the collapse ring: the third `FxRing` of `AirFx._rings`, after
  the damage and hit rings):
  - the ring is split over every running collapse; this replaces "When `n` collapses start in one
    tick, each gets at most `collapse_slots / n` puffs" above;
  - a running collapse keeps what it has born; its unborn dust and debris are trimmed to the new
    share;
  - the order is dust, flash, fire, debris; this replaces "dust first (it covers the hide), then
    fire, then debris" above;
  - `reduced` turned on before the debris is born (at `collapse_sink_ms[0]`, 250 ms) drops it;
    debris already in flight lives out;
  - the fire's spread over the footprint is data, `collapse_fire_spread_milli` (350).
- **An observed edge, recorded as a note only (no decision).** An enemy building seen one tick
  before its death and unseen in its DIED tick still collapses and leaves a crater: `_drop` reads
  `entry.shown` (§9's rule), which still holds the tick before. `EffectsLayer` draws no burst for
  it, because it checks the DIED tick's fog at the point of the death. The same lag works the other
  way: an enemy building unseen the tick before its death and seen in its DIED tick gets no collapse
  and no crater, while `EffectsLayer` draws its burst when the death's tile is seen.

### 9. Fog and ghosts
- **Live stages:** ADR 0028 §5 stands (a stage only on a shown row; the remembered stage; ghosts at
  it, dimmed, with no particles).
- **A collapse only for a death the player saw:** an own building, or an enemy building shown in the
  tick of its DIED (`entry.shown`, the rule of today's crater). A collapse runs whether or not it is
  on screen; its particles are born only in the view rect grown by a tile.
- **The smoke and embers over the crater** follow the fog rule of a live building: own always, an
  enemy one's while any cell of its footprint is seen now (`BuildingLayer.any_cell_seen`).
- **No ghost of a collapse.** A building that falls in sight leaves no `LastSeen` record (the sim
  drops it), so no ghost stands on its crater; `GhostMemoryLayer` needs no change.
- **A building that dies unseen** gets no collapse and no crater (today's rule). Its ghost stays, at
  its remembered stage, until the player sees any cell of that spot; then the record is dropped and
  the ground is empty. Nothing is invented for a death the player did not see.
- **A change of the local player** re-applies the fog rule to the craters' smoke; a collapse in
  flight plays on.

(2026-11-04, P26av docs: whether an enemy building collapses follows whether it was shown the tick
before its DIED, not in it; see the observed edge in §8's notes.)

### 10. Budget
- **Draw calls: none new** (§8). ADR 0027's forecast stays 16 (about 22 in the worst moment).
- **Sprite writes** (counted in `life_writes`, inside `damage_building_writes`, 20 a frame, ADR 0028
  §8): a collapse costs 2 at its start (`Anim`, `Head`), 4 per sink step (`Body` and `Damage`,
  region and offset; 6 steps from 250 to 700 ms) and 2 at the hide (the node and the shadow):
  **28** over its life. Collapse writes go first in the buildings' share (they are timed), then the
  queued stage changes. A step that does not fit waits a frame and then writes the step of that
  moment (a coarser sink, never a lost one): a strike that kills eight buildings in one tick writes
  32 in a step frame, 20 now and the rest in the next. **The share must be at least the largest
  single stage cost, 6** (0 → 2 with the `Anim` hidden: the body's region and offset, the patch's
  region, offset and visibility, the `Anim`'s visibility), or a change could never be applied; a data
  test holds `damage_building_writes >= 6` (a lead decision on P159). The worst frame of ADR 0028 §8
  is unchanged (the share is the cap).
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
- **Nodes:** none per frame and none at DIED; a collapsing building keeps its node for 900 ms, at
  most 16 at once.
- **The page** (cross-faction two-player match at bake scale 1.0, budget 3584): **the two patches at
  75 % fit.** P158 measured 3476 with its old patches at 75 % (108 rows left; 2875 and 3023 for the
  mirrors). The new `dmg1` (SKADET) has the old `dmg1`'s depth rule (at most half the body) and the
  new `dmg2` (KRITISK) the old `dmg2`'s (down to just above the foot), so the page is expected near
  3476. Page rows follow about the scale to the power 1.24, not the area (P158: 300 rows at full
  scale became 210 at 75 %, 0.75^1.24 = 0.70). If P158a and P158b measure more than 3584, the
  fallbacks in order are: (1) SKADET within the top 35 % of the body's rows (about 26 rows: `dmg1` is
  42 % of the two patches' area and loses 30 % of its rows), a lead decision, as it is still "small
  nicks"; (2) tighter KRITISK patches (the collapsed part on one side, crops to ink). Never a lower
  `DAMAGE_SCALE` without Michael, never a second page (a draw call and about 16 MB more), never the
  512 rows above 3584 that ADR 0027 §4 keeps for later types. The page's GPU memory stays under ADR
  0023 §2's 64 MB.
- (2026-11-04, P26au docs) P158a and P158b, not yet merged, measured the cross-faction page with all
  16 buildings at 3550, within 3584. Fallback (1) can no longer apply to many buildings; see the
  notes at the end of §4.
- (2026-11-04, P26av docs) How P165a writes the collapses (oldest first, the fewest steps first,
  `collapse_max` 0) is in §8's notes.

### 11. The seam of the trimmed body and its patch (replaces ADR 0028 §3's second amendment's open point)
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
- The generator refuses odd body canvas heights for buildings with damage parts (§5).

### 12. Vehicle overlays (lead decisions on P160 and P161; amends ADR 0028 §4)
- **`scar_milli`** scales the scar, and **1000 now means the scar's canvas as drawn**, not "the
  battle tank" (ADR 0028 §4's wording): a vehicle whose hull top is smaller takes less (the Bullhead
  800). The generator writes it per vehicle model, as today.
- **The loose part** takes one constant view scale, **`LOOSE_SCALE`** (about 0.8; P160 measures the
  final value against the hulls), not `scar_milli`: a skirt plate or a fender is about the same size
  on every vehicle.
- **P161 sets `Scar.scale` and `Loose.scale` when a rig is dressed for a type** (new, or out of the
  pool for another type), never per stage or per frame.
- **A mirrored loose part** must mirror its offset about the anchor too, not only its texels. P161
  mirrors it by a **negative `scale.x`** (the sign of the magnitude set at dress), which mirrors the
  picture and its offset together: a side switch stays **1 write**, as ADR 0028 §8 counts it (with
  `flip_h` it would be 2, the flip and the offset). The position write of the follow is unchanged.

Notes (2026-11-04, P26au docs; P161 #308 as merged, lead decisions; the text above stays as
accepted):
- **A hidden rig makes no overlay writes.** It keeps its stage and marks its overlays stale. It is
  placed once, and those writes are counted, when it is seen again.
- **The vehicles' write share** is `damage_writes_per_frame - damage_building_writes` (40 by
  default). It is at least 7, the dearest vehicle change (0 → 2 with the loose part); a test holds
  it, so the queue never stalls.
- **`LOOSE_SCALE` (0.8) lives in `VehicleDamage`.** The gallery's `LOOSE_SCALE` is an alias of it,
  so there is one constant.

### 13. Numbers in data and new sprites
- `data/life_settings.tres` (`LifeSettings`, view only), with their values:
  - stages: `building_stage_percent` [67, 34], `vehicle_stage_percent` [50, 25] (instead of
    `damage_stage_percent`); `damage_building_writes` at least 6 (a data test);
  - burning: `damage_burning_points` [1, 3], `damage_smoke_cap` 30; per stage `damage_emit_ms` and
    `damage_life_ms` (P148's, now per stage): SKADET `smoke` 500 / 2000, KRITISK `soot` 400 / 2000,
    `fire` 500 / 700 (KRITISK at `damage_fire_scale` 1.6), `glow` the life of its fire, `jet`
    300 / 600, `spark` 400 / 500, crater `smoke` 700 / 2000, `ember` 900 / 1800;
    `crater_smoke_ms` 8000, `crater_ember_ms` 15000, `crater_sources` 16;
  - rings: `damage_slots` 80, `collapse_slots` 40, `hit_slots` 16;
  - hits: `hit_flash_ms` 60, `hit_flash_box_milli` 500 (the middle half of `frame_box`),
    `hit_chips` [3, 5], `hit_chip_ms` 350;
  - collapse: `collapse_flash_ms` 250, `collapse_fire_puffs` [2, 3], `collapse_sink_ms` [250, 700],
    `collapse_sink_steps` 6, `collapse_sink_percent` 60, `collapse_hide_ms` 700,
    `collapse_dust_ms` [250, 900], `collapse_dust_puffs` 8, `collapse_debris` [6, 8],
    `collapse_end_ms` 900, `collapse_max` 16, `crater_scale_milli` {`refinery`: 1500} (others 1000).
  - Data tests hold the order of the times (flash end = sink start; sink end = hide; hide < dust end
    = collapse end), each `[min, max]` with min at most max, the smoke cap for every stage and for
    the crater, and one collapse's puffs (1 + 3 + 8 + 8 = 20) at most half of `collapse_slots`.
- `IsoAtlas.DAMAGE_SCALE` is a view constant (not balance), and so is `LOOSE_SCALE` (P161).
- **New frames in `fx/life_atlas.svg`** (hand-drawn in this repo, STYLE.md's fx rules, no filter):
  `hit_flash` (white, 2), `chip` (3: concrete grey, dark steel, a pale shard), `dust_cloud` (2, large,
  stepped alpha), `ember` (2), `glow` (1, stepped discs, warm yellow), `jet` (2, a sideways gas
  flame, yellow-white). `smoke`, `soot`, `fire` and `spark` exist.

Notes (2026-11-04, P26au docs; P148 #309 as merged and P148b #310, lead decisions; they concern §6
too; the text above stays as accepted). P148b is on `claude/p148b-crater-sources` (PR #310, open).
- (P148b) **A flame and its glow are born together**, on one grid per point of
  `ceil(damage_emit_ms[fire] x 15 / 1000)` ticks (8). The glow lives one flame cycle, about 533 ms,
  not the fire's 700 ms, so it is steady: it never pulses and never overlaps the next one. This
  replaces "`glow` the life of its fire" above. A building's fire now comes every 533 ms, not every
  500; a vehicle's fire keeps its 500 ms cycle.
- (P148b) **A gas point keeps the fire's grid at both stages.** Its SKADET `jet` (life 600 ms) is
  born on that grid, as its KRITISK fire is, so the two glows follow each other with no gap.
  `damage_emit_ms[jet]` is removed; "`jet` 300 / 600" above keeps only its life.
- (P148b) **The rings are planned at alpha at most 0.98** (`AirFx.MAX_PLAN_ALPHA`), so the view
  never draws time at or past a tick that is not yet published (a glow vanished at alpha 1.0 while
  the worker held a tick).
- (P148) **A vehicle's fire has no glow.** It keeps ADR 0028 §6's looks.
- (P148) **The 80-slot damage ring** keeps every soot puff for 15 of the 56 id sets of three
  buildings at KRITISK (P148 as merged). In the other sets the demand peaks at 81-88 puffs, and
  the ring loses only soot at 80 % or more of its 2000 ms life. That is §6's "the oldest, most faded
  smoke goes". P148b's shorter glow lowers the demand (not measured).
- (P148b) **The crater's ground point** is each sheet point's x on the footprint centre line. A
  sheet point is a 2D screen offset with no height of its own, so its "ground x and y" (§6) cannot
  be read from it. A type without points uses the footprint centre.
- (P148b) **The calls for P165** are `AirFx.add_crater_source(id, centre, type, foot, owner_id,
  tick)` and `AirFx.end_crater_sources_on(foot)`, named apart from `DecalLayer.add_crater`. P165
  calls `end_crater_sources_on` before `AirFx`'s `ticked` handler emits, so a source stops in that
  tick. The crater sources moved from P148 to P148b; §6's "P148 draws them" is P148b's.

(2026-11-04, P26av docs: `crater_scale_milli` also holds `renew_refinery` 1500; P165b's looks are
data too, beside the list above: `collapse_dust_life_ms` 450, `collapse_dust_rise_px` 18,
`collapse_dust_grow` (0.8, 1.5), `collapse_dust_alpha` 0.8, `collapse_spread_milli` 700 (the dust),
`collapse_fire_spread_milli` 350 (the fire), `collapse_debris_ms` 450, `collapse_debris_fly_px`
(eight directions), `collapse_flash_grow` (1.4, 2.6), `collapse_fire_grow` (1.2, 0.8),
`collapse_alpha` 1.0 and `collapse_lift_milli` 500; see §8's notes.)

### 14. Repair (rule 7; none in the game)
There is no repair, healing or regeneration (ADR 0028 §2). For a future repair ADR: **repair runs
backwards: fire and smoke go out first, then the sprite steps back one stage.** When hp rises past a
threshold by its band (ADR 0028 §2's foreseen band, a number beside `building_stage_percent`), the
burning points of the stage left stop being born at once (puffs live out), and the picture steps
back `repair_step_ms` later.

## Consequences
- A building's damage reads in its shape at phone zoom: nicks and blown panes, then a collapsed part
  with its inside showing and fire inside; a kill is a flash, a sinking building and a dust cloud,
  then the crater with a little smoke; the camera never shakes.
- Still view and art only: no sim change, no golden hash, no new draw call.
- The generator grows by two shapes, a helper, a move, five materials, an ink test, `anim_kritisk`,
  `emitter_quiet` and new counts; sixteen buildings get their two damage pictures redone (P158's
  `dmg1` poses are the starting point of the new KRITISK).
- The page keeps about 100 rows free (estimate; P158a and P158b measure it), so P153 and P154 of the
  unit-life plan may still fit.
- `AirFx` holds five rings (240 quads); the life layers' worst moment is about 0.55 ms, inside ADR
  0027 §9; the smoke is thinner than rule 8's cap allows (15 of 30 per building) to stay there.
- `RtsCamera` is untouched: the camera moves only by the player's hand.
- Amends (dated notes written with this ADR's acceptance, P26as): ADR 0028 (the top, §2 lists, §3
  stage meanings, the `Anim` at stage 2, the points and the seam, §4 the overlays' scales, §6, §7,
  §8, §9), ADR 0027 §3 (the quota table) and §8 (reduced), ADR 0023 §5 (the sheet fields).

## Alternatives considered
- **A ruin** (a 45 s low picture after DIED, the sheet's RUIN): built into the proposal; dropped by
  Michael ("Fjern ruinen, den er der i så kort tid at det er lige meget"). It would have cost a third
  picture per building (about 110-140 page rows at 75 %) and a 45 s view entry.
- **The `Anim` always hidden at KRITISK** (ADR 0028's third amendment): it was for a low ruin;
  rejected for "follows its carrier" (§3).
- **A new node per death:** a node at DIED; rejected for keeping the dying building's node.
- **A whole-building white flash:** a page picture per building or a batch split per hit; rejected
  for a flash at the hit point (§7, a stated deviation).
- **Hit feedback from IMPACT alone:** the rifle's hits would get none; rejected for SHOT too (§7).
- **Additive glow:** a material, one more draw call; rejected for one alpha glow pass (§6).
- **30 smoke puffs per building by default:** the rings would pass ADR 0027 §9; rejected for 15
  under the cap of 30 (§6, §10).
- **A camera shake for a collapse** (seen and on screen, own or enemy; the proposal's
  recommendation), for own buildings only, or on every collapse: rejected by Michael (answer 4,
  "Ingen rystelse").
- **A second atlas page or the reserve rows:** rejected (§10).

## Questions for Michael
As asked on 2026-11-03 and 2026-11-04; the answers follow. Questions 2 and 3 were about the ruin.
1. **When do vehicles look damaged?** Your sheet is about buildings, which now change at 66 % and
   33 %. Recommended: **vehicles keep 50 % and 25 %**, as today. If they changed at 66 %, most of an
   army would look worn after its first fight. Alternative: vehicles change at 66 % and 33 % too (one
   number in the data).
2. **If the picture page is still too full** with the ruin as a third picture: recommended **A, the
   ruin at 50 % sharpness**; B, the ruin at 40 %; C, all three damage pictures at 62.5 %.
3. **How the ruin goes away after 45 seconds.** Recommended: **it sinks into the ground over 1.5
   seconds with a little dust**; a true see-through fade costs extra draw calls.
4. **The camera shake.** Your sheet says only a collapse may shake the camera; until now the game
   had no shake at all. Recommended: **a small, short shake for every collapse you see on the
   screen, your own buildings and the enemy's**, and none with reduced effects. Alternatives: shake
   only for your own buildings, or no shake at all.

**Answers (Michael, 2026-11-04):**
1. **Vehicles keep 50 % and 25 %** (the recommendation): `vehicle_stage_percent` [50, 25];
   buildings change at 66 % and 33 % (`building_stage_percent` [67, 34]).
2. **A, the ruin at 50 %** (the recommendation). **Moot since 2026-11-04**: Michael dropped the ruin
   the same day ("Fjern ruinen, den er der i så kort tid at det er lige meget"); there is no ruin
   picture and no `RUIN_SCALE`, and the two patches at 75 % fit the page (§10).
3. **The ruin sinks into the ground** (the recommendation). **Moot since 2026-11-04**, for the same
   reason; the collapse ends in the crater (§8).
4. **"Ingen rystelse"**: no camera shake at all, against the recommendation. `RtsCamera` stays
   untouched; the sheet's rule 4 ("kun kollaps må ryste kameraet") is met by no shake at all.
