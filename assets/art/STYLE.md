# Art style guide (living)

This is the living version of the `svg-art-style` skill (`.claude/skills/svg-art-style/SKILL.md`)
plus the layer contract for multi-layer units. All art is hand-written SVG in this repository.
Update this file when Michael approves a change; the skill stays the short checklist.

Status: v1, written in Phase 0 with the light tank sample. v1.1 (Phase 1, P12) adds the feedback
markers and the gallery zoom row. v1.2 (Phase 2, P34) adds the rifle and rocket squads, the selection ring
texture, the effects atlas and the specs for combat effects, health bars, fog and terrain. Rules marked **(new)**
go beyond the skill and are waiting for Michael's approval (list at the end).

## Look
Clean, flat, top-down "military map" style with strong silhouettes, readable at small size on a
phone. Not cartoonish, not photoreal. Pure top-down view, light from the top-left.

## Scale
- 1 tile = 64 px in game at zoom 1. Author at 2x: 1 tile = 128 px in the SVG.
- Canvas at 2x: infantry squad 64x64, light vehicles 96x96, **tanks 128x128**, harvester 160x160,
  buildings 256x256 (2x2 tiles) or 384x384 (3x3 tiles).
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
To add an asset:
- Add its layers as one rig `Node2D` under each of the four slots (grass A, grass B, sand A, sand B).
- Put the rig in the group `gallery_team_a` or `gallery_team_b`, and name the layers `Hull`, `Team`
  and `Turret` (a unit without a turret leaves `Turret` out).
- The script `game/view/art_gallery.gd` tints `Team` and turns `Turret`. The team colours are exported
  properties of the scene root.
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
  and effects layers' constants, the art test's `REGIONS` and that table change with it.
- **The palette colours kept in `game/view`** as constants or exports: the team tints
  (`UnitLayer.team_colors`), the feedback markers (`FeedbackStyle`, `MoveMarkerLayer`), and from
  their PRs on the health bar, tracer and fog colours ("Health bars", "Combat effects", "Fog and
  terrain"). The gallery's copies follow them: `art_gallery.gd`'s team colours and
  `TERRAIN_COLORS`, and the `Grass` and `Sand` rects of `scenes/dev/art_gallery.tscn`.
- **The tests that pin today's palette**: `tests/art/test_art_assets.gd` (`ATLAS_COLOURS`,
  `REGIONS`, `SIDE_PX`, the ring, the terrain pictures) and `tests/view/test_feedback.gd`.

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
