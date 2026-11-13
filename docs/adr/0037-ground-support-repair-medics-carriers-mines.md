# ADR 0037: Ground support: building sale and repair, repair buildings, medics, carriers, mines

**In short, for Michael:** four things you asked for, and four gaps the lead found:
- **Sell a building** for part of its price, and **repair a building** with a switch that costs
  credits while it works. Both are small and need no new picture.
- **Repair of damaged vehicles** happens at a new building per side: the Derrick League's
  **Weld Shed** (a workshop where vehicles park on the apron) and the Lumen Accord's **Drone Dock**
  (small drones fly out to vehicles nearby). A building, not a vehicle; the reasons are in §5.
- **Medics** heal infantry squads near them: the League's **Patchers**, the Accord's **Menders**.
- **An infantry carrier** per side: the League's **Bunk Wagon** (slow, armoured, more seats) and the
  Accord's **Linecar** (fast, light). Squads ride inside and cannot shoot from it. It uses the same
  loading rules as the air design's transport aircraft (ADR 0036).
- **Mines**, laid by the League's **Shot Truck** and the Accord's **Seeder**. A mine is hidden from
  the enemy until one of its mine-layers or scout tanks finds it. Your own mines never hurt you.
- **Hold position:** a button that keeps selected units from leaving their path to chase. Ranks
  and patrol stay for later updates.

Michael answered the five questions on 2026-11-09 (end of this ADR): everything comes before
launch, after the Phase 4 gate, in one block with the air design. Inside the block it is built in
three waves: sale and building repair first; then repair buildings and medics, after the air rows
they share; then the carrier, mines and hold position.

Status: **accepted, 2026-11-09** (Michael: 1 A, 2 A, 3 A, 4 B, 5 A; accepted in docs row P270b
of `docs/plans/2026-11-09-ground-support.md`, together with ADR 0036 in one commit). Proposed
2026-11-09 (architect, branch `claude/design-ground-support`, base `main` at b6bfe95; reconciled
the same day with ADR 0036 at 0c5cc75 on `claude/design-air-and-tech`; fix 1 the same day after
gameplay-dev's docs lens: 8 must, 10 should, 5 nits). Nothing here is built before the Phase 4
gate.

Note (2026-11-09): Michael answered ADR 0036 (air before launch) and this ADR (1 A, 2 A, 3 A, 4 B,
5 A) the same day. The status stays proposed: the lead accepts both ADRs in one docs row once both
fix commits are in and Michael has said yes to the `touch-ui-rules` text. Where this ADR said
"version 1", "1.1" and "1.2", read waves 1, 2 and 3 of the pre-launch block (§1).

Status note (2026-11-09, P270b docs; acceptance):
- Accepted with ADR 0036 in one docs row (P230 and P270b), before Michael's yes to the
  `touch-ui-rules` text. The note above expected that yes first. The lead accepted the design
  now, and the skill gate moved to the rows: P272, P282, P294 and P299 still wait for the yes.
  The draft text is in `docs/plans/2026-11-09-air-and-tech.md`, section "touch-ui-rules text for
  Michael's yes (P230)".
- **This ADR amends ADR 0036 §2.** The repair role moves to `UnitDef` (a squad may hold it;
  `BuildingDef extends UnitDef`, so the names and the airfield's data stay), and it gains
  `repair_slots` and `repair_seek_milli`. ADR 0036 §2, §8 (`carry_eject_percent`) and §12 (Board
  and Unload take a ground carrier) carry dated notes, and so does P231's row.
- ADR 0036 §11 was rewritten at its acceptance (answer 3 B): the sweep lasts until the space
  centre is destroyed and pauses while it is blacked out or its owner is on low power. A sale of
  the space centre (§3) ends the sweep as its destruction does.
- Dated notes were written in ADRs 0007, 0010, 0017, 0018, 0023, 0030 and 0031 (this ADR's list),
  and in ADRs 0009 and 0013 for hold position's TARGETING edit and the mine blast, which the list
  missed. The GDD has a "Ground support" section and the ROADMAP Phase 4b.
- The order of the rows both designs share (§2, "whichever comes first") is fixed in one text,
  "Merge order of the shared rows", in both plans: ADR 0036's P231, P232 and P241b come before
  P276 and P277, and its `Carry.gd` (P262-P263b) before P289.

Amends, on acceptance, by dated notes the lead writes in P270b (accepted text stays as it is):
- ADR 0036 §2 (its line "Buildings ... The repair role") and P231's row text: **this ADR amends
  ADR 0036 §2** so the repair role's fields are declared on `UnitDef`, not `BuildingDef` (a squad
  may hold it; `BuildingDef` extends `UnitDef`, so every name and every airfield's data stay). The
  role gains `repair_slots` and `repair_seek_milli`. The lead edits ADR 0036 and its plan on
  acceptance. §8 gains `carry_eject_percent` (0 keeps §8's rule: passengers die). §12's Board and
  Unload buttons take a ground carrier as well as a transport.
- ADR 0007 §5 (Command types 8, 17 and 18) and §10 (events 7 and 8, DIED flag 3).
- ADR 0018 §5 (sale and mend; the refund and the price rule).
- ADR 0017 §5 and ADR 0010 §1 (the known-mine records beside the last-seen buildings).
- ADR 0023 §2 (the mine layer's z and page) and §13 (the names screen, §14 here).
- ADR 0030 (the managers' new duties, §10 here) and ADR 0031 §6 check 4 (the type count).

## Context
- **Michael's request (2026-11-09, through the lead):** a vehicle that carries infantry; repair of
  damaged tanks (a building, a vehicle or both, and whether buildings can be repaired); a medic
  that heals infantry; a minelayer whose mines are hidden. Each must have its own faction take.
- **The lead's gaps at b6bfe95:** no sale of buildings, no building repair, no veterancy, no
  stances (hold position, hold fire) and no patrol. Rally points exist. Save and resume on going to
  the background is a Phase 5 ROADMAP item already.
- **The GDD.** Derrick League heavy, robust, slow; Lumen Accord fast, precise, fragile. Pillar 4:
  the AI has no vision it has not scouted. "Not in version 1" lists air units.
- **Today's sim (b6bfe95).**
  - Commands 1-4 and 10-16 and 20 exist; 5-9, 17-19 and 21-29 are free.
  - Events SPAWNED 1 to STRIKE 5; DIED's seventh int is 1 for a cancelled site.
  - `construct_refund_percent` (75) prices a cancelled site; nothing sells a finished building.
  - `LastSeen` keeps per-player records of enemy buildings; the AI reads only `PlayerView`.
  - Kernels: FLOW, SEPARATION, INTEGRATE, TARGETING and FOG have C++ twins (ADR 0013). COMMANDS,
    PROJECTILES, FIRE, REMOVE, ECONOMY, PRODUCTION and MEMORY are GDScript only.
  - `cargo` is a harvester's load; a building row never writes it.
  - `remove_dead` writes DIED's flag from `build_left` (`World.gd:894`); the view reads it as
    "cancelled" whenever it is not 0 (`EffectsLayer.gd:414`, `BuildingCollapse.gd:158`).
  - There is no `Combat.damage` yet (ADR 0036's P246 adds it); the rupture applies
    `maxi(1, damage * percent / Combat.PERCENT)` per row (`Strike._land`, `Strike.gd:209`).
  - `target_grid` is rebuilt in GRIDS (`Sim.gd:57`), before movement and before `remove_dead`
    compacts the rows (`Sim.gd:80`): by ECONOMY its row indices and positions are stale.
- **ADR 0036 (proposed, 0c5cc75)** already designs, for the air layer:
  - `LOAD = 5`, `UNLOAD = 6`, `REPAIR = 7` as shared Command types;
  - the repair role (`repair_classes`, a move-class mask with FOOT 1, WHEELED 2, TRACKED 4, AIR 8;
    `repair_hp` per `repair_period_ticks`; `repair_cost_percent`; `repair_reach_milli`);
  - `Carry.gd`: boarded squads leave the row table for a passenger table and return with their id
    through `World.insert_row`; `Carry.BOARDED` = -2 in `build_left`, DIED flag 2; event
    `UNLOADED` = 6; `carry_mode`;
  - no tap overloads: a tap on an own unit or building always selects; "Home" (aircraft to their
    airfield), "Board" and "Unload" are 48 dp command-bar buttons, Board and Unload with an aim;
    that `touch-ui-rules` text waits for Michael's yes;
  - `STATE_FORMAT` 6 in P232 (exception 23) and 7 in P262 (exception 24);
  - the page rule: y-sorted items stay on page 1; page 2 holds unsorted layers; art-director's
    P237 (the page-2 split and probe) lands before any new art row.
  - Plan rows P230-P269. This plan therefore starts at **P270** (the lead's P260 was taken).
- **The atlas page** is 3,550 of 3,584 rows (cross-faction), ADR 0035's polish frees about 100,
  and ADR 0036's new buildings alone need more than page 1 has left. Every unit and building here
  is y-sorted, so it competes for page 1.

## Decisions in short
1. Everything before launch (answer 1 A), in three waves: sale and building repair; repair
   buildings and medics; the ground carrier, mines and hold position. Only hold position edits a
   kernel (TARGETING).
2. Shared with ADR 0036: Commands 5, 6 and 7 with its meanings; this ADR adds `LAY_MINE = 8`,
   `SELL = 17`, `MEND = 18`; events `MINE_BLAST = 7`, `REPAIRED = 8`; `SOLD` = -3, DIED flag 3.
3. Sale: `SELL` refunds `sell_refund_percent` of the price, scaled by hp left; two taps on a phone.
4. Building repair ("Mend"): `MEND` toggles a paid repair that stops at full hp; the switch is
   the building row's unused `cargo`, so wave 1 changes no state layout and re-pins nothing.
5. Vehicle repair is a building per faction on ADR 0036's repair role, served through `REPAIR`.
6. Medics are squads with the same role (FOOT bit), healing squads in reach, walking to hurt ones.
7. The ground carrier is a data entry on `Carry.gd`; `carry_eject_percent` lets the League's
   passengers get out hurt when it dies, while the Accord's (and the aircraft's) die.
8. Mines: one-shot, enemy ground units trigger them, own units never trigger or take damage; a
   player knows an enemy mine only through a detector's record kept like a last-seen building.
9. Mines, their records and hold position's `stance` column stay on `STATE_FORMAT` 7 (ADR 0036's
   last number), with one re-pin of their own after P262 (exception 25); no new format number.
10. Art rows wait for P237; the ground set asks page 1 for about 240 rows in wave 2 and 245-490 in
    wave 3. Hold position (answer 4 B): `STANCE` 9, no chase, in the TARGETING twin and kernel.

## Decision

### 1. Features, sizes and waves
Sizes are production lines (tests, fixtures and `.tres` do not count). Everything is before launch
(answer 1 A); the wave is the build order inside the block, set by the shared rows each wave needs:
wave 1 needs none of ADR 0036's rows; wave 2 needs P231, P232 and P241b (art after P237); wave 3
needs P262 and P263b (art after P237).

| Feature | Sim | View, input, UI | AI | Lines | Art (per faction) | Wave |
| --- | --- | --- | --- | --- | --- | --- |
| Sale (§3) | `SELL` 17 | two-tap order, sold pack-up | never sells | ~250 | one glyph (shared) | 1 |
| Building repair (§4) | `MEND` 18, `Mend.run` | Mend toggle, wrench glyph | mends on Normal/Hard | ~300 | one glyph (shared) | 1 |
| Repair buildings (§5) | `Repair.run`, `REPAIR` service point | fx, Repair button | retreat to repair | ~690 | 1 building | 2 |
| Medics (§6) | role on a squad, seek | glow fx | rides with waves | ~150 | 1 squad | 2 |
| Ground carrier (§7) | eject on `Carry.gd` | ADR 0036's Board and Unload | rides in waves | ~250 | 1 vehicle | 3 |
| Mines (§8) | `LAY_MINE` 8, tables, memory | MineLayer, aim | lays, sweeps | ~1,420 | 1 vehicle, 3 marks | 3 |
| Hold position (§15) | `STANCE` 9, `stance`, TARGETING twin + kernel | Hold toggle | artillery holds | ~430 (C++ ~120) | one glyph (shared) | 3 |
| Ranks, patrol, hold fire (§15) | options | options | options | ~570 | none or glyphs | later updates |

Totals before launch: wave 1 about 550; wave 2 about 840; wave 3 about 2,100; about 3,490 in all,
of which about 120 are C++.

### 2. The interface with ADR 0036 (numbers, roles, modules)
| Item | Value | Owner | Meaning |
| --- | --- | --- | --- |
| Command 5 `LOAD` | ADR 0036 §8 | ADR 0036 | squads board an own carrier, air or ground |
| Command 6 `UNLOAD` | ADR 0036 §8 | ADR 0036 | a carrier unloads at a point |
| Command 7 `REPAIR` | ADR 0036 §7 | shared | units go to an own building with the role |
| Command 8 `LAY_MINE` | §8 | this ADR | layers lay a mine each round a point |
| Command 9 `STANCE` | §15 | this ADR | payload `[0]` normal, `[1]` hold position |
| Command 17 `SELL` | §3 | this ADR | sell an own finished building |
| Command 18 `MEND` | §4 | this ADR | switch a building's repair on or off |
| Command 19 | reserved | this ADR | `PATROL`, for a later update |
| Event 6 `UNLOADED` | ADR 0036 §8 | ADR 0036 | also written by an eject (§7) |
| Event 7 `MINE_BLAST` | §8 | this ADR | `[7, mine id, x, y, weapon, owner, 0, 0]` |
| Event 8 `REPAIRED` | §5 | shared | `[8, repairer id, x, y, unit id, owner, hp gained, 0]` |
| DIED flag 2 | boarded (`Carry.BOARDED` = -2) | ADR 0036 | no loss, no wreck |
| DIED flag 3 | sold (`SOLD` = -3 in `build_left`) | this ADR | no loss, no crater, the pack-up look |
| `carry_mode` 1 | unload on arrival | ADR 0036 | |
| `carry_mode` 2, 3 | lay on arrival, sweeping | this ADR | minelayers only (§8) |

- **`remove_dead`'s DIED flag** becomes a mapping of `build_left`: `Production.CANCELLED` (-1)
  -> 1, `Carry.BOARDED` (-2) -> 2, `SOLD` (-3) -> 3, anything else -> 0. Every view reader of the
  flag compares with the value it means (`== 1` for "cancelled"), never `!= 0` (§3).
- **The repair role.** ADR 0036 §2's fields keep their names but are declared on `UnitDef`
  (`BuildingDef extends UnitDef`, so an airfield's data reads the same). This ADR adds two fields
  whose defaults leave ADR 0036's airfield unchanged:
  - `repair_slots`: rows served per acting turn, most hurt share first, then id. A data test
    allows 1-8 for a type without pads and 0 only for a type with pads (the airfield's pads are
    its limit), so `REPAIRED` events stay bounded.
  - `repair_seek_milli`: an idle mobile row with the role walks to a hurt row in this reach (0 =
    never; buildings 0).
- **The ECONOMY order** becomes: `Power.run`, `Harvest.run`, `Air.run` (ADR 0036), `Carry.run`
  (ADR 0036), `Repair.run`, `Mend.run`, `Mines.lay` (§8).
- **Who repairs where.** `Air.run` (ADR 0036 §6) keeps every type with `type_pads > 0`.
  `Repair.run` (§5) serves every other type with `repair_classes != 0`. The two never serve one
  row: airfields serve AIR only, and the ground buildings and medics leave bit 8 off. Two ground
  repairers whose reaches overlap may both repair one row in one period, each at its own price;
  that is intended (two Weld Sheds side by side repair faster and cost more). P241b's "shared
  repair-role contract test" gains the cases of §16.
- **`REPAIR` names a building**, as ADR 0036 §7 requires. Medics are never a `REPAIR` target.
  A building without pads serves at its **footprint centre** (§5); ADR 0036's airfield serves at
  a pad.
- **Aircraft at the ground repair buildings:** no. The Weld Shed and the Drone Dock leave bit 8
  off, as ADR 0036 §7 recommends; "both" stays a data change.
- **`Carry.gd` is built once**, by whichever design's rows come first (ADR 0036 §7). The ground
  carrier adds data, `carry_eject_percent` (§7) and its art. Its rows depend on ADR 0036's P262,
  P263 and P263b. Should the lead want the ground carrier before the transport aircraft, those
  three rows move forward unchanged; no split of `Carry.gd` is needed.
- **Who builds the shared parts first.** The role needs its defs (ADR 0036's P231) and its World
  type tables (P232's rows, rules only, not hashed). P276 depends on both. If this ADR's rows run
  first, P276 adds the defs and the type tables and P231 and P232 drop them. If ADR 0036's P241b
  runs first, it builds `REPAIR` and P277 adds the footprint-centre service point; otherwise P277
  builds `REPAIR` and P241b adds the pads.

### 3. Selling a building (a gap; wave 1)
- **Rule.** `SELL` (17): `target_id` = an own complete building (`build_left` 0) of a type with
  `type_cost > 0`. The Headquarters (cost 0) and sites are refused (a site uses `CANCEL_BUILD`).
  - The owner gets `floor(type_cost * sell_refund_percent * hp / (100 * max_hp))` (int64) at once.
  - The row's hp becomes 0 and `build_left` becomes `SOLD` (-3; -1 is `Production.CANCELLED`,
    -2 is ADR 0036's `Carry.BOARDED`). REMOVE takes it out in the same tick: DIED with flag 3, no
    loss counted (`Outcome.count_losses` skips it as it skips a cancelled site), the footprint
    unblocked, the last-seen rules as for any death.
  - **The rest of the tick.** `Power`, `Combat`, `Harvest` and `Strike` already treat a row with
    `build_left != 0` as not complete, so a sold row makes and uses no power, fires nothing and
    takes no tanker for the phases left in the tick, as a site does.
  - **Queues and rally points are per player and tab**, not per building. Selling a producer
    keeps the queue; while the player has no other producer of that tab, its paid items wait with
    no refund, as when a producer is destroyed (the player can cancel them for the refund). Rally
    points stay.
  - Selling the last production building is allowed; `Outcome.run` then decides as for a loss.
    The Headquarters cannot be sold, so this happens only after it is lost (§3 Touch's question).
  - Blacked-out and low-power buildings may be sold.
- **Data.** `RulesDef.sell_refund_percent` (starting value 50).
- **View.** DIED flag 3: the building sinks behind a little dust, with no flash, no burst and no
  crater (`BuildingCollapse`'s steps without its flash and crater). An enemy sale looks the same
  where the player sees it. `EffectsLayer._add_death` and `BuildingCollapse.cancelled` change from
  `!= 0` to a match on the flag (1 nothing, 2 ADR 0036's climb-in, 3 the pack-up); the first of
  P272 and ADR 0036's P265 to land makes the switch.
- **Touch.** Own building selected: a `SELL` order on the command bar (56 x 64 dp, coin glyph).
  The first tap arms it: it turns amber and shows "+N" (the refund now). A second tap within
  `sell_confirm_ms` (`data/input_settings.tres`) sends `SELL`, with a buzz. Any other touch, or the
  time running out, disarms it. Never a hold (a resting thumb must not sell).
  - **Stronger confirm for the last producer.** When the building is the player's last production
    building, the second tap opens the question card that Surrender uses ("Selling it loses the
    match": Keep / Sell); only "Sell" sends the Command.
  - The order bar's new buttons are `touch-ui-rules` text and wait for Michael's yes, as ADR
    0036's P244 and P265 do.
  - Note (2026-11-09, P270b fix 1, after touch-ux-dev's docs lens): the second tap sends `SELL`
    only between `sell_arm_min_ms` (starting 400) and `sell_confirm_ms` (starting 3000) after
    the first; a tap before the minimum is ignored and keeps the arm. Both live in
    `data/input_settings.tres`. The Sell button keeps its place and a fixed width, so "+N" never
    shifts it.
  - Note (2026-11-11, P273): the Sell glyph is a price tag with a coin on it, not a bare coin: a bare
    coin would sit too close to `glyph_credits` and the Draw and Alert discs, and the tag avoids a "$",
    which is text.
- **AI.** Never sells (the managers have no rule that gains from it).
- **Size.** Sim ~90, view and UI ~160.

### 4. Repairing buildings (Michael's item 2 and a gap; wave 1)
- **Rule.** `MEND` (18): `target_id` = an own complete building, payload `[1]` on or `[0]` off.
  The switch is the building row's `cargo` (0 or 1; buildings never carry cargo, so this is a
  documented reuse, as ADR 0036 reuses `home` and `ready_tick`).
- **`Mend.run`** (ECONOMY, after `Power.run`, GDScript). Each mending building acts on ticks with
  `(tick + id) % mend_period_ticks == 0` (staggered by id):
  - hp rises by `mend_hp` (not above max);
  - the owner pays `ceil(type_cost * gained * mend_cost_percent / (100 * max_hp))`, the role's
    price rule; with too few credits nothing happens that period;
  - at full hp the switch goes back to 0.
  - It mends while blacked out, on low power and under fire. The Headquarters (cost 0) mends free;
    the rate is the limit.
- **Data.** `RulesDef.mend_hp` (starting 10), `mend_period_ticks` (15), `mend_cost_percent` (30).
- **The price rounds up per step.** `ceil` on each `mend_hp` step overcharges small steps: at 10 hp
  a step on a cheap, sturdy building costs up to about a third more than the nominal percent (and
  up to twice for the cheapest). This is accepted, as for ADR 0036's repair price: no cumulative
  state, and the balance run tunes the effective price, not the percent.
- **View.** An own mending building wears a wrench glyph (the offline glyph's pass). The snapshot's
  `cargo` holds enemy buildings' switches too (view data; the AI never reads the snapshot), so the
  view draws the glyph for own buildings only, and a view test pins that an enemy's switch draws
  nothing. `PlayerView.row_mend(row)` is own-only.
  - Note (2026-11-11, P273): the wrench over an own mending building is `glyph_repair_map`, the
    wrench on the map seat tinted #30A46C (STYLE.md v1.30); the plain `glyph_repair` is the HUD's.
- **Touch.** Own building selected: a **`MEND`** order (wrench glyph, the word "MEND"), lit while
  mending; a tap toggles. It is a different word from the units' Repair button (§5).
- **AI.** `AiEconomy` (Normal and Hard) switches it on for a building under
  `mend_below_percent` while credits stay above `mend_floor` (both in `AiDifficultyDef`).
  - Note (2026-11-12, P274; changes no accepted text above): the AI only switches `MEND` **on**; it
    never switches off, because `Mend.run` skips a period it cannot pay and ends the repair at full
    hp. It goes on when hp is under `mend_below_percent` percent of the maximum and the credits left
    after the whole think's spending (`credits - reserve_credits`, less what production queued: the
    quantity production itself spends) are strictly above `mend_floor`; a building that costs 0 (the
    Headquarters) goes on whatever they are. The Commands are sent after `AiProduction.run`, so they
    take only the budget production left. Values (ADR 0030 section 6's table): Easy 0 / 0 (never),
    Normal 50 / 400, Hard 70 / 250. The fields default to 0, an exception to "defaults equal the
    files" (ADR 0030 section 6).
- **Size.** Sim ~110, view and UI ~110, AI ~80.

### 5. Repairing vehicles: a building per faction (Michael's item 2)
- **Choice: a repair building, not a repair vehicle, for both factions.** Why:
  - one rule for ground and air: ADR 0036's role already repairs at a building, and `REPAIR`
    names a building, so one module, one contract test and one AI duty serve both designs;
  - page 1: a building is about 45-60 rows per faction, a 16-direction vehicle about 120-150;
  - base building: a repair point is a place worth defending and attacking;
  - the field heal the player wants is the medic's job for infantry (§6); a repair vehicle stays
    an option for a later update (the role already allows mobile rows).
- **Faction takes:**
  - **Weld Shed** (Derrick League, 2 x 2): an open steel shed with a crane arm and a welding
    flash. Vehicles park on its apron. Short reach, fast, few at a time.
  - **Drone Dock** (Lumen Accord, 2 x 2): a white ceramic rack of small hexagonal drones with
    mint lights. Drones fly out to vehicles in a wide reach. Slower per vehicle, more at a time.
- **Rule (`Repair.run`, ECONOMY after `Carry.run`, GDScript).** It reads the rows as REMOVE left
  them (positions after INTEGRATE, rows compacted), **never `target_grid`**, whose rows and
  positions are stale by ECONOMY (Context). The fix chosen: a bounded scan of the row table per
  acting repairer, not a second grid rebuild (a rebuild costs every tick; the scan only on acting
  turns).
  - `repair_rows`: the ascending rows of types with the role and no pads, a derived list rebuilt
    with `building_rows` when `rows_version` moves (`Power.run`, P71).
  - Staggering: the repairer at index `k` of `repair_rows` acts on ticks with
    `tick % repair_period_ticks == k % repair_period_ticks` (its type's period), so at most
    `ceil(R / period)` repairers act in one tick.
  - An acting repairer makes one pass over the rows: candidates are own rows (not itself) within
    `repair_reach_milli` of its service point (a building: its footprint centre, the row's
    position; a squad: its position) whose move-class bit is in `repair_classes` and hp < max.
    It keeps the best `repair_slots` in a fixed scratch (most hurt share `hp * 1000 / max_hp`
    first, then id).
  - Each kept row gains `repair_hp` (not above max) at the role's price (rounded up per step, as
    in §4; accepted); no pay, no repair. An `REPAIRED` event per repaired row.
  - A building acts only when complete and online (a blackout stops it; low power does not).
  - Cost: `stats[REPAIR_CHECKS]` += rows per acting repairer, at most `ceil(R / period) * rows`
    per tick.
- **`REPAIR` for this role** (P277): each valid unit gets the MOVE reset to its approach point
  (`Buildings.aim`, as `ATTACK` on a building: a ring tile next to the footprint); a unit the
  building's classes do not serve is skipped. Arrived rows stand idle and are repaired while in
  reach, ordered or not.
- **Reach covers the ring.** Reach is measured from the footprint centre, and `Buildings.aim`'s
  ring points of a 2 x 2 lie up to about 2,121 from it (a corner tile's centre). A data test pins,
  for every type with the role and a footprint, `repair_reach_milli` >= the farthest ring tile
  centre + 500 (half a tile of arrival slack), so a unit sent by `REPAIR` is always in reach.
- **Starting data.** Weld Shed: cost 800, power -20, requires the vehicle factory, classes 6,
  `repair_hp` 30 per 15 ticks, reach 2,700, slots 2, cost 25 %. Drone Dock: cost 800, power -30,
  requires the vehicle factory, classes 6, `repair_hp` 12 per 15 ticks, reach 5,000, slots 4,
  cost 35 %.
- **View.** From `REPAIRED`: at a Weld Shed, sparks on the vehicle (GroundFx ring); at a Drone
  Dock, a drone flies from the dock to the vehicle, hovers and returns (AirFx ring quota). An
  enemy's only where the player sees the vehicle.
- **Touch: one "Repair" button, no tap overload.** A tap on an own unit or building always
  selects it (ADR 0036 §12). While the selection holds a damaged ground row that a complete own
  repair building serves, the command bar shows **Repair** (48 dp, wrench). One tap sends one
  `REPAIR` with those rows to the nearest serving building (straight distance from those rows'
  centre, chosen by the view; the Command names it). Rows that building does not serve are left
  out; there is no aim.
  - **Repair and ADR 0036's Home are two buttons.** Home sends aircraft to their own airfields;
    Repair sends ground rows to the nearest repair building. A mixed selection shows both, and
    each sends only its own rows. Aircraft never go to a Weld Shed or a Drone Dock (bit 8 off).
  - The button is `touch-ui-rules` text and waits for Michael's yes (as ADR 0036's P244).
- **AI.** `AiProduction`: the repair building in the build orders after the vehicle factory
  (Normal and Hard). `AiArmy`: a vehicle under `repair_retreat_percent` that is not in a wave's
  fight goes `REPAIR` (Normal and Hard); Hard also sends damaged wave members between waves.
- **Size.** Sim ~250 (+~100 for `REPAIR`'s service point), view ~120, UI ~100, AI ~120.

### 6. Medics (Michael's item 3)
- **A squad with the repair role**, FOOT bit only (`repair_classes` 1), unarmed (`weapon` null),
  `repair_cost_percent` 0. It heals squads, never itself (a row skips itself), never drone squads
  (AIR class) or vehicles.
- **Seek.** In its acting turn's pass (§5, the same scan, no grid), an idle medic (order IDLE)
  with no hurt squad in reach takes the MOVE reset toward the most hurt own FOOT row within
  `repair_seek_milli`, as `Air.run` sends an aircraft home. A player's order always wins: a moving
  medic does not seek. Two medics may heal one squad in one period (intended, §2).
- **In orders.** A medic is unarmed, so `ATTACK` skips it (`_own_rows(armed)`). The input layer
  sends the unarmed rows of an attack selection an `ATTACK_MOVE` to the target's point in the same
  tick, so medics follow the army.
- **Faction takes.** **Patchers** (League): two figures in olive coveralls with a steel kit chest
  and a lamp; 110 hp, reach 1,500, 6 hp per 15 ticks, slots 1, seek 4,000. **Menders** (Accord):
  two lean figures with a white hexagonal case and a mint hand light; 70 hp, speed 1.2 tiles/s,
  reach 2,500, 8 hp per 15 ticks, slots 2, seek 6,000. Both cost 300, from the barracks.
- **No emblem.** No red cross, red crescent or red crystal anywhere (Geneva-protected emblems):
  each side's kit mark is its own (the League's an orange band, the Accord's a mint ring).
- **View.** A short soft glow on the healed squad from `REPAIRED` (AirFx ring quota).
- **AI.** `AiProduction`: `medic_per_squads` in the mix (data). `AiArmy`: medics join waves and the
  home squad and get `ATTACK_MOVE` or `MOVE`, never `ATTACK`.
- **Size.** Sim ~60 (seek; the heal is §5's), view ~40, AI ~50.

### 7. The infantry carrier on the ground (Michael's item 1)
- **`Carry.gd` as ADR 0036 §8 builds it**: `LOAD` (5) and `UNLOAD` (6); boarded squads leave the
  row table; `insert_row`; passengers count toward `unit_cap`; unloading on arrival in ECONOMY by
  a bounded ring search; squads with no room stay aboard. The ground carrier is a WHEELED or
  TRACKED type with `carry_slots > 0` and `carry_classes` 1 (squads only).
- **Load: ADR 0036's "Board" button.** Squads selected and an own carrier (air or ground) on the
  map: the Board button (48 dp) shows; tap it, then tap an own carrier with a free slot, then the
  check mark: one `LOAD`. The carrier drives to the squads, as in ADR 0036 §8. A tap on an own
  carrier without the aim selects it, as every own-unit tap does.
- **Unload: ADR 0036's "Unload" button.** A loaded carrier selected: tap Unload, tap the ground,
  then the check mark: the carrier drives there and unloads round itself.
- Both buttons are ADR 0036's; P294 only checks that they take a ground carrier (data, no code).
- **Can passengers fire?** No (question 2). Fire from inside would make the carrier fire several
  weapons, a TARGETING edit in the twin and the kernel; it is also the best-known look of other
  games' troop carriers.
- **When the carrier dies** (question 2): new type field `carry_eject_percent`.
  - 0: passengers die with it and count as lost (ADR 0036 §8's rule; aircraft keep 0).
  - Above 0: in the REMOVE mark, in `Carry.board`'s place (after `FogUpdate.begin`, before
    `remove_dead`), each carrier with hp <= 0 has its passengers inserted round its point by the
    same ring search (`insert_row`, ascending passenger order), each with
    `max(1, hp * carry_eject_percent / 100)`, order IDLE, `fog_cell` -1 and an `UNLOADED` event;
    those with no free cell, or refused at `max_rows`, die with the carrier as in ADR 0036 §8 and
    count as lost. Bounded by the dead carrier's slots.
- **Faction takes.** **Bunk Wagon** (League): tracked, HEAVY, a riveted steel crew box with a roof
  hatch and a ladder; speed 1.0 tiles/s, 700 hp, 4 slots, eject 50 %, cost 700. **Linecar**
  (Accord): wheeled, LIGHT, a low white car with a glass roof and side doors; speed 2.0 tiles/s,
  320 hp, 2 slots, eject 0 % (the light shell does not protect), cost 500. Both unarmed, from the
  vehicle factory.
- **View.** ADR 0036's climb-in for DIED flag 2; seat pips on the chip (P265). The carrier shows
  no load to the enemy (pillar 4 both ways).
- **AI.** Normal and Hard: `AiArmy` loads a wave's squads into idle carriers at the staging point
  (`ride_squads`), drives the wave, and unloads at `ride_unload_tiles` from the target; this
  shares ADR 0036's drop code (P267). Easy builds none.
- **Size.** Sim ~100 (eject), view ~0 (ADR 0036's), AI ~150.

### 8. Mines (Michael's item 4)
- **Laying.** `LAY_MINE` (8): unit ids = own rows with `type_mine_weapon >= 0`; a target point.
  - `Formation.assign` gives each layer a slot round the point; each gets the MOVE reset with
    `carry_mode` 2 ("lay on arrival").
  - **Every Command that gives a row an order zeroes its `carry_mode` first**: `_apply_point`
    (MOVE, ATTACK_MOVE), `_apply_attack`, `_apply_stop`, `LOAD`, `UNLOAD`, `REPAIR` and
    `LAY_MINE` itself (which then sets 2; ADR 0036's `UNLOAD` sets 1). So a new order cancels a
    pending lay or sweep, unpaid.
  - **The cell is the layer's own cell** (`cell_of` its position) when it has arrived (order
    IDLE), not the slot point, which may have been blocked.
  - Start, in `Mines.lay` (ECONOMY, last): the cell must be FOOT-passable, outside any footprint
    and hold no mine; the owner must have fewer than `mine_cap` mines and at least
    `type_mine_cost` credits. Then `ready_tick` = tick + `mine_lay_ticks`.
  - **At the lay tick every check runs again** (cell, cap, credits), in ascending row order; only
    then does the mine join the table and the cost get paid, and `carry_mode` goes to 0. So two
    layers that both started at 11 of 12 give one mine and one refusal, and credits never go
    below 0. Pending lays do not count toward the cap.
  - A refusal at either check sets `carry_mode` 0, pays nothing and counts
    `stats[MINES_REFUSED]`.
  - A mine arms `mine_arm_ticks` after it is laid.
- **The mine table** (hashed, section `mines`): `mine_id` (own counter `next_mine_id`, never a
  row id), `mine_owner`, `mine_cell`, `mine_weapon`, `mine_armed_tick`; scalar `mine_count`;
  ascending id, stable compaction; at most `mine_cap * player_count` entries. A derived
  `mine_at` (a cells-long array: table index + 1, 0 = none) is updated sparsely: a lay sets one
  cell, a removal clears one cell, and a compaction rewrites only the moved entries' cells; never
  a fill of the whole grid.
- **Trigger and blast** (`Mines.run`, in the FIRE mark after `Strike.run`, GDScript), in three
  steps, only while any armed mine exists:
  1. **Mark.** One pass over the rows in ascending order: a mobile row triggers the armed mine at
     `mine_at[cell_of(pos)]` when its owner is a player other than the mine's owner and not
     neutral, its layer bit is GROUND (aircraft and drone squads fly over, ADR 0036 §5), and its
     type is not mine-aware. The mine is marked in a fixed scratch byte array (the first trigger
     marks it; later ones change nothing).
  2. **Blast**, marked mines in ascending mine id: every GROUND mobile row of a player other than
     the owner within `weapon_blast_milli` of the cell centre loses
     `maxi(1, damage * percent / Combat.PERCENT)` with `percent` its armour's `vs_armour` entry
     (the pattern of `Strike._land`, `Strike.gd:209`; `Combat.damage` with dealt = taken = 100
     once ADR 0036's P246 has landed, which gives the same ints). Buildings take none. A
     `MINE_BLAST` event per mine; no chain to other mines.
  3. **Compact** the table once (stable), clearing `mine_at` sparsely.
  - So one tick is one result, whatever the order of the triggers.
- **Friendly fire (question 3): none.** The owner's rows never trigger its mines and never take
  their damage. So own units need no path around own mines (no flow-field change).
- **Other removals.** A rupture (`Strike.run` kind 1) clears every mine in its radius, any owner,
  with no blast. A building placed over a mine removes it silently, any owner (`Buildings.add`;
  the placer learns nothing). A defeated player's mines stay until the match ends.
- **The cap.** `RulesDef.mine_cap` (starting 12) per player, laid mines only. The `MINE` order
  shows "n/12"; at the cap it is dim and a lay is refused.
- **Who sees a mine, and detection (pillar 4).**
  - The owner always knows its mines (own state, no fog).
  - Another player knows a mine only by a **record** in its own block: `mine_seen_id`,
    `mine_seen_owner`, `mine_seen_cell`, `mine_seen_count` (hashed, section `mines`), at most
    `mine_known_cap` per player.
  - `MineMemory.run` (MEMORY, after `LastSeen.run`, on the player's fog turn, GDScript):
    - forget: a record whose cell is visible to the player now and whose mine is gone;
    - remember: an enemy mine whose cell is visible to the player now and lies within
      `type_detect_milli` of one of the player's detector rows (ascending mine id; none past the
      cap).
    - Bound: one pass over the rows to find the player's detectors, then detectors x enemy mines
      distance tests, on the player's fog turn only, counted in `stats[MINE_CHECKS]` (at most
      rows + detectors x `mine_cap * player_count`).
  - Detectors: both minelayers (3,000) and the scout tanks Flarejack and Swift (2,000). No other
    type detects. A blast does not make a record: the player sees the blast, not a mine.
  - The AI reads only `PlayerView.own_mines()` and `known_mines()` (its records), never the table.
- **Sweeping.** A mine-aware row (`type_mine_aware`, both minelayers) never triggers a mine. When
  one stands idle on the cell of an enemy mine its player has a record of, it takes `carry_mode`
  3 and `ready_tick` = tick + `sweep_ticks`; still there at that tick, the mine leaves the table
  with no blast. The player sends it with a plain ground tap on the mark: no new gesture.
- **Faction takes.** **Shot Truck** (League): a six-wheeled truck with a drill mast laid on its bed;
  it drills and drops a **shot charge**, a squat steel can with an orange cap: high damage, small
  blast (1,000), strong against vehicles; cost 60. **Seeder** (Accord): a light wheeled planter with
  a glass hopper and a planting arm; it plants a **pulse seed**, a white hexagonal spike with a mint
  light: less damage, a wider blast (1,500), better against squads; cost 50. Both unarmed, from the
  vehicle factory, require the radar.
- **Starting data.** `mine_lay_ticks` 22, `mine_arm_ticks` 15, `sweep_ticks` 30,
  `mine_known_cap` 24.
- **View** (`MineLayer`, an unsorted ground layer at z 3 under the units and fog, one `_draw`, its
  marks on page 2 or a small texture of their own, per P237). `GroundFx` and the selection rings
  are at z 3 too, so the tree order decides: `MineLayer` goes into `main.tscn` after
  `DecalLayer` and before `LifeFx`, so dust, wrecks and rings draw over the marks:
  - own mines always, in the owner's colour, at half alpha until armed;
  - a known enemy mine at full strength with a notched rim (the colour-free enemy cue of the
    health bars) while its cell is visible, dimmed like a building ghost while it is not; it goes
    when the record goes;
  - an unknown enemy mine is never drawn; a blast shows (burst and scorch) only where the player
    sees the cell; the radar shows no mines.
- **Touch.** Minelayers selected: a **Mine** button (48 dp, mine glyph, "n/12"). Tap it, tap the
  ground (a mark and the blast ring show), tap the check mark: one `LAY_MINE` for the selected
  layers; the aim ends. X, the button again or a turn of the phone ends it with nothing sent (the
  pattern of the strike aim and ADR 0036's Board and Unload aims). The button and its aim are
  `touch-ui-rules` text and wait for Michael's yes.
- **AI** (`AiMines`, run in `AiStrikes`' slot, Normal and Hard; Easy builds no layer):
  - lay up to `ai_mine_target` mines on own-half cells of the route between the own base and the
    enemy's last-known base (`AiMemory`'s staging point and the ghosts), `ai_mine_spacing` apart;
  - before a wave leaves, send a layer to sweep any known mine within `ai_sweep_reach` of the
    route; send scouts ahead on Hard;
  - fairness: every target comes from own mines, records, ghosts or seen rows.
- **Size.** Defs ~100, tables ~150, laying and blast ~300, memory and sweep ~250, view ~220, aim
  ~150, AI ~250 (§7's rides are a separate AI row of ~150).

### 9. Touch: how the new gestures fit (touch-ui-rules; ADR 0015)
| Feature | Gesture | Fits the existing set because |
| --- | --- | --- |
| Board | squads selected: Board button, tap own carrier, check mark | ADR 0036's Board button and aim; air and ground carriers alike |
| Unload | carrier selected: Unload button, tap ground, check mark | ADR 0036's Unload button and aim |
| Lay a mine | layers selected: Mine button, tap ground, check mark | the same aim pattern |
| Sweep | ground tap on a known enemy mark | a plain move |
| Repair a vehicle | Repair button (nearest serving building) | one button, no aim; beside ADR 0036's Home |
| Building repair | own building selected: Mend toggle | the command bar's orders; buildings now have some |
| Sell | own building selected: Sell twice (the question card for the last producer) | a two-tap confirm, never a hold |
| Hold position | units selected: Hold toggle | one button, no aim |

- Orders are `CommandBar.ORDERS` entries: at least 56 x 64 dp, scrolling sideways when they do
  not fit, so portrait and landscape need no new layout. Buildings get orders for the first time
  (an entry flag for buildings beside `units`).
- No new gesture kind and no tap overload: drag, pinch, tap, hold, long-press box and double-tap
  keep their meanings, and a tap on an own unit or building always selects it (ADR 0036 §12).
  A hold never sells, lays or loads.
- **Michael's yes to the `touch-ui-rules` skill text** (the Repair, Mend, Sell, Mine and Hold
  buttons, the Mine aim, the two-tap and the question confirm) is asked with the acceptance
  (P270b); P272, P282, P294 and P299 wait for it, as ADR 0036's P244 and P265 do.
- Note (2026-11-09, P270b, after fix 1): the `touch-ui-rules` text is accepted, Michael's "ja
  til touch-teksten", and applied to `.claude/skills/touch-ui-rules/SKILL.md` (the Repair, Mend,
  Sell, Mine and Hold buttons, the Mine aim, the two-tap and the question card). P272, P282, P294
  and P299 no longer wait for it.
- HOW_TO_PLAY gets each row in the PR that ships it. Teach: sell, Mend and Repair, Board and
  Unload, lay a mine, mines are hidden until found, Hold.

### 10. The AI, per feature (ADR 0030's managers; no new manager)
| Feature | Manager | Commands | Fairness |
| --- | --- | --- | --- |
| Sale | none | none | |
| Building repair | `AiEconomy` | `MEND` | own state |
| Repair building | `AiProduction`, `AiArmy` | `QUEUE`, `PLACE`, `REPAIR` | own rows |
| Medic | `AiProduction`, `AiArmy` | `QUEUE`, `MOVE`, `ATTACK_MOVE` | own rows |
| Ground carrier | `AiArmy` (P267's drop code) | `LOAD`, `UNLOAD` | targets from seen rows and ghosts |
| Mines | `AiMines` in `AiStrikes`' slot | `LAY_MINE`, `MOVE` (sweep) | own mines and records only |
| Hold position | `AiArmy` | `STANCE` | own state |

- `PlayerView` gains `row_mend` (own), `own_mines()`, `known_mines()` and the role, carrier and
  mine type tables (rules every player knows). It exposes no enemy mine, passenger or switch.
- Values live in `OpponentDef` and `AiDifficultyDef` (`mend_below_percent`, `mend_floor`,
  `repair_retreat_percent`, `medic_per_squads`, `ride_squads`, `ride_unload_tiles`,
  `ai_mine_target`, `ai_mine_spacing`, `ai_sweep_reach`, `hold_types`); Easy uses none of wave
  3's features.
- Each new unit type must be built in at least half the gate matches (ADR 0031 answer 2 A), so
  each is in the Normal build orders. ADR 0031 check 4 counts unit types only (ADR 0036's
  convention: 12 today, 16 with the aircraft, 20 with the transports): this ADR adds none in
  wave 1, the 2 medics in wave 2 (18 with the aircraft) and the 2 carriers and 2 minelayers in
  wave 3 (26 at the end of the block). The repair buildings are buildings and are not counted.

### 11. State and hashing (no new `STATE_FORMAT` number)
"Hash-neutral" here means the **state hash** only. Every row that adds a def field or a type table
changes `defs_hash`, which no literal pins.

| Wave | Hashed state | Format | Re-pin |
| --- | --- | --- | --- |
| 1 | none new: `MEND` writes `cargo` of buildings; `SELL` writes hp and `build_left` | unchanged | none (frozen arenas never sell or mend) |
| 2 | none new: the role is type tables (rules, `defs_hash`); `Repair.run` writes hp | ADR 0036's 6 | none of its own |
| 3 | the mine table, the records and the `stance` row column; `carry_mode` 2 and 3 in ADR 0036's column | ADR 0036's 7 | P286's own, after P262 |

- **P286 always follows P262** (P262 is already about 350 lines and cannot take the mine tables).
  It carries every layout change of this ADR: the mine tables, the records and `stance`. It keeps
  `STATE_FORMAT` 7, because nothing ships before the block ends (answer 1 A; were a format-7 build
  ever shipped first, it would take 8),
  regenerates the sanitizer's format-7 cases, and re-pins every golden and `TICK_0_SEED_1` once
  under **named exception 25** (23 is P232's, 24 P262's), or the next free number when it starts.
- New rules in `RulesDef` have inert defaults (`mine_cap` 0 means no mine can be laid), and the
  frozen arena defs (P171) are not edited, so rule rows move no golden.
- Note (2026-11-13, P286, as built; changes no accepted text above): `STATE_FORMAT` stays 7 and
  `HASH_OTHER_SECTIONS` becomes 9. New hashed state: the row column `stance` (after `carry_mode`,
  0 at spawn and in `insert_row`), the scalars `next_mine_id` (starts 1) and `mine_count` (after
  `pass_count`), the mine table `MINE_ARRAYS` (`mine_id`, `mine_owner`, `mine_cell`,
  `mine_weapon`, `mine_armed_tick`, `mine_cap * player_count` entries each) and the records
  `MINE_SEEN_ARRAYS` (`mine_seen_id`, `mine_seen_owner`, `mine_seen_cell`, entry
  `player * mine_known_cap + record`, and the per-player `mine_seen_count`), fed by the new last
  section `mines` (live records only: the mines, then the count of each player, then its live
  records; counts are clamped to the table). The derived `mine_at` (a cells-long array, in
  `DERIVED_ARRAYS`, never hashed) is sized with zeros at prepare; nothing sets it before P287. No
  rule reads any of it yet, no kernel reads `stance` yet (P298), so `world_access.h` is unchanged and
  the sanitizer dump holds no new record: `KNOWN_FORMATS` is unchanged and the format-7 dumps are
  generated afresh by `dump_states.gd` from the new layout. P298 adds `stance` to TARGETING's
  records in `dump_states.gd` and the harness's targeting case together with its kernel read.
  - **Re-pin (named exception 25), reason: the layout moved, no row, rule or run did.**
    `TICK_0_SEED_1` `dd094805d77cbf7b` -> `4dfd1c3d7396f979`. Perf arena `golden_hex`
    (ticks 150..900) `d7fce97f1f4229d2 ff7c653cbc7be349 e5f3955277e06182 34d0829654960906
    ad9eaacdcd957f66 8ffe4168214d0fa4` -> `3d6ee5b68fdf3aaa 83b8672e197796e8 239d8fdc35111c3b
    24579b30eff0005c 52d35946449b2e47 73862041b906657b`. Base arena `bases_golden_hex`
    `7a5eb4891f611f91 349b450ff49039a4 52cd92542829c287 af85350bb23c2fa4 9cb92c90602bf261
    57a2fbfa38637bc4` -> `b31651bd894038b0 66506a0dc32b4f77 dc36d8f12e83b2c6 f98b22aca3526511
    7c8de3ca5dfa2143 e333de062be19dd4`. Twin and kernels end on the same hashes; the arena
    stats pins (test_base_arena_run and the perf stats) did not move.

### 12. Native kernels: one edit (TARGETING, for hold position)
Every other rule here runs in COMMANDS, FIRE (after `Strike.run`), REMOVE, ECONOMY or MEMORY, all
GDScript only. Carried squads are not rows (ADR 0036 §8). Mines are not rows, so TARGETING, FOG and
SEPARATION never see them.

| Kernel | Edit | Test (row) |
| --- | --- | --- |
| TARGETING (`core/targeting.cpp`, `bind/kernel_targeting.cpp`; twin `Targeting.gd`) | `stance` joins the TARGETING checked list in `bind/world_access.h`; a stance-1 row on `ATTACK_MOVE` acquires at weapon range, never takes `CHASE`, and an `ATTACK` whose target is gone goes IDLE instead of attack-moving on (§15) | lockstep cases with mixed stances, the chase and the follow-up (P298); the sanitizer cases (P286's format-7 set gains the column) |

The port rule (ADR 0013 §1) is read at the `perf_bases` and `perf_air` lines with the new counters.
With every stance 0 the kernel's results are today's, so P298 moves no golden.

### 13. Budget (150 units at 60 fps; ADR 0011's limits)
| Feature | Sim time per tick (phone = desktop x 5.9) | Draw calls | Page 1 rows (both factions, bake 1.0, estimate) |
| --- | --- | --- | --- |
| Sale | once per Command | 0 (collapse layer) | 0 |
| Building repair | building rows / `mend_period_ticks` per tick, staggered: under 0.02 ms | 0 (glyph pass) | 0 |
| Repair buildings | at most `ceil(R / period)` repairers act per tick, each one pass over the rows: under 0.05 ms | 0 (GroundFx, AirFx rings) | ~105 (+ shadows on page 2) |
| Medics | as above, plus seek | 0 | ~135 |
| Ground carrier | ADR 0036's; eject on a death tick only | 0 | ~270 at 16 directions, ~135 at 8 |
| Hold position | one read of `stance` per acquiring row in TARGETING (twin and kernel): negligible | 0 | 0 |
| Mines | 0 with no armed mine; else one `mine_at` lookup per row: under 0.1 ms; detectors x mines on fog turns | +1 (`MineLayer`) | ~220 at 16, ~110 at 8; marks on page 2 |

- New counters: `stats[REPAIR_CHECKS]`, `stats[MINE_CHECKS]`, `stats[MINES_REFUSED]`, read by
  the perf suites as counted bounds (no timing runs in a session).
- No allocation per tick: fixed tables, scratch reused, events in the existing buffer.
- The page estimate comes from today's sheets' canvas area / 4,096 x 1.08 (the packing loss seen
  on today's page). P237 measures. **The ground set needs about 240 rows in wave 2 and 245-490
  in wave 3 on page 1.** ADR 0036's buildings need about 900-1,300. Both cannot fit unless P237's
  option (a) frees enough; the lead splits page 1 after P237's measurement. Fallbacks for the
  ground set, in order: 8 directions for the four new vehicles (half their rows); the repair
  buildings' damage stage at a lower scale (ADR 0036 §15 (b)); medics with one idle frame.
- Mirror matches double one faction's share (each player's sheets are baked in its colours).

### 14. Art and names
| Type | Kind | Directions | Frames per direction | Parts |
| --- | --- | --- | --- | --- |
| Weld Shed / Drone Dock | building 2 x 2 | 1 view | body, `dmg2` at 0.75 (ADR 0034: no `dmg1`), `anim` 6 / 4 | crane arm and flash / drone rack lights |
| Patchers / Menders | squad of two | 8 | 1 + walk 4 + idle 2 | shadow (page 2) |
| Bunk Wagon / Linecar | vehicle | 16 (8 as fallback) | 1 | hull, shadow (page 2), shared vehicle overlays |
| Shot Truck / Seeder | vehicle | 16 (8 as fallback) | 1 | hull with the mast or arm, shadow (page 2) |
| Shot charge / pulse seed | mark | none | own, known enemy (unarmed = own at half alpha) | page 2 or own texture |
| Drone (Accord fx) | fx | none | 2 (rotor blur) | fx atlas |
| Glyphs | UI | none | repair (Repair and Mend), sell, mine, hold (Board and Unload are ADR 0036's) | `assets/art/svg/icons/` |
| Item cards | UI | none | 8 | `assets/art/iso/icons/` |

- All by `tools/artgen/` or by hand in this repo (CLAUDE.md, Legal), in each faction's key band
  and team share (STYLE.md).
- **Legal screen (ADR 0023 §13 extended).** Refused names: APC, Minelayer, Medic, Mechanic,
  Engineer, Service Depot (Red Alert), Ambulance and Battle Bus (Generals), IFV and Battle Fortress
  (Red Alert 2), Repair Bay, Field Medic, Sapper, Combat Engineer. Refused looks: a red cross or
  crescent; passengers that change the carrier's gun (RA2's IFV); a small helicopter drone that
  rides on a vehicle (Generals). "No known hit" is not a trademark search: the lead adds the chosen
  names to Phase 7's search. Names are at most 10 characters (ADR 0032's one line; the data rows
  run the width test).

### 15. Hold position (answer 4 B, before launch) and the later gaps
- **What already holds today.** An idle unit acquires only within weapon range and never moves to
  fight (`Targeting.gd:182`): it fires at what comes into range. The chase happens on
  `ATTACK_MOVE` (acquire range, `CHASE`) and after an `ATTACK` (the row attack-moves on to where
  its target stood).
- **The rule.** `STANCE` (9): unit ids = own mobile rows, payload `[0]` normal or `[1]` hold.
  It writes the hashed row column `stance` (0 at spawn and at unload) and touches no order, so a
  held unit still obeys MOVE, ATTACK_MOVE and ATTACK. A stance-1 row:
  - on `ATTACK_MOVE`, acquires at weapon range, not acquire range, and never takes `CHASE`: it
    stops to fire at what is in range (`HOLD`, as today) and walks on along its path;
  - on `ATTACK`, steers at its target as ordered; when the target is gone it goes IDLE where it
    stands instead of attack-moving on;
  - idle, behaves as today.
  - The stance lasts until the player changes it; STOP keeps it.
- **Kernel.** TARGETING twin and kernel (§12): one read of `stance` in acquisition, one in
  engagement, one in the ATTACK fallback. Lockstep cases in P298. No other kernel reads it.
- **State.** The `stance` column comes with P286 (§11), so hold position lands in wave 3. If the
  lead wants it earlier, P298 can carry the column itself under its own exception (the next free
  one then) and `STATE_FORMAT`'s next number; this plan does not.
- **View and touch.** Units selected: a **Hold** toggle (48 dp, a shield glyph), lit when every
  selected unit holds; a tap sets all of them to hold, or to normal when all already hold. The
  selection chip shows a small shield on a type whose units hold. No world glyph (0 draw calls).
  `touch-ui-rules` text, waiting for Michael's yes (P270b).
- **AI.** Own state, so fair. Normal and Hard set hold on the types in `OpponentDef.hold_types`
  (the artillery of each faction, which has a minimum range and should not chase into it) when
  they join a wave. `PlayerView.row_stance` is own-only.
- **Size.** Sim ~110 (Command, apply, twin), C++ ~120, UI ~120, AI ~40, column ~40 in P286: ~430.
- **Tests.** Stance survives STOP, MOVE and unload; a held attack-mover never chases and walks on;
  a held ATTACK row goes IDLE when its target dies; idle rows unchanged; the lockstep cases; the
  golden unchanged with every stance 0.

**Later updates (not before launch):**
| Option | Rule | Cost |
| --- | --- | --- |
| Hold fire | stance 2: no acquisition; fires only at a target the player orders | the same column, one more kernel branch, +~40 |
| Patrol | `PATROL` 19: attack-move between the row's point and a target, flipping on arrival | `patrol_x`, `patrol_y` columns, ~150 sim, ~150 UI (a second point gesture) |
| Veterancy | `xp` column; a kill credits the shooter (`proj_shooter` id); ranks at `rank_kills`; rank 1 +10 % damage, rank 2 +20 % and self-heal | ~150 sim (FIRE, PROJECTILES), ~80 view (chevrons in the bar pass), page 0 |

Patrol and veterancy change hashed state; whichever update takes one takes its `STATE_FORMAT` bump
then.

### 16. Tests (what is proven headless)
- **Sale:** refund at full, half and 1 hp; HQ and site refused; `SOLD` -3 gives DIED flag 3 while
  -1 gives 1 and -2 gives 2; no loss counted; no power, fire or harvest from the sold row in its
  last tick; the queue keeps its paid items; last producer sold ends the match; replay hash equal.
- **Building repair:** on, off, stop at full, no pay no mend, staggered ticks, the price formula on
  edge ints, HQ free, blackout keeps mending.
- **Repair role (the shared contract test, P241b + P277):** classes mask; slots order (share, then
  id); `Air.run` and `Repair.run` never serve one row; two overlapping repairers stack; reach from
  the footprint centre, read after REMOVE (a row moved this tick is judged at its new place);
  staggering by rank; blackout stops a building; `REPAIR` skips unserved rows; the data test that
  reach covers every ring point; `REPAIRED` events at most `repair_slots` per acting repairer.
- **Medics:** heal squads only, not itself, not drone squads; seek only when idle; a moving medic
  never seeks; `ATTACK` selection gives medics `ATTACK_MOVE`.
- **Carrier:** ADR 0036's P262-P263b cases, plus eject 0 and 50 %: hp, cells, no-room deaths,
  losses, `UNLOADED` events, unit cap.
- **Mines:** lay cost, cap, footprint and passability refusals, arm delay; two layers at 11 of 12
  give one mine; credits never below 0; a new order zeroes `carry_mode`; trigger only by enemy
  GROUND non-aware rows; blast reach and no friendly damage; air passes; rupture clears; a building
  removes; two mines and two triggers in one tick (mark, blast, compact); `mine_at` equals a full
  rebuild after every step; records forget and remember; sweep; replay hash equal under twins and
  kernels.
- **Fairness (AI):** two worlds equal but for an unknown enemy mine give byte-equal AI Commands;
  the same for a loaded enemy carrier and an enemy's mend switch.
- **Perf:** counted bounds on `perf_bases` with repairers, medics and 24 mines; no new allocation
  (the existing allocation guard).
- **View and touch:** two-tap sell and its disarm; the question card for the last producer; the
  Mine aim at ADR 0015's six sizes; Repair beside Home in a mixed selection, each sending its own
  rows; a tap on an own building always selects; DIED flags 1, 2 and 3 each drawn as meant; the
  wrench only on own buildings; mine marks never drawn for an unknown enemy mine (a snapshot
  test); `MineLayer` under GroundFx in the tree; draw-call guard +1.
- **Hold position:** §15's cases; the lockstep cases under twins and kernels (P298).
- **Mutation testing:** P271, P276, P287, P288 and P298 (sim rows), about 10 chosen mutants each.

## Consequences
- **Gains:**
  - Michael's four items and two gaps with three new Commands and three shared with ADR 0036.
  - One kernel edit (TARGETING, hold position) and no `STATE_FORMAT` number of its own; wave 1
    re-pins nothing, and the whole ADR re-pins once (P286).
  - One repair role serves aircraft, vehicles, squads and (by data) more later.
  - Mines follow the last-seen pattern, so the AI and the human know the same things.
- **Costs:**
  - About 3,490 production lines before launch (about 120 of them C++), 8 generated models,
    3 marks, 4 glyphs.
  - About 240 page-1 rows in wave 2 and 245-490 in wave 3, competing with ADR 0036's buildings.
  - Six more unit types for ADR 0031's check 4 (26 at the end of the block) and longer runs.
  - The launch moves later by the block's length (ADR 0036's plan and this one together).
- **Risks:**
  - Mines could stall attacks on small maps: the cap, the cost, the detectors and the rupture
    are the counters; the balance run's match length watches it.
  - Repair could prolong fights: `repair_slots` and the price limit it.
  - Hold position may matter less than players expect, because idle units already never chase.
  - Reusing `cargo` for buildings: a later feature that gives buildings cargo must move the
    switch (a comment and a test pin it).
  - Two designs share `Carry.gd`, `REPAIR`, the role's tables, P262 and the DIED-flag readers:
    the lead merges them in the order of §2.
- **Out of scope:** a repair vehicle, carrying vehicles, passengers firing, mines on water, anti-air
  mines, remote detonation, mine fields as one order, auto-pathing round known mines, engineers
  that capture or repair by entering.

## Alternatives considered
- **A repair vehicle per faction (or both a vehicle and a building).** Not taken now: ~120-150
  page rows each and a second service rule; the role allows it later by data.
- **Mines as rows.** Not taken: TARGETING, SEPARATION and FOG would see them, four twin edits.
- **Mines visible to anyone who sees the cell.** Not taken: no hidden mine, no point to detectors.
- **Friendly-fire mines (the owner's units trigger them too).** Not taken: own units would need
  paths round own mines, a flow-field change; recommendation of question 3.
- **A new column for the mend switch.** Not taken: a layout bump before launch for one bit.
- **Passengers firing from inside.** Not taken: a TARGETING edit with multiple weapons per row,
  and the best-known look of other games' carriers (question 2 B).
- **A sixth AI manager.** Not taken: ADR 0030's slot plan stays; mines run in `AiStrikes`' slot.

## Questions for Michael
**Answered by Michael on 2026-11-09 (in chat, through the lead): 1 A, 2 A, 3 A, 4 B, 5 A.** So:
everything before launch, after the Phase 4 gate and before Phase 5, in one block with ADR 0036;
passengers cannot fire, the Bunk Wagon's squads get out at half hp and the Linecar's die; own mines
never trigger under own units and never hurt them; hold position before launch, ranks and patrol
later; the names as listed. The questions stand below as they were asked.

1. **When.**
   - A: everything after the Phase 4 gate, before launch (about 3,060 lines and 8 models; launch
     about 2-3 weeks later, and the tutorial must teach all of it).
   - B (recommended): sale and building repair in version 1 (~550 lines, no new picture, about 2-3
     days); repair buildings and medics in update 1.1 with the aircraft (~840 lines, 4 models);
     the carrier and mines in update 1.2 with the transport aircraft (~1,670 lines, 4 models).
   - C: nothing before launch; 1.1 and 1.2 as in B, sale and building repair in 1.1.
2. **The carrier.**
   - A (recommended): passengers cannot fire from inside; when it dies, the Bunk Wagon's squads
     get out with half their health and the Linecar's die (as in the transport aircraft).
   - B: as A, but the Bunk Wagon's squads also fire from inside (about +350 lines with a C++
     kernel edit, and it looks like other games' carriers).
   - C: as A, but every carrier's squads die with it (about 100 lines less).
3. **Mines and your own units.**
   - A (recommended): your mines never go off under your units and never hurt them.
   - B: they never go off under your units, but a blast hurts everyone in reach, yours too (as the
     Deep Bore does).
   - C: your units set them off too (your units would need to drive round your own mines: a costly
     path change, about +400 lines).
4. **Ranks, hold position, patrol.**
   - A (recommended): later updates, hold position first, then ranks, then patrol.
   - B: hold position already in version 1 (about +430 lines including a C++ kernel edit).
   - C: none planned.
5. **Names.**
   - A (recommended): Weld Shed, Drone Dock, Patchers, Menders, Bunk Wagon, Linecar, Shot Truck,
     Seeder, shot charge, pulse seed. Bunk Wagon echoes the Bunkhouse and Linecar the Linemen on
     purpose: each side's carrier sounds like its own crews.
   - B: as A, but Ironbox for the Bunk Wagon and Lightcar for the Linecar (no echo).
   - Or name the ones to change.
