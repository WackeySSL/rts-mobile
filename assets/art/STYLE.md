# Art style guide (living)

This is the living version of the `svg-art-style` skill (`.claude/skills/svg-art-style/SKILL.md`)
plus the layer contract for multi-layer units. All art is hand-written SVG in this repository.
Update this file when Michael approves a change; the skill stays the short checklist.

Status: v1, written in Phase 0 with the light tank sample. v1.1 (Phase 1, P12) adds the feedback
markers and the gallery zoom row. v1.2 (Phase 2, P34) adds the rifle and rocket squads. Rules marked
**(new)** go beyond the skill and are waiting for Michael's approval (list at the end).

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
| Water | #2E5E7E / #3C7396 | |
| Ore | #F2B705, highlight #FFD84D, shade #A67C00 | |
| Team A / team B / neutral | #2F80ED / #E5484D / #9AA5B1 | 116 / 120 / 163 |
| UI accents: warning / danger / ok | #F5A524 / #E5484D / #30A46C | |

Luminance is 0.299 R + 0.587 G + 0.114 B. Use it when you judge the greyscale check below.

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
  `linearGradient` (sparingly; the tank uses none). Not allowed: text, image, filter, mask,
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
  3. Check the texture: a 128 px canvas must load as 64x64.

## Layer contract (multi-layer units)
Vehicles are drawn from three layers that share one canvas size:

| Order | File | Holds |
| --- | --- | --- |
| 1 | `<name>_hull.svg` | Tracks or wheels, hull deck and the ground shadow of the whole vehicle |
| 2 | `<name>_team.svg` | White and grey team marks, tinted with `modulate` |
| 3 | `<name>_turret.svg` | Turret and gun; rotates about the canvas centre |

- Draw order: hull, then team, then turret.
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
Selection rings, the target flash, the attack-move marker, the long-press anchor and the box are
drawn in code (`_draw` or `Line2D`), not as SVG. They stay crisp at every zoom and are sized in dp
(ADR 0004 section 7). The SVG technical rules do not apply to them, the palette does. touch-ux-dev
builds them in P16 and pins the numbers below in tests.

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
| Own selection ring | Circle at the unit position, radius R = max((selection_radius / 1000 + 0.05) x 64 world px, 18 dp). Light tank: 35.2 world px, so 31.5 / 35.2 / 52.8 base px on screen at zoom 0.75 / 1.0 / 1.5 on the 6-inch phone profile (1 dp = 1.75 base px) | 3 dp | #FFFFFF | None. Shown in the frame of the tap | World space, first child of the unit rig, under the hull |
| Enemy target flash | Diamond (a square turned 45 degrees), corners 45.8 world px from the enemy position (1.3 x the light tank's R of 35.2). `show_target(world_px)` carries only the position and Phase 1 has one unit type, so this is one view constant of the layer, not read from unit data | 3 dp | #E5484D | Starts at 1.5 x size, reaches 1.0 x in 150 ms (ease), then fades | World space, `MarkerLayer`, above the units |
| Attack-move marker | Four chevrons around the tapped point (the origin), pointing at it. The east one is the open polyline (d + 7, -7), (d, 0), (d + 7, 7) dp, so its tip faces the point. The south, west and north ones are the same turned by 90, 180 and 270 degrees. d = 12 dp at rest | 3 dp | #F5A524 | d goes from 36 dp to 12 dp in 200 ms (ease), then fades | World space, `MarkerLayer`. A dp size, so it does not grow with the zoom |
| Long-press anchor | Ring at the press point, radius 32 dp (diameter 64 dp, about 10 mm). Fill #FFFFFF at 15% | 3 dp | #FFFFFF | Radius 48 dp to 32 dp in 150 ms (ease), then it stays until the box ends or cancels | Screen space, `BoxOverlay`, drawn before the box |
| Selection box | The normalised drag rect. The centre line is the rect inset by 1 dp, so the outer edge of the white is the rect edge. Fill #FFFFFF at 15% | 2 dp | #FFFFFF | None | Screen space, `BoxOverlay` |

Draw order, bottom to top: ground, then each rig (ring, hull, team layer, turret), then flash and
chevrons, then the HUD layer with the anchor and the box. A fill is drawn before its outline pass.

Checked in a scratch render at 1.75 base px per dp on grass #6F8F57 and sand #CDB98F, in colour and
in greyscale: all five read apart by shape on both grounds, and the dark outline keeps the red
diamond (luminance 120, grass 127) and the chevrons (174, sand 186) readable. Look again once P16
draws them on the phone.

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
list in `art_gallery.gd` instead of getting rigs in the scene. To add an asset:
- Add its layers as one rig `Node2D` under each of the four slots (grass A, grass B, sand A, sand B).
- Put the rig in the group `gallery_team_a` or `gallery_team_b`, and name the layers `Hull`, `Team`
  and `Turret` (a unit without a turret leaves `Turret` out).
- The script `game/view/art_gallery.gd` tints `Team` and turns `Turret`. The team colours are exported
  properties of the scene root.
- The Back button (120x120 base px, top-left) and the Android back request both return to the dev
  menu. While the gallery is open the script switches `SceneTree.quit_on_go_back` off (its default
  is on, which would quit the app) and restores it on exit.

## Open points for Michael
- Approve the **(new)** rules: team-layer greys, elevation reads as lightness, rotating layers carry
  no shadow and no one-sided light, the reading of "1.5 px vs 2 px", and the feedback marker
  spec (shapes, dp sizes, colours, outline, fade).
- **(new)** The rocket warhead is #F5A524, the UI warning accent, used in unit art. The attack-move
  chevrons and the enemy health bar fill (P34b) use the same colour, so an own rocket squad carries
  two marks in the enemy-bar colour. The notch stays the own/enemy cue. Judge the warhead next to
  the bar in the gallery: if it confuses, the fix is a warm tone that is not a UI accent.
- Please judge on the phone (Dev, Art gallery, bottom row) whether zoom 1.5 looks too soft. The
  tile is a 64 px raster drawn at 2.25 times on a 6-inch phone. The fix would be SVG import scale
  1.0 with mipmaps and sprites drawn at scale 0.5. That changes the Technical rules here, so it
  needs your approval. It is not part of P12 (plan open question 4).
- The red target diamond has almost the same luminance as grass (120 against 127). Only its dark
  outline separates them. Judge it on the phone once P16 draws it.
- Team A and team B differ only in hue in the unit art. `touch-ui-rules` asks for a second cue than
  colour, which belongs on HUD markers (selection ring, health bar), not on the unit sprites.
  Decide whether that is enough.

## Change log
| Date | Change |
| --- | --- |
| 2026-10-10 | v1: guide written with the layer contract and the light tank sample. |
| 2026-10-11 | v1.1 (P12): feedback marker spec, gallery zoom row, launcher icon credit. |
| 2026-10-12 | v1.2 (P34): rifle and rocket squads, their gallery slots and zoom row. |
