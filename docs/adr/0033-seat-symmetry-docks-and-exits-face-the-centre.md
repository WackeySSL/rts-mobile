# ADR 0033: Seat symmetry: docks and exits face the map centre, and placement stops reading the explored map

**In short, for Michael:** in the first balance run the top-left player won about 98 % of equal
matches. Two of the three causes are in the game's rules, not in the AI: every factory, barracks
and refinery sends its units out (and takes its tankers in) on its south side, which faces the
enemy for the top-left player and the map edge for the bottom-right one; and a building may not
stand on ground its owner has never seen, which the two AIs see a little differently after the
first seconds. From now on every such building uses the side that faces the middle of the map,
yours as well as the AI's, so it is the same for every seat on every map. The six factories,
barracks and refineries get a door on both front walls (question 1, A), and the "never seen" rule
goes (question 2, A). Nothing costs anything on the phone.

Status: **accepted, 2026-11-09**, for the direction Michael approved in chat on 2026-11-09 ("ja" to
P195b and P195c, "including the ADR", relayed by the lead): docks and exits face the map centre
per building, for every player; placement in a player's own base no longer depends on what that
player has explored; the golden hashes that move are re-pinned with this ADR as the reason. Two
sub-choices change what the player sees: **Questions** below. Michael answered both on
2026-11-09: A and A (a door on both front walls; the explored rule goes, E1). Written by the
architect on `main` at b6bfe95 (plan row P195c). Amends ADR 0017 §2 (the `UNEXPLORED` rule, §4
here) and ADR 0018 §3 and §5 (where the dock and the exit are, §1 and §2 here); see §8.

## Context
- **The bias.** Balance run 1 (#378): in Normal-Normal mirrors the top seat (player 1, Headquarters
  at (7, 7) on Kestrel Flats; player 2 at (54, 54), the exact half turn of a 64 x 64 map) won about
  98 % of the decided matches. The human also plays the top seat today (ADR 0031 §1: player 1 is
  always the top seat).
- **The diagnosis (P195, experiment branches `claude/p195-exp-a` to `-q`, fossil-mirror seeds
  1-20; probes on `claude/p195-seat-bias`, `tests/sim/test_seat_symmetry.gd`).** The sim's own
  rules for units are symmetric (mirrored duels and marches; swapping think offsets, the flow cache
  or the player ids leaves the bias), and the map and spawns are exact half turns. Swapping the
  spawns moves the bias with the corner (exp A: 20-0 for whoever starts top-left). Without combat
  the top-left player harvested 44 988 credits against 33 396 (exp I). Three position effects, all
  economic:
  1. **The AI's refinery site is blind to ore**: it takes the first valid spiral slot (exp K, L).
     Fixed AI-side by P195b (ai-dev, running).
  2. **Docks and exits face south in data**: `BuildingDef.dock` (1, 3) for both refineries,
     `exit` (1, 3) for both vehicle factories and (1, 2) for both barracks
     (`data/units/*.tres`). For the top-left base south faces the centre, the ore and the enemy;
     for the bottom-right base it faces the map edge behind the base. With the AI fix alone the
     refinery sites became half turns, but the bottom-right dock now faced its ore and the top-left
     one did not: P2 earned more in 20 of 20 (exp K) and won fossil-mirror 16-0 (exp M). The probe
     `test_a_factorys_exit_faces_south_so_player_2s_units_leave_at_the_back` measured the walk of a
     light tank from mirrored factories to its side's staging point at 57 and 86 ticks (5 and 68
     from another site): the exit's side decides the walk.
  3. **Placement's `UNEXPLORED` rule**: the explored tiles start as exact half turns (209 each, the
     probe pins it) but drift apart within 30 ticks (the starting rifles' formation slots and the
     one-tick fog turn put 12 tiles apart), so player 1's corner slot (3, 3) is unexplored when
     player 2's mirror slot is explored, and the two layouts diverge from the 4th building on.
- **The prototype.** Exp N gave player 2 the half-turned offsets (`Buildings.seat_offset`, used in
  `ProductionSpawn.spawn`, `spawn_free` and `Harvest._dock`); exp P also turned the explored rule
  off (`Placement._unexplored` returns false). With the AI fix plus both, the layouts were exact
  half turns and the incomes equal (42 794 against 42 719; P2 more in 10 of 20), and the seats close
  to even: 8-3 with 9 timeouts; with the spawns swapped (exp Q) 12-5 for the bottom-right player 1.
  Over P and Q together player 1 won 20 of 28 decided (about 71 %, p about 0.04): a mild edge of
  the player index may remain (think order, the fog turn, command order). That is measured after
  this fix and is not decided here (a possible P195d).
- **The prototype is a hack**: it keys on player 2, so it is wrong for swapped spawns, for three or
  four seats and for any map that is not a half turn. This ADR replaces it with a rule of position.
- **No native twin.** The kernels are flow, fog, integrate, separation and targeting
  (`native/sim_kernels/src/core/`); none reads a dock, an exit or `Placement`. Harvest,
  Production, ProductionSpawn and Placement are GDScript in both implementations (verified on
  b6bfe95), so the golden hashes move identically under GDSCRIPT and NATIVE.
- **The art.** A building has one view (STYLE.md, "Directions"), drawn from the camera at +gx, +gy:
  only the +x wall (right front on the screen) and the +y wall (left front) are seen. The door,
  hopper or dock mouth is drawn on the +y wall in the data cell's column, and `tests/art` pins it
  there against the data. The world atlas page of a cross-faction match is 3550 px of its 3584 px
  budget (`tests/view/test_iso_atlas_budget.gd`, after P158b's damage patches): 34 px are left.

## Options

### Facing (which side a dock or exit uses)
- **F1, per building, toward the map centre (chosen).** At any time the side of the footprint
  whose outward direction is nearest to the vector from the building's centre to the map's centre;
  the data offsets, authored for the south side, turn with it. Needs only the building's position
  and the map size, so it is the same rule for every player, any seat count and any map, and it
  needs no state.
- **F2, toward the nearest enemy start.** The same on a two-seat half-turn map; needs the starting
  positions in the sim (new hashed player arrays, `STATE_FORMAT` 6, every golden re-pinned) and is
  ambiguous with three or four seats. Rejected.
- **F3, offsets mirrored per seat** (the prototype). Keys on the player index. Rejected.
- **F4, symmetric data**: the exit or dock chosen at use time as the ring tile nearest the rally
  point, the harvester or the centre. A ring scan per spawn and per return, and ring ties broken by
  the ring's index, which starts at the top-left corner and so is not seat-symmetric; it also drops
  the fixed dock that the art draws. Rejected.
- **F5, a facing column set by `PLACE`** (hashed). The behaviour of F1 at the price of
  `STATE_FORMAT` 6 (every golden, `TICK_0_SEED_1` and `KNOWN_FORMATS` re-pinned under exception
  10), 4 bytes a row and a snapshot copy. Only needed once a player chooses a facing (a rotate
  button on the ghost), which is out of Phase 4's scope. Rejected for now; a later ADR may add it.

### Art
- **A1, no art change (chosen for P195c-1).** The sim moves the dock and the exit; the frames stay.
  Zero frames, zero bytes, zero draw calls. The drawn door is on the +y wall even where the building
  faces east, north or west.
- **A2, flip the frame for an east facing.** Free in memory (same atlas region, flipped UVs), but a
  horizontal flip swaps gx and gy, so the lit left face and the shade of the right face swap and the
  cast shadow points to +gy: two lights in one scene, against STYLE.md's one light from the
  north-west. It also covers only one of the three other facings. Rejected.
- **A3, a generated view per facing** (`tools/artgen/` turns the model 90, 180 and 270 degrees).
  Correct pictures, but 3 extra views for 6 buildings, each with its hull, shadow and two damage
  patches: about 72 frames on a page that has 34 px left, so `IsoAtlas.fit_scale` would lower the
  bake scale of every sprite (softer art on the phone) or a second page would break the one-texture
  batching of the y-sorted world (a draw call at every texture switch in the sort). Rejected.
- **A4, a door on both front walls (recommended follow-up, question 1).** art-director regenerates
  the six producer and refinery models with a second door, hopper or dock mouth on the +x wall at
  the east facing's cell, so a building facing south or east shows the door it uses and one facing
  north or west (a hidden wall) reads as a drive-through hall. Same frame count, same atlas regions,
  same draw calls; the page must stay within 3584 px.

### The explored rule
- **E1, drop `UNEXPLORED` from `Placement` (chosen, measured as exp P).** No placement reads the fog
  any more. The ghost leaks nothing new: `GROUND` and `OCCUPIED` are tested before `UNEXPLORED`
  today, so a ghost over black ground already shows rock, water and units there. Removes code.
- **E2, the start area counts as explored for `Placement`**: tiles within `start_area_tiles` (a
  new `RulesDef` int) Chebyshev of an own building that produces the structures tab (the
  Headquarters), so no new state is needed. Unmeasured; an AI base that grows past the area meets
  the drift again at its edge, and it adds a rule int, an input field and a snapshot read.
- **E3, mark the start area explored in the fog at tick 0.** Changes what the player sees at the
  start (a revealed patch round each base) and the hashed fog; the drift at its edge stays.
  Rejected.

## Decision

### 1. Facing: a pure function of position (F1)
`game/sim/Buildings.gd` gains (names are the contract; the row may add private helpers):
```gdscript
enum Facing { SOUTH = 0, WEST = 1, NORTH = 2, EAST = 3 }  # quarter turns clockwise from SOUTH
static func facing(map_cols: int, map_rows: int, x: int, y: int) -> int
static func turned(offset: Vector2i, size: int, facing: int) -> Vector2i
```
- `x`, `y` are the building's centre in milli-tiles (its row's `pos_x`, `pos_y`). With
  `dx = map_cols * 1000 - 2 * x` and `dy = map_rows * 1000 - 2 * y` (twice the vector to the map's
  centre, so a half tile stays an integer):
  - `dx == 0 and dy == 0`: `SOUTH`;
  - `abs(dy) > abs(dx)`: `SOUTH` if `dy > 0`, else `NORTH`;
  - `abs(dx) > abs(dy)`: `EAST` if `dx > 0`, else `WEST`;
  - a diagonal tie: the side one quarter turn clockwise from the diagonal (y grows downwards):
    (+, +) `SOUTH`, (-, +) `WEST`, (-, -) `NORTH`, (+, -) `EAST`.

  The rule is equivariant under a quarter turn of a square map and a half turn of any map: a
  building's half turn gets `(facing + 2) % 4`, its quarter turn `(facing + 1) % 4`, ties
  included. Maps mirrored across an axis are not covered; maps stay half or quarter turns, as
  Kestrel Flats is.
- `turned`: one clockwise quarter turn about an n x n footprint is `(x, y) -> (n - 1 - y, x)`;
  `facing` applies it that many times. It keeps a ring tile on the ring. For today's data:

  | Offset (data, south) | WEST | NORTH | EAST |
  | --- | --- | --- | --- |
  | 3 x 3 dock or exit (1, 3) | (-1, 1) | (1, -1) | (3, 1) |
  | 2 x 2 exit (1, 2) | (-1, 1) | (0, -1) | (2, 0) |

- **Where it applies** (every read of a dock or exit position, nothing else):
  `ProductionSpawn.spawn` and `ProductionSpawn.exit_tile` (the exit), `ProductionSpawn.spawn_free`
  and `Harvest._dock` (the dock). `_dock`'s three callers, `Harvest.run` (the reach check of a
  harvester in RETURN), `_go_home` (SEEK's full load) and `_choose` (RETURN's refinery choice), all
  pick up the turn through `_dock` and need no edit of their own. The tests for "has a dock"
  (`dock != (0, 0)` in Harvest, `ProductionSpawn.spawn_free` and `PlayerView`) stay on the raw
  data: a dock of (0, 0) means none and is never turned. The clockwise ring walk past a closed exit
  starts from the turned tile; a rotation keeps clockwise clockwise, so the walk stays
  seat-symmetric.
- **Stale doc comments** that P195c-1 updates to "the offset turned to the building's facing":
  `Harvest.gd` lines 21-23 (a refinery's dock), line 321 (`_dock`: "origin plus the type's dock
  offset") and `ProductionSpawn.gd` line 81 (`exit_tile`), with `ProductionSpawn.spawn_free`'s and
  `tile_from`'s comments where they name the raw offset.
- **No state.** A building never moves, so its facing is derived where it is used: no row column,
  no `STATE_FORMAT` change, no snapshot or `PlayerView` change. The AI may call the static function
  if it wants a dock tile (P195b or later; not required). Cost: a dozen integer operations per spawn
  (event cadence) and per harvester in RETURN per tick (`Harvest.run` calls `_dock` there, at most
  `unit_cap` rows, typically 4-8), no allocation (`Vector2i` is a value). Nothing measurable against
  the 150-units-at-60-fps budget.
- **Data stays data (rule 5).** `BuildingDef.dock` and `exit` keep their meaning, offsets for the
  south facing; their doc comments say the sim turns them to the building's facing. The rule has no
  number: the map size and the footprint are already data. A data test pins that every type with a
  dock or an exit has a square footprint and its offset on the footprint's ring.
- **The human player.** The rule is the same for every player: your own factories, barracks and
  refinery also send units out and take tankers in on the side that faces the middle of the map.
  From the top seat that is the south or east side (the two walls the camera sees); the enemy's
  bottom-right base uses its north or west side, behind its buildings as seen. P195c-1 adds this to
  `docs/HOW_TO_PLAY.md` (the barracks and vehicle factory row and "Look at a tanker"). The exit
  puff (`GroundFx._exit_puffs`) is drawn at the SPAWNED position, so it follows by itself.

### 2. The rows that read docks and exits get their tests
See §6. The probe suite of `claude/p195-seat-bias` (`tests/sim/test_seat_symmetry.gd`) comes to
`main` with P195c-1 if it has not merged by then; its two cases that pin the asymmetry (the
refinery's dock, the factory's exit) are turned into cases that pin the symmetry.

### 3. Art: no change now (A1); A4 if Michael says yes (question 1)
- P195c-1 changes no frame. `tests/art`'s pin of the drawn door to the data cell stays true (the
  data still names the south cell). STYLE.md's "Dock and exits" paragraphs (both factions) get a
  sentence in P195c-2 either way: the data's cell is the south facing's, the sim turns it.
- With a yes, P195c-2 (art-director) adds the second door on the +x wall of the six models
  (`assets/art/models/fossil/{refinery,barracks,vehicle_factory}.tres`,
  `assets/art/models/renew/{renew_refinery,renew_barracks,renew_factory}.tres`) at the east
  facing's cell (3 x 3: the middle of the +x wall; 2 x 2: the wall's north cell, `turned` above),
  regenerates hull, shadow and damage patches (`bash scripts/gen-art.sh`), keeps the cross-faction
  page within 3584 px (`test_iso_atlas_budget.gd` re-pinned with the new heights), and extends
  `tests/art`'s pin to both walls. Runtime cost: none (same frames, regions and draw calls).
- Rejected: A2 (two lights in one scene) and A3 (about 72 frames on a full page).

### 4. Explored rule: dropped (E1), unless Michael picks E2 (question 2)
- P195c-3 removes `Placement._unexplored` and the `UNEXPLORED` member of `Placement.Reason`; the
  other members keep their numbers (`TOO_FAR` 5, `CAP` 6). `PlacementInput` keeps its fog fields
  (`PlayerView.is_explored` reads them). `docs/HOW_TO_PLAY.md`'s placement row loses "you have not
  explored the ground". The sim tests it rewrites (lines on b6bfe95): `tests/sim/test_placement.gd`
  13, 113-120, 182, 224 and 264; `tests/sim/test_production_place.gd` 17 and 145;
  `tests/sim/test_player_view_state.gd` 214-225. `GhostLayer` finds a glyph by the reason's name and
  `tests/view/test_ghost_layer.gd:132` loops `Placement.Reason.keys()`, so neither needs an edit.
- The glyph goes in P195c-2 (art-director's files), all in one commit so no test breaks between
  them: `assets/art/svg/icons/glyph_reason_unexplored.svg` and its `.svg.import`;
  `tests/art/test_icon_art.gd:67` (`REASONS` lists "unexplored", so it must lose the entry in the
  same commit as the SVG); `game/view/art_gallery.gd:206` and `:245` (its name and its colour);
  `assets/art/STYLE.md:1261` (the reason list) and `:1394` (the glyph's row).
- For the AI: its placements are the same function (`PlayerView.placement`), so two mirrored AIs
  get the same answers for mirrored slots. For the human: a building may stand on black ground, but
  only within `build_reach_tiles` (4) of an own building, so next to the base.
- If Michael picks E2, P195c-3 implements E2 as described under Options instead (a `RulesDef` int
  `start_area_tiles` in `data/rules.tres` and the frozen rules, `type_produces` in
  `PlacementInput`), and the balance run below judges it.

### 5. Determinism and golden hashes
| Pin | P195c-1 (facing) | P195c-3 (explored, E1) |
| --- | --- | --- |
| `golden_hex` (perf arena, seed 42: all six checkpoints of `golden_ticks` in `data/dev/perf_gate.tres`) and seed 43 | unchanged: units only, no building | unchanged: no `PLACE` |
| `TICK_0_SEED_1` (controls test) | unchanged: tick 0, no new state | unchanged |
| `STATE_FORMAT` 5, `KNOWN_FORMATS` | unchanged (no layout change, no exception 10) | unchanged |
| `bases_golden_hex` (base arena, six values at `bases_golden_ticks`) | **moves**, the one golden re-pinned: both bases' producers and refineries sit east or west of the map centre and turn; re-pinned under the Phase 2 plan's exception 3 with "ADR 0033 §1" as the reason | unchanged: the arena's buildings are scenario spawns and it sends no `PLACE` (the row checks it) |
| `test_base_arena_run.gd` counted pins (`UNLOAD_BY`, the heavy window) | re-checked; a pin that moves is re-pinned with the reason | unchanged |
| `perf_ai` (frozen scenario): printed hash, P189's counted bounds, P189b's `[ai]` ratchet | may move (AI refineries and factories turn) | moves (AI placements) |
| Smoke and balance hashes | printed, not pinned | printed, not pinned |

- Re-pin rule: exception 3 (Phase 2 plan) as ADR 0021 restates it: the sim row re-pins the golden
  hashes and the run-outcome pins in its own PR with the reason; cost bounds and `budget.cfg`
  (`[bases]`, `[ai]`) are qa-engineer's only, so a bound that fails stops the row and qa-engineer
  re-baselines it in a stacked commit with before and after numbers (ADR 0031 §8's ratchet rule).
- The frozen defs of `data/dev/arena/` are untouched (no data changes), so `test_frozen_defs_data`
  and ADR 0031's "tuning moves no golden hash" stay as they are: this is a rule change, not tuning.
- Both implementations move together (no twin, §Context). Replay: unchanged format; a replay
  recorded before P195c-1 no longer reproduces (as with every sim rule change).
- P195c-2 is art only: no hash.

### 6. Tests (all headless)
- **P195c-1**: `facing` on the four sides, the four diagonal ties and the exact centre; for every
  building centre of a 64 x 64 and a 63 x 63 map, `facing` of the quarter turn is `facing + 1`
  (mod 4) and of the half turn `facing + 2`, and the half turn on a 64 x 40 map; `turned` gives
  the table of §1, four turns are the identity, every shipped dock and exit stays on the ring; a
  factory in each quadrant spawns its first unit on the turned exit, a closed turned exit walks
  clockwise from it (the `EXIT_SCANNED` count), the free harvester appears at the turned dock, and
  `_go_home` (SEEK's full load), RETURN's reach check in `Harvest.run` and `_choose` all order it
  there; existing suites that place a dock or an exit by the raw offset are rewritten for the
  turned one: `tests/sim/test_base_arena_data.gd:118-142` (it reads `type_dock`/`type_exit` raw and
  asserts that tile is open; it must test the turned tile) and
  `tests/sim/test_production_free_harvester.gd` (its refinery at tile (6, 5) has its dock at (7, 8),
  and its closed-dock and free-unit cases name dock tiles); the seat-symmetry suite's refinery and
  factory cases now pin equal income and equal walk times (within what the row measures) for a site
  and its half turn; the base arena stays bit-identical across runs, across GDSCRIPT and NATIVE
  and under replay (existing cases).
  Mutants: one per call site (no turn in `spawn`, `exit_tile`, `spawn_free`, `_dock`) plus the
  facing rule's (sign of `dx`, `>` for `>=` in the side test, each tie case, `n - 1 - y` for
  `n - y`, `facing` not taken mod 4), about 10 in all.
- **P195c-3**: a never-explored footprint within reach is `OK`; no reason 4 is returned; the sim and
  `PlayerView.placement` agree; the ghost shows no unexplored sign; with P195b on `main`, a
  no-combat fossil-mirror match (both Normal, seed 1, 3 000 ticks) where every building of player 2
  stands on the half turn of one of player 1's (exp P's result; the row pins what it measures).
  About 5 mutants.
- **P195c-2**: `tests/art` pins the door on both front walls against `turned`; the atlas budget.

### 7. Rows
| Row | Owner | Title | ~Lines | Depends on |
| --- | --- | --- | --- | --- |
| P195c-1 | gameplay-dev | sim: docks and exits face the map centre (`Buildings.facing`, `turned`, the four call sites, the data test, `BuildingDef` comments, HOW_TO_PLAY rows, `bases_golden_hex` re-pin) | ~80 (tests ~300) | this ADR; none of the questions |
| P195c-3 | gameplay-dev | sim: placement without the explored rule (E1), or the start area (E2), per question 2; HOW_TO_PLAY's placement row; the sim tests of §4 (`test_placement.gd`, `test_production_place.gd`, `test_player_view_state.gd`) | ~-25 for E1, ~60 for E2 | question 2; P195b for its mirror-layout case |
| P195c-2 | art-director | art: STYLE.md's dock and exit note; with question 1's yes, the second door on six models (A4); if P195c-3 took E1, the unexplored glyph in one commit (the SVG and its `.import`, `test_icon_art.gd`'s `REASONS`, `art_gallery.gd`'s two entries, STYLE.md lines 1261 and 1394; §4) | 0 (SVG, `.tres`, STYLE.md) | P195c-1; question 1; P195c-3 for the glyph |
| P195d (conditional) | ai-dev with gameplay-dev | diagnosis of a remaining player-index edge (think order, fog turn, command order), its own plan entry and, if the sim changes, its own ADR | - | the balance run below fails |

P195c-1 and P195c-3 touch different files and may run in parallel; both can move `perf_ai`'s
counts, so the lead verifies their combined tree once before merging the second.

### 8. Acceptance and what this amends
- **Acceptance** (the lead, from GitHub balance runs; never in a session): once P195b, P195c-1 and
  P195c-3 are on `main`, the balance run's Normal-Normal sets fossil-mirror (20 matches, seeds
  1-20), renew-mirror (20) and cross (100) each give the top seat a win share (draws half, as
  `balance-summary.sh` reports it, ADR 0031 §4) of 400-600 per-mille. A mirror set of 20 has a
  standard deviation of about 110 per-mille at 500, so a mirror set outside the band gets one rerun
  on seeds 21-40 and is judged on the pooled 40. Still outside: P195d. P192's tuning starts after
  this acceptance (the plan's P192 dependency on P195).
- **Why the cross set may judge the seat.** A cross match has one faction a side, so a stronger
  faction could pass for a stronger seat. It does not here: `cross` plays the odd seeds on Kestrel
  Flats and the even ones on the mirrored scenario (`tests/smoke/smoke_run.gd`, the `--scenarios`
  comment), so each faction holds each seat in half the matches, and the balance run's cross set is
  seeds 1-100 (`scripts/ci/balance-plan.sh`, four blocks of 25): 50 matches each way. The faction's
  strength then adds the same to both seats and cancels from the top seat's share. The cross set is
  a seat test only with an even number of matches from an odd seed; a rerun or a custom run with an
  odd count is judged on the two mirrors alone, and the faction balance is P192's.
- **Amends** (the lead adds dated notes on merge; the accepted texts stay as they are): ADR 0017 §2
  (line 174: `UNEXPLORED` 4 is no longer returned, E1); ADR 0018 §3 and §5 (the dock and the exit
  are the origin plus the offset turned to the building's facing); ADR 0019's ghost reasons (one
  fewer). STYLE.md's "Dock and exits" paragraphs are art-director's (P195c-2). No CLAUDE.md, skill
  or agent change; no ROADMAP box.

## Consequences
- The economic seat bias from docks, exits and layout drift is gone by construction for every
  half-turn or quarter-turn map and any seat count, without a player-index rule; P195b fixes the
  AI's side.
- No state, no hash layout change, no frame, no byte and no draw call: only `bases_golden_hex`
  and the AI workload's counts move.
- The human's buildings turn too: from the top seat mostly south as today, some east. Until A4 the
  drawn door can be on a wall the building does not use (east, north and west facings).
- A building whose dock faces the centre may face away from its ore where the ore lies behind the
  base: the same for every seat, so fair, but a map with ore behind the bases makes slower trips.
  The AI can choose sites knowing this (`Buildings.facing` is public and pure).
- With E1 a player can place on black ground near the base; the ghost shows no new information.
- A player-chosen facing (a rotate button) would need F5's hashed column and a `PLACE` field: a
  later ADR, outside Phase 4.
- A mild player-index edge (about 71 % over exp P and Q) may remain; it is measured, not assumed.

## Questions for Michael
1. **The door on the pictures.** Units now leave, and tankers unload, on the side of a building
   that faces the middle of the map. The pictures show the door only on the front-left wall. **A**
   (recommended): the art-director draws the six factories, barracks and refineries with a door on
   both front walls, so the door you see is the one in use or the other wall's door is implied; no
   cost on the phone. **B**: leave the pictures as they are.
2. **Building on ground you have never seen.** **A** (recommended, and the version that was
   tested): drop the rule; you may place a building on black ground, but only near your own
   buildings, as today. **B**: keep the rule, except in an area round each Headquarters (its size
   in the data); not yet tested, and the two bases can still drift apart outside that area.

Answered by Michael on 2026-11-09 (chat, "ADR 0033: begge A"): question 1 **A**, question 2 **A**.
P195c-2 draws the second door; P195c-3 removes the explored rule (E1, §4).

Note (2026-11-09, the lead, from P195c-1's review): §1's equivariance holds for every building
centre except the map centre itself, the fixed point of every turn, where `facing` returns SOUTH by
convention. Two seats can never both own a building there, so it adds no seat bias. Follow-up row
P195e: a dock covered by the owner's own building never unloads (`Harvest._dock` does not walk the
ring); either the dock walks the ring like `tile_from`, or Placement refuses a footprint on an own
dock or exit tile. Turned docks make this easier to hit.

Note (2026-11-10, the lead, P26bk; row P195d-2): P195b, P195c-1 and P195c-3 merged together as #391.
On their combined tree, §8's sets gave the top seat 650 (fossil-mirror), 750 (renew-mirror) and
655 per-mille (cross), so §8 was not met. P195d's diagnosis found the rest of the edge in the sim:
- experiments A to K and a mirror-divergence probe (`tests/ai/probe_mirror_divergence.gd` on
  `claude/p195d-probe`, not merged);
- the bisect runs KA, KB and KD found world-fixed tie-breaks and tile borders, not the player
  index.

Row P195d-2 (gameplay-dev) makes four rules half-turn equivariant, in the GDScript twin and the
kernel in lockstep:
1. **Tile border (`FixedMath.centre_side`).** A coordinate exactly on a tile border past the middle
   of the map gives up 1 milli, so its tile is the one on the centre's side; a half turn then maps
   a point's tile to its image's tile.
   - Users: `World.cell_of`, Movement, Targeting (lock, keep, scan, `sees`), FogUpdate,
     `PlayerView._take_rows` (the AI's copy of `sees`), the line_clear segment ends, and the
     kernels `integrate.cpp`, `targeting.cpp` and `fog.cpp`.
   - LastSeen keeps the plain floor: an even footprint is anchored on a tile corner and its set is
     already equivariant.
2. **Formation.** Equal slot keys and equal-distance units go by the larger dot, then the larger
   cross product, with the group's approach (`centre*count - sum(positions)`). The open-centre ring
   search ties by `way = point*count - sum(positions)` the same way, in 64-bit ints. A zero vector
   falls back to generation order and the lower id.
3. **`Harvest._scan`.** Equal distance goes to the cell further toward the map centre, then the
   larger cross; at the exact centre, list order.
4. **Flow `best_neighbour`.** Equal-cost lower neighbours go by the larger dot of the step with
   (goal - cell), then the larger cross; goal = cell keeps NW..SE order. The integrate kernel reads
   `goal_cell`.

Limits, recorded and not fixed here:
- The rules are equivariant under a half turn, not a reflection: the cross product flips under a
  mirror. Skirmish maps must stay half turns (Kestrel Flats is one).
- On an even-sized map both centre lines are tile borders. A point with x or y on a centre line
  takes the +x/+y tile, which is the only remaining fixed choice (a "pinwheel" tie would leave only
  the exact centre point).
- line_clear shifts only ends on a far border, which tilts the segment. An exact interior corner can
  then be missed and a corner-touching tile dropped; on 10 x 10, (2000, 1000)-(8000, 4000) drops
  tile (4, 1).
- Other world-fixed rules of the same kind remain, for follow-up row P195f:
  - Separation's 3 x 3 scan from the north-west, which counts only the first
    `separation_neighbours` (twin and kernel);
  - the edge clamps to [0, W - 1] (Movement, `integrate.cpp`, WorldLoad, Strike, Outcome): the half
    turn of 0 is W, so a unit at the east or south edge rests 1 milli further in;
  - the AI's own floors (AiArmy, AiStrikes, AiIntel);
  - the view's cell (`MatchSnapshot.cell_of` and the view layers floor, so a building or fogged
    unit exactly on a far border can show one tile off).

Hashes (§5, exception 3) re-pinned by P195d-2: perf arena final `7bcb20994df10b28` ->
`17f7a83c4d492c4c`, base arena final `4f1b4973efe6377c` -> `c84764064abfb27c`; twin and kernel
agree.

§8's acceptance on P195d-2's head:
- before review (`bd7bc2e`): fossil-mirror 450 (seeds 1-40) and 488 (41-80), pooled 469;
  renew-mirror 550; cross 535;
- fossil-mirror with the spawns swapped: 513 for the top-left seat (player 2), 478 for player 1 of
  the decided matches, so neither the corner nor the index keeps an edge;
- after review (`1994a20`): FINAL_NUMBERS.

The faction edge is separate and is P192's to tune: in cross, fossil won 59 matches and renew 4.
