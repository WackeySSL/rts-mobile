# Art style guide (living)

This is the living version of the `svg-art-style` skill (`.claude/skills/svg-art-style/SKILL.md`)
plus the layer contract for multi-layer units. All art is hand-written SVG in this repository.
Update this file when Michael approves a change; the skill stays the short checklist.

Status: v1, written in Phase 0 with the light tank sample. Rules marked **(new)** go beyond the
skill and are waiting for Michael's approval (list at the end).

## Look
Clean, flat, top-down "military map" style with strong silhouettes, readable at small size on a
phone. Not cartoonish, not photoreal. Pure top-down view, light from the top-left.

## Scale
- 1 tile = 64 px in game at zoom 1. Author at 2x: 1 tile = 128 px in the SVG.
- Canvas at 2x: infantry squad 64x64, light vehicles 96x96, **tanks 128x128**, harvester 160x160,
  buildings 256x256 (2x2 tiles) or 384x384 (3x3 tiles).
- Godot rasterises an SVG once, at import. Showing a sprite above scale 1 therefore looks soft.
  The gallery shows scale 1 only.

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

## Originality
Describe each silhouette in one line before drawing, in your own words. The catalogue below holds
the line for the unit and each SVG header holds the line for its layer. No recognisable designs
from other games, for example twin-barrel super-heavy tanks, tesla-coil towers or airships. When
in doubt, choose a plainer real-world form.

## Catalogue
| Unit | Silhouette | Layers |
| --- | --- | --- |
| Light tank | A plain light tank shaped like an H on its side: two long round-ended track pods joined by a short flat deck, a compact rounded-rear turret, and one long vented barrel leaving through the front bay. | `units/light_tank_{hull,team,turret}.svg`, 128x128 |

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

Light tank result (v1): visible team share 29.9 / 26.5 / 26.8 / 26.4 % at 0 / 90 / 180 / 270
degrees; the team layer has no non-grey pixel; the gun sticks out 4 px by 4 px in the 32 px
silhouette; at 32 px greyscale the tracks, deck, turret and gun read as separate parts on grass and
sand.

## Gallery
`scenes/dev/art_gallery.tscn` (opened from the dev menu, also in the web preview) shows every asset
at scale 1 (gameplay zoom) on grass and sand, in team A and team B. A faint 64 px square behind each
unit marks one tile. Turrets turn slowly. To add an asset:
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
  no shadow and no one-sided light, and the reading of "1.5 px vs 2 px".
- Import scale 0.5 may look soft on phones with a device pixel ratio around 1.5. Judge it in the
  gallery on the phone. Changing it means a new rule here, approved by you.
- Team A and team B differ only in hue in the unit art. `touch-ui-rules` asks for a second cue than
  colour, which belongs on HUD markers (selection ring, health bar), not on the unit sprites.
  Decide whether that is enough.

## Change log
| Date | Change |
| --- | --- |
| 2026-10-10 | v1: guide written with the layer contract and the light tank sample. |
