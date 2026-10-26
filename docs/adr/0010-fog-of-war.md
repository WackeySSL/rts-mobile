# ADR 0010: Fog of war (sim grids, update cadence, rendering)

Status: accepted, 2026-10-12 (Michael). Proposed 2026-10-11 (revision 5 after the five-lens plan review and three completeness checks, same day).

Status note (2026-10-12): §1-2 partly superseded by ADR 0012 §3, where the view reads the fog and
its dirty lists from the World: it reads them from `runner.snapshot.fog`.

Status note (2026-10-13): §1's stamping order is amended (the new disc before the old one); see the
status note under "Stamping" in §1.

Status note (2026-10-21, P26ac docs): §1 carries a dated status note on P46 (#129) as merged:
where the sim clears a dirty list (`FogUpdate.begin` before `remove_dead()`), the masks one per
type plus a pad mask, and the stamping as merged; no accepted text changed.

Status note (2026-10-21, P26ad docs): §2 carries a dated status note on P47 (#136) and P47p (#137)
as merged: the rebuild triggers beyond a new match and an overflow, the sync in `_process` next to
`ticked`, the hiding rule of every draw layer and of picking, and the lead's decision that the
death of an own unit always shows; no accepted text changed.

Status note (2026-10-21, P26ae docs): §1 carries a dated status note on its "Users" as P46b
(#144) merged them (target acquisition and `ATTACK` validation read the fog through
`Targeting.sees`) and on rows added after `prepare()`; no accepted text changed.

Status note (2026-10-22, ADR 0016 accepted): §1 and "Consequences" carry dated status notes on
ADR 0016's decision that P65 will take `visible` out of `FogGrid.HASHED`; no accepted text
changed.

Status note (2026-10-22, P68b docs; ADR 0017 accepted 2026-10-22): §1 carries a dated status note:
the per-player last-seen building memory lives in the World (ADR 0017 §3, `GHOST_ARRAYS`), not in
`FogGrid`, and `PlayerView` arrives in plan row P78 (ADR 0020 §1); no accepted text changed.

Status note (2026-10-26, P68d docs; ADR 0022 accepted 2026-10-26): §2 carries a dated status note:
the fog layer moves under the building roofs, bars, projectiles and effects (z 110), and a tracer is
drawn clipped to the seen tiles (ADR 0022 §2, §4); no accepted text changed.

Status note (2026-10-26, P68e docs; ADR 0023 accepted 2026-10-26): §2 carries a dated status note:
in the isometric view the fog lies on the ground at z 4, as diamonds under every object, and
last-seen enemy buildings draw at z 5 with one dim; ADR 0022's z 110 does not come. No accepted
text changed.

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
    (counts - 1), stamp the new one (counts + 1, explored = 1). (Order amended 2026-10-13, see
    the status note below.)
  - `remove_dead()` unstamps a dying row at once, so a dead scout's vision ends that tick.
  - A row added later is stamped at its player's next update.

  Status note (2026-10-13, P26h, after the P32f review): an update re-stamps a moving row by
  stamping the new disc (counts + 1, explored = 1) **before** it unstamps the old one
  (counts - 1), so only the cells that really change flip and are listed in the dirty list
  (the symmetric difference of the two discs instead of their union). For a 6-tile disc (sight
  6000, 113 cells) moving one tile along a row or a column that is 26 listed cells instead of
  126 (P32f's `test_a_cell_is_listed_once_per_update_in_either_stamp_order`, cell 465 to 466 on
  a 30 x 30 map); a diagonal one-tile step lists 34 instead of 130. The final counts and
  `explored` are identical in either order. The lead proposed it; Michael answered "ja"
  (2026-10-13). `remove_dead()`'s unstamp of a dying row stays as it is. The plan's row P46
  (the fog update) carries it.
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

Status note (2026-10-21, P26ac docs, after P46, #129; the text above stays as accepted): §1 as
merged in `game/sim/FogUpdate.gd`, `World.gd` and `Sim.gd`.
- **Where the sim clears a dirty list.** "The sim clears a player's list at the start of that
  player's update" holds in this form: `FogUpdate.begin(world)` empties the list of each player
  whose turn it is right before `remove_dead()`, and `FogUpdate.run(world)`, the update, runs
  after it. A death on the owner's own update tick therefore stays listed (its unstamp's flips
  are added after the clear), where a single clear inside the update would have dropped them
  (one in three deaths with a period of 3) and left those cells visible in the view. Pinned by
  `test_the_cells_of_a_death_on_the_owners_update_tick_stay_listed`. Each player's first update
  (player 1 at tick 0, player 2 at tick 1) empties the list that the initial stamp of
  `prepare()` filled.
- **Sight masks.** One mask per type in type order (a mask id is the type index; two types of
  equal sight repeat their mask) and one last pad mask of sight 0 for a type with no entry, so a
  World has `mask_start.size()` = types + 1 and a row's mask is `mini(type_index,
  type_sight.size())`; not "one per distinct `sight_range`" as above. The disc rule (tile centre
  to tile centre, row spans clipped to the map) is unchanged.
- **Stamping and cadence** as above and as the status note of 2026-10-13 amends it: the new
  disc before the old one, only for a row whose cell changed, a row added later (`fog_cell`
  -1) stamped at its player's next update; `remove_dead()` unstamps only with a map and a
  stamped row. The period is read as `maxi(fog_period_ticks, 1)`. `stats[FOG_CELLS]` counts the
  cells the update's stamps cover, not the initial stamp or a death's unstamp.
- The plan's contract row `FogUpdate` and its section P46 "As merged" hold the details.

Status note (2026-10-21, P26ae docs, after P46b, #144; the text and the note above stay as
accepted and as dated): the two Phase 2 "Users" as merged.
- **Target acquisition and `ATTACK` validation** read the fog through `Targeting.sees(world,
  player, x, y)`: the cell by `World.cell_of`'s rule on the fog's own sides, visible when the
  count at `(player - 1) * cells + cell` of `fog.visible` is above 0. `Targeting.run` inlines it
  on the aliased array (a candidate, a held target on the row's turn, an `ATTACK` lock on every
  tick); `Sim._enemy_target` calls it, so an `ATTACK` on an unseen enemy is dropped and counted.
  Owner 0, an owner past `player_count` and a fog whose sides do not make its cells see every
  cell (the lead's decision of 2026-10-21). ADR 0009 §2's note of P26ae docs.
- **Rows added after `prepare()`** stay unstamped (`fog_cell` -1) until their player's first
  update, as the note above says, so under the vision rule their player sees nothing through
  them before then. Tests that act from tick 0 stamp the fog or reveal it; the shared test
  builders reveal it by default (the plan's contract row `World` v1, "P46b as merged").
- The ROADMAP box "Fog of war (visible and explored) and its rendering" was ticked by P46b.

Status note (2026-10-22, ADR 0016 accepted; the text and the notes above stay as accepted and as
dated): ADR 0016 (Michael's answer 1) decides that P65 will take `visible` out of the hash; until
it merges, the text above describes `main`.
- After P65, `const HASHED` will be `[&"explored"]` and `visible` will join `UNHASHED`.
  `visible` stays sim state with the same layout, rules and users; only the state hash stops
  covering it directly (ADR 0007 §8's note of the same date).
- Why: the counts are derived from hashed state (`owner`, `type_index` and `fog_cell` in the
  rows, the sight tables in `defs_hash`), and they are most of the bytes hashed every checkpoint.
- `explored` is history, not derived, and stays hashed. The per-player last-seen memory that
  Phase 3 adds is history too, so it "will live inside `FogGrid` and be hashed" as written.
- `FogGrid.copy_into` duplicates every array of `HASHED` and `UNHASHED`, so the snapshot keeps
  `visible`.

Status note (2026-10-22, P68b docs, ADRs 0017 and 0020 accepted; the text and the notes above stay
as accepted): P65 merged as 757b5f9 (#163): `FogGrid.HASHED` is `[&"explored"]` on `main`. ADR
0017 §3 supersedes one point of this section, where the last-seen memory lives: it is history and
hashed as written, but it lives in the World's `GHOST_ARRAYS` (`ghost_id`, `ghost_type`,
`ghost_owner`, `ghost_cell` per player up to `ghost_cap`, and `ghost_count`; the `ghosts` hash
section, live entries only), not inside `FogGrid`. The records are per building, not per cell, and
keeping them out of `FogGrid` leaves the FOG kernel's checked list as it is. The MEMORY phase
(id 13) updates them on each player's fog turn (plan row P77). `PlayerView`
(`game/sim/PlayerView.gd`, pure) arrives in plan row P78 with the shape §1 reserves (ADR 0020 §1),
and the scan over `game/ai` in P78q.

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

Status note (2026-10-21, P26ad docs, after P47, #136, and P47p, #137; the text above stays as
accepted): §2 as merged in `game/view/FogLayer.gd`, the other draw layers, `game/input/` and
`scenes/main.tscn`.
- **Draw order.** `scenes/main.tscn` sets `z_index = 140` and `z_as_relative = false` on the
  `FogLayer` node, with its `runner` path; the script sets no z, so another scene that uses the
  layer (the perf arena) sets them on its own node.
- **Updates.** The layer syncs in the `ticked` handler and also in `_process`, because a new
  match's tick-0 snapshot comes with no `ticked`. Beyond "a new match (`runner.match_serial`
  changed) or when the dirty list overflowed", a full rebuild also comes at the start of a match
  (the first snapshot the layer sees), for another local player and for another `explored_alpha`;
  and, when `version_of(local_player)` has changed, for a gap in the ticks (a snapshot whose tick
  is not the one after the last the layer looked at). Otherwise a changed version patches the
  cells of `dirty_cells(local_player)`, and an unchanged one does nothing; each rebuild or patch
  is uploaded. With no grid for the local player (no map, or a player past `fog.player_count`)
  the layer draws nothing. The update time is `last_update_usec()`, kept until the next update,
  so a sampler takes one reading per update, on a frame where `upload_count()` rose.
- **Hiding.** One test of a tile for every layer and for picking, in `FogLayer`'s statics
  `local_player_of`, `covers` and `is_seen`, with the cell from `snapshot.cell_of` at the
  position of the tick; a local player the fog has no grid for sees everything. A unit of any
  owner but the local player (a neutral owner 0 included) is hidden on a tile the local player
  does not see: `UnitLayer.is_shown(row)` decides a rig (hiding sets only `visible`),
  `HealthBarLayer` draws a bar only where `is_shown`, and `UnitLayer.fill_pick_snapshot` marks
  such a unit unpickable (`PickSnapshot.pickable`). `ProjectileLayer` skips every projectile on
  an unseen tile, whatever its owner. `EffectsLayer` filters each effect as it is born, whatever
  its owner: an impact by its landing tile, a muzzle flash by the shooter's tile, a tracer when
  either end is seen (as above) and a death by its tile, with the one exception below.
- **An own unit's death always shows** (the lead's decision, 2026-10-21): its sight ends that
  tick (`remove_dead()` unstamps it, §1), so its own tile can be dark in the very tick it dies,
  and the death burst is shown whatever the fog says. A neutral death in the dark does not show.
- **`reveal_enemies`** is an export of `UnitLayer`, `ProjectileLayer` and `EffectsLayer`, as
  above; besides the perf arena, tests whose subject is not fog set it (the two Phase 1 enemy-tap
  cases and seven Phase 2 view suites; the plan's second audited table).
- The plan's contract rows `FogLayer`, `UnitLayer` v2, `HealthBarLayer`, `ProjectileLayer`,
  `EffectsLayer` and `PickSnapshot`, `Picker`, and its sections P47 and P47p "As merged", hold
  the details. The look (the fog colour, the soft edge, alpha 140 on the phone, an own unit's
  death on a dark tile) is recorded there as follow-ups for the art lens; STYLE.md is unchanged.

Status note (2026-10-26, P68d docs, ADR 0022 accepted 2026-10-26, Michael's "ja til anbefaling";
the text and the notes above stay as accepted and as dated): ADR 0022 §2 supersedes the draw order
above ("projectiles and effects, **fog**, then move and target markers") and the note's
`z_index = 140`. From plan row P84 on, the fog layer draws at **z 110**: over the unit bands and the
base parts of buildings (z 2), under the building roofs (z 111), the health bars (z 112),
projectiles (120), effects (130), the placement ghost (145), the rally flags (146) and the markers
(150), in `scenes/main.tscn` and `scenes/dev/perf_arena.tscn`. A roof carries its footprint's fog
state as its quad colour (ADR 0022 §4). Bars, projectiles and effects keep their hiding by tile
(the "Hiding" item above), but the fog no longer darkens them at the edge of vision, and an own
unit's death burst is no longer dimmed on its dark tile. **Tracers:** the "either end" rule of the
2026-10-21 note stays as the birth rule (a tracer is added when either end is seen); since the fog
no longer covers the effects, a tracer with one end seen is drawn clipped to the seen tiles, from
the seen end to the last point on a seen tile, found at birth in 16 px steps (ADR 0022 §4, P84),
and one with both ends seen is drawn whole. The texture, its updates, `explored_alpha` and the
soft one-tile edge are unchanged.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26, Michael's answer 7 "ja"; the
text and the notes above stay as accepted and as dated): ADR 0023 §2 supersedes the P68d note's
z 110 and roof colour (ADR 0022 is superseded and plan row P84 retired). From plan row P117 on,
`FogLayer` keeps its texture (one RGBA8 texel per cell, linear filtering, alpha 255 /
`explored_alpha` / 0, the dirty-list patching) and draws it under a `Transform2D` whose axes are
(32, 16) and (-32, 16) px per texel, so each texel is a diamond, at **z 4**: over the terrain, the
decals, the unit shadows and the selection rings, under every object (`WorldSort`, z 10), the
bars (30), projectiles (40), effects (50) and markers. Objects carry no fog of their own: enemy
rigs, buildings, bars and projectiles are drawn only where the local player sees them (the
"Hiding" item above, unchanged); a building partly in vision is drawn whole; last-seen enemy
buildings draw at z 5 in `GhostMemoryLayer` with one shared dim colour (plan row P115c). The
tracer stays clipped to the seen tiles as the P68d note says (plan row P117b). The texture, its
updates, `explored_alpha` and the soft edge are unchanged.

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

Status note (2026-10-22, ADR 0016 accepted; the bullets above stay as accepted): after P65, the
second bullet holds for `explored` directly and, through the hashed rows, for everything a
`visible` count changes. The counts themselves will be covered by the kernel locksteps (full
state), by `NativeKernels.self_check`, which will compare `fog.visible`, and by P65's test that
rebuilds them from the rows and compares. Until P65 merges, the bullet describes `main`.
