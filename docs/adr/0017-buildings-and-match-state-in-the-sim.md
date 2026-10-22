# ADR 0017: Buildings and match state in the sim (World v2, Commands 10-14 and 20, tick phases 11-13)

Status: accepted, 2026-10-22 (Michael: 1 ja, 2 ja, 3 ja, 4 ja). Proposed 2026-10-22. Docs PR P68
(with `docs/plans/2026-10-22-phase-3.md`), accepted by the lead's row P68b on the same PR (#166).
Code facts are from `main` at 757b5f9, where P68b re-checked them (the proposal was written
against 7185a91). P65 (ADR 0016) merged as 757b5f9 (#163): `World.STATE_FORMAT` is 2 and
`FogGrid.HASHED` is `[&"explored"]`.

## Acceptance note (2026-10-22)
Michael answered the questions of ADRs 0017-0021 in chat on 2026-10-22, verbatim "Ja til alle
anbefalinger" (yes to all recommendations), which the lead records for this ADR as "1 ja, 2 ja,
3 ja, 4 ja":
1. **ja:** the placement rule of §2 holds: a new building stands on explored, buildable ground
   with no mobile unit on it, within `build_reach_tiles` (4) of an own building and below
   `building_cap`.
2. **ja:** at most `unit_cap` (75) mobile rows and `building_cap` (40) buildings per side, both
   in `data/rules.tres`; the refinery's free harvester counts against the 75, and at the cap the
   refinery comes without it (ADR 0018 §3).
3. **ja:** the last-seen building memory ships in Phase 3 (plan row P77), hashed, in the World's
   `GHOST_ARRAYS` (§3), not in `FogGrid`.
4. **ja:** P70 re-pins the golden hashes once more (`STATE_FORMAT` 3) under the Phase 2 plan's
   exception 10, after P65's re-pin to 2, which has merged.

The decision below is unchanged by the acceptance. P68b fixed three review points in its
wording: the source of a quote in the Context (`game/core/MatchSnapshot.gd`, not ADR 0012 §3),
the power totals the snapshot copies (§6), and the totals of the hash-growth estimate (§7).
Nothing here is applied in code yet: plan rows P69-P81 apply it.

Companion ADRs: 0018 (economy and production rules), 0019 (build UI), 0020 (dummy opponent and the
AI hook), 0021 (Phase 3 performance gate). This ADR fixes the data model and the plumbing; 0018
fixes what the rules do with it.

## Context
What earlier ADRs already decided for Phase 3:
- **ADR 0007 §2:** "Buildings (Phase 3) are rows of the same table", so targeting, damage, death
  and fog need no second code path; building-only state goes in side arrays "added by the Phase 3
  ADR and registered in the shape lists"; "Per-player economy (credits, power) arrives in Phase 3
  as arrays indexed by player id". A test fails unless every `Packed*Array` property of `World` is
  in exactly one shape list and every `int` in exactly one scalar list
  (`test_the_shape_lists_cover_every_array_and_int_property_once` in `tests/sim/test_world_v1.gd`).
- **ADR 0007 §4:** probe phase ids are fixed and never renumbered; marks come in ascending id
  order, at most once per tick; "A phase added in a later phase of the roadmap gets a new id
  through a new ADR".
- **ADR 0007 §5:** `Command` types 10-19 are reserved for Phase 3 economy and production
  ("planned: place building, queue unit, cancel unit, set rally, harvest"), 20-29 for match-level
  commands ("planned: surrender"); "Each later command type's id rules and payload layout are fixed
  by the ADR that adds it". `Command.gd`'s header repeats the reservation, and `Sim._apply` drops
  every type without a branch as unknown.
- **ADR 0010 §1:** the per-player last-seen building memory is history, "will live inside
  `FogGrid` and be hashed", and the AI reads the World only through a pure
  `game/sim/PlayerView.gd`; both arrive with the first AI code (the Phase 3 dummy opponent).
- **ADR 0016 (accepted):** derived state stays out of the state hash, with a test that rebuilds it
  from hashed state; history (the last-seen memory, ore left, credits) is hashed. P65q's
  `WATCH sim hash_bytes` line (`tests/perf/test_hash_bytes.gd`) prints the bytes fed per
  checkpoint in every CI log, so Phase 3's growth shows there first.
- **ADR 0013 §1:** later ports follow clauses (a) and (b); new phases start as GDScript.
- **ADR 0012 §3:** the view reads only `MatchSnapshot`; `MatchSnapshot.COPIED` and `NOT_COPIED`
  split `ROW_ARRAYS`, `TYPE_ARRAYS`, `WEAPON_ARRAYS`, `PROJECTILE_ARRAYS` and `MAP_ARRAYS` exactly
  once (`test_copied_and_not_copied_split_the_world_shape_lists_exactly_once` in
  `tests/core/test_match_snapshot.gd`), so that a Phase 3 column "fails the test until it is
  classified" (ADR 0012 §3); the doc comment of `NOT_COPIED` in `game/core/MatchSnapshot.gd` says
  the same: "so a new World column fails until it is classified".

What the code does today (`main` at 757b5f9):
- `Sim.step` runs COMMANDS, FLOW, GRIDS, TARGETING, INTENTS, SEPARATION, INTEGRATE, PROJECTILES,
  FIRE, REMOVE (with `FogUpdate.begin` first) and FOG, then `tick += 1`. `SimProbe.Phase` holds
  ids 0-10 and `COUNT = 11`.
- `World.set_terrain` writes `terrain` and `move_cost`, bumps `map_version` and calls
  `flow.invalidate(map_version)`; the map digest of the hash follows `map_version` alone
  (`_map_digest_value`). `World.is_passable` reads `move_cost` and says that "a rule that makes
  more than the terrain block a tile (a building) edits both" twins (its C++ twin is in the
  INTEGRATE kernel).
- `World.add_unit` refuses a row beyond `max_rows` after `prepare()` (`spawn_refused`); a new row
  has `fog_cell` -1, which `FogUpdate.run` stamps on its player's next fog turn ("a row not stamped
  yet, -1, only stamps").
- `World.remove_dead` writes a `DIED` event per dead row, unstamps its fog and compacts every
  `ROW_ARRAYS` column. `REMOVE` is GDScript only (ADR 0013 §1).
- `World.state_hash` feeds `ROW_ARRAYS.size() + HASH_OTHER_SECTIONS` sections (20 + 4: header,
  map, one per row column, projectiles, fog).
- `Separation` reads `type_radius`; `Targeting` treats every enemy row with a damage percent above
  0 against its armour as a candidate (`World.Armour.BUILDING` exists); `Combat.fire` (FIRE) is
  GDScript only (ADR 0013 §1's status note of P26ac: P42n not triggered).

## Decision

### 1. Buildings are rows that never move and block their tiles
- A building type is a type with a footprint: `type_foot_w` and `type_foot_h` above 0. Data gives
  it speed 0, radius 0 and armour `BUILDING` (a data test pins all three for every building).
- Its row's position is the footprint centre: `origin * 1000 + foot * 500` on each axis. The
  footprint origin is derived from the position and the type, so no column stores it.
- `World.add_building(owner, type_index, origin_col, origin_row) -> int` appends the row through
  `add_unit` (so the refusal rules, the `SPAWNED` event and `rows_version` stay one code path), then
  writes `move_cost` 0 for every movement class on every footprint cell, bumps `map_version` once
  and calls `flow.invalidate(map_version)`. `from_scenario` places scenario buildings through it.
- `remove_dead` restores each dead building's footprint cells from `terrain_cost` (what
  `set_terrain` would write) and bumps `map_version` once on a tick with a building death.
- **An `ATTACK` on a building aims at an approach point, not at the centre.** Today the TARGETING
  phase writes an `ATTACK` row's goal from its target's position every tick (`Targeting.gd` and
  `core/targeting.cpp`), and `Sim._apply_attack` sets `group_cell` -1, so the field is keyed on the
  goal's cell. For a 3x3 footprint that cell is the centre, whose eight neighbours are all footprint
  cells (`move_cost` 0): `FlowField.advance` reaches no other cell, `_take_own_field` finds the key
  equal to the goal's cell, and the unit steers DIRECT into the wall. The rule (P71):
  - `Sim._apply_attack` (COMMANDS, GDScript only, command cadence): when the target's type has a
    footprint, it writes each row's `goal_x`, `goal_y` to the row's approach point: the centre of
    the ring cell (the cells 8-adjacent to the footprint and outside it, inside the map) that is
    passable for the row's class and nearest to the row's position (squared distance, then the
    lower cell index). A row with no passable ring cell is left out; none left: the command is
    dropped and counted.
  - TARGETING (both twins: `Targeting.gd` and `core/targeting.cpp`): an `ATTACK` lock writes the goal
    from the target's position only when the target's `type_speed` is above 0, so a building
    target keeps the approach point; the lock's line re-test tests the line to the goal instead of
    the target's position. For a mobile target the goal equals the target's position at that
    point of the pass, so Phase 2 state does not move (the arenas stay bit-identical). The kernel
    fetches `type_speed` on entry (one more name in its checked list).
  - `World.add_building` re-picks the approach point of every `ATTACK` row whose goal cell lies in
    the new footprint (event cadence, bounded by `max_rows` per placement).
  - Unchanged: INTENTS (`_check_line`) and INTEGRATE (`_rekey`, `_take_own_field`) key on the goal's
    cell, which is now a passable ring cell, so the field grows from it and the keys agree. Range
    and the HOLD at range still measure to the target's position (the footprint centre); a data
    test (ADR 0018 §9) keeps every weapon's range above the distance from a 3x3 centre to its ring
    corner cell (2 829), so the approach point is always within range.
- Why no other kernel changes: every ported kernel reads the blocked cells through `move_cost`
  (FLOW, INTEGRATE's `is_passable` twin), the radii (SEPARATION: with radius 0, a pair with a
  building needs a mobile row closer than its own radius to the building's centre, which a blocked
  footprint and a radius of at most 500 rule out; a data test pins that radius bound for
  every mobile unit, plan row P72), the rows as candidates (TARGETING, apart from
  the `ATTACK` goal above) and the rows' cells (FOG). P71 adds a building-world case to each
  kernel's lockstep suite to prove it on both implementations, among them an `ATTACK` on a 3x3
  building behind rock. A later rule that needs a kernel change edits both twins (ADR 0013 §5).
- `_own_rows` already filters speed-0 rows, so no unit-group Command moves a building.

### 2. Placement validity is one pure function
`game/sim/Placement.gd` decides whether a footprint fits, for the sim (applying `PLACE`) and the
view (the ghost's tint, ADR 0019) alike, so both judge by the same code:
- `static func reason(input: PlacementInput, player: int, type_index: int, origin_col: int,
  origin_row: int) -> int` returns a `Placement.Reason`, the first rule that fails in this order:
  `OK` 0, `OUTSIDE` 1 (a cell outside the map), `GROUND` 2 (a cell whose terrain is not buildable,
  or whose `move_cost` for foot is 0: rock, water or a building), `OCCUPIED` 3 (a row of speed above
  0 whose disc touches the footprint), `UNEXPLORED` 4 (a cell the player has never explored),
  `TOO_FAR` 5 (the footprint's Chebyshev gap to every own building footprint is above
  `build_reach_tiles`), `CAP` 6 (the player has `building_cap` buildings).
- `PlacementInput` (pure `RefCounted`, `game/sim`) holds references to the arrays the rules read,
  under their World names; `PlacementInput.of_world(world)` fills it for the sim, and the view
  fills it from the snapshot (ADR 0012 §3: the view never reads the World).
- Its cost is bounded: at most 9 footprint cells, `max_rows` rows and `building_cap` buildings per
  call. The sim calls it once per `PLACE`; it is never in a per-tick loop.

### 3. World v2: new state, each array in exactly one list
Declared at once by one PR (P70), sized at `prepare()` and set to its start values there, so
later rows fill rules without moving any arena hash again (§7):

| List | Names | Hashed |
| --- | --- | --- |
| `ROW_ARRAYS` (appended) | `harvest_mode`, `cargo`, `harvest_slot` (index into `ore_cell`, -1), `home` (refinery id, 0) | yes (one section each, as today) |
| `PLAYER_ARRAYS` (new) | per player, index 0..`player_count` (0 unused): `credits`, `defeated_tick` (0 = playing; else the tick the defeating step produces, `tick + 1`), `had_producer` (1 once the player has owned a building that produces a tab, ADR 0018 §7), `stat_built`, `stat_lost_units`, `stat_lost_buildings`, `stat_harvested`; per player and tab, index `player * TABS + tab`: `queue_count`, `queue_progress`, `rally_x`, `rally_y` (-1 = none); per queue slot, index `(player * TABS + tab) * queue_slots + slot`: `queue_type` | yes (new section `players`, one block per array) |
| `ORE_ARRAYS` (new) | `ore_amount`, one per `ore_cell` entry | yes (new section `ore`) |
| `GHOST_ARRAYS` (new) | per player, capacity `ghost_cap`: `ghost_id`, `ghost_type`, `ghost_owner`, `ghost_cell`; and `ghost_count` per player | yes, live entries only (new section `ghosts`, like the projectile slots) |
| `MAP_ARRAYS` (appended) | `terrain_buildable` (byte per terrain index), `ore_cell` (ascending cells of the ore terrain, fixed at load) | through the map digest |
| `TYPE_ARRAYS` (appended) | `type_foot_w`, `type_foot_h`, `type_cost`, `type_build_ticks`, `type_tab` (-1 = not buildable), `type_requires` (type index, -1), `type_produces` (tab, -1), `type_power`, `type_harvest` (cargo capacity in credits, 0), `type_free_unit` (type index, -1), `type_dock_x`, `type_dock_y`, `type_exit_x`, `type_exit_y` (tile offsets from the origin) | no (`defs_hash`) |
| `DERIVED_ARRAYS` (new) | `power_made`, `power_used` (per player), `building_rows`, `harvester_rows` (ascending rows), rebuilt when `rows_version` moves | no; a rebuild test (ADR 0016) |
| `HASHED_SCALARS` (appended) | `match_end_tick` (0 = running; else the tick the ending step produces, `tick + 1`, so an end on the first step reads 1), `winner` (0 = none or a draw) | yes |
| `RULE_SCALARS` (appended) | the economy and production ints of ADR 0018 §9 | no (`defs_hash`) |

- New enums: `Tab { STRUCTURES = 0, INFANTRY = 1, VEHICLES = 2 }` with `const TABS: int = 3`, and
  `HarvestMode { IDLE = 0, SEEK = 1, MINE = 2, RETURN = 3, UNLOAD = 4 }`. `Stat` gains
  `ORE_SCANNED = 7`, `EXIT_SCANNED = 8` and `MEMORY_CHECKS = 9`, so qa-engineer can bound the new
  work deterministically, as for the Phase 2 counters.
- **The last-seen memory lives in the World, not in `FogGrid`** (this supersedes ADR 0010 §1's
  "will live inside `FogGrid`", and only that): its records are per building, not per cell, and
  keeping them out of `FogGrid` leaves the FOG kernel's checked list as it is. It stays history and
  hashed, as ADR 0010 and ADR 0016 say.
- `STATE_FORMAT` becomes 3 (P65 made it 2). `HASH_OTHER_SECTIONS` becomes 7; the new sections
  come after `fog` in the order `players`, `ore`, `ghosts`, and `hash_section_names()` names them.

### 4. Commands 10-14 and 20
Fixes ADR 0007 §5's reserved slots. Every type keeps the common rules (player in
1..`player_count`, payload at most `MAX_PAYLOAD`, the command's tick); the new types also need a
player who is not defeated. Once the match has ended (`match_end_tick` above 0), every Command of
any type is dropped and counted. The per-type rules are ADR 0018's.

| Type | Value | Fields | Payload |
| --- | --- | --- | --- |
| `PLACE` | 10 | `target_x`, `target_y`: a point in the footprint's origin tile (milli) | empty; places the ready head of the player's STRUCTURES queue |
| `QUEUE` | 11 | - | `[type_index]` |
| `CANCEL` | 12 | - | `[tab, slot]` |
| `RALLY` | 13 | `target_id`: an own production building; `target_x`, `target_y`: the point | empty |
| `HARVEST` | 14 | `unit_ids`: own harvesters; `target_x`, `target_y`: a point near ore | empty |
| `SURRENDER` | 20 | - | empty |

Factories in `Command`, each copying its arrays as today: `place(player_id, target_x, target_y)`,
`queue(player_id, type_index)`, `cancel(player_id, tab, slot)`,
`rally(player_id, building_id, target_x, target_y)`, `harvest(player_id, unit_ids, target_x,
target_y)`, `surrender(player_id)`. `encode`/`decode` need no change: the payload and every field
are already written. A type index in a payload is the World's type index; `defs_hash` protects a
replay against other data, as today. 15-19 and 21-29 stay reserved.

### 5. Three new tick phases after FOG
`SimProbe.Phase` gains `ECONOMY = 11`, `PRODUCTION = 12` and `MEMORY = 13`, `COUNT = 14`, and
`PHASE_NAMES` gains `"economy"`, `"production"`, `"memory"`. Because marks must ascend, the three
run after FOG, before `tick += 1`:
- **ECONOMY:** the derived lists and power totals when `rows_version` moved (`Power.run`), the
  harvest loop and ore regrowth (`Harvest.run`).
- **PRODUCTION:** queues advance, finished units spawn at their exit and leave for the rally
  point, structures turn ready (`Production.run`); then the defeat and victory check
  (`Outcome.run`).
- **MEMORY:** the last-seen records of the players whose fog turn ran this tick
  (`LastSeen.run`).

Consequences of the order, all deterministic and pinned by tests: a building placed in COMMANDS of
tick t counts for power in t's ECONOMY and for defences in t+1's FIRE; a unit produced in t's
PRODUCTION enters the grids in t+1 and is stamped into the fog on its player's next fog turn, like
every row with `fog_cell` -1; orders that the harvest loop gives in t's ECONOMY move the harvester
from t+1. Every loop visits players ascending, tabs ascending, rows ascending by id and ore cells
ascending; no Phase 3 rule draws a random number.

### 6. The snapshot
P70 lists every new `ROW_ARRAYS`, `TYPE_ARRAYS` and `MAP_ARRAYS` name in `MatchSnapshot.NOT_COPIED`
(the plan's named exception 11), so the coverage test stays green. P81 (the lead) moves what the
view reads to `COPIED` (including `move_cost` and `type_radius`, which the ghost check needs),
copies `PLAYER_ARRAYS`, `ORE_ARRAYS`, `GHOST_ARRAYS`, the derived power totals `power_made` and
`power_used` (the sidebar's power bar and the low-power cues show them, ADR 0019 §1 and §5; ECONOMY
has rebuilt them by the end of the step) and the two new scalars, lists `building_rows` and
`harvester_rows` as not copied, extends the coverage test to the new lists (`DERIVED_ARRAYS`
included), and makes the runner stop ticking once `match_end_tick` is set. All copies are
`duplicate()` (O(1); the next write copies the buffer, inside `step_usec`, ADR 0016's Context).

### 7. The state hash
- One re-pin: P70 changes the layout (four row columns, three sections, two scalars,
  `STATE_FORMAT` 3), so it re-pins the golden hashes under exception 10. The perf arena has no
  building, ore or queue, and every new array starts at a value that no later row changes for it,
  so from P70 on every Phase 3 row must leave the arena's golden hashes bit-identical; a row that
  moves them is a bug or a rule change that says why under exception 3. Two inputs of the arena's
  state come from shared data and must land with the re-pin, so P70 carries them: the `ore`
  terrain appended to `data/terrain/standard.tres` (it lengthens `terrain_cost`, which is in
  `MAP_ARRAYS`) and the terrains' `buildable` flags (`terrain_buildable`); `rules.tres` gets every
  Phase 3 rule value in P69, before the re-pin, and no rule value is in the state hash. The arena has
  no building that produces a tab, so its players never set `had_producer` and are never defeated
  (ADR 0018 §7): `defeated_tick`, `match_end_tick` and `winner` stay 0 through all 900 ticks.
- Estimated growth at the perf arena (150 rows at tick 15, 71 at tick 900, 2 players): about 2.5 KB
  of new row columns at tick 15 and 1.2 KB at tick 900, about 0.6 KB for `players` and 48 bytes of
  block headers for the empty `ore` and `ghosts`: in all about +3.1 KB per checkpoint at tick 15
  and +1.8 KB at tick 900. P65q's line will show the real numbers.
- Derived and unhashed, each with a rebuild test: `power_made`, `power_used`, `building_rows`,
  `harvester_rows`. `move_cost` is derived from the terrain and the buildings but stays in the map
  digest, as today; a placement or a building death recomputes the digest at the next checkpoint
  (about 16 KB through SHA-256 on a 64x64 map, once per change).

### 8. Native kernels
No new phase is ported. ECONOMY, PRODUCTION and MEMORY start as GDScript (ADR 0013 §1, "Later
ports"). The lead applies clauses (a) and (b) to each at the first `PERF` line with the full
Phase 3 tick (the base arena, ADR 0021, plan row P93), and §15's port trigger on the gate cards.
`COMMANDS` grows by the new types; it stays GDScript only, under the same §15 trigger.

## Consequences
- Buildings get targeting, damage, death, health bars and fog from the existing code paths.
- Placing or losing a building invalidates every cached flow field (`flow.invalidate`), as a
  terrain change does today; the base arena measures the cost (risk in the plan).
- Every hash printed before P70 differs from those after it; `STATE_FORMAT` 3 marks the change.
- A replay of Phase 3 needs only the Command log; the economy and AI need no extra replay field.
  `Replay`'s `FORMAT` stays 1 (ADR 0007 §9 allows a change if a per-match value is added later).
- The perf arena stays the Phase 2 regression run; Phase 3's own load is measured by the base
  arena (ADR 0021).
- ADR 0010 §1 is superseded in one point (where the memory lives); its rules stay.

## Alternatives considered
- **A separate building table** (own ids, own compaction): rejected, as in ADR 0007 §2: a second
  path for targeting, damage, death and fog, and every kernel would need to read it.
- **Production state per building** (a queue on every factory row): rejected for ADR 0018's
  per-tab queues; per-row queues would need variable-length state in fixed columns.
- **A separate blocked-cell overlay instead of `move_cost`:** rejected; every ported kernel would
  need to read it (a twin change in FLOW and INTEGRATE).
- **New phases between FIRE and REMOVE:** rejected; marks must ascend (ADR 0007 §4), and
  renumbering the Phase 2 ids would break every per-phase comparison.
- **Ghost records inside `FogGrid`** (ADR 0010's wording): rejected for the reason in §3.
- **Hashing the derived power totals:** rejected by ADR 0016's rule.

## Questions for Michael
1. A new building must stand on explored, buildable ground with no unit on it and within a few
   tiles of one of your buildings (`build_reach_tiles`, starting at 4). Do you accept this placement
   rule? (ja/nej; recommended: ja)
2. A match never holds more than 150 units if each side has at most 75 units (harvesters count,
   the free harvester of a new refinery too: at the cap the refinery comes without it) and 40
   buildings, both values in `data/rules.tres`. Do you accept these caps? (ja/nej; recommended: ja)
3. ADR 0010 promised that enemy buildings you have seen stay on the map as "last seen" markers in
   the fog. Should the sim keep that memory already in Phase 3 (it is small and hashed)? (ja/nej;
   recommended: ja)
4. P70 adds the new state to the hash, so the six golden hashes change once more, right after P65.
   Do you accept that? (ja/nej; recommended: ja)
