---
name: svg-art-style
description: Style guide and technical rules for all hand-written SVG art in rts-mobile - realistic muted military look with top-down units and oblique 3/4 buildings (ADR 0022), palette, edges and shadows, light direction, canvas sizes, team-colour layers, naming, Godot import and originality. Use whenever creating, editing or reviewing any SVG asset, icon, unit, building, terrain tile or effect.
paths:
  - "assets/art/**"
---

# SVG art style

Look (ADR 0022, Michael 2026-10-26): a realistic, muted military look, readable at small size on a
phone. Real materials (poured concrete, corrugated steel, tarmac, sandbags, canvas, rust, dirt),
believable proportions and detail density, soft shading and weathering, small team markings. Not
cartoonish, not photoreal, no flat colour fields. Units, effects, icons, ore and ground are
top-down; buildings are drawn in an oblique 3/4 view. `assets/art/STYLE.md` holds the full rules.

## Camera and scale
- One light from the top-left for everything.
- 1 tile = 64 px in game at zoom 1. Author at 2x for sharpness: 1 tile = 128 px in the SVG; import
  scale 0.5.
- **Units and everything but buildings: pure top-down.** Canvas at 2x: infantry squad 64x64, light
  vehicles 96x96, tanks 128x128, harvester 160x160. Vehicles have separate hull and turret files.
  The turret pivot is the canvas centre; the hull faces east (+x).
- **Buildings: oblique 3/4 view.** A ground point (x, y) of the footprint is drawn at (x, y), a
  point h px above the ground at (x, y - h); no sideways skew, so the east and west walls are
  edge-on and the sprite never leaves the footprint's columns. The roof and the south facade show.
  The rise is 0.75 tile: 96 px at 2x (48 in game). Canvas = footprint plus the rise: 3x3 384x480,
  2x2 256x352, 1x1 128x224 at 2x. Anchor: the canvas's bottom edge lies on the footprint's south
  edge and its left edge on the west edge; the view derives the rise from the texture height. A
  low building leaves the top of its canvas clear; nothing is drawn outside the canvas (shading and
  contact shadows stay inside the box). A building `turret` head turns about the roof's centre (the
  footprint centre lifted by the rise).

## Palette (hex)
- Materials (A's muted values): tarmac #4A4F53 to #62676A, concrete #8D8F88, corrugated steel
  #5D6B68 to #A0ACA8, olive drab #46532F to #78885B, rust #8F5731.
- Edges are a dark shade of their own material, not one outline colour; shadows are soft and dark.
- Terrain: grass #5E7D4A / #6F8F57, dirt #8A6F4D, rock #6E6A66, water #2E5E7E / #3C7396: the base
  colours that `MapView` and the gallery keep (P52's cross-file facts); the textured ground tiles
  follow STYLE.md's "Fog and terrain".
- Ore: #F2B705 with highlight #FFD84D and shade #A67C00.
- Team-colour layer is drawn in greys only (R = G = B) and tinted at runtime: team A #2F80ED,
  team B #E5484D, neutral #9AA5B1.
- UI accents: warning #F5A524, danger #E5484D, ok #30A46C.

## Drawing rules
- No heavy outline: a thin dark edge (about 1.5 px at 2x) on the silhouette and inner details, a
  soft dark contact rim where a volume meets the ground, and a short soft shadow. No other detail
  thinner than 2 px at 2x.
- Three tones per material plus a highlight on edges facing the top-left; texture from gradients
  and dash arrays.
- Units: the shadow is a short throw plus a ring of ambient dark inside the hull canvas, so the
  hull can face any way; rotating layers (turrets) carry no shadow and are shaded symmetrically
  about the gun line.
- Buildings: south facades in shade; the roof reads as the footprint lifted by the wall height.
- The silhouette must be identifiable at 32 px in greyscale.
- Team colour covers about 8-12 % of the visible surface, as marks visible from above (stripes,
  bands, pennants, panels), never large team plates.

## Technical rules
- One drawing per file with `width`, `height` and `viewBox="0 0 W H"` set to the canvas.
- Allowed elements: path, rect, circle, ellipse, polygon, polyline, line, g, defs, linearGradient,
  radialGradient, clipPath, and use referencing only `href="#id"` in the same file; group opacity
  and dash arrays.
- A mask only with solid fills (Godot 4.7.2's ThorVG hides everything under a gradient-filled
  mask). No `pattern`: ThorVG in 4.7.2 renders none, so the file would look empty in the game.
- Not allowed: pattern, text, image, filter, foreignObject, external href, style blocks, scripts.
- At most 28 KB per file; integer or one-decimal coordinates.
- Naming: `assets/art/svg/<category>/<name>[_hull|_turret|_team].svg` in snake_case; ground tiles
  `assets/art/svg/ground/<terrain_id>_a.svg` and `_b.svg`.
- Godot imports SVG directly. Use import scale 0.5 for 2x assets so 1 tile = 64 px in game,
  and commit the `.import` files.

## Originality
Describe each silhouette in words before drawing. No recognizable designs from other games,
for example twin-barrel super-heavy tanks, tesla-coil towers or airships. When in doubt, choose
a plainer real-world form.

## Gallery
Every asset appears in `scenes/dev/art_gallery.tscn` at gameplay zoom on grass and sand, in both
team colours, so consistency can be judged on a phone through the web preview.
