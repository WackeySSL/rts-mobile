---
name: svg-art-style
description: Style guide and technical rules for all hand-written SVG art in rts-mobile - top-down flat military-map look, palette, outline, light direction, canvas sizes, team-colour layers, naming, Godot import and originality. Use whenever creating, editing or reviewing any SVG asset, icon, unit, building, terrain tile or effect.
paths:
  - "assets/art/**"
---

# SVG art style

Look: clean, flat, top-down "military map" style with strong silhouettes, readable at small size
on a phone. Not cartoonish, not photoreal.

## Camera and scale
- Pure top-down view; light from the top-left.
- 1 tile = 64 px in game at zoom 1. Author at 2x for sharpness: 1 tile = 128 px in the SVG.
- Canvas at 2x: infantry squad 64x64, light vehicles 96x96, tanks 128x128, harvester 160x160,
  buildings 256x256 (2x2 tiles) or 384x384 (3x3 tiles).
- Vehicles have separate hull and turret files. The turret pivot is the canvas centre; the hull
  faces east (+x).

## Palette (hex)
- Outline #1C2127. Drop shadow #000000 at 25% opacity, offset (4, 4) at 2x.
- Metal #5B6670 / #7D8893 / #A9B4BE (shade, mid, highlight).
- Olive #4E5A3A / #6B7A4F / #8C9A6B. Sand #B59F72 / #CDB98F / #E4D6B3.
- Terrain: grass #5E7D4A / #6F8F57, dirt #8A6F4D, rock #6E6A66, water #2E5E7E / #3C7396.
- Ore: #F2B705 with highlight #FFD84D and shade #A67C00.
- Team-colour layer is drawn in white and greys and tinted at runtime: team A #2F80ED,
  team B #E5484D, neutral #9AA5B1.
- UI accents: warning #F5A524, danger #E5484D, ok #30A46C.

## Drawing rules
- Outline 3 px (at 2x) on the outer silhouette, 1.5 px on inner details.
- Three tones per material plus a highlight on edges facing the top-left.
- No detail thinner than 2 px at 2x. The silhouette must be identifiable at 32 px in greyscale.
- The team-coloured area covers 20-35% of the visible surface and always includes a stripe or
  marker visible from above.

## Technical rules
- One drawing per file with `width`, `height` and `viewBox="0 0 W H"` set to the canvas.
- Allowed elements: path, rect, circle, ellipse, polygon, polyline, line, g, linearGradient
  (sparingly). Not allowed: text, image, filter, mask, foreignObject, external href, style
  blocks, scripts.
- At most 20 KB per file; integer or one-decimal coordinates.
- Naming: `assets/art/svg/<category>/<name>[_hull|_turret|_team].svg` in snake_case.
- Godot imports SVG directly. Use import scale 0.5 for 2x assets so 1 tile = 64 px in game,
  and commit the `.import` files.

## Originality
Describe each silhouette in words before drawing. No recognizable designs from other games,
for example twin-barrel super-heavy tanks, tesla-coil towers or airships. When in doubt, choose
a plainer real-world form.

## Gallery
Every asset appears in `scenes/dev/art_gallery.tscn` at gameplay zoom on grass and sand, in both
team colours, so consistency can be judged on a phone through the web preview.
