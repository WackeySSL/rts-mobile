# ADR 0023: Isometric 2:1 view, two energy factions with their own rosters, and the art generator

Status: accepted, 2026-10-26 (Michael: 1 "Derrick League + Lumen Accord", 2 ja, 3 A, 4 A, 5-10
ja; "Answers" below). Proposed 2026-10-26. Docs PR #200 with `docs/plans/2026-10-22-phase-3.md`
revision 5, accepted by the lead's row P68e on the same PR. Base: `main` at 3d9e133. Supersedes ADR
0022 (accepted the same morning) except the rules §15 keeps, and amends ADRs 0004 §6, 0007 §4-§5,
0010 §2, 0011 §3, 0012 §6, 0015 §5, 0017 §4-§5, 0018 §2-§5, 0019 §1-§5, 0020 §4 and 0021 §1-§2
(listed in §15). No rule of the Phase 2 sim changes; the sim gains one data column (factions, §6)
and the strike rules of §10 with one re-pin.

## Answers (2026-10-26)
Michael answered the ten questions in chat on 2026-10-26. The lead asked them in Danish, the first
four as multiple choice; Michael's words are quoted:
1. **"Derrick League + Lumen Accord"**, the lead's alternative, not option A. The oil and gas bloc
   is the **Derrick League** (internal `fossil`), the green-energy alliance the **Lumen Accord**
   (internal `renew`). Option A's "Iron Compact" is dropped: it evokes the Iron Curtain (Red
   Alert's superweapon) and the Warsaw Pact, and it named the bloc that carried Version B's east
   look, which decision 1 drops (§13). Option B's "Current Accord" is not used.
2. **"ja":** every display name of §7, as listed after fix 1 (Flarejack, Bullhead and Arcline in
   place of the first Coyote, Bulwark and Longshot).
3. **"A":** both factions' full rosters and both superweapons in Phase 3; the strike rows
   P109-P112b are plain rows, with P109's one re-pin.
4. **"A":** the canvas's floating panels in landscape (§12, row P85d); portrait keeps the band.
5. **"ja":** the art generator (`tools/artgen/`, §5).
6. **"ja":** the two superweapons as §10 gives them (the Deep Bore's rupture, the Blackout
   Array's blackout of enemy buildings).
7. **"ja":** the on-screen trade-offs of §2-§4: a unit behind a building is hidden and its bar
   shows, last-seen ghosts draw under live units, low power shows a glyph instead of a dim, the
   minimap is a diamond.
8. **"ja":** the eight triads, Signal and Arktisk by default, and the four palette changes of §6.
9. **"ja":** the rule texts of §15: `CLAUDE.md`, `docs/GDD.md`, the `svg-art-style` and
   `touch-ui-rules` skills, `.claude/agents/art-director.md` and the new ROADMAP Phase 3 box.
10. **"ja":** oil and gas fields work as today's ore loop (§11).

The game's title stays "Treadline" (ADR 0006); the lead told Michael so, and he did not ask to
change it.

The decision below is unchanged by the acceptance except answer 1's name for the oil and gas bloc.
P68e wrote the answers into the text (the names; the options not taken are gone from §8, §10, §12,
§14 and §15), added the ADR sections the decision amends but the proposal did not list (ADR 0004
§6, the camera clamp; ADR 0007 §4 and ADR 0018 §4-§5, the strike and faction rules; ADR 0021 §1,
the P109 re-pin), added `touch-ui-rules`' description and line 66 (confirm and cancel in the
floating panel) to §15, and fixed four review points: the ellipse's semi-axes (§1, §3), the
Blackout Array's closest Command & Conquer analogue (§13), question 3's cost wording and the plan
lines that still said the perf arena is never re-pinned after P70.

## Decisions in short
| # | Topic | Decision |
| --- | --- | --- |
| 1 | Projection | Dimetric 2:1, `screen = ((gx - gy) x 32, (gx + gy) x 16 - z)` px; the sim keeps its square grid; one `IsoProjection` in `game/view/` replaces `ViewScale`'s position functions |
| 2 | Draw order | One y-sorted node (`WorldSort`) holds every unit rig and building at one z; sort key = the screen y of the ground point (units) or of the footprint centre (buildings); every footprint is square, which makes that key exact |
| 3 | Batching | Every sorted sprite is a region of **one per-match atlas** with team colours baked in and white modulate, so the sorted world is about one draw call; shadows and rings are rig children at lower z |
| 4 | Fog | On the ground (z 4), under the sorted world; only seen enemies are drawn; last-seen ghosts at z 5 with one dim; tracers clipped to seen tiles (kept from ADR 0022) |
| 5 | Picking | Inverse projection for ground taps; units first (kept); a unit is hit around its lifted centre, a building on its silhouette (diamond plus walls) |
| 6 | Camera | Pan and pinch unchanged, zoom 0.75 / 1 / 1.5 unchanged, the view centre's ground point clamped into the map's diamond; portrait unchanged |
| 7 | Minimap | Isometric diamond in a 2:1 box (the canvas's minimap) |
| 8 | Art | An in-repo generator (`tools/artgen/`, GDScript run headless) turns simple 3D models into SVG frames: vehicles and turrets 16 directions, infantry 8; buildings generated or hand-drawn; one light from the north-west |
| 9 | Team colour | Art keys its team zones in its faction's canvas triad; at match start the view rasterises each player's SVG text with the player's triad (`Image.load_svg_from_string`) into the atlas; 8 triads from the canvas |
| 10 | Factions | Two invented energy factions, the Derrick League (oil and gas) and the Lumen Accord (green energy), data only: `UnitDef.faction`, `FactionDef`, `ScenarioDef.factions`, one type column `type_faction`; a producer queues only its own faction's types |
| 11 | Roster | Per faction: HQ, power, refinery, barracks, vehicle factory, radar, defence, superweapon; rifle and anti-tank infantry, scout, tank, artillery, tanker (§7) |
| 12 | Hashes | Factions move no state hash (the perf arena loads no faction); strikes (§10) add hashed state with **one** re-pin |
| 13 | Economy | Oil and gas fields are the merged ore cells; tanker = harvester; data and view only |
| 14 | HUD | The canvas's floating panels in landscape (question 4 A, P85d); ADR 0019's tiles, queues and placement stay |
| 15 | Legal | Every canvas name screened (§13); hits replaced; no mobile base, no capture of neutral derricks, no freeze, no flamethrower infantry, no engineers in Phase 3 |

## Context
- **Michael's canvas.** "Iron Meridian - grafisk udkast" (Claude Design) has two versions. A: a
  science alliance against an industrial bloc, violet crystals. B ("Øst/Vest"): the same mechanics
  and camera, oil and gas from fixed fields, an east bloc (concrete, gas spheres, flares,
  pumpjacks, olive vehicles) against a west alliance (glass, wind park, solar, blue-grey vehicles,
  drones), tanker trucks as the obvious targets, team colour on bands. B's main board says it reads
  "Russia against Europe ... never said out loud". Its Spec board (§01-§10) fixes the projection,
  light, anchors, directions, sizes, render order, team-colour remap, export and touch rules. The
  artboard images are uploads that this ADR could not read; their alt texts, captions and the
  inline SVG (emblems, icons, HUD layout) were read from the `.dc.html` files. Lead note
  (2026-10-26): Michael then exported every artboard of both versions as PNG. The lead checked B's
  sheets against this ADR: clean flat-shaded vector, three tones per face, north-west light, which
  §5's generator reproduces. B's drawings still carry geography that decision 1 drops (a
  hyperboloid lattice tower for the superweapon and the radar, a domed hall with a colonnade,
  timber framing, a log cabin and a red wooden house on the map), as §6 already says. The PNGs
  stay out of the repo (an outside tool's renders, reference only); art-director gets them as
  mood reference with each art row.
- **Michael's four decisions (2026-10-26)**, after looking at the canvas:
  1. "Energi, ingen geografi": an oil and gas bloc against a green-energy alliance with invented
     names, B's look and materials, no Russia or Europe coding (no Vysotka, Panelka, Zavod,
     Strelok, Moroz, Veter, Raskat, Neftovoz, Voron, fur hats, Stalinist towers, panel blocks,
     timber framing), no flags, no stars, no real insignia, no copied real weapons.
  2. "Isometrisk 2:1 som canvas": the Spec board's camera. This replaces ADR 0022's projection
     (oblique buildings, top-down units), accepted the same morning (#186; its art P91b #190).
  3. "Asymmetri nu": each faction gets its own buildings, vehicles, infantry and superweapon in
     Phase 3 (the plan has one shared roster today).
  4. A new original app icon by art-director, in a separate lane (not this ADR).
- **State of `main` at 3d9e133.** Merged: the sim rows P69, P70, P70b, P70c, P71, P71b, P72 (six
  buildings and three new units, one shared roster), P73, P73b, P74, P75, P75b; core P81; UI P85
  and P85c (ADR 0019's sidebar zone, credits, power bar); art P91, P92 (top-down) and P91b
  (oblique buildings). Open: P78 `PlayerView` (#196), P76 outcome (`claude/p76-outcome`), P85b
  item tiles (running). Shelved: P84 (`claude/p84-buildings-view`, 817c90c). No building is drawn
  on `main`, and nothing in `game/sim` depends on the projection.
- **The view on `main`.** `ViewScale` converts milli-tiles to px (64 px per tile) for nine view
  and input files; `UnitLayer` draws one rig per row (`Ring`, `Hull`, `Team`, `Turret` sprites,
  rotated freely) at ADR 0012 §6's absolute z bands, one z per type and owner, because sprites at
  one z batch only while consecutive sprites share texture and modulate. ADR 0012's probe
  (Compatibility, Mesa llvmpipe): 150 sprites, one texture and one tint = 1 call; tints
  alternating = 150; three textures interleaved = 150; colour inside one `_draw()` does not break
  batches. Gate: `draw_calls_max` 60, the MultiMesh trigger at a forecast of 40, `work_p95_ms` 5.6
  (`data/dev/perf_gate.tres`).
- **The sim on `main`.** Types come from a scenario's spawns and `roster` in first-seen order
  (`WorldLoad._type_for`); type tables are out of the state hash and in `defs_hash`. A producer of
  each tab is found by `type_produces`; `QUEUE` checks the tab's producer, credits, slots and
  `requires` (`Production.apply_queue`). The perf arena (`data/scenarios/perf_arena.tres`) spawns
  `light_tank`, `rifle_squad` and `rocket_squad` only. Command types 15-19 are reserved.

## Decision

### 1. The projection
- **Formulas** (Spec §01; `gx`, `gy` in tiles, `z` in px at zoom 1):
  `screen_x = (gx - gy) x 32`, `screen_y = (gx + gy) x 16 - z`. From milli-tiles (1 tile = 1000):
  `px = (x - y) x 32 / 1000`, `py = (x + y) x 16 / 1000`. **Inverse** for a ground point:
  `x = (py / 16 + px / 32) x 500`, `y = (py / 16 - px / 32) x 500`, rounded to the nearest milli
  for a Command. A tile is a 64 x 32 diamond; a ground circle of radius `r` milli is a 2:1 ellipse
  whose horizontal semi-axis is `r x 32 x sqrt(2) / 1000` px and whose vertical semi-axis is half
  that (`ellipse_px(r)` returns the two semi-axes).
- **Where it lives.** `game/view/IsoProjection.gd` (touch-ux-dev): `ground_to_px(x, y)`,
  `px_to_ground(p)`, `cell_centre_px(col, row)`, `ellipse_px(r)`, the map's diamond and its
  bounding rect. It replaces `ViewScale.milli_to_px_vec` and `px_to_milli` at every caller
  (`UnitLayer`, `EffectsLayer`, `ProjectileLayer`, `HealthBarLayer`, `FogLayer`, `MapView`,
  `PlayerController`, `RtsCamera`, `perf_arena.gd`, `main_view.gd`); no other file holds 32 or 16.
  The view interpolates in grid space and projects; the projection is linear, so this equals
  interpolating projected points (ADR 0011 §2 unchanged).
- **Never rotated** (Spec §01). The sim, its square grid, its integers and every rule stay as they
  are; only drawing and input convert. `game/sim` gains no view concept.
- **Directions** (Spec §04): `d00` to `d15` in 22.5° steps, named so the canvas's names hold:
  `d_k` faces the grid angle `(k - 6) x 22.5°` measured from +gx towards +gy, so `d06` is +gx
  (south-east on screen, the canvas's default for the oil and gas bloc), `d10` is +gy
  (south-west), `d00` points up the screen and `d08` down it. Infantry uses the even ones. The
  view picks the frame from the heading it already computes (`round(angle / 22.5°)`, view-only
  float math).

### 2. Drawing: one sorted world from one per-match atlas
- **The world z table** (replaces ADR 0012 §6's bands and ADR 0022 §2's table; absolute z):

  | z | Layer | What |
  | --- | --- | --- |
  | 0 | `MapView` (bake, under the iso transform), `GroundLayer` (P116) | terrain diamonds |
  | 1 | `DecalLayer` | building cast shadows, craters, field stains, placement marks under the ghost |
  | 2 | rig child `Shadow` | unit cast shadows (one atlas, so one call) |
  | 3 | rig child `Ring` | selection rings as 2:1 ground ellipses |
  | 4 | `FogLayer` | fog on the ground, in diamonds |
  | 5 | `GhostMemoryLayer` | last-seen enemy buildings, one dim colour |
  | 10 | `WorldSort` (y-sorted) | unit rigs (`Hull`, `Turret`), buildings (with a defence's `Head`) |
  | 20 | reserved | air units (not Phase 3, §9) |
  | 30 | `HealthBarLayer` | bars, the building selection frame, offline glyphs |
  | 40 | `ProjectileLayer` | |
  | 50 | `EffectsLayer` | flashes, puffs, bursts, tracers (clipped, §2 "Fog") |
  | 60 | `GhostLayer` (P86) | placement ghost |
  | 61 | `RallyLayer` (P87) | rally flags and lines |
  | 70 | `MoveMarkerLayer` | move and target marks |

- **Sort key.** `WorldSort` is a `Node2D` with `y_sort_enabled`; the engine sorts its children by
  their y in C++ every frame. A unit rig stands at its projected ground point. A building node
  stands at its **footprint centre's** projected point (y = `(c + r + n) x 16` px for an n x n
  footprint at origin (c, r)) and offsets its sprite by the art's anchor (Spec §03: the art's
  origin is the footprint's back corner, 16 x n px above the centre). The Spec's "gx + gy of the
  front corner" is **not** used: it puts a unit standing against a building's east or south wall
  behind that wall.
- **Why the centre is exact.** Units never enter a footprint (ADR 0017 §1). For an n x n footprint
  a unit east of it (`ux >= c + n`, rows overlapping) has `ux + uy - (c + r + n) >= uy - r > 0`, so
  it sorts in front, which is right; a unit south of it likewise; a unit north or west sorts
  behind. Two square footprints whose screen columns overlap are separated along one grid axis, and
  the same sum puts the southern or eastern one in front. Only a unit centred within half a tile of
  a footprint's east or west corner tip can sort wrongly, by a few px at the tip. **Every footprint
  is therefore square**: a data test in the roster rows (P107, P108) pins it; the canvas's 3x2
  refinery becomes 3x3 with its dock inside the drawing (the merged dock cell (1, 3) of P72 stays).
- **Rigs v2** (P114). A rig is a `Node2D` in `WorldSort` with children `Shadow` (z -8 relative,
  absolute 2), `Ring` (absolute 3, made on first selection as today), `Hull` and, for a turreted
  type, `Turret` (both relative 0). Each is a `Sprite2D` with `region_enabled` on the one atlas;
  the region changes only when the 16-step direction index changes (hull from the move heading,
  turret from the aim bearing, as `UnitLayer` computes them today). There is no `Team` node: team
  colour is in the atlas. The turret's offset per hull direction comes from the sheet metadata
  (the mount projects differently in each direction). A squad is one rig whose frame shows its
  three figures (Spec §05).
- **Buildings** (P115): one `Sprite2D` per building row in `WorldSort` (static, redrawn on
  `rows_version` only), a defence's turning `Head` as a child; its cast shadow is a sprite in
  `DecalLayer` (z 1), so units in front of it stand on it. Damage states and animations
  (pumpjacks, flares, rotors) are not Phase 3: a damaged building looks intact, and a destroyed one
  leaves a crater decal (P105's art, drawn by P115).
- **Batching.** Everything in `WorldSort` uses one texture and white modulate, so its whole sorted
  list is one batch however types, owners and depths interleave (the probe's "one texture, one tint
  = 1 call" for 150 sprites). The shadows at z 2 are another call, the rings at z 3 another.
  Anything that would tint a sorted sprite individually is not allowed: a low-power dim would
  split the batch at every dimmed building (up to `2k + 1` calls for `k` buildings), so **low power
  shows a glyph on each consuming building** instead of a dim (P89; question 7), and last-seen
  ghosts draw in their own layer (z 5) with one shared dim colour.
- **Draw-call forecast** (base arena, both factions): ground 1, fields and props 1, decals 1, unit
  shadows 1, rings 1, fog 1, ghosts 1, sorted world 1, bars 1, glyphs 1, projectiles 1, effects 2 =
  **13**, against the trigger of 40 and the ceiling of 60 (ADR 0022's was 32). The number of
  atlas pages is the one risk: a second page interleaved in the sort would split batches, so a
  match has **exactly one page** for the sorted world (next item). P114 counts the calls with
  ADR 0012's llvmpipe method (a count, not a timing) and the phone card confirms them.
- **The per-match atlas** (P113, `IsoAtlas`, built on the shelved P84's `RuntimeAtlas`). At match
  start, on the main thread, for each player: read the SVG text of every frame of the player's
  faction (`FileAccess`; the iso art imports as "Keep File", §5), replace the faction's key triad
  with the player's triad (three exact hex strings), rasterise with
  `Image.load_svg_from_string(text, bake_scale)`, and shelf-pack into one RGBA8 `Image` with the
  2 px gutter of ADR 0022; upload once as an `ImageTexture`. Estimate of the page at `bake_scale`
  1.0 on 2x-authored art (1 tile = 128 x 64 texels):

  | Item | Texels (estimate) |
  | --- | --- |
  | turreted vehicle: 16 hull frames 128x128, 16 turret 96x96, 16 shadows 128x64 | 540 K |
  | tanker: hull and shadows | 393 K |
  | infantry squad: 8 frames 96x64, 8 shadows 96x48 | 86 K |
  | 3x3 building 384x492 (Spec: up to 150 px high at 1x) plus shadow | 263 K |
  | 2x2 building 256x328 plus shadow | 117 K |
  | 1x1 defence with 16 heads 64x64 | 98 K |
  | one faction (3 turreted, 1 tanker, 2 squads, 4 3x3, 3 2x2, 1 1x1) | about 3.7 M |
  | with gutters and shelf waste (x 1.3) | about 4.8 M |
  | a two-player match | about 9.6 M, one 4096 x 4096 page or less (at most 64 MB RGBA8) |

  If the packed page would pass 4096 on a side (more players, more types), the bake lowers
  `bake_scale` for that match until it fits one page; the web preview may start at 0.75. The CPU
  `Image` is dropped after the upload except in tests, which read it (`image()`, the FogLayer
  rule). Bake time is an estimate (about 230 frames per player; if one small polygon SVG takes 1 to
  3 ms on the gate phone, 0.25 to 0.7 s per player); P113 adds `atlas_bake_ms` to the phone card's
  report (report-only, no new threshold).
- **Per-frame work.** Per rig: one position write (as today) and a region write only when a
  direction index changes; today's rig writes a position and three rotations every frame. The
  sort runs in the engine. Buildings and their shadows are static. So the main-thread view work
  per frame should not exceed today's; the phone card's `work_p95_ms` 5.6 judges it.
- **Fog** (amends ADR 0010 §2). `FogLayer` keeps its texture (one RGBA8 texel per cell, linear
  filtering, alpha 255 / `explored_alpha` / 0, the dirty-list patching) and draws it under a
  `Transform2D` whose axes are (32, 16) and (-32, 16) px per texel, so each texel is a diamond and
  the soft edge runs along the diamonds. It lies **on the ground** (z 4): over terrain, decals,
  shadows and rings, under every object. This is right in iso: a tall building's upper part lies
  over the cells behind it, and fog drawn over objects would black out the top of a seen building
  standing in front of unexplored ground. Objects need no fog of their own: enemy rigs, buildings,
  bars and projectiles are drawn only where the local player sees them (ADR 0010 §2's hiding,
  unchanged), own rows always stand on seen cells, and last-seen ghosts carry the dim at z 5. A
  building partly in vision is drawn whole as seen (ADR 0022's seam goes). Effects (z 50) are
  above the fog, so **the tracer clip of ADR 0022 §4 stays** (the shelved P84's `EffectsLayer`
  change and its `test_fog_hiding.gd` cases are reused in P117b).
- **Health bars** sit above each sprite: the ground point lifted by the sheet's `bar_lift_px` (the
  frame's top) plus a gap; `VEHICLE_REACH_PX` and `INFANTRY_REACH_PX` give way to the sheet. A
  selected or hit unit behind a building is hidden by it, and its bar still shows (ADR 0022
  question 1, kept).
- **Projectiles and effects** draw at the projected ground point lifted by the shooter's muzzle
  height from the sheet; shells fly straight in Phase 3 (arcs are Phase 5 polish).

### 3. Picking, selection and placement
- **Ground taps:** `IsoProjection.px_to_ground` of the camera's world point, rounded to milli.
- **Units first** (ADR 0022 §3's order kept): with a selection enemy unit > own unit > enemy
  building > own building, without one own unit > own building. A unit is hit within its pick
  radius of its **lifted centre** (the ground point raised by the sheet's `pick_lift_px`, half the
  frame's visible height), the radius the larger of 24 dp (48 dp across, Spec §09's 44 pt is
  smaller) and the horizontal semi-axis of the selection radius's ellipse (§1). Infantry is
  picked as a squad (one row).
- **A building** is hit on its silhouette: the footprint diamond plus the rectangle between the
  diamond's left and right corners from the sprite's top to the corners' y; at least 48 dp a side
  at zoom 0.75. Among overlapping buildings the larger sort key wins (it is drawn in front).
- **Selection:** a unit's ring is a 2:1 ground ellipse (art-director redraws the ring texture as an
  ellipse with an even stroke); a building's frame is four brackets round its silhouette box
  (ADR 0022 question 2 = A, kept).
- **Placement ghost** (amends ADR 0019 §2): the footprint's cells are marked as diamonds on the
  ground (wash, hatch and frame as diamond tile quads from one texture, per cell, in `GhostLayer`),
  then the building's sprite faded over them; the tile under the reference point is
  `floor(px_to_ground)`; the ghost still follows the finger 64 dp above it; the grab area is the
  silhouette plus 24 dp. The rest of ADR 0019 §2 is unchanged.

### 4. Camera, portrait and minimap
- **Clamp to the diamond** (amends ADR 0004 §6 as `RtsCamera` implements it): after every move or
  zoom the view centre's ground point is clamped into `[0, map_w] x [0, map_h]` milli and projected
  back; the `limit_*` values are the diamond's bounding rect grown at the top by the tallest
  sprite's height (so a building on the back edge is not cut, ADR 0022's open point). Outside the
  diamond the clear colour shows (an STYLE.md "off-map" colour). Pan, pinch, two-finger pan, the
  three zoom levels 0.75 / 1 / 1.5 (`data/input_settings.tres`, equal to Spec §09's range) and the
  snap are unchanged.
- **Portrait** (ADR 0015): unchanged. A turn keeps the world point at the centre and the world size
  per dp; the clamp above works in both orientations. A 64 x 64 map is a 4096 x 2048 px diamond.
- **Minimap** (amends ADR 0019 §4; P88): an **isometric diamond** in a 2:1 box, as the canvas draws
  it (HUD board: a 148 x 86 panel). It is one cell texture at fog cadence drawn with the same skew
  as the fog, so the camera's frame is a plain rectangle on it. A plan view was rejected: its
  camera frame would be a turned quadrilateral and its north would not match the screen's.

### 5. Art pipeline
- **Rule kept:** only SVG authored in this repository (CLAUDE.md, Legal). The canvas images are a
  reference only; art-director re-authors everything.
- **The generator** (`tools/artgen/`, GDScript run by the pinned Godot headless through
  `bash scripts/gen-art.sh`; owner art-director; Spec §10). An `ArtModel` resource per art id
  (`assets/art/models/<faction>/<type_id>.tres`) lists simple primitives (box, wedge, cylinder,
  frustum, sphere as a polygon ring) with a size, a position, a part (`hull`, `turret`, `head`) and
  a material key (a palette tone or a team tone). For each of the 16 yaws (8 for infantry) the tool
  projects the primitives with §1's formulas, culls back faces, orders faces back to front, shades
  them with the one light (Spec §02: top lightest, left side middle, right side darkest, a thin
  light edge on top edges), and writes one SVG per frame using only the elements STYLE.md allows
  (polygons, a `g` with group opacity). It also writes the cast shadow frame (each primitive
  projected onto the ground away from the light, Spec §02: black at 35 % opacity as one group,
  length about 0.8 x the height) and an `IsoSheetDef` per art id (frame boxes, anchors, the turret
  mount per hull frame, `bar_lift_px`, `pick_lift_px`, `muzzle_lift_px`). Output is deterministic
  (fixed decimals, fixed order): a `tests/art` case regenerates every model in memory and fails on
  any difference from the committed files (the gdformat pattern). Floats are fine there: the tool
  is not the sim.
- **Buildings** may be generated, hand-drawn in the projection, or generated with a hand-drawn
  detail overlay (signage, pipes, stripes) in the same canvas; whichever the art row chooses, the
  light, the anchor (Spec §03) and the canvas rules are the same and `tests/art` pins them. Item
  icons for the build cards are emitted by the generator from the default frame (`d06` for the
  oil and gas bloc, `d10` for the green alliance, Spec §04) on the canvas's faint iso grid.
- **Blockouts first.** P99 commits a blockout model (boxes sized by footprint or size class, a team
  band) for every Phase 3 type of both factions, so every view row builds against real frames,
  names and metadata from the start; the art rows (P101-P105) replace the models, not the names.
- **Files and naming** (Spec §08, adapted to folders): `assets/art/iso/<faction>/<category>/
  <type_id>_<part>_d<NN>.svg` (`category` `veh`, `inf`, `bld`, `fx`; `part` `hull`, `turret`,
  `head`, `shadow`), e.g. `assets/art/iso/fossil/veh/heavy_tank_hull_d06.svg`; a building has one
  view, so its body and shadow carry no direction (`.../bld/refinery_hull.svg`); one `.import` per
  file with the "Keep File" importer, so the export carries the SVG text the bake reads and no
  unused texture; `assets/art/iso/index.tres` maps each `type_id` to its sheet. Ground tiles, field
  stages and props stay normal imports (`assets/art/svg/ground/`, `.../fields/`), which P116 packs
  into the ground's atlas; the ring and the UI icons stay normal imports too. Internal faction ids are `fossil` (oil and gas) and `renew`
  (green energy); they never show in the game.
- **Team colour** (Spec §07). Each faction's art paints its team zones only in its key triad:
  oil and gas `#FF9446 #E8681F #B04B12`, green `#62D6EE #1FA6C8 #137C99`. The bake replaces those
  six exact hex strings and nothing else.
- **The key band** (a `tests/art` check on the SVG text of each faction's frames). A colour other
  than the three key colours is in its faction's key band when its HSV hue lies within 20° of the
  hue of any of the three (oil and gas: 21.6° to 25.3°, so 1.6° to 45.3°; green: 190.3° to 193.0°,
  so 170.3° to 213.0°) **and** its HSV saturation is at least 0.30. No colour in the band is
  allowed, so nothing but a team zone reads as team colour in the default pairing. Greys and muted
  materials (saturation below 0.30) are allowed at any hue. The rule wins over the canvas's
  palette: §6's four colliding entries are changed there. The band guards the key triads only;
  how the art reads with the other six triads is the gallery's check (every type in two triads,
  P99) and art-director's in the art rows, not a test.
- **Triads.** Players take any of the canvas's eight triads (light, mid, dark):

  | Name | Triad |
  | --- | --- |
  | Signal | #FF9446 #E8681F #B04B12 |
  | Arktisk | #62D6EE #1FA6C8 #137C99 |
  | Karmin | #F26A5E #CF3A2E #922219 |
  | Kobolt | #7AA2F7 #3F6FE0 #27479E |
  | Guld | #FFDA6B #E6B52E #A47D13 |
  | Magenta | #F083CF #C9439F #8C2A6E |
  | Sne | #FFFFFF #DCE2E6 #A3ACB3 |
  | Kul | #6E737A #44494F #26292D |

  Defaults: player 1 Signal, player 2 Arktisk (question 8); a mirror match keeps them, so both
  sides of one faction still differ. Team colour covers about 8-12 % of a sprite as bands, cranes,
  stripes and light strips (ADR 0022 question 3, kept).
- **Where atlases are built:** at match start (§2), from the SVG text, not in CI and not at import.
  Godot's own import of the ground, field and UI SVGs is unchanged. Nothing is generated in CI
  except the staleness check, which runs inside `tests/art`.
- **Gallery and tests.** The art gallery shows every type of both factions in all directions, in
  two team triads, on grass and sand at zoom 0.75, 1 and 1.5, with a tank in front of and behind
  each building (through the same `IsoAtlas` bake, so the gallery shows exactly what a match
  draws). `tests/art` pins: canvases and anchors per footprint, directions complete (16 or 8),
  allowed elements and size limits, the key band (§5), determinism and staleness, the sheet
  metadata against the frames, and the square-footprint art. Today's top-down unit files, P91b's
  oblique buildings and their pages stay on `main` as reference until the art rows replace them;
  the row that replaces a set deletes it and its gallery page.
- **Out of Phase 3:** @3x atlases (Spec §08; at zoom 1.5 on the gate phone a 2x texel covers about
  1.1 physical px), building damage states and animations, terrain transition tiles (Spec's
  "overgangsfliser"; Phase 3 ground tiles are per-terrain diamonds with variants a and b and a
  soft rim), new fonts (the canvas's Big Shoulders and Chakra Petch are SIL OFL, which CLAUDE.md's
  asset rule does not allow without a change).

### 6. Factions: names, look and data
- **Names** (Michael's answer 1; screened in §13): the **Derrick League** (the oil and gas bloc;
  internal `fossil`) and the **Lumen Accord** (the green-energy alliance; internal `renew`). The
  proposal's "Iron Compact" (§13: the Iron Curtain, the Warsaw Pact) and Version A's "Aurora Accord"
  ("Aurora" is a Command & Conquer: Generals unit) are not used. No geography, no
  Cold War: the canvas's "1986 retro-futuristic Cold War" and "East against West" framing goes;
  the world is two energy blocs. The game's title stays "Treadline" (ADR 0006); "Iron Meridian" is
  the canvas's working title only.
- **Look.** Derrick League: poured concrete, riveted steel, rust, olive drab vehicles, gas spheres,
  flare stacks, pumpjacks, pipe racks, warning stripes, amber lamps; wedges and trapezoids (A's
  form language). Lumen Accord: white ceramic, graphite, glass, blue-grey vehicles with dark
  patches, wind turbines, solar panels, battery banks, drones, cyan status light; hexagons and
  rounded panels. Dropped from B as geography: red brick with copper patina and stucco, spires and
  tiered towers, panel blocks, hyperboloid masts, fur hats and long coats, domes with colonnades,
  timber framing, snow-and-birch as one side's home; from A: the cryo theme (§13).
- **Palettes** (starting values from the canvas; art-director owns them in STYLE.md): Derrick League
  gun steel #6B7366, concrete #9F9A8E, weathered rust #6E5D50, dark iron #3B3F39, lamp warm white
  #FFF1D6, olive #7D8562; Lumen Accord ceramic #D5DBDC, graphite #414A51, titanium #8A9398, glass
  #B4C8CF, blue-grey #7D8B96, status light mint #A8F5B0. Four canvas entries fall in their
  faction's key band (§5) and are changed: rust #8E5A38 (hue 23.7°, saturation 0.61) and lamp
  amber #FFC45C (38.3°, 0.64) against the oil and gas key (21.6°-25.3°); glass #8AD6E6 (190.4°,
  0.40) and status light #9BF6FF (185.4°, 0.39) against the green key (190.3°-193.0°). The
  replacements are muted (rust 0.27, lamp 0.16, glass 0.13 saturation) or outside the band and
  every triad's hue (mint, 126°). Every other entry has a saturation below 0.30. Terrain: a
  neutral temperate set (grass, dirt, sand, scrub, rock, water) as today's terrain ids.
- **Emblems** (art-director, P103 and P104): Derrick League starts from A's octagon with an I-beam
  and four rivets (no star, no letter); Lumen Accord from A's hexagon with horizon arcs, but with a
  three-blade rotor in place of A's four-pointed sparkle (a star shape, which decision 1 excludes).
  No flag, star, wreath, crest or real insignia.
- **Data model** (P106, gameplay-dev; the sim rule is one condition):
  - `UnitDef.faction: StringName` (empty = any faction; buildings inherit it through
    `BuildingDef`). `World.faction_ids` (an `Array[StringName]` like `type_ids`, first-seen order)
    and `type_faction` (a new `TYPE_ARRAYS` column: the index into `faction_ids`, -1 for none).
    `defs_hash` feeds both, so a replay against other faction data fails as today.
  - `FactionDef` (`game/sim/defs/`, files `data/factions/fossil.tres`, `renew.tres`): id, display
    name, emblem art id, key triad and its roster (`Array[UnitDef]`); no AI reference (the sim
    names nothing in `game/ai`): the dummy of a faction is `data/ai/dummy_<faction>.tres`, which
    the Skirmish route puts in `MatchRunner.opponents` (P83d, P90).
    `ScenarioDef.factions: Array[FactionDef]` indexed by player (entry 0 unused); `WorldLoad`
    registers every listed faction's roster after the spawns, as it does `roster` today.
  - **The rule:** `QUEUE` is dropped and counted when the item's faction is set and differs from
    the faction of the producer the queue uses (`type_faction[type] != type_faction[producer]`).
    No per-player faction state exists: a player's faction is the faction of what it owns, so
    `PLACE`, power, harvest and the outcome need no change. A data test pins that every buildable
    type has a faction and that every `requires` chain stays inside its faction and reaches its HQ.
  - **Determinism and hashes:** `type_faction` and `faction_ids` are type data, outside the state
    hash; no row, player or map array changes; loops and orders are unchanged. The perf arena's
    scenario lists no faction and its three unit files keep every sim field (only their faction
    and display names change), so **its golden hashes and `TICK_0_SEED_1` stay bit-identical**;
    its `defs_hash` changes, which nothing pins. `MatchSnapshot` copies `type_faction` and lists
    `faction_ids` beside `type_ids`: two list entries, two member declarations and two capture
    lines in the lead's `MatchSnapshot.gd`, plus the `ID_LISTS` literal of the lead's
    `tests/core/test_match_snapshot.gd` (the plan's named exception 17); P109's strike arrays
    follow under exception 18 (eight copied with members and capture lines, three in
    `NOT_COPIED`).
  - The view and the UI read the local player's faction from `runner`'s scenario
    (`factions[local_player]`); the build menu lists the types of that faction only; the Skirmish
    route gives the dummy its faction's `AiDef`.

### 7. The asymmetric Phase 3 roster
Derrick League keeps the twelve merged files (ids, sim numbers, P72's tests) and adds two; Lumen
Accord gets fourteen new files. Display names are Michael's (answer 2); sizes are footprints;
numbers marked P are proposals for Phase 4's balance runs, stored in `data/` only.

| Role | Derrick League: id, name | Lumen Accord: id, name | Asymmetry (P) |
| --- | --- | --- | --- |
| HQ 3x3 | `headquarters`, Rigworks | `renew_hq`, Grid Hub | same role |
| Power 2x2 | `power_plant`, Turbine Hall | `renew_power`, Wind Park | Wind Park cheaper (250), less power (+80) |
| Refinery 3x3 + dock | `refinery`, Cracking Plant | `renew_refinery`, Synthesis Works | same loop |
| Barracks 2x2 | `barracks`, Bunkhouse | `renew_barracks`, Crew Hall | same role |
| Vehicle factory 3x3 | `vehicle_factory`, Heavy Yard | `renew_factory`, Motor Works | same role |
| Radar 2x2 (new) | `fossil_radar`, Signal Mast | `renew_radar`, Relay Tower | tech gate for artillery and the strike (800, -30) |
| Defence 1x1 | `defence_turret`, Redoubt | `renew_defence`, Rail Battery | Redoubt anti-infantry gun, Rail Battery anti-vehicle |
| Strike 3x3 (new) | `fossil_strike`, Deep Bore | `renew_strike`, Blackout Array | §10 |
| Rifle infantry | `rifle_squad`, Roustabouts | `renew_rifle`, Linemen | Linemen faster (1.1 tiles/s), 80 hp |
| Anti-tank infantry | `rocket_squad`, Wildcatters | `renew_rocket`, Breakers | Breakers longer range (5.5) |
| Scout | `light_tank`, Flarejack | `renew_scout`, Swift | Swift 2.2 tiles/s, 220 hp |
| Tank | `heavy_tank`, Bullhead | `renew_tank`, Torque | Torque 1.4 tiles/s, 520 hp |
| Artillery | `artillery`, Mortar Rig | `renew_artillery`, Arcline | Arcline range 10, 160 hp |
| Tanker | `harvester`, Tanker | `renew_tanker`, Fuel Runner | Fuel Runner faster (1.4), carries 450 |

Character (canvas A's, kept): Derrick League heavy, robust, slow; Lumen Accord fast, precise,
fragile. Every footprint is square. `requires`: each faction's chain mirrors P72's (power after
HQ, refinery after power, barracks after power, factory after refinery, defence after barracks);
the radar after the refinery; artillery and the strike after the radar (P107 moves the merged
artillery's `requires` and P72's data test with it; the perf arena has no artillery). Infantry
squads keep three figures per row.

### 8. Mechanics in the canvas that the sim does not have
| Mechanic | Phase | Why | Rows, size |
| --- | --- | --- | --- |
| Asymmetric rosters (§7) | 3 | decision 3 | P106 sim 120; P107, P108 data (.tres) |
| Radar building | 3, as a tech gate only | data only; a radar that unlocks the minimap is C&C's (TD, RA) | data |
| Superweapons, one per faction | 3 (question 3 A) | decision 3; no kernel touched (§10) | P109 220, P110 250, P111 180, P112 350 + P112b 150 |
| Oil and gas fields with three stages | 3, on the ore loop | §11; data and view only | P116 (view) |
| Tanker trucks | 3, as the harvester | §11 | data, P84b cue |
| Pumps or wellheads built on a field (2x1) | later (Phase 4 economy, its own ADR) | a new income rule, a non-square footprint | - |
| Capturing a neutral derrick with an engineer | dropped | Red Alert 2 and Generals' oil derricks, C&C 3's Tiberium spike (§13) | - |
| Engineers (repair, capture), sappers | dropped in Phase 3 | C&C's Engineer (§13); repair stays out of scope | - |
| Air units, anti-air, drones in the air | later (after Phase 4; GDD: not in version 1) | a new movement class through flow, targeting and two kernels | ~1500 lines + kernels |
| A mobile base that unfolds into an HQ | dropped | C&C's MCV (§13) | - |
| Freeze, cryo units | dropped | Red Alert 3's cryo weapons (§13) | - |
| EMP on units | not Phase 3 | would stop movement and fire inside the INTEGRATE and TARGETING kernels (ADR 0013 twin rule); the blackout acts on buildings only | - |
| Seismic strike | 3, as the Deep Bore | damage in GDScript | in P110 |
| Pipelines (destroyable, repairable) | later or dropped | a new map object and income rule | - |
| Bridges that blow up and are rebuilt | later (Phase 5 maps) | terrain change rules; rebuilding by engineers is RA2's | - |
| Houses infantry can occupy | dropped | Red Alert 2's garrisons | - |
| Plateaus with height advantage, forest cover, an ice ford for infantry | later (Phase 5 maps) | terrain rules; the ford is data (per-class cost) | data later |
| Veterancy, primary building, sell and repair buttons, guard, patrol, formations | out of scope | the plan's out-of-scope list; sell and repair stay out | - |

### 9. Air units and anti-air: not Phase 3
They need a movement class through FLOW, INTEGRATE and TARGETING (two kernels with their twins,
ADR 0013 §5) and the GDD keeps them out of version 1; a later ADR decides them. The z table
reserves 20 for them.

### 10. Superweapons (question 3 A: in Phase 3)
- **State** (P109, one layout row, like P70): `ROW_ARRAYS` + `ready_tick` (the tick a strike
  building may fire, 0 for every other row) and `offline_until` (the tick a blacked-out building
  comes back, 0 = on); `PLAYER_ARRAYS` + `strike_x`, `strike_y`, `strike_tick` (one pending
  rupture per player, 0 = none). `TYPE_ARRAYS` + `type_strike_kind` (0 none, 1 rupture,
  2 blackout), `type_charge_ticks`, `type_strike_radius`, `type_strike_delay`,
  `type_strike_ticks` (the blackout's length) and `type_strike_weapon` (a `WeaponDef`, so damage
  uses `weapon_vs_armour`), all from `BuildingDef` exports. `STATE_FORMAT` 4. **This is the one
  re-pin of revision 5:** the perf arena's units behave bit-identically, but its hash now feeds
  two more row columns and three more player arrays, so `golden_hex`, `TICK_0_SEED_1` and
  `KNOWN_FORMATS` are re-pinned in P109 under the Phase 2 plan's exception 10, with this reason;
  P65q's byte line moves once and stays constant afterwards.
- **Command** `SUPERWEAPON = 15` (fixes ADR 0007 §5's reserved 15; ADR 0017 §4's common rules):
  `target_id` an own strike building, `target_x`, `target_y` the point; payload empty. Valid when
  the player is playing, the building is the player's, `type_strike_kind` > 0, `world.tick + 1 >=
  ready_tick` and the building is not offline. Firing sets `ready_tick` to `tick + 1 +
  type_charge_ticks`. A placed strike building starts charging when placed. Low power does not
  pause the charge in Phase 3 (a Phase 4 balance question).
- **Rupture** (Deep Bore): firing writes the player's pending strike, `strike_tick = tick + 1 +
  type_strike_delay` (P: 45 ticks, a 3 s warning that every player sees); on that tick every row
  (own rows included) within `type_strike_radius` (P: 3000 milli) of the point, in ascending id, loses the weapon's
  damage times its armour percent (P: 600, buildings 100 %). The damage lands in FIRE (next item),
  so a ruptured row dies at that tick's REMOVE exactly like a row killed by a shot.
- **Blackout** (Blackout Array): at once, in the command's apply (COMMANDS, one pass over the rows
  in ascending id), every building not owned by the firing player within
  `type_strike_radius` (P: 4000) gets `offline_until = tick + 1 + type_strike_ticks` (P: 450,
  30 s). While offline: `Power.run` counts neither its output nor its use; `Combat.fire` skips it
  (P74's offline rule, widened); `Production.run` does not advance a queue whose producer is
  offline. Units are not affected.
- **Where it runs:** a new `Strike.gd` module. `Strike.apply_superweapon` is the command's apply
  (COMMANDS). `Strike.run(world)` applies a pending rupture on its `strike_tick`; `Sim.step` calls
  it right after `Combat.fire` and before `FogUpdate.begin` and `world.remove_dead()`, inside the
  FIRE mark (no new probe phase, ADR 0017 §5 and its rejection of phases between FIRE and REMOVE
  hold). Consequences, the same as for a shot that kills in FIRE: the ruptured rows are removed at
  that tick's REMOVE (`FogUpdate.begin` has already run, so `remove_dead`'s unstamp lands in the
  right dirty lists, ADR 0010 §1), `rows_version` moves, ECONOMY's `Power.run` rebuilds
  `building_rows` and sums power without them, and PRODUCTION's `Outcome.run` sees a ruptured
  producer gone, so **a rupture's kills count for defeat on the same tick** and no ruptured row
  takes part in the next tick's COMMANDS, TARGETING, movement phases or FIRE. Rejected: `Strike.run` in
  PRODUCTION with a second `remove_dead` there (it would unstamp after this tick's FOG update and
  after `Power.run` summed the totals) and in PRODUCTION without one (`Outcome._owns_producer`
  walks `building_rows` without an hp check, so the kills would count a tick late and the dead rows
  would act through the next tick). Event cadence; at most one pass over the rows per strike,
  aliased arrays, no allocation. No kernel changes: damage and the offline flag are written in
  GDScript, and `Strike.run` is its own call after `Combat.fire`, so a later FIRE port (whose
  dispatch is the first line of `Combat.fire`, ADR 0013 §3) leaves it in GDScript.
- **Proposed numbers (P):** both strike buildings cost 2500 and use 60 power; charge 4500 ticks
  (5 min of a match of 8-10 min). The dummy builds no strike building and never fires (ADR 0020
  §4 unchanged); Phase 4's AI uses them.
- **View and UI** (P112): a strike button with a charge ring in the HUD, a targeting mode (tap the
  map, confirm), the warning marker for every player during the delay, the rupture crater decal and
  a blackout overlay (the offline glyph over each affected building, no tint, §2).

### 11. Economy: oil and gas fields on the merged ore loop
- **Mapping:** a field is the merged ore cells (`ore_cell`, `ore_amount`, `ore_cell_max` 20,
  `ore_regrow_ticks` 150); the tanker is the harvester (`harvest_capacity`, SEEK, MINE, RETURN,
  UNLOAD, `HARVEST`, auto-resume); the refinery and its dock are unchanged. **No sim change**, no
  rule value change, so no hash moves. Internal names (`ore`, `harvest_*`) stay; every
  player-facing word says oil, gas, field, tanker.
- **Three stages** (B's full, half, dry) are view-only thresholds on `ore_amount` (P116): full above
  two thirds of `ore_cell_max`, half above one third, dry below; dry fields refill slowly, as ore
  regrows today (B's "fixed fields" become "fields that recover", a Phase 4 balance question).
- **Oil or gas** is a view-only choice per field: `MapDef` gains `field_kinds` (a view export that
  `WorldLoad` does not read; no digest change) or, without it, a fixed function of the field's
  first cell. A neutral wellhead prop stands on a field (decor, not a row). Both kinds pay the same.
- **HUD icons** (B's Resources board): credits as a barrel with a flame, oil as a dark drop, gas
  as a blue flame.

### 12. HUD (question 4 A)
- **Kept from ADR 0019:** the item tiles and their states, tap to queue, long-press to cancel,
  ready structures and placement mode, the power bar, the three tabs (Structures, Infantry,
  Vehicles; no separate Defense or Air tab), the portrait bottom band (ADR 0015 §5) and every dp
  rule. P85, P85c and P85b keep their code.
- **Decided (A): the canvas's own layout in landscape.** The build panel becomes a floating
  panel at the bottom right (canvas HUD board: 372 x 130 at 932 x 430, one row of 68 dp cards with
  the item's name always shown, tabs as line icons above it), the minimap a floating panel at the
  top right, credits and power a pill at the top left; the map fills the rest. Portrait keeps the
  band (the canvas's portrait board puts the same panel at the bottom). One row, P85d (about 250
  lines), before P86 and P88, which then build against it. Why: Version A's own legal note ("our
  own UI: a map rail and floating panels instead of a fixed sidebar"); a right-hand column with
  the minimap on top, credits, tabs and build icons below is the Command & Conquer and Red Alert 2
  sidebar layout; and landscape gains map width.
- **Not taken (B):** keep ADR 0019's right zone in landscape, restyle it with the canvas's cards
  and icons only, and revisit the layout in Phase 5. Cheaper at first, but P86's buttons and P88's
  minimap would have moved again later.
- **Not taken from the canvas HUD:** the command buttons (attack-move, guard, stop, patrol,
  formation), sell and repair, the Air tab, rank chevrons, the "PRIMARY" label: out of scope or
  too close to Red Alert 2's sidebar buttons (§13).

### 13. Legal screen
Screened against Command & Conquer (Tiberian Dawn, Red Alert 1-3 and expansions, Tiberian Sun and
Firestorm, Renegade, Generals and Zero Hour, C&C 3 and Kane's Wrath, C&C 4) and other well-known
RTS games (StarCraft I-II, Warcraft III, Age of Empires II-III, Company of Heroes, Halo Wars, Dune
II and 2000, Starship Troopers: Terran Command), from the architect's knowledge; a "no known hit"
is not a trademark search (ADR 0006's Phase 7 search covers the store title; the lead adds the
faction and unit names to it). Generic military or industrial words may stay as words, but no
display name equals a C&C unit or building name. Decision 1 (no real weapons, no national coding)
adds a second screen: no display name equals the name of a real military vehicle, aircraft, ship or
weapon programme, in service or recent (from the architect's knowledge; the lead's trademark list
gets these names too). The table records that screen in its Jackal and Trebuchet rows and in
its three name-list rows, for every name this ADR uses.

| Canvas name or concept | Where | Finding | Decision |
| --- | --- | --- | --- |
| Aurora Accord | A | Aurora bomber (Generals Zero Hour) | replaced: Lumen Accord |
| Iron Compact | A | no exact hit, but it evokes the Iron Curtain (Red Alert's superweapon) and the Warsaw Pact, and it named the bloc that carried Version B's east look, which decision 1 drops | replaced: Derrick League (Michael's answer 1, 2026-10-26) |
| Iron Meridian | A | no known hit | not used; the title stays Treadline |
| Meridium crystals, regrowing | A | harvested glowing crystals = Tiberium (TD, TS, C&C 3), RA's gems | replaced by B's oil and gas |
| Forge, Forge Rig | A | StarCraft Protoss Forge; the rig is an MCV | replaced: Rigworks; no mobile base |
| Nexus, Nexus Carrier | A | StarCraft Protoss Nexus (main base); MCV | replaced: Grid Hub; no mobile base |
| Extractor | A | StarCraft Zerg Extractor (a gas building), C&C 3 Scrin Extractor | replaced: Synthesis Works |
| Fusion Core | A | StarCraft II Terran Fusion Core | replaced: Wind Park (B) |
| Sensor Array | A | Tiberian Sun Firestorm's Mobile Sensor Array | replaced: Relay Tower |
| Frostfall Array, Cryo Trooper, Winter Engine (freeze) | A, B | Red Alert 3's cryo weapons (Cryocopter, the Allied Cryoshot) | dropped |
| Ranger | A | RA1 Ranger (jeep), Generals Ranger (infantry) | replaced: Linemen |
| Seeker | A | C&C 3 Scrin Seeker | replaced: Breakers |
| Prospector | A | Red Alert 3 Allied ore collector | replaced: Fuel Runner (B) |
| Wisp | A | Warcraft III Wisp | dropped (air later) |
| Jackal | A | Halo Wars Jackals; also the British Army's Jackal patrol vehicle | replaced: Flarejack (the first replacement, Coyote, is the Canadian Army's LAV Coyote reconnaissance vehicle and the British Army's Coyote, the Jackal's sibling) |
| Technician | A | TD and RA civilian Technician | dropped with the engineer role |
| Sapper | A, B | Company of Heroes Sappers; an engineer role | dropped |
| Scorcher, Flamer (flamethrower infantry) | A, B | TD and RA1 Flamethrower, StarCraft Firebat | dropped |
| Grenadier | B | TD, RA1 and C&C 3 Grenadier | dropped |
| Engineer (repairs, captures) | B | C&C Engineer in every game | dropped in Phase 3 |
| Neutral derrick or pump captured for income | A, B | RA2 and Generals Oil Derrick, C&C 3 Tiberium Spike | dropped |
| Mobile base unfolding into the HQ (Forge Rig, Nexus Carrier, Nomad, Caravan) | A, B | C&C's MCV | dropped; matches start with an HQ |
| Pillbox | B | RA1 and RA2 Pillbox | replaced: Redoubt |
| Sentry | B | RA2 and RA3 Sentry Gun, Generals Sentry Drone | replaced: Rail Battery |
| Radome, radar dome | B | RA1 Radar Dome | replaced: Signal Mast, Relay Tower; no dome on a tower |
| Radar unlocks the minimap | A | TD Communications Center, RA Radar Dome | not taken: radar is a tech gate, the minimap is always on |
| Power Station, Power Plant | B, GDD | "Power Plant" in TD, RA1-3, TS, C&C 3 | display names Turbine Hall, Wind Park; the id `power_plant` stays internal |
| Refinery | B, GDD | TD, RA, TS, C&C 3, StarCraft | display names Cracking Plant, Synthesis Works; id stays internal |
| War Factory, Barracks, Headquarters | GDD | War Factory: RA, RA2, RA3, Generals; Barracks and Headquarters are generic | display names Heavy Yard, Motor Works, Bunkhouse, Crew Hall, Rigworks, Grid Hub |
| Harvester | GDD | TD, TS, C&C 3, Dune | display names Tanker, Fuel Runner; id stays internal |
| Light tank, Heavy tank, Artillery, Rifle and Rocket squads | GDD | RA1 Light Tank, Heavy Tank, Artillery, Rifle Infantry, Rocket Soldier | display names per §7; ids stay internal |
| Ore | P75 | RA's ore | player-facing words are oil and gas; `ore` stays internal |
| Academy | B | StarCraft Terran Academy | replaced: Crew Hall |
| Trebuchet | B | Age of Empires II Trebuchet | replaced: Arcline (the first replacement, Longshot, is a real air-launched drone programme, DARPA's LongShot) |
| Warden | B | Halo's Warden (not a known RTS unit) | not used: Torque |
| Fusilier, Jäger | B | real military words with national coding (decision 1) | replaced: Linemen, Breakers |
| Blackout Array (EMP dish) | B | the closest C&C analogue is Generals Zero Hour's EMP Pulse (a general's power that disables vehicles and buildings in an area); also Tiberian Sun's EMP Cannon (a GDI structure firing an area EMP) and StarCraft's EMP Shockwave; the name has no known hit | kept as a name; it blacks out buildings only, no EMP wording, no blue lightning |
| Tectonic Hammer (seismic strike) | A | no known C&C seismic superweapon | the concept kept as Deep Bore |
| Twin rail cannon (Lancer, Rail Battery), twin gun (Sentry) | A, B | the twin-barrel super-heavy tank is TD and RA's Mammoth (svg-art-style forbids it) | single barrels only |
| Tesla, Chrono, Mammoth, Iron Curtain, coil and prism towers, airships | - | RA | excluded (A's own list, svg-art-style) |
| Tabs Base, Defense, Infantry, Vehicles, Air; sell and repair buttons; rank chevrons; PRIMARY | A HUD | RA2's sidebar tabs and buttons | not taken (§12) |
| Blue against red, East against West, Cold War 1986, orbital ring as a Cold War sign | A, B, GDD | RA's Allies (blue) and Soviets (red) | dropped; orange against cyan by default |
| Lancer, Bulwark, Kestrel, Bastion, Gyro Striker | A, B | no known hit in the games above, but real military names: the B-1B Lancer bomber, HMS Bulwark (a Royal Navy assault ship), the Kestrel anti-armour rocket, the Bastion coastal missile system, the Striker anti-tank vehicle | not used (Bulwark was §7's first tank name; now Bullhead) |
| Thunderhead, Hauler, Swift, Fuel Runner, Wind Park, Motor Works, Gas Works, Training Hall, Garrison, Rail Battery, Armor Works, Smelter, Furnace Plant, Radar Mast, Halcyon, Skylance, Trooper, Breacher | A, B | no known hit in the games above or among real military vehicles in service (Swift: the Supermarine Swift jet, retired in the 1960s; a common word) | Swift, Fuel Runner, Wind Park, Motor Works and Rail Battery used; the others unused |
| Big Shoulders, Chakra Petch fonts | A | SIL OFL fonts, not CC0 or CC-BY | not used (§5) |
| The names of §6 and §7: Derrick League, Lumen Accord, Rigworks, Turbine Hall, Cracking Plant, Bunkhouse, Heavy Yard, Signal Mast, Redoubt, Deep Bore, Roustabouts, Wildcatters, Flarejack, Bullhead, Mortar Rig, Tanker, Grid Hub, Synthesis Works, Crew Hall, Relay Tower, Blackout Array, Linemen, Breakers, Torque, Arcline | this ADR | no known hit in the games above or among real military vehicles, aircraft, ships or weapon programmes. Flarejack (flare stack + pumpjack) and Arcline are coined; Bullhead is an oilfield word (bullheading, a well-control method); Roustabouts, Wildcatters and Linemen are trades (the AW159 Wildcat helicopter is another word); Redoubt, Tanker, Mortar Rig and Rail Battery are generic words; "derrick" is an oilfield word (Red Alert 2's and Generals' Oil Derrick is a capturable neutral building, another name and a dropped mechanic, row above). Rejected while choosing them: Roughnecks (Starship Troopers' Roughnecks, an RTS since 2022), Blockhouse (Age of Empires III), Thumper (Dune), Aegis (RA2 Aegis Cruiser; also a real naval combat system), Pylon (StarCraft), Longbow (RA1; also the AH-64D Longbow), Coyote, Longshot, Bulwark, Iron Compact (rows above) | used (Michael's answers 1 and 2, 2026-10-26) |

### 14. Performance and the arenas
- **Perf arena:** nothing here but §10 touches its state (§6 adds type data only, and its
  scenario lists no faction), so its golden hashes, `budget.cfg` and every `PERF` line stay;
  P109's one re-pin (§10) is the only change, with its reason. The arena scene gets the iso
  layers (P117, P114, P116), so its phone card's draw calls and frame times change; thresholds are
  unchanged (ADR 0021 §5).
- **Base arena** (P80, not merged): side 1 Derrick League, side 2 Lumen Accord, every building type
  of both (about 30 buildings) and 150 mobile rows; a scenario order fires each strike once
  (`OrderDef` gains `SUPERWEAPON`). Its golden hashes are pinned first by P93, after
  every sim row of revision 5.
- **Headless proof:** the projection round trip; the sort order of crafted units around 1x1, 2x2
  and 3x3 footprints; every `WorldSort` sprite on the one atlas texture with white modulate (the
  headless stand-in for the call count); the bake's CPU image (triads, gutters, page size for the
  real art); the camera clamp; picking; the generator's determinism. On a renderer: P114's
  llvmpipe count (at most 15 for a base-arena-like scene) and the phone cards.

### 15. What this supersedes and amends
- **ADR 0022:** superseded. §1 (oblique buildings, top-down units), §2 (the middle-line cut, the
  two building layers and their z, the z table, the forecast of 32), §4's roof fog colour and
  partly-seen seam, §5's ghost in the oblique view, §6's square ground tiles and §7's art list give
  way to §1-§5 here. **Kept:** units first in picking and its order (§3), the frame round the
  picture (question 2 = A), a unit hidden behind a building keeps its bar (question 1), team marks
  about 8-12 % (question 3), textured ground in Phase 3 (question 4), the tracer clip (§4), the
  runtime atlas helper with its 2 px gutter, `MapView` as the map's model with its colours, tiles
  and bake (P52's cross-file facts untouched), and "no new perf arena" (§8).
- **ADR 0004 §6:** the camera's edge clamp becomes §4's: the view centre's ground point is
  clamped into the map's diamond, and the limits are the diamond's bounding rect grown at the top by
  the tallest sprite; pan, pinch, the zoom levels and the snap are unchanged.
- **ADR 0010 §2:** the fog draws at z 4 on the ground, as diamonds under the iso transform, under
  every object; last-seen ghosts at z 5; enemies, bars and projectiles keep their hiding by tile;
  the tracer stays clipped. Texture, updates, `explored_alpha` and the soft edge unchanged.
- **ADR 0011 §3:** rigs are `[Shadow, Ring, Hull, Turret]` with regions of one per-match atlas,
  y-sorted in `WorldSort`; no `Team` node; buildings are sprites in the same sort; `MapView` draws
  its bake under the iso transform where no ground layer covers it.
- **ADR 0012 §6:** the z bands per type and owner are replaced by §2's table and the one-atlas rule;
  the forecast is 13; the MultiMesh trigger (40) and the ceiling (60) stand.
- **ADR 0015 §5:** landscape's right zone becomes the floating panels (question 4 A, P85d);
  portrait unchanged; the minimap's place follows §12.
- **ADR 0019:** §1 (layout, question 4), §2 (the ghost on diamonds, grab area = silhouette + 24 dp),
  §3 (pick shapes), §4 (an isometric minimap, its place), §5 (low power: a glyph on every consuming
  building instead of a dim, question 7).
- **ADR 0007 §4-§5 and ADR 0017 §4-§5** (question 3 A): `SUPERWEAPON` = 15; `Strike.run` inside
  the FIRE mark (step 10 of ADR 0007 §4), after `Combat.fire` and before REMOVE (§10), so its kills
  die at that tick's REMOVE; no new phase id.
- **ADR 0018 §2-§3:** player-facing ore and harvester become fields and tankers (§11); the rules
  are unchanged. **§4-§5:** an offline (blacked-out) building neither makes nor uses power, a
  defence among them does not fire and a producer among them does not advance its queue (§10);
  `QUEUE` is dropped for another faction's item (§6).
- **ADR 0020 §4:** one dummy `AiDef` per faction; the dummy never builds or fires a strike.
- **ADR 0021 §1:** the perf arena's golden hashes move once more after P70, in P109 (§10).
  **§2:** the base arena holds both factions (§14).
- **Lines that changed with Michael's yes** (question 9 "ja"; applied by P68e on #200):
  - `CLAUDE.md` Stack: "- 2D top-down, buildings in an oblique 3/4 view (ADR 0022), landscape and
    portrait (ADR 0015; the" becomes "- 2D isometric (dimetric 2:1, ADR 0023): the sim keeps its
    square grid and only the view projects; landscape and portrait (ADR 0015; the". Layout: a new
    line "`tools/artgen/` the art generator: simple 3D models to SVG frames (ADR 0023)". Legal,
    assets: "only SVG authored in this repo" gains "(by hand or by `tools/artgen/`)".
  - `docs/GDD.md`: "Match setup" (two asymmetric factions in the MVP, their names, both sides
    playable; "Both sides use the same faction in the MVP (mirror). A second, asymmetric faction
    comes after launch." and the "Working faction names" line go), "Economy" (oil and gas fields,
    tankers), "Buildings (MVP)" and "Units (MVP)" (per faction, §7), a new "Superweapons (MVP)"
    (§10), "Art and audio" (isometric, ADR 0023), "Not in version 1" ("second faction" goes; air
    stays); P68e also turned the ore of "Pitch" and "Maps (MVP)" into oil and gas (§11).
  - `.claude/skills/svg-art-style/SKILL.md`: the frontmatter `description` (isometric, generated
    frames), "Look" (lines 10-14), "Camera and scale" (lines 16-31: §1's projection, 2x = 128 x 64
    per tile, directions, anchors, sizes of Spec §05), "Palette" (lines 33-43: per-faction palettes,
    the key triads instead of "Team-colour layer is drawn in greys only ... team A #2F80ED, team B
    #E5484D"), "Drawing rules" (lines 45-57: Spec §02's light and shadows; the "short throw ...
    so the hull can face any way" and "Buildings: south facades in shade" lines go), "Technical
    rules" (lines 59-71: generated files, the keep import, naming of §5), "Originality" (line 74-76
    gains the dropped concepts of §13).
  - `.claude/skills/touch-ui-rules/SKILL.md`: the frontmatter `description` (the build menu, not
    a sidebar), line 22 (tap own building: its silhouette, ADR 0023 §3), line 26 ("Tap ore with
    harvesters selected" becomes oil or gas fields with tankers), lines 41-42 (harvesters become
    tankers), lines 51-54 (the pick shapes of §3), lines 58-60 (the ghost's grab area: silhouette
    plus margin), line 66 (the check mark and X in the floating build panel in landscape), lines
    74-77 (landscape layout, question 4), line 89 (the portrait minimap's place).
  - `.claude/agents/art-director.md` line 10 ("All art is hand-written SVG code in this
    repository.") and line 15 ("Write clean SVG by hand") allow the generator and its models.
  - `docs/ROADMAP.md` Phase 3: a new box "Two original factions with their own buildings, units
    and superweapon (ADR 0023)".
  - Not changed: `rts-sim-conventions` (the lead adds the faction rule and Command 15 in the sim
    rows' review, as for every sim rule), `export_presets.cfg` (the keep import needs no filter;
    P113 confirms it on both exports), the perf thresholds.

## Consequences
- The view is rebuilt once more, the day after ADR 0022: P84's shelved branch, P91b's oblique art
  and the top-down unit art become reference. Reused from the shelved P84: `RuntimeAtlas` with its
  test (the bake's packer), the tracer clip with its fog-hiding cases, and `UnitLayer`'s skip of
  footprint rows; not reused: `BuildingLayer`, `BuildingRoofLayer`, `BuildingGeometry`, the cut
  tests and the z moves of fog (to 110) and bars (to 112).
- The draw-call forecast falls from 32 to about 13, but the match needs one texture page of up to
  about 64 MB (estimate) and a bake of about 0.5 to 1.5 s at match start (estimate); both are
  measured on the phone card (P113) before the view rows build on them.
- Units behind tall buildings are hidden (bars show); last-seen ghosts draw under live units; a
  unit centred within half a tile of a footprint's side corner may sort wrongly at the tip.
- Low power no longer dims buildings; it shows a glyph on each consuming building and the power bar.
- Michael's art rows depend on a new tool. Until the art rows land the game shows blockout models
  (boxes with team bands), which Michael sees in the preview.
- The perf arena's golden hashes are re-pinned once more (P109, question 3 A).
- Two factions double the art and data work of the roster and the balance space of Phase 4.
- The CLAUDE.md asset rule, the art-director agent and the skills changed wording with Michael's
  yes (question 9, P68e).

## Alternatives considered
- **Keep ADR 0022's oblique view.** Rejected by Michael's decision 2.
- **Sort by the front corner (Spec §06).** Wrong for a unit beside a building's east or south wall
  (drawn behind it). The centre key with square footprints is exact (§2).
- **Slice buildings into half-tile columns, each with its own key** (the classic fix for
  non-square footprints): about 6 slices per 3x3 building, more sprites, art cut by code; not
  needed while footprints are square. The fallback if a later footprint must be oblong.
- **Draw the sorted world in one `_draw()` with vertex colours** (team overlay quads tinted per
  item, no per-player bake): one call and no bake, but every frame re-records about 150 x 4 + 60
  quads and sorts in GDScript on the main thread (an estimate of 1-3 ms per frame on the gate
  phone, against 5.6 ms for all view work). Kept as the fallback if the bake's memory or time
  fails on the phone.
- **Per-type z bands (ADR 0012 §6) with y-sorting:** z outranks y-sorting, so bands and sorting
  exclude each other; ADR 0022 measured the interleaved case at 150 calls.
- **Team colour by a palette shader at draw time:** a per-sprite team needs a per-sprite uniform
  or modulate; modulate breaks the batch (probe), and canvas shaders have no instance uniforms in
  4.7.2. **A GPU bake through a `SubViewport`** would avoid the SVG text in the export, but cannot
  be tested headless (no rendering there).
- **Fog over every object** (ADR 0010's first order): it would hide tracers for free, but a tall
  building in front of unexplored ground would have its top blacked out.
- **Hand-drawn SVG for every direction:** about 500 files for the Phase 3 rosters, slow and
  inconsistent in light; question 5's other answer.
- **Rasterised PNG atlases committed to the repo or built in CI** (Spec §08): binary files in the
  repo, a second source of truth beside the SVG, and a per-team copy for each of 8 triads; the
  match-start bake needs neither.
- **A plan-view minimap:** a turned camera frame and a north that does not match the screen.
- **Everything of the canvas in Phase 3** (air, engineers, capture, pumps, pipelines, bridges,
  garrisons): several thousand lines and kernel changes; the gate would move by weeks.

## Questions for Michael (answered 2026-10-26)
As proposed; the lead asked them in Danish in chat. "Answers" at the top records Michael's
answers and what they mean.
1. **Faction names.** A: Iron Compact (oil and gas) and Lumen Accord (green energy). B: Derrick
   League and Current Accord. C: names you choose (screened by the lead before use). Recommended:
   A. Cost: none either way (display names in data and docs).
2. **Unit and building names** of §7 (Rigworks, Turbine Hall, Cracking Plant, Bunkhouse, Heavy
   Yard, Signal Mast, Redoubt, Deep Bore, Roustabouts, Wildcatters, Flarejack, Bullhead, Mortar Rig,
   Tanker; Grid Hub, Wind Park, Synthesis Works, Crew Hall, Motor Works, Relay Tower, Rail
   Battery, Blackout Array, Linemen, Breakers, Swift, Torque, Arcline, Fuel Runner). ja, or name
   the ones to change. Flarejack, Bullhead and Arcline replace this draft's first Coyote, Bulwark
   and Longshot, which are names of real military vehicles, a ship and a drone programme (§13).
   Recommended: ja. Cost: none; later renames are data only.
3. **What comes in Phase 3.** A: both factions' full rosters (8 buildings and 6 unit types each)
   and both superweapons (the rest of §8 later or dropped). B: the full rosters now; the
   superweapon buildings stand but fire only after the gate (5 rows and about 1150 lines later, no
   re-pin before the gate; the rows are off the critical path, so the gate comes about a day
   sooner). C: as B, and Lumen Accord's units share
   Derrick League's numbers until Phase 4 (art-only asymmetry; saves little, the numbers are data).
   Recommended: A (you chose asymmetry with a superweapon now; its rows run beside the critical
   path). Cost of A over B: the five strike rows (about 1 150 production lines) inside Phase 3
   and about a day on the gate, since they run beside the critical path. Revision 5 as a whole
   (the view, the art and the factions, whatever the answer) moves the gate about one week
   (estimate: 0.5 to 1.5 weeks; plan revision 5 gives the rows and the critical path).
4. **The build menu in landscape.** A: the canvas's floating panels (build panel at the bottom
   right with named cards, minimap top right, more map visible), one extra row before placement.
   B: keep today's right-hand sidebar, restyled with the canvas's cards, and revisit in Phase 5.
   Recommended: A (the canvas's own UI, further from Command & Conquer's sidebar, and the
   placement and minimap rows are not built yet). Cost: A one row (about 250 lines) on the HUD
   lane, off the critical path if it merges while the map lane builds the sorted world; B nothing
   now, about two rows of rework later.
5. **Art made by a generator.** Units, turrets and most buildings are described as simple 3D shapes
   in the repository and a tool in the repository draws them as SVG in every direction with one
   light; art-director may still hand-draw buildings and details. ja/nej. Recommended: ja. Cost of
   nej: about 500 hand-drawn files, roughly 3-4 extra weeks of art (estimate).
6. **The two superweapons.** Derrick League's Deep Bore splits the ground (damage in 3 tiles after a
   3-second warning everyone sees); Lumen Accord's Blackout Array shuts enemy buildings in 4 tiles
   down for 30 seconds (no power, defences silent, production paused; units keep going). No freeze
   (Red Alert 3 has freezing weapons). ja/nej, or swap the effects. Recommended: ja. Only if
   question 3 is A or B.
7. **What the new view means on screen.** A unit behind a building is hidden (its bar shows, as
   you accepted for ADR 0022); enemy buildings remembered in the fog are drawn under live units;
   low power shows a warning sign on each building that uses power instead of dimming it; the
   minimap is a diamond like the map. ja/nej. Recommended: ja. Cost of dimming instead: up to
   about 30 extra draw calls while power is low, or a second dimmed copy of every building
   picture.
8. **Team colours.** The canvas's eight three-tone colours; player 1 orange, player 2 cyan by
   default; no red-against-blue. The team colours win over the canvas's material colours: four of
   them change so that nothing in a faction's art looks like its team colour (Derrick League's rust
   becomes a dull brown and its amber lamps warm white; Lumen Accord's glass becomes pale grey-blue
   and its cyan status lights mint green; §5, §6). ja/nej. Recommended: ja. Cost: none (the art is
   not drawn yet). The other answer, other key colours that no material uses, would make the
   art's source files show the wrong colours and change the canvas's default look.
9. **The texts that must follow** (§15): CLAUDE.md's Stack, Layout and asset lines, the GDD's
   factions, rosters and economy, the two skills, art-director's agent file and a new ROADMAP
   Phase 3 box for the factions. ja/nej. Recommended: ja. Cost: none (one docs row).
10. **Oil and gas.** Fields work like today's ore: tankers load at a field and drive to the
    refinery, fields show full, half and dry and refill slowly; no pumps, no captured derricks and
    no pipelines in Phase 3. ja/nej. Recommended: ja. Cost: none (data and view only).

## On acceptance (lead, docs row P68e; applied 2026-10-26 on #200)
- This ADR: status "accepted" with the date and the answers; the plan's revision 5 rows become plain
  rows. No row is withdrawn: question 3 A keeps P109-P112b in Phase 3, question 4 A keeps P85d
  whole.
- ADR 0022: status "superseded by ADR 0023 except §15's kept rules", dated, never rewritten. Dated
  status notes on ADRs 0004 §6, 0007 §4-§5, 0010 §2, 0011 §3, 0012 §6, 0015 §5, 0017 §4-§5,
  0018 §2-§5, 0019 §1-§5, 0020 §4 and 0021 §1-§2 as §15 lists.
- With Michael's yes to question 9: `CLAUDE.md`, `docs/GDD.md`, both skills, `art-director.md` and
  the ROADMAP box, line by line as §15 lists. `assets/art/STYLE.md` changes in the art rows
  (art-director).
- The lead adds the faction and unit names to the Phase 7 trademark search list (ADR 0006).
