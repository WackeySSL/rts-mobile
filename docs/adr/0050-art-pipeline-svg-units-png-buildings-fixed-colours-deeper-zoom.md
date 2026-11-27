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

Status note (2026-11-26, P621c, architect): Michael reversed §3's fixed faction colours on
2026-11-26 ("A: Holdfarve på pladerne"): the large panels wear the player's team colour, the
bodies stay neutral and the sides are told apart by shape. The section "Amendment (2026-11-26,
P621c)" at the end of this ADR records the decision, the measured share bands and what it replaces
in §3, §7 and the Consequences. The default team colours there are the lead's proposal, which
Michael can override. No accepted text changed.

Status note (2026-11-27, P654, architect; ADR 0053 **proposed**): Michael chose "3D til terræn +
bygninger, SVG-enheder" on 2026-11-27, after the probes P653 and P655. ADR 0053
(`docs/adr/0053-prerendered-terrain-and-buildings.md`) proposes to reverse answer 1's "There is
no PNG on the map" (§2, §4's "Stand-alone pictures" bullet) for terrain and buildings: they would
be pre-rendered from our own 3D models at today's density, with the team colour recoloured at match
start. Units stay generator SVG under this ADR as amended. §8, the amendment's A1-A7, §1's byte
budget for buildings and §6 still bind the pre-rendered art. Until ADR 0053 is accepted, this ADR
stands as written. No accepted text changed.

Status note (2026-11-27, P654, acceptance): ADR 0053 is **accepted** (Michael, verbatim:
"Godkend alle 7 (anbefalet)"). From now on terrain and buildings are pre-rendered PNG from our own 3D model
data, and §2's first bullet and §4's "Stand-alone pictures" bullet no longer bind those two
classes. Units stay generator SVG under this ADR as amended. No accepted text changed.

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
- 2026-11-27 (P654): ADR 0053 (proposed) would make terrain and buildings pre-rendered PNG from
  our own 3D models, in place of this section's first bullet for those two classes. Units stay
  generator SVG. See the status note at the top.
- 2026-11-27 (P654): ADR 0053 is accepted; the line above holds.

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

## Amendment (2026-11-26, P621c): team colour on the large panels
**In short, for Michael:** the big orange and blue panels now wear each player's team colour.
The bodies stay steel and iron (Nordværn) or white and graphite (Facet), and the lamps stay as
they are. You tell the two sides apart by their shapes. By default each side still wears its own
colour, orange or blue, and in a mirror match the other player wears the other one. That last
point is the lead's proposal, and you can change it.

**Michael's decision** (2026-11-26, his answer to the lead's AskUserQuestion), verbatim: "A:
Holdfarve på pladerne" (A: team colour on the panels).

**Why.** With §3's fixed faction colours, both armies of a mirror match are the same orange (or
the same blue). The team marker was the only thing that told them apart, and at 32 px it covers
only about 1.5 to 8 % of a unit.

**Form.** This is an amendment section in ADR 0050, not a new ADR. That follows the repo's
precedent for a dated change to one part of an accepted ADR ("Amendment (2026-10-11, P8 review)"
and "(2026-10-11, P21)" in ADR 0004, "Amendment (2026-10-12, P34b review)" in ADR 0012). The change
is confined to §3, and to the lines of §7 and the Consequences that repeat §3. Keeping it beside
the text it replaces leaves one place for the art pipeline. The accepted text above stays as it
was written, and the status note at the top points here. A11 lists every accepted line this
section replaces.

Built on `main` at 99d0a5b5. The 14 detail-2 models on `main` (P638-P641) were measured with
throwaway scripts in a copy of the tree, which ran the suites' own measures on frames regenerated
with P652's swap. No code was committed. The 4 models of P642 (PR #681, not yet on `main`) use the
numbers that row measured.

### A1. The look
- **Team panels.** Every large panel that is now the fixed faction colour wears the player's
  team colour: Nordværn's orange panels, cab and turret flanks, hoods, hard hats, shoulder plates
  and pack panels, and Facet's blue ones.
- **Neutral bodies.** Nordværn is steel and iron (and concrete on buildings), Facet is white
  (ceramic) and graphite. Rust and olive stay retired where P638-P642 retired them.
- **Accents unchanged.** Nordværn's warm lamp and Facet's mint lamp, the visors, the decals
  (number, hazard, vent) and the hazard stripes keep their colours.
- **Shape language tells the sides apart.** Nordværn is heavy steel, tall boxy hulls and wide
  tracks. Facet is low faceted wedges, closed armour and hexagons (ADR 0049 §7). A4 adds the
  check for it.
- **Item cards** belong to no player, so they still draw the key in the faction's colour
  (`ArtIcon`, STYLE.md "The sentinel key triad"). A card therefore shows the panels in Nordværn
  orange or Facet blue, as it does today. The HUD accents `AccentFossil` and `AccentRenew` keep
  those hues.

### A2. The sentinel key covers the panels
- In every model at detail 2 or more, the fixed faction material (`faction`) becomes the sentinel
  key material (`team`). The bake replaces the sentinel with the player's triad, so the team
  colour covers the large panels.
- The swap changes only the material word of those primitive lines: no geometry, no primitive
  added or removed, no detail level, decal or pose. P652 does it on all 18 detail-2 models.
- The small rimmed plates of P638's rule (a `team` plate on a lamp or ceramic line, on an iron or
  graphite rim), and the aircraft's stripes and bands, may stay. They become part of the team
  area.
- **No fixed faction paint on the map.** After P652 no model paints `faction` (a test over every
  model). A fixed orange or blue part left on a body would read as a team colour in a mirror
  match, which is the very confusion this amendment fixes. `ArtPalette` keeps the material for
  the cards and as the classifier's reference hue.
- Measured on the 14 models in the copy (P642's four follow when they merge):
  - **The frames change in hex strings only.** 574 frames changed. `scripts/art-hex-only.sh`'s
    normalisation finds no other change, and the bytes are the same (7,836,215 before and after).
    Team faces get the same extras as faction faces (seams, tints, bolts, all black or white at
    some opacity), and neither material has metal sheen, so no key colour enters a gradient.
  - **The item cards come out byte-identical.**
  - **The page cost.** Five parts gain a key colour: the Bullhead's hull and the turrets of the
    Mortar Rig, `renew_scout`, `renew_tank` and `renew_artillery`. A frame that a key colour
    touches is baked per player (`IsoAtlas`), so a mirror match bakes those frames twice.
    `IsoAtlas.planned_page` gives:

    | Page | Today (the pins) | After the swap | Left of 3584 |
    | --- | --- | --- | --- |
    | Cross-faction, page 1 | 2748 | 2748 | 836 |
    | Nordværn mirror, page 1 | 2615 | 2697 (+82) | 887 |
    | Facet mirror, page 1 | 2536 | 2596 (+60) | 988 |
    | Page 2 (cross, mirrors) | 2594, 1458, 1480 | unchanged | |

    Draw calls and sprites per unit do not change. The rows come out of the free rows of §5 and
    ADR 0027 §4.

### A3. TEAM_SHARE at detail 2 and up (replaces §3's 2-6 % marker share for those models)
- **Measure.** On the raw frames (sentinel, not recoloured), in the default view of
  `test_artgen_readability.gd` (d06 for Nordværn, d10 for Facet, a building's one view, alpha of
  0.95 or more), the share of opaque pixels **in the key band**: a hue within
  `ArtPalette.BAND_DEGREES` (20°) of the sentinel's 300° at a saturation of
  `ArtPalette.BAND_SATURATION` (0.30) or more.
- **Why the key band.** The key-band rule guarantees that nothing else in a frame sits in that
  band, so the count is exact in what it counts. The exact-tone measure of today's `_share`
  (`KEY_TOLERANCE` 0.06) misses the panel seams, the cell tints and the edges of small faces. On
  the swapped frames it reads 14.0 to 40.8 % where the panels cover 42.3 to 62.7 %. P640 moved
  FACTION_SHARE to a hue band for the same reason.
- **The band:**
  - **30 to 65 % of the default view** for every model at detail 2 or more, units and buildings.
  - **25 to 75 % in every direction**, for the suites that band every direction (medic, carrier,
    minelayer, aircraft).
- **The method of the numbers.** Today's two shares, each as its suite measures it, were set
  against the key-band share of the same view after the swap:
  - "Faction, hue band": today's FACTION_SHARE measure (P640).
  - "Marker, exact": today's TEAM_SHARE measure.
  - After the swap, the share is about the faction share plus the marker share, when the marker
    too is counted by band. Counted by band, today's marker is 3.6 to 6.0 % on the vehicles and
    14.3 to 20.7 % on the squads, whose small faces the exact measure misses.
- **Measured** (default view, %):

  | Id (row) | Faction, hue band | Marker, exact | Sum | After the swap, key band | Every direction | Mirror differs |
  | --- | --- | --- | --- | --- | --- | --- |
  | `light_tank` Flarejack (P638) | 49.3 | 3.8 | 53.1 | 54.2 | 47.3-58.3 | 67.5 |
  | `heavy_tank` Bullhead | 38.5 | 3.2 | 41.6 | 42.3 | 33.6-52.4 | 51.0 |
  | `artillery` Mortar Rig | 57.1 | 3.5 | 60.6 | 62.5 | 55.8-68.0 | 72.6 |
  | `harvester` Tanker | 52.1 | 3.4 | 55.5 | 56.3 | 50.4-59.9 | 68.5 |
  | `renew_scout` (P639) | 47.9 | 2.9 | 50.8 | 52.1 | 41.9-55.8 | 62.2 |
  | `renew_tank` | 47.2 | 2.1 | 49.4 | 52.0 | 47.9-62.6 | 62.3 |
  | `renew_artillery` | 58.0 | 2.5 | 60.5 | 62.7 | 58.2-71.3 | 73.4 |
  | `renew_tanker` | 43.2 | 2.5 | 45.6 | 46.3 | 37.5-47.8 | 59.0 |
  | `rifle_squad` Rig Hands (P640) | 33.2 | 4.5 | 37.7 | 48.1 | 42.2-61.7 | 65.0 |
  | `rocket_squad` Wildcatters | 30.6 | 8.1 | 38.7 | 49.1 | 49.1-66.5 | 56.9 |
  | `fossil_patchers` Patchers | 32.8 | 6.6 | 39.4 | 51.6 | 47.5-60.4 | 67.2 |
  | `renew_rifle` Linemen (P641) | 34.8 | 4.7 | 39.5 | 55.0 | 48.9-67.9 | 69.9 |
  | `renew_rocket` Breakers | 30.3 | 5.9 | 36.2 | 51.5 | 45.0-70.8 | 69.6 |
  | `renew_menders` Menders | 36.6 | 8.1 | 44.7 | 60.0 | 31.3-60.0 | 72.9 |
  | `fossil_bunk_wagon` Bunk Wagon (P642, #681) | 56.0 | 3.0 | 59.0 | about 60 (estimate) | P652 | P652 |
  | `fossil_shot_truck` Shot Truck | 49.8 | 3.9 | 53.7 | about 56 (estimate) | P652 | P652 |
  | `fossil_fighter` Torchjet | 45.3 | 4.6 | 49.9 | about 52 (estimate) | P652 | P652 |
  | `fossil_bomber` Drillhead | 39.4 | 3.1 | 42.5 | about 44 (estimate) | P652 | P652 |

  - **The range.** After the swap the 14 measured models read 42.3 to 62.7 % in the default view
    and 31.3 to 71.3 % in every direction. The four P642 estimates are the sum plus half the
    exact marker share again, which is the vehicles' band-to-exact ratio of about 1.5. P652
    measures them.
  - **"Mirror differs"** is `test_same_scene.gd`'s mirror measure: the share of body pixels that
    change when the same sprite wears the other route triad.
- **Why 30 and 65.**
  - The floor is five times the old marker's 6 % ceiling, so the owner reads at the far zoom.
    It leaves room below today's lowest unit (the Bullhead, 42.3 %) for the building batches,
    whose large neutral walls and roofs P644-P647 draw to this band.
  - The ceiling is near the frozen same-scene cap. Wearing Signal, the Mortar Rig at 62.5 % reads
    `tone_sat_all` 0.536 against `tone_sat_all_max` 0.55 (A9), so a model much above 65 %
    would fail the sheet anyway. The unit test now catches that before the sheet does.
  - 60 % would fail two models of today (62.5 and 62.7).
- **Models below detail 2** keep today's exact-tone measure and its 2-12 % band until their batch.
  Every art id is in one of the batches P638-P647 (`docs/art/treadline-batches.json`), so after
  P647 no model is left in that band. Its planned narrowing to 2-6 % (§3 Migration step 7, P647)
  is struck, because no model will carry a small marker alone.
- **The roof-plate rule** (`test_artgen_plates.gd`) applies to models below detail 2. At detail 2
  and up, the team area is large panels by design and TEAM_SHARE bounds it. On the swapped
  frames the rule would flag 57 team primitives in 12 of the 14 models (from 0 on the Tanker and
  `renew_tanker` to 9 on each rifle and rocket squad). So the rule is scoped; no geometry is
  changed to satisfy it. The rimmed-marker exception stays valid.
- **The mirror row** of `test_same_scene.gd` ("differs only in the marker", 2 to 30 %) becomes
  "differs only in the team panels", 30 to 80 %. Measured: 51.0 to 73.4 % over the 14, and 51.0
  (`heavy_tank`) and 62.3 (`renew_tank`) on the sheet's own pair.

### A4. FACTION_SHARE is retired and replaced by a shape check
- **Retired.** FACTION_SHARE (15-85 % of the fixed faction colour at detail 1 and up) measured a
  material that no model paints any more (A2). It is deleted, not re-banded.
- **Replaced by two checks:**
  1. **No fixed faction paint:** no model's primitive uses `faction` (A2).
  2. **The faction reads from shape at 32 px.** For each Nordværn and Facet model of one role,
     both at detail 2 or more, the silhouettes overlap less than 0.85. That is the repo's
     `MAX_OVERLAP`, measured with `building_picture_support.gd`'s `mask_32` and `overlap`
     (intersection over union of the 32 px masks). Each pair is compared in d06 and in d10, the
     same direction for both models.
     - The pairs come from the batch lists: the same position in P638 and P639, P640 and P641,
       P642 and P643, P644 and P645, P646 and P647.
     - A mask has no colour, so the check holds whichever triad either side wears. That matters
       in a mirror match, where one Nordværn player is blue.
- **Measured** on today's frames (silhouettes do not change with the swap):

  | Pair | d06 | d10 | Each side's own default view (d06 against d10) | Highest in any one direction |
  | --- | --- | --- | --- | --- |
  | `light_tank` / `renew_scout` | 0.38 | 0.50 | 0.36 | 0.86 (d15) |
  | `heavy_tank` / `renew_tank` | 0.75 | 0.75 | 0.65 | 0.88 (d08) |
  | `artillery` / `renew_artillery` | 0.68 | 0.67 | 0.49 | 0.81 (d08) |
  | `harvester` / `renew_tanker` | 0.82 | 0.83 | 0.39 | 0.87 (d08) |
  | `rifle_squad` / `renew_rifle` | 0.75 | 0.78 | 0.48 | 0.84 (d08) |
  | `rocket_squad` / `renew_rocket` | 0.63 | 0.55 | 0.72 | 0.63 (d06) |
  | `fossil_patchers` / `renew_menders` | 0.34 | 0.31 | 0.61 | 0.55 (d04) |

  - All seven pairs pass in d06 and d10. The tightest is the Tanker against `renew_tanker` at
    0.83 (a risk; the swap cannot move it).
  - In a few single directions the two sides come close: d08 for three pairs and d15 for the
    scout pair, at 0.86 to 0.88. Those directions are not banded; there the team pad, the ring
    and the side's default colour carry the read. Banding every direction would need geometry
    changes to models that are already merged, which is outside P652.
  - The support and air pairs are tested from P643 on. At detail 0 they read 0.59 to 0.76 in
    d06 and d10.
- **The greyscale readability check stays** on every model, on the raw frames
  (`test_artgen_readability.gd`, spread of 80 or more at 32 px). After the swap the 14 models read
  129 to 212 raw. Recoloured, the lowest is 99 (the Tanker in Kul). That covers Signal, Kobolt,
  Sne and Kul, which bracket the eight triads in value.

### A5. ADR 0035's team pad and ring stay unchanged
The pad under a unit's hull and the selection ring keep ADR 0035 §4. They take the same sentinel
triad as the panels, so they wear the player's team colour, and the ring stays baked once for the
local player. The pad is a mark on the ground, not a plate on the model (ADR 0035 §4.1), so it is
outside TEAM_SHARE. Page 2's pins do not move (A2).

### A6. Default team colours (the lead's proposal; Michael can override it)
**This point is the lead's proposal, not Michael's answer.** It replaces §3's answer 3 ("own
white (Sne), the computer red (Karmin)"). Michael can override it; Sne and Karmin would then come
back as their own row, with a sheet and the classifier change described below.
- **The proposal.** The defaults stay today's interim (P632), now as the rule. Each side wears
  its own colour: Nordværn Signal (`WorldSort.TRIADS` 0), Facet Kobolt (3). In a mirror match the
  second player wears the other one. The Skirmish scenarios' `team_triads` keep those values, so
  no data changes and no balance run starts.
- **P647's switch to Sne and Karmin is struck.** White or red panels over 30-65 % of a unit
  would be a different look from the orange and blue that every sheet since P638 has shown:
  - Sne's mid #DCE2E6 sits on Facet's ceramic #D5DBDC (a summed channel gap of 0.09), so a Facet
    unit in Sne loses its panels into its body.
  - Karmin (hue about 5°) is outside both of the classifier's faction hues (21.2° and 208.9°,
    ±15°) and outside `SameScene.ROUTE_TRIAD`. The frozen `tone_sat` (A9) would count red
    panels as neutral body: about 0.4 against its 0.30 cap.
  - Taking Sne and Karmin back would need a new same-scene sheet for Michael, Karmin and Sne in
    the classifier's marker list (`SameScene.gd`, code, not the frozen `.tres`), and a contrast
    rule for white panels on Facet.
- The eight wearable triads stay as they are (STYLE.md "Triads").

### A7. Damage stages: what KRITISK does to the team panels
§3 said the marker shows "at every damage stage except KRITISK". With the marker now the large
panels, hiding it all at KRITISK would leave a wreck with no owner, so that clause is withdrawn.
- **Units** (vehicles, squads, aircraft) have no KRITISK frame. Their stages are the neutral
  overlays of ADR 0028 §4 (scars and the loose part, each slot at most 64 x 48 px at 2x, outside
  every key band). The hull frames do not change with the stage, so the team panels stay at
  every stage under the overlays. No change is needed.
- **Buildings** (P644-P647) keep ADR 0029 §5's rule for the team area at KRITISK: 20 to 50 % of
  the intact picture's key-band pixels stay in the band (the `char` and `hide` moves take the
  rest out of it, and a charred team face must leave the band wholly). The transition band of
  15-55 % (P632) is restored to 20-50 % in P647, as planned.
  - Together with TEAM_SHARE's 30 % floor, this leaves at least 6 % of the intact picture's area
    in team colour on a KRITISK building. That is the old marker's ceiling, so a wreck reads its
    owner as well as an intact building with a marker did. No new test is needed: the two
    existing bands imply it.
  - The GDD's "little team colour left" still holds: at most half the team paint survives.
- **Why this option.** Hiding all team colour at KRITISK (§3 as written) loses the owner of a
  building that is still a target. Keeping all of it loses the damage read that ADR 0029 built
  the stages on. ADR 0029's band does both, it is already tested per building, and it works on
  any team area.

### A8. same_scene.tres stays frozen
`tools/artgen/same_scene.tres` does not change: its bands, its hues and its comments. The neutral
body must still meet `tone_sat` 0.06 to 0.30, and the whole sprite `tone_sat_all_max` 0.55.

### A9. How the same-scene check treats the team key today (read from the code)
- `SameScene.sprite` renders every sprite through `IsoPlayerArt.recolour`, the bake's swap. The
  audit and the sheet's main rows wear the side's route triad (`ROUTE_TRIAD`: Signal for
  Nordværn, Kobolt for Facet). The mirror row wears the other one (`mirror_of`).
- `SameScene.measure` takes `tone_sat` over the pixels that `SameScene.is_faction` calls neutral.
  A pixel is not neutral when either:
  - its hue is within `faction_hue_band` (15°) of a `faction_hues` entry (21.2° or 208.9°) at a
    saturation of `faction_sat_min` (0.35) or more; or
  - it is within `key_tolerance` (0.06, the summed channel gap) of a tone of the sentinel triad
    or of either route triad.
- So the team key is **excluded** from `tone_sat`: a team pixel shows as Signal or Kobolt, which
  both tests take out (Signal's hues are 21.6° to 25.3° and Kobolt's 220.8° to 223.9°, all inside
  the bands). It is **included** in `tone_sat_all`, which averages every opaque pixel (alpha of
  0.9 or more).
- Measured with `is_faction` on the default views (same thresholds):

  | | `tone_sat` (0.06-0.30) | `tone_sat_all` (cap 0.55) |
  | --- | --- | --- |
  | Today, own route triad | 0.076-0.165 | 0.340-0.507 |
  | After the swap, own route triad (the audit) | 0.074-0.166 | 0.339-0.536 |
  | After the swap, the mirror triad (the mirror row) | 0.094-0.151 | 0.283-0.562 |

  - Both bands hold for every sprite the audit measures. The highest `tone_sat_all` is the
    Mortar Rig at 0.536.
  - Only the mirror row's `renew_artillery` in Signal goes over 0.55 (0.562). The audit does not
    measure mirror sprites, so nothing fails; Michael judges that pair by eye on the sheet.
  - If a later row puts other triads on the sheet, `SameScene.ROUTE_TRIAD` and `is_faction`
    (code) must learn them; the `.tres` stays as it is.
- The comments that name P647's switch to Sne and Karmin become stale: in `SameScene.gd`,
  `ScenarioDef.gd`, STYLE.md "Triads" and the tests. P652 rewrites them, except the comment in
  `same_scene.tres`, which stays frozen (a comment-only change there needs its own yes).

### A10. Cost against rule 6 and the web
- **Frames:** the same bytes, hex strings only (A2). There is no export or web-size change.
- **Atlas:** the mirror pages' page 1 grows by 82 and 60 rows (A2), and the cross-faction
  page does not change. All pages stay within 3584 rows, so the sorted world stays on one page.
- **Draw calls, sprites, frame time and bake time:** unchanged. The bake swaps more pixels of
  the same strings, and the five newly keyed parts are baked once more in a mirror.

### A11. What this replaces in the accepted text
- **§3's title and first bullet** ("The faction colour is a fixed material, never replaced"): the
  panels take the team key (A2). The two fixed materials stay for the item cards and the HUD
  accents only.
- **§3's team marker share** ("2 to 6 % of the visible surface") and its placement as the only
  team colour: at detail 2 and up, TEAM_SHARE 30-65 % of the large panels (A3). The rimmed
  plate may stay as part of it. Its white inner line and dark rim stay where a plate is kept.
- **§3's "except KRITISK":** A7.
- **§3's Migration step 6** (FACTION_SHARE 15-85 %) and **step 7** (the marker shrinks to 2-6 %,
  the last batch narrows TEAM_SHARE to 2-6 %): A3 and A4.
- **§3's "Default team colours" (answer 3, Sne and Karmin):** the lead's proposal in A6,
  which Michael can override.
- **§4's `svg-art-style` text** ("Fixed faction panels may cover large surfaces", "The team
  marker covers 2-6 %"): the skill is not edited here. P652 brings the matching text change to
  the lead, who asks Michael's yes for the skill, as P630b did.
- **§7's per-batch line** "Marker and faction shares are in their bands": TEAM_SHARE (A3) and
  the shape check (A4).
- **The Consequences' "Factions read by colour at any distance, and players by a small marker.
  Mirror matches lean on the marker, the pad and the ring":** players read by the team panels at
  any distance, factions by shape, and a mirror match reads like any other match.
- **The Alternatives' "Team-coloured large panels (P601 as built). Rejected":** chosen now by
  Michael. P601's rejection rested on the 3-20 % team-share test and on fixed colours. Both are
  replaced here, and the bodies are now neutral, which P601's were not.

### A12. Consequences
- A mirror match reads like a cross-faction match: two colours, one per player.
- Faction identity moves from colour to shape. The shape check (A4) and Michael's eye on the
  sheet guard it, and the end-on views stay the weak spot.
- The 18 detail-2 models change in one mechanical row (P652). The batches after it (P643-P647)
  are drawn straight to the new rule, so no model is drawn twice.
- The bands of five suites change, and FACTION_SHARE and the detail-2 half of the roof-plate rule
  go.
- §3's answer 3 is open again as a proposal (A6).

### A13. Alternatives considered
- **Keep fixed colours with a larger marker** (for example 8-12 %). Rejected by Michael's
  answer. A mirror match would still be two orange armies told apart by a patch.
- **Team colour on the bodies as well** (everything but the lamps). Rejected: it leaves no
  neutral body for `tone_sat`, and the sides lose their material language (steel against
  ceramic).
- **Sne and Karmin by default.** A6: the look changes, and the frozen same-scene bands fail
  for Karmin.
- **Keep FACTION_SHARE, inverted** (fixed colour at most 5 %). Rejected: no model paints the
  material, so a band on it would test nothing. A prim-level "no `faction`" check is exact and
  costs nothing.
- **Re-band the exact-tone TEAM_SHARE** (about 14-41 % after the swap). Rejected: it counts the
  seams and tints of each panel as body, so the number would follow the detail renderer rather
  than the art.
