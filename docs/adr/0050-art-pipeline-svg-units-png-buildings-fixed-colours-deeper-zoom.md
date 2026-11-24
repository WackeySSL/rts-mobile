# ADR 0050: The art pipeline: one coherent look, richer SVG units, a building route chosen by comparison, fixed faction colours with a team marker, and a closer zoom

**In short, for Michael:**
- **Units:** they stay SVG from our own generator, now with much more detail: panels with seams,
  bevels, about 15 shades per material, soft contact shadows and a metal sheen made with
  gradients. Godot draws all of that correctly; we tested it.
- **One look for everything** (your rule): units, buildings, ground, effects, icons and item
  cards must look like one game, never random. Every way of making art has to pass the same
  test: units and buildings side by side on the same ground in the same light.
- **Large buildings:** still open. We compare the same Facet headquarters made three ways (our
  generator, Figma vector, Figma AI), and you pick one way for all of them. If Figma AI does not
  clearly win, everything stays in our generator and there is no PNG.
- **Colours:** Nordværn is always orange and Facet always blue. A small marker on each unit and
  building shows whose it is.
- **Zoom:** you get a fourth, closer level. At that level the sprites are a little soft, because
  baking them sharp would take more than twice today's graphics memory.

You answered questions 2 to 5. Question 1, the building route, waits for the comparison.

Status: **proposed, 2026-11-24; questions 2-5 answered, question 1 pending** (the building
route, decided after the comparison of row P637; row P621b then accepts this ADR). Written by
the architect (row P621) on branch
`claude/p600-treadline-plan`, after Michael's answer of 2026-11-24 to ADR 0049 and P601 ("A, SVG
til enheder men prøv om du ikke kan gøre dem mere realistiske. brug gerne figma som tegner og PNG
kun til de store bygninger, faste farver, Facet. og i spillet skal det være muligt at zoome
længere ind end det er idag"). Plan: `docs/plans/2026-11-24-treadline-restyle.md`, rows
P621 and P630-P649 (P622 and P623 are ADR 0051's rows). It is built on P601's prototype: branch `claude/p601-style-proto`,
`docs/proto/p601/README.md`. That prototype is the reference only and is never merged as it is.

## Michael's answers (2026-11-24)
Verbatim: "ja til alle 4, men vi skal have afgjort om det er figma Ai der vinder, vi skal have en
helhed i grafikken hele vejen rundt så det virker gennemarbejdet og ikke tilfældigt" (yes to
all four, but we must settle whether Figma AI wins; the graphics must be one whole all the way
round, so it looks worked through and not random).
- **2: 2.0.** Appended at the end; soft past 1.5 by choice (§6).
- **3: own white, the computer red,** each marker with a dark rim (§3).
- **4: yes,** gradient sheen from detail 2 (§1).
- **5: yes** to §4's `svg-art-style` text (P630b applies it).
- **1: open.** On P601 round 2 (`docs/proto/p601/README.md`, "Round 2") Michael preferred the
  artgen SVG Facet headquarters to the Figma-vector one. A Figma-AI variant is made and compared
  after ADR 0051 (#643) merges (row P637), and then he picks one building route (§2).
- **New principle: one coherent look** (§8), with the same-scene check as the test for every art
  route.

Amends, on acceptance (dated notes; no accepted text is rewritten):
- ADR 0023 §5 (the art pipeline: SVG only, the per-faction key triads).
- ADR 0035 §4 (the team pad and ring take the marker key).
- ADR 0027 §4 (the page rule holds, and PNG frames join the same page).
- The `svg-art-style` skill (§4, with Michael's yes to the text).
- `data/input_settings.tres`'s zoom list (§6).

No sim rule, Command or hash changes. Everything here is art, view and settings data.

## Context
- **P601's findings** (heavy tank and a Facet command hold, `docs/proto/p601/README.md`):
  - A second renderer over the same model faces gives four levels: L0 flat, L1 about 15 tones,
    L2 panels, seams, bolts and stripes, L3 bevels, contact bands, chips and grime.
  - Output is still only `svg`, `g` and `polygon`, and hash-seeded, so byte-stable.
  - The tank at L3 has 138 primitives against 36, and 6.8 times the polygons. Its 48 frames
    take 1.7 MB on disk against 287 KB. Its bake is about 3 times slower (164 ms against 57 ms,
    headless, noisy).
  - The canvases are the same, so atlas memory, sprite count and draw calls do not change.
  - A per-pixel PNG bake looks grittier but fixes the resolution and loses the recolourable key.
  - The large orange panels sit in the fossil key band. As team colour they break the 3-20 %
    team-share test and the own-or-enemy read.
  - The generator lacks chamfered boxes, rotated primitives, decals and a per-primitive detail
    override.
- **Gradients work.** Probed on Godot 4.7.2 (`Image.load_svg_from_string`, the bake's loader,
  2026-11-24, scratch project):
  - A `linearGradient` from #202020 to #E8681F across a polygon gives a smooth ramp: 23211f,
    53321f, 84441f, b6561f, e4661f at x 1, 25, 50, 75, 98.
  - A `radialGradient` gives e2e2e2 at the centre and 242424 at the rim.
  - Replacing a stop's hex string in the SVG text recolours the ramp (e4661f becomes 3e6ddc). So
    the bake's string swap still works inside gradients.
  - `svg-art-style` already allows gradients in hand-drawn files. A mask with a gradient and a
    `pattern` are the two known ThorVG gaps.
- **The atlas today** (`tests/view/test_iso_atlas_budget.gd`):
  - Page 1, the sorted world, is 2730 of 3584 rows. Page 2 (shadows, flyers) is 2510. Both pages
    are 4096 px wide.
  - RGBA8 means about 44.7 MB plus 41.1 MB, so about 86 MB of texture in a cross-faction match.
  - The sorted world must stay on one page: two interleaved textures break the batch at every
    switch.
- **Zoom today.** `data/input_settings.tres` has `zoom_levels = (0.75, 1, 1.5)` and
  `zoom_start_index = 1`. The art is drawn at 2x and baked at `bake_scale` 1.0, which gives 2
  texels per world px (`WorldSort.ART_SCALE` 0.5). A phone with a 1080 px short side has stretch
  1.5, and a 1440 px one has stretch 2.0. On screen, one texel covers `stretch × zoom / 2` device
  px: today's closest level (1.5) is 1.125 on a 1080p phone and 1.5 on a QHD phone.
- **Tutorial.** Basics' beat `zoom` is `ZOOM_LEVEL` with value 2 and an equality test
  (`ctx.zoom_level == value`). Its prompt says "one of three zoom levels". It is the only beat
  that reads the zoom. It assumes index 2 is the closest.
- **Large buildings** (3x3 footprint), six per faction, twelve in all: the Headquarters,
  refinery, vehicle factory, airfield, space centre and superweapon. 2x2 and 1x1 buildings stay
  SVG.

## Decision

### 1. Units: SVG from `tools/artgen`, made more realistic
- **The detail renderer moves into the real generator** (P631), written fresh with P601's
  `ArtDetail.gd` as the reference. It sits behind a per-model `detail` level, 0 to 3:
  - 0 is today's output, byte-identical, so every committed frame is untouched until its model
    opts in.
  - Units target L2, plus L3's bevels and contact bands. Chips and grime stay off on units: noise
    at far zoom.
  - Buildings drawn as SVG (2x2, 1x1) use L2, with no bolts on buildings (P601: 800 of the
    hall's 2,446 polygons).
  - Every jitter is seeded from the model id and the face index, so `--check` stays byte-stable.
- **Metal sheen** at detail 2 and up:
  - One `linearGradient` per lit metal face of at least 12 x 12 px, in the frame's `defs`.
  - Ids are `s0`, `s1` … in face order. Two stops from the material's own tone ladder, with fixed
    decimals.
  - Never on key colours (the marker is flat), never in a shadow frame, never in a mask.
- **Generator features first** (P630, with no change to any output): chamfered boxes, rotated
  primitives, face decals (numbers, hazard marks, vents), a per-primitive detail override, and
  macros for tracks, wheel sets, grilles, hatches and pylons. Models get shorter, not longer.
- **Budgets per frame** (pinned in `tests/art`):
  - At most 600 polygons for a unit hull at L2. P601's tank was 18,409 over 48 frames, about 380
    each.
  - At most 64 KB per generated frame. The 28 KB cap stays for hand-drawn files.
  - The page rule of ADR 0027 §4 is unchanged.
- **Directions stay 16 for vehicles.** Halving them to 8 is the named lever if the bake or the
  size runs over (§5).

### 2. Large buildings: one route, chosen by comparison (question 1, pending)
- **The rule.** All twelve 3x3 buildings use **one** route, so the set looks like one hand
  (§8). The candidates are:
  - artgen SVG at the new detail levels, with P630's chamfered and rotated primitives, so
    facets read as facets rather than a dome;
  - a Figma vector drawing;
  - a Figma-AI picture.
  The route is not chosen per building.
- **The comparison** (P637, after #643 merges): the same Facet headquarters is made in all three
  routes, taking round 2's artgen SVG and Figma-vector versions as they are. Each goes through
  §8's same-scene check beside the round-2 tank and the Nordværn headquarters, at all four zoom
  levels. Michael picks.
- **The default.** If Figma AI does not clearly win, every building stays artgen SVG at the new
  detail levels. The PNG path and its rows (P635, P636 and the Figma parts of P644 and P645) are
  dropped, and the 3x3 buildings join the SVG batches. Round 2 already favours artgen: Michael
  preferred its headquarters. If the Figma-vector route were picked, it would ship as PNG
  through the same path as below.
- **If a Figma route wins**, the rest of this section holds.
- **Made in Figma, in one of two ways.** Art-director works in AppCode ApS's own file
  "Treadline — building art", in the one route Michael picked. The CREDITS row says which.
  - **Drawn by us:** vector shapes with the Figma MCP (`use_figma`). This is our own work, all
    rights reserved (ADR 0046). The CREDITS row names the file and frame (CLAUDE.md Legal,
    Michael 2026-11-09).
  - **Made with Figma's own AI features** (ADR 0051, accepted 2026-11-24, Michael's "C"), then
    edited by hand on the footprint template. The CREDITS row is marked "AI-made with Figma AI,
    no copyright claimed by AppCode ApS" and gives the feature, the date, a short prompt and
    the hand edits. The file is outside ADR 0046's reserved scope. No prompt names another game,
    studio, faction, unit or brand, or asks for its style. Every picture passes ADR 0051 §3's
    resemblance screen before it is committed (no C&C or Red Alert silhouettes, insignia or
    interface look, no glowing crystal ore), and the screen is recorded in the row.
  - **Never** a plugin's AI tools, a community file, a shared library or a stock asset. Never
    the style file's existing pictures (ADR 0049 §1: their provenance is not recorded).
- **One building, one picture.** An AI-made body's `dmg2` picture and anim crops are made by
  editing that same picture, by hand or with Figma's AI edit, never by a fresh prompt. That keeps
  the parts matched. A picture that misses the 2:1 view, the north-west light or the footprint is
  redrawn, not shipped (ADR 0051 §2).
- **What suits Figma:** single views.
  - The twelve 3x3 buildings: body, `dmg2`, anim crops and their item cards.
  - Menu and loading backdrops and portraits (ADR 0051 §2). ADR 0049's menu rows may use them.
  - UI icons and the order glyphs, drawn as vectors and exported as SVG flattened to
    `svg-art-style`'s hand-drawn elements.
  **Units stay artgen** (ADR 0051 §2): they need 16 hull and 16 turret directions plus poses in
  one projection and one light. Unit cards stay rendered from their models, so a card always
  matches its sprite.
- **The model stays as the volume.** Each building's artgen model is kept. It makes the cast
  shadow frame, the footprint and the pick and bar lifts. So a Figma picture gets a correct
  shadow and stands where the SVG building stood.
- **Geometry match.** P636 exports a template from artgen per footprint: the 2:1 footprint
  diamond, the anchor, the height guide, the light arrow and the canvas size of today's sheet.
  The template is our own geometry. Drawings sit on it, so a PNG building stands where the SVG
  one stood, with the same pick and bar lifts.
- **Format:**
  - 8-bit sRGB RGBA PNG at the sheet's 2x canvas, with no metadata.
  - The cast shadow stays a generated SVG frame from the model's volume.
  - Damage keeps ADR 0034's rule: body and `dmg2`, no `dmg1`.
  - Anim parts are cropped Figma frames on the sheet's anim point.
  - Smoke and fire stay effects.
- **The bake** (P635) loads a PNG part, resizes it once to the bake scale (Lanczos) and blits it
  into **the same page** as the SVG frames. So the sorted world stays one texture and one batch.
  Same canvas means the same rows: the page budget does not move.
- **Size:** about 90 to 150 KB per picture (P601: 90 KB). With body, `dmg2`, anim crops and a
  card for twelve buildings, that is about 3 to 5 MB in the export. Bake time falls for them (a
  blit, not a raster).

### 3. Fixed faction colours and a team marker (replaces ADR 0049 question 5)
- **The faction colour is a fixed material**, never replaced:
  - Nordværn orange panels and hazard stripes.
  - Facet blue panels with navy trim.
  The two triads are art-director's in P632. P601's blue was `#68A8F2 #2F6FD0 #1B4A9C`.
  The HUD accents (`AccentFossil`, `AccentRenew`, ADR 0049 §5) take the same hues.
- **The team marker:**
  - Placement: a band, pennant or plate in the player's triad, on the hull top or turret and on a
    building's roof edge.
  - Share: 2 to 6 % of the visible surface in the default view.
  - Readability: a white inner line and a dark rim, so it reads on orange, blue and gunmetal
    (the selection ring's pattern, ADR 0035 §4).
  - It shows at every damage stage except KRITISK (the GDD's "little team colour left").
  - For PNG buildings it is a separate small SVG overlay part at the sheet's `marker` point,
    baked per player into the same page.
  - ADR 0035's pad and ring stay and take the marker's triad.
- **One key triad for both factions.**
  - The per-faction keys (#FF9446 #E8681F #B04B12 and #62D6EE #1FA6C8 #137C99) are retired.
    They are the same hexes as the wearable Signal and Arktisk triads and sit inside the new
    fixed orange.
  - In their place comes one sentinel triad, magenta near hue 300°, set by P632. It is never
    seen in the game, because the bake always replaces it.
  - The key band rule stays as it is, now against the sentinel: no other colour within 20° of
    hue at a saturation of 0.30 or more.
- **Migration** (P632, one row, mechanical):
  1. Every model's `team` material moves to the sentinel.
  2. Every committed frame is regenerated. Only the hex strings change: same shapes, same rows.
  3. The bake's key table goes from per-faction to one triad.
  4. The fixed faction materials are added to `ArtPalette`.
  5. The galleries' triads follow (`art_gallery_iso.gd`, `art_gallery_units.gd`).
  6. The tests change: `test_artgen_readability.gd`'s `TEAM_SHARE` becomes 2-12 % for the
     transition (today's 8-12 % bands are valid markers), and a `FACTION_SHARE` band applies to
     models at detail 1 and up.
  7. Each model batch then adds the panels, shrinks its marker to 2-6 % and is tested there. The
     last batch to merge narrows `TEAM_SHARE` to 2-6 %.
- **Default team colours** (question 3): own white (Sne), the computer red (Karmin). This is a
  route rule in the menus' match setup. The eight triads stay.

### 4. The `svg-art-style` changes (exact text, applied in P630b with Michael's yes)
- **Palette:** "Team zones are painted only in the faction's key triad …" becomes: "Each faction
  has a fixed colour material (Nordværn orange, Facet blue; STYLE.md owns the values) that the
  bake never changes. The team marker is painted only in the sentinel key triad (STYLE.md), which
  the bake replaces with each player's triad."
- **Team share:** "Team colour covers about 8-12 % …, never large team plates" becomes: "The team
  marker covers 2-6 % of the visible surface (a band, pennant or roof-edge plate with a white
  inner line and a dark rim). Fixed faction panels may cover large surfaces."
- **Shading:** "Faces are flat-shaded from the one light: top lightest, left side middle, right
  side darkest" gains: "From detail 1 a face's tone follows its normal on the material's ladder
  (about 15 tones). Detail 2 adds panel seams, bolts (units only) and stripes. Detail 3 adds
  bevel edges and contact bands. Units target detail 2, buildings detail 2 without bolts."
- **Technical:** "Generated frames use only polygons and `g` with group opacity …" becomes:
  "Generated frames use polygons, `g` with group opacity, and at detail 2 and up `linearGradient`
  in `defs` for metal sheen (ids `s0`, `s1` … in face order, two stops from the material's
  ladder, never a key colour, never in a shadow frame or a mask)." The 64 KB cap for generated
  frames is added beside the 28 KB hand-drawn cap.
- **New "PNG pictures" rule** (applied only if question 1 picks a Figma route; under the default
  there is no PNG rule and "units are never PNG" becomes "game art is never PNG"): "PNG only for the 3x3 buildings' body, `dmg2`, anim crops and
  cards, for backdrops and portraits, and for UI icons, made in Figma (buildings on the artgen
  footprint template). They are drawn by us from vector shapes, or made with Figma's own AI
  features under ADR 0051: the CREDITS marking, the resemblance screen, never a plugin's AI,
  community files or shared libraries. Exported as 8-bit sRGB RGBA at the sheet's 2x canvas with
  no metadata; a CREDITS row each, naming the Figma file and frame. Units are never PNG."

### 5. Cost against rule 6 and the web
| | Today | After (estimates; measured per batch) |
| --- | --- | --- |
| Draw calls, sprites per unit | 3 sprites, one atlas | Unchanged. The marker is part of the hull frame; on buildings it is one more sprite on the same page, so no extra call |
| Frame time at 150 units | — | Unchanged: same quads, same fill |
| Atlas memory (cross-faction) | About 86 MB over two pages | Unchanged: same canvases, plus a few rows for building markers |
| Unit SVG on disk | `assets/art/iso` 18 MB | About 4 times raw at L2 (P601's tank: 4.4 times; macros and no bolts on buildings bring it down). SVG compresses 8 to 10 times in the pck, so about +6 to 20 MB of export (P601's estimate for L3: 10 to 20) |
| PNG buildings (only if a Figma route wins) | 0 | About +3 to 5 MB; 0 under the default |
| Match-start bake | Today's `atlas_bake_ms` | About 2 to 3 times for units, less for the PNG buildings. Budget: at most twice today's on the reference phone (CI and P649 report it; no timing runs in a session). Over that: L1 for far parts, then 8 directions |

### 6. Deeper zoom: a fourth level at the end
- **`zoom_levels` becomes (0.75, 1, 1.5, 2.0)** (P634). The new level goes at the end, so indexes
  0-2 keep their meaning and `zoom_start_index` 1 is unchanged. The `InputSettings` default list
  matches. `data/input_settings.tres` is not excluded from `balance.yml`'s paths, so the row
  starts one balance run.
- **The tutorial.** Basics' `zoom` beat (`ZOOM_LEVEL` 2, equality) assumed 2 was the last level.
  A strong pinch would now settle on 3 and stall the beat. P633:
  - adds `TutorialConditions.Kind` 19 `ZOOM_AT_LEAST` (appended);
  - points the beat at it with value 2;
  - lets `TutorialLessonDef.problems()` take the pinch gesture with it;
  - teaches the hint's AUTO rule to pinch in below the value;
  - changes "one of three zoom levels" to four in the prompt, `camera-pinch` and its help text.
  It runs after P592 and P594 (guide v2), and P634 merges after it.
- **Sharpness at 2.0.** One texel covers 1.5 device px on a 1080p phone and 2.0 on a QHD phone.
  Today's closest level covers 1.125 and 1.5.

  | Option | Memory (cross-faction) | Other cost | Verdict |
  | --- | --- | --- | --- |
  | Bake for 2.0 (`bake_scale` 1.5 for 1080p) | About 193 MB (2.25 times; 2.0 for QHD: about 344 MB) | Page 1 needs about 6,140 rows, more than 4,096, so the sorted world splits across textures; the bake takes 2.25 times as long | Rejected: rule 6 and the mobile web's texture memory |
  | Bake per zoom tier (re-bake when entering 2.0) | +193 MB while near, or a swap | A hitch of seconds at each zoom-in with L2 art; two code paths | Rejected |
  | Accept softness past 1.5 | 0 | Sprites, the ground and the fog are slightly soft at 2.0 (bilinear) | **Chosen** (question 2) |
  | Raise `bake_scale` to the page fit (about 1.1) | +21 %, about +18 MB | Uses the 854 free rows that later types need | Lever only, not now |

  L2's seams and stripes are at least 2 px at 2x, so they survive 1.5x magnification. Zoomed
  in, fewer sprites are on screen, so the frame gets cheaper.

### 7. Tests (headless)
- **Generator** (P630, P631):
  - `--check` stays byte-identical for every model at detail 0.
  - Each level's output uses only the allowed elements (polygon, g, and `linearGradient` in
    defs from L2).
  - The gradient ids are in order, and no key colour is in a gradient.
  - Polygon and byte budgets per frame are checked.
- **Key migration** (P632):
  - The key band holds against the sentinel.
  - Every committed frame holds only sentinel key hexes.
  - The bake replaces them for each of the eight triads, inside gradients too.
  - The share bands are checked.
  - Page rows are unchanged within the existing 40-row tolerance.
- **PNG path** (P635, only if a Figma route wins):
  - A crafted PNG sheet bakes into page 1 at its region.
  - No second texture appears.
  - The marker overlay is baked per player.
  - The page budget is unchanged for an equal canvas.
- **Zoom** (P634, P633):
  - Snap to each of the four levels.
  - Pinch overshoot is bounded at the new last level.
  - The start index is unchanged.
  - A turn keeps the level.
  - The picker, the minimap and edge pan pass at every level.
  - The gallery zoom row's cross-file fact holds.
  - Basics ends when the player settles on 2 or 3.
- **Per batch:**
  - The 32 px greyscale readability check.
  - Silhouettes tell apart in a mirror match.
  - Marker and faction shares are in their bands.
  - The page budget holds.

### 8. One coherent look and the same-scene check (Michael, 2026-11-24)
- **The principle.** All graphics form one whole: units, buildings, terrain, effects, UI icons
  and item cards. Nothing may look random or as if from another game. One look beats the best
  single picture, so a route that makes a better building that does not match the units loses.
- **The same-scene check** is the acceptance test for every art route and every art batch. A
  headless composer in `tools/artgen` (row P629) builds one sheet per PR. It uses the same
  loader as the bake (`Image.load_svg_from_string`, PNG decode) and blends with `Image`, with no
  renderer, so it runs headless. Each sheet holds:
  - Nordværn and Facet units and buildings side by side on the same ground tiles (grass, dirt,
    sand, rock, an oil field);
  - the same north-west light and the world grade (ADR 0035);
  - the four zoom levels;
  - a mirror pair with both default markers;
  - the effects that touch them (smoke, fire, muzzle flash, dust);
  - their item cards and the HUD glyphs beside them.
  Michael judges the sheet by eye in the PR. The PR attaches it as a screenshot; it is not
  committed.
- **What is measured** (`tests/art/test_same_scene.gd`, bands in `tools/artgen/same_scene.tres`,
  outside `data/` so no balance run starts):
  - Light: top, left and right faces in that luminance order for every sprite, and the shadow
    direction is the same.
  - Tone: the faction materials' value and saturation within one band across units and
    buildings.
  - Edges: the same edge treatment, dark own-material edges and no black outline.
  - Detail density: edges per 100 px² at zoom 1.0 within one band, so no building is busier
    or flatter than the units.
  - Contact shadow style.
  - Readability: the 32 px greyscale check on the sheet itself.
  A route or a batch that fails a band does not merge until it is redone.

## Consequences
- Units get much closer to the reference's mood (P601: about 70 % of the way for the tank) with
  no new pipeline and no runtime cost. The finish of a lit render (specular, GI) stays out of
  reach.
- One look is the gate for every route (§8). A better single picture that does not match loses,
  and every art PR carries a same-scene sheet.
- Under the default (artgen wins), all game art has one source and one bake path, and there is
  no PNG path to build.
- If a Figma route wins, large buildings can go further (per-pixel shading), at the price of a
  fixed resolution and a second art source to keep consistent with the generated shadows.
  AI-made pictures would carry no copyright claim (ADR 0051 §5), so others could copy them.
- Factions read by colour at any distance, and players by a small marker. Mirror matches lean on
  the marker, the pad and the ring.
- Every committed frame changes bytes once (P632), mechanically.
- The closest zoom is a little soft, by choice.

## Alternatives considered
- **PNG for everything** (P601's per-pixel bake). Rejected by Michael's answer. It also has no
  recolourable key, and the resolution is fixed.
- **Team-coloured large panels** (P601 as built). Rejected: 60 % team colour breaks the read and
  the share rule ("faste farver").
- **Units drawn or AI-made in Figma.** Rejected (ADR 0051 §2): one picture gives no 16
  directions, moving turret or shadow in one projection. That is too many drawings to keep
  consistent.
- **A sharper bake for the new zoom.** Rejected (§6).

## Questions for Michael
1. **Open: the building route.** After P637's comparison of the same Facet headquarters in
   three routes (artgen SVG, Figma vector, Figma AI), all through §8's same-scene check, pick one
   route for all twelve 3x3 buildings. Recommended: artgen SVG unless Figma AI clearly wins on
   both the picture and the fit with the units. That is also the default. The 2x2 and 1x1
   buildings stay artgen SVG in every case.
2. **The new zoom level.** Answered 2026-11-24: **2.0**, appended, soft past 1.5.
3. **Default marker colours.** Answered 2026-11-24: **own white, the computer red**, each with a
   dark rim.
4. **Metal sheen with gradients on units.** Answered 2026-11-24: **yes**, from detail 2.
5. **The `svg-art-style` text of §4.** Answered 2026-11-24: **yes** (P630b).
