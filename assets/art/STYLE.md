# Art style guide (living)

This is the living version of the `svg-art-style` skill (`.claude/skills/svg-art-style/SKILL.md`)
plus the layer contract for multi-layer units. All art is hand-written SVG in this repository.
Update this file when Michael approves a change; the skill stays the short checklist.

Status: v1, written in Phase 0 with the light tank sample. v1.1 (Phase 1, P12) adds the feedback
markers and the gallery zoom row. v1.2 (Phase 2, P34) adds the rifle and rocket squads, the selection ring
texture, the effects atlas and the specs for combat effects, health bars, fog and terrain. v1.3 (Phase 3, P91) adds
the six buildings, the ore cells and the two ghost patterns, and two more gallery pages. v1.4 (Phase 3, P92) adds
the heavy tank, the artillery and the harvester, the tab, item and glyph icons, the two rally flags, and two more
gallery pages. Rules marked **(new)** go beyond the skill and are waiting for Michael's approval (list at the end).

## Look
Clean, flat, top-down "military map" style with strong silhouettes, readable at small size on a
phone. Not cartoonish, not photoreal. Pure top-down view, light from the top-left.

## Scale
- 1 tile = 64 px in game at zoom 1. Author at 2x: 1 tile = 128 px in the SVG.
- Canvas at 2x: infantry squad 64x64, light vehicles 96x96, **tanks 128x128**, harvester 160x160,
  buildings 128x128 (1x1 tile), 256x256 (2x2 tiles) or 384x384 (3x3 tiles), an ore cell 128x128,
  a rally flag 128x128. **Icons and glyphs are 128x128 with import scale 1.0 (new)**, because they
  are drawn at 24 to 64 dp, not in tiles (see "Icons and glyphs").
- Godot rasterises an SVG once, at import. Showing a sprite above scale 1 therefore looks soft.
  The gallery's main row shows scale 1. Its zoom row shows the light tank at 0.75, 1.0 and 1.5.

## Palette
| Role | Hex | Luminance (0-255) |
| --- | --- | --- |
| Outline | #1C2127 | 32 |
| Drop shadow | #000000 at 25% | |
| Metal shade / mid / highlight | #5B6670 / #7D8893 / #A9B4BE | 100 / 134 / 178 |
| Olive shade / mid / highlight | #4E5A3A / #6B7A4F / #8C9A6B | 83 / 113 / 144 |
| Sand shade / mid / highlight | #B59F72 / #CDB98F / #E4D6B3 | mid 186 |
| Grass (map) | #5E7D4A / #6F8F57 | grass 127 |
| Dirt / rock | #8A6F4D / #6E6A66 | |
| Rock lit / shade (new) | #8C8782 / #4F4B48 | 136 / 76 |
| Dirt shade / highlight (new) | #6F583B / #A3865E | 92 / 138 (the dirt itself, #8A6F4D, is 115) |
| Water | #2E5E7E / #3C7396 | |
| Ore | #F2B705, highlight #FFD84D, shade #A67C00 | |
| Team A / team B / neutral | #2F80ED / #E5484D / #9AA5B1 | 116 / 120 / 163 |
| UI accents: warning / danger / ok | #F5A524 / #E5484D / #30A46C | |
| HUD panel backdrop | #0F141C at 78% | 19 |

Luminance is 0.299 R + 0.587 G + 0.114 B. Use it when you judge the greyscale check below.

The HUD panel backdrop is the one palette value that lives in the UI Theme (`game/ui/theme.tres`,
`Color(0.06, 0.08, 0.11, 0.78)`, behind the selection panel). The hex is the 8-bit rounding of the
theme's floats: the theme is the value of record, and `tests/ui/test_ui_theme.gd` pins the floats.

**Team layer greys (new)**: white #FFFFFF, shade grey #BFBFBF, edge grey #4D4D4D. Every colour in
a team layer has R = G = B, so the runtime tint stays clean.

## Drawing rules
- Outline 3 px (at 2x) on the outer silhouette, 1.5 px on inner details. Outline colour #1C2127
  (team layers use the edge grey instead).
- Three tones per material plus a highlight on edges that face the top-left.
- Filled shapes and gaps are at least 2 px at 2x. Inner outline strokes may be 1.5 px. (This is how
  we read the skill's "1.5 px inner details" together with "nothing thinner than 2 px".)
- **Elevation reads as lightness (new).** The lower the plane, the darker the olive: hull deck
  #4E5A3A, turret #6B7A4F, hatches and barrel in metal, highlights #8C9A6B / #A9B4BE. This keeps
  the turret apart from the hull at 32 px greyscale without a bigger palette.
- The silhouette must be identifiable at 32 px in greyscale. A gun or other weapon must also stick
  out of the body as its own shape in the pure silhouette, at least 3 px long and 3 px thick at
  32 px (see "Readability check").
- The team-coloured area covers 20-35% of the visible surface and always includes a stripe or
  marker visible from above.

## Technical rules
- One drawing per file with `width`, `height` and `viewBox="0 0 W H"` set to the canvas.
- Allowed elements: `svg`, `g`, `path`, `rect`, `circle`, `ellipse`, `polygon`, `polyline`, `line`,
  `linearGradient` and its `stop` children (sparingly; the tank uses none). Not allowed: text, image, filter, mask,
  foreignObject, external href, style blocks, scripts, raster data.
- At most 20 KB per file; integer or one-decimal coordinates. A group `opacity` is fine and flattens
  overlapping shapes (used for the shadow).
- Start each file with XML comments: the layer, then the silhouette in one line. Do not use the
  forbidden words in comments either, because the check is a plain `grep` (this rules out words
  such as "description", which contains "script").
- Naming: `assets/art/svg/<category>/<name>[_hull|_turret|_team].svg` in snake_case.
- Godot imports SVG directly. Commit the `.svg.import` next to each file with `svg/scale=0.5`:
  1. Write the SVG, run `godot --headless --path . --import` (this creates the `.import` with
     `svg/scale=1.0`).
  2. Set `svg/scale=0.5` in the `.import` file and import again. The uid does not change.
  3. Check the texture: a 128 px canvas must load as 64x64 (`ui/selection_ring.svg` is the
     exception: import scale 1.0, 168 px).

## Layer contract (multi-layer units)
Vehicles are drawn from three layers that share one canvas size:

| Order | File | Holds |
| --- | --- | --- |
| 1 | `<name>_hull.svg` | Tracks or wheels, hull deck and the ground shadow of the whole vehicle |
| 2 | `<name>_team.svg` | White and grey team marks, tinted with `modulate` |
| 3 | `<name>_turret.svg` | Turret and gun; rotates about the canvas centre |

- Draw order across rigs, not per rig (ADR 0012 section 6, one z per batch group): every ring, then
  every hull, then every team layer, then every turret. Two overlapping rigs can therefore show a
  neighbour's team layer over this hull, or a neighbour's turret over this team layer, for a moment
  (separation keeps overlaps short). The art must read right that way, and also with a neighbour's
  hull over this team layer, as under the old per-rig order: every team mark keeps its own #4D4D4D
  edge and stays inside its unit's footprint, and no hull relies on its team layer to look finished.
- Hull and team share one orientation. The hull faces +x (east). Rotating the vehicle rotates hull
  and team together.
- The turret pivot is the canvas centre. Turret art is drawn facing +x.
- All layers of one unit have the same canvas. Tanks: **128x128 at 2x**.
- Import scale **0.5** for every layer, so 128 px becomes 64 px, one tile.
- Team layer: tinted at runtime with `modulate` (team A #2F80ED, team B #E5484D, neutral #9AA5B1).
  Keep it clear of the turret ring where possible so it shows at any turret heading.
- **Rotating layers (new).** The ground shadow lives only in the hull layer. A turret layer has no
  drop shadow and no one-sided light: its shading is mirrored about the gun line, so it still
  looks right when it turns. Give it one off-axis detail (hatch, sight) so the heading is readable.
- **Infantry squads** have two layers, hull and team, on a 64x64 canvas (32 px in game, import scale
  0.5) and no turret: the whole rig turns toward its target. The hull holds every soldier and weapon,
  facing east. The team layer holds one marker per soldier (a helmet cover; also a band on each rocket
  tube), clear of the shoulders and weapons so it shows at any heading.

## Buildings
Six buildings, drawn from above on a pad that covers their whole footprint, so the sprite's box is
the blocked cells (ADR 0017). Each has one canvas per layer, one tile (128 px at 2x) per footprint
tile: 3x3 is 384x384, 2x2 is 256x256 and the 1x1 defence turret 128x128. Import scale **0.5**, so
the sprite is 64 px per footprint tile in game. The pad's outline starts 6 px inside the canvas and
the shadow (offset 4,4) ends inside it.
- Files: `buildings/<id>_hull.svg` and `buildings/<id>_team.svg` by building id, the names of the
  unit layers, so one loader reads both. `hull` is the building's body: pad, roof and the ground
  shadow. `team` is white and grey marks tinted at run time, under the same rules as a unit's. Only
  the defence turret has `turret`, a gun head that turns about the canvas centre under the rules
  for rotating layers (no shadow, shading mirrored about the gun line, one off-axis detail).
- The hull draws a neutral plinth under every team mark (the darkest olive, or a metal deck), so it
  looks finished without its team layer, and the team mark sits 3 to 4 px inside it with its own
  #4D4D4D edge. Buildings never overlap, so the draw-order rule for rigs holds trivially.
- The team-coloured share is 20-35 % of the building's visible body (the shadow left out) at every
  quarter turn of the gun head. The team marks are large roof plates and rings, because a building
  is big: they say who owns it from one tile away.
- Use seen from above: a refinery or a vehicle factory shows what it is for. The refinery's gold
  funnel and the factory's bay with its two arrows both sit in the middle of the south wall. The
  art therefore assumes the dock and the exit are the middle cell south of the footprint: offsets
  (1, 3) for the 3x3 buildings. The barracks' yard opens south, so its exit is (0, 2) or (1, 2).
  The offsets are data (`BuildingDef`, P72); this is what the sprites show.
- The view dims a building on low power with `modulate` on the whole rig. Health bars, the offline
  glyph and damage are the view's and P92's, not part of these files.
- The hazard arrows of the vehicle factory are the UI warning accent #F5A524 (palette), the refinery
  funnel holds the ore colours; nothing else in a building uses either.

## Ore
Nine opaque tiles, `ore/ore_<level>[a|b].svg`, 128x128 at 2x, import scale 0.5, so one tile is
64 px. Each tile is dirt #8A6F4D to every edge, with speckles in the two new dirt tones and gold
nuggets in the ore colours (outline, highlight on the top left, shade on the lower right, shadow
offset 4,4). Nothing reaches the outer 4 px (2 px imported), so two tiles side by side show bare
dirt on both sides of the join and the map keeps its "no grid" rule.
- The level of a cell is 0 when `ore_amount` is 0 and `1 + (amount - 1) * 4 / ore_cell_max`
  (integer division) above it, so 1 to 5 is level 1, 6 to 10 level 2, 11 to 15 level 3 and 16 to 20
  level 4 at `ore_cell_max` 20. A cell that regrows climbs the levels one at a time.
- A tile name is its level, plus `a` or `b` from level 1 up: two layouts of the same gold, so a
  field does not repeat. The suggested pick is `(col + row) % 2`, so neighbours differ.

| File | Level | Look | Bright gold at 64 px |
| --- | --- | --- | --- |
| `ore_0.svg` | 0 | bare dirt, three dug-out pits with a lit lip, three dull flecks of gold | 0 |
| `ore_1a.svg`, `ore_1b.svg` | 1 | three small nuggets | 63 |
| `ore_2a.svg`, `ore_2b.svg` | 2 | one medium and three small | 137 |
| `ore_3a.svg`, `ore_3b.svg` | 3 | one large crystal, two medium and one small | 377 |
| `ore_4a.svg`, `ore_4b.svg` | 4 | two large, two medium and two small, packed | 606 and 604 |

There is no team layer: ore is neutral. The tiles are opaque, so they cover whatever colour
`MapView` bakes for the terrain `ore`, but the key must exist from the day the terrain does: P70 adds
the id `ore` to `data/terrain/standard.tres`, and the same tree must carry the key `ore` in
`MapView.colors` and `MapView.tiles`, the gallery's `TERRAIN_COLORS` and `TERRAIN_TILES`, the two
terrain tables under "Fog and terrain" and the terrain lists of `tests/art`, because `tests/project`
(every terrain id has a colour and a tile in both map views; `MapView` and the gallery hold the same
keys) goes red without them. The proposal is the dirt the tiles are filled with: key `ore` #8A6F4D,
tile `0,0,8,8,ore`, probe 3,3. The key is not in this PR's tables because `MapView` is another
owner's file (see "Open points", the request for P70).
Greyscale check: the dirt (115) is as bright as grass (110 and 127), so the nuggets carry the field:
gold 180 to 212 with a 3 px outline at 32. At 32 px per tile in greyscale the five levels read apart
by the number and size of the nuggets alone, and level 0 by its dark pits.

## Ghosts
A ghost is a building drawn as a plan: where the player is about to place one (ADR 0019 section
2), and a building last seen (ADR 0017 section 3, plan P84c). Two pattern tiles do the work, both
seamless, white and grey only and tinted at run time like a team layer: `ui/ghost_hatch.svg` and
`ui/ghost_seen.svg`, 128x128 at 2x, import scale 0.5, so 64 px. They are drawn tiled
(`TextureRect` with `stretch_mode` TILE, or a tiled `draw_texture_rect`) over the **footprint
rectangle**, not the sprite's outline, because the hatch also shows which cells are blocked.
Each meaning has its own shape (see "Shape as second cue"): bold diagonal bands rising to the right
mean it does not fit, fine staggered dots mean last seen, and a solid frame and no pattern mean it
fits.

| Ghost | Building | Wash | Pattern | Frame |
| --- | --- | --- | --- | --- |
| Fits | own team colour, faded as one group | #30A46C | none | solid, #30A46C |
| Does not fit | own team colour, faded as one group | #E5484D | `ghost_hatch.svg` tinted #E5484D | solid, #E5484D |
| Last seen | the other team's colour, not faded | none | `ghost_seen.svg` tinted #9AA5B1 | none, no health bar |

The numbers: sprite alpha 0.7 (the whole rig in one `CanvasGroup`, faded through its
`CanvasGroup.self_modulate`: `modulate` would reach the hull and team sprites too and blend twice,
so the hull would show through a team plate, as `MoveMarkerLayer` notes), wash alpha 0.3, hatch alpha 0.8, dots alpha 0.7 and a frame 3 dp wide
(the marker stroke rule, dp over zoom in world space; the gallery draws 3 base px). A last-seen
ghost is drawn under the fog like any explored tile, so it is dimmed by the explored fog alpha (140)
and carries no other dimming. The reason's glyph for a placement that does not fit is
`icons/glyph_reason_<reason>.svg` (see "Icons and glyphs"); the view of P86 places it.
The gallery's `GHOST_*` constants hold these values and `tests/art` pins this paragraph to them;
the values are a proposal for touch-ux-dev to tune with Michael.

## Heavy tank, artillery and harvester
Three vehicles of Phase 3 (plan row P92), drawn under the layer contract above. Their file names are
the type ids of P72's data files (`heavy_tank`, `artillery`, `harvester`), so `UnitLayer` finds them
as it finds the light tank. The art says what each is for from above; every number is in
`data/units/`. The ground shadow lives in the hull, a turret layer has none and is shaded the same
either side of the gun line, and each turret has one off-axis detail, as under "Layer contract".

| Unit | Canvas (2x) | Layers | What turns | Team marks (white and grey) |
| --- | --- | --- | --- | --- |
| Heavy tank | 128x128 | hull, team, turret | the turret, about the canvas centre | a plate on each track pod, two wedges on the nose, a strip on each rear corner of the deck |
| Artillery | 128x128 | hull, team, turret | the gun house, about the canvas centre | a strip down the spade, a plate across the rear deck, a plate on the cab roof, a strip along each deck edge |
| Harvester | 160x160 | hull, team | the whole rig, like a squad: it is unarmed and has no turret | a plate on each track pod, a strip along the top, bottom and rear rim of the bin, the cab roof, a cap on each end of the reel bar |

- In game (import scale 0.5) the tanks are 64x64 px, one tile, and the harvester is 80x80 px.
- **Heavy tank**: the broad one. Its track pods are flat-sided slabs with chamfered fronts, not the
  light tank's round-ended capsules, and its hull is 96 high against the light tank's 80 (at 2x).
  Its barrel is the thickest of the three guns: 12 plus the outline, with a fat fume bulge and a
  cross-bar muzzle brake. One barrel only.
- **Artillery**: the only wheeled vehicle. Three fat tyres a side give it a comb outline, and a wide
  folded spade plate across the back makes the rear a T. Its gun is the longest and the thinnest.
  The open gun house is nearly square (40x42 at 2x), so the plates round it stay covered about the
  same at every heading.
- **Harvester**: a combine. Two track pods either side of one square open bin, a small cab in front
  of it, and a reel bar wider than the pods with a row of ten teeth across the nose.
- **The bin for the cargo cue (P84b).** The hull draws the bin empty: a dirt-dark floor (#6F583B)
  with a lit lip (#A3865E). The floor is the rectangle x 32 to 90, y 56 to 104 of the 160 px canvas,
  which is x 16 to 45, y 28 to 52 in imported px (29x24): its centre is 9.5 px behind the unit's
  centre. The view fills it in the ore colours by the cargo carried; there is no cargo layer.
- Silhouettes in greyscale at 32 px: the light tank is an H with round ends; the heavy tank a
  chamfered slab with an eight-sided turret; the artillery a comb with a T at the back; the
  harvester an H with a toothed bar across the nose.

Results (P92, scratch script, imported scale 0.5, alpha above 0.5): the team layers have no
non-grey pixel. The visible team share, by the tank's definition (shadow left out, nothing under the
turret), is 30.0 / 22.8 / 30.0 / 22.8 % for the heavy tank and 27.7 / 26.9 / 23.9 / 26.9 % for the
artillery at turret headings 0 / 90 / 180 / 270 degrees, and 24.0 % for the harvester. The heavy
tank's gun leaves the hull 9 px long and 12 px thick (the muzzle brake) and the artillery's 12 px
long and 6 px thick, which is 4.5 by 6 and 6 by 3 px at 32 px, over the 3 by 3 minimum. At 32 px
greyscale on grass and sand the three read apart from each other and from the light tank, and
the turret and gun of each keep their own shape at all four headings.

## Icons and glyphs
Icons live in `assets/art/svg/icons/`, named `<kind>_<name>.svg`, three kinds, all 128x128 with a
clear background. **Import scale 1.0 (new)**: an icon is drawn from 24 to 64 dp (42 to 152 base px
across the phone profiles), not in map tiles, so one sharp 128 px raster serves every size, as the
selection ring does. The world art (units, buildings, flags) keeps scale 0.5.
- `tab_<tab>`: the build tabs, Structures, Infantry and Vehicles, named by the tab.
- `item_<type_id>`: a build tile's icon, one per buildable type, named by P72's type id. The eleven
  types are the five buildings the player builds and the six units. The Headquarters is not
  buildable and has none.
- `glyph_<name>`: HUD, map and result glyphs. A placement reason's glyph is
  `glyph_reason_<reason>`, the `Placement.Reason` name in lower case (`outside`, `ground`,
  `occupied`, `unexplored`, `too_far`, `cap`); the view finds it by name. `OK` has none, and the
  "Blocked" of a pending ghost uses `glyph_reason_occupied`.

**Item icons** are in palette colours, top-down like the sprites and simplified for a small size,
with a 4 px outline, thin inner details at 2 to 3 px and no drop shadow, on a clear canvas: the
tile draws its own panel. A unit carries one neutral grey (#9AA5B1, the palette's neutral) where
its sprite has team plates, and a building carries none: a build tile is not a team's.

**Tab and glyph icons** are drawn in the team layer greys, white #FFFFFF, shade #BFBFBF and edge
#4D4D4D, every colour R = G = B, and are tinted at run time with `modulate`, so the HUD says the
state with a palette colour and the shape says the rest. A thick stroke is two strokes, the edge
grey under and white over. Light is from the top left, with the shade on the lower right facets.
The tints the HUD gives them (the gallery's `GLYPH_TINTS` holds the same values):

| Glyph | Tint |
| --- | --- |
| tab, selected | none (white) |
| tab, at rest | #9AA5B1 |
| `glyph_credits` | #F2B705 |
| `glyph_power`, `glyph_check`, `glyph_victory` | #30A46C |
| `glyph_low_power`, `glyph_offline` | #F5A524 |
| `glyph_under_attack`, `glyph_cross`, `glyph_defeat`, every `glyph_reason_<reason>` | #E5484D |
| `glyph_lock`, `glyph_draw` | #9AA5B1 |

Sizes in dp (1 dp = 1.75 base px on the 6-inch phone): an item icon fills its 64 dp tile (ADR 0015
section 5 and ADR 0019 section 1), a tab icon 32 to 48 dp inside its 48 dp tab, a HUD glyph 24 to
48 dp, a glyph on the map 32 dp, and the under-attack arrow at least 48 dp. The gallery shows the
tabs at 48, the items at 64, the HUD glyphs at 48 and the map glyphs at 32 dp, and the arrow at 48.

| File | Silhouette |
| --- | --- |
| `tab_structures.svg` | A wide workshop from the front, a sawtooth roof of three teeth, a tall chimney on the right and a dark doorway. |
| `tab_infantry.svg` | A soldier from the chest up, a round helmet with a wide brim over a grey face, on sloping shoulders. |
| `tab_vehicles.svg` | A tank from the side, a long track pod with four grey wheels, a sloped hull, a boxy turret and one long barrel. |
| `item_power_plant.svg` | One big and one small round drum with dark open mouths, side by side over a low wide ribbed hall. |
| `item_refinery.svg` | One fat round silo and two small ones stepping off to the right above a wide hall, a gold-filled funnel jutting out of its front. |
| `item_barracks.svg` | A U of three long olive roofs round a bare metal yard that opens to the bottom, a dark door at its head. |
| `item_vehicle_factory.svg` | One wide hall whose roof is four bright stripes, a dark open bay under it with two orange arrows pointing out. |
| `item_defence_turret.svg` | A round gun pit ringed by eight fat sandbags, a round gun head with one thick barrel and a wide muzzle block leaving to the right. |
| `item_rifle_squad.svg` | Four soldiers in a loose diamond, each a broad oval with a grey helmet cover and a short stubby rifle to the right. |
| `item_rocket_squad.svg` | Two staggered soldiers, each with a long fat launch tube flared at the back and ending in an orange warhead: two parallel bars. |
| `item_light_tank.svg` | An H on its side: two long round-ended track pods, a flat deck, a compact turret and one long barrel. |
| `item_heavy_tank.svg` | A chamfered slab of two broad pods and a deep deck, a eight-sided turret, one thick barrel with a bulge and a cross-bar brake. |
| `item_artillery.svg` | A comb of six fat tyres round a long chassis, a wide spade across the back, a square open gun house, one very long thin barrel. |
| `item_harvester.svg` | Two long track pods either side of one big square open bin, a small cab, a toothed reel bar across the nose. |
| `glyph_credits.svg` | A short stack of three coins from the side, the top coin turned up as an ellipse with a second ring. |
| `glyph_power.svg` | One fat zigzag lightning bolt leaning right, flat on top and pointed at the foot. |
| `glyph_low_power.svg` | A rounded warning triangle, point up, with a dark lightning bolt in its middle. |
| `glyph_offline.svg` | A grey lightning bolt struck through by one thick white slash from top left to bottom right. |
| `glyph_under_attack.svg` | A fat block arrow pointing right with a stubby tail and a wide head carrying an exclamation mark. |
| `glyph_lock.svg` | A padlock: a wide rounded body with a keyhole under a tall rounded shackle. |
| `glyph_check.svg` | One bold check mark, a short stroke down to the left and a long stroke up to the right. |
| `glyph_cross.svg` | A bold X of two crossing strokes. |
| `glyph_reason_outside.svg` | An open square bracket, the map edge, with a fat arrow running out through its open side. |
| `glyph_reason_ground.svg` | Two jagged mountain peaks side by side on one base line, a small one in front of a tall one. |
| `glyph_reason_occupied.svg` | Two squares overlapping at a corner, a white one behind and a grey one in front. |
| `glyph_reason_unexplored.svg` | An almond eye with a round iris, crossed out by one thick slash from top right to bottom left. |
| `glyph_reason_too_far.svg` | A long fat arrow from a small square base that stops against a tall wall bar. |
| `glyph_reason_cap.svg` | A stack of three blocks pressed up under a wide ceiling bar with a down-pointing wedge at each end. |
| `glyph_victory.svg` | A fat five-pointed star, point up. |
| `glyph_defeat.svg` | A heater shield with a pointed foot, split by a dark zigzag crack. |
| `glyph_draw.svg` | A round disc with two level bars across it, an equals sign. |

Each meaning has its own shape (see "Shape as second cue"): the state of a tile is never the tint
alone. The glyphs of one group differ by silhouette, not by hue: the three tabs, the six placement
reasons, the three results.

Results (P92, scratch script, imported scale 0.5 and 0.25, alpha above 0.5): every tab and glyph
file has no non-grey pixel and no ink in the outer 1 px of its 64 px raster, and neither has an
item icon. At 64 px an item icon covers 32 to 77 % of the canvas and the mean luminance of its
ink is 72 to 110 against the HUD backdrop's 19 (a tab or glyph: 160 to 200). The icons were rasterised at 32 px
in greyscale over the HUD backdrop and compared pair by pair (mean absolute luminance difference,
0 to 255): the eleven item icons differ by 26 or more (the rifle and rocket squads are the
closest pair), the three tabs by 56, the six HUD glyphs and
three result emblems by 29 and the eight map glyphs by 43. At 32 px the eleven tile icons read apart by
silhouette and interior: drums, silos and a gold funnel, the U, the stripes over a bay, the sandbag
ring, four soldiers, two tubes, and the four vehicles by pods, turret and gun. A danger-tinted
glyph (luminance 120) is as bright as grass (110 and 127), so on the map its dark edge is what
separates it in greyscale, the way the marker outline does; the view may seat a map glyph on a dark
disc (#1C2127, the marker outline) if the phone check says it needs it.

## Rally flags
Each producing tab has a rally flag (ADR 0019 section 3). Two layers share one 128x128 canvas at
import scale 0.5, so 64 px in game, and the **foot of the pole is the canvas centre**: centre the
sprite on the point the player tapped.
- `flags/rally_<tab>_hull.svg`: the ground shadow, a foot plate, the pole and its finial.
- `flags/rally_<tab>_team.svg`: white and grey only, tinted with the owner's colour: the cloth and a
  ground marker round the foot, so it is read from above.
- The shape says which tab, not the colour: Infantry has a small triangular pennant over a **ring**
  on the ground, Vehicles a wide notched banner over a **square frame**.
- The line from the building to the flag is drawn in code (the marker stroke rule, ADR 0019
  section 3); it is not part of these files.

## Originality
Describe each silhouette in one line before drawing, in your own words. The catalogue below holds
the line for the unit and each SVG header holds the line for its layer. No recognisable designs
from other games, for example twin-barrel super-heavy tanks, tesla-coil towers or airships. When
in doubt, choose a plainer real-world form.

## Catalogue
| Unit | Silhouette | Layers |
| --- | --- | --- |
| Light tank | A plain light tank shaped like an H on its side: two long round-ended track pods joined by a short flat deck, a compact rounded-rear turret, and one long vented barrel leaving through the front bay. | `units/light_tank_{hull,team,turret}.svg`, 128x128 |
| Rifle squad | Four soldiers in a loose pinwheel diamond, each a broad-shouldered oval with a round helmet cover and a short stubby rifle held out to the right of the head. | `units/rifle_squad_{hull,team}.svg`, 64x64, no turret |
| Rocket squad | Two staggered soldiers, each carrying a long fat launch tube over the right shoulder, flared at the back and ending in a rounded orange warhead: the squad reads as two parallel bars. | `units/rocket_squad_{hull,team}.svg`, 64x64, no turret |
| Headquarters | A square pad with cut corners carrying a plus-shaped roof, a round dome where the four arms cross and a small square deck in each corner. | `buildings/headquarters_{hull,team}.svg`, 384x384 |
| Power plant | One big and one small round drum with dark open mouths over a low ribbed hall on the left and a tall yard of three boxes on the right, on a rounded square pad. | `buildings/power_plant_{hull,team}.svg`, 256x256 |
| Refinery | One fat round silo and two small ones stepping off to the right behind a wide hall, with a belt rising from a gold-filled funnel that juts out of the middle of the front. | `buildings/refinery_{hull,team}.svg`, 384x384 |
| Barracks | A U of three long olive pitched roofs round a bare yard that opens to the front, a raised metal spine along the ridge of all three, on a square pad. | `buildings/barracks_{hull,team}.svg`, 256x256 |
| Vehicle factory | One wide hall with a five-tooth sawtooth roof across the back, a dark doorway in its front wall and an open bay with two arrows pointing out, crates on the left and a round tank on the right. | `buildings/vehicle_factory_{hull,team}.svg`, 384x384 |
| Defence turret | A round gun pit ringed by eight fat sandbags, with a squat wedge-shaped gun head on top whose single long barrel ends in a wide muzzle block. | `buildings/defence_turret_{hull,team,turret}.svg`, 128x128 |
| Heavy tank | A squat armoured slab: two broad flat-sided track pods with chamfered fronts joined by a deep deck whose lit wedge nose pokes out ahead of them, a wide eight-sided turret with a boxy rear bustle, and one thick barrel with a fat fume bulge and a cross-bar muzzle brake. | `units/heavy_tank_{hull,team,turret}.svg`, 128x128 |
| Artillery | A long narrow wheeled carrier with three fat tyres a side, a short armoured cab at the front and a wide folded spade plate across the back that makes the rear a T, carrying a squarish open-topped gun house with a sloped front shield, a fat recoil sleeve and one very long thin barrel. | `units/artillery_{hull,team,turret}.svg`, 128x128 |
| Harvester | A combine-like ore hauler: two long round-ended track pods either side of one big square open bin, a small cab in front of it and a wide toothed reel bar across the nose. | `units/harvester_{hull,team}.svg`, 160x160, no turret |
| Infantry rally flag | A slim metal pole standing up from a round foot plate with a small triangular pennant, over a round ring on the ground. | `flags/rally_infantry_{hull,team}.svg`, 128x128 |
| Vehicles rally flag | A slim metal pole standing up from a square foot plate with a wide notched swallowtail banner, over a square frame on the ground. | `flags/rally_vehicles_{hull,team}.svg`, 128x128 |
| Tab, item and glyph icons | Three tab pictograms, eleven build tile icons and seventeen glyphs, one silhouette each. | `icons/<kind>_<name>.svg`, 128x128, import scale 1.0, see "Icons and glyphs" |
| Ore cell | A square of dirt, bare or holding three to six gold nuggets and crystals by level. | `ore/ore_<level>[a\|b].svg`, 128x128, see "Ore" |
| Ghost hatch | Bold diagonal bands rising to the right, a seamless tile. | `ui/ghost_hatch.svg`, 128x128, see "Ghosts" |
| Ghost dots | Small round dots in a staggered lattice, a seamless tile. | `ui/ghost_seen.svg`, 128x128, see "Ghosts" |

## Readability check (every asset)
1. Rasterise each layer at 32 px with `Image.load_svg_from_buffer` (scale = 32 / canvas, so 0.25 for
   a 128 px canvas) in a scratch script. Do not commit the script or the PNGs.
   ```gdscript
   var img: Image = Image.new()
   var err: Error = img.load_svg_from_buffer(FileAccess.get_file_as_bytes(path), 0.25)
   ```
2. Composite hull, tinted team layer and turret on grass #6F8F57 and on sand #CDB98F, then convert to
   greyscale and look at it enlarged (nearest neighbour, 6x).
3. Pass when all three hold:
   - The vehicle type and its heading are identifiable in the grey composite on both grounds.
   - In the pure silhouette (every opaque layer as one black shape) the gun sticks out of the body
     as its own shape, at least 3 px long and 3 px thick.
   - The visible team share is 20-35% at turret headings 0, 90, 180 and 270 degrees.

Light tank result (v1): visible team share 28.6 / 24.5 / 25.6 / 24.5 % at 0 / 90 / 180 / 270
degrees (team alpha not covered by the turret, divided by the alpha of the whole vehicle without
its shadow, both summed over the 128 px raster); the team layer has no non-grey pixel; the gun
sticks out 4 px by 4 px in the 32 px silhouette; at 32 px greyscale the tracks, deck, turret and
gun read as separate parts on grass and sand. Detail check at 2x (raster scale 1.0): the muzzle
face keeps 3 px of metal on each side of its 2 px vent, and one full row of the upper pod
highlight stays visible beside the team plate.

Squad results (v1, scratch script, scale 0.5, alpha above 0.5): the team layers have no non-grey
pixel. The visible team share, by the tank's definition (shadow left out, no turret, so every
heading gives the same value), is 26.6 % (rifle) and 25.1 % (rocket) at 32 px, 26.3 and 25.3 % at
2x. In the pure silhouette (hull and team as one shape) the rifle squad is four separate lollipops,
each with a rifle 5-6 px long and 4 px thick sticking out of the body, and the rocket squad two
separate bars with a 13-14x6 px tube each. The two silhouettes overlap by 0.27 (intersection over
union, same canvas). Composited on grass and sand in greyscale at headings 0, 90, 180 and 270
degrees, the pinwheel and the two bars stay apart and the heading reads. Detail check at 2x: 2 px
of metal between the rifle outlines, 1.9 units (1 px at 32 px) between each rifle tip and the next
soldier, and on each helmet cover a full 1.5 px edge with a 2.0 px grey shade, both at the minimum.

Building results (P91, scratch script, imported scale 0.5, alpha above 0.5): the six team layers
have no non-grey pixel. The visible team share, by the tank's definition (shadow left out, nothing
under the gun head), is 24.8 % (headquarters), 22.6 % (power plant), 22.7 % (refinery), 24.2 %
(barracks), 23.2 % (vehicle factory) and 26.0 % (defence turret, the same at 0, 90, 180 and 270
degrees). The silhouette of each was drawn at 32 px for its longest side, in greyscale on grass and
sand, and at 48 px per tile (the camera's 0.75 zoom). At 32 px the six read apart: the cut-corner
cross with its dome, the two drums beside a yard of three boxes, the three silos over a bright gold
funnel, the U, the five roof stripes over a dark bay, and the ring with a gun. In the pure
silhouette the defence turret's gun is its own shape: the muzzle block leaves the pit 4 px by 6 px
at 32 px (7 by 12 at 64). Both ground tones keep every building apart because of the outline (32)
and the pad, which is darker (100) than the grass (110 and 127) and the sand (186) under it. The
ore tiles at 32 px per tile in greyscale read by nugget count and size (see "Ore").

## Feedback markers (new)
The target flash, the attack-move marker, the long-press anchor and the box are drawn in code
(`_draw` or `Line2D`), not as SVG. They stay crisp at every zoom and are sized in dp (ADR 0004
section 7). The SVG technical rules do not apply to them, the palette does. The selection ring is
the exception (ADR 0011 section 3): one SVG texture, `ui/selection_ring.svg`, on a `Sprite2D` that
scales its baked stroke with the ring. touch-ux-dev builds the markers in P16 and the ring sprite in
P40, and pins the numbers below in tests.

Conventions:
- **dp** is `UiScale.dp(v)`, base px on screen. In world space (under `RtsCamera`) divide by the
  camera zoom, so a dp size looks the same at 0.75, 1.0 and 1.5. `MoveMarkerLayer` has no camera
  export, so it reads the zoom as `get_canvas_transform().get_scale().x`. **World px** (1 tile = 64)
  scale with the zoom, like the sprites.
- **Stroke**: two passes on one centre line, round caps and joins, antialiased. First the outline
  pass in #1C2127 at width + 2 dp, then the colour pass. 1 dp of dark shows on each side. That
  separates every colour from grass (luminance 127) and sand (186).
- **Fade**: full alpha until min(200 ms, `marker_ms` / 3), then linear to 0 at `marker_ms` (600),
  so a shorter `marker_ms` never makes the fade interval empty. Fade the outline pass and the
  colour pass as one group (a `CanvasGroup` per marker, or outline alpha a^2 under colour alpha a),
  because Godot blends each draw pass on its own and two plain alphas turn the marker dark mid-fade.
  **Ease** is ease-out quad, e(t) = 1 - (1 - t)^2.
- Alpha is 1.0 unless a row says so. Markers have no shadow and make no sound.

| Marker | Shape and size | Stroke | Colour | Motion | Drawn where |
| --- | --- | --- | --- | --- | --- |
| Own selection ring | Circle at the unit position, radius R = max((selection_radius / 1000 + 0.05) x 64 world px, 18 dp). Light tank: 35.2 world px, so 31.5 / 35.2 / 52.8 base px on screen at zoom 0.75 / 1.0 / 1.5 on the 6-inch phone profile (1 dp = 1.75 base px) | Baked, centre line on R: white R/6 with a dark outline of R/18 on each side, so 1 + 3 + 1 dp when R is its 18 dp minimum and 1.7 + 5.0 + 1.7 dp at 52.8 px | #FFFFFF on #1C2127 | None. Shown in the frame of the tap | World space, `Sprite2D` `Ring`, first child of the unit rig, z 1, `scale = R / RING_TEX_RADIUS_PX` |
| Enemy target flash | Diamond (a square turned 45 degrees), corners 45.8 world px from the enemy position (1.3 x the light tank's R of 35.2). `show_target(world_px)` carries only the position and Phase 1 has one unit type, so this is one view constant of the layer, not read from unit data | 3 dp | #E5484D | Starts at 1.5 x size, reaches 1.0 x in 150 ms (ease), then fades | World space, `MarkerLayer`, above the units |
| Attack-move marker | Four chevrons around the tapped point (the origin), pointing at it. The east one is the open polyline (d + 7, -7), (d, 0), (d + 7, 7) dp, so its tip faces the point. The south, west and north ones are the same turned by 90, 180 and 270 degrees. d = 12 dp at rest | 3 dp | #F5A524 | d goes from 36 dp to 12 dp in 200 ms (ease), then fades | World space, `MarkerLayer`. A dp size, so it does not grow with the zoom |
| Long-press anchor | Ring at the press point, radius 32 dp (diameter 64 dp, about 10 mm). Fill #FFFFFF at 15% | 3 dp | #FFFFFF | Radius 48 dp to 32 dp in 150 ms (ease), then it stays until the box ends or cancels | Screen space, `BoxOverlay`, drawn before the box |
| Selection box | The normalised drag rect. The centre line is the rect inset by 1 dp, so the outer edge of the white is the rect edge. Fill #FFFFFF at 15% | 2 dp | #FFFFFF | None | Screen space, `BoxOverlay` |

`RING_TEX_RADIUS_PX = 72`: the texture's centre-line radius in imported px (168x168 canvas, import
scale 1.0, because the ring is drawn at any scale and keeps its 2x raster). The white band is 12 px,
the outline 4 px each side, the outer radius 82.

Draw order, bottom to top (z, ADR 0012 section 6): ground 0, rings 1, every hull 10-19, every team
layer 20-99, every turret 100-109, health bars 110, projectiles 120, effects 130, fog 140, then flash
and chevrons 150, then the HUD layer with the anchor and the box. A fill is drawn before its outline
pass.

Checked in a scratch render at 1.75 base px per dp on grass #6F8F57 and sand #CDB98F, in colour and
in greyscale: all five read apart by shape on both grounds, and the dark outline keeps the red
diamond (luminance 120, grass 127) and the chevrons (174, sand 186) readable. Look again once P16
draws them on the phone.

Ring check (P34b): in a scratch render at 1.75 base px per dp the ring around the light tank at zoom
0.75 / 1.0 / 1.5 measures 3.00 / 3.35 / 5.03 dp of white with 1.00 / 1.12 / 1.68 dp of dark on each
side. In greyscale on grass and sand it reads at all three zooms as a closed white circle around a
unit. At zoom 1.5 its outer radius equals the long-press anchor's (60 base px): the ring's band is
5 dp against 3 dp, and the anchor has the 15 % fill and shrinks in.

### Shape as second cue
- Colour is never the only cue (`touch-ui-rules`). Each meaning has its own shape: own selection is
  a closed circle around a unit, an enemy target is a closed diamond, attack-move is four open
  chevrons closing in, the box is a rectangle, and the long-press anchor is the only lightly filled
  ring and the only ring that shrinks in. A press on a unit puts the anchor on that unit, and on a
  desktop or tablet profile a unit ring can be as large as the anchor. Fill and motion tell the two
  apart there, not size.
- Test for every new marker: look at it in greyscale at the size the player sees. The marker
  colours have luminance white 255, warning 174, danger 120, outline 32. If two markers cannot be
  told apart by shape, size or motion alone, change the shape, not the hue.
- The sprites of team A and team B differ by hue only (luminance 116 and 120). In Phase 1 the markers
  carry the second cue: only own units get a ring, and a targeted enemy gets the diamond. Anything
  later that must tell the teams apart in a crowd (health bars, minimap dots) needs a shape
  difference.

### Enemy target look
No new SVG. An enemy is the light tank (`units/light_tank_{hull,team,turret}.svg`) with its `Team`
layer modulated #E5484D (team B). Hull and turret keep their olive and metal. The sand half of the
gallery's zoom row shows it at 0.75, 1.0 and 1.5. Phase 1 targets stand still, so they need no other
cue.

## Combat effects (new)
Five sprites share one sheet, `fx/effects_atlas.svg` (352x168 at 2x, import scale 0.5, so 176x84 px).
Quads are drawn in one `_draw()` per layer from these regions (x, y, w, h in px of the imported
texture), each sprite at the centre of its region, facing east, with `modulate` Color(1, 1, 1, alpha).
The colours are baked in, all palette colours and none a team colour: burst #F5A524, #FFD84D, #FFFFFF;
puff #7D8893, #A9B4BE with a #F5A524, #FFD84D core; shell #F2B705, #FFD84D; rocket #A9B4BE, #5B6670
with #F5A524, #FFD84D; outlines #1C2127. A layer turns shell and rocket by the flight direction and
leaves the others unturned. Sizes are world px (they scale with the zoom), times run on the frame
clock. Thin parts (flash points, flame) have a 2 px outline (new), fins 1.5 px, the rest 3 px (at 2x).
`PUFF` holds the largest puff (56), so the smaller ones scale it down and none is stretched.

Every rule keys on a snapshot column (ADR 0012 section 3). A weapon is `weapon_ids[i]` for the weapon
index `i` of the event or slot (`tank_cannon`, `rocket`, `rifle`); hitscan is `weapon_projectile_speed[i]
== 0`. A type is infantry when `type_armour[type_index] == World.Armour.INFANTRY`; any other armour
(light, heavy, building) is a vehicle. ADR 0011 section 1 and ADR 0012 section 3 list neither
`weapon_ids` nor `type_armour`, so an addendum must add both to the view's read list and to
`MatchSnapshot.COPIED` before P44 and P45 can follow this spec.

| Effect | Trigger | Region | Size (world px) | Motion and lifetime | Layer |
| --- | --- | --- | --- | --- | --- |
| Shell | live slot (`proj_weapon`) of a weapon other than `rocket` | `SHELL` 84,60,16,8 | 16x8 | At the interpolated position, turned along `prev_proj` to the position, for as long as the slot lives. A new slot (its `proj_id` differs from `prev_proj_id`) has no heading: it is not drawn until it has moved, one tick (67 ms), which the muzzle flash covers | Projectiles, z 120 |
| Rocket | live slot of the weapon `rocket` | `ROCKET` 84,72,36,12 | 36x12 | As the shell; the quad centre is the body centre, the flame trails behind it | z 120 |
| Muzzle flash | `SHOT` | `FLASH` 144,0,32,32 | 32 (`tank_cannon`), 24 (`rocket`), 16 (`rifle`) | At the muzzle point: the shooter's position plus 31 px (`tank_cannon`) or 13 px (`rocket`, `rifle`) towards the event's target position. Alpha 1 until 40 ms, then linear to 0 at 100 ms | Effects, z 130 |
| Tracer | `SHOT` of a hitscan weapon (the rifle) | none, a line | #FFD84D 1.5 dp over #1C2127 3.5 dp (the marker stroke rule) | From the muzzle point to the event's target position. Alpha a from 1 to 0 over 120 ms: outline pass at a squared, colour pass at a (the marker fade rule) | z 130 |
| Impact puff | `IMPACT` (projectiles only) | `PUFF` 84,0,56,56 | 40 (`tank_cannon`), 56 (`rocket`) | At the event position, 0.6x growing to 1.0x. Alpha 1 until 150 ms, then linear to 0 at 350 ms | z 130 |
| Vehicle death | `DIED` of a type that is not infantry | `BURST` 0,0,80,80 | 80 | At the event position, 0.5x to 1.0x in 150 ms (ease-out). Alpha 1 until 350 ms, then linear to 0 at 600 ms | z 130 |
| Infantry death | `DIED` of an infantry type | `PUFF` | 24, no growth | At the event position, alpha 0.7 linear to 0 over 700 ms | z 130 |

The regions have 4 px of clear space between them and no ink outside (the rocket's ends at the
sheet's edge). On grass and sand, in colour and in greyscale, all five read apart by shape at zoom
0.75 / 1.0 / 1.5; the dark outline keeps the shell body (luminance 180, sand 186) and the cloud (134,
grass 127) readable.

## Health bars (new)
Bars are filled rects only, drawn in one `_draw()` (ADR 0011 section 3), sized in dp so they look the
same at every zoom. Sizes are outer boxes in dp, in rects of 1 dp, origin at the top-left corner. The
class is the one under Combat effects (infantry when `type_armour` is INFANTRY).

| Class | Width W | Height | Reach r (world px) | Edge and empty part | Fill |
| --- | --- | --- | --- | --- | --- |
| Own, vehicle | 22 | 6 | 26 | #1C2127, 1 dp round the 4 dp interior | #30A46C (ok), luminance 123 |
| Own, infantry | 16 | 6 | 14 | as above | as above |
| Enemy | as the class of the unit | 6 | as the class | as above | #F5A524 (warning), luminance 174 |

Half-heights, for the overlap check only: P45's overlap test (see Overlap below) takes the vertical
half-height h of a unit as 14 world px for squads and 21 for tanks. The layer never reads h, it places
a bar by r.

Neither fill is a team colour, so a red or blue unit keeps its bar colour. Own bars are plain
rects, enemy bars are notched (Michael's answer 3, see Open points):
- Own: edge (0,0,W,6), fill (1,1,W-2,4).
- Enemy, with a = (W - 4) / 2 (9 for 22, 6 for 16): edge rects (0,0,a,6), (a+4,0,a,6) and
  (a,2,4,4), which leave an open notch 4 dp wide and 2 dp deep in the top edge, outlined all
  round; fill rects (1,1,a-2,2), (a+5,1,a-2,2) and (1,3,W-2,2), a shoulder on each side of the
  notch over one continuous strip.
- Fill length: x_end = 1 + max(1, round((W - 2) x hp / max_hp)) while hp > 0, so a living unit
  always shows 1 dp of fill. Every fill rect is clipped to x < x_end, so a bar fills from the left.
- The bar is centred on the unit, its bottom edge 1 dp above the sprite: r x zoom + 1 dp above the
  unit's position on screen, r the class's reach in world px. The light tank hull is 21 high facing
  east and 29 long, so 26 sits between; a rifle squad is 14 high and a rocket squad 12 to 13. The
  ring does not set it: its 18 dp floor put each bar on the unit above in a formation. The bar may
  cover the unit's own barrel or the inner edge of its ring (z 110 is above both).
- Density: a bar shows for a unit that is selected (at any hp) or was hit within the last 3000 ms
  (frame clock, `hit_time_ms`). No bar otherwise, and none for a unit the fog hides.

Overlap (P34b, scratch render and sweep): each class at its own formation spacing, 900 milli for squads
and 1200 milli for tanks and mixed groups (a group spaces by its largest `type_spacing`, so tanks
never form at 900), at zoom 0.75 / 1.0 / 1.5 and 1.0 to 2.37 base px per dp.
- Side by side, at zoom 0.75 on web_phone_small (2.37 px per dp, the widest ratio) the spacing is 18.2
  dp (squads) and 24.3 dp (tanks), so 16 and 22 dp bars leave 2.2 and 2.3 dp; 8.7 and 10.9 dp on the
  6-inch phone.
- Above each other, a bar's top is r x zoom + 7 dp over its unit and the unit above starts (spacing -
  h) x zoom over it, h the half-height above (14 squads, 21 tanks): at worst 5.6 px clear. The bar's
  middle is nearer its own unit than the unit above, except for tanks at zoom 0.75 on web_phone_small,
  where it is midway.
- Notch: 3x3 formations of squads, of tanks and of a mixed group, every unit hit, at headings 0 to 315
  degrees in 45 degree steps and with the turret aligned or pointing down. On the 6-inch phone (1.75
  px per dp) no sprite covers a notch at any zoom, and squads are clean on every profile. Residual:
  on web_phone_small at zoom 0.75 the barrel of the tank above pointing down, or its hull corner at
  225 or 315 degrees, covers up to 53 % of a notch (25 % averaged over the headings; 4 % at most on
  web_phone). On desktop and tablet (1.0 and 1.25 px per dp) at zoom 1.5, and desktop at zoom 1.0, a
  tank aimed north puts its own barrel through its notch, and its hull corner does at 45 or 135
  degrees. The fill still shows the notch as a 6 dp gap in its top row.
P45's test pins the first two inequalities (squads at 900, tanks at 1200), not only the side-by-side gap.

Mixed group check (P34b): a scratch render at 1.75 base px per dp of blue tanks and squads, ringed, with
plain bars, beside red ones with notched bars, in a 1200-milli formation at zoom 0.75, 1.0 and 1.5 on
grass and sand. In greyscale own bars read as plain rectangles and enemy bars as rectangles with a bite
out of the top edge, at every zoom and for both classes, so the notch alone tells them apart (the fill
luminance, 123 against 174, is a second cue).

## Fog and terrain
`MapView` bakes the map once per match and per `map_version` (a terrain change) into one texture at
8 px per tile (ADR 0011 section 3) and draws it with `texture_filter` NEAREST, so a texel is 8x8
world px. The colours are `MapView.colors` keys: a terrain id of `data/terrain/standard.tres`, and
`<id>_b` and `<id>_c` for the second and third tone of its tile (for grass `_b` is the tile parity,
elsewhere a pattern tone). Probe is a texel (x, y) that shows the key's colour, for tests to read;
the tile centre would show the scrub's highlight, so it is named per key:

| Key | Colour | Where | Probe |
| --- | --- | --- | --- |
| `grass` | #5E7D4A | tiles with x + y even (the Phase 1 checkerboard) | 3,3 |
| `grass_b` | #6F8F57 | tiles with x + y odd | 3,3 |
| `sand` | #CDB98F | the whole tile | 3,3 |
| `scrub` | #4E5A3A | base | 6,2 |
| `scrub_b` | #6B7A4F | bush | 2,2 |
| `scrub_c` | #8C9A6B | highlight | 4,4 |
| `rock` | #6E6A66 | base | 3,3 |
| `rock_b` | #8C8782 | lit edge, top and left (new) | 3,0 |
| `rock_c` | #4F4B48 | shade edge, bottom and right (new) | 7,3 |
| `water` | #2E5E7E | base | 3,3 |
| `water_b` | #3C7396 | ripple | 2,2 |

A tile is 8x8 texels of filled rects `x,y,w,h,key`, in drawing order. The first rect is the base,
the whole tile, and the other rects are drawn over it:

| Terrain id | Rects |
| --- | --- |
| `grass` | `0,0,8,8,grass`, and `0,0,8,8,grass_b` on odd tiles |
| `sand` | `0,0,8,8,sand` |
| `scrub` | `0,0,8,8,scrub 1,1,3,3,scrub_b 4,4,3,3,scrub_b 1,1,1,1,scrub_c 4,4,1,1,scrub_c` |
| `rock` | `0,0,8,8,rock 0,0,8,1,rock_b 0,0,1,8,rock_b 0,7,8,1,rock_c 7,0,1,8,rock_c` |
| `water` | `0,0,8,8,water 1,2,4,1,water_b 4,6,4,1,water_b` |

There is no grid (Michael, 2026-10-12): no band, no line and nothing darkened on row 0 or column 0
of a tile, on any terrain. `MapView` (P36) bakes no grid. Fog is black on a texture of one texel per
tile, linear filtered, so its edge is soft across one tile (ADR 0010 section 2): alpha 255 where
unexplored, 140 where explored but not visible, 0 where visible. `FogLayer.explored_alpha` and the
gallery's `explored_fog_alpha` are 140. The gallery's `TERRAIN_COLORS` and `TERRAIN_TILES`
(`art_gallery.gd`) hold these keys and strings, which `tests/art` pins to this text and to every
texel; `MapView` keeps its own copy and P52 compares the two.

Greyscale check (P34c, the tiles' own texels, Rec. 601 luminance of the 8-bit colours; mean and
spread (standard deviation) inside one tile): grass 110 and 127 (spread 0), sand 186 (0), scrub 92
(15.9), rock 105 (19.9), water 86 (6.4). Grass and sand are flat. Scrub is 18 and 35 below the grass
tones (its base alone, 83, is 27 and 44 below) and has a spread of 15.9 where grass has none, so the
dotted bushes read apart from grass in greyscale, as a darker patch with a texture. Rock's mean is
just under the darker grass, so its bevel carries it: the lit edge (136) is lighter than any grass
texel (127 at most) and the shade edge (76) darker than any (110 at least). Under the explored fog
(x 0.45) the means are grass 50 and 57, sand 84, scrub 42, rock 48, water 39, all dark, with the
patterns of scrub, rock and water still visible.

Squads on scrub (P34c, a one-off measurement in greyscale): scrub has the unit olive and only foot
units can stand on it. Method: both squads in both team colours, laid out as the gallery's terrain
row draws them (the rifle squad 16 px and the rocket squad 48 px across a 64 px tile, both 32 px
down, hull then the tinted team layer, bilinear), over the ground with nearest filtering (an 8 px
texel; flat colours for the two grass tones and for sand), at zoom 1.0 and 0.75, turning through 12
headings 30 degrees apart. A squad pixel is one with alpha 0.5 or more, and the figure is the Rec.
601 luminance of what is shown there against the ground under it. Over the 8 variants of squad,
team and zoom, the mean luminance difference is 37 to 44 on scrub (48 to 51 on the darker grass, 62
to 65 on the lighter, 114 to 119 on sand), and at most 15 % of the squad's pixels are within 12 of
the ground (9 % on the darker grass, 6 % on the lighter, 1 % on sand). Scrub has the least contrast
of the four grounds, lower than on either grass tone, and the dark outline and team colour carry the
squads there. The figures move by about 1 with the number of headings, and no test pins them.

## Gallery
`scenes/dev/art_gallery.tscn` (opened from the dev menu, also in the web preview) shows every asset
at scale 1 (gameplay zoom) on grass and sand, in team A and team B. A faint 64 px square behind each
tank marks one tile. Turrets turn slowly. The zoom row at the bottom shows the light tank at rig
scale 0.75, 1.0 and 1.5, the camera zoom levels of `data/input_settings.tres`: team A on grass,
team B on sand, labelled on the grass half. On a 6-inch phone (stretch 1.5) zoom 1.5 draws one
tile as 144 window px from a 64 px raster, 2.25 times. Only the light tank has that zoom row; a
second row above it, built by `art_gallery.gd`, shows both squads (team A on grass, B on sand) in
the same three columns, and in each slot the squads stand beside the tank and turn slowly. The
squads are built in code, without a tile square: a unit with no turret can join the `_squad_pair`
list in `art_gallery.gd` instead of getting rigs in the scene. A ring row (also built by the
script) shows team A's tank with its ring on both grounds (only own units get one) at the three zoom
levels, at the ring radius of the 6-inch phone, and each ground carries the effects atlas at scale 1.
A terrain row at the top shows a patch of 8 x 2 map tiles at 64 px in a dark frame, so every tile
edge shows on both grounds: grass, scrub, rock, water and sand. Team A's and team B's
squads stand on the two scrub tiles, and the second row of the patch is under the explored fog alpha.
A button at the top right (120x120 base px, labelled with the page it is on) turns the pages: **Units**
(everything above), **Build**, **Ground**, **Vehicles** and **Icons**, and the Back button leaves
from any of them. The new pages are built by `art_gallery.gd` and start hidden, so the Units page is
as it was.
- **Build** shows the six buildings at scale 1 on grass (left) and sand (right). Each ground has four
  rows: the small ones first (power plant, barracks, defence turret), team A then team B, then the
  3x3 ones (headquarters, refinery, vehicle factory), team A then team B. Every building is a rig
  `Node2D` named by its id in PascalCase, with `Hull`, `Team` and, for the turret, `Turret`, in the
  team group; the turret's gun head turns slowly like the tanks'. The rows are centred and the
  layout is made for landscape (the Units page is too).
- **Ground** shows, on each ground, the ore levels (five tiles by two variants, side by side with
  no gap), a mixed ore field of 6 x 3 tiles to judge the joins, the three ghosts of a barracks (fits,
  does not fit, last seen) and the two pattern tiles repeated three by two times.
- **Vehicles** shows the light tank for scale beside the heavy tank, the artillery and the
  harvester at scale 1, a row for team A and a row for team B on each ground, each on a faint tile
  square with its name below. Every unit is a rig `Node2D` named by its id in PascalCase with
  `Hull`, `Team` and `Turret` where it has one, in the team group. The turrets turn slowly; the
  harvester has none, so its whole rig turns, as a squad's does.
- **Icons** has two halves. The left half is the HUD's dark panel (#0F141C, here opaque): the three
  tab icons at 48 dp, the eleven item icons on their tiles at 64 dp (four to a line), the six HUD
  glyphs and the three result emblems at 48 dp, each tinted as the HUD tints it (see "Icons and
  glyphs"). The right half is grass above and sand below, each with the seven map glyphs at 32 dp,
  the under-attack arrow at 48 dp and the two rally flags in team A and team B at scale 1. Every
  icon is a `TextureRect` named by its file in PascalCase (`TabInfantry`, `ItemHeavyTank`,
  `GlyphReasonTooFar`); a flag is a rig `Node2D` (`RallyInfantryA`) with `Hull` and `Team`. All of it
  sits clear of the two corner buttons, which cover 24 to 144 px from the top and the left or right.

To add an asset:
- Add its layers as one rig `Node2D` under each of the four slots (grass A, grass B, sand A, sand B).
- Put the rig in the group `gallery_team_a` or `gallery_team_b`, and name the layers `Hull`, `Team`
  and `Turret` (a unit without a turret leaves `Turret` out).
- The script `game/view/art_gallery.gd` tints `Team` and turns `Turret`. The team colours are exported
  properties of the scene root.
- An icon goes on the Icons page: add its file name to the list of its kind in `art_gallery.gd`
  (`TAB_ICONS`, `ITEM_ICONS`, `HUD_GLYPHS`, `EMBLEMS`, `MAP_GLYPHS`) and, if the HUD tints it, to
  `GLYPH_TINTS`.
- The Back button (120x120 base px, top-left) and the Android back request both return to the dev
  menu. While the gallery is open the script switches `SceneTree.quit_on_go_back` off (its default
  is on, which would quit the app) and restores it on exit.

## Reskin
Michael, 2026-10-15: the game's look must stay replaceable as a whole without touching game rules
(plan `docs/plans/2026-10-11-phase-2.md`, "Answers and follow-ups (P26t docs)"). A new look is
made in three places, and the palette table above is the source for all three: change the
palette first, then the three places from it.
1. **Units**: the SVG layers in `assets/art/svg/units/`, found by name: `<type>_hull.svg`,
   `<type>_team.svg` and `<type>_turret.svg` (`UnitLayer.ART_DIR`). Replace a unit's files under
   the same names and keep the layer contract above.
2. **Terrain**: the `colors` and `tiles` exports of `game/view/MapView.gd`, with the gallery's
   copies and the "Fog and terrain" section above.
3. **UI**: the central Theme of plan row P58, `game/ui/theme.tres`. It holds the HUD's font
   sizes, the selection panel's backdrop (palette row "HUD panel backdrop") and the colours of the
   selection box and anchor. The text and button colours, the Button StyleBoxes and the HUD font
   are the engine's defaults and are not in the file: a restyle adds them there
   (`Label/colors/font_color`, `Button/styles/normal`, a Font) with no code change, and gives the
   neutrals a palette row then. The file is written in dp, and `game/ui/HudTheme.gd` is the dp
   step: on a resize it gives the HUD roots a copy in px, scaling every font size and every
   StyleBox size (content margins, corner radii, border widths, expand margins, shadows, a line's
   thickness) but not a StyleBoxTexture's texture margins or the theme's constants (add one to
   `HudTheme.scaled()` before using it). An entry that stays in base px is listed in the file's
   `metadata/base_px`. The selection box and anchor take their fill and dark pass from the theme,
   and the world-space move markers from `FeedbackStyle` in `game/view`: they share one fill and
   one dark pass, so a new palette changes both places. A new font goes under `assets/art/fonts/`,
   with a row in `assets/CREDITS.md` (author, source URL, licence) and its licence text in the
   Licences screen, and is referenced only from the theme.

Besides the three places, the same new look also replaces, in the same PR:
- **The art without a naming convention**, in place. The selection ring
  (`ui/selection_ring.svg`) is the layer contract's exception: it keeps its 168 px canvas, import
  scale 1.0 and the 72 px centre-line radius, or `UnitLayer.RING_TEX_RADIUS_PX`, the gallery's
  copy and the art test change with it. The effects atlas (`fx/effects_atlas.svg`, colours baked
  in) keeps its 176x84 px size and the region table under "Combat effects", or the projectile
  and effects layers' constants, the art test's `REGIONS` and that table change with it. The icons
  (`icons/<kind>_<name>.svg`, found by name: `item_<type_id>`, `glyph_reason_<reason>`) and the
  rally flags (`flags/rally_<tab>_{hull,team}.svg`) are replaced under the same names, keeping the
  128 px canvas, import scale 1.0 for icons and 0.5 for flags, the grey contract of the glyphs and
  the tint table under "Icons and glyphs", whose copy is the gallery's `GLYPH_TINTS`.
- **The palette colours kept in `game/view`** as constants or exports: the team tints
  (`UnitLayer.team_colors`), the feedback markers (`FeedbackStyle`, `MoveMarkerLayer`), and from
  their PRs on the health bar, tracer and fog colours ("Health bars", "Combat effects", "Fog and
  terrain"). The gallery's copies follow them: `art_gallery.gd`'s team colours and
  `TERRAIN_COLORS`, and the `Grass` and `Sand` rects of `scenes/dev/art_gallery.tscn`.
- **The tests that pin today's palette**: `tests/art/test_art_assets.gd` (`ATLAS_COLOURS`,
  `REGIONS`, `SIDE_PX`, the ring, the terrain pictures), `tests/art/test_vehicle_art.gd`,
  `tests/art/test_icon_art.gd` and `tests/view/test_feedback.gd`.

Renaming a unit or a unit type is a data change, not a reskin.

## Open points for Michael
- Approve the **(new)** rules: team-layer greys, elevation reads as lightness, rotating layers carry
  no shadow and no one-sided light, the reading of "1.5 px vs 2 px", the feedback marker spec
  (shapes, dp sizes, colours, outline, fade), the combat effect spec (sizes, lifetimes, the 2 px
  outline on thin parts) and the health bar spec (sizes, notched enemy bar, placement, density).
- The rocket warhead is #F5A524, the UI warning accent, used in unit art. Decided by Michael on
  2026-10-12: kept. The attack-move chevrons, the enemy health bar fill and four of the five effect
  sprites (burst, flash, puff core, rocket nose and flame) use it too. The measured reason: an own
  rocket squad's warhead is about 6 px of the enemy-bar colour at zoom 1.0 on the 6-inch phone,
  beside 411 px of enemy bar, at the same luminance (174), and the notch stays the own/enemy cue.
- Please judge on the phone (Dev, Art gallery, bottom row) whether zoom 1.5 looks too soft. The
  tile is a 64 px raster drawn at 2.25 times on a 6-inch phone. The fix would be SVG import scale
  1.0 with mipmaps and sprites drawn at scale 0.5. That changes the Technical rules here, so it
  needs your approval. It is not part of P12 (plan open question 4).
- The red target diamond has almost the same luminance as grass (120 against 127). Only its dark
  outline separates them. Judge it on the phone once P16 draws it.
- Team A and team B differ only in hue in the unit art. Decided for Phase 2 (Michael, answer 3,
  2026-10-12): the cue is the notched enemy health bar. It shows only while an enemy bar shows (the
  enemy was just hit), so in a calm moment colour is the only cue. There is no always-on marker. Phase 5
  polish revisits this if playtesters have trouble telling the sides apart, for example with an
  always-on marker or a second team stripe shape.
- The selection ring is imported at scale 1.0, not 0.5 (see `RING_TEX_RADIUS_PX = 72` under the
  marker table), so it stays sharp at zoom 1.5. This is an exception to the half-scale rule for one
  asset.
- Terrain (gallery, top row). Decided by Michael on 2026-10-12: the map has no grid. A tile is its
  base colour and its pattern rects, and `MapView` (P36) bakes no grid. Still open: the rock lit and
  shade colours are new, and scrub shares the unit olive, so judge the squads on it in the patch.
  The explored fog (alpha 140) leaves terrain at 45 % brightness: check that explored ground stays
  readable; it is one value (`FogLayer.explored_alpha`) to change.
- P91 (Phase 3), please approve the **(new)** items and judge them on the phone (Dev, Art gallery,
  button at the top right: Build, then Ground):
  - the two dirt tones #6F583B and #A3865E beside the palette's dirt colour;
  - the building layers, named like the unit layers (`hull` is the body of the building) and sized one
    tile per footprint tile, with team marks that are large roof plates and rings (a team share of
    20-35 % of the visible body, 22.6 to 26.0 % measured);
  - that the dock of the refinery and the exit of the factory are the middle cell south of the
    footprint, where the art draws the funnel and the bay;
  - opaque ore tiles with five levels, the level formula under "Ore" and two layouts per level;
  - the ghost look under "Ghosts": its two pattern tiles, the alphas and the colours;
  - the Build and Ground gallery pages.
- P92 (Phase 3), please approve the **(new)** items and judge them on the phone (Dev, Art gallery,
  button at the top right: Vehicles, then Icons):
  - the silhouettes of the heavy tank, the artillery (wheeled, with a spade) and the harvester
    (a combine with a toothed reel bar), and their team marks (a share of 20-35 % of the visible
    body, 22.8 to 30.0 % measured);
  - the harvester's empty bin, a 29x24 px rectangle that the cargo cue of P84b fills;
  - **icons and glyphs at 128 px with import scale 1.0**, an exception to the half-scale rule for UI
    art, like the selection ring;
  - the glyph contract (white, #BFBFBF and #4D4D4D greys, tinted by the HUD from the palette, the
    tint table under "Icons and glyphs") and the neutral grey team mark on a unit's item icon;
  - the two rally flags, a ring with a pennant for Infantry and a square frame with a notched banner
    for Vehicles;
  - the naming contract `item_<type_id>`, `tab_<tab>` and `glyph_reason_<reason>` that the sidebar
    and the placement view find the icons by, and `glyph_reason_occupied` for a pending ghost that
    turns "Blocked";
  - the Vehicles and Icons gallery pages.
- For touch-ux-dev (requests from P92): the HUD finds each icon by name as above and tints it with
  `modulate`; `UnitLayer` and the selection panel already skip a missing `turret` layer (the squads
  have none), which the harvester relies on too. A danger-tinted glyph is as bright as grass, so on the map it
  is its dark edge that separates it: look at it in the phone check of P86 and P89 and seat it on a
  dark disc if it needs one.
- For the lead, before P70 starts (request from P91): the terrain id `ore` that P70 adds to
  `data/terrain/standard.tres` turns `tests/project/test_cross_file_facts.gd` red (every terrain id has
  a colour and a tile in both map views, and `MapView` and the gallery hold the same keys) until
  `MapView.colors` and `MapView.tiles` (the script defaults and the node of `main.tscn`), the gallery's
  `TERRAIN_COLORS` and `TERRAIN_TILES`, the two terrain tables in this file and the terrain lists of
  `tests/art` all carry `ore` in one tree. `MapView` is touch-ux-dev's, and the plan's P70 row and its
  exceptions 11 to 15 do not name it, so the plan needs a named one-line exception for P70 (add the key
  `ore` #8A6F4D and the tile `0,0,8,8,ore` to those places, as proposed under "Ore") or a joint art and
  view row before P70. P84b comes too late. P91 leaves the key out of the gallery on purpose: `MapView`
  would then lack a key the gallery has, and P52's comparison would go red in this PR.
- For the lead, before P36 starts: the plan's `MapView` row allows the keys `<id>` and `<id>_b`
  and holds no tile rects, but this spec has three tones for scrub and rock and rect patterns for
  scrub, rock and water (ADR 0011 section 3 asks for the scrub pattern). The row needs `_c` keys, a
  rect table in `MapView` copied from the table above and applied as base, then rects, and the
  probe texels in P36's colour test (the tile centre of scrub is its highlight). The row's grid
  colour export and ADR 0011 section 3's "grid lines" are stale: the map has no grid. P52's
  cross-file test then compares `MapView`'s keys and strings with the gallery's `TERRAIN_COLORS` and
  `TERRAIN_TILES`. P36's phone check "the map looks as before" needs an exception: the Phase 1 grid
  lines are gone. The other route is two tones per terrain, which drops the scrub highlight and the
  rock bevel: change this spec for it, not the contract.

## Change log
| Date | Change |
| --- | --- |
| 2026-10-10 | v1: guide written with the layer contract and the light tank sample. |
| 2026-10-11 | v1.1 (P12): feedback marker spec, gallery zoom row, launcher icon credit. |
| 2026-10-12 | v1.2 (P34): rifle and rocket squads, their gallery slots and zoom row. |
| 2026-10-12 | v1.2 (P34b): selection ring texture and the draw-order rule, effects atlas, combat effects and health bars specs (weapon and class from snapshot columns, bars placed by sprite reach), the own and enemy cue. |
| 2026-10-12 | v1.2 (P34c): terrain tiles with the scrub pattern, keyed by `MapView.colors` key, the fog alpha, the gallery terrain patch with squads on scrub. |
| 2026-10-12 | v1.2 (P34c, Michael's answers): the map grid is removed, the rocket warhead stays #F5A524; the health bar overlap half-heights (14 and 21 world px) are recorded. |
| 2026-10-15 | P26t docs (Michael's decision): the Reskin section names the three places a new look is made; no rule changed. |
| 2026-10-19 | P58 review (art-director): palette row for the HUD panel backdrop; Reskin item 3 says what the UI Theme holds and what the dp step scales. No rule changed. |
| 2026-10-22 | v1.3 (P91, art-director): the six buildings with their layer contract, the ore cells and their levels, the two ghost patterns and the ghost look, two dirt tones (new), the Build and Ground gallery pages. |
| 2026-10-22 | v1.4 (P92, art-director): the heavy tank, the artillery and the harvester, the tab, item and glyph icons with the glyph contract (import scale 1.0, new), the two rally flags, the Vehicles and Icons gallery pages. |
