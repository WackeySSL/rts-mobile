# ADR 0008: Map grid, movement, flow fields and separation

Status: proposed, 2026-10-11

## Context
ROADMAP Phase 2 asks for "movement with flow fields and separation". Phase 1 moves units in
straight lines to formation slots with no terrain and no collision (ADR 0003 §4-5), and its
tests pin exact positions tick by tick on an open map. `rts-sim-conventions` asks for:
- passability per movement class;
- integer flow fields per (target cell, class), cached and shared by a group;
- separation through a spatial hash processed in id order.

ADR 0002 §5 says Phase 2 replaces the view-only test map with sim map data. GDD maps are 56x56
to 64x64 tiles with chokepoints.

Measurements (Godot 4.7.2 headless, 2026-10-11, Xeon 2.1 GHz cloud VM; a mock tick, not the
real sim):
- **Dijkstra (Dial's buckets) over 64x64 cells, 8 neighbours:**
  - 17 to 20 ms with array literals in the loop;
  - 3 to 4 ms with constant offset arrays and a grid padded by one blocked cell.

  On a phone that is roughly 6 to 10 ms, too much for a single tick.
- **Separation for 150 packed units:**
  - 2-tile cells, 3x3 scan: 1.3 ms per tick;
  - 1-tile cells, 3x3 scan, stopping at 8 neighbours: 0.23 ms.
- **Target scans for a fifth of the units per tick, 6-tile acquire range:**
  - 2-tile grid (7x7 cells): 0.43 ms;
  - 4-tile grid (5x5 cells): 0.09 ms.
- **Whole optimised mock tick** (grids, flow lookup, separation, integration, targeting, fog):
  0.7 ms mean, 1.25 ms p95, over 900 ticks with 150 units.

## Decision

### 1. Map data
- `MapDef` (`game/sim/defs/MapDef.gd`, Resource):
  - `rows: PackedStringArray`, one string per tile row, one character per tile, all rows the
    same length;
  - `terrain: TerrainSetDef`.
  
  Maps are text, readable and diffable by agents and reviewers.
- `TerrainSetDef` holds `Array[TerrainDef]`. Each `TerrainDef` has:
  - `symbol: String` (one character);
  - `id: StringName`;
  - `cost: PackedInt32Array`, one entry per `MoveClass` (FOOT, WHEELED, TRACKED). 0 is blocked
    and 10 is normal. Costs above 10 are slower ground for pathing, capped at 40.
- Phase 2 terrain set `data/terrain/standard.tres`:

  | Symbol | id | Foot | Wheeled | Tracked |
  | --- | --- | --- | --- | --- |
  | `.` | grass | 10 | 10 | 10 |
  | `:` | sand | 10 | 10 | 10 |
  | `^` | scrub | 10 | 0 | 0 |
  | `#` | rock | 0 | 0 | 0 |
  | `~` | water | 0 | 0 | 0 |

  Scrub proves per-class passability (infantry crosses it, vehicles do not). Terrain speed
  modifiers are not part of Phase 2.
- `ScenarioDef` gains `map: MapDef`. Without a map, the scenario is open grass of
  `map_size_tiles` (Phase 1 scenarios unchanged). `World.from_scenario` copies the terrain index
  per tile into `world.terrain` and the cost per class into `world.move_cost`.
- A cell index is `(y / 1000) * map_cols + x / 1000`, for positions clamped to `[0, map_w - 1]`
  and `[0, map_h - 1]`. Collision is by unit centre: a unit may stand on a tile only if its
  class cost there is above 0.
- `map_version` increments whenever passability changes (buildings in Phase 3). Phase 2 maps are
  static, and tests change a tile through `World.set_terrain(cell, index)` to prove
  invalidation.

### 2. Orders, slots and navigation modes
- Formation slots stay as in ADR 0003 §4, with one addition: a candidate on a tile that is
  blocked for any movement class in the group is skipped. A target point on a blocked tile first
  moves to the centre of the nearest tile that is passable for every class in the group: rings of
  tiles around it, row by row, first hit wins.
- Each moving unit has a `nav_mode`:
  - `DIRECT`: steer straight at the goal. This is Phase 1 movement.
  - `FIELD`: follow a flow field.
  - `HOLD`: no intent; set by combat (ADR 0009).
- **Line check.** When an order is applied, each unit tests the tile line from its position to
  its goal: an integer supercover traversal of every tile the centre segment touches, all of
  them passable for its class.
  - Line clear: `DIRECT`. In a static map a clear line stays clear, so the unit never checks
    again.
  - Line blocked: `FIELD`, and the unit asks the flow cache for the field of (goal tile of the
    group target, class). While that field is not complete, the unit steers `DIRECT` and slides
    (section 4).
  - A `FIELD` unit repeats the line check each time it enters a new tile (`nav_cell`). As soon
    as the line is clear it switches to `DIRECT` and releases the field. This is any-angle
    path smoothing at the cost of about one line check per unit every 8 ticks.
- On an open map every line is clear. No field is ever computed, and Phase 1 movement and its
  tests stay exactly as they are.
- **Field following:** the unit steers towards the centre of the neighbour tile with the lowest
  integrated cost. That is any-angle steering from its real position, not an 8-way snap.
- **Steering:** `FixedMath.step_toward(x, y, tx, ty, speed)` (truncating, ADR 0003 §5), one
  `isqrt` per moving unit per tick. `isqrt` currently costs about 2 µs. The movement PR may
  replace its body with a faster exact method (for example Newton's method from a bit-length
  guess). The existing exhaustive `isqrt` test proves it is still exact.
- **Arrival:** snap to the goal when `d2 <= speed * speed` (v0).
- **Stall:** a moving unit tracks `best_dist`, its smallest distance to the goal so far. If that
  does not improve for `stall_ticks` (rules, 15) while the unit is within 2 formation spacings of
  its goal, the unit goes `IDLE` where it stands. A crowd around a slot then ends instead of
  jittering forever.

### 3. Flow fields and the cache
- `FlowField` (`game/sim/FlowField.gd`) runs an integer Dijkstra with Dial's buckets:
  - 8 neighbours: orthogonal cost = terrain cost, diagonal = terrain cost x 14 / 10;
  - no diagonal step past a blocked orthogonal neighbour (no corner cutting);
  - the grid is padded by one blocked ring, and the offset arrays are constants;
  - the buckets are preallocated rings, so integrating allocates nothing after the first field;
  - unreached cells hold `UNREACHED = 0x3FFFFFFF`.
- **Time-sliced:** `FlowCache.advance(budget)` settles at most `flow_cells_per_tick` (rules,
  1024) cells per tick, over one field at a time, in request order. A 64x64 field completes in
  about 4 ticks (0.27 s). Units steer `DIRECT` until then. The slicing counts cells, not time,
  so it is deterministic.
- **Cache:** `flow_cache_size` (rules, 8) slots, keyed by (goal cell, class, `map_version`).
  - Each slot has a reference count (units whose `field` is the slot) and a last-used tick.
  - A request for an existing key shares the slot. A group order shares one field per class.
  - A new key takes a free slot, else the least recently used slot with no references (ties go
    to the lower slot).
  - If none exists, the request returns -1 and the unit stays `DIRECT`.
  - Release on order change, on arrival and on death.
- **Invalidation:** when `map_version` changes, every slot restarts its integration in place, and
  units keep following the old costs until the new field completes.
- The cache is derived state and is not hashed (ADR 0007 §8). It changes behaviour only through
  "complete or not", which follows the command history deterministically.
- Fields for `ATTACK` orders are keyed on the target's tile when the order is applied. They are
  re-keyed if the target moves more than 4 tiles from that goal while the line stays blocked.

### 4. Separation and sliding
- `SpatialGrid` (`game/sim/SpatialGrid.gd`) is a counting-sort bucket grid (`cell_start` of
  cells + 1, `items` of rows), rebuilt from start-of-tick positions with no allocation:
  - the separation grid has 1-tile cells (every unit radius is at most 500, so contact pairs are
    always in the 3x3 neighbourhood);
  - the targeting grid has 4-tile cells (ADR 0009).
  
  Rows inside a cell are in ascending id order.
- For each unit in id order, scan the 3x3 cells row by row:
  - Look at most at `separation_scan` (rules, 16) other units and use the first
    `separation_neighbours` (rules, 8) that overlap (`d2 < R * R` with `R = r_i + r_j`).
  - The push is sqrt-free: `(dx, dy) * (R*R - d2) / (2 * R*R)`. It is strongest when the units
    nearly coincide and 0 at contact. Two units on exactly the same point get `±R / 4` along x,
    the lower id towards -x.
  - Shares: two units in the same state split the push 50/50. An idle unit next to a moving one
    takes `separation_idle_share` percent (rules, 75), so moving units shoulder through idle
    ones.
  - Each unit's summed push is clamped to `separation_push_max` (rules, 60 milli per tick) per
    axis.
- Pushes are accumulated for all units before any unit moves (Jacobi style). The result does not
  depend on which unit was processed first, except through the neighbour caps, and those follow
  the id order of the scan.
- All units separate, including enemies. Projectiles do not.
- **Integrate and slide:**
  - The new position (intent + push) is clamped to the map.
  - If its tile is blocked for the unit's class, try the x move alone, then the y move alone,
    else stay.
  - A unit that started on a blocked tile (only possible after `map_version` changes) may move
    anywhere passable.

### 5. Rules data
`data/rules.tres` (`RulesDef`) holds every tuning number of this ADR:
- `flow_cells_per_tick` 1024, `flow_cache_size` 8;
- `separation_neighbours` 8, `separation_scan` 16, `separation_idle_share` 75,
  `separation_push_max` 60;
- `stall_ticks` 15.

ADRs 0009 and 0010 add to the same file. No such number is a constant in code (CLAUDE.md
rule 5).

## Consequences
- Phase 1's straight-line behaviour is the special case "line clear". The Phase 1 tests and the
  controls map keep passing, as long as the controls map keeps the area that those tests use
  free of blocked tiles (the plan's P48 constraint).
- Flow fields cost time only when a line is blocked, and then at most `flow_cells_per_tick` cells
  per tick. The cost of an order no longer depends on the map size.
- The tick grows with crowding, not with the map: separation is bounded by
  `separation_scan * units`.
- Centre-based collision lets a large unit's art overlap rock by up to its radius. That is
  acceptable top-down, and the art keeps shadows small.
- Chasing a target (ADR 0009) steers `DIRECT` with sliding and can stall behind a wall. The Phase 4
  AI may need field-based chasing, through a new ADR.
- Diagonal movement past corners and the sqrt-free push are approximations. They are pinned by
  tests, so a later change is visible.
- `rts-sim-conventions` says "cell = 2 tiles". That text changes with Michael's approval (ADR 0007
  Consequences).
