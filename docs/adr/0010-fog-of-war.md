# ADR 0010: Fog of war (sim grids, update cadence, rendering)

Status: accepted, 2026-10-12 (Michael). Proposed 2026-10-11 (revision 5 after the five-lens plan review and three completeness checks, same day).

Status note (2026-10-12): §1-2 partly superseded by ADR 0012 §3, where the view reads the fog and
its dirty lists from the World: it reads them from `runner.snapshot.fog`.

## Context
ROADMAP Phase 2 asks for "fog of war (visible and explored) and its rendering". The GDD says:
- unexplored is black;
- explored but not visible shows the last known buildings;
- the AI has no vision it has not scouted (pillar 4, `ai-dev`).

`rts-sim-conventions` asks for per-player `visible` and `explored` bit grids, updated every
3 ticks from precomputed sight masks. Targeting (ADR 0009) and `ATTACK` validation (ADR 0007 §5)
need "visible to player p at cell c". The renderer is Compatibility (web and low-end Android).

Measurements (Godot 4.7.2, Xeon cloud VM):
- In the mock tick (ADR 0008 Context), re-stamping full sight discs for every unit every 3 ticks
  cost 0.69 ms per tick on average, with 2 ms on update ticks. Stamping only units that changed
  tile, one player per tick, with row spans, cost 0.12 ms per tick in that mock.
- The plan review measured the real data sizes: re-stamping one unit (unstamp and stamp a 6-7
  tile disc with the count, explored and version checks) costs 23-26 µs. At arena speeds 20-27 of
  a player's 75 units change tile between its updates, so an update costs 0.5-0.7 ms and the mean
  is about 0.4 ms per tick. The first stamp of all 150 units costs 1.8-2.0 ms (once, at setup).
- A full GDScript rebuild of a 64x64 RGBA fog texture (read count and explored, write 4 bytes per
  cell, then `set_data` and `update`) costs 0.72-0.77 ms, on the frames that already carry a
  tick.

## Decision

### 1. Sim representation
- `FogGrid` (`game/sim/FogGrid.gd`, pure) is owned by `World` and hashed with it. Every
  per-player block is indexed by `player - 1` (players are 1..`player_count`; neutral 0 has no
  grid), and the methods take the player id:
  - `visible: PackedInt32Array`: the number of the player's sight discs covering each cell,
    laid out `(player - 1) * cells + cell`. A cell is visible when the count is above 0. A count,
    not a bit, so moving one unit never clears what another still sees.
  - `explored: PackedByteArray`: 1 once any of the player's discs has covered the cell, same
    layout. Never cleared.
  - `version: PackedInt32Array`: one entry per player (`version_of(player)`). It increments when
    a cell of that player changes visible or explored state. Not hashed.
  - **Dirty lists** (not hashed): per player, the cells whose visible or explored state flipped
    since that player's previous update, with a capacity of a quarter of the cells and a "full"
    flag on overflow. The sim clears a player's list at the start of that player's update, so the
    view reads each list in the `ticked` signal that follows the update.
  - `const HASHED: Array[StringName] = [&"visible", &"explored"]` and the matching `UNHASHED`
    list, so the hash coverage test sees FogGrid's arrays (ADR 0007 §8).
- **Sight masks:** one per distinct `sight_range`, built once in `World.prepare()`. A mask is a
  half-width per row offset: tile `(dx, dy)` is inside when
  `(dx*1000)^2 + (dy*1000)^2 <= sight^2`, measured from tile centre to tile centre. Stamping
  walks row spans, clipped to the map. There is no line-of-sight blocking by terrain in
  Phase 2.
- **Stamping:** each row keeps `fog_cell`, the cell its disc was stamped at (-1 = not stamped).
  - `World.prepare()` stamps every existing row, so the first frame of a match already shows the
    player's own vision (the tick-0 hash includes it).
  - An update re-stamps a row only when its current cell differs: unstamp the old disc
    (counts - 1), stamp the new one (counts + 1, explored = 1).
  - `remove_dead()` unstamps a dying row at once, so a dead scout's vision ends that tick.
  - A row added later is stamped at its player's next update.
- **Cadence:** player `p` updates on ticks where `tick % fog_period == (p - 1) % fog_period`
  (rules, 3). With two players the work is spread over two ticks of every three, never both on
  one tick (with four players, players 1 and 4 share a tick). A unit entering view may show up
  to 2 ticks (0.13 s) late. That is acceptable, and pinned by a test.
- **Queries:** `is_visible(player, cell)` and `is_explored(player, cell)` for code outside hot
  loops. Hot loops alias `fog.visible` and index it inline (ADR 0007 §1).
- **Users:**
  - target acquisition (ADR 0009: a candidate must be visible to the attacker's owner);
  - `ATTACK` validation;
  - in Phase 4, the AI's own view of the map;
  - in Phase 3, the last-seen building memory.

  The sim itself is not hidden from anyone: fog limits what Commands and targeting may use, not
  what the World stores.
- **AI access (reserved, built by the first AI PR):** opponent AI code in `game/ai` will read the
  World only through a pure `game/sim/PlayerView.gd` (visible enemy rows, own rows, explored
  cells, events filtered to visible cells), with a scan test over `game/ai` like the randomness
  scan. The per-player last-seen memory will live inside `FogGrid` and be hashed. Both arrive
  with the first AI code (Phase 3 dummy opponent), not in Phase 2.

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
- **Updates:** in the `ticked` handler, when `fog.version_of(local_player)` has changed:
  - patch only the bytes of the cells in the player's dirty list in a reused `PackedByteArray`,
    then `Image.set_data()` and `ImageTexture.update()` (native copies);
  - do a full rebuild only for a new match (`runner.match_serial` changed) or when the dirty list
    overflowed.

  The GDScript work is then proportional to the cells that changed. The layer records its update
  time for the perf card. Its budget is 1 ms p95 on a 2021 phone, which the gate checks as
  0.4 ms p95 on the gate phone (`fog_update_p95_ms`, ADR 0011 §5).
- **Testability:** the layer keeps its CPU-side `Image` and exposes it (`func image() -> Image`).
  Tests assert on that image, never on `ImageTexture.get_image()`, which on Godot 4.7.2 keeps
  returning the first upload after `update()` or `set_image()` (verified headless).
- **Enemy rigs, projectiles and effects** on a cell the local player does not see are hidden,
  and hidden enemies are **not pickable**: the pick snapshot keeps its row order but marks them
  unpickable, so a tap near a hidden enemy is a ground tap. Own units are always shown. The
  visible flag changes per tick, not per frame. A `SHOT` tracer is drawn when either end is on a
  visible cell.
- Explored-but-not-visible areas show no enemy units in Phase 2. Ghosts of the last seen
  buildings come with buildings in Phase 3, from the memory reserved above.
- There is no minimap fog in Phase 2 (no minimap). There is no reveal toggle in the game. The
  perf arena alone sets a view-only `reveal_enemies` export on its unit, projectile and effects
  layers, so every enemy rig is drawn and the render load is the worst case. Its `FogLayer`
  still draws player 1's real fog, and the sim and the hash are unaffected. Among shipped scenes
  only the perf arena sets it; a test whose subject is not fog (a Phase 1 enemy-tap case, for
  example) may set it on `UnitLayer`, which also makes those enemies pickable, while the fog
  picking rule keeps its own cases.

### 3. Data
`RulesDef.fog_period_ticks` (3). `TerrainDef` has no sight effect in Phase 2. The explored alpha
and the edge look are in `assets/art/STYLE.md` § "Fog and terrain" (art-director), and
`FogLayer` exports the matching values.

## Consequences
- Fog costs about 0.4 ms per tick on average in a moving 150-unit fight on the VM (0.5-0.7 ms on
  a player's update tick), plus 1.8-2.0 ms once at setup. It grows with the number of units that
  change tile, not with the map size.
- The hash covers `visible` counts and `explored`, so a fog divergence is caught like any other.
- Targeting depends on fog, so the fog-rules PR changes target acquisition. Its tests pin "an
  enemy just outside sight is not attacked" and "an `ATTACK` on an unseen unit is dropped".
- Hiding enemies uses the tile at their current position. An enemy at the very edge of sight can
  flicker as it crosses tiles. Interpolated rigs make that rare, and the tile-soft fog edge
  hides it.
- A shader-based smooth fog (interpolating between two textures over the 3-tick update) is
  polish for Phase 5, if Michael wants it.
