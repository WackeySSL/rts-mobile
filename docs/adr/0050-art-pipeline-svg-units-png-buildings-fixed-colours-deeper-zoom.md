# ADR 0050: The art pipeline: one coherent look, generator SVG for everything on the map, Figma AI for stand-alone art, fixed faction colours with a team marker, and a closer zoom

**In short, for Michael:**
- **Units:** they stay SVG from our own generator, now with much more detail: panels with seams,
  bevels, about 15 shades per material, soft contact shadows and a metal sheen made with
  gradients. Godot draws all of that correctly; we tested it.
- **One look for everything** (your rule): units, buildings, ground, effects, icons and item
  cards must look like one game, never random. Every way of making art has to pass the same
  test: units and buildings side by side on the same ground in the same light.
- **Buildings:** every unit and every building on the map comes from our generator as SVG. The
  generator learns bevelled boxes and turned prisms, so buildings get the low, faceted shape of
  the Figma drawing instead of domes. There is no PNG on the map.
- **Figma AI** makes only pictures that stand alone: the menu and loading backdrops, portraits
  and store art. It is never on the map next to units.
- **Colours:** Nordværn is always orange and Facet always blue. A small marker on each unit and
  building shows whose it is.
- **Zoom:** you get a fourth, closer level. At that level the sprites are a little soft, because
  baking them sharp would take more than twice today's graphics memory.

You answered all five questions.

Status: **accepted, 2026-11-24** (Michael: questions 2-5 "ja til alle 4", question 1 "ja, kør med
generator-SVG og Figma AI til menuer"; accepted in row P621b on branch
`claude/p621b-adr0050-accept`, base `main` at 653383c5). Proposed 2026-11-24 by the architect in
row P621 (PR #642), after Michael's answer to ADR 0049 and P601 ("A, SVG til enheder men prøv om
du ikke kan gøre dem mere realistiske. brug gerne figma som tegner og PNG kun til de store
bygninger, faste farver, Facet. og i spillet skal det være muligt at zoome længere ind end det er
idag"). Plan: `docs/plans/2026-11-24-treadline-restyle.md`. Built on P601's prototype: branch
`claude/p601-style-proto` (head 6be63003), `docs/proto/p601/README.md`, rounds 1-3. The prototype is
the reference only and is never merged as it is.

## Michael's answers (2026-11-24)
Verbatim: "ja til alle 4, men vi skal have afgjort om det er figma Ai der vinder, vi skal have en
helhed i grafikken hele vejen rundt så det virker gennemarbejdet og ikke tilfældigt" (yes to
all four, but we must settle whether Figma AI wins; the graphics must be one whole all the way
round, so it looks worked through and not random).
- **2: 2.0.** Appended at the end; soft past 1.5 by choice (§6).
- **3: own white, the computer red,** each marker with a dark rim (§3).
- **4: yes,** gradient sheen from detail 2 (§1).
- **5: yes** to §4's `svg-art-style` text (P630b applies it).
- **1: "ja, kør med generator-SVG og Figma AI til menuer"** (yes, go with generator SVG, and Figma
  AI for the menus), after P637's same-scene comparison (`docs/proto/p601/README.md`, "Round 3
  (P637)"):
  - (a) artgen SVG was the most coherent whole;
  - (b) the Figma vector had the best silhouette;
  - (c) Figma AI looked best alone but broke the scene: no outline, a painterly light of its own,
    a glossier cobalt and detail at another scale.
  So everything on the map is generator SVG, with (b)'s faceted form (§2).
- **New principle: one coherent look** (§8), with the same-scene check as the test for every art
  route.

Amends (P621b writes the dated notes; no accepted text is rewritten):
- ADR 0023 §5 (the art pipeline: SVG only, the per-faction key triads).
- ADR 0035 §4 (the team pad and ring take the marker key).
- ADR 0027 §4 (the page rule holds, and building frames get a budget, §1).
- ADR 0051 §2 (its "large building pictures" item: on the map they are generator SVG; Figma AI
  is for stand-alone art).
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
  - Every building (3x3 included) uses L2 and L3's bevels, with the building budget below.
  - Every jitter is seeded from the model id and the face index, so `--check` stays byte-stable.
- **Metal sheen** at detail 2 and up:
  - One `linearGradient` per lit metal face of at least 12 x 12 px, in the frame's `defs`.
  - Ids are `s0`, `s1` … in face order. Two stops from the material's own tone ladder, with fixed
    decimals.
  - Never on key colours (the marker is flat), never in a shadow frame, never in a mask.
- **Generator features first, with no change to any output:**
  - P630: face decals (numbers, hazard marks, vents), a per-primitive detail override, and
    macros for tracks, wheel sets, grilles, hatches and pylons. Models get shorter, not longer.
  - P630c: a chamfered (bevelled) box and rotated prisms (n-gon prisms and frustums turned about
    the vertical axis, with sloped faces). Their target is the facet form (§2).
- **Budgets per frame** (pinned in `tests/art`):
  - At most 600 polygons for a unit hull at L2. P601's tank was 18,409 over 48 frames, about 380
    each.
  - At most 64 KB per generated unit frame. The 28 KB cap stays for hand-drawn files.
  - **Buildings**, per frame (body, `dmg2`; anim crops are capped at a quarter of the body):

    | Footprint | Polygons | Bytes |
    | --- | --- | --- |
    | 3x3 | 1,500 | 128 KB |
    | 2x2 | 900 | 80 KB |
    | 1x1 | 500 | 48 KB |

    P601's Nordværn works hull frame is 404 KB (round 3) and the round-1 Facet hall 210 KB
    (2,446 polygons, 800 of them bolts). Both must come down about 2 to 3 times.
  - **Building detail rules:**
    - No bolts on faces larger than 0.25 tile² (big walls, roofs and aprons). Bolts only on
      hatches, pylons, trim and small parts.
    - Panel cells at least 0.3 tile across, the tanks' panel size (round 3's density match).
    - Hazard stripes at least 6 px wide at 2x.
  - The page rule of ADR 0027 §4 is unchanged.
- **Directions stay 16 for vehicles.** Halving them to 8 is the named lever if the bake or the
  size runs over (§5).
- 2026-11-25: faces with equal sheen stops share one linearGradient (P631).

### 2. Buildings: generator SVG with a faceted form; Figma AI for stand-alone art (answer 1)
- **Everything on the map is generator SVG:** every unit and every building (3x3, 2x2, 1x1), at
  the new detail levels, with the team marker in the frames (§3). **There is no PNG on the map.**
  The PNG bake path and the Figma building rows of the proposal are dropped (plan: P635 and P636
  struck; P644 and P645 are SVG batches).
- **The facet form.** Buildings take (b)'s silhouette: low, faceted, closed armour, crisp facets,
  never the dome that artgen's axis-aligned boxes and n-gon frustums give today (a). The target
  references are in `docs/proto/p601/` on `claude/p601-style-proto`:
  - form: `round2/figma_facet_hq_1_0.png` and `scene/scene_b_figma_vector_1_0.png` (and `_2_0`);
  - the dome to replace: `scene/scene_a_svg_1_0.png`;
  - the scene it must sit in: the round-3 tanks and the Nordværn works.
  P630c adds the primitives. The Facet 3x3 batch (P645) rebuilds the Facet headquarters to
  that form and passes §8's check beside the round-3 scene. The Figma vector stays a reference
  only; nothing from it is imported.
- **Figma AI is for stand-alone art only** (ADR 0051):
  - the main-menu and loading backdrops;
  - portraits;
  - store art.
  It is never on the map and never next to units. Each picture gets ADR 0051 §4's CREDITS row
  ("AI-made with Figma AI, no copyright claimed by AppCode ApS": file and frame, feature, date,
  short prompt, hand edits, the screen). Each one also has to sit right with the restyled UI
  tokens (ADR 0049 §5), so a stand-alone picture still belongs to the one look (§8). P601's
  round-3 AI headquarters (`scene/figma_ai_raw_1280x960.png`) is not shipped.
- **Item cards stay rendered from their models**, so a card always matches the sprite it builds.
  Portraits are used where no card is: first on the main menu's and map select's side cards (one
  hero portrait per faction). Per-type portraits for production and unit details come with those
  screens' own rows (unit details is out of scope, ADR 0049).

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
  - On buildings it is a roof-edge plate in the frame itself, like the units' (no overlay sprite).
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
     models at detail 1 and up. P640 measures it with the same-scene hue band (within
     `faction_hue_band` of the faction's mid hue at `faction_sat_min` or more, from
     `same_scene.tres`) instead of the exact tones, which miss the small faces of infantry; the
     band stays 15-85 %.
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
- **New "Stand-alone pictures" rule** (the decided form of the proposal's conditional PNG rule;
  P630b asks Michael's yes to this bullet, since he saw the conditional one): "Game art on the
  map is never PNG: units, buildings, terrain and effects come from `tools/artgen` or hand-drawn
  SVG. PNG is only for stand-alone pictures: the menu and loading backdrops, portraits and store
  art. They may be made with Figma's own AI features under ADR 0051 (the CREDITS marking, the
  resemblance screen; never a plugin's AI, community files or shared libraries), and must sit
  right with the UI tokens."

### 5. Cost against rule 6 and the web
| | Today | After (estimates; measured per batch) |
| --- | --- | --- |
| Draw calls, sprites per unit | 3 sprites, one atlas | Unchanged. The marker is part of the frame, on units and buildings |
| Frame time at 150 units | — | Unchanged: same quads, same fill |
| Atlas memory (cross-faction) | About 86 MB over two pages | Unchanged: same canvases |
| Unit SVG on disk | `assets/art/iso` 18 MB | About 4 times raw at L2 (P601's tank: 4.4 times; macros and no bolts on buildings bring it down). SVG compresses 8 to 10 times in the pck, so about +6 to 20 MB of export (P601's estimate for L3: 10 to 20) |
| Buildings' SVG | in the 18 MB | At most 128 KB per 3x3 frame (§1); about 24 buildings with body and `dmg2` stay under about 5 MB raw |
| Stand-alone pictures (menus) | 0 | A few PNG backdrops and portraits; the web size is reported per PR. They load only in menus, never in the match atlas |
| Match-start bake | Today's `atlas_bake_ms` | About 2 to 3 times for units and buildings. Budget: at most twice today's on the reference phone (CI and P649 report it; no timing runs in a session). Over that: L1 for far parts, then 8 directions |

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
- **Building budgets:** the table of §1 per footprint; no bolt on a face over 0.25 tile².
- **Facet primitives** (P630c): a chamfered box and a rotated prism give the expected face count
  and normals. `--check` is byte-identical for every existing model.
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
- All game art on the map has one source and one bake path. There is no PNG path to build, and
  damage stages, the team marker and every zoom stay code.
- Buildings get the Figma vector's form through two new primitives, not through a second art
  source.
- Figma AI pictures (menus, portraits, store) carry no copyright claim (ADR 0051 §5), so others
  may copy them. They are outside the match.
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
- **Figma vector or Figma AI buildings on the map** (P637 routes b and c). Rejected by answer 1:
  (b) needs a second source and PNG per zoom; (c) breaks the scene's edges, light, tone and
  detail scale.

## Questions for Michael (answered 2026-11-24)
1. **The building route.** Answered 2026-11-24, after P637: **generator SVG** for every building,
   with Figma AI for the menus ("ja, kør med generator-SVG og Figma AI til menuer").
2. **The new zoom level.** Answered 2026-11-24: **2.0**, appended, soft past 1.5.
3. **Default marker colours.** Answered 2026-11-24: **own white, the computer red**, each with a
   dark rim.
4. **Metal sheen with gradients on units.** Answered 2026-11-24: **yes**, from detail 2.
5. **The `svg-art-style` text of §4.** Answered 2026-11-24: **yes** (P630b).
