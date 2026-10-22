# ADR 0018: Economy, power, production and the match outcome

Status: proposed, 2026-10-22. Docs PR P68 (with `docs/plans/2026-10-22-phase-3.md`). Builds on ADR
0017 (the data model, the Commands and the tick phases); this ADR fixes the rules. Every number
below is a starting value in `data/*.tres` (CLAUDE.md rule 5) for Phase 4's balance runs, never a
literal in code.

## Context
- `docs/GDD.md`, "Match setup": one Headquarters, 2 000 credits and 2 rifle squads at the start;
  victory when "the enemy has neither a Headquarters nor a production building left".
- `docs/GDD.md`, "Economy": ore fields regrow "1 unit per field cell per 10 seconds, capped"; a
  harvester carries 500 credits per trip; every refinery comes with one free harvester; low power
  means "production at 50% speed, defences offline".
- `docs/GDD.md`, "Buildings (MVP)" and "Units (MVP)": six buildings with size, cost, power and one
  requirement each; six units with cost, hp, speed and range. The GDD gives no build times and no
  building hp.
- `touch-ui-rules`: the sidebar has three tabs (Buildings, Infantry, Vehicles) with build icons
  that show cost and progress; tapping an own production building opens its tab.
- ADR 0007 §5's planned Phase 3 commands: place building, queue unit, cancel unit, set rally,
  harvest; and surrender.
- Phase 2 left "splash damage" out of scope (Phase 2 plan, "Goal"), and the GDD calls artillery
  strong against "Buildings, groups".

## Decision

### 1. Credits
Per player, starting at `start_credits` (2 000). Only unloading harvesters add credits; `QUEUE`
subtracts, `CANCEL` refunds. A value never goes below 0 (a `QUEUE` the player cannot pay is
dropped).

### 2. Ore fields
- Ore is a terrain: the symbol of the terrain `ore` in `data/terrain/standard.tres`, passable for
  every class and not buildable. `World` lists its cells at load, ascending (`ore_cell`).
- Each ore cell starts with `ore_start` units (20) and holds at most `ore_cell_max` (20). On every
  tick with `tick % ore_regrow_ticks == 0` (150, 10 seconds) each cell below the cap gains 1.
- One unit is worth `credits_per_ore` (25) credits, so a full cell holds 500.

### 3. The harvest loop
A harvester is a mobile row whose type has `type_harvest` above 0 (cargo capacity in credits,
500). Its state is `harvest_mode`, `cargo` (credits), `harvest_slot` (its ore cell) and `home`
(its refinery's id). The loop runs in ECONOMY over `harvester_rows`, ascending:
- **SEEK:** if its ore cell is empty or unset, it takes the ore cell with ore that is nearest to its
  position (smallest squared distance, then the lowest index; each cell looked at counts in
  `Stat.ORE_SCANNED`); none: it waits and looks again every `harvest_retry_ticks` (15). It gets a
  `MOVE` order to the cell's centre. When its order has ended (`IDLE`) within `harvest_reach_milli`
  (1 200) of that centre, it turns to MINE; ended farther away, it gets the order once more, then
  SEEKs another cell.
- **MINE:** on ticks with `(tick + id) % harvest_ticks_per_ore == 0` (3) it moves one unit from
  the cell into its cargo (the cargo grows by `credits_per_ore`). Cargo at `type_harvest`: RETURN.
  Empty cell: SEEK (the cargo stays).
- **RETURN:** it takes `home` if that refinery still exists, else the nearest own refinery (then
  the lowest id) and makes it `home`, and gets a `MOVE` to the refinery's dock (origin plus
  `type_dock_x`, `type_dock_y`, a tile centre). No refinery: it waits as in SEEK. Order ended within
  `dock_reach_milli` (1 500) of the dock: UNLOAD.
- **UNLOAD:** on ticks with `(tick + id) % unload_ticks_per_ore == 0` (1) it moves one unit's worth
  of credits (`credits_per_ore`) to its owner and to `stat_harvested`. Empty: SEEK, back to its last
  cell.
- **IDLE:** under the player's control. A unit-group order (`MOVE`, `ATTACK_MOVE`, `STOP`) on a
  harvester sets IDLE and keeps the cargo. On ticks with `(tick + id) % harvest_resume_ticks == 0`
  (75, 5 seconds) a harvester in IDLE whose order is `IDLE` turns to SEEK (0 turns this off).
- **`HARVEST`** (Command 14): the player's harvesters among `unit_ids` take the ore cell with ore
  nearest to the point, within `harvest_pick_milli` (3 000) of it, and SEEK it; no such cell: the
  command is dropped.
- A refinery placed with `PLACE` spawns its type's `type_free_unit` (the harvester) at its dock,
  in SEEK with `home` set. The free harvester counts against the unit cap (§5) like any mobile
  row: a refinery placed while the player has `unit_cap` mobile rows, or while `max_rows` is full,
  comes without it (nothing is held or owed), so a side never has more than `unit_cap` mobile rows.
- A harvester spawned by a scenario or by a factory starts in SEEK with no `home`.
The loop gives orders the way the unit-group commands do: it writes `order` (`MOVE`), `goal_x`,
`goal_y` and `group_cell` (-1, so a blocked line keys the field on the goal's tile) and calls
`Movement.reset_nav` with `DIRECT`, as `Sim._apply_point` does after `Formation.assign`
(`Movement.reset_row` is Targeting's per-row helper, with a C++ twin in the TARGETING kernel, and
the loop does not call it); it reads no input. That is a sim rule, like target acquisition, not a
player action, so CLAUDE.md rule 4 holds.

### 4. Power
- `power_made` is the sum of the positive `type_power` of a player's buildings, `power_used` the
  sum of the negative ones (as a positive number). Both are derived (ADR 0016), rebuilt in ECONOMY
  when `rows_version` has moved; a test rebuilds them from the rows at every checkpoint.
- Low power: `power_used > power_made`. Then the player's queues advance at `low_power_percent`
  (50) of the normal rate (§5), and the player's defences (building rows with a weapon) do not fire:
  `Combat.fire` (GDScript only) skips them. They still pick targets (TARGETING is unchanged, its
  kernel too), so the view can show them as offline and they fire at once when power returns.

### 5. Production
- **Tabs and producers.** A buildable type has a tab (`type_tab`): STRUCTURES, INFANTRY or
  VEHICLES. A building type may produce one tab (`type_produces`): the Headquarters produces
  STRUCTURES, the barracks INFANTRY, the vehicle factory VEHICLES. A tab's primary producer is the
  player's lowest-id building that produces it.
- **One queue per player and tab**, `queue_slots` (5) long. All barracks share the INFANTRY queue;
  a second one adds no speed (Phase 4 may add a rule).
- **`QUEUE`** `[type_index]`: valid when the type has a tab, the player has a producer of that tab,
  owns a row of `type_requires` (if any), has room in the queue and at least `type_cost` credits.
  The cost is paid at once (question 2); the item joins the queue's end.
- **`CANCEL`** `[tab, slot]`: removes that item, refunds its full cost and moves the later items
  up; cancelling the head resets the progress.
- **Progress:** in PRODUCTION, the head of each queue that has a producer gains 100 per tick, or
  `low_power_percent` on low power, and is done at `type_build_ticks * 100`. No producer: it waits.
- **A finished unit** spawns at the primary producer's exit (origin plus `type_exit_x`,
  `type_exit_y`). If that cell is impassable for the unit's class, it takes the first passable cell
  of the ring around the footprint, walked clockwise from the exit (each cell counts in
  `Stat.EXIT_SCANNED`). It then gets a `MOVE` to the tab's rally point, if one is set, through the
  same nearest-passable rule as a one-unit `MOVE`; a harvester ignores the rally point and SEEKs
  (§3). It waits at 100 % while no exit cell is free,
  while the player has `unit_cap` (75) mobile rows, or while `max_rows` is full.
- **A finished structure** turns ready and stays at the head; the STRUCTURES queue stops until the
  player places it (`PLACE`) or cancels it (structures are built in the sidebar, then placed,
  question 1).
- **`PLACE`**: valid when the STRUCTURES head is ready and `Placement.reason` is `OK` (ADR 0017
  §2). It adds the building complete through `World.add_building`, pops the head, adds 1 to
  `stat_built` and spawns a free unit (§3).
- Requirements are checked when an item is queued; losing the required building later leaves
  queued items as they are.

### 6. Rally points
One per player and production tab (INFANTRY, VEHICLES), stored in `rally_x`, `rally_y` (-1 =
none). **`RALLY`**: `target_id` is an own building that produces INFANTRY or VEHICLES; the point is
clamped to the map and becomes that tab's rally point. Without one, new units stay at the exit and
separation spreads them.

### 7. Defeat, victory and the end of a match
- **Only a side that has owned a producer can lose it.** `World.add_building` sets the owner's
  `had_producer` to 1 when the type produces a tab (scenario buildings too); nothing resets it.
  In PRODUCTION, after the queues, a player still playing whose `had_producer` is 1 and who owns no
  building that produces a tab (no Headquarters, barracks or vehicle factory) is defeated. A ready
  structure in the queue does not save the player. A side that never owned a producer (the perf
  arena, `controls_test.tres`, a hand-built test World with units only) is never defeated by this
  rule, so those worlds keep running and keep applying Commands; only `SURRENDER` ends them.
- **`SURRENDER`** (Command 20) defeats its player at once.
- When at most one player is still playing, the match ends: `match_end_tick` is set and `winner` is
  that player, or 0 when the last players fell on the same tick (a draw).
- Both ticks hold the tick the step produces, `world.tick + 1` (the World's tick once the step has
  run; `SURRENDER` in COMMANDS writes the same value), so a defeat or an end on the first step of a
  match reads 1, and 0 keeps meaning "playing" and "running".
- After the end, `Sim.step` drops every Command (ADR 0017 §4), and the runner stops ticking
  (P81).
- Per player, for the result screen: `stat_built` (units produced and buildings placed),
  `stat_lost_units`, `stat_lost_buildings` (counted in `remove_dead` by the dying row's owner) and
  `stat_harvested`.

### 8. New unit types
Heavy tank, artillery and harvester join `data/units/` with the GDD's costs, hp, speeds and
ranges; artillery's weapon has `min_range` 3 tiles. Artillery has no splash damage in Phase 3
(question 4); Phase 4's balance runs decide whether it needs one.

### 9. Data
- `RulesDef` (and `data/rules.tres`) gains, as rule ints that `World` copies under the same names:
  `start_credits` 2000, `ore_start` 20, `ore_cell_max` 20, `ore_regrow_ticks` 150,
  `credits_per_ore` 25, `harvest_ticks_per_ore` 3, `unload_ticks_per_ore` 1,
  `harvest_reach_milli` 1200, `dock_reach_milli` 1500, `harvest_retry_ticks` 15,
  `harvest_resume_ticks` 75, `harvest_pick_milli` 3000, `low_power_percent` 50, `queue_slots` 5,
  `build_reach_tiles` 4, `unit_cap` 75, `building_cap` 40, `ghost_cap` 40.
- `UnitDef` gains `cost`, `build_ticks`, `tab` (-1 = not buildable), `requires` (a `UnitDef`, null =
  none) and `harvest_capacity` (0 = not a harvester). A new `BuildingDef extends UnitDef` adds
  `footprint` (`Vector2i`), `power`, `produces` (-1 = none), `free_unit` (a `UnitDef`), `dock` and
  `exit` (`Vector2i` tile offsets). `TerrainDef` gains `buildable` (a bool, copied as a byte).
- Starting build times (ticks at 15 Hz): rifle squad 75, rocket squad 150, light tank 225, heavy
  tank 330, artillery 300, harvester 300; power plant 150, barracks 150, refinery 375, vehicle
  factory 450, defence turret 225. Starting building hp: Headquarters 2000, power plant 800,
  refinery 1500, barracks 1000, vehicle factory 1600, defence turret 900.
- Data tests: every building has speed 0, radius 0, armour `BUILDING` and a footprint of at most
  3x3; `harvest_capacity` is a multiple of `credits_per_ore`; `unit_cap` and `building_cap` times
  the players fit in `max_rows` (2 x (75 + 40) = 230 of 256; the free harvester is inside the 75,
  §3); every requirement chain reaches the Headquarters; every weapon's `range` reaches the ring
  corner cell of a 3x3 footprint from its centre (`range` of at least 2 829, ADR 0017 §1's
  approach point).

## Consequences
- Harvesters, production and defeat are sim rules on hashed state, so AI-vs-AI runs, replays and
  the golden hashes cover them.
- With payment at queue time, the sidebar can grey out what the player cannot pay before a Command
  is sent, and a cancel is a plain refund.
- A destroyed refinery sends its harvesters to the nearest other refinery, or leaves them waiting.
- A player who loses every producer loses at once, even with an army left; this matches the GDD.
  A scenario without producers (the perf arena, the controls test) never ends on its own.

## Alternatives considered
- **Pay as it builds** (credits drained per tick, production pauses at 0): more state (a paid
  amount per head) and a stall rule; recorded as option B of question 2.
- **Place first, build on the spot** (a construction site with rising hp): more sim state (a site
  phase, power and defeat rules for unfinished buildings) and a second interaction while the site
  builds; recorded as option B of question 1.
- **Per-building queues and rally points:** rejected in ADR 0017 (Alternatives).
- **Harvesters that never resume on their own:** simpler, but one stray box selection stops the
  income; question 3.
- **Splash damage now:** a new rule in PROJECTILES with a grid query per impact; deferred to
  Phase 4 (question 4).

## Questions for Michael
1. How are structures built? A: in the sidebar first, then you place the finished building
   (instant on placement). B: you place it first, then it is built on the spot over time.
   (A/B; recommended: A, the simpler rule and one tap less while fighting)
2. When are credits paid? A: the full cost when you queue an item, fully refunded if you cancel.
   B: bit by bit while it is built. (A/B; recommended: A)
3. A harvester that you have moved, or that stands idle, goes back to harvesting by itself after
   about 5 seconds (`harvest_resume_ticks`). Do you want that? (ja/nej; recommended: ja)
4. The GDD calls artillery strong against groups, which needs splash damage. Should splash wait
   for Phase 4's balance work, so artillery ships in Phase 3 as long-range, anti-building fire?
   (ja/nej; recommended: ja)
