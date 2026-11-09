# ADR 0035: Visual polish: fog tint, a soft map edge, a world grade, and team colour under units

**In short, for Michael:** the parts of the eight polish proposals that change earlier decisions.
Unexplored ground becomes a very dark blue-grey instead of black; the map's edge fades into a mist
instead of ending on a hard line; the whole battlefield gets a light warm/cool grade and a soft
vignette; units stand on a pad in their team colour and the selection ring takes your colour. The
fog's soft edge at the limit of sight stays one tile wide, and nothing uses additive blending or a
shader.

Status: **proposed 2026-11-09** (P200, architect, on `main` at b6bfe95). Michael said yes to the
eight proposals of art-director's board on 2026-11-09; this ADR records how they fit the accepted
ADRs and what changes in them. Questions 2 and 3 of the plan
(`docs/plans/2026-11-09-visual-polish.md`, "Questions for Michael") decide §1 and §4.3. Revised
the same day after the docs lens: the Hud's layer (§3), what the canvas tint covers (§3), the
forecast's figures and where the code prints them (§7), the `data/` rows (§5).
Amends, on acceptance: ADR 0010 §2 (fog colour), ADR 0023 §2 (the z table and the draw-call
forecast) and §5 (key colours in shadow frames), ADR 0027 §9 (the forecast it carries), the GDD's
"unexplored is black". Keeps: ADR 0029 §6's rejection of additive blending, ADR 0023 §2's
"nothing tints a sorted sprite", ADR 0022 question 3's team share of a model, ADR 0011 §3's
one-texture ring.

## Context
- **The board** (art-director, Figma "Polish proposals", 2026-11-09): 1 contact shadows and ambient
  occlusion, 2 selection ring and health bar, 3 team-colour pad, 4 build cards, 5 ground variety,
  6 day-tint grade and vignette, 7 muzzle flashes and impact bursts, 8 fog and map-edge softness.
  Michael: "ja" to all eight. Most are art or view work inside today's rules (the plan's rows); four
  touch accepted text:
  - **8** proposes "a cool blue-grey fog with a long soft falloff". ADR 0010 §2 makes each fog
    texel "one tile of black", and the GDD says "unexplored is black". A longer falloff at the
    limit of sight would shade tiles the player sees and leave seen enemies standing in a half-dark
    (ADR 0010 §2's one-tile edge, `tests/view/test_fog_hiding_edges.gd`).
  - **6** adds a full-screen layer and a canvas tint. ADR 0023 §2's z table and its forecast (16,
    ADR 0027 §9) list neither; "nothing tints a sorted sprite" is about per-sprite tints.
  - **3** bakes the key triad into a unit's shadow frame. ADR 0023 §5 and `IsoAtlas` bake a frame
    with no key colour (a shadow) once per faction; ADR 0022 question 3 holds a model's team share
    at about 8-12 %, and STYLE.md says team colour is "never a large plate".
  - **7** names additive blending for the flashes. ADR 0029 §6 rejected additive blending (a
    material on its own canvas item, one more draw call) for one alpha glow pass.
- **Budgets:** CLAUDE.md rule 6 (150 units at 60 fps on a mid-range 2021 phone, Compatibility),
  `data/dev/perf_gate.tres` (`draw_calls_max` 60, `work_p95_ms` 5.6), the MultiMesh trigger at a
  forecast of 40 (ADR 0023 §2), ADR 0027 §9's life budget, the sorted world's one page of at most
  3584 rows (`tests/view/test_iso_atlas_budget.gd`; 3550 cross-faction today, about 100 rows freed
  by ADR 0034).

## Decision
### 1. The fog's colour (amends ADR 0010 §2 and the GDD line; plan Q2)
- A fog texel is `fog_rgb` (from `data/look_settings.tres`, §5) with the alpha ADR 0010 §2 gives:
  255 unexplored, `explored_alpha` (140) explored, 0 visible. `fog_rgb` is a dark cool blue-grey
  that art-director picks in STYLE.md with a greyscale check: its luminance is at most 40 (black is
  0, the off-map colour #16191D is 25), so unexplored ground still reads as "never seen" and the
  explored dim keeps every ground under 60 (STYLE.md's x 0.45 table moves by at most 10 levels).
- **The soft edge at the limit of sight stays one tile** (one texel per cell, linear filtering), and
  the hiding rules of ADR 0010 §2 and the tracer clip stay. The proposal's long falloff is taken at
  the map's edge only (§2).
- If Michael keeps black (Q2 option A), `fog_rgb` is #000000 and §2's mist still applies.

### 2. The map's edge (new; amends ADR 0023 §2's z table)
- `MapEdge` (a `Sprite2D` or one textured polygon, `game/view/MapEdge.gd`) at z 4, after `FogLayer`
  in the tree, under the iso transform of the fog: one low-resolution mask texture of
  `(cols + 2m) x (rows + 2m)` texels (m = `edge_outer_tiles`), linear filtering, one draw call.
- Inside the map its alpha rises toward the edge over at most `edge_inner_tiles` (at most 2) to at
  most 0.6, on the ground only (z 4, under every object), so a unit at the edge stays crisp.
  Outside the map the mask shades from a mist band to the off-map colour; the band's peak is at
  least 20 grey levels above both the unexplored fog and the off-map colour, so where the map ends
  still reads (STYLE.md's reason for an off-map colour that is not the fog's holds).
- The camera clamp (ADR 0023 §4), picking and the minimap are unchanged. The clear colour stays
  `GroundLayer.OFF_MAP_COLOR` (one writer).

### 3. The world grade (amends ADR 0023 §2's z table)
- **A `CanvasModulate`** in the world canvas with each channel at least 0.90: one colour for every
  item of that canvas, applied by the renderer as one canvas-wide factor, so no batch splits and no
  sprite is tinted on its own ("nothing tints a sorted sprite" holds). The HUD's `CanvasLayer` is
  not affected.
- **What it tints:** every item of the world canvas, `FogLayer` and `MapEdge` (§1, §2) included,
  so the fog's and the mist's luminance bounds (P213's table) are measured after the modulate. The
  clear colour (the off-map colour) is not a canvas item and is not tinted: `MapEdge`'s outer end
  is chosen to meet it after the modulate.
- **Layers:** the `Hud` `CanvasLayer` moves from the default layer 1 to **layer 2** in both
  `scenes/main.tscn` and `scenes/dev/perf_arena.tscn`, and `WorldGrade` takes **layer 1** (layer 0
  is the root canvas, where the world and the `CanvasModulate` are). The order does not rest on
  tree order between equal layers; a test pins `WorldGrade.layer < Hud.layer` on both scenes.
- **A `WorldGrade` `CanvasLayer`** at layer 1, holding one full-rect
  `TextureRect` of a small gradient texture (warm from the top left, cool to the bottom right, and
  a vignette), `mouse_filter` IGNORE, alpha at most `grade_alpha_max`. One draw call and one
  blended full-screen fill. It is screen-fixed: a grade, not a light, so it does not move with the
  map. With reduced effects (`LifeSettings.reduced`) the quad is hidden; the `CanvasModulate` stays.
- No shader, no screen-reading pass, no blur (Compatibility, web).

### 4. Team colour under units and on the ring (relates to ADR 0022 Q3 and ADR 0023 §3, §5)
1. **Pad:** a unit's shadow part may hold a pad in its faction's key triad under the hull (the
   contact shadow and the cast shadow of `ArtShadow` drawn over it). Such a shadow frame touches a
   key colour, so `IsoAtlas` bakes it per player by its existing rule; a cross-faction page bakes
   each faction for one player and does not grow by it, a mirror page bakes the unit shadows twice.
   The 8-12 % team share of ADR 0022 question 3 stays a rule of model frames (`test_artgen_plates`
   checks models, not shadows); the pad is a mark on the ground, not a plate on the model.
2. **Ring:** the selection ring is one SVG with the key triad in an outer band and STYLE.md's white
   band with its dark outline kept inside (the colour-free cue of "Shape as second cue"). At match
   start it is baked once with the local player's triad (the `IsoPlayerArt` replacement, one small
   `ImageTexture`): only own units have rings, so every ring shares that one texture with white
   modulate, as today (ADR 0011 §3, one call). The building frame keeps white and amber.
3. **Page fallback** (plan Q3): if the shadows with their pads and occlusion pass 3584 rows on any
   page after ADR 0034's rows are freed, unit and building shadow frames bake at `SHADOW_SCALE` 0.75
   (soft shapes, the loss does not show), as ADR 0028 did for the damage patches. Option B, a
   separate pad sprite per unit from one small texture, costs one draw call and 150 nodes.

### 5. View-only look data
- `game/view/LookSettings.gd` and `data/look_settings.tres` (view only, not balance): the grade
  colour, the gradient's colours and `grade_alpha_max`, `fog_rgb`, the mist colour,
  `edge_inner_tiles`, `edge_outer_tiles`, the edge alphas. Values come from STYLE.md's new section
  "Grade, fog and map edge" (art-director). Tests pin the bounds above, not the colours.
- `data/**` starts a balance run in `balance.yml`: the file is written whole in one row (P214),
  with every field P215 and P216 read, so P214 is the only row that writes `data/` and its merge
  starts one run (cancel it: no sim input changed, the result cannot change); P215 and P216 read
  the file and never write it.

### 6. Effects (keeps ADR 0029 §6)
- Proposal 7's look (a two-frame muzzle flash, a core flash and a flat dust ring at impacts) is
  drawn with normal alpha blending from the existing atlases: the bright core is in the frames. No
  material, no additive pass, no new ring: the flash is the existing `EffectsLayer` slot with a
  second region, the impact dust goes into `GroundFx`'s dust ring (`dust_slots`, as the
  factory-exit puff does). No new draw call.

### 7. The draw-call forecast (amends ADR 0023 §2 and ADR 0027 §9's figure)
- The figures are the ones the perf card prints (`game/ui/PerfBases.gd`: `CALLS_FORECAST` 16,
  `CALLS_STRIKE` 17, `CALLS_WORST` 22, pinned by `tests/ui/test_perf_bases.gd`). New: **18** in an
  ordinary moment (16 + `MapEdge` + `WorldGrade`), **19** while a strike is aimed or in flight,
  **about 25** at the worst moment (22 + `MapEdge` + `WorldGrade` + the health bars' tick pass).
  ADR 0027 §9's status note (the strike net's `draw_multiline` calls) is kept as it stands; it is
  not added into these figures. Under the trigger of 40 and the ceiling of 60.
- Plan row P216 (the last row that adds a layer) sets the three constants to 18, 19 and 25 and the
  card line's test; P219 and the phone card on the base arena confirm them.

## Consequences
- The GDD line "unexplored is black" and `HOW_TO_PLAY.md`'s Fog section row "Look at the map"
  (line 92: "Black ground has never been seen") change with P215 if Q2 is B.
- Every fog test that reads a texel's colour reads `fog_rgb`; the alpha tests are unchanged.
- Greyscale figures in STYLE.md are measured without the grade; the grade's bounds (each channel at
  least 0.90, the gradient's alpha at most `grade_alpha_max`) keep them within about 10 %, and the
  STYLE.md section records the graded figures for grass, sand, the explored dim and both triads'
  rings.
- A mirror match's page grows by the unit shadows of one faction (pads in key colours).
- Two more draw calls in an ordinary moment and one blended full-screen fill.
- The Hud's layer number changes (1 -> 2) in both scenes; nothing else reads it today.

## Alternatives considered
- **A longer soft edge at the limit of sight:** shades seen tiles and seen enemies; rejected (§1).
- **A fog or vignette shader, or a blur:** Compatibility and web cost, a material per item;
  rejected.
- **A light that moves with the map** (a world-space gradient): a node following the camera every
  frame, or a shader; rejected for the screen-fixed grade.
- **Additive flashes:** one more draw call per layer (ADR 0029 §6); rejected (§6).
- **A team-colour ring by `modulate` alone:** the dark triads (Kul #6E737A) would draw a ring as
  dark as grass; rejected for the baked two-band ring.
- **The pad as a separate sprite per unit:** the fallback of §4.3, not the first choice.

## Questions
In the plan, "Questions for Michael": Q2 decides §1 (A keep black, B blue-grey, recommended B), Q3
decides §4.3 (A `SHADOW_SCALE` 0.75, recommended; B a separate pad sprite).
