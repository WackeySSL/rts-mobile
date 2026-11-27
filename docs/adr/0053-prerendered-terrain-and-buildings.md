# ADR 0053: Pre-rendered 3D terrain and buildings at today's density, with SVG units for now

**In short, for Michael:**
- **Terrain and buildings** are rendered from our own 3D models into pictures (PNG), as in the
  P653 and P655 tests. The ground gets roads, cliff edges, shores and more variety. The
  buildings get real light, edges and shadow.
- **Units stay generator SVG for now.** They take P655's lessons as SVG: darker gunmetal bodies,
  team colour on the turret and the side panels, and a longer gun (row P658). You
  decide whether units go 3D after you have seen 3D terrain and buildings in the game with the
  SVG units on top (row P659).
- **Sharpness stays as today.** Twice the sharpness would need about 350 MB of graphics memory,
  so it is ruled out.
- **Team colour** on the 3D buildings is put in by the game when a match starts. It is exact to
  about 3 of 255 colour steps, and it costs nothing while you play.
- **The game gets about 7.5 MB bigger** (APK and web).
- You answered all seven questions with the recommended answer (at the end).

Status: **accepted, 2026-11-27.** Michael's answer to the seven questions (2026-11-27, the lead's
AskUserQuestion), verbatim: "Godkend alle 7 (anbefalet)", so the recommended answer to questions 1 to 7. Proposed
the same day by the architect in row P654 on branch `claude/p654-prerender-adr` (base `main` at
7648d987), and accepted in that PR; the planned acceptance row P654b was folded into it. Plan:
`docs/plans/2026-11-27-prerender.md`.

**Acceptance note.** CLAUDE.md's Legal, Layout and Stack lines are edited by the lead (approved by Michael's answer 2), before any PNG art merges (P656 / P644). No row edits CLAUDE.md. The tool rows P656a and P656b may merge before
that edit; no PNG frame or kit tile may.
Evidence: two prototype branches that are never merged, and that stay the reference:
- `claude/p653-prerender-prototype` (head 5d2fa55d), `docs/proto/p653/README.md`: a tank, a 3x3
  building and a terrain patch, pre-rendered from the repo's own model data.
- `claude/p655-detailed-tank` (head 9c6dcd71), `docs/proto/p655/README.md`: one tank modelled in
  detail in code (42,032 triangles) and pre-rendered at today's density.

**Michael's decisions** (the lead's AskUserQuestion), verbatim:
1. 2026-11-26, before the probes: "Trinvis: terræn + én detaljeret tank (Recommended)" (step by
   step: terrain plus one detailed tank). This is the brief of P653 and P655.
2. 2026-11-27, after P655: "3D til terræn + bygninger, SVG-enheder" (3D for terrain and
   buildings, SVG units).
3. 2026-11-27, verbatim: "Vi kan starte der og så kan tanks laves til 3D senere når jeg har set
   det?" (we can start there, and tanks can be made 3D later when I have seen it?). The lead
   answered yes. So units stay SVG **for now**, and 3D units are an **open decision** for
   Michael (§1, row P659).
4. 2026-11-27: "Ironward (Recommended)". Nordværn is renamed Ironward and Facet stays. This ADR
   says Ironward. The ids (`fossil`, `renew`) and file names do not change. Row P657 renames the
   existing text.
5. 2026-11-27, to this ADR's seven questions: "Godkend alle 7 (anbefalet)" (approve all 7, recommended).

Answers 1 to 4 settle the scope (§1) and the reversal (§2). Answer 5 settles the rest: the
method (density, recolour, bake toolchain), the CLAUDE.md lines, the size, roads as decoration,
the order of the building batches, the SVG units' look and the ground bands.

**Form: a new ADR, not an amendment of ADR 0050.** The repo uses an amendment section for a
dated change confined to one part of an accepted ADR. That covers ADR 0004's and ADR 0012's
amendments, and ADR 0050's own "Amendment (2026-11-26, P621c)", which stays inside §3. This
change is wider:
- It reverses ADR 0050's answer 1 ("no PNG on the map") for two of its three classes of map art.
- It adds a second art source and its bake toolchain, a renderer outside the Stack (Forward+ over
  Vulkan, in a tool only) and a recolour pass at match start.
- It needs two CLAUDE.md lines changed (§6).
ADR 0050 itself followed the same rule when it amended ADR 0023 §5's pipeline from a new ADR.

**Supersedes in part** (dated notes; no accepted text is rewritten):
- ADR 0050 §2's first bullet ("Everything on the map is generator SVG … There is no PNG on the
  map"), for terrain and buildings. The note is placed in this PR: a status note at the top of
  ADR 0050 and a dated line at the end of §2.
- ADR 0050 §4's "Stand-alone pictures" bullet, its first sentence ("Game art on the map is never
  PNG: units, buildings, terrain …"), for terrain and buildings. The skill text is not edited
  here (§6).
- ADR 0050 §1's building budget: the polygon column, for pre-rendered buildings. It is replaced
  by §7's triangle cap. The byte column stays.
- ADR 0050 §5's row "Buildings' SVG", and the Consequences' "There is no PNG path to build".
- ADR 0023 §5 (SVG frames from `tools/artgen`), for terrain and buildings. Its status note is
  placed in this PR, at acceptance, as P621b placed ADR 0050's.

**Holds unchanged:**
- ADR 0050 §8 (one coherent look, the same-scene check) and its frozen `same_scene.tres` (A8).
- ADR 0050's amendment A1-A7: team colour on the large panels over neutral bodies, TEAM_SHARE
  30-65 %, the shape pairs, KRITISK keeping ADR 0029 §5's band.
- ADR 0050 §6 (zoom 2.0, soft by choice) and §3's units' rules as amended (L2 SVG, the sentinel
  key).
- ADR 0023 §1-§2: the projection, the anchors and the sorted world on one page.
- ADR 0027 §4 (3584 rows), ADR 0029 (three stages, the crater), ADR 0034 (no `dmg1`).

No sim rule, Command, `STATE_FORMAT`, hash, `data/` value or balance number changes.

## Context
- **P653's findings** (`docs/proto/p653/README.md`):
  - **The bake works.** Godot 4.7.2 runs headless under `xvfb-run` on Mesa llvmpipe. Forward+
    over Vulkan needs `mesa-vulkan-drivers` (lavapipe). Compatibility starts too, but it has no
    SSAO.
  - **The bake is repeatable.** The same frame baked four times (also with `LP_NUM_THREADS` 1 and
    3) is byte-identical, on one container and one Mesa build.
  - **The projection matches.** All 221,717 diamond pixels of a checkerboard match
    `IsoProjection`, and a cube's corners match it to a pixel.
  - **Density.** At today's density the atlas is the same size as today's, 70.4 MB of texels and
    two pages of 2748 and 2594 rows. At 2x it is about 350 MB and needs 7 pages, so the sorted
    world no longer fits on one page. The highest density that keeps page 1 under 3584 rows is
    about 1.14x linear.
  - **The look gain** is largest on terrain (today there is no road, cliff or shore tile at
    all). Buildings come second. On today's blockout models, units gain little.
  - **Recolour.** Today's recolour swaps hex strings (`IsoPlayerArt.recolour`). On a render it
    matches 0 pixels. `recolour2`, a hue key in linear light, keeps the shading: mean error 3.1 of
    255, p99 38.9, 1 magenta fringe pixel at 1x. It needs a sentinel albedo that never clips.
  - **The terrain kit** would be about 80 sprites of 128 x (64 to 100) texels, about 4 MB at 1x.
    A whole map baked as patches is not viable (183 MB for 64 x 64 tiles).
- **P655's findings** (`docs/proto/p655/README.md`):
  - A tank modelled in detail (42,032 triangles) "gets close at zoom 2 and does not get there at
    zoom 1". At 83 px everything below about 2 art px is lost: rivets, seams, hinges, the track
    links, edge wear.
  - What is kept: the value structure, the team panels, the wheel row, the gun and turret form,
    the shadow. Its recommendation is to keep units SVG with that palette and silhouette, and to
    take the 3D look for terrain and buildings first.
  - The recolour on the detailed tank: mean error 2.5, p99 9, 0 fringe and 0 clipped pixels at
    1x.
  - Effort: about one P638-size row per vehicle or building, and about two per squad.
- **Today's ground** (`GroundLayer`, a `TileMapLayer`, and `GroundAtlas`; the brief's
  "TerrainLayer" is this pair):
  - One 64 x 32 diamond per cell, from 12 SVG diamonds (6 terrain ids, variants `a` and `b` by
    `(column + row) % 2`), plus the field stages and the wellhead, on one page.
  - The diamonds import at `svg/scale` 0.5, so 64 x 32 texels, one texel per world px. That is
    half the sorted world's linear density (`WorldSort.ART_SCALE` 0.5: two texels per world px).
  - Per-map looks (`MapDef.ground_look`, folders under `assets/art/svg/ground_looks/`) swap
    diamonds.
  - There are no transitions, no cliffs and no shores.
- **Today's buildings:**
  - 26 sheets (12 of 3x3, 10 of 2x2, 4 of 1x1). Their parts are `hull`, `dmg2`, `shadow`, plus
    `anim` (up to 16 frames) or `head` (16 directions) on some.
  - Measured from the sheets' canvases (untrimmed, `dmg2` at `DAMAGE_SCALE` 0.75 per axis): 7.95
    M texels for both factions, one colour slot. 6.0 M of them are in keyed parts (all but the
    shadow). That is about 3 M per player.
  - The SVG frames take 1.38 MB on disk.
  - `IsoAtlas` bakes a frame that a key colour touches once per player, and one that none
    touches (a shadow) once per faction.
- **The sorted world** (`WorldSort`, ADR 0023 §2) is one draw call: every sprite is a region of
  the one page, drawn "in white" with no material.
- **CLAUDE.md's Legal line** allows only "SVG authored in this repo (by hand or by
  `tools/artgen/`), or CC0/CC-BY", plus Figma-drawn vector exports and the brand files. A PNG
  rendered by our own tool from our own model data is none of these.

## Decision

### 1. Scope: terrain and buildings pre-rendered; units SVG for now
- **Pre-rendered from our own 3D models, at today's density (§3):**
  - **Terrain:** the ground kit of §7 (P656).
  - **Every building**, 26 sheets in four batches:
    - P644: the Ironward 3x3 buildings (`headquarters`, `refinery`, `vehicle_factory`,
      `fossil_airfield`, `fossil_space`, `fossil_strike`).
    - P645: the Facet 3x3 buildings (`renew_hq` first, in ADR 0050 §2's faceted form).
    - P646: the Ironward 2x2 and 1x1 buildings.
    - P647: the Facet 2x2 and 1x1 buildings.

    They keep the team panels of ADR 0050 A1 and A7's KRITISK band. The recolour (§4) therefore
    lands with the first building batch, P644. Terrain has no team colour, so P656 does not need
    it.
- **Units stay generator SVG** (ADR 0050 §1 as amended). They take P655's gains in SVG, in one
  row, P658, over all 18 detail-2 models (and P643's four, if P643 merges first). It splits into
  P658a (Ironward) and P658b (Facet) only if its production diff goes over about 400 lines.
  - Darker gunmetal neutral bodies, as new materials, not the shared iron and steel.
  - The team colour on the turret and the skirt or side panels.
  - A gun 0.2 tile longer. A taller turret gave no gain and is not taken. If the longer barrel
    would move projectile spawns (muzzle points in `game/view` or `data/`), that change is a
    separate row.
  Ironward goes first. Facet keeps its own white and graphite language.
- **P658's same-scene gate is met.** It was a throwaway measure on `main` at c09c91be, with
  nothing committed. Both models pass every band of the frozen `same_scene.tres`:

  | Model | Body materials | `tone_sat` | `tone_sat_all` | 32 px spread | TEAM_SHARE | Max mirror overlap |
  | --- | --- | --- | --- | --- | --- | --- |
  | Ironward `heavy_tank` (P652 swap, gunmetal step s3) | iron #2B2E32, steel #5C6066, body #4A4D52 | 0.132 | 0.379 | 142.5 | 43.2 % | 0.78, 0.685 with the longer gun (spread -3) |
  | Facet `renew_tank` (t2) | graphite #2B2E32, titanium #5C6066, white kept | 0.113 | 0.325 | 199.5 | 52.1 % | — |

  **Two bands bind, and they set the design limit.** `black_edge_max` (0.02) binds first: iron
  #212427 gives 0.223. `light_left_min` (-0.04) binds second, on Ironward only: s3b #25282B gives
  -0.042. So no body tone goes darker than about #25282B, and a right side is never much darker
  than its left.
- **3D units are an open decision for Michael**, taken after he has seen 3D terrain and buildings
  in the game with the SVG units on top (row P659, after P644). No unit row is planned now. If he
  says yes, a new ADR (or an amendment of this one) and a plan follow. P655 is their starting
  point, `heavy_tank` first.
- **The pipeline stays ready for units.** Nothing in §4, §5 or §7 is building-only:
  - the hull and turret rig and the turret mount (`IsoSheetDef.mounts`);
  - 16 directions (8 for squads);
  - the keyed-part recolour;
  - the trimmed directional frames of `IsoAtlas`.
  The bake tool keeps P655's rig, and `IsoAtlas`'s PNG path takes any sheet.
- **P653 and P655 stay prototype branches**, the references for this ADR, and are never merged.
  Row P656a promotes their tooling into `tools/prerender/`, rewritten and linted (P655's
  `DetailTank.gd` fails `gdlint`'s file length). It is not copied as it is.

### 2. ADR 0050's "no PNG on the map" is reversed for terrain and buildings
- ADR 0050 answer 1 ("ja, kør med generator-SVG og Figma AI til menuer") chose generator SVG for
  everything on the map. Michael's answer 2 above reverses that for terrain and buildings. The
  PNG frames come from our own renderer (§5), never from Figma, Figma AI or another tool.
- **What of ADR 0050 still binds the pre-rendered art:**
  - §8's one look and same-scene check;
  - the team panels and their bands (A1-A7);
  - the building byte budget (§1's byte column);
  - the detail rules: no bolts on faces over 0.25 tile², panel cells at least 0.3 tile, hazard
    stripes at least 6 px at 2x;
  - §2's facet form as the Facet target (`round2/figma_facet_hq_1_0.png` on
    `claude/p601-style-proto`);
  - item cards that match their sprite.
- **What stays SVG:**
  - units (§1);
  - fields and the wellhead, ore, effects, damage overlays, glyphs, icons and the UI;
  - the menu pictures (ADR 0050 §2, ADR 0052).
  A later row may move fields and the wellhead to the kit, if the same-scene sheet asks for it.
- The units' SVG rules (ADR 0050 §3 as amended, L2 detail, the sentinel key) do not change.

### 3. Density: 1x only, never 2x
- **Every pre-rendered frame is at the sorted world's density:** two texels per world px, so a
  ground diamond is 128 x 64 texels and a sprite has its sheet canvas in texels. This is P653's
  "1x".
- **For buildings** that is exactly today's frame size, so page 1's rows do not move (§7).
- **For the ground** it is twice the linear density of today's 64 x 32 texel diamonds. The kit is
  about 4 MB against today's 0.4 MB (P653), and the ground layer draws its tiles at scale 0.5 (§7).
  The kit's tiles have to sit under the 1x sprites without looking softer than them.
- **2x is ruled out** for every class: about 350 MB and 7 pages for the roster, 4 pages for page 1
  alone. That breaks the single sorted page (ADR 0023 §2), ADR 0027 §4's 3584 rows and rule 6
  (P653, P655).
- The only density lever is ADR 0050 §6's `bake_scale` of about 1.1, with the same cost and
  verdict there (not now).
- **The bake renders supersampled and box-filters to 1x in linear light.** P653 used 8 texels per
  art px for units and 4 for terrain and buildings.

### 4. Team colour: a hue-key recolour in linear light, run once at match start
- **The formula** (P653 `recolour2`, measured in P653 and P655), per pixel, in linear light, on
  straight (not premultiplied) colour `s`:
  - `m = min(R, B)`.
  - `w = clamp((m - G) / m / k, 0, 1)`, with `k = (A_s.r - A_s.g) / A_s.r` of the sentinel
    albedo `A_s` (0.947 for `#D234D2`), and `w = 0` where `m` is about 0.
  - `E_r = w R / A_s.r`, `E_b = w B / A_s.b`, `E_g = (E_r + E_b) / 2`.
  - `out = s + E × (A_t - A_s)`, where `A_t` is the target albedo, clamped at 0.

  `A_s` is the sentinel triad's mid (STYLE.md "The sentinel key triad", `#D234D2`). `A_t` is the
  player's triad mid (`WorldSort.TRIADS`). The light and dark tones of a triad are not used by
  pre-rendered art, because the light makes the shading. Alpha is copied unchanged.
- **Where it runs: one GPU pass per player at match start, never per frame.**
  - `game/view/team_recolour.gdshader`: a `canvas_item` shader with
    `render_mode unshaded, blend_disabled`, the two albedos as uniforms (linear) and nearest
    filtering.
  - `game/view/TeamRecolourPass.gd`: a Node that `WorldSort` owns. It draws one strip image per
    player (that player's keyed PNG frames) through the shader into a `SubViewport` with
    `transparent_bg` and `UPDATE_ONCE`, reads it back with `get_texture().get_image()`, and
    gives the image to `IsoAtlas`.
  - `IsoAtlas` packs the result into that player's slots, as it packs today's per-player SVG
    frames. The page, its regions and its offsets are what they would be for SVG frames.
  - The sorted world keeps no material and stays one draw call "in white" (ADR 0023 §2). Draw
    calls, memory and frame time while playing do not change.
- **The GDScript twin** `game/view/TeamRecolour.gd` (RefCounted, static, on `Image`) is the
  reference, like the native kernels' twins (ADR 0013). It also serves:
  - the tests;
  - the same-scene composer (`tools/artgen`, headless);
  - the bake's item cards, which are recoloured in the faction colour (A1), so the Python post
    never recolours;
  - a fallback, with `push_error`, if the pass fails on a device.
  Its `coverage(image)` (the sum of `w` over opaque pixels) is how TEAM_SHARE and KRITISK are
  measured on pre-rendered frames (§9). A CPU recolour of about 3 M texels per player in
  GDScript would take seconds on a phone. That is why the match uses the GPU pass.
- **Compatibility and web constraints of the shader:**
  - The GLSL ES 3.0 / WebGL 2 subset only: `texture()` with `filter_nearest` and
    `repeat_disable`, no `SCREEN_TEXTURE`, no derivatives, no loops, no integer textures.
  - The 2D path in Compatibility has no HDR and no linear 2D. The texture holds sRGB-encoded
    8-bit values, so the shader does the exact piecewise sRGB-to-linear conversion and back
    itself.
  - The fragment math is declared `highp`. Mobile `mediump` would band the light recovery, and
    WebGL 2 guarantees `highp` in fragment shaders.
  - It writes straight alpha (`blend_disabled`) into a transparent RGBA8 target, so the readback
    is not premultiplied.
  - The readback (`glReadPixels`) works on GLES3 and WebGL 2. ASTC and ETC are not used: the PNG
    decodes to an RGBA8 `Image`, as the SVG does today.
  - **Sync or async readback.** P644a takes `RenderingServer.force_draw(false)` and then the
    readback in the same call if it works on desktop, Android and the web preview. If not, it
    takes an awaited `frame_post_draw` while the loading card shows. Either way, no frame of the
    match is drawn before the pass is done, so the sentinel magenta is never on screen.
- **Under the dummy renderer** (headless tests, the sim smoke), the pass does not run. Keyed
  frames stay in the sentinel, with the same page, regions and offsets. A test that needs
  colour uses the twin on a fixture.
- **Render rules the formula depends on** (checked by the bake, §5):
  - The sentinel material is rendered at the exact mid albedo. Sun, fill and ambient are set so
    that a lit top face stays at or below 1.0 in linear light. A frame with a clipped sentinel
    pixel is refused.
  - No non-linear grade comes between the render and the recolour. An exposure gain commutes with
    the formula and is allowed. Contrast and saturation (P653's post grade) do not commute: the
    look gets them from the lights and the materials instead.
  - No material other than `team` lies in the key band (hue within 20° of 300° at a saturation of
    0.30 or more). This is ADR 0050 §3's key-band rule, applied to the 3D materials and checked
    on the model data.
- **One copy of the formula ships**: the shader, with the twin as its reference. The Python post
  of §5 does not recolour.

### 5. Renderer and bake: a tool in a pinned container; committed PNGs; CI checks, never re-renders
- **The game does not change renderer.** The game stays Compatibility (CLAUDE.md Stack). The bake
  is a developer tool. It runs Godot 4.7.2 (the pinned engine) headless under `xvfb-run`, on
  Forward+ over Vulkan with Mesa lavapipe, for SSAO. Blender is not used.
- **Pinned bake image** (the versions P653 measured), checked by `scripts/prerender.sh` before
  any render:
  - Ubuntu 24.04.5 LTS;
  - `mesa-vulkan-drivers`, `libgl1-mesa-dri`, `libglx-mesa0`, `libgbm1` and `mesa-libgallium`,
    all `25.2.8-0ubuntu0.24.04.5`;
  - `libllvm20` `1:20.1.2-0ubuntu1~24.04.3`;
  - `xvfb` `2:21.1.12-1ubuntu1.9`;
  - Python 3.13 with numpy 2.5.3 and Pillow 12.3.0 (`tools/prerender/requirements.txt`).
  On any other version the script stops and names what differs (CLAUDE.md: say what is missing
  and stop). It installs nothing by itself.
- **The code lives in `tools/prerender/`:**
  - the mesh builder: P653's `ArtMesh` faces with bevel strips, and P655's plane-clipped solids,
    cylinders, domes and tori;
  - the camera and light rig at `IsoProjection`'s angles, with its constants read from
    `IsoProjection` and `ArtShadow`, never copied;
  - the bake scenes;
  - the Python post: a linear-light box filter to 1x, the exposure gain, and PNG write.

  Code there is MIT, like `tools/artgen`.
- **The model data is the source** (ADR 0046's reserved scope):
  - The building's `ArtModel` under `assets/art/models/` stays the source of its footprint,
    silhouette, anchors, cuts, emitters, lifts and damage rules (`char`, `hide`).
  - The 3D detail of each building is data next to it, in
    `assets/art/models/<faction>/<id>_detail.tres` (parts, materials, seeded variation).
  - It is never GDScript per building. P655's code-built tank was right for a probe. In
    production the art is data, all rights reserved, and the builder is code, MIT.
- **One writer per file:**
  - `tools/artgen` still writes every sheet (`IsoSheetDef`: sizes, anchors, cuts, parts,
    frames). For an id the pre-render owns (`tools/prerender/owned.tres`, one list), it writes the
    `.png` frame and card paths, and it writes no SVG frame or SVG card.
  - `tools/prerender` writes only that id's PNG frames, its card and the manifest.
  - `gen-art.sh --check` stays byte-stable over the sheets.
- **Frames keep the sheet's canvas and anchor.** A pre-rendered frame has the artgen sheet's
  canvas, anchor and cut row for its part, so it overlays today's frame exactly (P653 checked
  this on `vehicle_factory`).
  - Shadows are a separate frame: the geometry flattened along +gx by `ArtShadow.REACH`, unlit
    black at the same-scene band's alpha (0.3-0.4), as P653 did.
  - Self-shadowing and SSAO are baked into the hull, the head and the anim frames.
- **Committed outputs and the manifest:**
  - The PNGs go to the sheet's folder (`assets/art/iso/<faction>/bld/<id>_<part>.png`; cards
    `assets/art/iso/icons/item_<id>.png`). The kit goes to `assets/art/terrain/`.
  - Encoding: 8-bit RGBA, sRGB, straight alpha, and no time, gamma or ICC chunks, so the bytes
    depend only on the pixels.
  - `assets/art/prerender/manifest.tres` lists every PNG with its sha256, bytes, size in texels,
    its source model files' sha256 and the renderer stamp. The stamp is Godot's renderer line
    (for example "Vulkan 1.4.318 - Forward+ - llvmpipe") and the Mesa version.
  - **CI checks, it never re-renders.** A headless gdUnit4 test checks:
    - every PNG against its manifest line (hash, bytes, size);
    - that no PNG is missing from the manifest;
    - the budgets of §7;
    - that each frame's size is its sheet's canvas at its part's factor;
    - that a model file whose hash moved without a re-bake fails, naming the id.
- **The determinism caveat.** A bake is byte-identical only on one Mesa build: other Mesa, LLVM
  or a real GPU differ in the low bits.
  - `scripts/prerender.sh --check` re-renders and compares only when the stamp is the pinned
    one.
  - Moving to another image is an explicit **re-bake row**: every PNG and the manifest are
    regenerated in one PR, and Michael sees the same-scene sheet. It is never a CI failure path.
  - A model change re-bakes only its own ids.
- **Imports:**
  - Building frames use the `keep` importer and are read with
    `Image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))`, as the SVG text is read
    today. The pck carries the PNG bytes once.
  - Kit tiles and cards import as lossless 2D textures (`compress/mode` 0, no mipmaps), as
    today's diamonds and cards do.
  - If the atlas's fit lowers `bake_scale` below 1.0, PNG frames are resized with
    `Image.INTERPOLATE_LANCZOS` after the recolour. At 1.0 nothing is resized.

### 6. Legal
- **Geometry, materials and textures** come only from this repo's model data and code: the
  `ArtModel` files, the `_detail.tres` data and the `tools/prerender` builders. Noise, sky and
  materials are Godot built-ins driven by our parameters. Never allowed:
  - asset packs, scans, HDRIs or web textures;
  - sculpt imports;
  - AI generators, Figma AI included, for map art.
- **Figma file `HsBPSXZ6PTRp6KkdhEi6bT`** is a look reference only, under ADR 0049 §1's tool rules:
  - nothing is traced, measured to copy or imported;
  - screenshots stay in the scratchpad, and no Figma pixel is committed;
  - none of its names are taken (Helix, Prisme, Aegis);
  - its building list, which reproduces Red Alert's tech tree as a set, is not followed.
  The ids stay ours (`vehicle_factory`, `renew_hq` …), and the names stay those of ADR 0049 §6
  and ADR 0023 §7.
- **Ownership** (ADR 0046):
  - The PNGs and the `_detail.tres` data are under `assets/`, so they are "Copyright (c) 2026
    AppCode ApS. All rights reserved."
  - `tools/prerender` is MIT.
  - `assets/CREDITS.md` gets one own-work row per group: the kit, each building batch and the
    cards. Each row names the source model files and "rendered by tools/prerender", with the
    licence "All rights reserved (AppCode ApS)".
- **CLAUDE.md lines, approved by Michael's answer 2** (2026-11-27). The lead edits CLAUDE.md, not
  a row:
  - **Legal,** "Assets: only SVG authored in this repo …": add "or PNG rendered in this repo by
    `tools/prerender/` from the repo's own model data (ADR 0053)".
  - **Layout:** add `tools/prerender/`, the bake of terrain and buildings, 3D models to PNG frames
    (ADR 0053).
  - **Stack:** add one clause saying Forward+ over Vulkan is used only inside the offline bake
    tool, and that the game stays Compatibility.
  CLAUDE.md's Legal, Layout and Stack lines are edited by the lead (approved by Michael's answer 2), before any PNG art merges (P656 / P644). The tool rows (P656a,
  P656b) can merge before that.
- **The `svg-art-style` skill** (ADR 0050 §4's "Stand-alone pictures" bullet, if P630b applied
  it) gets a matching note through the lead. No skill is edited in this PR.

### 7. Budgets and wiring
| | Today | After | Gate |
| --- | --- | --- | --- |
| Atlas pages (cross-faction) | 2748 / 2594 rows | **Unchanged for building bodies**: same canvases. Heads (16 directions) are trimmed, so within the 40-row tolerance | Every page under 3584. P644-P647 pin the rows |
| Atlas memory | About 86-88 MB | Unchanged | ADR 0027 §4 |
| Ground page | 12 diamonds and fields, about 0.4 MB | The kit: about 80 tiles, about 4 MB (P653) | At most 512 rows of 4096 px (8 MB), the look included |
| Building PNG on disk | 1.38 MB of SVG | About 3.5 MB (7.95 M texels at P653's 0.44 B a texel) | Per frame the ADR 0050 §1 bytes: 3x3 128 KB, 2x2 80 KB, 1x1 48 KB. P653's `vehicle_factory` hull and shadow: 105 KB for both |
| Kit PNG on disk | 0.4 MB | About 4 MB | At most 5 MB |
| APK and web export | — | About +7.5 MB. PNG does not shrink further in the pck, and the SVG it replaces packs 8-10 times | At most +10 MB, reported per PR |
| Mesh (bake only) | Blockouts of 20-40 primitives | At most 60,000 triangles per building (P655's tank: 42,032) | The bake tool refuses more |
| Match-start bake | `atlas_bake_ms` | PNG decode in place of the buildings' SVG raster, plus one pass and readback per player (about 3 M texels, 12 MB) | ADR 0050 §5: at most twice today's on the reference phone. CI reports it (no timing runs in a session) |
| Draw calls | Forecast 18 (ADR 0035 §7) | Sorted world unchanged. Ground: at most +1 (the edge layer) | 19. P656d moves `PerfBases`' constants with their test if it adds the layer |
| 150 units at 60 fps | — | Unchanged at 1x: same quads, the same one page, no material, no per-frame work in the ground layer | P659's phone card |

- **Building frames and damage stages** (ADR 0029, ADR 0034, ADR 0050 A7):
  - The frames per building are today's sheet: `hull` 1, `dmg2` 1, `shadow` 1, `anim` n (each
    crop at most a quarter of the body) and `head` 16. No `dmg1`.
  - `dmg2` (KRITISK) is the same mesh posed with the model's `char` and `hide` rules: charred
    materials and the hidden parts removed. It is rendered at `DAMAGE_SCALE` and cut at the
    sheet's cut row, so the Damage child's trim rule (`IsoAtlas`) holds as it is.
  - KRITISK keeps 20 to 50 % of the intact frame's key coverage (ADR 0029 §5, A7). A charred team
    face is rendered in a non-key material, so it leaves the band wholly.
  - The collapse, the crater, the hit flash and the chips stay view code (ADR 0029).
- **Detail scale** (P655: below about 2 art px is lost at 1x): nothing under 2 art px across is
  modelled (rivets, hinges, fine seams). It would only add noise and triangles.
- **Ground wiring** (`GroundLayer`, `GroundAtlas`; the sim/view split is unchanged):
  - **What it reads.** The view chooses each cell's pieces from the snapshot's terrain grid and
    the map's `ground_look`. Nothing is stored in the sim, and no `data/` file changes: the kit
    description `assets/art/terrain/kit.tres` holds only art mappings, no balance numbers.
  - **The piece choice is a pure static function of:**
    - the cell's and its 8 neighbours' terrain ids;
    - the look;
    - a fixed integer hash of the cell's coordinates, which picks one of up to 4 variants.
    It never uses `randi()` or a `DetRandom` (rule 3). It is unit-tested with tables.
  - **Two tile layers on the one kit texture:**
    - the base layer: one flat piece per cell (a road piece replaces it where a look lays a road);
    - the edge layer: at most one piece per cell (a blend into the lower-priority terrain, a
      shore at water, a cliff lip at rock).
    Both draw their 128 x 64 texel tiles at scale 0.5, as the sorted world draws its 2x art.
  - **The lip rule.** A piece may rise at most 36 texels (18 world px) above its diamond. It may
    only rise over cells that block every move class (rock or water, `TerrainDef.cost` 0 for all
    three). The ground draws at z 0, under the sorted world, so no unit or building can stand
    behind a lip and be drawn over it. A test checks the rule on every shipped map.
  - **Writes.** The first fill writes every cell once. A `map_version` change rewrites the
    changed cells and their 8 neighbours, at most 9 writes per changed cell. There is no
    per-frame work.
  - **Fallback.** A terrain or look with no kit piece uses today's SVG diamond path, so
    `covers_map()` holds and no map shows a hole.
  - The fog, the minimap, `MapView`'s bake and `MinimapImage` are unchanged. They read the sim's
    terrain.
- **Roads are decoration** in a map look's decor list, under `assets/art/terrain/looks/`. They do
  not change movement, because the sim has no road terrain. A road that sped units up would be a
  sim and balance change for a later phase (question 4, answered: decoration only). `HOW_TO_PLAY.md` says roads are only
  looks.

### 8. Same-scene coherence with SVG units on pre-rendered terrain (ADR 0050 §8)
The sheet shows the SVG units and the pre-rendered buildings on the kit's ground. Recoloured
buildings come from the twin, because the composer is headless. `same_scene.tres` stays frozen
(A8). The ground bands go into a new file, `tools/artgen/same_scene_ground.tres`, which is not
frozen; its bands change through review.

| Band (`same_scene.tres` unless named) | Units (SVG) | Buildings (PNG) | Terrain kit |
| --- | --- | --- | --- |
| Light order (`light_up_min`, `light_left_min`) | yes | yes | On the pieces with raised faces only: cliffs, shore banks, boulders |
| Shadow direction (`shadow_dx_min`) | yes | yes | Yes, for the shadows baked into pieces (boulders, lips) |
| Shadow alpha (0.3-0.4) | yes | yes (shadow frame) | No: baked ground shadows are judged by eye |
| `tone_value`, `tone_sat`, `tone_sat_all_max` | yes | yes | No: they bound a sprite's neutral body, and the ground has no faction or team material |
| Edges (`black_edge_max`, no black outline) | yes | yes | Yes |
| Detail density (30-75 edges per 100 px² at zoom 1) | yes | yes | No. The ground has its own ceiling instead: at most the units' floor (30), so every sprite reads busier than the ground |
| Readability (32 px greyscale, `spread_min` 80) | yes | yes | Measured for every sprite over each kit terrain |
| **New, `same_scene_ground.tres`:** the ground's mean saturation | — | — | At most 0.30 (`tone_sat`'s ceiling), so the ground stays calmer than the panels |
| **New:** ground pixels in a route triad's hue band at a saturation of `faction_sat_min` or more | — | — | At most 5 %, so sand and dirt never eat an orange or blue panel |
| **New:** key band (hue 300 ± 20°, saturation 0.30 or more) | — | — | 0 pixels |

P656e sets the new bands from today's diamonds and the kit, and attaches the sheet. If the kit
fails a band from the frozen file, the row stops and brings its numbers to the architect. Michael
judges the look in P659.

### 9. Tests (what is proven headless, and what is not)
- **Headless (gdUnit4):**
  - The manifest and budgets (§5, §7).
  - The twin against fixtures:
    - mean error at most 3.5/255, p99 at most 40, at most 2 % of team pixels over 12/255 and at
      most 2 magenta fringe pixels a frame, against a committed ground-truth re-render in a
      target colour;
    - 0 clipped sentinel pixels;
    - `coverage` exact on crafted mixes.
  - TEAM_SHARE by coverage, 30-65 % in the default view, and KRITISK at 20-50 % of the intact
    coverage.
  - The shape pairs under 0.85 (A4) and the 32 px greyscale spread at least 80.
  - Same-scene audit green, with the frozen bands, plus the ground bands.
  - Ground: the piece-choice tables, the lip rule on every shipped map, the write bounds,
    `covers_map()` and the fallback.
  - `IsoAtlas`: a PNG sheet packs to the same regions and offsets as an SVG sheet of the same
    canvases. Under the dummy renderer the keyed frames are left in the sentinel.
  - Mesh builder: face counts and normals, and the triangle cap.
  - `scripts/prerender.sh`'s version preflight: its exit codes.
- **Render test, CI only** (like the sanitizer harness, ADR 0013 §10): `TeamRecolourPass` under
  `xvfb-run` with Compatibility (`--rendering-driver opengl3`) on the runner's Mesa. It compares
  the shader with the twin on the fixtures, to at most 1/255 per channel. P644a adds the CI step.
  A runner without xvfb is a missing tool: the row stops and says so.
- **Not headless:**
  - the look (Michael, P659);
  - the softness at zoom 2.0 (ADR 0050 §6);
  - the bake and the readback time on the phone (CI's `atlas_bake_ms`, the phone card).

## Consequences
- Terrain gets what it has never had: roads, cliffs, shores, blends and variety. Buildings get
  lit material, edge light and occlusion. Units keep the cheap SVG path and get P655's palette
  and silhouette.
- The map has two art sources: generator SVG for units and pre-rendered PNG for terrain and
  buildings. ADR 0050 §8's same-scene check is the guard against a mixed look, now with ground
  bands.
- Runtime cost is unchanged: the same page, the same quads, no material. Match start gains one
  GPU pass and readback per player. Memory is unchanged for the atlas, and the ground page grows
  by about 4 MB.
- The export grows by about 7.5 MB, and the repository by the PNGs.
- The bake needs a pinned container. A Mesa upgrade becomes a re-bake row, not a broken CI.
- Model detail is data under `assets/`, all rights reserved. The builders are MIT code.
- Two more places have to agree: the shader and its twin. A CI render test ties them together.
- `gen-art.sh` stops writing SVG for owned ids, and their SVG frames and cards are deleted when
  their PNGs land.
- The decision on 3D units waits for Michael's eye (P659). The pipeline is ready for them.

## Alternatives considered
- **Everything pre-rendered now, units included.** Rejected by Michael's answer, and by P655: at
  83 px the detail is lost, and about 35 to 50 rows of modelling would buy mostly palette and
  silhouette, which SVG can give cheaply (P658).
- **2x density.** Rejected: about 350 MB and 7 pages (§3).
- **A recolour material on the sorted world at runtime** (team index in each sprite's modulate,
  one shader for all sprites). Rejected:
  - it costs fill on every sprite pixel, every frame, on the phone, and that cost was never
    measured (rule 6);
  - it ends the sorted world's "in white" rule;
  - it conflicts with the layers that dim by modulate.
  It would save the per-player copies of the building frames. That saving is a lever only, if
  memory ever runs short.
- **A material only on building sprites.** Rejected: it breaks the sorted world's batch at every
  switch between a unit and a building.
- **A CPU recolour in GDScript at match start.** Rejected: about 3 M texels per player, seconds on
  a phone. It stays as the twin and the fallback.
- **Pre-baked PNGs per triad** (8 per keyed frame). Rejected: about 8 x 3.5 MB on disk and in the
  export.
- **Re-rendering in CI and comparing bytes.** Rejected: bytes are stable only on one Mesa build
  (§5).
- **Compatibility for the bake.** Rejected: it has no SSAO, and the occlusion is much of the gain.
- **A whole map baked as patches.** Rejected: 2.9 MB per 8 x 8 patch, 183 MB for a 64 x 64 map
  (P653).
- **Code-built meshes per building** (P655's `DetailTank.gd`). Rejected for production: art
  belongs in reserved data, and a 1,200-line file per model fails the lint and the review.

## Questions for Michael (answered 2026-11-27: "Godkend alle 7 (anbefalet)")
1. **Accept this ADR as written**: 1x only, team colour by one GPU pass at match start, a pinned
   bake container, and CI checking hashes without re-rendering. Recommended: yes.
   **Answered:** "Godkend alle 7 (anbefalet)". Accepted as written.
2. **CLAUDE.md**: allow "PNG rendered in this repo by `tools/prerender/` from our own model data"
   in Legal, add `tools/prerender/` to Layout, and note in Stack that Forward+ is used only in the
   bake tool (§6). Recommended: yes. The lead edits CLAUDE.md.
   **Answered:** "Godkend alle 7 (anbefalet)". Yes; the lead edits the three lines before any PNG art merges
   (P656 / P644).
3. **Size**: the APK and the web build grow by about 7.5 MB, capped at 10 MB. Recommended: yes.
   **Answered:** "Godkend alle 7 (anbefalet)". Yes: about +7.5 MB, at most +10 MB.
4. **Roads**: decoration only in the map looks, with no speed change (recommended). The
   alternatives are no roads now, or later as a real terrain with a speed change (a sim and
   balance change, a later phase).
   **Answered:** "Godkend alle 7 (anbefalet)". Roads are decoration only (P656f).
5. **The Facet buildings and the small buildings wait for your look check** (P645 after P659), so
   nothing is made twice if you say no to 3D buildings. Recommended: yes.
   **Answered:** "Godkend alle 7 (anbefalet)". Yes: P645-P647 wait for P659.
6. **The SVG unit restyle toward P655** (P658, one row for all 18 detail-2 models): darker
   gunmetal bodies, team colour on the turret and the skirt or side panels, a gun 0.2 tile longer;
   Ironward first, Facet in its own white and graphite. The gate measure already passes every
   frozen same-scene band (§1), so no band moves. Recommended: yes.
   **Answered:** "Godkend alle 7 (anbefalet)". Yes: P658's steel look, as one row.
7. **The ground in the same-scene check** gets its own bands (§8): calmer than the units, at most
   5 % of it in the orange or blue hue, and no magenta. Recommended: yes.
   **Answered:** "Godkend alle 7 (anbefalet)". Yes: separate, calmer ground bands in `same_scene_ground.tres`.
