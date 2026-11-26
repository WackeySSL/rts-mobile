# P653: pre-rendered 3D prototype (prototype only, never merged)

Question: should units, buildings and terrain switch from generator SVG to sprites pre-rendered from our own
3D models? This folder is the evidence. Michael decides; the decision becomes an ADR.

Everything here is ours: the geometry is the repo's own model data (`assets/art/models/fossil/heavy_tank.tres`,
`vehicle_factory.tres`, read through `ArtMesh.faces`), plus code-built detail and a code-built terrain. No asset
packs, no web models or textures, no AI generators. The Figma frames were looked at for material, light and
proportion only and nothing was traced. No Figma pixels are in this folder.

## What was built

| Item | Id used | Canvas (art px, today's) |
|---|---|---|
| Nordvaern tank, hull plus separate turret, 16 directions | `heavy_tank` | hull 166x104, turret 214x118, shadow 254x130 |
| Nordvaern 3x3 building | `vehicle_factory` | hull 384x346, shadow 456x230 |
| Terrain patch 8x8 tiles: grass, dirt, sand, gravel, asphalt road, cliff edge, shore with water, boulders | n/a | 1032x692 at 1x |

Team colour: the team panels are painted in the existing magenta sentinel (`#D234D2` mid) and shown in
Signal (`#E8681F`) and Kobolt (`#3F6FE0`).

## Files (all our own renders)

- `tank_z1.png`, `tank_z2.png`: today's SVG L2 (left) | prototype (right), 1280x720 base at zoom 1 and zoom 2,
  grass row in Signal, sand row in Kobolt. Real pixel size (zoom 1 = 0.5 px per art px).
- `building_z1.png`, `building_z2.png`: same for the 3x3 building.
- `terrain_z1.png`, `terrain_z2.png`: same for terrain. Today's side is today's flat ground diamonds laid out
  with the same tile classes. Today has no road tile and no cliff tile, so the road is shown as sand and the
  cliff as the flat rock tile.
- `scene_svg_z1.png`, `scene_proto_z1.png`, `scene_svg_z2.png`, `scene_proto_z2.png`: tank x3 (one Kobolt),
  building and terrain together, 1280x720, today's SVG vs prototype.
- `tank_16dir_contact_sheet.png`: 16 directions, Signal rows 1-2, Kobolt rows 3-4, at zoom 2.
- `readability_32px_grey.png`: units shrunk to 32 px on the long side, greyscale, x6 nearest. Top row today,
  bottom row prototype. Both stay identifiable as a tracked tank with a turret and gun. The prototype is a
  little darker with less top-to-side contrast. Hull, turret and gun still read.
- `grid_overlay.png`: the projection check (below).
- `tools/`: the post-process and measurement scripts. The Godot side is in `/tools/prerender/`
  (`ProtoBuild.gd`, `ProtoRig.gd`, `bake_units.gd`, `bake_terrain.gd`).

Figma node ids used for the three-way comparisons (kept in the scratchpad, not committed). The Figma file
key is `HsBPSXZ6PTRp6KkdhEi6bT`; the crops are from the full-frame screenshots at their native 1600 px width.

| Comparison | Figma node | Crop of that screenshot |
|---|---|---|
| tank | `2:10462` "Krigsarkiv / Tanks og soldater", card "K-7 Bastion" (4th card, row 1) | x1198-1530, y332-447 |
| building | `2:10275` "Bygninger / NORDVAERN", card "Teknologilab" (3x3, row 2, col 3) | x822-1154, y614-746 |
| terrain | `2:10611` "Terraen og kortkit", the eight kit cards (x56-1532, y235-731) and the example map "Askehavn" (x56-986, y800-1230) | as listed |
| scene | `2:9945` "Treadline / Kamp / Landscape", whole frame 932x430 | whole |

Three-way PNGs: `threeway_tank_z1/z2`, `threeway_building_z1/z2`, `threeway_terrain_z1/z2`,
`threeway_scene_z2` in `/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p653/`.

## Approach

- **Mesh source.** `ArtMesh.faces(prim)` gives the flat faces of every box, wedge and prism of the existing
  model; macros (`wheels`, `tracks`) expand through `ArtPrim.parse_all`. Spheres and rods are Godot primitives.
  Each face gets a 0.016-tile bevel strip with blended normals, so every edge catches light (the "edge highlight").
  Big box faces get seeded raised plates and vent slats (`_greeble`), the prototype's stand-in for hand
  modelled surface detail. The silhouette is therefore the same as today's. Only surface, light and
  occlusion differ.
- **Scene.** One orthographic `Camera3D`, elevation 30 degrees, yawed 45 degrees, 90.51 px per world unit
  (= 64 x sqrt 2). One sun towards (-0.8, +0.25, 1.0) in grid axes: shadows reach 0.8 per unit of height
  towards +gx like `ArtShadow.REACH`. A bluish fill from +gy, a procedural sky for ambient and reflections,
  SSAO, PBR materials (metallic/roughness per material, clearcoat on paint), triplanar noise grain, panel
  seams and rivets as albedo and normal maps. Light tonemap is linear, with a global grade applied after
  recolour.
- **Terrain.** A 56 vertices-per-tile height field built in code from noise: plateau with a wandering cliff
  edge and strata, a basin filled by a water mesh with foam, a meandering asphalt road with a dashed line and
  cracks, vertex-colour splat for grass/dirt/sand/gravel, 22 deformed boulders.
- **Bake.** `bake_units.gd` renders each frame at 8 texels per art px (units) or 4 (terrain, building); `pipeline.py`
  box-filters in linear light to 2x (4 texels per art px, `f=4`) or 1x (today's density, `f=8`), recolours,
  grades and writes RGBA PNGs.
- **Shadows.** A separate layer, like today: the hull and turret geometry is flattened onto the ground along
  +gx and drawn unlit black at 35 % (one frame per direction, `*_shadow_dNN.png`). Reasons: the light does not
  turn with the unit, so a shadow baked into the hull frame would rotate with it; the view already draws
  shadows at z 2 and in the `DecalLayer` under other units; it stays on atlas page 2. Self-shadowing
  (turret on hull) and SSAO are baked into the hull and turret frames.
- **Renderer.** Godot 4.7.2, `xvfb-run`, Mesa llvmpipe.
  - Compatibility (OpenGL 4.5 llvmpipe): initialises fine, but has no SSAO.
  - Forward+ over Vulkan failed first (`Required Vulkan instance extension VK_KHR_surface not found`: no
    lavapipe ICD in the image). Fixed with `apt-get update` and `apt-get install -y mesa-vulkan-drivers`.
    That gave `Vulkan 1.4.318 - Forward+ - llvmpipe` and is what all frames use.
  - Blender was not needed or installed.
  - Packages: `mesa-vulkan-drivers 25.2.8-0ubuntu0.24.04.5` installed; four mesa libraries
    (`libgl1-mesa-dri`, `libglx-mesa0` and two siblings) were upgraded from `.4` to `.5` as dependencies.

## Projection check (IsoProjection, ADR 0023)

A flat 8x8 checkerboard and a 1x1x1 cube rendered through the same camera, compared with the formula
`px = (gx-gy)*64, py = (gx+gy)*32 - z*78.38` (art px at 2x), see `grid_overlay.png` and `tools/grid_check.py`:

- 221,717 of 221,717 diamond pixels (away from tile borders and the cube) have the colour the formula predicts;
  none are uncovered.
- The cube's top corner is at y 264 (formula 263.6); its x range is 452-579 (formula 452-580).

The building anchor semantic is different from the unit's: the sheet anchors a building at the footprint's
back corner, 32 x n art px above its centre. The renders honour that, and the building overlays today's frame
exactly.

## Recolour findings

The existing recolour is a string swap of three exact hex values in the SVG text (`IsoPlayerArt.recolour`).
On a shaded or anti-aliased render it matches **0 pixels** (measured on 1,406 team pixels at 1x and 5,414 at 2x).
It cannot recolour pre-rendered PNG.

The first attempt at a smaller fix (keying on `min(R,B) - G` and adding a constant albedo difference) failed:
mean error 13.7 of 255, 54 magenta fringe pixels at 1x, 262 at 2x. Two causes: it ignored that light is
coloured, and the lit sentinel clipped in the render (R and B reached 1.0, so the lighting was unrecoverable).

The fix, prototyped in this branch only (`pipeline.py: recolour2`):

1. Render the sentinel with an albedo that cannot clip: the exact mid colour, with the sun, ambient and fill
   set so a lit top face stays at or below 1.0. This is a rule for the model side, not a code change.
2. Hue-key the team share `w = clamp((min(R,B) - G) / min(R,B) / 0.947)` per pixel in linear light. It is exactly
   the coverage of the sentinel in a pixel that is mixed with neutral or orange neighbours.
3. Recover the light per channel from the sentinel's own pixel (`E_R = w R / A_R`, `E_B` alike, `E_G` as their
   mean) and replace the sentinel albedo by the target's: `out = pixel + E x (A_target - A_sentinel)`.

Measured against a ground truth, a full re-render with the team material set to the target colour, on the hull and turret frames of directions 3 and 9, both
teams (only the turret carries team pixels):

| Density | Team px | Mean error | p99 | Max | px over 12/255 | px over 24/255 | Magenta fringe px |
|---|---|---|---|---|---|---|---|
| 1x | 1,406 | 3.1 | 38.9 | 50 | 27 (1.9 %) | 13 | 1 |
| 2x | 5,414 | 2.9 | 31.2 | 47 | 46 (0.8 %) | 28 | 2 |

The errors that remain are specular highlights (white, not tinted) and the clearcoat. Shading keeps its
value; there is no visible fringe. The same formula is about ten ALU operations and fits a `canvas_item` shader
(not written or tested in-game). The shader route matters for cost, see the risks.

## Determinism of the bake

The same frame baked four times (two default runs, `LP_NUM_THREADS=1`, `LP_NUM_THREADS=3`) is byte-identical (same md5 for hull,
turret and shadow). That holds for one container and one Mesa build. A different Mesa, LLVM or a real GPU
will differ in low bits. See the risks.

## Numbers

Counts (from `assets/art/iso/*/*/*_sheet.tres`, `docs/art/treadline-batches.json` and `data/terrain/standard.tres`):
48 art ids in the batches (both factions): 22 units (16 vehicle and air with 16 directions, 6 infantry with
8 directions and walk/idle), 26 buildings (12 of 3x3, 10 of 2x2, 4 of 1x1), 6 terrain ids (12 flat ground
diamonds today). 800 unit frames and 154 building frames, one colour slot.

Today's atlas: 70.4 MB of texels (17.6 M) for all 48 ids in one colour slot; the cross-faction match packs two
4096-wide pages, 2748 and 2594 rows against the 3584-row budget (about 87.5 MB).

**Atlas MB (RGBA8, per colour slot, tight boxes, shadows at full canvas as today):**

| Item | Today (SVG baked) | Prototype 1x (today's density) | Prototype 2x (4x texels) |
|---|---|---|---|
| `heavy_tank` hull+turret+shadow, 16 dir | 3.41 | 3.36 (measured: boxes 310,972 vs 323,970 texels) | 13.4 |
| `vehicle_factory` hull+dmg2+shadow | 1.34 | 1.34 (hull and shadow measured; dmg2 assumed as today) | 5.4 |
| Terrain patch 8x8 as one sprite | n/a | 2.9 (1032x692) | 11.4 (2064x1384) |

**Projected over the roster.** Assumptions: the same silhouettes, so the same frames and tight boxes; the
same 16 or 8 directions; the same animation frames; shadows as today.

- 1x: 70.4 MB of texels, 2 pages of 2748 and 2594 rows. **Unchanged from today.**
- 2x: 281.6 MB of texels, about 350 MB cross-faction. Rows scale by about 4: page 1 about 10,990 rows
  (4 pages of the 3584 budget), page 2 about 10,380 (3 pages). The sorted world no longer fits on one page
  (ADR 0050's context says it must). The highest density that keeps page 1 under 3584 is about 1.14x linear.
- Terrain kit: 6 ids x 4 variants, 8 blend masks, about 12 cliff pieces, about 15 road pieces, so about 80
  sprites of 128x(64..100) texels. About 4 MB at 1x, 16 MB at 2x, in its own texture. Today: 12 diamonds, 0.4 MB.
  A whole map as chunks of 8x8 patches would be 2.9 MB each at 1x: not viable (a 64x64 map is 183 MB).

**Time (one-off, this container, 4-core llvmpipe, no GPU, not a game timing run):**

- Tank: 48 frames rendered in 20.8 s (0.43 s a frame, including shader warm-up); 6.4 s (1x) and 8.5 s (2x)
  for the Python downsample, recolour, grade and PNG write. About 36 s per unit for both densities.
- Building: 3.6 s for hull and shadow, about 2 s post (a dmg1/dmg2 pose adds 1-2 frames).
- Terrain patch: 2.3 s to build the mesh, 6.7 s to render 4128x2768.
- Roster estimate: 22 units about 13 min, 26 buildings (with damage stages) about 4 min, so under 20 min of CPU
  for a full re-bake. The render is not the cost. Modelling is.
- At match start the bake becomes a PNG decode instead of an SVG rasterise (cheaper). A GDScript per-pixel
  recolour of 17.6 M texels would not be: it has to be a shader (see risks).

**Repo size per unit:**

| | Today | Prototype 1x | Prototype 2x |
|---|---|---|---|
| `heavy_tank`: meshes | 2.3 KB (`heavy_tank.tres`, unchanged, it is the mesh) | same | same |
| `heavy_tank`: outputs (48 frames) | 491 KB SVG | 444 KB PNG | 1,497 KB PNG |
| `vehicle_factory`: outputs (hull+shadow; dmg2 extra) | 22 KB SVG | 105 KB PNG | 413 KB PNG |
| Terrain patch (one 8x8) | 0.4 MB (12 diamonds) | 514 KB | 2,153 KB |
| Roster (800+154 frames, at 0.53 and 0.45 B per texel) | about 20 MB of SVG in `assets/art/iso` | about 9 MB | about 32 MB |

The meshes need no new data (the model files are the meshes). Real hand-modelled meshes would be larger,
and are not costed here.

## Recommendation

**A conditional go, on three conditions: pre-render at today's density (1x), recolour in a shader, and upgrade the meshes before the units.** Do not
switch the roster wholesale, and do not go to 2x.

What the evidence says:

1. **It works and it is cheap at runtime.** The bake runs headless in this container, is repeatable, and
   costs under 20 minutes for the roster. At 1x the atlas, the draw calls, the quads and the fill are the same as
   today's, so 150 units at 60 fps is not made worse by the art.
2. **The look gain is real but small on today's models.** The silhouettes are the same blockouts, so the
   prototype gives better material, edge light and occlusion, not a different shape (`tank_z2.png`,
   `building_z2.png`). The Figma cards get their look from sculpted detail shown at about 330 px wide. Our tank is 83 px
   (zoom 1) or 166 px (zoom 2) wide. Reaching that look means new, hand-modelled meshes, and also more pixels per unit.
3. **Terrain is the biggest win.** Today has no road, cliff or shore tile at all, and the prototype patch has all
   three (`terrain_z1.png`). Buildings are second.
4. **Density is the blocker.** 2x is about 350 MB and 7 pages, which breaks ADR 0050's single sorted page and a
   mid-range 2021 phone. Only 1x fits. It looks soft at zoom 2 on a QHD phone (1.5 device px per texel, see ADR 0050
   context), the same as today.

Suggested first step if Michael agrees: one lane that adds the shader recolour and the PNG atlas path behind the
existing view code, a terrain kit (about 80 sprites) and the 12 3x3 buildings from upgraded meshes, with this
branch's tooling promoted into `tools/prerender/`. Units follow only after the mesh upgrade proves the look.

### Risks

- **Mobile memory.** 1x equals today (about 87 MB cross-faction). 2x does not fit. Per-player colour slots in
  the atlas stay as they are with a CPU recolour. A shader recolour would let both players share one copy (roughly
  half the atlas) but needs two canvas materials, and its in-game cost is untested. Compressed formats (ETC2/ASTC)
  would cut 2x to a quarter on Android, but WebGL2 (the phone preview) has no ASTC, and the preview is how Michael
  judges.
- **60 fps with 150 units.** Unchanged in principle (same sprite quads). A per-sprite recolour shader on the Compatibility
  renderer was not measured here; a canvas shader with a team uniform is cheap, but each team is its own batch.
- **APK and web size.** PNG does not compress further in the pck: about +9 MB at 1x (replacing about 20 MB of SVG that
  packs to about 2-3 MB), about +32 MB at 2x. Terrain kit +4 MB (1x).
- **Determinism in CI.** Byte-identical here across runs and thread counts, but only for this container's Mesa
  25.2.8 and llvmpipe. CI must not rebake and compare against committed files unless it runs this exact image.
  Safer: commit the baked PNGs, hash them in a test, and treat the bake as a dev tool run in a pinned container.
- **Effort.** The tooling is about 36 KB of GDScript and 29 KB of Python. The real work is meshes: today's models are
  blockouts of 20-40 primitives. Detail that reads at 166 px needs several times that, per unit and building, plus a
  terrain kit and damage stages. Rough estimate: 30 to 50 rows of the size of P638-P647, with wide uncertainty.
- **Legal.** Clean, if the rule holds that geometry is our code and data. The recolour, noise, sky and materials are
  engine built-ins or ours. The Figma frames were used as look reference only. The Figma file's building list and the
  names "Helix", "Prisme", "Aegis" were not used; ids are `heavy_tank` and `vehicle_factory`. The output is
  (c) AppCode ApS like today's SVG, to be listed in CREDITS/LICENSE as generated art if adopted.
- **Own coverage gaps in this prototype.** Only one tank and one building; no damage stages, no animation frames
  (walk, rotor, flicker), no infantry (8 directions with poses). The terrain is one patch, not a tileable kit with seams.
  No in-game shader test. No device measurement.
