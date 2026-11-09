# ADR 0037: Ground support: building sale and repair, repair buildings, medics, carriers, mines

**In short, for Michael:** four things you asked for, and four gaps the lead found:
- **Sell a building** for part of its price, and **repair a building** with a switch that costs
  credits while it works. Both are small and need no new picture, so they can be in version 1.
- **Repair of damaged vehicles** happens at a new building per side: the Derrick League's
  **Weld Shed** (a workshop where vehicles park on the apron) and the Lumen Accord's **Drone Dock**
  (small drones fly out to vehicles nearby). A building, not a vehicle; the reasons are in §5.
- **Medics** heal infantry squads near them: the League's **Patchers**, the Accord's **Menders**.
- **An infantry carrier** per side: the League's **Bunk Wagon** (slow, armoured, more seats) and the
  Accord's **Linecar** (fast, light). Squads ride inside and cannot shoot from it. It uses the same
  loading rules as the air design's transport aircraft (ADR 0036).
- **Mines**, laid by the League's **Shot Truck** and the Accord's **Seeder**. A mine is hidden from
  the enemy until one of its mine-layers or scout cars finds it. Your own mines never hurt you.
- **Ranks, hold position and patrol** are options for later updates.

The recommendation splits the work over three releases, with the air design's updates: sale and
building repair in version 1, repair buildings and medics in update 1.1 (with the aircraft), the
carrier and mines in update 1.2 (with the transport aircraft). Five questions are at the end.

Status: **proposed, 2026-11-09** (architect, branch `claude/design-ground-support`, base `main` at
b6bfe95; reconciled the same day with ADR 0036 at e01ee4c on `claude/design-air-and-tech`). Not
accepted. The lead accepts it in docs row P270b of `docs/plans/2026-11-09-ground-support.md` once
Michael has answered. Nothing here is built before the Phase 4 gate.

Amends, on acceptance, by dated notes the lead writes in P270b (accepted text stays as it is):
- ADR 0036 §2 and §7: the repair role moves from `BuildingDef` to `UnitDef` (a squad may hold it;
  `BuildingDef` extends `UnitDef`, so every name stays) and gains `repair_slots` and
  `repair_seek_milli`; §8 gains `carry_eject_percent` (0 keeps §8's rule: passengers die).
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
- **ADR 0036 (proposed, e01ee4c)** already designs, for the air layer:
  - `LOAD = 5`, `UNLOAD = 6`, `REPAIR = 7` as shared Command types;
  - the repair role (`repair_classes`, a move-class mask with FOOT 1, WHEELED 2, TRACKED 4, AIR 8;
    `repair_hp` per `repair_period_ticks`; `repair_cost_percent`; `repair_reach_milli`);
  - `Carry.gd`: boarded squads leave the row table for a passenger table and return with their id
    through `World.insert_row`; DIED flag 2 = boarded; event `UNLOADED` = 6; `carry_mode`;
  - `STATE_FORMAT` 6 for update 1.1 (air) and 7 for 1.2 (passengers);
  - the page rule: y-sorted items stay on page 1; page 2 holds unsorted layers; art-director's
    P237 (the page-2 split and probe) lands before any new art row.
  - Plan rows P230-P269. This plan therefore starts at **P270** (the lead's P260 was taken).
- **The atlas page** is 3,550 of 3,584 rows (cross-faction), ADR 0035's polish frees about 100,
  and ADR 0036's new buildings alone need more than page 1 has left. Every unit and building here
  is y-sorted, so it competes for page 1.

## Decisions in short
1. Releases (recommended, question 1): sale and building repair in version 1; repair buildings and
   medics in 1.1; the ground carrier and mines in 1.2. No feature changes a kernel.
2. Shared with ADR 0036: Commands 5, 6 and 7 with its meanings; this ADR adds `LAY_MINE = 8`,
   `SELL = 17`, `MEND = 18`; events `MINE_BLAST = 7`, `REPAIRED = 8`; DIED flag 3 = sold.
3. Sale: `SELL` refunds `sell_refund_percent` of the price, scaled by hp left; two taps on a phone.
4. Building repair: `MEND` toggles a paid repair that stops at full hp; the switch lives in the
   building row's unused `cargo`, so version 1 changes no state layout and re-pins nothing.
5. Vehicle repair is a building per faction on ADR 0036's repair role, served through `REPAIR`.
6. Medics are squads with the same role (FOOT bit), healing squads in reach, walking to hurt ones.
7. The ground carrier is a data entry on `Carry.gd`; `carry_eject_percent` lets the League's
   passengers get out hurt when it dies, while the Accord's (and the aircraft's) die.
8. Mines: one-shot, enemy ground units trigger them, own units never trigger or take damage; a
   player knows an enemy mine only through a detector's record kept like a last-seen building.
9. Mines and their records ride `STATE_FORMAT` 7 (ADR 0036's 1.2 bump); no new bump anywhere.
10. Art rows wait for P237; the ground set asks page 1 for about 240 rows in 1.1 and 245-490 in 1.2.

## Decision

### 1. Features, sizes and releases
Sizes are production lines (tests, fixtures and `.tres` do not count). Release is the
recommendation of question 1.

| Feature | Sim | View, input, UI | AI | Lines | Art (per faction) | Release |
| --- | --- | --- | --- | --- | --- | --- |
| Sale (§3) | `SELL` 17 | two-tap order, sold pack-up | never sells | ~250 | one glyph (shared) | version 1 |
| Building repair (§4) | `MEND` 18, `Mend.run` | toggle order, wrench glyph | mends on Normal/Hard | ~300 | one glyph (shared) | version 1 |
| Repair buildings (§5) | `Repair.run`, `REPAIR` dock point | fx, REPAIR button and tap | retreat to repair | ~690 | 1 building | 1.1 |
| Medics (§6) | role on a squad, seek | glow fx | rides with waves | ~150 | 1 squad | 1.1 |
| Ground carrier (§7) | eject on `Carry.gd` | ADR 0036's taps | rides in waves | ~250 | 1 vehicle | 1.2 |
| Mines (§8) | `LAY_MINE` 8, tables, memory | MineLayer, aim | lays, sweeps | ~1,420 | 1 vehicle, 3 marks | 1.2 |
| Ranks, stances, patrol (§15) | options | options | options | ~1,150 | none or glyphs | later |

Totals: version 1 about 550; 1.1 about 840; 1.2 about 1,670; about 3,060 in all, with no C++.

### 2. The interface with ADR 0036 (numbers, roles, modules)
| Item | Value | Owner | Meaning |
| --- | --- | --- | --- |
| Command 5 `LOAD` | ADR 0036 §8 | ADR 0036 | squads board an own carrier, air or ground |
| Command 6 `UNLOAD` | ADR 0036 §8 | ADR 0036 | a carrier unloads at a point |
| Command 7 `REPAIR` | ADR 0036 §7 | shared | units go to an own building with the role |
| Command 8 `LAY_MINE` | §8 | this ADR | layers lay a mine each round a point |
| Command 9 | reserved | this ADR | `STANCE`, if question 4 brings it |
| Command 17 `SELL` | §3 | this ADR | sell an own finished building |
| Command 18 `MEND` | §4 | this ADR | switch a building's repair on or off |
| Command 19 | reserved | this ADR | `PATROL`, if question 4 brings it |
| Event 6 `UNLOADED` | ADR 0036 §8 | ADR 0036 | also written by an eject (§7) |
| Event 7 `MINE_BLAST` | §8 | this ADR | `[7, mine id, x, y, weapon, owner, 0, 0]` |
| Event 8 `REPAIRED` | §5 | shared | `[8, repairer id, x, y, unit id, owner, hp gained, 0]` |
| DIED flag 2 | boarded | ADR 0036 | no loss, no wreck |
| DIED flag 3 | sold | this ADR | no loss, no crater, the pack-up look |
| `carry_mode` 1 | unload on arrival | ADR 0036 | |
| `carry_mode` 2, 3 | lay on arrival, sweeping | this ADR | minelayers only (§8) |

- **The repair role.** ADR 0036 §2's fields, by its names, move from `BuildingDef` to `UnitDef`
  (`BuildingDef extends UnitDef`, so an airfield's data reads the same). This ADR adds two fields,
  both 0 by default, so ADR 0036's airfield is unchanged:
  - `repair_slots`: rows served per period, most hurt share first, then id (0 = every row in
    reach);
  - `repair_seek_milli`: an idle mobile row with the role walks to a hurt row in this reach (0 =
    never; buildings 0).
- **Who repairs where.** `Air.run` (ADR 0036 §6) keeps every type with `type_pads > 0`.
  `Repair.run` (§5) serves every other type with `repair_classes != 0`. A row is never repaired
  twice in one period. P241b's "shared repair-role contract test" gains the cases of §16.
- **`REPAIR` names a building**, as ADR 0036 §7 requires. Medics are never a `REPAIR` target.
  A building without pads serves at its dock (`Buildings.aim`'s approach point); ADR 0036's
  airfield serves at a pad.
- **Aircraft at the ground repair buildings:** no. The Weld Shed and the Drone Dock leave bit 8
  off, as ADR 0036 §7 recommends; "both" stays a data change.
- **`Carry.gd` is built once**, by whichever release comes first (ADR 0036 §7). The ground carrier
  adds data, `carry_eject_percent` (§7) and its art. Its rows depend on ADR 0036's P262, P263 and
  P263b. If Michael wants the ground carrier before the transport aircraft, those three rows move
  forward unchanged and the aircraft's data comes later; no split of `Carry.gd` is needed.
- **Who builds the shared parts first.** If this ADR's 1.1 rows run before ADR 0036's P231, P276
  writes the role's defs and P231 drops them. If ADR 0036's P241b runs first, it builds `REPAIR`
  and P277 adds the dock service point; otherwise P277 builds `REPAIR` and P241b adds the pads.

### 3. Selling a building (gap option; recommended for version 1)
- **Rule.** `SELL` (17): `target_id` = an own complete building (`build_left` 0) of a type with
  `type_cost > 0`. The Headquarters (cost 0) and sites are refused (a site uses `CANCEL_BUILD`).
  - The owner gets `floor(type_cost * sell_refund_percent * hp / (100 * max_hp))` (int64) at once.
  - The row's hp becomes 0 and `build_left` becomes `SOLD` (-2). REMOVE takes it out in the same
    tick: DIED with flag 3, no loss counted (`Outcome.count_losses` skips it as it skips a
    cancelled site), the footprint unblocked, the last-seen rules as for any death.
  - Selling the last producer is allowed; `Outcome.run` then decides as for a loss.
  - Blacked-out and low-power buildings may be sold.
- **Data.** `RulesDef.sell_refund_percent` (starting value 50).
- **View.** DIED flag 3: the building sinks behind a little dust, with no flash, no burst and no
  crater (`BuildingCollapse`'s steps without its flash and crater). An enemy sale looks the same
  where the player sees it.
- **Touch.** Own building selected: a `SELL` order on the command bar (56 x 64 dp, coin glyph).
  The first tap arms it: it turns amber and shows "+N" (the refund now). A second tap within
  `sell_confirm_ms` (`data/input_settings.tres`) sends `SELL`, with a buzz. Any other touch, or the
  time running out, disarms it. Never a hold (a resting thumb must not sell).
- **AI.** Never sells (the managers have no rule that gains from it).
- **Size.** Sim ~90, view and UI ~160.

### 4. Repairing buildings (Michael's item 2 and a gap; recommended for version 1)
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
- **View.** An own mending building wears a wrench glyph (the offline glyph's pass, own only,
  because the switch is own state like power). `PlayerView.row_mend(row)` is own-only.
- **Touch.** Own building selected: a `REPAIR` order (wrench), lit while mending; tap toggles.
- **AI.** `AiEconomy` (Normal and Hard) switches it on for a building under
  `mend_below_percent` while credits stay above `mend_floor` (both in `AiDifficultyDef`).
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
- **Rule (`Repair.run`, ECONOMY after `Air.run`, GDScript).** For each row with the role and no
  pads, in ascending row order, on ticks with `(tick + id) % repair_period_ticks == 0`:
  - candidates: own rows within `repair_reach_milli` of the service point (a building: its dock
    point; a squad: its position) whose move-class bit is in `repair_classes` and hp < max,
    found through `target_grid` (rebuilt in GRIDS; a bounded cell query);
  - up to `repair_slots` of them, most hurt share first (`hp * 1000 / max_hp`), then id;
  - each gains `repair_hp` (not above max) at the role's price; no pay, no repair;
  - an `REPAIRED` event per repaired row;
  - a complete, online building only (a blackout stops it; low power does not).
- **`REPAIR` for this role** (P277): each valid unit gets the MOVE reset to the building's dock
  point (`Buildings.aim`, as `ATTACK` on a building); a unit the building's classes do not serve is
  skipped. Arrived rows stand idle and are repaired while in reach, ordered or not.
- **Starting data.** Weld Shed: cost 800, power -20, requires the vehicle factory, classes 6,
  `repair_hp` 30 per 15 ticks, reach 2,000, slots 2, cost 25 %. Drone Dock: cost 800, power -30,
  requires the vehicle factory, classes 6, `repair_hp` 12 per 15 ticks, reach 5,000, slots 4,
  cost 35 %.
- **View.** From `REPAIRED`: at a Weld Shed, sparks on the vehicle (GroundFx ring); at a Drone
  Dock, a drone flies from the dock to the vehicle, hovers and returns (AirFx ring quota). An
  enemy's only where the player sees the vehicle.
- **Touch.** With damaged units selected that one of your repair buildings serves, the command bar
  shows `REPAIR` (wrench): it sends `REPAIR` to the nearest such building (straight distance from
  the selection's centre, chosen by the view; the Command names it). A tap on your own repair
  building with such units selected sends `REPAIR` to that one (ADR 0036 §12's rule: a tap on an
  own building that serves the selection orders, otherwise it selects).
- **AI.** `AiProduction`: the repair building in the build orders after the vehicle factory
  (Normal and Hard). `AiArmy`: a vehicle under `repair_retreat_percent` that is not in a wave's
  fight goes `REPAIR` (Normal and Hard); Hard also sends damaged wave members between waves.
- **Size.** Sim ~250 (+~100 for `REPAIR`'s dock point), view ~120, UI ~100, AI ~120.

### 6. Medics (Michael's item 3)
- **A squad with the repair role**, FOOT bit only (`repair_classes` 1), unarmed (`weapon` null),
  `repair_cost_percent` 0. It heals squads, never itself (a row skips itself), never drone squads
  (AIR class) or vehicles.
- **Seek.** In `Repair.run`, an idle medic (order IDLE) with no hurt squad in reach takes the MOVE
  reset toward the most hurt own FOOT row within `repair_seek_milli`, as `Air.run` sends an
  aircraft home. A player's order always wins: a moving medic does not seek.
- **In orders.** A medic is unarmed, so `ATTACK` skips it (`_own_rows(armed)`). The input layer
  sends the unarmed rows of an attack selection an `ATTACK_MOVE` to the target's point in the same
  tick, so medics follow the army.
- **Faction takes.** **Patchers** (League): two figures in olive coveralls with a steel kit chest
  and a lamp; 110 hp, reach 1,500, 6 hp per 15 ticks, seek 4,000. **Menders** (Accord): two lean
  figures with a white hexagonal case and a mint hand light; 70 hp, speed 1.2 tiles/s, reach
  2,500, 8 hp per 15 ticks, seek 6,000. Both cost 300, from the barracks.
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
- **Load.** Squads selected + tap an own carrier with a free slot = `LOAD`; carrier selected + tap
  an own squad = `LOAD` (ADR 0036 §12). The carrier drives to the squad, as there.
- **Unload.** A loaded carrier shows ADR 0036's `UNLOAD` order; tap it, tap the ground, then the
  check mark: the carrier drives there and unloads round itself.
- **Can passengers fire?** No (question 2). Fire from inside would make the carrier fire several
  weapons, a TARGETING edit in the twin and the kernel; it is also the best-known look of other
  games' troop carriers.
- **When the carrier dies** (question 2): new type field `carry_eject_percent`.
  - 0: passengers die with it and count as lost (ADR 0036 §8's rule; aircraft keep 0).
  - Above 0: in REMOVE, after the carrier's death, its passengers are inserted round its point by
    the same ring search, each with `max(1, hp * carry_eject_percent / 100)`, order IDLE, an
    `UNLOADED` event; those with no free cell die and count as lost.
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
  - On arrival (order IDLE) in `Mines.lay` (ECONOMY): the cell must be FOOT-passable, outside
    any footprint and hold no mine, the owner must have fewer than `mine_cap` mines and at least
    `type_mine_cost` credits. Then `ready_tick` = tick + `mine_lay_ticks`; at that tick the mine
    joins the table, the cost is paid and `carry_mode` goes to 0. Any new order cancels it unpaid.
    A refusal sets `carry_mode` 0 and counts `stats[MINES_REFUSED]`.
  - A mine arms `mine_arm_ticks` after it is laid.
- **The mine table** (hashed, section `mines`): `mine_id` (own counter `next_mine_id`, never a
  row id), `mine_owner`, `mine_cell`, `mine_weapon`, `mine_armed_tick`; scalar `mine_count`;
  ascending id, stable compaction; at most `mine_cap * player_count` entries. A derived
  `mine_at` (cell -> table index + 1) is rebuilt when the table changes.
- **Trigger and blast** (`Mines.run`, in the FIRE mark after `Strike.run`, GDScript). One pass
  over the mobile rows, while any armed mine exists: a row triggers the mine on its cell when the
  row's owner is a player other than the mine's owner and not neutral, its layer bit is GROUND
  (aircraft and drone squads fly over, ADR 0036 §5), and its type is not mine-aware. Then:
  - every GROUND mobile row of a player other than the owner within `weapon_blast_milli` of the
    cell centre takes the weapon's damage (`Combat.damage`, ADR 0036 §10, or today's formula);
  - buildings take none; the mine leaves the table; a `MINE_BLAST` event; no chain to other mines.
  - Rows are visited in ascending row order and mines blast in that order, so one tick is one
    result.
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
      `type_detect_milli` of one of the player's rows (ascending mine id; none past the cap).
  - Detectors: both minelayers (3,000) and the scout cars Flarejack and Swift (2,000). No other
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
  marks on page 2 or a small texture of their own, per P237):
  - own mines always, in the owner's colour, at half alpha until armed;
  - a known enemy mine at full strength with a notched rim (the colour-free enemy cue of the
    health bars) while its cell is visible, dimmed like a building ghost while it is not; it goes
    when the record goes;
  - an unknown enemy mine is never drawn; a blast shows (burst and scorch) only where the player
    sees the cell; the radar shows no mines.
- **Touch.** Minelayers selected: a `MINE` order (mine glyph, "n/12"). Tap it, tap the ground (a
  mark and the blast ring show), tap the check mark: one `LAY_MINE` for the selected layers; the
  aim ends. X, the order again or a turn of the phone ends it with nothing sent (the strike aim's
  pattern, `StrikeAim`).
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
| Board | squads selected + tap own carrier; carrier selected + tap own squad | ADR 0036 §12's rule: a tap on an own unit or building that serves the selection orders, else selects |
| Unload | `UNLOAD` order, tap ground, check mark | the strike aim's pattern (check mark and X beside the button) |
| Lay a mine | `MINE` order, tap ground, check mark | the same aim pattern |
| Sweep | ground tap on a known enemy mark | a plain move |
| Repair a vehicle | `REPAIR` order, or tap own repair building | the serve-tap rule; one button |
| Building repair | own building selected, `REPAIR` toggle | the command bar's orders, buildings now have some |
| Sell | own building selected, `SELL` twice | a two-tap confirm, never a hold |

- Orders are `CommandBar.ORDERS` entries: at least 56 x 64 dp, scrolling sideways when they do
  not fit, so portrait and landscape need no new layout. Buildings get orders for the first time
  (an entry flag for buildings beside `units`).
- No new gesture kind: drag, pinch, tap, hold, long-press box and double-tap keep their meanings.
  A hold never sells, lays or loads.
- HOW_TO_PLAY gets each row in the PR that ships it. Teach: sell, repair (both), load and unload,
  lay a mine, mines are hidden until found.

### 10. The AI, per feature (ADR 0030's managers; no new manager)
| Feature | Manager | Commands | Fairness |
| --- | --- | --- | --- |
| Sale | none | none | |
| Building repair | `AiEconomy` | `MEND` | own state |
| Repair building | `AiProduction`, `AiArmy` | `QUEUE`, `PLACE`, `REPAIR` | own rows |
| Medic | `AiProduction`, `AiArmy` | `QUEUE`, `MOVE`, `ATTACK_MOVE` | own rows |
| Ground carrier | `AiArmy` (P267's drop code) | `LOAD`, `UNLOAD` | targets from seen rows and ghosts |
| Mines | `AiMines` in `AiStrikes`' slot | `LAY_MINE`, `MOVE` (sweep) | own mines and records only |

- `PlayerView` gains `row_mend` (own), `own_mines()`, `known_mines()` and the role, carrier and
  mine type tables (rules every player knows). It exposes no enemy mine, passenger or switch.
- Values live in `OpponentDef` and `AiDifficultyDef` (`mend_below_percent`, `mend_floor`,
  `repair_retreat_percent`, `medic_per_squads`, `ride_squads`, `ride_unload_tiles`,
  `ai_mine_target`, `ai_mine_spacing`, `ai_sweep_reach`); Easy uses none of the 1.2 features.
- Each new type must be built in at least half the gate matches (ADR 0031 answer 2 A), so each is
  in the Normal build orders.

### 11. State and hashing (no new `STATE_FORMAT` bump)
| Release | Hashed state | Format | Re-pin |
| --- | --- | --- | --- |
| Version 1 | none new: `MEND` writes `cargo` of buildings; `SELL` writes hp and `build_left` | unchanged | none (frozen arenas never sell or mend) |
| 1.1 | none new: the role is type tables (rules, `defs_hash`); `Repair.run` writes hp | ADR 0036's 6 | none of its own |
| 1.2 | the mine table and the records; `carry_mode` 2 and 3 in ADR 0036's column | ADR 0036's 7 | rides P262's |

- The mine tables join ADR 0036's `STATE_FORMAT` 7. If P286 merges before P262, P262 carries
  them and re-pins once. If P262 merged first and 1.2 has not shipped, P286 keeps format 7 and
  re-pins the goldens once more under P262's exception.
- New rules in `RulesDef` have inert defaults (`mine_cap` 0 means no mine can be laid), and the
  frozen arena defs (P171) are not edited, so rule rows move no golden.

### 12. Native kernels: none
Every rule here runs in COMMANDS, FIRE (after `Strike.run`), REMOVE, ECONOMY or MEMORY, all
GDScript only. Carried squads are not rows (ADR 0036 §8). Mines are not rows, so TARGETING, FOG and
SEPARATION never see them. Stances (§15) would be the first kernel edit and are not in this plan.
The port rule (ADR 0013 §1) is read at the `perf_bases` and `perf_air` lines with the new counters.

### 13. Budget (150 units at 60 fps; ADR 0011's limits)
| Feature | Sim time per tick (phone = desktop x 5.9) | Draw calls | Page 1 rows (both factions, bake 1.0, estimate) |
| --- | --- | --- | --- |
| Sale | once per Command | 0 (collapse layer) | 0 |
| Building repair | building rows / `mend_period_ticks` per tick, staggered: under 0.02 ms | 0 (glyph pass) | 0 |
| Repair buildings | repairers / period, each a bounded grid query: under 0.05 ms | 0 (GroundFx, AirFx rings) | ~105 (+ shadows on page 2) |
| Medics | as above, plus seek | 0 | ~135 |
| Ground carrier | ADR 0036's; eject on a death tick only | 0 | ~270 at 16 directions, ~135 at 8 |
| Mines | 0 with no armed mine; else one lookup per mobile row: under 0.1 ms; memory on fog turns | +1 (`MineLayer`) | ~220 at 16, ~110 at 8; marks on page 2 |

- New counters: `stats[REPAIR_CHECKS]`, `stats[MINE_CHECKS]`, `stats[MINES_REFUSED]`, read by
  the perf suites as counted bounds (no timing runs in a session).
- No allocation per tick: fixed tables, scratch reused, events in the existing buffer.
- The page estimate comes from today's sheets' canvas area / 4,096 x 1.08 (the packing loss seen
  on today's page). P237 measures. **The ground set needs about 240 rows in 1.1 and 245-490 in
  1.2 on page 1.** ADR 0036's buildings need about 900-1,300. Both cannot fit unless P237's
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
| Glyphs | UI | none | repair, sell, mine (unload is ADR 0036's) | `assets/art/svg/icons/` |
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

### 15. The other gaps: options, none decided (question 4)
| Option | Rule | Cost | Recommendation |
| --- | --- | --- | --- |
| Hold position | a `stance` column; TARGETING never chases for a stance-1 row | `STANCE` 9; twin and kernel edit and lockstep (~120 C++), ~150 sim, ~120 UI; a layout bump | first of the later updates |
| Hold fire | stance 2: no acquisition; fires only at a target the player orders | the same column and kernel edit, +~40 | with hold position |
| Patrol | `PATROL` 19: attack-move between the row's point and a target, flipping on arrival | `patrol_x`, `patrol_y` columns, ~150 sim, ~150 UI (a second point gesture) | after hold position |
| Veterancy | `xp` column; a kill credits the shooter (`proj_shooter` id); ranks at `rank_kills`; rank 1 +10 % damage, rank 2 +20 % and self-heal | ~150 sim (FIRE, PROJECTILES), ~80 view (chevrons in the bar pass), page 0 | later; it adds balance variance and rewards micro, which is hard on touch |

All four change hashed state; whichever update takes one takes its `STATE_FORMAT` bump then.

### 16. Tests (what is proven headless)
- **Sale:** refund at full, half and 1 hp; HQ and site refused; DIED flag 3; no loss counted;
  last producer sold ends the match; replay hash equal.
- **Building repair:** on, off, stop at full, no pay no mend, staggered ticks, the price formula on
  edge ints, HQ free, blackout keeps mending.
- **Repair role (the shared contract test, P241b + P277):** classes mask; slots order (share, then
  id); no double repair with `Air.run`; reach through `target_grid`; blackout stops a building;
  `REPAIR` skips unserved rows and reaches the dock point; `REPAIRED` events.
- **Medics:** heal squads only, not itself, not drone squads; seek only when idle; a moving medic
  never seeks; `ATTACK` selection gives medics `ATTACK_MOVE`.
- **Carrier:** ADR 0036's P262-P263b cases, plus eject 0 and 50 %: hp, cells, no-room deaths,
  losses, `UNLOADED` events, unit cap.
- **Mines:** lay cost, cap, footprint and passability refusals, arm delay; trigger only by enemy
  GROUND non-aware rows; blast reach and no friendly damage; air passes; rupture clears; a building
  removes; ascending order with two mines in one tick; records forget and remember; sweep; replay
  hash equal under twins and kernels.
- **Fairness (AI):** two worlds equal but for an unknown enemy mine give byte-equal AI Commands;
  the same for a loaded enemy carrier and an enemy's mend switch.
- **Perf:** counted bounds on `perf_bases` with repairers, medics and 24 mines; no new allocation
  (the existing allocation guard).
- **View and touch:** two-tap sell and its disarm; aim mode at ADR 0015's six sizes; the serve-tap
  rule; mine marks never drawn for an unknown enemy mine (a snapshot test); draw-call guard +1.
- **Mutation testing:** P271, P276, P287 and P288 (sim rows), about 10 chosen mutants each.

## Consequences
- **Gains:**
  - Michael's four items and two gaps with three new Commands and three shared with ADR 0036.
  - No kernel edit and no `STATE_FORMAT` bump of its own; version 1's part re-pins nothing.
  - One repair role serves aircraft, vehicles, squads and (by data) more later.
  - Mines follow the last-seen pattern, so the AI and the human know the same things.
- **Costs:**
  - About 3,060 production lines over three releases, 8 generated models, 3 marks, 3 glyphs.
  - About 240 page-1 rows in 1.1 and 245-490 in 1.2, competing with ADR 0036's buildings.
  - Eight more unit and building types for ADR 0031's check 4 and longer balance runs.
- **Risks:**
  - Mines could stall attacks on small maps: the cap, the cost, the detectors and the rupture
    are the counters; the balance run's match length watches it.
  - Repair could prolong fights: `repair_slots` and the price limit it.
  - Reusing `cargo` for buildings: a later feature that gives buildings cargo must move the
    switch (a comment and a test pin it).
  - Two designs share `Carry.gd`, `REPAIR` and P262: the lead merges them in the order of §2.
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
5. **Names.** A (recommended): Weld Shed, Drone Dock, Patchers, Menders, Bunk Wagon, Linecar, Shot
   Truck, Seeder, shot charge, pulse seed. Or name the ones to change.
