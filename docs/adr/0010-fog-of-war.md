# ADR 0010: Fog of war (sim grids, update cadence, rendering)

Status: proposed, 2026-10-11

## Context
ROADMAP Phase 2 asks for "fog of war (visible and explored) and its rendering". The GDD says:
- unexplored is black;
- explored but not visible shows the last known buildings;
- the AI has no vision it has not scouted (pillar 4, `ai-dev`).

`rts-sim-conventions` asks for per-player `visible` and `explored` bit grids, updated every
3 ticks from precomputed sight masks. Targeting (ADR 0009) and `ATTACK` validation (ADR 0007 §5)
need "visible to player p at cell c". The renderer is Compatibility (web and low-end Android).

Measured in the mock tick (ADR 0008 Context): re-stamping full sight discs for every unit every
3 ticks cost 0.69 ms per tick on average, with 2 ms on update ticks. Stamping only units that
changed tile, one player per tick, with row spans, cost 0.12 ms per tick.

## Decision

### 1. Sim representation
- `FogGrid` (`game/sim/FogGrid.gd`, pure) is owned by `World` and hashed with it:
  - `visible: PackedInt32Array`: the number of the player's sight discs covering each cell,
    laid out `player * cells + cell`. A cell is visible when the count is above 0. A count, not a
    bit, so moving one unit never clears what another still sees.
  - `explored: PackedByteArray`: 1 once any of the player's discs has covered the cell. Never
    cleared.
  - `version: PackedInt32Array`: one entry per player. It increments when a cell of that player
    changes visible or explored state. The view uses it to skip unchanged frames. It is not
    hashed.
- **Sight masks:** one per distinct `sight_range`, built once at match start. A mask is a
  half-width per row offset: tile `(dx, dy)` is inside when
  `(dx*1000)^2 + (dy*1000)^2 <= sight^2`, measured from tile centre to tile centre. Stamping
  walks row spans, clipped to the map. There is no line-of-sight blocking by terrain in
  Phase 2.
- **Stamping:** each row keeps `fog_cell`, the cell its disc was stamped at (-1 = not stamped).
  - An update re-stamps a row only when its current cell differs: unstamp the old disc
    (counts - 1), stamp the new one (counts + 1, explored = 1).
  - `remove_dead()` unstamps a dying row at once, so a dead scout's vision ends that tick.
  - A new row is stamped at its player's next update.
- **Cadence:** player `p` updates on ticks where `tick % fog_period == (p - 1) % fog_period`
  (rules, 3). With two players the work is spread over two ticks of every three, never both on
  one tick. A unit entering view may show up to 2 ticks (0.13 s) late. That is acceptable, and
  pinned by a test.
- **Queries:** `is_visible(player, cell)` and `is_explored(player, cell)`. Neutral (0) has no
  grid.
- **Users:**
  - target acquisition (ADR 0009: a candidate must be visible to the attacker's owner);
  - `ATTACK` validation;
  - in Phase 4, the AI's own view of the map;
  - in Phase 3, the last-seen building memory.

  The sim itself is not hidden from anyone: fog limits what Commands and targeting may use, not
  what the World stores.

### 2. View rendering (`game/view/FogLayer.gd`)
- A `Sprite2D` with an `ImageTexture` of `map_cols x map_rows` pixels in `FORMAT_RGBA8`,
  `centered = false` at the map origin, scaled by `ViewScale.PX_PER_TILE`, `texture_filter =
  LINEAR`. Each texel is one tile of black with an alpha:
  - unexplored: 255;
  - explored but not visible: the art spec's value (starting at 140);
  - visible: 0.
  
  Linear filtering softens each boundary across one tile with no shader. Compatibility samples
  RGBA8 everywhere. LA8 or R8 would need format checks on GLES3 and WebGL2, so they are not used.
- Draw order, bottom to top: map, units (rings, hulls, team layers, turrets, health bars),
  projectiles and effects, **fog**, then move and target markers, then the HUD. Orders and their
  markers stay readable above the fog.
- **Updates:** in the `ticked` handler, when `fog.version[local_player]` has changed. Rebuild a
  reused `PackedByteArray` (4 bytes per tile), then call `Image.set_data()` and
  `ImageTexture.update()`. That is at most 5 uploads per second of 16 KB for a 64x64 map.
- **Enemy rigs, projectiles and effects** on a cell the local player does not see are hidden.
  Own units are always shown. The visible flag changes per tick, not per frame.
- Explored-but-not-visible areas show no enemy units in Phase 2. Ghosts of the last seen
  buildings come with buildings in Phase 3, from a per-player memory that this ADR does not fix.
- There is no minimap fog in Phase 2 (no minimap). A reveal toggle for debugging is not added.
  The perf arena plays with normal fog for player 1.

### 3. Data
`RulesDef.fog_period_ticks` (3). `TerrainDef` has no sight effect in Phase 2. The explored alpha
and the edge look are in `assets/art/STYLE.md` § "Fog and terrain" (art-director), and
`FogLayer` exports the matching values.

## Consequences
- Fog costs about 0.1 ms per tick in the mock, independent of the map size, because only units
  that changed tile re-stamp.
- The hash covers `visible` counts and `explored`, so a fog divergence is caught like any other.
- Targeting depends on fog, so the fog PR changes target acquisition. Its tests pin "an enemy
  just outside sight is not attacked" and "an `ATTACK` on an unseen unit is dropped".
- Hiding enemies uses the tile at their current position. An enemy at the very edge of sight can
  flicker as it crosses tiles. Interpolated rigs make that rare, and the tile-soft fog edge
  hides it.
- A shader-based smooth fog (interpolating between two textures over the 3-tick update) is
  polish for Phase 5, if Michael wants it.
