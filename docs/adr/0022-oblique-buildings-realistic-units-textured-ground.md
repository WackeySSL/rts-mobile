# ADR 0022: Oblique buildings, realistic top-down units and textured ground (art direction B)

Status: proposed, 2026-10-26. Docs PR with `docs/plans/2026-10-22-phase-3.md` revision 4. Base:
`main` at 9b690b0. Nothing here is applied in code, art or the style guide until Michael answers the
questions at the end. Builds on ADR 0011 (view draw structure and budget), ADR 0012 §6 (z bands and
batching), ADR 0010 §2 (the fog layer), ADR 0015 (portrait), ADR 0017 §1 (footprints), ADR 0019 §2
and §3 (placement ghost, building taps) and ADR 0021 (the base arena). Supersedes parts of ADR 0012
§6, ADR 0010 §2, ADR 0011 §3 and ADR 0019 §2 (listed under "On acceptance"); no rule of the sim
changes.

## Context
- Michael checked P91 (#172) and P92 (#178) on his phone on 2026-10-26: the art is "too square and
  too toy-like"; he wants it "more true to nature". art-director drew a probe in three directions
  (draft PR #183, branch `claude/art-style-probe`, commit df3bbf2: `assets/art/STYLE.md` section
  "Style probe (2026-10-26, not approved)", `assets/art/svg/probe/`, `game/view/art_gallery_probe.gd`).
  Michael chose **B** the same day: buildings drawn in an oblique 3/4 projection (roof plus the south
  facade with height; the sprite stands on its footprint and rises up to about 0.75 tile above it);
  units stay top-down, because they turn freely, with direction A's realistic treatment (materials,
  weathering, soft shadows, a muted palette, small team markings); the ground in A's textured tiles.
- The probe's B refinery (`b_refinery_hull.svg`, 384x480 at 2x) maps a ground point (x, y) to
  (x, y + 96) and a point z px up to z px higher: the east and west walls are edge-on, so the sprite
  stays inside the footprint's columns and only grows north. Its bottom 384x384 is the footprint,
  its top 96 px (48 px in game, 0.75 tile) rise above it.
- Legal (CLAUDE.md, hard): original art only, hand-written SVG in the repo, no likeness to any
  existing game. Godot 4.7.2's ThorVG draws no SVG `pattern`, and a mask works only with solid fills
  (the probe's finding), so texture comes from gradients and dash arrays.
- What the view does on `main` at 9b690b0:
  - `UnitLayer` draws one rig per unit row, a `Node2D` named `Unit<id>` with the `Sprite2D`
    children `Ring`, `Hull`, `Team` and `Turret`, each at an absolute z per batch group
    (`Z_RING` 1, `Z_FIRST` [10, 20, 100], `Z_LAST` [19, 99, 109]): ADR 0012 §6's bands, which keep
    150 rigs of mixed types and owners at a few draw calls. Sprites at one z batch only while
    consecutive sprites share texture and modulate; the ADR 0012 probe measured 150 calls for three
    textures interleaved at one z, against a ceiling of 60 (`draw_calls_max`).
  - `HealthBarLayer` (z 110), `ProjectileLayer` (120) and `EffectsLayer` (130) each draw in one
    `_draw()`, `FogLayer` (140) is one sprite and `MarkerLayer` (150) holds the move marks; their z
    is set on their node in `scenes/main.tscn` and `scenes/dev/perf_arena.tscn` (the arena has no
    `MarkerLayer`).
    `tests/view/test_fog_layer.gd` (`Z_BARS` 110 ... `Z_MARKERS` 150), `tests/view/test_health_bars.gd`
    and `tests/ui/test_perf_arena.gd` pin these values.
  - `FogLayer` is one RGBA8 texel of black per tile, filtered linearly (a soft edge one tile wide):
    alpha 255 unexplored, `explored_alpha` 140 explored, 0 seen. `UnitLayer` and the bar and
    projectile layers skip what the local player does not see (`FogLayer.is_seen`,
    `FogLayer.covers`, `UnitLayer.is_shown`), and `EffectsLayer` filters each effect as it is born,
    with two items that do rely on the fog drawn over them (z 140 over 130):
    - a rifle `TRACER` (the one hitscan weapon) is added when **either** end is seen
      (`EffectsLayer._add_shot`; ADR 0010 §2's status note of 2026-10-21;
      `tests/view/test_fog_hiding.gd`'s
      `test_a_shot_shows_its_tracer_when_either_end_is_seen_and_its_flash_when_the_shooter_is`).
      It runs from the muzzle (13 px from the shooter) to the target, so its unseen part lies over
      tiles that the fog blacks (unexplored) or dims (explored). Today's data narrows the case
      (rifle `range` 4000 is under every `sight_range`, 5000 or more), but an armed neutral
      (owner 0), a third party or a later weapon with range above sight still draws a line into the
      dark that points at an unseen shooter or target;
    - an own unit's death always shows (ADR 0010 §2), and its tile, dark in that tick, dims it.
  - `MapView` bakes the terrain into one image of `bake_px_per_tile` 8 texels per tile from its
    `colors` and `tiles` exports and draws it as one rect (`draw_count()` 1 in
    `tests/scenes/test_main_scene.gd`). `tests/project/test_cross_file_facts.gd` (qa-engineer, P52)
    holds `test_map_view_colors_and_tiles_equal_the_gallerys_terrain_colors_and_tiles` and
    `test_every_terrain_id_in_the_data_has_a_base_colour_and_a_tile_in_both_map_views`.
  - `Picker.pick` hits a unit when the point is within its `radius_px` of its centre.
- Not on `main` yet: `BuildingLayer` (P84), building picking (P84 or its split P84d), last-seen
  ghosts (P84c), `OreLayer` and the rig pool (P84b), `GhostLayer` (P86), `RallyLayer` (P87), the
  minimap (P88), the cues (P89), the base arena (P80, P93, P93c). P91 and P92 have merged, so every
  view row of Phase 3 that draws a building would be built against art that is about to change.
- A building is a row whose position is the footprint centre (ADR 0017 §1); its cells are blocked,
  so no unit centre is ever inside a footprint. Units have a radius of at most 500 (P72's data test);
  sprite canvases at 2x are 64 (squads), 128 (tanks, artillery) and 160 (harvester), so a unit's
  drawn reach from its centre is at most 40 px axis-aligned and 57 px on a diagonal in game.

## Decision

### 1. The projection and its numbers
- **Buildings are oblique, everything else is top-down.** A building sprite shows its roof and its
  south facade: a ground point (x, y) of the footprint is drawn at (x, y), and a point h px above the
  ground at (x, y - h). There is no sideways skew: east and west walls are edge-on, so **a building
  sprite never leaves its footprint's columns**.
- **The rise is 0.75 tile**: 48 px in game at zoom 1, 96 px at 2x. Every building canvas is its
  footprint plus the rise: 3x3 is 384x480 at 2x, 2x2 256x352, 1x1 128x224, import scale 0.5. A low
  building leaves the top of its canvas clear; nothing is drawn above the rise or outside the canvas
  (no cast shadow onto the ground east or south of the footprint: shading and contact shadows stay
  inside the box).
- **The anchor is the footprint's south edge.** The sprite's bottom edge lies on the footprint's
  south edge, its left edge on the footprint's west edge: the sprite box in world px is
  `(origin_col * 64, (origin_row + foot_h) * 64 - tex_h, foot_w * 64, tex_h)`, so the box is the
  footprint plus 48 px to the north. The view derives the rise from the texture (`tex_h - foot_h *
  64`); no view constant holds it, and `tests/art` pins it on every building canvas.
- **The defence turret's head** (the only building `turret` layer) turns about the footprint centre
  lifted by the rise, the centre of its roof. Its rules stay those of a rotating layer (no shadow,
  shading mirrored about the gun line).
- **Units, effects, projectiles, ore, ghosts' patterns, markers, flags and icons stay top-down.**
  Unit rigs keep the layer contract, canvases, names and pivots (`UnitLayer.ART_DIR` finds them by
  name), so the redraw needs no view change.
- **How the two read together:** one light (top left) for both; the south facades lie in shade and
  the units carry a short soft shadow plus a ring of ambient dark, so both read as standing on the
  same ground; a building's roof hides what stands north of it, and what stands south of it is drawn
  in front (§2). The camera, its zoom levels (0.75, 1, 1.5) and both orientations are unchanged
  (ADR 0015): the projection lives in world space.

### 2. Draw order: each building is cut at its footprint's middle line
- **Rule.** Each building is drawn in two parts, cut along the horizontal line through its
  footprint's centre (`y_mid = origin_row * 64 + foot_h * 32` px):
  - the **base part**, the sprite rows south of `y_mid` (the south half of the roof and the
    facade), is drawn **under** every unit layer;
  - the **roof part**, the sprite rows north of `y_mid` (the north half of the roof and the 48 px
    overhang), is drawn **over** every unit layer.
- **Why it is right.** A unit north of a building has its centre at or north of the footprint's
  north edge, so its pixels reach at most `r` south of it; a unit south has its centre at or south
  of the south edge. Both stay out of the other part as long as `r <= foot_h * 32`, half the
  footprint's depth. That holds for every unit against every 2x2 and 3x3 building (r at most 57 px
  against 64 and 96 px). For the 1x1 defence turret (32 px) it holds for squads and for tanks along
  the axes; a harvester or a diagonal tank hugging its north side can show a few px of its tail over
  the turret's lower wall for a moment (accepted, "Consequences"). Buildings among themselves:
  base parts lie inside their footprints, so they never overlap; a roof part can overlap another
  building's roof part only when a building stands directly south of a 1x1 turret, so the roof
  part is drawn in ascending order of the footprint's south row.
- **Alternatives measured against the budget** (details under "Alternatives considered"): one
  y-sorted canvas for building sprites and unit rigs is exact, but a z_index outranks y-sorting,
  so the rigs would have to give up ADR 0012 §6's bands and interleave types and owners at one z:
  the measured 150 calls. Buildings in row bands interleaved with units multiply the unit groups by
  the map rows. The middle-line cut costs two batches and no sorting per frame.
- **Mechanism.** Two new world layers (touch-ux-dev, P84):
  - `BuildingLayer` (the base parts) and `BuildingRoofLayer` (the roof parts), each one `Node2D`
    that draws all its quads in one `_draw()` with `draw_texture_rect_region` from **one runtime
    atlas**: at match start the view copies every building layer texture it needs (`hull`, `team`,
    and the last-seen dot tile `ui/ghost_seen.svg`) into one `ImageTexture` (about 1024x512 px,
    2 MB). Team tint, the low-power dim and the fog dim (§4) are the quad's colour, which is vertex
    data and does not break the batch (ADR 0012 §6, "What else batches"). So each part is **one draw
    call** however many buildings stand. ADR 0011 §3's rule (per-item quads from one shared
    texture) holds; the atlas is how it holds with per-building SVG files.
  - The defence turrets' heads are `Sprite2D` children of `BuildingRoofLayer`, one per turret
    row, sharing one texture: one more call, and they turn on the frame clock as unit turrets do
    without redrawing the roof list.
  - Each list is redrawn only on a change: the building rows (`rows_version`), a cell of a drawn
    footprint in the local player's fog dirty list (a cell-to-building map rebuilt with the rows, so
    the check is O(dirty cells)), the low-power set, the local player. No redraw in a frame without
    a published change; a `draw_count()` like `MapView`'s lets tests pin it.
- **The z bands** (ADR 0012 §6's table; rows marked new or moved, the rest unchanged):

  | z | Layer | Change |
  | --- | --- | --- |
  | 0 | map (`MapView`), then the ground and ore layers in tree order (§6, P84b) | ground added |
  | 1 | selection rings | unchanged |
  | 2 | `BuildingLayer`: base parts of buildings and last-seen ghosts | new |
  | 10 + `type_index` | hull | unchanged |
  | 20 + 8 x `type_index` + `owner` | team | unchanged |
  | 100 + `type_index` | turret | unchanged |
  | 110 | fog (`FogLayer`) | moved from 140 |
  | 111 | `BuildingRoofLayer`: roof parts, then the turret heads | new |
  | 112 | health bars and the building selection frame (`HealthBarLayer`) | moved from 110 |
  | 120 | projectiles | unchanged |
  | 130 | effects | unchanged |
  | 145 | placement ghost (`GhostLayer`, P86) | new |
  | 146 | rally flags and lines (`RallyLayer`, P87) | new |
  | 150 | markers | unchanged |

- **What stays where, and why.**
  - Rings stay at 1, under the building base, so a ring never paints onto a facade.
  - The unit bands stay as they are: the rig node contract (`[Ring, Hull, Team, Turret]`, names
    `Unit<id>` in row order), `UnitLayer.layer_z` and its tests do not change.
  - The **fog moves under the roofs** (140 to 110), because a roof must show the fog of its own
    footprint, not of the cells north of it that its overhang lies over (§4); the roof layer applies
    the footprint's fog itself. Bars, projectiles, flashes, puffs and bursts are each tested at the
    tile of their point, so above the fog they show nothing of an unseen tile; the pixels of a quad
    centred on a seen tile may now reach over a dark neighbour, which tells nothing new. **One item
    would leak, the tracer** (Context): above the fog its unseen part would show where an unseen
    shooter or target is. So the tracer is **clipped to the seen tiles** (§4, P84). An own unit's
    death burst is no longer dimmed on its dark tile; it shows the player's own unit and nothing
    hidden, so that is accepted. What else changes is the soft one-tile edge, which no longer
    darkens bars, projectiles and effects at the edge of vision.
  - **Bars move over the roofs** (110 to 112), so a unit behind a roof still shows its bar when it is
    selected or hit, and a building's bar and frame sit on its roof.
  - Projectiles and effects stay at 120 and 130, over the roofs: a shell in flight is above the
    buildings, and a hit behind a roof still flashes.
  - The ghost and the rally flags are UI on the map: over everything but the markers.
- **Pooled rigs and interpolation (ADR 0011 §2, P84b) keep working unchanged.** Buildings never
  move, so nothing of them is interpolated; they are no rigs and need no pool (a turret head is
  made once per turret row when the row appears, at event cadence). `UnitLayer` skips rows with a
  footprint, as P84 already planned.
- **Draw calls.** ADR 0012 §6's forecast gains: ground 1 (it replaces the map rect, §6), ore 1,
  building base 1, roofs 1, turret heads 1. For the base arena (six mobile types, two owners, three
  turret types): ground 1 + ore 1 + rings 1 + base 1 + hulls 6 + teams 12 + turrets 3 + fog 1 +
  roofs 1 + heads 1 + bars 1 + projectiles 1 + effects 2 = **32**, under the 40 that triggers
  `MultiMeshInstance2D` and the ceiling of 60. Without the building atlas (textures sorted inside
  each `_draw()` instead) the two building parts alone would cost up to 24 calls instead of 2, about
  54 in all: the atlas is not optional.

### 3. Picking and selection
- **A tap on a building's picture selects it:** the pick shape is the sprite box (footprint plus the
  overhang), grown about its centre to at least 48 dp on each axis at the current zoom (touch rule
  unchanged; it matters for the 1x1 turret at zoom 0.75).
- **Units first:** a unit hit (`Picker.pick`'s circle) wins over a building box at the same point,
  so a unit next to or partly under a roof stays tappable. Among buildings, the one with the larger
  footprint south row wins (it is drawn in front). Own and enemy follow the unit rule (with a
  selection, an enemy wins). A building the fog hides and a last-seen ghost are not pickable.
- Buildings still never join a box, a double-tap selection or "All army" (ADR 0019 §3); a box uses
  unit centres as today.
- **The selection frame** is four corner brackets of filled rects round the sprite box, drawn by
  `HealthBarLayer` in its one `_draw()` (z 112), white like the selection ring, with
  `FeedbackStyle`'s stroke rule (a `STROKE_DP` 3 pass over an `OUTLINE` pass `OUTLINE_DP` wider);
  question 2 decides box or footprint (recommended: the box, what the player tapped).
- **The building's health bar** is centred on the footprint's columns with its top edge 2 dp below
  the sprite box's top edge, inside the box, so it never covers a neighbour north of the building;
  its size in dp is a row of STYLE.md's "Health bars" (P91b adds it). The offline glyph of P89 sits
  on the roof's centre (the footprint centre lifted by the rise), in the same layer.

### 4. Fog and memory
- **The overhang gets the fog of its footprint.** The base part is under the fog layer, so its
  pixels get the fog of the footprint cells they lie on, soft edge included. The roof part is over
  the fog layer and carries the building's fog state as its quad colour: a seen building white, a
  last-seen ghost the explored dim, `1 - explored_alpha / 255` on each channel (black at alpha 140
  over a colour is that colour times 115/255), so both parts of a building that lies wholly in one
  state match exactly. A building the local player does not see is not drawn (P84's rule); a ghost is
  drawn only where its cells are explored and not seen (P84c's rule).
- **Partly seen buildings** (vision edge across a footprint): the roof part is drawn as seen while
  the base part's unseen cells are dimmed by the fog under it. Accepted; it occurs only at the edge
  of vision and lasts until the next fog update. A fog shader that samples the fog texture at the
  ground point under each roof pixel would be exact; it is the fallback if Michael's phone check
  finds the seam ("Alternatives").
- **Last-seen ghosts (P84c)** are drawn in the same projection by the same two layers: the building
  in the other team's colour, cut at the same line, with the `ghost_seen` dots (from the atlas, one
  quad per 64 px of the box) over the **whole sprite box**, because the remembered picture, roof
  included, is what the dots mark. Never a bar, never pickable.
- `reveal_enemies` (the perf arena) draws every building as seen, as `UnitLayer` does.
- **Tracers are clipped to the seen tiles** (P84, touch-ux-dev; `EffectsLayer` is that owner's
  file), because the fog no longer covers the effects (§2). The birth rule of ADR 0010 §2 stays: a
  tracer is added when either end is seen, so fire from the dark still shows its direction. A
  tracer with both ends seen is drawn whole. A tracer with one end seen is drawn from that end
  towards the other and ends at the last point whose tile the local player sees in that tick's fog,
  found at birth by stepping along the line from the seen end in steps of 16 px (a quarter tile),
  at most the weapon's range in px / 16 + 1 steps, at event cadence and without allocation; the
  slot keeps the clipped end, so `_draw` does not change. `reveal_enemies` draws it whole.
  `tests/view/test_fog_hiding.gd` gains the case: a shooter on a dark tile three tiles east of a
  seen target gives a tracer whose far end lies on a seen tile within 16 px of the dark one, and
  a shooter and target both seen give the whole line; the existing either-end test keeps its counts.

### 5. Placement ghost (ADR 0019 §2)
- The ghost is the building's whole sprite in the same projection (no cut: it is above every unit
  layer), anchored on the footprint's south edge like a placed building, faded as one group
  (`CanvasGroup.self_modulate`, alpha 0.7, STYLE.md "Ghosts").
- **The footprint is marked on the ground:** the wash is drawn first on the footprint rect, then the
  faded sprite, then the hatch (if it does not fit) and the solid frame on the footprint rect, so the
  cells that will be blocked read through the sprite; the overhang shows the faded sprite only. The
  reason's glyph sits at the footprint's centre.
- The grab area of ADR 0019 §2 ("its footprint plus 24 dp") becomes **the sprite box plus 24 dp**:
  a finger on the roof grabs the ghost. The ghost still follows the finger 64 dp above the touch
  point (the footprint's centre is the reference) and snaps to tiles; the rest of §2 is unchanged.
- `GhostLayer` draws at z 145.

### 6. Ground
- **A's textured tiles replace the drawn map**, not the map's model. New art files
  `assets/art/svg/ground/<terrain_id>_a.svg` and `<terrain_id>_b.svg` for every terrain id of
  `data/terrain/standard.tres` (grass, sand, scrub, rock, water, ore), 128x128 at 2x, import scale
  0.5, with a flat edge band so tiles join (the probe's `a_grass_*`, `a_sand_*`). Variant a or b per
  cell is a fixed function of the cell (no randomness, view only).
- **Mechanism:** a `GroundLayer` (touch-ux-dev, new row P97), a `TileMapLayer` at z 0 after
  `MapView` in tree order, whose `TileSet` has one `TileSetAtlasSource` on a runtime atlas of the
  ground textures (the helper of §2), filled once per match and on each `map_version` change. Its
  quadrants are culled by the engine and share one texture, so they batch into one call (to be
  confirmed by P97 with the ADR 0012 probe method, the way the unit bands were measured). A full
  bake at 64 px per tile was rejected: a 64x64 map is a 4096x4096 texture (64 MB).
- **`MapView` stays the map's model.** Its `colors`, `tiles` and 8 px bake (`image()`) stay: the
  minimap (P88) may read them, the missing-art fallback uses them, and the P52 cross-file facts
  between `MapView` and the gallery stay as they are (no exception). It stops drawing its rect when
  a `ground` node path is set and that layer covers the map (the main scene and the perf arena), so
  `test_main_scene.gd`'s `draw_count()` assertion moves to 0 in P97 (touch-ux-dev's own suite). The
  rect patterns then show only where the bake is shown; removing them is a later cleanup with its
  own cross-file plan, not part of this ADR.
- **Ore:** the nine ore tiles keep their names, canvas and levels (STYLE.md "Ore") and are redrawn
  in A's treatment; P84b's `OreLayer` draws them from an atlas at z 0 after the ground. The ore
  terrain's ground tile is the dirt under them.
- **Minimap (P88): unaffected.** It is a plan view (footprints as rects, rows as dots, terrain as
  base colours), redrawn at fog cadence as ADR 0019 §4 says; the projection does not reach it.

### 7. Art: what is redrawn, in which order
- **Redrawn under the same file names** (so every view row can be built against names that do not
  change):
  - the six buildings' `hull` and `team` and the turret's `turret`, in B (new canvases, §1);
  - the five building item icons (`icons/item_<building>.svg`) in B, the six unit item icons in A's
    palette (canvas and import scale unchanged; the sidebar finds them by name);
  - the six units' layers (15 files) in A's treatment, keeping canvas, pivot, facing (+x), the
    harvester's bin rectangle (x 32 to 90, y 56 to 104 at 2x, which P84b's cargo cue fills) and the
    light tank's and rifle squad's reach within 2 px of `HealthBarLayer`'s `VEHICLE_REACH_PX` 26 and
    `INFANTRY_REACH_PX` 14 (or the row says the new reach in its "Requests");
  - the nine ore tiles in A's treatment.
- **New:** the twelve ground tiles (§6).
- **Unchanged:** tab icons and glyphs (UI greys, tinted at run time), the ghost patterns
  (`ui/ghost_hatch.svg`, `ui/ghost_seen.svg`), the selection ring, the effects atlas and the two
  rally flags. Any of them is redrawn only if Michael's phone check asks for it.
- **The probe:** PR #183 is not merged; its files are the pattern for the new rows, which copy and
  finish them under the real names, and close #183 with the first of them (P91b).
- **Order against P84:** P91b (buildings) comes first and P84 depends on it, so P84 builds against
  the new canvases and the anchor; then P92c (ground and ore, which P97 needs); then P92b (units),
  which no view row waits for. Rows and owners: plan revision 4.
- **Style guide and skill** (art-director edits `assets/art/STYLE.md` in each art row; the skill
  only after Michael's yes, question 5): "Look" (flat goes, "not photoreal" stays, buildings in a 3/4
  view), "Scale" (building canvases with the rise), "Palette" (A's muted values: tarmac #4A4F53 to
  #62676A, concrete #8D8F88, corrugated steel #5D6B68 to #A0ACA8, olive drab #46532F to #78885B,
  rust #8F5731), "Drawing rules" (the 3 px outline becomes a thin dark edge plus a contact rim and a
  short soft shadow; team marks about 8 to 12 % instead of 20 to 35 %, question 3), "Technical
  rules" (`defs`, `radialGradient`, `clipPath` and `use` with `href="#id"` allowed; no `pattern`;
  a mask only with solid fills; at most 28 KB), "Layer contract" (shadows), "Buildings" (projection,
  canvas, anchor, middle-line cut, turret pivot, no pixel outside the box), "Ghosts" (dots over the
  sprite box; placement marks on the footprint), "Ore", "Fog and terrain" (ground tiles), "Health
  bars" (the building bar row; the bar band), "Reskin" (place 2 gains the ground files), "Gallery".

### 8. Performance
- **No new arena.** The base arena (ADR 0021 §2: about 30 buildings of every type, 150 mobile rows,
  P80) is the building-heavy case, and its phone card (P93c) counts the draw calls and times the
  frame with the ground, both building parts, the fog at its new z and the bars. The perf arena card
  sees the ground (P97) and nothing else of this ADR. The sim does not change: golden hashes,
  `budget.cfg` and every `PERF` line stay as they are.
- **Headless proof before the phone** (P84, P97): the z of each new and moved layer in both scenes;
  each building part draws from one texture (the atlas) whatever the mix of types, owners, ghosts
  and dim states; the roof list is redrawn on a change only (a `draw_count()` that does not move over
  frames without a published change); the middle-line cut on crafted footprints and unit
  positions (a unit north never in the base part's rect, south never in the roof part's); the
  forecast of §2 computed from a base-arena-like snapshot is at most 40.
- **Gate:** unchanged thresholds (`draw_calls_max` 60, `work_p95_ms` 5.6, ...); the Phase 3 gate
  runs both cards three times each (ADR 0021 §3). P93c also frames the base arena's camera on every
  sprite box, overhangs included (the P50c rule).

## Consequences
- Every Phase 3 view row that draws a building waits for P91b; P84 grows by about 110 lines and
  takes its named split P84d (picking and selection). Five new rows (one docs, three art, one view),
  about 520 production lines in all (plan revision 4).
- A unit north of a building can be hidden by the roof; its bar still shows when it is selected or
  hit (question 1).
- The 1x1 defence turret's lower wall can show a few px of a harvester or a diagonal tank hugging
  its north side; a unit touching a building's east or west wall is cut at the middle line where
  its pixels cross the footprint's columns. Both are short-lived and only a few px.
- A building on the map's top row shows its roof cut at the map's edge, because the camera stops at
  the map rect (`test_camera_limits_equal_the_map_rect`); if the play sessions find it, the camera's
  top limit grows by the rise in a touch-ux-dev row.
- The fog no longer softens bars, projectiles and effects at the edge of vision, and no longer dims
  an own unit's death burst on its dark tile. A tracer fired from or into the dark is drawn only
  over the seen tiles (§4); at the vision edge it ends up to 16 px short of the dark tile.
- Team colour on a sprite drops to about 8 to 12 %: ownership reads from stripes and bands and is
  weaker at zoom 0.75 (question 3); the art rows show both teams at every zoom in the gallery.
- SVG files grow (the probe's B refinery hull is 25.2 KB); the import time and the APK grow a little.
- The reskin principle (Michael, 2026-10-15) holds: units and ore change by file name, ground by a
  folder of named files, buildings by file name plus the canvas rule.

## Alternatives considered
- **One y-sorted canvas for buildings and rigs** (`y_sort_enabled` on a parent of building sprites
  and unit rigs, keyed by the footprint's south row and the unit's position): exact, but z_index is
  applied before y-sorting, so every rig layer would share one z and types and owners would
  interleave: 150 calls measured for three textures at one z (ADR 0012's probe), against 60. It also
  breaks the rig contract's per-layer bands.
- **Buildings in row bands interleaved with units** (z = row band x K + group): calls grow with the
  rows on screen times the unit groups (about 20 x 20), and Godot's z range (-4096 to 4096) runs
  out on a 64-row map.
- **Cut at the eave** (the facade under the units, the whole roof over them): fails for every
  footprint shallower than the rise plus a unit's reach (1x1 and, for the harvester, 2x2).
- **The whole building under the units, the overhang only over them:** a tank behind a roof would
  stand on its south half.
- **A fog shader on the roof layer** (sample the fog texture at the pixel's ground point): exact at
  the vision edge, but a custom shader on the Compatibility renderer and the web export, a uniform
  for the fog texture and its transform, and the bars and effects would still need the move. Kept as
  the fallback for §4.
- **Keep the fog at 140 and draw the roofs over it at 141:** bars, projectiles and effects (110 to
  130) would vanish behind roofs.
- **A second fog draw above the effects (z 135) with the unexplored alpha only**, to keep hiding the
  tracer's unseen part: one more call (33 in the forecast) and a second fog texture kept up to date
  from the dirty lists (twice the upload), it would black a roof's overhang that lies over
  unexplored cells, and it still would not hide the part over explored cells (only dimmed today).
  Clipping the tracer (§4) costs no call and hides the part over every unseen tile.
- **Draw the ground per visible tile in `MapView._draw()`:** hundreds of commands re-recorded on
  every camera move, on the main thread.
- **A non-turning shadow sprite per unit** (the probe's note for longer tank shadows): one more
  band per type and a fifth child in the rig contract; not now.
- **A (realistic top-down) for buildings too:** cheaper (no draw-order change), but Michael chose B.

## Questions for Michael
1. A unit that drives behind (north of) a building is hidden by its roof; its health bar still
   shows on top when it is selected or hit, and a tap on it still selects it. Is that fine?
   (ja/nej; recommended: ja)
2. When you select a building, what does the frame go around? A: the whole picture, roof included,
   which is what you tapped. B: only the ground the building stands on. (A/B; recommended: A)
3. Units and buildings show their team colour as thin stripes and bands (about a tenth of the
   sprite instead of a quarter to a third), so the picture looks real but ownership is a little
   harder to see when zoomed out. Is that fine? (ja/nej; recommended: ja, and you check it in the
   gallery at zoom 0.75 on your phone)
4. Should the new textured ground come in Phase 3 (one art row and one view row, off the critical
   path) rather than after the gate? (ja/nej; recommended: ja)
5. May art-director's style guide and the `svg-art-style` skill change as listed in §7 (a 3/4 view
   for buildings, the muted palette, thin edges instead of outlines, smaller team marks, the new SVG
   rules), and CLAUDE.md's "2D top-down" line name the oblique buildings? (ja/nej; recommended: ja)

## On acceptance (lead, docs row P68d; nothing before Michael's answers)
- This ADR: status "accepted" with the date and the answers; the plan's revision 4 rows become
  plain rows (or are withdrawn on a "nej" to the ADR as a whole).
- Dated status notes, never a rewrite: ADR 0012 §6 (the z table and the forecast of §2 here; the
  "Markers" and "What else batches" items stand), ADR 0010 §2 (the fog layer draws at z 110, under
  the roofs, bars, projectiles and effects; the "either end" tracer rule of its 2026-10-21 status
  note stays as the birth rule, and the tracer is drawn clipped to the seen tiles, ADR 0022 §4),
  ADR 0011 §3 (`MapView` is not drawn where the ground layer covers the map; the per-building atlas
  is how the one-texture rule holds), ADR 0019 §2 (the grab area is the sprite box plus 24 dp; the
  ghost is drawn in the projection, §5) and §3 (a tap on the roof selects the building; units win).
- `.claude/skills/svg-art-style/SKILL.md` (with Michael's yes to question 5): "Look", "Camera and
  scale" (pure top-down for units, the oblique view and canvases for buildings), "Palette" (A's
  values), "Drawing rules" (edge, rim, shadow, team share), "Technical rules" (elements, 28 KB, no
  `pattern`, masks with solid fills only).
- `.claude/skills/touch-ui-rules/SKILL.md` (Michael's yes, as for any skill): "Tap own building"
  picks on the whole picture, roof included; a unit at the same point wins.
- `CLAUDE.md` Stack line "2D top-down" gains "buildings in an oblique 3/4 view (ADR 0022)"
  (Michael's yes, question 5).
- `docs/GDD.md` line 81 ("flat top-down military-map look") becomes the new look in one sentence.
- Not changed: `docs/ROADMAP.md` (no box changes), the sim, `rts-sim-conventions`, the perf
  thresholds.
- `assets/art/STYLE.md` is art-director's and changes in P91b, P92c and P92b, not in P68d.
