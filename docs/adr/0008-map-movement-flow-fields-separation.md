# ADR 0008: Map grid, movement, flow fields and separation

Status: accepted, 2026-10-12 (Michael). Proposed 2026-10-11 (revision 4 after the five-lens plan review and two completeness checks, same day).

Status note (2026-10-12): §3 partly superseded by ADR 0012 §5 (the slice budget of about 2 ms on
the worker instead of 0.2 ms, `flow_cells_per_tick` from the release run instead of 512, and no
slice on checkpoint ticks instead of a slice on every tick).

Status note (2026-10-12): §3 superseded in part by ADR 0013 §2 (accepted 2026-10-12): "the buckets
are preallocated rings, so integrating allocates nothing after the first field" becomes
"`configure()` allocates every slot's arrays; nothing allocates after it" (P30b), so the C++ FLOW
kernel never resizes a slot array.

Status note (2026-10-13, P26i): two decisions of the lead after the P30b review (#58) refine §3;
the inline notes in §3 give them in full:
- `acquire()` counts the slot it hands out as referenced until the next `recount()` (a
  provisional reference), so two new keys in one tick never share a slot;
- `World.set_terrain()` calls `flow.invalidate(map_version)` right after it bumps `map_version`,
  once the World is prepared; `FlowCache.run` (P30n) does not call `invalidate()`.

The allocation rule of the note above is the plan's revision-15 rule, and it is what P30b merged:
`FlowCache.configure()` calls `FlowField.reserve()` on every slot, and nothing allocates after it.

Status note (2026-10-14, P26p docs, from P37a as merged, #86): §1 and §2 are made precise by the
merged `game/sim/FixedMath.gd` and `game/sim/Formation.gd`; the inline notes in §1 and §2 give
the rules with quotes from the code. In short: a point is in the tile `World.cell_of` gives it
(half-open tiles, the far map edge in the last tile); `line_clear` tests every tile the segment
touches under that rule (along a tile edge only the tiles on its right or lower side; a corner
crossed strictly between the ends also touches the two tiles beside it, matching `FlowField`'s
no-corner-cutting rule); a group is blocked on a tile when any move class in it is blocked; a
target on rock moves to the first open tile of §2's ring search, kept inside the radius-inset
box. No decision changes.

Status note (2026-10-14, P26s docs, from P37a2 as merged, #94): §2's "Arrival" bullet carries a
dated note: the merged arrival is the snap rule on the tick the goal is within one step, and a
push or the slide can leave the arrived unit off the goal. No decision changes.

Status note (2026-10-19, P26u docs, from P37b as merged, #101): the lead's decisions of
2026-10-15 refine §2 and §3; the dated inline notes in §2 ("Field following" and "Stall") and §3
(at "Cache" and at the `ATTACK` fields bullet) give them in full. In short: the field key is the
group target (the new row column `group_cell`), else the unit's own goal tile; a unit whose slot
the group field does not reach takes its own goal's field when the group field names no next
tile, and so does an `ATTACK` unit that has outrun its field; a blocked key tile counts as no
next tile; a `FIELD` unit whose field names no next tile stalls at any distance. The accepted
text stays as written; where it differs, the notes win.

## Context
ROADMAP Phase 2 asks for "movement with flow fields and separation". Phase 1 moves units in
straight lines to formation slots with no terrain and no collision (ADR 0003 §4-5), and its
tests pin exact positions tick by tick on an open map. `rts-sim-conventions` asks for:
- passability per movement class;
- integer flow fields per (target cell, class), cached and shared by a group;
- separation through a spatial hash processed in id order.

ADR 0002 §5 says Phase 2 replaces the view-only test map with sim map data. GDD maps are 56x56
to 64x64 tiles with chokepoints.

Measurements (Godot 4.7.2 headless, 2026-10-11, Xeon cloud VM; mock code, not the real sim):
- **Dijkstra (Dial's buckets) over 64x64 cells, 8 neighbours:**
  - 17 to 20 ms with array literals in the loop;
  - 3 to 4 ms with constant offset arrays and a grid padded by one blocked cell;
  - in 1024-cell slices: 0.24 ms setup, then 1.1 to 1.5 ms per slice (plan review).

  On a phone that is roughly 2 to 4 times slower, so a slice must stay well under 1024 cells.
- **Separation for 150 packed units:**
  - 2-tile cells, 3x3 scan: 1.3 ms per tick;
  - 1-tile cells, 3x3 scan, stopping at 8 neighbours: 0.23 ms.
- **Grid rebuild for 150 units, both grids (64x64 and 16x16 cells):** a counting sort with a
  per-cell prefix sum costs 0.32-0.40 ms, because it walks every cell. Linked lists (`head` per
  cell, `next` per row) that reset only the cells occupied last tick cost 0.046 ms (plan review).
- **Target scans for a fifth of the units per tick, 6-tile acquire range:**
  - 2-tile grid (7x7 cells): 0.43 ms;
  - 4-tile grid (5x5 cells): 0.09 ms.
- **Line checks** (supercover over a few tiles): about 6-7 µs each, so 150 at once cost about
  1 ms.
- **Whole optimised mock tick** (grids, flow lookup, separation, integration, targeting, fog):
  0.7 ms mean, 1.25 ms p95, over 900 ticks with 150 units.
- **Separation against the Phase 1 tests** (plan review prototype on `controls_test`, 30 tanks):
  with any idle share above 0, tanks arriving later shove settled idle tanks off their slots.
  At tick 450, 26 of 30 tanks were off their slot and 28 pairs were closer than the 1200
  formation spacing (minimum 801, just above the 800 radii sum). Only share 0 kept every slot.

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
  per tile into `world.terrain` and the cost per class into `world.move_cost`. A hand-built
  `World.new()` is open grass sized from `map_w`/`map_h` (ADR 0007 §2).
- A cell index is `(y / 1000) * map_cols + x / 1000`, for positions clamped to `[0, map_w - 1]`
  and `[0, map_h - 1]`. Collision is by unit centre: a unit may stand on a tile only if its
  class cost there is above 0.

  Status note (2026-10-14, P26p docs, from P37a as merged, #86): **the tile of a point.** A point
  is in the tile `World.cell_of` gives it, which clamps the tile, not the position:
  `clampi(x / MILLI_PER_TILE, 0, map_cols - 1)` and `clampi(y / MILLI_PER_TILE, 0, map_rows - 1)`.
  So a tile is half-open, and in the words of `FixedMath.line_clear`'s header: "its left and top
  edge belong to it, its right and bottom edge to the next tile, and the far edge of the map to
  the last tile". `line_clear` and `Formation`'s slot check read a point by the same rule
  (`Formation._slots`: "a point on the far edge of the map belongs to the last tile").
- `map_version` increments whenever passability changes (buildings in Phase 3). Phase 2 maps are
  static, and tests change a tile through `World.set_terrain(cell, index)` to prove
  invalidation.

### 2. Orders, slots and navigation modes
- Formation slots stay as in ADR 0003 §4, with one addition: a candidate on a tile that is
  blocked for any movement class in the group is skipped. A target point on a blocked tile first
  moves to the centre of the nearest tile that is passable for every class in the group: rings of
  tiles around it, row by row, first hit wins. `Formation.assign` calls `world.prepare()` first
  (one bool check), because Phase 1 tests call it on an unprepared hand-built World whose
  `type_move_class` and tile grid exist only after `prepare()`.

  Status note (2026-10-14, P26p docs, from P37a as merged, #86): **blocked for the group, and the
  moved target.** A tile is blocked for the group when any move class in the group is blocked
  there: `Formation.assign` collects one offset into `move_cost` per class of the group, and a
  tile is open only if no class has cost 0 there (`_slots` tests `cost[base + cell] == 0` for
  each offset). The target moves by `Formation._open_centre`: "the centre of the nearest open
  tile whose centre is in the box [low, high]: rings of tiles around the point's tile, each ring
  row by row (j, then i, ascending), and the first hit wins". The box is the target clamp, the
  map inset by the largest radius in the group, so "the slot lattice always starts inside the
  box"; when no such tile is open, the clamped point stays. "Nearest" in this section means the
  first hit of that ring order. Only a cost of 0 blocks; tiles of cost 20 and 40 keep the target
  and their slots.
- Each moving unit has a `nav_mode`:
  - `DIRECT`: steer straight at the goal. This is Phase 1 movement.
  - `FIELD`: follow a flow field.
  - `HOLD`: no intent; set by combat (ADR 0009).
  - `CHASE`: steer straight at a target; set by combat only while the line to it is clear
    (ADR 0009 §3).
- **Line check.** A unit tests the tile line from its position to its goal: an integer
  supercover traversal of every tile the centre segment touches, all of them passable for its
  class.
  - **When:** a new order sets `DIRECT` and marks the line unchecked (`nav_cell = -1`). The unit
    checks on its first tick where `(tick + id) % line_check_period_ticks == 0` (rules, 5), so a
    150-unit order spreads its line checks over 5 ticks instead of one. Until then it steers
    `DIRECT` and slides (section 4). On an open map the check always passes, so positions are
    exactly Phase 1's.
  - Line clear: `DIRECT`. In a static map a clear line stays clear, so the unit never checks
    again.
  - Line blocked: `FIELD`, with the field of (goal tile of the group target, class) from the
    flow cache. While that field is not complete, the unit steers `DIRECT` and slides.
  - A `FIELD` unit repeats the line check each time it enters a new tile (`nav_cell`). As soon
    as the line is clear it switches to `DIRECT` and sets `field = -1`. This is any-angle
    path smoothing at the cost of about one line check per unit every 8 ticks.

  Status note (2026-10-14, P26p docs, from P37a as merged, #86): **the tiles a line touches.**
  `FixedMath.line_clear(world, x0, y0, x1, y1, move_class)` reads each end point in the tile §1's
  status note gives it ("Points are milli-tiles and are clamped into the grid") and tests every
  tile the segment touches under that rule: "The segment touches the tiles of its points, and
  where it crosses a tile corner exactly (the corner is between its ends, and the segment is along
  no axis) it also touches the two tiles beside the corner, which keeps the flow field's rule
  against cutting a corner" (§3: no diagonal step past a blocked orthogonal neighbour). "A
  segment along an edge touches the tiles on one side only": the tile the edge belongs to, which
  is the tile on its right (a vertical segment) or below it (a horizontal one), and the last tile
  on the far map edge. So "a goal on an open tile is in reach of a clear line from every point of
  its tile", and a unit standing on a rock tile's left or top edge is inside that tile, so its
  line starts blocked. It reads the grid "like World.is_passable: true while no map is loaded,
  false for a class that does not exist".
- On an open map every line is clear. No field is ever computed, and Phase 1 movement stays
  exactly as it is.
- **Field following:** the unit steers towards the centre of the neighbour tile with the lowest
  integrated cost. That is any-angle steering from its real position, not an 8-way snap. The
  neighbour is looked up with `FlowField.best_neighbour(cell)` only at event cadence (ADR 0007
  §1): when the unit enters a new tile (together with its line re-check) and on the first tick
  its field is complete. The result (a plain cell, -1 at the goal or when unreached) is stored in
  the row column `nav_next` (hashed, -1 at spawn and on every new order), and the steering of
  the ticks in between reads only that column. No per-tick call and no per-row aliasing of a
  field's array is needed.

  Status note (2026-10-19, P26u docs, from P37b as merged, #101): **where and when.** FIELD
  following, the stall and the `ATTACK` re-key run in INTEGRATE (`Movement.integrate`, ADR 0013
  §1): following and the re-key at event cadence, the stall on every tick of a unit that tracks
  it; `Movement.run` (INTENTS) keeps the steering, the line checks and the first acquire of a
  blocked line. `nav_next` has two "none" values: -1 = not looked up yet (a pending field or a
  new order), and `Movement.NO_NEXT` (-2) = looked up, and the complete field names no next tile
  (the goal tile, or ground the field does not reach), so such a unit does not ask
  `best_neighbour` on every tick. Besides the tile entry and the first complete tick, `nav_next`
  is also refreshed on the unit's line-check turn (`(tick + id) % line_check_period_ticks == 0`),
  so a field re-integrated after a map change sends the unit on within a period. A next tile that
  equals the field's key and is blocked for the unit's class counts as no next tile (the
  blocked-key rule, §3's note). A `DIRECT` step that the slide refuses entirely (no x move, no y
  move) unchecks the line (`nav_cell` -1), so the next turn checks it again: truncated steps do
  not follow a shallow clear line.
- **Steering:** `FixedMath.step_toward(x, y, tx, ty, speed)` (truncating, ADR 0003 §5), one
  `isqrt` per moving unit per tick. `isqrt` currently costs about 2 µs. The movement PR may
  replace its body with a faster exact method (for example Newton's method from a bit-length
  guess). The existing exhaustive `isqrt` test proves it is still exact.

  Status note (2026-10-14, P26p docs, from P37a as merged, #86): `isqrt` is now "Newton's method
  from above: a power of two at or over the root, found from the bit length of n, then x = (x + n
  / x) / 2 until it no longer falls, which ends on the floor"; about 3 times faster than the old
  digit method (0.37 µs against 1.15 µs in #86), with identical results and the exhaustive tests
  unchanged.
- **Arrival:** snap to the goal when `d2 <= speed * speed` (v0).

  Status note (2026-10-14, P26s docs, from P37a2 as merged, #94), the text above stays as
  accepted: the snap is the intent, not a position write. `Movement.run` gives a unit whose aim
  is within one step the exact rest (`d2 <= speed^2`), and `Movement.integrate` ends the order on
  that tick ("a unit that steered at its goal (not in HOLD or CHASE) with an order other than
  ATTACK arrives on the tick its goal is within one step at the start of the tick"): `order`
  `IDLE`, `nav_mode` `NONE`, `nav_cell` -1, "also when a push or the slide kept it off the goal
  itself". So the unit lands on the goal only when no push and no slide move it; the order ends
  either way. `HOLD` and `CHASE` units never arrive, and `ATTACK` keeps its order (P41 ends it).
  The destination-tile rule of §4 holds as written: only the new point's tile is tested (so a
  diagonal step may pass between two blocked orthogonal neighbours, which a test pins, as the
  Consequences ask), and a unit that started on a blocked tile may move to a passable one.
- **Stall:** a moving unit tracks `best_dist`, its smallest distance to the goal so far (a plain
  distance in milli, at most about 91 000 on a 64x64 map, so int32 is safe). If that does not
  improve for `stall_ticks` (rules, 15) while the unit is within `stall_range_spacings` (rules, 2)
  formation spacings of its goal, the unit goes `IDLE` where it stands. A crowd around a slot
  then ends instead of jittering forever.

  Status note (2026-10-19, P26u docs, from P37b as merged, #101; the lead's decision 3 of
  2026-10-15): a `FIELD` unit whose field names no next tile (`nav_next` `Movement.NO_NEXT`)
  stalls at any distance, not only within `stall_range_spacings`, so a unit that cannot reach
  its goal gives its slot back after `stall_ticks` without progress. A `DIRECT` unit stalls as
  written: with a checked line, within `stall_range_spacings` times its type's formation spacing.
  `ATTACK` units, units of speed 0 and units waiting for a field or for a slot do not stall. The
  stall sets the goal to the unit's position and its intent to 0, and `Movement._end_order` ends
  the order (also on arrival), clearing `group_cell`, the navigation state, `field`, `best_dist`
  and `stall`.
- FixedMath gains no sine table and no `dir_to` in Phase 2: no sim rule needs a direction (there
  is no facing; turret aim is view-only). They come with the first rule that needs facing.

### 3. Flow fields and the cache
- `FlowField` (`game/sim/FlowField.gd`) runs an integer Dijkstra with Dial's buckets:
  - 8 neighbours: orthogonal cost = terrain cost, diagonal = terrain cost x 14 / 10;
  - no diagonal step past a blocked orthogonal neighbour (no corner cutting);
  - the grid is padded by one blocked ring, and the offset arrays are constants. `cost` and
    `next` are indexed by the **padded** cell `(ty + 1) * (cols + 2) + tx + 1`, so they hold
    `(cols + 2) * (rows + 2)` entries; `begin`, `best_neighbour` and the cache take and return
    plain cells (`ty * cols + tx`), and only `FlowField` itself converts;
  - the buckets are preallocated rings, so integrating allocates nothing after the first field;
  - unreached cells hold `UNREACHED = 0x3FFFFFFF`.
- **Double buffer.** Each field has `cost` (served to units) and `next` (being integrated). A
  first integration fills `next` and swaps on completion, and until then `complete` is false.
  A re-integration after a map change also fills `next` while units keep reading the old
  `cost`, and swaps on completion. About 2 x 4356 x 4 bytes per slot on 64x64 (280 KB for 8
  slots).
- **Time-sliced:** `FlowCache.advance(budget)` settles at most `flow_cells_per_tick` cells per
  tick, over one field at a time, in request order. The rule value starts at 512 and is set from
  the P26s probe so that a slice costs at most about 0.5 ms on a 2021 phone, which is 0.2 ms on
  the gate phone with k = 2.5 (ADR 0011 §5). A 64x64 field completes in about 8 ticks (0.5 s)
  at 512, and proportionally later at a smaller value. Units steer `DIRECT` until then. The
  slicing counts cells, not time, so it is deterministic.
- **Cache:** `flow_cache_size` (rules, 8) slots, keyed by (goal cell, class, `map_version`).
  - **References are derived, not maintained.** At the start of `advance`, the cache recounts
    each slot's references from the World's `field` column in one pass over the rows. No code
    path has to release a field: a new order, `STOP`, arrival, stall, a line-clear switch, an
    `ATTACK` re-key, target loss and death simply stop pointing at the slot (death removes the
    row). A leak cannot exist.
  - Each slot has a last-used tick. A request for an existing key shares the slot. A group order
    shares one field per class.
  - A new key takes a free slot, else the least recently used slot with no references (ties go
    to the lower slot).
  - If none exists, the request returns -1 and the unit stays `DIRECT`.

  Status note (2026-10-13, P26i, a decision of the lead after the P30b review): references stay
  derived, and `acquire()` adds a provisional one. The recount is `FlowCache.recount(field_column,
  count)`, which `FlowCache.run` calls before `advance` (P30n). A unit stores the slot in its
  `field` column only after `acquire()` returns, so a slot handed out since the last recount
  would read as unreferenced, and a second new key in the same tick could take it while a unit
  already points at it. `acquire()` therefore counts the slot it hands out (a new key's, or a
  shared one's) as referenced until the next `recount()`, which overwrites every count from the
  rows; two new keys in one tick never share a slot. `FlowCache.gd` (P30b, #58) does this.

  Status note (2026-10-19, P26u docs, from P37b as merged, #101): **the key** ("A group order
  shares one field per class", and §2's "goal tile of the group target"). The lead's decision of
  2026-10-15, after the architect's and gameplay-dev's evaluations: the key is the group target,
  the row column `group_cell` (a cell, -1 = none, -1 at spawn), else the unit's own goal tile.
  `Formation.assign` writes the cell of the group's centre into every row of a `MOVE` or
  `ATTACK_MOVE` command; `Sim._apply_attack`, `Sim._apply_stop` and `Movement._end_order` write
  -1, and `Movement.reset_nav` leaves it. A blocked line (`Movement._check_line`) of a unit with
  no field asks the cache for (`group_cell`, class), else (the cell of the unit's goal, class); a
  `FIELD` unit re-checking its line keeps the field it follows. One `acquire`, and with
  every slot referenced the unit stays `DIRECT` and asks again on its next turn. The column is
  hashed. Formation slots lie on different tiles, so a key per slot would take one field per
  unit from a cache of 8.
  - **The own field.** A unit whose slot the group field does not reach takes its own goal's
    field when the group field names no next tile (`Movement._take_own_field`: a complete field
    keyed on a tile other than the cell of the unit's goal), with a fresh `best_dist`
    (`FlowField.UNREACHED`) and `stall` (0), so the ticks it counted on the group field do not
    end the new one. With every slot referenced it keeps the old field and asks again at its next
    event.
  - **The blocked key.** A next tile that equals the field's key and is blocked for the unit's
    class counts as no next tile (`Movement._refresh_next`): the field seeds its key at cost 0
    whatever the terrain, so after `set_terrain` on the key tile (later a building)
    `best_neighbour` keeps naming it. A unit with a reachable goal then takes its own field, and
    a unit whose goal is the key stalls (§2's note) and frees the slot. Only the key counts:
    another blocked tile keeps the old field until the cache swaps the new one in.
  - **Accepted behaviour.** With every slot referenced, a unit whose slot the group field does
    not reach can end `IDLE` through the stall short of a reachable slot (maze fuzz in the lead's
    brief: 55 of 5,600 units at 8 slots, 28% rock).
- **Invalidation:** when `map_version` changes, slots with references re-integrate into `next`
  (double buffer, so units keep following the old costs until the swap), and slots without
  references are dropped.

  Status note (2026-10-13, P26i, a decision of the lead after the P30b review): **who calls it.**
  `World.set_terrain()` calls `flow.invalidate(map_version)` right after it bumps `map_version`,
  once the World is prepared. `FlowCache.run` (P30n) does not call `invalidate()`. The reason:
  `COMMANDS` run before `FLOW`, so an `acquire()` under the new version can happen before any
  `FLOW` phase; invalidating at the change keeps one slot per key (a slot still holding the key
  under the old version would otherwise stay beside a new one). An unreferenced slot is dropped,
  which also spares a slot handed out since the last recount, because its provisional reference
  counts. P31a implements the call.
- The cache is derived state and is not hashed (ADR 0007 §8). It changes behaviour only through
  "complete or not", which follows the command history deterministically.
- Fields for `ATTACK` orders are keyed on the target's tile when the order is applied. They are
  re-keyed if the target moves more than `attack_rekey_milli` (rules, 4000) from that goal while
  the line stays blocked.

  Status note (2026-10-19, P26u docs, from P37b as merged, #101): an `ATTACK` unit has no group
  cell, so it keys on the target's tile at its first acquire (its goal follows the target), and
  re-keys in INTEGRATE (`Movement._rekey`, at the `nav_next` events of §2's note) once its goal is
  more than `attack_rekey_milli` from the centre of the key tile; with no free slot it keeps the
  old field. LEAD DECISION (2026-10-15): `Movement._take_own_field` also re-keys an `ATTACK`
  field that names no next tile (a unit that outran its field, the key tile still within
  `attack_rekey_milli` of the goal), a second trigger besides `attack_rekey_milli`, kept because
  the unit would otherwise stand idle on a tile the target has left. `ATTACK` units never stall
  (§2's note).

### 4. Separation and sliding
- `SpatialGrid` (`game/sim/SpatialGrid.gd`) is a linked-list bucket grid: `head` per cell (-1 =
  empty), `next` per row, and a list of the cells occupied in the last rebuild. A rebuild resets
  only those cells and inserts rows in descending order, so each cell lists its rows in
  ascending id order. It costs O(units), not O(cells), and allocates nothing after `configure`.
  - the separation grid has 1-tile cells (every unit radius is at most 500, so contact pairs are
    always in the 3x3 neighbourhood);
  - the targeting grid has 4-tile cells (ADR 0009).
- For each unit in id order, scan the 3x3 cells row by row:
  - Look at most at `separation_scan` (rules, 16) other units and use the first
    `separation_neighbours` (rules, 8) that overlap (`d2 < R * R` with `R = r_i + r_j`).
  - The pair push is sqrt-free: `(dx, dy) * (R*R - d2) / (2 * R*R)`, truncated toward zero per
    axis. Its length is `d * (R*R - d*d) / (2 * R*R)`: 0 at `d = 0`, largest near `d = 0.58 R`
    and 0 again at contact. It is therefore weak when the units nearly coincide, and integer
    truncation makes it 0 for pairs only a few milli apart.
  - **Near-coincident pairs** therefore use a fixed push instead. With
    `C = R / separation_coincident_divisor` (rules, 4; 200 for two tanks, 150 for two squads), a
    pair with `d2 * divisor * divisor < R * R` (closer than `C`) gets the pair push
    `min(C, separation_push_max)` on each axis where `dx` or `dy` is not 0, signed away from the
    other unit. A pair on exactly the same point gets it along x only, the lower id towards -x.
    With the starting values that is 60 per tick for the pair (30 each when the shares are
    equal), and at `d = C` the formula takes over with a larger push (93 for two tanks), so no
    distance below contact has a zero push except through truncation right at contact.
  - Shares: two units in the same state split the push 50/50. An idle unit next to a moving one
    takes `separation_idle_share` percent (rules, 75), so moving units shoulder through idle
    ones.
  - Each unit's summed push is clamped to `separation_push_max` (rules, 60 milli per tick) per
    axis.
- Pushes are accumulated into the World's `push_x`/`push_y` scratch arrays for all units before
  any unit moves (Jacobi style). The result does not depend on which unit was processed first,
  except through the neighbour caps, and those follow the id order of the scan.
- All units separate, including enemies and idle units. Projectiles do not.
- **Consequence for Phase 1's pinned results (decided):** an idle unit has no force pulling it
  back to its slot, so a moving group shoves units that already settled. The idle share stays
  75, because an idle share of 0 would let idle units block corridors and gaps (and it would not
  save the Phase 1 view tests below, where the moving tank itself is deflected). Separation does
  not move units that stand on distinct slots at the Phase 1 spacing (1200 > the 800 radii sum),
  but moving units push them. Every Phase 1 test that runs two or more ticks with more than one
  unit was audited (plan, "File ownership"); the assertions that change, with the reason in the
  PR:
  - `test_controls_flow` (qa-owned) and `test_player_controller` (touch-ux-dev's; the same order),
    each a one-line named exception in the PR that puts separation into the tick (P39b): the
    bound "every pair at least the formation spacing apart" becomes "every pair at least 90% of
    the radii sum apart" (no visible overlap). The centre bounds stay (prototype maximum 3794
    against 3795-3800);
  - `test_sim_step` (gameplay-dev's own): "all 40 rows idle at tick 150" moves to the tick
    measured in the PR (prototype: 155), with distinct positions and the same 90% pair bound;
  - `test_unit_layer` (touch-ux-dev's): two cases drive tank 1 through or next to the block. Its
    owner re-aims them, before separation lands (P40), to corner tanks whose paths stay more than
    800 milli from every other unit, with the same headings and arrival ticks.
- **Integrate and slide:**
  - The new position (intent + push) is clamped to the map.
  - If its tile is blocked for the unit's class, try the x move alone, then the y move alone,
    else stay.
  - A unit that started on a blocked tile (only possible after `map_version` changes) may move
    anywhere passable.

### 5. Rules data
`data/rules.tres` (`RulesDef`) holds every tuning number of this ADR:
- `line_check_period_ticks` 5;
- `flow_cells_per_tick` 512, `flow_cache_size` 8;
- `separation_neighbours` 8, `separation_scan` 16, `separation_idle_share` 75,
  `separation_push_max` 60, `separation_coincident_divisor` 4 (sets the near-coincident distance
  `R / divisor` and caps that push at `min(R / divisor, separation_push_max)`);
- `stall_ticks` 15, `stall_range_spacings` 2;
- `attack_rekey_milli` 4000.

ADRs 0007, 0009 and 0010 add to the same file. No such number is a constant in code (CLAUDE.md
rule 5).

## Consequences
- Phase 1's straight-line behaviour is the special case "line clear". The Phase 1 movement tests
  and the controls map keep passing through the movement PRs, as long as the controls map keeps
  the area that those tests use free of blocked tiles (the plan's P48 constraint). Separation
  changes two pinned results on purpose (section 4).
- Flow fields cost time only when a line is blocked, and then at most `flow_cells_per_tick` cells
  per tick. The cost of an order no longer depends on the map size, and its line checks are
  spread over `line_check_period_ticks`.
- The tick grows with crowding, not with the map: separation is bounded by
  `separation_scan * units`, and the grid rebuild by the unit count. The perf test asserts these
  bounds through the World's cost counters.
- Centre-based collision lets a large unit's art overlap rock by up to its radius. That is
  acceptable top-down, and the art keeps shadows small.
- Chasing (ADR 0009 §3) steers straight only while the line to the target is clear. Otherwise
  the unit keeps its order's path, so units do not press into rock at a ridge.
- Diagonal movement past corners and the sqrt-free push are approximations. They are pinned by
  tests, so a later change is visible.
- `rts-sim-conventions` says "cell = 2 tiles" and promises a sine table. Those lines change in
  P26 (plan, "P26").
